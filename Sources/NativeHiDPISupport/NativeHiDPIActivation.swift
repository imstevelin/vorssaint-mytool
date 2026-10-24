// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
#if canImport(DisplayRecoverySupport)
import DisplayRecoverySupport
#endif

/// Persist only an explicit user request, never an automatically inferred mode.
struct NativeHiDPIActivation: Codable, Equatable {
    let uuid: String
    let vendor: UInt32
    let product: UInt32
    var width: Int
    var height: Int
    let rate: Double
    var prepared = false
    var panel: NativeHiDPIOverride.PanelSize? = nil
    var useAvailableDefault: Bool? = nil
    func matches(uuid: String?, vendor: UInt32, product: UInt32) -> Bool {
        self.uuid == uuid && self.vendor == vendor && self.product == product
    }
    var valid: Bool {
        UUID(uuidString: uuid) != nil
            && NativeHiDPIOverride.Identity(vendor: vendor, product: product).valid
            && NativeDisplayModes.validRequest(width: width, height: height, rate: rate)
            && panel?.valid != false
    }
    enum Step { case enable, prepare, waitForDisplay }
    func next(modeAvailable: Bool) -> Step {
        if modeAvailable && (panel == nil || prepared) { return .enable }
        return prepared ? .waitForDisplay : .prepare
    }
}
