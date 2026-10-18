// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import CoreGraphics

/// Compiles the production profile selection against cached physical modes.
enum HiDPIRefreshRateTests {
    class Fixture {
        static let ownershipLock = NSLock()
        static var physicalSizes: [UInt32: CGSize] = [:]
        static var physicalRates: [UInt32: Double] = [:]
        struct Session { let profile: Profile }
        var sessions: [UInt32: Session] = [:]
    }
    static func run(_ suite: TestSuite) {
        suite.expect(Service.preferredRefreshRate(requested: 60, physical: 75, cached: nil) == 75,
                     "a cold-start 60 Hz fallback never overrides the live 75 Hz physical mode")
        suite.expect(Service.preferredRefreshRate(requested: 60, physical: 144, cached: 75) == 144,
                     "a new monitor's live timing takes precedence over a stale cached timing")
        suite.expect(Service.preferredRefreshRate(requested: 60, physical: 0, cached: 74.97) == 74.97,
                     "an unknown physical readback preserves the last valid fractional timing")
        suite.expect(!Service.refreshRateMatches(actual: 60, requested: 75),
                     "verification rejects a physical mirror follower silently reduced to 60 Hz")
        suite.expect(Service.refreshRateMatches(actual: 74.97, requested: 75),
                     "normal fractional panel timing is accepted")
        var stable = 0
        for _ in 0..<3 { stable = Service.stableVerificationCount(valid: true, previous: stable) }
        suite.expect(stable == 3, "one transiently correct mode cannot complete a HiDPI transition")
        stable = Service.stableVerificationCount(valid: false, previous: stable)
        suite.expect(stable == 0, "mode, mirror or ICC instability resets the consecutive verification count")
        for _ in 0..<4 { stable = Service.stableVerificationCount(valid: true, previous: stable) }
        suite.expect(stable == 4, "four consecutive valid mode and color checks complete stabilization")
        let service = Service()
        for rate in [60.0, 75, 120, 144, 59.94, 74.97, 165] {
            Service.recordPhysicalSize(2, width: 2560, height: 1440, rate: rate)
            suite.expect(service.presets(for: 2).allSatisfy { $0.rate == rate },
                         "every HiDPI resolution preserves the physical refresh rate \(rate)")
            suite.expect(service.defaultProfile(for: 2).rate == rate,
                         "the simple HiDPI switch defaults to \(rate) Hz")
            suite.expect(service.refreshRates(for: 2).contains(rate),
                         "the refresh picker represents fractional and uncommon rate \(rate)")
        }
        Service.recordPhysicalSize(3, width: 1920, height: 1080, rate: 75)
        Service.recordPhysicalSize(4, width: 2560, height: 1440, rate: 144)
        suite.expect(service.defaultProfile(for: 3).rate == 75 && service.defaultProfile(for: 4).rate == 144,
                     "each monitor retains its own rate")
        for unknown in [0.0, Double.nan, Double.infinity, 500, -1] {
            Service.recordPhysicalSize(3, width: 1920, height: 1080, rate: unknown)
            suite.expect(service.defaultProfile(for: 3).rate == 75,
                         "unknown or invalid rates never overwrite the last physical rate")
        }
        Service.recordPhysicalSize(5, width: 1920, height: 1080, rate: 0)
        suite.expect(service.defaultProfile(for: 5).rate == 60, "unknown initial rate has a valid fallback")
        let active = Profile(width: 1920, height: 1080, rate: 74.97)
        service.sessions[3] = .init(profile: active)
        suite.expect(service.defaultProfile(for: 3) == active && service.presets(for: 3).allSatisfy { $0.rate == 74.97 },
                     "an active user-selected HiDPI profile remains the current default")
        Service.recordPhysicalSize(6, width: 1080, height: 1920, rate: 75)
        suite.expect(service.presets(for: 6).first == Profile(width: 1080, height: 1920, rate: 75),
                     "portrait presets preserve geometry and refresh rate")
    }
}
