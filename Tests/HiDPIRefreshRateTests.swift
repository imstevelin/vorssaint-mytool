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
        let native = Profile(width: 2560, height: 1440, rate: 75, nativeOnly: true)
        let legacy = Profile(width: 2560, height: 1440, rate: 75)
        let virtual = Profile(width: 2560, height: 1440, rate: 75, nativeOnly: false)
        suite.expect(!Service.shouldTryNative(virtual, legacyPreference: true)
                     && Service.shouldTryNative(native, legacyPreference: false)
                     && Service.shouldTryNative(legacy, legacyPreference: true)
                     && !Service.shouldTryNative(legacy, legacyPreference: false),
                     "explicit method choices override the legacy preference in both directions")
        suite.expect(!Service.allowsVirtualDisplay(native) && Service.allowsVirtualDisplay(legacy),
                     "native requests never silently fall back to a virtual display; legacy profiles retain behavior")
        suite.expect(!Service.nativeConnectionAllowed(native, inMirrorSet: true)
                     && Service.nativeConnectionAllowed(native, inMirrorSet: false),
                     "native mode activation rejects an existing mirror set")
        let oldJSON = Data(#"{"width":2560,"height":1440,"rate":75}"#.utf8)
        suite.expect((try? JSONDecoder().decode(Profile.self, from: oldJSON)) == legacy,
                     "old profiles decode without an unrequested strategy migration")
        let restoredNative = try? JSONDecoder().decode(Profile.self, from: JSONEncoder().encode(native))
        suite.expect(restoredNative == native && restoredNative?.nativeOnly == true,
                     "native-only selection survives profile persistence and reconnect")
        let initial = ReconnectSignature(id: 2, mode: 1, width: 2560, height: 1440, rate: 75, color: Data([1]))
        let calibrated = ReconnectSignature(id: 2, mode: 1, width: 2560, height: 1440, rate: 75, color: Data([2]))
        let replacement = ReconnectSignature(id: 3, mode: 1, width: 2560, height: 1440, rate: 75, color: Data([2]))
        var gate = ReconnectGate()
        suite.expect(!gate.observe(initial) && !gate.observe(initial), "initial online notifications cannot auto-apply HiDPI")
        suite.expect(!gate.observe(calibrated) && !gate.observe(calibrated), "late ColorSync calibration restarts readiness")
        suite.expect(!gate.observe(nil), "missing AppKit screen or retiring host resets readiness")
        suite.expect(!gate.observe(calibrated) && !gate.observe(calibrated) && !gate.observe(calibrated)
                     && gate.observe(calibrated), "four consecutive actual mode and ICC observations permit resume")
        suite.expect(!gate.observe(replacement), "numeric display replacement cannot reuse prior readiness")
        var timeout = ReconnectGate()
        for _ in 0..<20 { _ = timeout.observe(nil) }
        suite.expect(timeout.exhausted, "unavailable display readiness has a finite retry budget")
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
        let colorPending = VerificationState(modeMatches: true, physicalRateMatches: true,
            mirrorMatches: true, virtualColorMatches: false, physicalColorMatches: true)
        suite.expect(!colorPending.valid && !colorPending.shouldReapplyMode,
                     "late source ICC must wait without reapplying the correct mode")
        suite.expect(colorPending.failures == ["source-ICC"], "diagnostics isolate source color mismatch")
        let wrongMode = VerificationState(modeMatches: false, physicalRateMatches: true,
            mirrorMatches: true, virtualColorMatches: true, physicalColorMatches: true)
        suite.expect(!wrongMode.valid && wrongMode.shouldReapplyMode,
                     "a mismatched mode on an attached mirror remains eligible for one repair")
        let wrongMirror = VerificationState(modeMatches: false, physicalRateMatches: true,
            mirrorMatches: false, virtualColorMatches: true, physicalColorMatches: true)
        suite.expect(!wrongMirror.shouldReapplyMode, "do not change a source mode when the mirror is detached")
        let wrongRate = VerificationState(modeMatches: true, physicalRateMatches: false,
            mirrorMatches: true, virtualColorMatches: true, physicalColorMatches: true)
        suite.expect(!wrongRate.valid && !wrongRate.shouldReapplyMode && wrongRate.failures == ["physical-rate"],
                     "physical refresh mismatch stays a failure without resetting a correct source mode")
        let wrongPanelColor = VerificationState(modeMatches: true, physicalRateMatches: true,
            mirrorMatches: true, virtualColorMatches: true, physicalColorMatches: false)
        suite.expect(!wrongPanelColor.valid && wrongPanelColor.failures == ["physical-ICC"],
                     "a correct source profile cannot hide a physical ICC mismatch")
        let verified = VerificationState(modeMatches: true, physicalRateMatches: true,
            mirrorMatches: true, virtualColorMatches: true, physicalColorMatches: true)
        suite.expect(verified.valid && verified.failures.isEmpty && !verified.shouldReapplyMode,
                     "all original verification requirements must pass")
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
