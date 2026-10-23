// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import CoreGraphics
import Darwin

/// CoreGraphics' public list omits some valid scaled modes installed by a
/// model override. Resolve the legacy mode API dynamically and validate its
/// fixed-size descriptor before using it. Callers still own rollback/readback.
public enum NativeDisplayModes {
    public struct Mode {
        public let index: Int32
        public let width: Int
        public let height: Int
        public let rate: Double
        public let density: Double
        public var pixelWidth: Int { Int(Double(width) * density) }
        public var pixelHeight: Int { Int(Double(height) * density) }
        public func matches(width: Int, height: Int, pixelWidth: Int, pixelHeight: Int, rate: Double) -> Bool {
            self.width == width && self.height == height && self.pixelWidth == pixelWidth
                && self.pixelHeight == pixelHeight && rate.isFinite && rate > 0
                && abs(self.rate - rate) < 0.5
        }
    }
    private typealias Count = @convention(c) (UInt32, UnsafeMutablePointer<Int32>) -> Void
    private typealias Describe = @convention(c) (UInt32, Int32, UnsafeMutableRawPointer, Int32) -> Void
    private typealias Configure = @convention(c) (CGDisplayConfigRef, UInt32, Int32) -> Int32
    private static let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY)
    private static func symbol<T>(_ name: String, as: T.Type) -> T? {
        guard let handle, let pointer = dlsym(handle, name) else { return nil }
        return unsafeBitCast(pointer, to: T.self)
    }
    public static func decode(_ data: Data, index: Int32) -> Mode? {
        guard data.count == 0xd4, index >= 0 else { return nil }
        let bytes = [UInt8](data)
        func word(_ offset: Int) -> UInt32 {
            (0..<4).reduce(0) { $0 | UInt32(bytes[offset + $1]) << (8 * $1) }
        }
        let width = Int(word(8)), height = Int(word(12))
        let density = Double(Float(bitPattern: word(208)))
        let rate = Double(UInt16(bytes[190]) | UInt16(bytes[191]) << 8)
        guard word(0) == UInt32(index), word(4) & 1 != 0,
              (320...16384).contains(width), (200...16384).contains(height),
              density == 1 || density == 2, (24...240).contains(rate) else { return nil }
        return Mode(index: index, width: width, height: height, rate: rate, density: density)
    }
    public static func modes(for display: UInt32) -> [Mode] {
        guard CGDisplayIsOnline(display) != 0,
              let count = symbol("CGSGetNumberOfDisplayModes", as: Count.self),
              let describe = symbol("CGSGetDisplayModeDescriptionOfLength", as: Describe.self) else { return [] }
        var total: Int32 = 0
        count(display, &total)
        guard total > 0, total <= 20000 else { return [] }
        return (0..<total).compactMap { index in
            var bytes = [UInt8](repeating: 0, count: 0xd4)
            bytes.withUnsafeMutableBytes { describe(display, index, $0.baseAddress!, 0xd4) }
            return decode(Data(bytes), index: index)
        }
    }
    public static func configure(_ mode: Mode, display: UInt32, config: CGDisplayConfigRef) -> Bool {
        guard let configure = symbol("CGSConfigureDisplayMode", as: Configure.self) else { return false }
        return configure(config, display, mode.index) == CGError.success.rawValue
    }
    /// Only for an explicitly requested real-display mode, after a watchdog is armed.
    public static func apply(display: UInt32, width: Int, height: Int, rate: Double) -> Bool {
        guard CGDisplayIsBuiltin(display) == 0, CGDisplayIsInMirrorSet(display) == 0,
              width >= 640, width <= 3072, height >= 480, height <= 3072,
              let mode = modes(for: display).first(where: {
                  $0.matches(width: width, height: height, pixelWidth: width * 2, pixelHeight: height * 2, rate: rate)
              }) else { return false }
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else { return false }
        guard configure(mode, display: display, config: config) else {
            CGCancelDisplayConfiguration(config); return false
        }
        return CGCompleteDisplayConfiguration(config, .forSession) == .success
    }
}
