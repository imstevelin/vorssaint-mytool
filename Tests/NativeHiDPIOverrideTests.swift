// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

enum NativeHiDPIOverrideTests {
    static func run(_ suite: TestSuite) {
        // Real descriptor shape observed for the hidden PA328QV 75 Hz mode.
        // The index is ephemeral and must always come from fresh enumeration.
        var descriptor = [UInt8](repeating: 0, count: 0xd4)
        func put(_ value: UInt32, at offset: Int) {
            for byte in 0..<4 { descriptor[offset + byte] = UInt8(truncatingIfNeeded: value >> (8 * byte)) }
        }
        put(89, at: 0); put(0x200001, at: 4); put(2560, at: 8); put(1440, at: 12)
        descriptor[190] = 75; put(Float(2).bitPattern, at: 208)
        let hidden = NativeDisplayModes.decode(Data(descriptor), index: 89)
        suite.expect(hidden?.matches(width: 2560, height: 1440, pixelWidth: 5120, pixelHeight: 2880, rate: 75) == true,
                     "a valid hidden native HiDPI descriptor retains its logical size, density and refresh rate")
        suite.expect(hidden?.matches(width: 2560, height: 1440, pixelWidth: 2560, pixelHeight: 1440, rate: 75) == false
                     && hidden?.matches(width: 2560, height: 1440, pixelWidth: 5120, pixelHeight: 2880, rate: 60) == false,
                     "private mode selection cannot substitute LoDPI or a lower refresh rate")
        suite.expect(NativeDisplayModes.decode(Data(descriptor.dropLast()), index: 89) == nil
                     && NativeDisplayModes.decode(Data(descriptor), index: 90) == nil,
                     "an incomplete or mismatched private descriptor fails closed")
        put(0, at: 4)
        suite.expect(NativeDisplayModes.decode(Data(descriptor), index: 89) == nil, "an invalid private mode is never selectable")
        put(1, at: 4); put(Float.nan.bitPattern, at: 208)
        suite.expect(NativeDisplayModes.decode(Data(descriptor), index: 89) == nil, "unknown descriptor density fails closed")
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
            suite.expect(entries.count == 4 && entries[0] == Data([4, 5, 6]), "native preparation preserves existing modes and deduplicates additions")
            suite.expect(entries[1] == Data([0,0,0x14,0, 0,0,0x0b,0x40, 0,0,0,9, 0,0x20,0,0]), "2560x1440 HiDPI is encoded as 5120x2880 network-order pixels with explicit flags")
            suite.expect(entries[2] == Data([0,0,0x14,0, 0,0,0x0b,0x40])
                         && entries[3] == Data([0,0,0x0a,0, 0,0,0x05,0xa0]),
                         "native HiDPI includes pixel-double and logical plain-mode dependencies")
            for original in [nil, false, true] as [Bool?] {
                let preference = NativeHiDPIOverride.ResolutionPreference(original: original)
                let roundtrip = try JSONDecoder().decode(NativeHiDPIOverride.ResolutionPreference.self,
                    from: JSONEncoder().encode(preference))
                suite.expect(roundtrip.original == original && roundtrip.accepts(true) && roundtrip.accepts(original),
                             "system scaling preference preserves absent, disabled and enabled baselines")
            }
            suite.expect(!NativeHiDPIOverride.ResolutionPreference(original: nil).accepts(false),
                         "restore cannot overwrite an external system scaling preference change")
            suite.expect(plist["IODisplayEDID"] as? Data == edid && plist["DisplayPixelDimensions"] as? Data == Data([1, 2]), "native preparation preserves EDID and physical dimensions")
            let panel = NativeHiDPIOverride.PanelSize(width: 2560, height: 1440)
            let corrected = try NativeHiDPIOverride.configuration(identity: id,
                sizes: [.init(width: 2560, height: 1440)], existing: existing, nativePanelSize: panel)
            let correctedPlist = try PropertyListSerialization.propertyList(from: corrected, format: nil) as! [String: Any]
            suite.expect(correctedPlist["DisplayPixelDimensions"] as? Data == Data([0,0,0x0a,0, 0,0,0x05,0xa0]),
                         "explicit native panel correction uses physical 2560x1440, never the 5120x2880 render buffer")
            suite.expect(correctedPlist["IODisplayEDID"] as? Data == edid
                         && correctedPlist["scale-resolutions"] as? [Data] == entries,
                         "panel correction preserves EDID and independent scaled mode records")
            let correctedReceipt = NativeHiDPIOverride.Receipt(original: existing, installed: corrected,
                                                               previous: output, nativePanelSize: panel)
            let roundtripReceipt = try JSONDecoder().decode(NativeHiDPIOverride.Receipt.self,
                from: JSONEncoder().encode(correctedReceipt))
            suite.expect(roundtripReceipt.nativePanelSize == panel && roundtripReceipt.original == existing,
                         "explicit panel correction persists separately without changing the restoration baseline")
            for invalidPanel in [NativeHiDPIOverride.PanelSize(width: -1, height: 1440),
                                 .init(width: 2560, height: Int.max)] {
                var rejectedPanel = false
                do { _ = try NativeHiDPIOverride.configuration(identity: id,
                    sizes: [.init(width: 2560, height: 1440)], existing: existing, nativePanelSize: invalidPanel) }
                catch { rejectedPanel = true }
                suite.expect(rejectedPanel, "invalid physical panel dimensions are rejected before encoding")
            }
            suite.expect((plist["DisplayProductName"] as? [String: String])?["en_US"] == "Calibrated screen", "native preparation preserves installed model metadata")
            let twice = try NativeHiDPIOverride.configuration(identity: id, sizes: [.init(width: 2560, height: 1440)], existing: output)
            suite.expect(twice == output, "reapplying a prepared mode is idempotent")
            let receipt = NativeHiDPIOverride.Receipt(original: nil, installed: output, previous: nil)
            let decoded = try JSONDecoder().decode(NativeHiDPIOverride.Receipt.self, from: JSONEncoder().encode(receipt))
            suite.expect(decoded.original == nil && decoded.accepts(nil) && decoded.accepts(output), "receipt preserves original absence for exact removal on restore")
            suite.expect(decoded.nativePanelSize == nil, "legacy receipts do not silently enable native panel correction")
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
