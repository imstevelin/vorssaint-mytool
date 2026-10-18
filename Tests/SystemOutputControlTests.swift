// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Combine

enum SystemOutputControlTests {
    enum Control: Hashable { case volume, mute }
    struct Value {
        var current: UInt16
        var normalized: Double { Double(current) / 100 }
    }
    struct State { var values: [Control: Value] }
    final class BrightnessService: ObservableObject {
        static let shared = BrightnessService()
        var hardwareAudioDisplayID: UInt32? = 2
        @Published var hardwareControls: [UInt32: State] = [2: State(values: [.volume: Value(current: 40), .mute: Value(current: 1)])]
        var fail = false
        func setHardwareControl(_ control: Control, value: Double, for id: UInt32, completion: @escaping (Bool) -> Void) {
            if !fail { hardwareControls[id]?.values[control] = Value(current: UInt16(value * 100)) }
            completion(!fail)
        }
        func toggleHardwareMute(for id: UInt32, completion: @escaping (Bool) -> Void) {
            let old = hardwareControls[id]?.values[.mute]?.current
            hardwareControls[id]?.values[.mute] = Value(current: old == 1 ? 2 : 1)
            completion(true)
        }
    }
    final class AppVolumeMixer: ObservableObject {
        static let shared = AppVolumeMixer()
        @Published var systemOutputVolume: Double?
        @Published var systemOutputMuted: Bool?
        var currentOutputDeviceUID: String? = "output"
        var deferred = false
        var completions: [(Bool) -> Void] = []
        var nativeWrites = 0
        func requestOutputAdjustment(volume: Double?, muted: Bool?, completion: @escaping (Bool) -> Void) {
            nativeWrites += 1
            if let volume { systemOutputVolume = volume }
            if let muted { systemOutputMuted = muted }
            if deferred { completions.append(completion) } else { completion(true) }
        }
    }
    enum VolumeFeedbackSound {
        static let shared = VolumeFeedbackSound.self
        static var scheduled = 0
        static func schedule() { scheduled += 1 }
    }
    static func run(_ suite: TestSuite) {
        VolumeFeedbackSoundTests.run(suite)
        VolumeFeedbackAudioPlayerTests.run(suite)

        let monitors: [DisplayKeyRoutingSupport.Monitor] = [
            .init(id: 2, identity: "left", name: "PA328QV"),
            .init(id: 3, identity: "right", name: "Other")
        ]
        func route(_ name: String, _ list: [DisplayKeyRoutingSupport.Monitor], native: Bool = false,
                   transport: Bool = true, binding: String? = nil) -> UInt32? {
            DisplayKeyRoutingSupport.audioDisplay(nativeVolumeAvailable: native, displayTransport: transport,
                outputName: name, explicitIdentity: binding, monitors: list)
        }
        suite.expect(route("PA328QV", monitors) == 2, "display audio matches the physical monitor without a binding")
        suite.expect(route("DisplayPort", Array(monitors.prefix(1))) == 2, "one physical monitor is selected for display audio automatically")
        suite.expect(route("DisplayPort", monitors) == nil, "ambiguous multi-monitor audio never follows the pointer")
        suite.expect(route("PA328QV", monitors, native: true) == nil, "native CoreAudio controls always have priority")
        suite.expect(route("Bluetooth speaker", Array(monitors.prefix(1)), transport: false) == nil,
                     "Bluetooth and USB audio cannot accidentally adjust the only monitor")
        suite.expect(route("Unknown", monitors, binding: "right") == 3, "an explicit override remains supported")
        suite.expect(route("Unknown", monitors, binding: "gone") == nil, "a missing manual binding cannot transfer ownership")
        let unsupported = monitors + [.init(id: 4, identity: "unsupported", name: "TV", supportsVolume: false)]
        suite.expect(route("TV", unsupported) == nil, "a display without DDC volume is not replaced by another controllable display")
        let identical = [monitors[0], DisplayKeyRoutingSupport.Monitor(id: 5, identity: "duplicate", name: "PA328QV")]
        suite.expect(route("PA328QV", identical) == nil, "identical monitor names do not establish a unique audio match")

        let output = SystemOutputControl.shared
        let mixer = AppVolumeMixer.shared
        let displays = BrightnessService.shared
        suite.expect(output.volume == 0.4 && output.muted == true, "the island sees DDC volume and mute when CoreAudio exposes neither")
        var applied = false
        output.requestAdjustment(volume: 0.3) { applied = $0 }
        suite.expect(VolumeFeedbackSound.scheduled == 1, "successful DDC slider adjustment schedules feedback once")
        suite.expect(applied && output.volume == 0.3 && output.muted == false && mixer.nativeWrites == 0,
                     "the island slider writes DDC and unmutes through the same control")
        output.requestAdjustment(muted: true) { applied = $0 }
        suite.expect(applied && output.muted == true, "the island mute button controls the monitor")
        suite.expect(VolumeFeedbackSound.scheduled == 1, "muting does not schedule an audible click")
        mixer.systemOutputVolume = 0.8; mixer.systemOutputMuted = false
        suite.expect(output.volume == 0.8 && output.muted == false, "switching to native audio hides the monitor's old state")
        output.requestAdjustment(volume: 0.6) { applied = $0 }
        suite.expect(VolumeFeedbackSound.scheduled == 2, "successful native slider adjustment schedules feedback once")
        suite.expect(applied && mixer.nativeWrites == 1 && output.volume == 0.6, "native output changes never write DDC")
        mixer.systemOutputVolume = nil; mixer.systemOutputMuted = nil
        displays.hardwareAudioDisplayID = nil
        output.requestAdjustment(volume: 0.5) { applied = $0 }
        suite.expect(!applied && output.volume == nil && output.muted == nil, "no selected route exposes no stale speaker capability")
        displays.hardwareAudioDisplayID = 2; displays.fail = true
        output.requestAdjustment(volume: 0.7) { applied = $0 }
        suite.expect(!applied && output.volume == 0.3, "failed DDC writes preserve the last confirmed volume")
        displays.fail = false
        suite.expect(VolumeFeedbackSound.scheduled == 2, "missing routes and failed DDC writes schedule no feedback")

        mixer.systemOutputVolume = 0.4; mixer.systemOutputMuted = false
        mixer.deferred = true
        output.requestAdjustment(volume: 0.2)
        output.requestAdjustment(volume: 0.3)
        mixer.completions.removeFirst()(true)
        suite.expect(VolumeFeedbackSound.scheduled == 3,
                     "each successful slider adjustment retains its own feedback")
        mixer.completions.removeFirst()(true)
        suite.expect(VolumeFeedbackSound.scheduled == 4, "the next slider completion adds another feedback click")
        output.requestAdjustment(volume: 0.2)
        mixer.currentOutputDeviceUID = "replacement"
        mixer.completions.removeFirst()(true)
        suite.expect(VolumeFeedbackSound.scheduled == 4,
                     "handled old-output completions cannot play feedback on the replacement output")
        mixer.deferred = false

        let suiteName = "com.vorssaint.tests.native-display-keys.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.register(defaults: Defaults.registeredDefaults)
        suite.expect(defaults.bool(forKey: DefaultsKey.brightnessControlEnabled)
                     && defaults.bool(forKey: DefaultsKey.brightnessKeysEnabled), "fresh installs enable native display keys by default")
        defaults.set(false, forKey: DefaultsKey.brightnessKeysEnabled)
        Defaults.enableNativeDisplayKeysOnce(in: defaults)
        suite.expect(defaults.bool(forKey: DefaultsKey.brightnessKeysEnabled), "existing installations adopt the new default once")
        defaults.set(false, forKey: DefaultsKey.brightnessKeysEnabled)
        Defaults.enableNativeDisplayKeysOnce(in: defaults)
        suite.expect(!defaults.bool(forKey: DefaultsKey.brightnessKeysEnabled), "later explicit opt-outs survive relaunch")
        defaults.removePersistentDomain(forName: suiteName)
    }
}

