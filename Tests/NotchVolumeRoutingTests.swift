// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

private typealias ProductionNotchSupport = NotchSupport

enum NotchVolumeRoutingTests {
    typealias DispatchQueue = MixerOutputAdjustmentContract.DispatchQueue
    enum AppVolumeMixer {
        typealias OutputKeyResult = MixerOutputAdjustmentContract.Mixer.OutputKeyResult
        static var shared = MixerOutputAdjustmentContract.Mixer()
    }
    enum VolumeFeedbackSound {
        static var enabled = false
        static let shared = VolumeFeedbackSound.self
        static var plays = 0
        static var levels: [(Double?, Bool?)] = []
        static func schedule(force: Bool, volume: Double? = nil, muted: Bool? = nil) {
            plays += 1; levels.append((volume, muted))
        }
    }
    enum UserDefaults {
        static let standard = UserDefaults.self
        static var precise = false
        static func bool(forKey key: String) -> Bool {
            key == DefaultsKey.preciseVolumeRollerEnabled && precise
        }
    }
    enum AppFeature {
        case mixer
        static var mixerAvailable = true
        var isAvailable: Bool { Self.mixerAvailable }
    }
    enum NotchSupport {
        enum Module { case volume }
        static func routes(_ module: Module) -> Bool { true }
        static func volumeLevel(current: Double, direction: Int, fine: Bool) -> Double {
            ProductionNotchSupport.volumeLevel(current: current, direction: direction, fine: fine)
        }
    }
    final class NotchService {
        static let shared = NotchService()
        var acceptsUserInteraction = true
        let acceptsSystemFeedback = true
        let showsSystemFeedback = true
        var shownLevels: [Double] = []
        @discardableResult func showCurrentVolume() -> Bool {
            let mixer = AppVolumeMixer.shared
            if let level = mixer.systemOutputVolume {
                shownLevels.append(mixer.systemOutputMuted == true ? 0 : level)
                return true
            }
            return false
        }
    }
    struct NSEvent {
        struct Subtype { let rawValue = 8 }
        let subtype = Subtype()
        let data1: Int
    }
    final class CGEvent {
        var flags: CGEventFlags = []
        var marker: Int64?
        var posts = 0
        func copy() -> CGEvent? { self }
        func setIntegerValueField(_ field: CGEventField, value: Int64) { marker = value }
        func post(tap: CGEventTapLocation) { posts += 1 }
    }
    final class BrightnessService {
        static let shared = BrightnessService()
        var wantsMonitorVolumeKeys: Bool { DisplaySpeakerVolumeTests.Service.shared.wantsMonitorVolumeKeys }
        var monitorVolumeKeySettings: MonitorVolumeKeySettings { DisplaySpeakerVolumeTests.Service.shared.monitorVolumeKeySettings }
        func rescanForUnclaimedVolumeKey() { DisplaySpeakerVolumeTests.Service.shared.rescanForUnclaimedVolumeKey() }
        var hardwareAudioDisplayID: UInt32? = 2
        var writes: [String] = []
        var succeeds = true
        var deferred = false
        var completions: [(Bool) -> Void] = []
        func stepHardwareAudio(_ direction: Int, fine: Bool, completion: @escaping (Bool) -> Void) {
            writes.append("step:\(direction):\(fine)")
            if deferred { completions.append(completion) } else { completion(succeeds) }
        }
        func toggleHardwareMute(for id: UInt32, completion: (Bool) -> Void) {
            writes.append("mute:\(id)"); completion(succeeds)
        }
    }
    class State {
        var hardwareKeyGate = NotchVolumeKeyGate()
        var monitorVolumeKeysHeld: [BrightnessSupport.VolumeKeyAction: BrightnessSupport.SpeakerTarget] = [:]
        static func showMonitorFeedback() { NotchService.shared.showCurrentVolume() }
        var notchKeyGate = NotchVolumeKeyGate()
        var gate = PreciseVolumeRollerGate()
        static var forwardedReleases: [Int32] = []
        static func postForwardedRelease(_ code: Int32) { forwardedReleases.append(code) }

    }

