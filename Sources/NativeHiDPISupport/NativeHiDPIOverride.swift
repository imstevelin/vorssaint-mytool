// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Display override data, independent of virtual screens and mirror state.
/// Resolution records use network-order UInt32 words, not host endianness.
enum NativeHiDPIOverride {
    struct Identity: Codable, Equatable {
        let vendor: UInt32
        let product: UInt32
        var valid: Bool { vendor > 0 && vendor <= 0xffff && product > 0 && product <= 0xffff }
        var relativePath: String { "DisplayVendorID-\(String(vendor, radix: 16))/DisplayProductID-\(String(product, radix: 16))" }
    }
    struct Size: Codable, Equatable {
        let width: Int
        let height: Int
        var valid: Bool {
            width >= 640 && height >= 480 && width <= 3072 && height <= 3072
                && width * height <= 9_437_184
        }
    }
    enum Failure: Error, LocalizedError {
        case invalid, conflict, unsafePath
        var errorDescription: String? {
            switch self {
            case .invalid: return "Invalid native HiDPI display configuration"
            case .conflict: return "Display override was changed by another tool; restore cancelled"
            case .unsafePath: return "Display override path is not a regular protected system path"
            }
        }
    }
    struct Receipt: Codable {
        let original: Data?
        let installed: Data
        let previous: Data?
        func accepts(_ current: Data?) -> Bool {
            current == installed || current == original || current == previous
        }
    }
    struct ResolutionPreference: Codable {
        let original: Bool?
        func accepts(_ current: Bool?) -> Bool { current == true || current == original }
    }
    static func words(_ values: [UInt32]) -> Data {
        var result = Data()
        for value in values {
            var big = value.bigEndian
            withUnsafeBytes(of: &big) { result.append(contentsOf: $0) }
        }
        return result
    }
    static func configuration(identity: Identity, sizes: [Size], existing: Data?) throws -> Data {
        guard identity.valid, !sizes.isEmpty, sizes.count <= 32, sizes.allSatisfy(\.valid) else { throw Failure.invalid }
        var dictionary: [String: Any] = [:]
        if let existing {
            guard existing.count <= 4 * 1024 * 1024,
                  let parsed = try PropertyListSerialization.propertyList(from: existing, format: nil) as? [String: Any],
                  (parsed["DisplayVendorID"] as? NSNumber)?.uint32Value == identity.vendor,
                  (parsed["DisplayProductID"] as? NSNumber)?.uint32Value == identity.product else { throw Failure.invalid }
            dictionary = parsed
        }
        dictionary["DisplayVendorID"] = identity.vendor
        dictionary["DisplayProductID"] = identity.product
        // Preserve EDID, color metadata, native dimensions, names and all other
        // installed model overrides. Request only additional scaled modes.
        var resolutions = dictionary["scale-resolutions"] as? [Data] ?? []
        if dictionary["scale-resolutions"] != nil && dictionary["scale-resolutions"] as? [Data] == nil { throw Failure.invalid }
        for size in sizes {
            let width = UInt32(size.width), height = UInt32(size.height)
            // The HiDPI record and its two plain-size dependencies are a set.
            // Do not add ValidForHiRes (0x00800000) to the mirror-valid flag.
            let entries = [words([width * 2, height * 2, 9, 0x00200000]),
                           words([width * 2, height * 2]), words([width, height])]
            for entry in entries where !resolutions.contains(entry) { resolutions.append(entry) }
        }
        dictionary["scale-resolutions"] = resolutions
        return try PropertyListSerialization.data(fromPropertyList: dictionary, format: .xml, options: 0)
    }
}
