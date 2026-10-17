// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Pure routing policy: default display audio follows the current audio output,
/// never the mouse. Ambiguous multi-monitor matches stay with the system.
enum DisplayKeyRoutingSupport {
    struct Monitor {
        let id: UInt32
        let identity: String
        let name: String
        var supportsVolume = true
    }
    static func audioDisplay(nativeVolumeAvailable: Bool, displayTransport: Bool,
                             outputName: String, explicitIdentity: String?, monitors: [Monitor]) -> UInt32? {
        guard !nativeVolumeAvailable else { return nil }
        if let explicitIdentity {
            let matches = monitors.filter { $0.identity == explicitIdentity }
            return matches.count == 1 && matches[0].supportsVolume ? matches[0].id : nil
        }
        guard displayTransport else { return nil }
        func normalized(_ value: String) -> String {
            value.lowercased().unicodeScalars.filter(CharacterSet.alphanumerics.contains).map(String.init).joined()
        }
        let name = normalized(outputName)
        let named = monitors.filter { !name.isEmpty && normalized($0.name) == name }
        if named.count == 1 { return named[0].supportsVolume ? named[0].id : nil }
        if monitors.count == 1, monitors[0].supportsVolume { return monitors[0].id }
        return nil
    }
}
