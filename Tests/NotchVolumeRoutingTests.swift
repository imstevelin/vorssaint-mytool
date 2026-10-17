// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

private typealias ProductionNotchSupport = NotchSupport

enum NotchVolumeRoutingTests {
    typealias DispatchQueue = MixerOutputAdjustmentContract.DispatchQueue
    enum AppVolumeMixer { static var shared = MixerOutputAdjustmentContract.Mixer() }
    enum VolumeFeedbackSound {
        static var enabled = false
        static let shared = VolumeFeedbackSound.self
        static var plays = 0
        static func schedule(force: Bool, volume: Double? = nil, muted: Bool? = nil) { plays += 1 }
    }
    enum UserDefaults {
        static let standard = UserDefaults.self
        static func bool(forKey key: String) -> Bool { false }
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
        let acceptsSystemFeedback = true
        let showsSystemFeedback = true
        func showCurrentVolume() {}
    }
    struct NSEvent { let data1: Int }
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
        var notchKeyGate = NotchVolumeKeyGate()
        var gate = PreciseVolumeRollerGate()
        static var forwardedReleases: [Int32] = []
        static func postForwardedRelease(_ code: Int32) { forwardedReleases.append(code) }

    }

    static func run(_ suite: TestSuite) {
        typealias Hardware = MixerOutputAdjustmentContract.Hardware
        func reset() -> Service {
            DispatchQueue.main = MixerOutputAdjustmentContract.Queue()
            Hardware.device = 1
            Hardware.volume = 0.5
            Hardware.muted = false
            Hardware.writes = []
            Hardware.succeeds = true
            Hardware.afterVolumeWrite = nil
            AppVolumeMixer.shared = MixerOutputAdjustmentContract.Mixer()
            AppVolumeMixer.shared.selectOutput(1, volume: 0.5, muted: false)
            VolumeFeedbackSound.enabled = false; VolumeFeedbackSound.plays = 0
            BrightnessService.shared.deferred = false; BrightnessService.shared.completions = []
            Service.forwardedReleases = []
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
        suite.expect(VolumeFeedbackSound.plays == 0 && failedSoundEvent.posts == 1,
                     "failed DDC adjustment adds no duplicate click before native fallback")
        let failedHost = reset(); hardware.succeeds = false
        let failedEvent = CGEvent()
        _ = failedHost.routeHardwareVolume(NSEvent(data1: Int(PreciseVolumeMediaKey.volumeUp.rawValue) << 16 | 0x0a00), event: failedEvent)
        drain()
        suite.expect(failedEvent.posts == 1 && failedEvent.marker == PreciseVolumeKeyEvents.postedMarker,
                     "failed DDC media-key operations forward a marked native event without recursion")
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
        service = reset()
        AppVolumeMixer.shared.systemOutputMuted = nil
        let unsupportedMute = CGEvent()
        suite.expect(!press(.mute, service: service, event: unsupportedMute)
                     && DispatchQueue.main.jobs.isEmpty && Hardware.writes.isEmpty && unsupportedMute.posts == 0,
                     "initially unsupported mute passes through without scheduling or reposting")
    }
}

extension MixerOutputAdjustmentContract.Mixer {
    var currentOutputDeviceUID: String? { outputControlListenerDevice.map { String($0) } }
}
