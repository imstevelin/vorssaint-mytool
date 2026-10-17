// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import CoreGraphics

/// Production request/feedback methods, with slow DDC and queues advanced by the test.
enum DisplayAudioBurstTests {
    final class Queue {
        var jobs: [() -> Void] = []
        func async(execute job: @escaping () -> Void) { jobs.append(job) }
        func asyncAfter(deadline: DispatchTime, execute job: DispatchWorkItem) {
            jobs.append { if !job.isCancelled { job.perform() } }
        }
        func drain() { while !jobs.isEmpty { jobs.removeFirst()() } }
    }
    enum DispatchQueue { static let main = Queue() }
    enum DisplayControlText { static let failed = "failed" }
    static func CGDisplayIsOnline(_ id: UInt32) -> UInt32 { 1 }
    final class NotchService {
        static let shared = NotchService()
        var levels: [Double] = []
        func showVolume(_ volume: Double, muted: Bool) -> Bool {
            levels.append(muted ? 0 : volume); return true
        }
    }
    enum BrightnessOSD {
        static func showVolume(displayID: UInt32, volume: Double, muted: Bool) {}
    }
    class Fixture {
        let stateLock = NSLock()
        let workQueue = Queue()
        var hardwareControls: [UInt32: DisplayHardwareState] = [:]
        var hardwareRoutes: [UInt32: HardwareRoute] = [:]
        var hardwareRequests: [String: DispatchWorkItem] = [:]
        var hardwareRevision: [String: UInt64] = [:]
        var hardwareConfirmed: [String: DisplayHardwareValue] = [:]
        var hardwareSequence: UInt64 = 0
        var hardwareAudioDisplayID: UInt32? = 2
        var writes: [UInt16] = []
        var fail = false
        var deviceVolume: UInt16 = 20
        var deviceMute: UInt16 = 2
        static func displayFingerprint(_ id: UInt32) -> String { "monitor" }
        func ddcSend(to id: UInt32, service: CFTypeRef, packet: [UInt8]) -> Bool {
            let value = UInt16(packet[3]) << 8 | UInt16(packet[4])
            writes.append(value)
            if !fail {
                if packet[2] == 0x62 { deviceVolume = value } else { deviceMute = value }
            }
            return !fail
        }
        func ddcReadControl(_ code: UInt8, for id: UInt32, service: CFTypeRef) -> DisplayHardwareValue? {
            .init(current: code == 0x62 ? deviceVolume : deviceMute, maximum: code == 0x62 ? 100 : 2)
        }
    }
    static func make() -> Service {
        DispatchQueue.main.jobs = []
        NotchService.shared.levels = []
        let service = Service()
        service.hardwareRoutes[2] = .init(service: "monitor" as CFString, identity: "monitor", fingerprint: "monitor")
        service.hardwareControls[2] = .init(identity: "monitor", values: [
            .volume: .init(current: 20, maximum: 100), .mute: .init(current: 2, maximum: 2)])
        return service
    }
    static func run(_ suite: TestSuite) {
        let service = make()
        for _ in 0..<5 { service.stepHardwareAudio(1, fine: false) { _ in }; DispatchQueue.main.drain() }
        suite.expect(NotchService.shared.levels.map { Int(($0 * 100).rounded()) } == [26,32,38,44,50],
                     "each rapid volume press updates the island before any slow hardware write")
        suite.expect(service.writes.isEmpty, "feedback never waits for a DDC transaction")
        service.workQueue.drain(); DispatchQueue.main.drain()
        suite.expect(service.writes == [50] && service.deviceVolume == 50,
                     "queued obsolete writes are skipped and the latest target reaches the monitor")
        suite.expect(NotchService.shared.levels.count == 5, "successful readback does not replay delayed notices")

        let stale = make()
        stale.stepHardwareAudio(1, fine: false) { _ in }; DispatchQueue.main.drain()
        stale.workQueue.drain() // Readback queued, but not yet delivered.
        stale.stepHardwareAudio(1, fine: false) { _ in }
        DispatchQueue.main.drain()
        suite.expect(stale.hardwareControls[2]?.values[.volume]?.current == 32,
                     "an older readback cannot overwrite newer input")
        stale.workQueue.drain(); DispatchQueue.main.drain()
        suite.expect(NotchService.shared.levels == [0.26, 0.32], "old completion never jumps the island backwards")

        let lateFailure = make()
        lateFailure.stepHardwareAudio(1, fine: false) { _ in }; DispatchQueue.main.drain()
        lateFailure.workQueue.drain()
        lateFailure.stepHardwareAudio(1, fine: false) { _ in }; DispatchQueue.main.drain()
        lateFailure.fail = true; lateFailure.workQueue.drain(); DispatchQueue.main.drain()
        suite.expect(lateFailure.hardwareControls[2]?.values[.volume]?.current == 26,
                     "rollback uses the most recent confirmed in-flight write")

        let obsoleteFailure = make()
        var obsoleteResult: Bool?
        obsoleteFailure.stepHardwareAudio(1, fine: false) { obsoleteResult = $0 }
        DispatchQueue.main.drain(); obsoleteFailure.fail = true; obsoleteFailure.workQueue.drain()
        obsoleteFailure.fail = false
        obsoleteFailure.stepHardwareAudio(1, fine: false) { _ in }; DispatchQueue.main.drain()
        suite.expect(obsoleteResult == true, "superseded failure cannot trigger a native volume fallback")
        obsoleteFailure.workQueue.drain(); DispatchQueue.main.drain()

        let failure = make()
        failure.stepHardwareAudio(1, fine: false) { _ in }; DispatchQueue.main.drain()
        failure.stepHardwareAudio(1, fine: false) { _ in }; DispatchQueue.main.drain()
        failure.fail = true; failure.workQueue.drain(); DispatchQueue.main.drain()
        suite.expect(failure.hardwareControls[2]?.values[.volume]?.current == 20
                     && NotchService.shared.levels.last == 0.2,
                     "failed burst restores the confirmed volume rather than an unconfirmed intermediate value")

        let muted = make()
        muted.hardwareControls[2]?.values[.mute]?.current = 1
        muted.deviceMute = 1
        muted.stepHardwareAudio(1, fine: false) { _ in }
        suite.expect(NotchService.shared.levels == [0.26], "volume up immediately presents unmute intent")
        DispatchQueue.main.drain(); muted.workQueue.drain(); DispatchQueue.main.drain()
        suite.expect(muted.deviceMute == 2 && muted.deviceVolume == 26, "unmute and volume both reach the monitor")
    }
}
