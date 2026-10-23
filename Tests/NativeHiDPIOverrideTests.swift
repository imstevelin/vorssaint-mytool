// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

enum NativeHiDPIOverrideTests {
    static func run(_ suite: TestSuite) {
        let id = NativeHiDPIOverride.Identity(vendor: 0x6b3, product: 0x32c2)
        suite.expect(id.relativePath == "DisplayVendorID-6b3/DisplayProductID-32c2", "native override uses the actual vendor/product model path")
        do {
            let edid = Data([0, 255, 1, 2])
            let existing = try PropertyListSerialization.data(fromPropertyList: [
                "DisplayVendorID": id.vendor, "DisplayProductID": id.product,
                "IODisplayEDID": edid, "DisplayPixelDimensions": Data([1, 2]),
                "DisplayProductName": ["en_US": "Calibrated screen"],
                "scale-resolutions": [Data([4, 5, 6])]
            ], format: .binary, options: 0)
            let output = try NativeHiDPIOverride.configuration(identity: id,
                sizes: [.init(width: 2560, height: 1440), .init(width: 2560, height: 1440)], existing: existing)
            let plist = try PropertyListSerialization.propertyList(from: output, format: nil) as! [String: Any]
            let entries = plist["scale-resolutions"] as! [Data]
            suite.expect(entries.count == 2 && entries[0] == Data([4, 5, 6]), "native preparation preserves existing modes and deduplicates additions")
            suite.expect(entries.last == Data([0,0,0x14,0, 0,0,0x0b,0x40, 0,0,0,9, 0,0xa0,0,0]), "2560x1440 HiDPI is encoded as 5120x2880 network-order pixels with explicit flags")
            suite.expect(plist["IODisplayEDID"] as? Data == edid && plist["DisplayPixelDimensions"] as? Data == Data([1, 2]), "native preparation preserves EDID and physical dimensions")
            suite.expect((plist["DisplayProductName"] as? [String: String])?["en_US"] == "Calibrated screen", "native preparation preserves installed model metadata")
            let twice = try NativeHiDPIOverride.configuration(identity: id, sizes: [.init(width: 2560, height: 1440)], existing: output)
            suite.expect(twice == output, "reapplying a prepared mode is idempotent")
            let receipt = NativeHiDPIOverride.Receipt(original: nil, installed: output, previous: nil)
            let decoded = try JSONDecoder().decode(NativeHiDPIOverride.Receipt.self, from: JSONEncoder().encode(receipt))
            suite.expect(decoded.original == nil && decoded.accepts(nil) && decoded.accepts(output), "receipt preserves original absence for exact removal on restore")
            suite.expect(!decoded.accepts(Data([9])), "third-party override changes are rejected rather than overwritten")
            let updating = NativeHiDPIOverride.Receipt(original: existing, installed: twice, previous: output)
            suite.expect(updating.accepts(existing) && updating.accepts(output) && updating.accepts(twice), "interrupted updates retain known original and installed states")
            for (vendor, product, width, height) in [(0, 1, 1920, 1080), (1, 65536, 1920, 1080), (1, 1, 4000, 2000), (1, 1, -1, 1080)] {
                var rejected = false
                do { _ = try NativeHiDPIOverride.configuration(identity: .init(vendor: UInt32(vendor), product: UInt32(product)), sizes: [.init(width: width, height: height)], existing: nil) }
                catch { rejected = true }
                suite.expect(rejected, "invalid identity/dimensions cannot become a system override")
            }
            var rejected = false
            do { _ = try NativeHiDPIOverride.configuration(identity: .init(vendor: 1, product: 2), sizes: [.init(width: 1920, height: 1080)], existing: existing) }
            catch { rejected = true }
            suite.expect(rejected, "an override for another model cannot be reused")
        } catch { suite.expect(false, "native override fixture: \(error)") }
    }
}