/// Exercise production sound scheduling without changing hardware or playing audio.
enum VolumeFeedbackSoundTests {
    final class Preferences {
        var values: [String: Bool] = [:]
        func object(forKey key: String) -> Any? { values[key] }
        func bool(forKey key: String) -> Bool { values[key] ?? false }
    }
    enum UserDefaults { static let standard = Preferences() }
    final class Queue {
        static var instances: [Queue] = []
        static var running = false
        var jobs: [() -> Void] = []
        init(label: String, qos: DispatchQoS.QoSClass) { Self.instances.append(self) }
        func async(execute work: @escaping () -> Void) { jobs.append(work) }
        static func drain() {
            for queue in instances {
                while !queue.jobs.isEmpty {
                    running = true
                    queue.jobs.removeFirst()()
                    running = false
                }
            }
        }
    }
    typealias DispatchQueue = Queue
    final class VolumeFeedbackAudioPlayer {
        static var plays = 0
        static var routes: [String?] = []
        static var lastUID: String?
        static var onlyWorker = true
        init() { Self.onlyWorker = Self.onlyWorker && Queue.running }
        func prepare(uid: String?) {
            Self.onlyWorker = Self.onlyWorker && Queue.running
            Self.routes.append(uid)
        }
        func play(uid: String) {
            Self.onlyWorker = Self.onlyWorker && Queue.running
            Self.plays += 1; Self.lastUID = uid
        }
    }
    final class AppVolumeMixer {
        static let shared = AppVolumeMixer()
        var currentOutputDeviceUID: String? = "media-output"
    }
    final class SystemOutputControl {
        static let shared = SystemOutputControl()
        var volume: Double? = 0.4
        var muted: Bool? = false
    }
    static func run(_ suite: TestSuite) {
        let prefs = UserDefaults.standard
        let output = SystemOutputControl.shared
        let sound = VolumeFeedbackSound.shared
        typealias Player = VolumeFeedbackAudioPlayer
        prefs.values = [:]
        suite.expect(!VolumeFeedbackSound.enabled, "feedback stays silent until enabled")
        prefs.values["com.apple.sound.beep.feedback"] = true
        suite.expect(VolumeFeedbackSound.enabled, "an untouched preference inherits the system choice")
        prefs.values[DefaultsKey.volumeFeedbackSoundEnabled] = false
        sound.schedule(); Queue.drain()
        suite.expect(Player.plays == 0, "explicit opt-out silences feedback")
        prefs.values[DefaultsKey.volumeFeedbackSoundEnabled] = true
        sound.prepare()
        suite.expect(Player.routes.isEmpty, "prewarming never initializes audio on the UI thread")
        Queue.drain()
        suite.expect(Player.routes.count == 1 && Player.plays == 0, "the output is prewarmed without playing a click")
        sound.schedule(); sound.schedule(); sound.schedule()
        suite.expect(Player.plays == 0 && Queue.instances[0].jobs.count == 3,
                     "three inputs enqueue three immediate worker requests with no playback or timed FIFO on main")
        Queue.drain()
        suite.expect(Player.plays == 3 && Player.lastUID == "media-output", "each rapid input reaches the current output once")
        for volume: Double? in [0, nil, .nan] {
            output.volume = volume; sound.schedule(); Queue.drain()
        }
        output.volume = 0.5; output.muted = true
        sound.schedule(); Queue.drain()
        suite.expect(Player.plays == 3, "muted and unreadable outputs remain silent")
        output.muted = false
        sound.schedule(); sound.schedule()
        AppVolumeMixer.shared.currentOutputDeviceUID = "replacement"
        sound.prepare()
        Queue.drain()
        suite.expect(Player.plays == 3 && Player.routes.last! == "replacement", "output changes discard stale queued clicks and prewarm the replacement")
        sound.schedule()
        prefs.values[DefaultsKey.volumeFeedbackSoundEnabled] = false
        sound.prepare()
        Queue.drain()
        suite.expect(Player.plays == 3 && Player.routes.last! == nil, "disabling feedback stops the engine and discards queued clicks")
        output.volume = 0; output.muted = true
        sound.schedule(force: true, volume: 0.1, muted: false)
        Queue.drain()
        suite.expect(Player.plays == 4, "key preview can unmute and sound immediately before slow hardware confirmation")
        suite.expect(Player.onlyWorker, "audio initialization, preparation and playback all stay off main")
        suite.expect(SettingsBackupSupport.exportKeys().contains(DefaultsKey.volumeFeedbackSoundEnabled), "the preference remains backed up")
    }
}

