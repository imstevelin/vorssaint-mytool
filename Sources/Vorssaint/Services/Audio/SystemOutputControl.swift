// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import Combine

/// The same output control powers the island and native media keys.
/// CoreAudio has priority; a hardware display output can use DDC transparently.
final class SystemOutputControl: ObservableObject {
    static let shared = SystemOutputControl()
    let objectWillChange = ObservableObjectPublisher()
    private var subscriptions = Set<AnyCancellable>()
    private var mixer: AppVolumeMixer { .shared }
    private var displays: BrightnessService { .shared }
    private init() {
        AppVolumeMixer.shared.objectWillChange.merge(with: BrightnessService.shared.objectWillChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &subscriptions)
    }
    var volume: Double? {
        if let native = mixer.systemOutputVolume { return native }
        guard let id = displays.hardwareAudioDisplayID else { return nil }
        return displays.hardwareControls[id]?.values[.volume]?.normalized
    }
    var muted: Bool? {
        if mixer.systemOutputVolume != nil { return mixer.systemOutputMuted }
        guard let id = displays.hardwareAudioDisplayID, let state = displays.hardwareControls[id] else { return nil }
        return state.values[.mute].map { $0.current == 1 } ?? state.values[.volume].map { $0.current == 0 }
    }
    func requestAdjustment(volume: Double? = nil, muted: Bool? = nil, completion: @escaping (Bool) -> Void = { _ in }) {
        let outputUID = mixer.currentOutputDeviceUID
        let completed: (Bool) -> Void = { [weak self] applied in
            if applied, self?.mixer.currentOutputDeviceUID == outputUID,
               volume != nil || muted == false { VolumeFeedbackSound.shared.schedule() }
            completion(applied)
        }
        if mixer.systemOutputVolume != nil {
            mixer.requestOutputAdjustment(volume: volume, muted: muted, completion: completed)
            return
        }
        guard let id = displays.hardwareAudioDisplayID else { completion(false); return }
        let applyMute: (Bool) -> Void = { [weak self] applied in
            guard let self, applied else { completion(false); return }
            guard self.displays.hardwareAudioDisplayID == id else { completion(false); return }
            let desired = muted ?? (volume.map { $0 <= 0 })
            guard let desired, let current = self.muted, current != desired else { completed(true); return }
            self.displays.toggleHardwareMute(for: id, completion: completed)
        }
        if let volume { displays.setHardwareControl(.volume, value: volume, for: id, completion: applyMute) }
        else { applyMute(true) }
    }
}
