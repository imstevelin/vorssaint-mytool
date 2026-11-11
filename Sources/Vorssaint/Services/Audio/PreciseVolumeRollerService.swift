// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine

/// Turns coarse hardware volume wheel bursts into macOS' fine volume step.
/// Active only while enabled and Accessibility is granted.
final class PreciseVolumeRollerService: ObservableObject {
    static let shared = PreciseVolumeRollerService()

    @Published private(set) var tapFailed = false

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var gate = PreciseVolumeRollerGate()
    private var keyOwnership = PreciseVolumeKeyOwnership()
    private var notchKeyGate = NotchVolumeKeyGate()
    private var hardwareKeyGate = NotchVolumeKeyGate()
    /// Monitor volume presses this tap claimed and has not yet seen released,
    /// so their key-ups are consumed too. Main thread only: the tap runs there.
    private var monitorVolumeKeysHeld: [BrightnessSupport.VolumeKeyAction: BrightnessSupport.SpeakerTarget] = [:]
    private init() {
        SessionActivity.shared.onChange { [weak self] _ in self?.syncWithPreferences() }
    }

    func syncWithPreferences() {
        VolumeFeedbackSound.shared.prepare(active: SessionActivity.shared.isActive)
        let wanted = BrightnessService.shared.wantsMonitorVolumeKeys || BrightnessService.shared.hardwareAudioDisplayID != nil || (AppFeature.mixer.isAvailable
            && (UserDefaults.standard.bool(forKey: DefaultsKey.preciseVolumeRollerEnabled)
                || (NotchSupport.routes(.volume) && NotchService.shared.acceptsUserInteraction)))
        if SessionActivitySupport.tapShouldRun(featureWanted: wanted,
                                               accessibilityGranted: AXIsProcessTrusted(),
                                               sessionIsActive: SessionActivity.shared.isActive) {
            start()
        } else {
            stop()
        }
    }

    func suspend() {
        stop()
    }

    func stop() {
        removeTap()
        tapFailed = false
    }