    static func run(_ suite: TestSuite) {
        typealias Hardware = MixerOutputAdjustmentContract.Hardware
        func reset() -> Service {
            DispatchQueue.main = MixerOutputAdjustmentContract.Queue()
            Hardware.reset()
            UserDefaults.precise = false
            Hardware.volume = 0.5
            AppVolumeMixer.shared = MixerOutputAdjustmentContract.Mixer()
            AppVolumeMixer.shared.selectOutput(1, volume: 0.5, muted: false)
            VolumeFeedbackSound.enabled = false; VolumeFeedbackSound.plays = 0; VolumeFeedbackSound.levels = []
            BrightnessService.shared.deferred = false; BrightnessService.shared.completions = []
            Service.forwardedReleases = []
            NotchService.shared.shownLevels = []
            return Service()
        }
        func drain() {
            let mixer = AppVolumeMixer.shared
            while !DispatchQueue.main.jobs.isEmpty || !mixer.halQueue.jobs.isEmpty {
                if !DispatchQueue.main.jobs.isEmpty { DispatchQueue.main.runOne() }
                if !mixer.halQueue.jobs.isEmpty { mixer.halQueue.runOne() }
            }
        }
        func press(_ key: PreciseVolumeMediaKey, service: Service, event: CGEvent) -> Bool {
            service.routeNotchVolume(NSEvent(data1: Int(key.rawValue) << 16 | 0x0a00), event: event)
        }

        let hardware = BrightnessService.shared
        for key in [PreciseVolumeMediaKey.volumeUp, .volumeDown, .mute] {
            let host = reset()
            hardware.hardwareAudioDisplayID = 2; hardware.writes = []; hardware.succeeds = true
            let event = CGEvent()
            suite.expect(host.routeHardwareVolume(NSEvent(data1: Int(key.rawValue) << 16 | 0x0a00), event: event),
                         "native monitor volume/mute down is consumed without manual binding")
            drain()
            let expected = key == .mute ? "mute:2" : "step:\(key == .volumeUp ? 1 : -1):false"
            suite.expect(hardware.writes == [expected] && event.posts == 0,
                         "the production media-key callback sends the expected DDC operation")
            suite.expect(host.routeHardwareVolume(NSEvent(data1: Int(key.rawValue) << 16 | 0x0b00), event: event),
                         "a consumed monitor key also consumes its release")
        }
        let audible = reset()
        VolumeFeedbackSound.enabled = true
        hardware.hardwareAudioDisplayID = 2; hardware.succeeds = true
        let audibleEvent = CGEvent()
        _ = audible.routeHardwareVolume(NSEvent(data1: 0x0a00), event: audibleEvent)
        suite.expect(VolumeFeedbackSound.plays == 0, "DDC feedback waits for asynchronous acceptance")
        _ = audible.routeHardwareVolume(NSEvent(data1: 0x0b00), event: audibleEvent)
        suite.expect(VolumeFeedbackSound.plays == 0, "release does not add a separate click before acceptance")
        drain()
        suite.expect(VolumeFeedbackSound.plays == 1, "successful DDC adjustment plays exactly once")
        let switchedSound = reset()
        VolumeFeedbackSound.enabled = true
        let switchedEvent = CGEvent()
        _ = switchedSound.routeHardwareVolume(NSEvent(data1: 0x0a00), event: switchedEvent)
        drain()
        AppVolumeMixer.shared.selectOutput(2, volume: 0.3, muted: false)
        _ = switchedSound.routeHardwareVolume(NSEvent(data1: 0x0b00), event: switchedEvent)
        suite.expect(VolumeFeedbackSound.plays == 1,
                     "releasing a completed key does not add another click on the newly selected output")
        let burst = reset()
        VolumeFeedbackSound.enabled = true
        hardware.deferred = true; hardware.succeeds = true
        for _ in 0..<5 {
            let event = CGEvent()
            _ = burst.routeHardwareVolume(NSEvent(data1: 0x0a00), event: event)
            _ = burst.routeHardwareVolume(NSEvent(data1: 0x0b00), event: event)
        }
        drain()
        suite.expect(VolumeFeedbackSound.plays == 5 && hardware.completions.count == 5,
                     "five rapid taps feed back before any slow DDC write finishes")
        for completion in hardware.completions.reversed() { completion(true) }
        suite.expect(VolumeFeedbackSound.plays == 5,
                     "out-of-order DDC completions cannot replay feedback or build a delayed sound backlog")
        let nativeBurst = reset()
        VolumeFeedbackSound.enabled = true
        for _ in 0..<5 {
            let event = CGEvent()
            _ = press(.volumeUp, service: nativeBurst, event: event)
            _ = nativeBurst.routeNotchVolume(NSEvent(data1: 0x0b00), event: event)
        }
        drain()
        suite.expect(VolumeFeedbackSound.plays == 5,
                     "five native audio taps each produce feedback instead of overwriting the previous request")
        let held = reset()
        VolumeFeedbackSound.enabled = true
        let heldEvent = CGEvent()
        _ = held.routeHardwareVolume(NSEvent(data1: 0x0a00), event: heldEvent)
        for _ in 0..<3 { _ = held.routeHardwareVolume(NSEvent(data1: 0x0a01), event: heldEvent) }
        drain()
        suite.expect(VolumeFeedbackSound.plays == 4,
                     "holding a volume key feeds back on every accepted repeat before release")
        let failedSound = reset()
        VolumeFeedbackSound.enabled = true; hardware.succeeds = false
        let failedSoundEvent = CGEvent()
        _ = failedSound.routeHardwareVolume(NSEvent(data1: 0x0a00), event: failedSoundEvent)
        _ = failedSound.routeHardwareVolume(NSEvent(data1: 0x0b00), event: failedSoundEvent)
        drain()
        suite.expect(VolumeFeedbackSound.plays == 0 && failedSoundEvent.posts == 0,
                     "failed DDC adjustment adds neither feedback nor a native system event")
        let failedHost = reset(); hardware.succeeds = false
        let failedEvent = CGEvent()
        _ = failedHost.routeHardwareVolume(NSEvent(data1: Int(PreciseVolumeMediaKey.volumeUp.rawValue) << 16 | 0x0a00), event: failedEvent)
        drain()
        suite.expect(failedEvent.posts == 0 && failedEvent.marker == nil,
                     "a failed owned DDC command never replays an unsupported system volume key")
        let switchedHardware = reset()
        hardware.hardwareAudioDisplayID = 2; hardware.writes = []; hardware.succeeds = true
        let switchedHardwareEvent = CGEvent()
        _ = switchedHardware.routeHardwareVolume(NSEvent(data1: 0x0a00), event: switchedHardwareEvent)
        AppVolumeMixer.shared.selectOutput(2, volume: 0.3, muted: false)
        drain()
        suite.expect(hardware.writes.isEmpty && switchedHardwareEvent.posts == 0,
                     "a queued monitor key cannot write or replay into a replacement audio output")
        let switchedNative = reset()
        let switchedNativeEvent = CGEvent()
        _ = press(.volumeUp, service: switchedNative, event: switchedNativeEvent)
        AppVolumeMixer.shared.selectOutput(2, volume: 0.3, muted: false)
        drain()
        suite.expect(Hardware.writes.isEmpty && switchedNativeEvent.posts == 0,
                     "a queued native key cannot adjust the output selected after its keydown")
        hardware.succeeds = true; hardware.hardwareAudioDisplayID = nil
        let nativeHost = reset(); let nativeEvent = CGEvent()
        suite.expect(!nativeHost.routeHardwareVolume(NSEvent(data1: Int(PreciseVolumeMediaKey.volumeUp.rawValue) << 16 | 0x0a00), event: nativeEvent),
                     "native audio and unmatched devices keep their normal system key handling")
        hardware.hardwareAudioDisplayID = 2

        var service = reset()
        let lostMute = CGEvent()
        suite.expect(press(.mute, service: service, event: lostMute), "supported mute is accepted before dispatch")
        AppVolumeMixer.shared.systemOutputMuted = nil
        Hardware.muted = nil
        drain()
        suite.expect(Hardware.writes.isEmpty && AppVolumeMixer.shared.systemOutputVolume == 0.5,
                     "mute capability lost before dispatch must not lower or write volume (writes: \(Hardware.writes))")
        suite.expect(lostMute.posts == 1 && lostMute.marker == PreciseVolumeKeyEvents.postedMarker
                     && Service.forwardedReleases == [7],
                     "mute capability lost before dispatch forwards the native press and release")

        service = reset()
        let ordinaryMute = CGEvent()
        _ = press(.mute, service: service, event: ordinaryMute)
        drain()
        suite.expect(Hardware.writes == [.init(device: 1, volume: nil, muted: true)]
                     && AppVolumeMixer.shared.systemOutputVolume == 0.5 && ordinaryMute.posts == 0,
                     "ordinary mute preserves the stored volume")

        for key in [PreciseVolumeMediaKey.volumeUp, .volumeDown] {
            service = reset()
            let event = CGEvent()
            _ = press(key, service: service, event: event)
            drain()
            let expected: Double = key == .volumeUp ? 0.5625 : 0.4375
            suite.expect(AppVolumeMixer.shared.systemOutputVolume == expected && event.posts == 0
                         && Hardware.writes.contains { $0.volume == Float(expected) },
                         "\(key) still applies its ordinary volume step")
        }
        for initiallyMuted in [false, true] {
            service = reset()
            Hardware.muted = initiallyMuted
            Hardware.accepts = { ($0 * 100).rounded() / 100 }
            AppVolumeMixer.shared.selectOutput(1, volume: 0.5, muted: initiallyMuted)
            let roundedKey = CGEvent()
            _ = press(.volumeUp, service: service, event: roundedKey)
            drain()
            let expectedPercent = initiallyMuted ? 6.0 : 56.0
            suite.expect(Hardware.muted == false && roundedKey.posts == 0
                         && Hardware.writes.compactMap(\.volume).count == 1
                         && NotchService.shared.shownLevels.map { ($0 * 100).rounded() } == [expectedPercent],
                         "a regular output reporting whole percentages confirms its accepted level, including unmuting")
        }
        service = reset()
        Hardware.volume = 0.3
        Hardware.requiresQuantizedKeys = true
        let coarse: (Float32) -> Float32 = { value in
            let levels: [Float32] = [0, 0.05, 0.1, 0.2, 0.3, 0.45, 0.65, 1]
            return levels.min { abs($0 - value) < abs($1 - value) }!
        }
        Hardware.accepts = coarse
        Hardware.quantizes = { coarse($0) }
        AppVolumeMixer.shared.selectOutput(1, volume: 0.3, muted: false)
        Hardware.afterVolumeWrite = {
            suite.expect(abs((AppVolumeMixer.shared.systemOutputVolume ?? -1) - 0.3) < 0.0001
                         && NotchService.shared.shownLevels.isEmpty,
                         "a volume key keeps the confirmed level until its write is read back")
        }
        let coarseKey = CGEvent()
        _ = press(.volumeUp, service: service, event: coarseKey)
        drain()
        suite.expect(Hardware.volume == 0.45 && coarseKey.posts == 0
                     && Hardware.writes.compactMap(\.volume).count == 1,
                     "one intercepted key advances coarse USB volume with one write and no native replay")
        suite.expect(NotchService.shared.shownLevels.map { ($0 * 100).rounded() } == [45],
                     "the notch announces the device's accepted volume instead of the rounded-away request")

        service = reset()
        Hardware.requiresQuantizedKeys = true
        Hardware.volume = 0.3
        Hardware.muted = true
        Hardware.accepts = coarse
        Hardware.quantizes = { coarse($0) }
        AppVolumeMixer.shared.selectOutput(1, volume: 0.3, muted: true)
        let fineUnmute = CGEvent()
        fineUnmute.flags = [.maskAlternate, .maskShift]
        _ = press(.volumeUp, service: service, event: fineUnmute)
        drain()
        suite.expect(Hardware.volume == 0.05 && Hardware.muted == false && fineUnmute.posts == 0
                     && Hardware.writes.compactMap(\.volume).count == 1
                     && NotchService.shared.shownLevels.map { ($0 * 100).rounded() } == [5],
                     "one fine USB key leaves muted stored volume at the first audible step and announces it")

        service = reset()
        Hardware.accepts = { _ in 0.5 }
        let ignoredKey = CGEvent()
        _ = press(.volumeDown, service: service, event: ignoredKey)
        drain()
        suite.expect(ignoredKey.posts == 0 && Service.forwardedReleases.isEmpty
                     && Hardware.writes.compactMap(\.volume).count == 1
                     && NotchService.shared.shownLevels.isEmpty,
                     "an unconfirmed successful write is neither escalated nor replayed and shows no false confirmation")
        suite.expect(AppVolumeMixer.shared.systemOutputVolume == 0.5,
                     "an ignored key leaves the last confirmed volume published")

        service = reset()
        Hardware.requiresQuantizedKeys = true
        Hardware.supportsScalarConversion = false
        let unsupportedPlan = CGEvent()
        _ = press(.volumeUp, service: service, event: unsupportedPlan)
        drain()
        suite.expect(Hardware.writes.isEmpty && unsupportedPlan.posts == 1
                     && Service.forwardedReleases == [PreciseVolumeMediaKey.volumeUp.rawValue]
                     && NotchService.shared.shownLevels.isEmpty,
                     "an output without a safe volume plan receives native handling before any hardware write")

        service = reset()
        UserDefaults.precise = true
        Hardware.requiresQuantizedKeys = true
        Hardware.supportsScalarConversion = false
        let preciseFallback = CGEvent()
        _ = press(.volumeUp, service: service, event: preciseFallback)
        drain()
        suite.expect(Hardware.writes.isEmpty && preciseFallback.posts == 1
                     && preciseFallback.flags.contains([.maskAlternate, .maskShift])
                     && Service.forwardedReleases == [PreciseVolumeMediaKey.volumeUp.rawValue]
                     && NotchService.shared.shownLevels.isEmpty,
                     "unsupported USB native fallback preserves a precise roller's fine step with one press and release")

        service = reset()
        UserDefaults.precise = true
        let muteFallback = CGEvent()
        _ = press(.mute, service: service, event: muteFallback)
        Hardware.muted = nil
        drain()
        suite.expect(Hardware.writes.isEmpty && muteFallback.posts == 1
                     && muteFallback.flags.isDisjoint(with: [.maskAlternate, .maskShift])
                     && Service.forwardedReleases == [PreciseVolumeMediaKey.mute.rawValue],
                     "precise roller mode adds no fine-step modifiers to a native mute fallback")

        service = reset()
        Hardware.requiresQuantizedKeys = true
        let continuousConversion = CGEvent()
        _ = press(.volumeUp, service: service, event: continuousConversion)
        drain()
        suite.expect(Hardware.writes.isEmpty && continuousConversion.posts == 1
                     && Service.forwardedReleases == [PreciseVolumeMediaKey.volumeUp.rawValue]
                     && NotchService.shared.shownLevels.isEmpty,
                     "a continuous USB conversion receives native handling without treating equivalence as a hardware step")

        service = reset()
        Hardware.requiresQuantizedKeys = true
        Hardware.quantizes = { _ in
            Hardware.device = 2
            Hardware.volume = 0.2
            return nil
        }
        let replacedDuringPlanning = CGEvent()
        _ = press(.volumeUp, service: service, event: replacedDuringPlanning)
        drain()
        suite.expect(Hardware.writes.isEmpty && Hardware.volume == 0.2
                     && replacedDuringPlanning.posts == 0 && Service.forwardedReleases.isEmpty
                     && NotchService.shared.shownLevels.isEmpty,
                     "a default change that invalidates conversion consumes the old key instead of falling back on the new output")

        service = reset()
        Hardware.afterVolumeWrite = {
            Hardware.device = 2
            Hardware.volume = 0.2
        }
        let replacedOutput = CGEvent()
        _ = press(.volumeUp, service: service, event: replacedOutput)
        drain()
        suite.expect(Hardware.writes.count == 1 && Hardware.writes[0].device == 1
                     && Hardware.volume == 0.2 && replacedOutput.posts == 0
                     && Service.forwardedReleases.isEmpty && NotchService.shared.shownLevels.isEmpty,
                     "a default change during a write consumes the old key without replay, stale mute or feedback")

        service = reset()
        AppVolumeMixer.shared.systemOutputMuted = nil
        let unsupportedMute = CGEvent()
        suite.expect(!press(.mute, service: service, event: unsupportedMute)
                     && DispatchQueue.main.jobs.isEmpty && Hardware.writes.isEmpty && unsupportedMute.posts == 0,
                     "initially unsupported mute passes through without scheduling or reposting")

        service = reset()
        AppVolumeMixer.shared.monitorOutput = BrightnessSupport.MonitorSpeakerOutput(target: .init(displayID: 7, path: "port-a"), volume: 0.4, muted: nil)
        let monitorUp = CGEvent()
        suite.expect(!press(.volumeUp, service: service, event: monitorUp)
                     && monitorUp.posts == 0 && DispatchQueue.main.jobs.isEmpty && Hardware.writes.isEmpty,
                     "monitor speakers with keys off pass volume keys through to macOS")
        service = reset()
        AppVolumeMixer.shared.monitorOutput = BrightnessSupport.MonitorSpeakerOutput(target: .init(displayID: 7, path: "port-a"), volume: 0.4, muted: false)
        let monitorMute = CGEvent()
        suite.expect(!press(.mute, service: service, event: monitorMute)
                     && monitorMute.posts == 0 && DispatchQueue.main.jobs.isEmpty,
                     "monitor speakers with keys off pass mute through to macOS")

        service = reset()
        let speakers = DisplaySpeakerVolumeTests.connect(AppVolumeMixer.shared, raw: 2)
        func monitorPress(_ data: Int, flags: CGEventFlags = []) -> Bool {
            service.routeMonitorVolume(NSEvent(data1: data), flags: flags)
        }
        let fine: CGEventFlags = [.maskAlternate, .maskShift]
        suite.expect(monitorPress(0x0a00, flags: fine), "the matched display claims the fine volume key")
        speakers.finish()
        suite.expect(speakers.raw == 3 && NotchService.shared.shownLevels == [0.03],
                     "monitor feedback uses the confirmed fine level")
        speakers.selectedAudioOutput = (32, "Monitor B")
        speakers.actualDevice = 32
        speakers.audioRoutes[8] = .init(path: "port-b", fingerprint: "fixture-identity",
                                        service: NSObject(), hasNativeMute: true)
        speakers.displays.append(.init(id: 8, name: "Monitor B", audio: .init(target: .init(displayID: 8, path: "port-b"), volume: 0.4, muted: false)))
        suite.expect(monitorPress(0x0a01) && monitorPress(0x0b00), "the old hold owns its repeats and release")
        speakers.finish()
        suite.expect(speakers.writes.count == 1 && NotchService.shared.shownLevels.count == 1,
                     "a held key does not transfer writes or feedback to the new monitor")
        suite.expect(monitorPress(0x0a00, flags: fine) && monitorPress(0x0b00),
                     "a fresh press can start on the newly selected monitor")
        speakers.finish()
        suite.expect(speakers.writtenIDs == [7, 8] && NotchService.shared.shownLevels.last == 0.04,
                     "the new press and its feedback use the new selection")
        speakers.displays[0].name = "Monitor B"
        suite.expect(!monitorPress(0x0a00) && !monitorPress(0x0a01) && !monitorPress(0x0b00),
                     "identical names pass a whole press through even if only one endpoint can write")
        speakers.finish()
        speakers.displays[0].name = "Monitor A"
        speakers.selectedAudioOutput = (31, "Monitor A")
        speakers.actualDevice = 31
        AppVolumeMixer.shared.monitorOutput = speakers.monitorSpeakerOutput()
        speakers.rejectVolume = true
        suite.expect(monitorPress(0x0a00, flags: fine), "the current target can claim a new press")
        speakers.finish()
        suite.expect(NotchService.shared.shownLevels.count == 2 && Hardware.writes.isEmpty,
                     "a rejected DDC transaction never announces a new level or writes HAL")

        service = reset()
        let mutedSpeakers = DisplaySpeakerVolumeTests.connect(AppVolumeMixer.shared, raw: 0, muted: true)
        VolumeFeedbackSound.enabled = true
        for _ in 0..<5 {
            suite.expect(monitorPress(0x0a00) && monitorPress(0x0b00),
                         "each new monitor press owns its down and release")
        }
        while !DispatchQueue.main.jobs.isEmpty { DispatchQueue.main.runOne() }
        suite.expect(VolumeFeedbackSound.plays == 5 && VolumeFeedbackSound.levels.allSatisfy {
            ($0.0 ?? 0) > 0 && $0.1 == false
        }, "five monitor taps each feed back immediately, including raising a muted zero output")
        mutedSpeakers.finish()
        suite.expect(VolumeFeedbackSound.plays == 5,
                     "monitor hardware completions never replay a delayed feedback backlog")
        _ = monitorPress(0x0a00)
        AppVolumeMixer.shared.monitorOutput = nil
        while !DispatchQueue.main.jobs.isEmpty { DispatchQueue.main.runOne() }
        suite.expect(VolumeFeedbackSound.plays == 5,
                     "a queued monitor press cannot play feedback after its output is retired")

    }
}

extension MixerOutputAdjustmentContract.Mixer {
    var currentOutputDeviceUID: String? { outputControlListenerDevice.map { String($0) } }
}
