// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import CoreGraphics

enum DisplayColorPipelineTests {
    static var profile: Data?
    static var effective: Data?
    struct Space { func copyICCData() -> CFData? { effective as CFData? } }
    static func CGDisplayCopyColorSpace(_ id: UInt32) -> Space { Space() }
    enum Checker {
        static func data(for id: UInt32) -> Data? { profile }
        static func CGDisplayCopyColorSpace(_ id: UInt32) -> Space { Space() }
    }
    static func run(_ suite: TestSuite) {
        let physical = Data([1, 2, 3, 4])
        profile = physical; effective = physical
        suite.expect(Checker.matches(physical, display: 2), "ICC verification requires matching ColorSync and WindowServer profiles")
        effective = Data([1,2,3,5])
        suite.expect(!Checker.matches(physical, display: 2), "pending WindowServer profile propagation cannot pass verification")
        profile = Data([1,2,3,5]); effective = physical
        suite.expect(!Checker.matches(physical, display: 2), "a substituted ColorSync profile cannot pass verification")
        profile = nil
        suite.expect(!Checker.matches(physical, display: 2), "unreadable ICC fails verification instead of substituting sRGB")
        profile = physical; effective = nil
        suite.expect(!Checker.matches(physical, display: 2), "unreadable effective color space fails verification")
        let request = VirtualDisplayHostRequest(parentPID: 1, width: 2560, height: 1440,
            rate: 75, serial: 2, name: "HiDPI", colorProfile: physical)
        let decoded = try? JSONDecoder().decode(VirtualDisplayHostRequest.self, from: JSONEncoder().encode(request))
        suite.expect(decoded?.colorProfile == physical && decoded?.rate == 75,
                     "the child host receives the exact ICC bytes and requested refresh rate")
    }
}