    private func removeTap() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap { CFMachPortInvalidate(tap) }
        tap = nil
        source = nil
        gate.reset()
        notchKeyGate = NotchVolumeKeyGate()
        hardwareKeyGate = NotchVolumeKeyGate()
        keyOwnership = PreciseVolumeKeyOwnership()
        monitorVolumeKeysHeld = [:]
    }

    private func start() {
        guard AXIsProcessTrusted() else {
            removeTap()
            tapFailed = false
            return
        }
        if let tap, !CGEvent.tapIsEnabled(tap: tap) {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        guard tap == nil else { return }

        let systemDefined = CGEventType(rawValue: CleaningSystemKeyEvent.systemDefinedEventTypeRawValue)!
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let service = Unmanaged<PreciseVolumeRollerService>
                .fromOpaque(userInfo)
                .takeUnretainedValue()
            return service.handle(type: type, event: event)
        }
        guard let created = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << systemDefined.rawValue),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            tapFailed = true
            return
        }

        tap = created
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, created, 0)
        if let source {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
        CGEvent.tapEnable(tap: created, enable: true)
        tapFailed = false
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if SessionActivity.shared.isActive, AXIsProcessTrusted(), let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            } else {
                DispatchQueue.main.async { [weak self] in self?.syncWithPreferences() }
            }
            return Unmanaged.passUnretained(event)
        }
        guard type.rawValue == CleaningSystemKeyEvent.systemDefinedEventTypeRawValue,
              let nsEvent = NSEvent(cgEvent: event),
              nsEvent.subtype.rawValue == 8 else { return Unmanaged.passUnretained(event) }
        if PreciseVolumeKeyEvents.isPosted(event) {
            return Unmanaged.passUnretained(event)
        }
        if routeHardwareVolume(nsEvent, event: event) { return nil }
        if routeMonitorVolume(nsEvent, flags: event.flags) { return nil }
        guard AppFeature.mixer.isAvailable else { return Unmanaged.passUnretained(event) }
        if routeNotchVolume(nsEvent, event: event) { return nil }
        guard UserDefaults.standard.bool(forKey: DefaultsKey.preciseVolumeRollerEnabled),
              let volumePress = Self.volumePress(fromData1: nsEvent.data1) else {
            return Unmanaged.passUnretained(event)
        }

        if keyOwnership.leavesToSystem(
            keyCode: volumePress.keyCode, isDown: volumePress.isDown, isRepeat: volumePress.isRepeat,
            option: event.flags.contains(.maskAlternate),
            commandOrControl: !event.flags.isDisjoint(with: [.maskCommand, .maskControl])) {
            return Unmanaged.passUnretained(event)
        }

        guard volumePress.isDown else { return nil }
        guard gate.accepts(volumePress.direction, at: ProcessInfo.processInfo.systemUptime) else {
            return nil
        }
        Self.postFineStep(volumePress.keyCode)
        return nil
    }

    private func routeHardwareVolume(_ nsEvent: NSEvent, event: CGEvent) -> Bool {
        let service = BrightnessService.shared
        let code = Int32((nsEvent.data1 >> 16) & 0xffff)
        let state = (nsEvent.data1 >> 8) & 0xff
        guard let key = PreciseVolumeMediaKey(rawValue: code), key != .play else { return false }
        let id = service.hardwareAudioDisplayID
        let action = hardwareKeyGate.handle(keyCode: code, state: state,
            isRepeat: nsEvent.data1 & 1 != 0, enabled: id != nil, acceptsNewPress: id != nil,
            hasVolume: id != nil, hasMute: id != nil,
            option: event.flags.contains(.maskAlternate), shift: event.flags.contains(.maskShift),
            commandOrControl: !event.flags.isDisjoint(with: [.maskCommand, .maskControl]))
        if action == .passThrough { return false }
        if action == .consume { return true }
        guard let id else { return false }
        let outputUID = AppVolumeMixer.shared.currentOutputDeviceUID
        let wantsFeedback = NotchVolumeKeyGate.playsFeedback(
            setting: VolumeFeedbackSound.enabled,
            option: event.flags.contains(.maskAlternate), shift: event.flags.contains(.maskShift))
        let fine = UserDefaults.standard.bool(forKey: DefaultsKey.preciseVolumeRollerEnabled)
            || (event.flags.contains(.maskAlternate) && event.flags.contains(.maskShift))
        DispatchQueue.main.async {
            // A DDC route has no native volume control to fall back to. Keep
            // its failed operation in the App instead of replaying it into the
            // system HUD (or a newly selected output).
            guard service.hardwareAudioDisplayID == id,
                  outputUID == AppVolumeMixer.shared.currentOutputDeviceUID else { return }
            var rejectedImmediately = false
            let completion: (Bool) -> Void = { applied in
                if !applied { rejectedImmediately = true }
            }
            if key == .mute { service.toggleHardwareMute(for: id, completion: completion) }
            else { service.stepHardwareAudio(key == .volumeUp ? 1 : -1, fine: fine, completion: completion) }
            // DDC publishes intent synchronously; sound and the island must not
            // wait for the monitor's slow write/readback round trip.
            if !rejectedImmediately, wantsFeedback, outputUID == AppVolumeMixer.shared.currentOutputDeviceUID {
                VolumeFeedbackSound.shared.schedule(force: true)
            }
        }
        return true
    }

    /// Routes a volume press to the monitor the sound plays through, when macOS
    /// cannot set that output's volume. Every other press keeps its path. The
    /// tap only queues the change. All device I/O happens on the DDC queue.
    private func routeMonitorVolume(_ nsEvent: NSEvent, flags: CGEventFlags) -> Bool {
        guard let press = BrightnessSupport.volumeKeyEvent(
            subtype: Int(nsEvent.subtype.rawValue), data1: nsEvent.data1) else { return false }
        if !press.isKeyDown {
            return monitorVolumeKeysHeld.removeValue(forKey: press.action) != nil
        }
        let held = monitorVolumeKeysHeld[press.action]
        if !press.isRepeat { monitorVolumeKeysHeld[press.action] = nil }
        if press.isRepeat && held == nil { return false }
        guard let fine = BrightnessSupport.volumeKeyFineness(
            option: flags.contains(.maskAlternate), shift: flags.contains(.maskShift),
            commandOrControl: !flags.isDisjoint(with: [.maskCommand, .maskControl])),
              BrightnessService.shared.wantsMonitorVolumeKeys,
              let output = AppVolumeMixer.shared.monitorOutput,
              press.action != .toggleMute || output.muted != nil else {
            if !press.isRepeat {
                DispatchQueue.main.async { BrightnessService.shared.rescanForUnclaimedVolumeKey() }
            }
            return press.isRepeat && held != nil
        }
        if press.isRepeat, held != output.target || press.action == .toggleMute { return true }
        monitorVolumeKeysHeld[press.action] = output.target
        let action = press.action
        // The precise volume setting applies to the monitor as it does to any
        // other output: wheel bursts are thinned by the same gate and each
        // accepted click takes the fine step.
        let precise = AppFeature.mixer.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.preciseVolumeRollerEnabled)
        if precise, case let .step(direction) = action,
           !gate.accepts(direction > 0 ? .up : .down, at: ProcessInfo.processInfo.systemUptime) {
            return true
        }
        let target = output.target
        DispatchQueue.main.async {
            guard let current = AppVolumeMixer.shared.monitorOutput, current.target == target else { return }
            let expected: Double?
            switch action {
            case let .step(direction):
                expected = BrightnessService.shared.monitorVolumeKeySettings.requestedLevel(
                    from: current.muted == true ? 0 : current.volume,
                    direction: direction, fine: fine || precise)
            case .toggleMute:
                expected = current.muted == true ? current.volume : 0
            }
            Self.applyMonitorVolumeKey(action, target: target, fine: fine || precise)
            if NotchVolumeKeyGate.playsFeedback(
                setting: VolumeFeedbackSound.enabled,
                option: flags.contains(.maskAlternate), shift: flags.contains(.maskShift)),
               AppVolumeMixer.shared.monitorOutput?.target == target {
                VolumeFeedbackSound.shared.schedule(force: true, volume: expected, muted: expected.map { $0 <= 0 })
            }
        }
        return true
    }

    /// Applies a press that routeMonitorVolume claimed. Main thread only, where
    /// the mixer's monitor output and its request path live.
    private static func applyMonitorVolumeKey(_ action: BrightnessSupport.VolumeKeyAction,
                                              target: BrightnessSupport.SpeakerTarget, fine: Bool) {
        let mixer = AppVolumeMixer.shared
        guard mixer.monitorOutput?.target == target else { return }
        func feedback(_ result: AppVolumeMixer.OutputKeyResult) {
            guard result == .applied, mixer.monitorOutput?.target == target else { return }
            Self.showMonitorFeedback()
        }
        switch action {
        case let .step(direction):
            let settings = BrightnessService.shared.monitorVolumeKeySettings
            mixer.requestOutputStep(level: {
                settings.requestedLevel(from: $0, direction: direction, fine: fine)
            }, raises: direction > 0, completion: feedback)
        case .toggleMute:
            mixer.requestOutputMuteToggle(completion: feedback)
        }
    }

    /// Shows the monitor's level after a key moved it. The island takes the
    /// notice when it can; the brightness overlay is the fallback.
    private static func showMonitorFeedback() {
        if NotchService.shared.showCurrentVolume() { return }
        guard let output = AppVolumeMixer.shared.monitorOutput else { return }
        BrightnessOSD.show(displayID: output.target.displayID, level: output.volume,
                           kind: output.muted == true ? .mutedVolume : .volume)
    }

    private func routeNotchVolume(_ nsEvent: NSEvent, event: CGEvent) -> Bool {
        let code = Int32((nsEvent.data1 >> 16) & 0xffff)
        let state = (nsEvent.data1 >> 8) & 0xff
        guard let key = PreciseVolumeMediaKey(rawValue: code), key != .play else { return false }
        let mixer = AppVolumeMixer.shared
        let action = notchKeyGate.handle(
            keyCode: code, state: state, isRepeat: nsEvent.data1 & 1 != 0,
            enabled: NotchSupport.routes(.volume) && NotchService.shared.acceptsUserInteraction,
            acceptsNewPress: NotchService.shared.acceptsUserInteraction,
            hasVolume: mixer.systemOutputVolume != nil && !mixer.outputIsMonitorSpeakers,
            hasMute: mixer.systemOutputMuted != nil && !mixer.outputIsMonitorSpeakers,
            option: event.flags.contains(.maskAlternate), shift: event.flags.contains(.maskShift),
            commandOrControl: event.flags.contains(.maskCommand) || event.flags.contains(.maskControl))
        if action == .passThrough { return false }
        if action == .consume { return true }
        let precise = UserDefaults.standard.bool(forKey: DefaultsKey.preciseVolumeRollerEnabled)
        if precise, let direction = key.rollerDirection,
           !gate.accepts(direction, at: ProcessInfo.processInfo.systemUptime) { return true }
        let outputUID = AppVolumeMixer.shared.currentOutputDeviceUID
        let wantsFeedback = NotchVolumeKeyGate.playsFeedback(
            setting: VolumeFeedbackSound.enabled,
            option: event.flags.contains(.maskAlternate), shift: event.flags.contains(.maskShift))
        let fine = precise || (event.flags.contains(.maskAlternate) && event.flags.contains(.maskShift))
        let fallback = event.copy()
        // CoreAudio can wait for a reconnecting device. Never hold the event
        // tap's reply while reading or writing the audio driver.
        DispatchQueue.main.async {
            guard outputUID == mixer.currentOutputDeviceUID, !mixer.outputIsMonitorSpeakers else { return }
            let completion: (AppVolumeMixer.OutputKeyResult) -> Void = { result in
                if result == .fallback, outputUID == mixer.currentOutputDeviceUID, let fallback {
                    if precise, key.rollerDirection != nil {
                        fallback.flags.formUnion([.maskAlternate, .maskShift])
                    }
                    fallback.setIntegerValueField(.eventSourceUserData, value: PreciseVolumeKeyEvents.postedMarker)
                    fallback.post(tap: .cgSessionEventTap)
                    Self.postForwardedRelease(code)
                }
            }
            // Audible input feedback uses the expected level immediately. HAL
            // remains authoritative for the committed level and visual correction.
            if wantsFeedback, outputUID == mixer.currentOutputDeviceUID {
                let expected = key == .mute ? mixer.systemOutputVolume : mixer.systemOutputVolume.map {
                    NotchSupport.volumeLevel(current: $0, direction: key == .volumeUp ? 1 : -1, fine: fine)
                }
                let silent = key == .mute ? !(mixer.systemOutputMuted ?? false) : expected.map { $0 <= 0 }
                VolumeFeedbackSound.shared.schedule(force: true, volume: expected, muted: silent)
            }
            // Both keys start from the device's own reading, so the island
            // shows the result once it has been applied. A native fallback
            // publishes its state through the listeners.
            if key == .mute {
                mixer.requestOutputMuteToggle { result in
                    completion(result)
                    if result == .applied { NotchService.shared.showCurrentVolume() }
                }
            } else if mixer.systemOutputVolume != nil {
                let direction = key == .volumeUp ? 1 : -1
                mixer.requestOutputStep(level: {
                    NotchSupport.volumeLevel(current: $0, direction: direction, fine: fine)
                }, completion: { result in
                    completion(result)
                    if result == .applied { NotchService.shared.showCurrentVolume() }
                })
            } else { completion(.fallback) }
        }
        return true
    }

    private static func postForwardedRelease(_ code: Int32) {
        let event = NSEvent.otherEvent(with: .systemDefined, location: .zero,
                                      modifierFlags: NSEvent.ModifierFlags(rawValue: 0xB00),
                                      timestamp: 0, windowNumber: 0, context: nil,
                                      subtype: 8, data1: Int(code << 16) | 0xB00, data2: -1)?.cgEvent
        event?.setIntegerValueField(.eventSourceUserData, value: PreciseVolumeKeyEvents.postedMarker)
        event?.post(tap: .cgSessionEventTap)
    }

    private static func volumePress(fromData1 data1: Int) -> (keyCode: Int32,
                                                             direction: PreciseVolumeRollerDirection,
                                                             isDown: Bool,
                                                             isRepeat: Bool)? {
        let keyCode = Int32((data1 >> 16) & 0xffff)
        guard let mediaKey = PreciseVolumeMediaKey(rawValue: keyCode),
              let direction = mediaKey.rollerDirection else { return nil }
        let state = (data1 >> 8) & 0xff
        return (keyCode, direction, state == 0x0a, data1 & 1 != 0)
    }

    private static func postFineStep(_ keyCode: Int32) {
        PreciseVolumeKeyEvents.fineStep(keyCode).forEach { $0.post(tap: .cghidEventTap) }
    }
}
