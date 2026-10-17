// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import ColorSync
import CoreGraphics
import Darwin

/// Shared with the independent, unprivileged recovery executable.
public struct DisplayRecoverySnapshot: Codable {
    public struct Screen: Codable {
        public let uuid: String
        public let mirrorUUID: String?
        public let modeID: Int32
        public let width: Int
        public let height: Int
        public let pixelWidth: Int
        public let pixelHeight: Int
        public let refreshRate: Double
        public let x: Int32
        public let y: Int32
    }
    public let screens: [Screen]

    public static func uuid(_ id: CGDirectDisplayID) -> String? {
        typealias CreateUUID = @convention(c) (CGDirectDisplayID) -> Unmanaged<CFUUID>?
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGDisplayCreateUUIDFromDisplayID"),
              let uuid = unsafeBitCast(symbol, to: CreateUUID.self)(id)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }

    public static func onlineIDs() -> [CGDirectDisplayID] {
        // Active enumeration refreshes CoreGraphics' per-process mode cache.
        // Online enumeration alone can leave newly created virtual modes unreadable.
        var active = [CGDirectDisplayID](repeating: 0, count: 64)
        var activeCount: UInt32 = 0
        _ = CGGetActiveDisplayList(64, &active, &activeCount)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }

    public static func capture() -> DisplayRecoverySnapshot {
        DisplayRecoverySnapshot(screens: onlineIDs().compactMap { id in
            guard let uuid = uuid(id), let mode = CGDisplayCopyDisplayMode(id) else { return nil }
            let origin = CGDisplayBounds(id).origin
            let mirror = CGDisplayMirrorsDisplay(id)
            return Screen(uuid: uuid, mirrorUUID: mirror == 0 ? nil : Self.uuid(mirror),
                          modeID: mode.ioDisplayModeID, width: mode.width, height: mode.height,
                          pixelWidth: mode.pixelWidth, pixelHeight: mode.pixelHeight,
                          refreshRate: mode.refreshRate, x: Int32(origin.x), y: Int32(origin.y))
        })
    }

    public func restoringOnly(uuid: String?) -> Bool {
        guard let uuid else { return false }
        return DisplayRecoverySnapshot(screens: screens.filter { $0.uuid == uuid }).restore()
    }

    /// Resolve IDs afresh. Never apply a saved numeric ID to a replacement display.
    @discardableResult
    public func restore() -> Bool {
        let ids = Self.onlineIDs()
        let pairs = ids.compactMap { id in Self.uuid(id).map { ($0, id) } }
        let grouped = Dictionary(grouping: pairs, by: { $0.0 })
        guard screens.allSatisfy({ grouped[$0.uuid, default: []].count <= 1 }) else { return false }
        let byUUID = Dictionary(pairs, uniquingKeysWith: { first, _ in first })
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else { return false }
        var valid = true
        for screen in screens {
            guard let id = byUUID[screen.uuid] else { continue }
            let mirror = screen.mirrorUUID.flatMap { byUUID[$0] } ?? kCGNullDirectDisplay
            valid = CGConfigureDisplayMirrorOfDisplay(config, id, mirror) == .success && valid
            let options = [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary
            let modes = CGDisplayCopyAllDisplayModes(id, options) as? [CGDisplayMode] ?? []
            let matches: (CGDisplayMode) -> Bool = {
                $0.width == screen.width && $0.height == screen.height
                    && $0.pixelWidth == screen.pixelWidth && $0.pixelHeight == screen.pixelHeight
                    && ($0.refreshRate == 0 || screen.refreshRate == 0 || abs($0.refreshRate - screen.refreshRate) < 0.5)
            }
            let mode = modes.first { $0.ioDisplayModeID == screen.modeID && matches($0) }
                ?? modes.first(where: matches)
            if let mode { valid = CGConfigureDisplayWithDisplayMode(config, id, mode, nil) == .success && valid }
            else { valid = false }
            valid = CGConfigureDisplayOrigin(config, id, screen.x, screen.y) == .success && valid
        }
        guard valid else { CGCancelDisplayConfiguration(config); return false }
        return CGCompleteDisplayConfiguration(config, .forSession) == .success
    }
}

public struct DisplayRecoveryJournal: Codable {
    public let parentPID: Int32
    public let snapshot: DisplayRecoverySnapshot
    public var deadline: TimeInterval
    public var confirmed: Bool
    public var hostPIDs: [Int32] = []
    public init(parentPID: Int32, snapshot: DisplayRecoverySnapshot, deadline: TimeInterval) {
        self.parentPID = parentPID; self.snapshot = snapshot; self.deadline = deadline; confirmed = false
    }
    public func save(to url: URL) throws {
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

public struct VirtualDisplayHostRequest: Codable {
    public let parentPID: Int32
    public let width: UInt32
    public let height: UInt32
    public let rate: Double
    public let serial: UInt32
    public let name: String
    public let colorProfile: Data?
    public init(parentPID: Int32, width: UInt32, height: UInt32, rate: Double, serial: UInt32, name: String, colorProfile: Data? = nil) {
        self.parentPID = parentPID; self.width = width; self.height = height
        self.rate = rate; self.serial = serial; self.name = name; self.colorProfile = colorProfile
    }
}

/// Read the effective ICC, including the user's calibration. Never substitute sRGB.
public enum DisplayColorProfile {
    public static func data(for id: CGDirectDisplayID) -> Data? {
        guard let profile = ColorSyncProfileCreateWithDisplayID(id)?.takeRetainedValue(),
              let data = ColorSyncProfileCopyData(profile, nil)?.takeRetainedValue() else { return nil }
        return data as Data
    }

    public static func matches(_ data: Data, display id: CGDirectDisplayID) -> Bool {
        guard self.data(for: id) == data,
              let effective = CGDisplayCopyColorSpace(id).copyICCData() else { return false }
        return effective as Data == data
    }

    public static func resetOwnedVirtualDisplay(_ id: CGDirectDisplayID) {
        guard CGDisplayVendorNumber(id) == 0xeeee,
              let deviceClass = kColorSyncDisplayDeviceClass?.takeUnretainedValue(),
              let defaultID = kColorSyncDeviceDefaultProfileID?.takeUnretainedValue(),
              let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return }
        _ = ColorSyncDeviceSetCustomProfiles(deviceClass, uuid,
            [defaultID as String: kCFNull as Any] as CFDictionary)
    }

    public static func apply(_ data: Data, to id: CGDirectDisplayID, url: URL) -> Bool {
        guard let deviceClass = kColorSyncDisplayDeviceClass?.takeUnretainedValue(),
              let defaultID = kColorSyncDeviceDefaultProfileID?.takeUnretainedValue(),
              let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return false }
        do { try data.write(to: url, options: .atomic) } catch { return false }
        return ColorSyncDeviceSetCustomProfiles(deviceClass, uuid,
            [defaultID as String: url as CFURL] as CFDictionary)
    }
}
