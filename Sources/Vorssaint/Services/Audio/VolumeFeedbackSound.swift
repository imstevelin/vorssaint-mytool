// SPDX-License-Identifier: GPL-3.0-or-later
import AVFAudio
import Foundation

/// Input/UI only snapshots state. Audio preparation and playback never run on main.
final class VolumeFeedbackSound {
    static let shared = VolumeFeedbackSound()
    static var enabled: Bool {
        UserDefaults.standard.object(forKey: DefaultsKey.volumeFeedbackSoundEnabled) as? Bool
            ?? UserDefaults.standard.bool(forKey: "com.apple.sound.beep.feedback")
    }
    private let audioQueue = DispatchQueue(label: "com.imstevelin.volume-feedback", qos: .userInteractive)
    private let stateLock = NSLock()
    private var routeUID: String?
    private lazy var player = VolumeFeedbackAudioPlayer()

    /// Called during output/session changes, before the first key needs sound.
    func prepare(active: Bool = true) {
        selectRoute(active && Self.enabled ? AppVolumeMixer.shared.currentOutputDeviceUID : nil)
    }

    private func selectRoute(_ uid: String?) {
        stateLock.lock()
        let changed = routeUID != uid
        routeUID = uid
        stateLock.unlock()
        guard changed else { return }
        audioQueue.async { [weak self] in
            guard let self, self.isCurrentRoute(uid) else { return }
            self.player.prepare(uid: uid)
        }
    }

    private func isCurrentRoute(_ uid: String?) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return routeUID == uid
    }

    /// One immediate request per input. No debounce, timer or hardware-readback wait.
    func schedule(force: Bool = false, volume: Double? = nil, muted: Bool? = nil) {
        guard force || Self.enabled,
              let level = volume ?? SystemOutputControl.shared.volume,
              level.isFinite, level > 0,
              (muted ?? SystemOutputControl.shared.muted) != true,
              let uid = AppVolumeMixer.shared.currentOutputDeviceUID else { return }
        selectRoute(uid)
        audioQueue.async { [weak self] in
            guard let self, self.isCurrentRoute(uid) else { return }
            self.player.play(uid: uid)
        }
    }
}

/// Keep the render engine running between clicks. Restart only the buffer, so
/// each tap gets a new attack without reopening the output device or blocking UI.
final class VolumeFeedbackAudioPlayer {
    private var engine: AVAudioEngine?
    private var node: AVAudioPlayerNode?
    private var buffer: AVAudioPCMBuffer?
    private var routeUID: String?

    func prepare(uid: String?) {
        if let uid, uid == routeUID, engine?.isRunning == true { return }
        engine?.stop()
        engine = nil; node = nil; routeUID = nil
        guard let uid else { return }
        do {
            if buffer == nil {
                let file = try AVAudioFile(forReading: URL(fileURLWithPath:
                    "/System/Library/LoginPlugins/BezelServices.loginPlugin/Contents/Resources/volume.aiff"))
                guard let pcm = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                frameCapacity: AVAudioFrameCount(file.length)) else { return }
                try file.read(into: pcm)
                buffer = pcm
            }
            guard let buffer else { return }
            let engine = AVAudioEngine()
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: buffer.format)
            node.volume = 1 // Output gain (native or physical DDC) sets the loudness once.
            engine.prepare()
            try engine.start() // Uses the current system media output, never the alert output.
            node.play()
            self.engine = engine; self.node = node; routeUID = uid
        } catch {
            engine = nil; node = nil; routeUID = nil
        }
    }

    func play(uid: String) {
        prepare(uid: uid)
        guard let node, let buffer, engine?.isRunning == true else { return }
        node.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
    }
}