/// Execute the production player state machine without touching an audio device.
enum VolumeFeedbackAudioPlayerTests {
    typealias AVAudioFrameCount = UInt32
    final class AVAudioFile {
        let processingFormat = 1
        let length = 1
        init(forReading url: URL) throws { }
        func read(into buffer: AVAudioPCMBuffer) throws { }
    }
    final class AVAudioPCMBuffer { init?(pcmFormat: Int, frameCapacity: UInt32) { } }
    final class AVAudioEngine {
        static var latest: AVAudioEngine?
        var running = false
        init() { Self.latest = self }
    }
    final class AVAudioPlayerNode { var playing = false }
    static var starts = 0, clicks = 0, stops = 0
    static var startFails = false, scheduleFails = false
    static func VSDAudioFeedbackReady(_ engine: AVAudioEngine, _ node: AVAudioPlayerNode) -> Bool {
        engine.running && node.playing
    }
    static func VSDAudioFeedbackStart(_ engine: AVAudioEngine, _ node: AVAudioPlayerNode, _ buffer: AVAudioPCMBuffer) -> Bool {
        starts += 1
        guard !startFails else { return false }
        engine.running = true; node.playing = true; return true
    }
    static func VSDAudioFeedbackStop(_ engine: AVAudioEngine) { stops += 1; engine.running = false }
    static func VSDAudioFeedbackSchedule(_ engine: AVAudioEngine, _ node: AVAudioPlayerNode, _ buffer: AVAudioPCMBuffer) -> Bool {
        guard !scheduleFails, VSDAudioFeedbackReady(engine, node) else { return false }
        clicks += 1; return true
    }
    static func run(_ suite: TestSuite) {
        let player = VolumeFeedbackAudioPlayer()
        startFails = true
        player.prepare(uid: "hdmi")
        suite.expect(starts == 1 && clicks == 0, "an unavailable route does not mark a feedback player ready")
        startFails = false
        player.play(uid: "hdmi")
        suite.expect(starts == 2 && clicks == 1, "the same output UID retries after a transient start failure")
        for _ in 0..<8 { player.play(uid: "hdmi") }
        suite.expect(starts == 2 && clicks == 9, "rapid accepted taps each schedule without restarting a healthy engine")
        AVAudioEngine.latest?.running = false
        player.play(uid: "hdmi")
        suite.expect(starts == 3 && clicks == 10, "a hardware configuration change rebuilds even with an unchanged UID")
        scheduleFails = true
        player.play(uid: "hdmi")
        suite.expect(clicks == 10 && AVAudioEngine.latest?.running == false, "a schedule failure invalidates the stopped player")
        scheduleFails = false
        player.play(uid: "hdmi")
        suite.expect(starts == 4 && clicks == 11, "the next tap recovers after a device disappears during scheduling")
        player.prepare(uid: nil)
        suite.expect(AVAudioEngine.latest?.running == false, "disabling feedback releases the active output engine")
    }
}
