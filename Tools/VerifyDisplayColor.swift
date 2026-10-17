// SPDX-License-Identifier: GPL-3.0-or-later
// Read-only ICC, ColorSync conversion and display LUT audit. Never calibrates a panel.
import Foundation
import CoreGraphics
import ColorSync
import CryptoKit

let output = URL(fileURLWithPath: CommandLine.arguments[1])
var ids = [UInt32](repeating: 0, count: 32), count: UInt32 = 0
_ = CGGetActiveDisplayList(32, &ids, &count)
_ = CGGetOnlineDisplayList(32, &ids, &count)
let source = CGColorSpace(name: CGColorSpace.sRGB)!
var displays: [[String: Any]] = []
for id in ids.prefix(Int(count)) {
    let effective = CGDisplayCopyColorSpace(id)
    guard let profile = ColorSyncProfileCreateWithDisplayID(id)?.takeRetainedValue(),
          let bytes = ColorSyncProfileCopyData(profile, nil)?.takeRetainedValue() as Data?,
          let effectiveBytes = effective.copyICCData() as Data? else { continue }
    var errors: Unmanaged<CFError>?, warnings: Unmanaged<CFError>?
    let valid = ColorSyncProfileVerify(profile, &errors, &warnings)
    var samples: [[Double]] = [], failures = 0
    // Includes 9 neutral levels, primaries, secondaries, darks and intermediate saturation.
    for r in 0...8 { for g in 0...8 { for b in 0...8 {
        let rgb = [CGFloat(r)/8, CGFloat(g)/8, CGFloat(b)/8, 1]
        guard let input = CGColor(colorSpace: source, components: rgb),
              let converted = input.converted(to: effective, intent: .relativeColorimetric, options: nil),
              let components = converted.components, components.count >= 3 else { failures += 1; continue }
        samples.append(components.prefix(3).map(Double.init))
    } } }
    let capacity = 4096
    var red = [Float](repeating: 0, count: capacity)
    var green = red, blue = red
    var n: UInt32 = 0
    let gammaStatus = CGGetDisplayTransferByTable(id, UInt32(capacity), &red, &green, &blue, &n)
    let length = min(Int(n), capacity)
    let mode = CGDisplayCopyDisplayMode(id)
    displays.append([
        "id": id, "virtual": CGDisplayVendorNumber(id) == 0xeeee,
        "description": ColorSyncProfileCopyDescriptionString(profile)?.takeRetainedValue() as String? ?? "",
        "iccSHA256": SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(),
        "effectiveSHA256": SHA256.hash(data: effectiveBytes).map { String(format: "%02x", $0) }.joined(),
        "iccValid": valid, "iccError": errors?.takeRetainedValue().localizedDescription ?? "",
        "iccWarning": warnings?.takeRetainedValue().localizedDescription ?? "",
        "samples": samples, "conversionFailures": failures,
        "gammaStatus": gammaStatus.rawValue, "gammaCount": length,
        "gamma": [Array(red.prefix(length)), Array(green.prefix(length)), Array(blue.prefix(length))],
        "mode": ["width": mode?.width ?? 0, "height": mode?.height ?? 0,
                 "pixelWidth": mode?.pixelWidth ?? 0, "pixelHeight": mode?.pixelHeight ?? 0,
                 "rate": mode?.refreshRate ?? 0]
    ])
}
let data = try JSONSerialization.data(withJSONObject: ["date": ISO8601DateFormatter().string(from: Date()),
    "sampleGrid": "9x9x9 sRGB relative colorimetric", "displays": displays], options: [.prettyPrinted, .sortedKeys])
try data.write(to: output, options: .atomic)
print(output.path)
