// SPDX-License-Identifier: GPL-3.0-or-later
// Developer-only, explicit opt-in real-device integration verification.
#if VORSSAINT_DEVELOPMENT
import AppKit
#if canImport(DisplayRecoverySupport)
import DisplayRecoverySupport
#endif

enum DisplayIntegrationValidation {
    @MainActor static func startIfRequested() -> Bool {
        guard let argument = CommandLine.arguments.first(where: { $0.hasPrefix("--verify-display-integration=") }) else { return false }
        let path = String(argument.dropFirst("--verify-display-integration=".count))
        Task { @MainActor in await run(URL(fileURLWithPath: path)) }
        return true
    }
    @MainActor private static func run(_ output: URL) async {
        var events: [[String: Any]] = []
        func record(_ name: String, _ details: [String: Any] = [:]) {
            events.append(["event": name, "details": details, "time": Date().timeIntervalSince1970])
            if let data = try? JSONSerialization.data(withJSONObject: events, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: output, options: .atomic)
            }
        }
        let baseline = DisplayRecoverySnapshot.capture()
        if let data = try? JSONEncoder().encode(baseline) { try? data.write(to: output.appendingPathExtension("baseline.json")) }
        let defaults = UserDefaults.standard
        let oldEnabled = defaults.object(forKey: DefaultsKey.brightnessControlEnabled)
        let oldProfiles = defaults.object(forKey: "virtualHiDPIProfilesLocalV1")
        let crashMode = CommandLine.arguments.contains("--verify-display-crash")
        defaults.set(true, forKey: DefaultsKey.brightnessControlEnabled)
        let service = BrightnessService.shared
        service.syncWithPreferences()
        record("start", ["baselineScreens": baseline.screens.count])
        for _ in 0..<100 {
            if !service.hardwareControls.isEmpty { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        guard let display = service.displays.first(where: { !$0.isBuiltIn && $0.isActive && service.hardwareControls[$0.id] != nil }) else {
            record("failed", ["reason": "No matched physical DDC display"])
            restorePreference(defaults, value: oldEnabled); NSApp.terminate(nil); return
        }
        let id = display.id
        record("physical", ["id": id, "name": display.name, "brightness": display.brightness])
        var originals: [UInt8: UInt16] = [:]
        for code: UInt8 in [0x10, 0x12, 0x62, 0x8d] {
            if let value = await read(code, id: id) {
                originals[code] = value.current
                record("ddcRead", ["code": code, "current": value.current, "max": value.maximum])
            } else { record("ddcUnavailable", ["code": code]) }
        }
        for control in (crashMode ? [] : [DisplayHardwareControl.contrast, .volume, .mute]) {
            guard let value = service.hardwareControls[id]?.values[control], let original = originals[control.rawValue] else { continue }
            let target: UInt16 = control == .mute ? (original == 1 ? 2 : 1)
                : (original < value.maximum ? min(value.maximum, original + max(1, value.maximum / 20)) : original - 1)
            // Keep hardware muted while testing its volume, and restore volume before unmuting.
            let normalized = control == .mute ? (target == 1 ? 1.0 : 0.0) : Double(target) / Double(value.maximum)
            let applied = await set(control, value: normalized, id: id)
            record("ddcWrite", ["code": control.rawValue, "requested": target, "confirmed": applied,
                                "readback": service.hardwareControls[id]?.values[control]?.current as Any? ?? "nil"])
            let restore = control == .mute ? (original == 1 ? 1.0 : 0.0) : Double(original) / Double(value.maximum)
            let restored = await set(control, value: restore, id: id)
            record("ddcRestored", ["code": control.rawValue, "confirmed": restored])
        }
        if !crashMode, let before = await read(0x10, id: id), before.maximum > 0, display.method == .ddc {
            let target = before.current < before.maximum ? before.current + 1 : before.current - 1
            service.setBrightness(Double(target) / Double(before.maximum), for: id)
            try? await Task.sleep(nanoseconds: 400_000_000)
            let changed = await read(0x10, id: id)
            record("brightnessWrite", ["requested": target, "readback": changed?.current as Any? ?? "nil"])
            service.setBrightness(Double(before.current) / Double(before.maximum), for: id)
            try? await Task.sleep(nanoseconds: 400_000_000)
            record("brightnessRestored", ["readback": (await read(0x10, id: id))?.current as Any? ?? "nil"])
        }
        let hiDPI = VirtualHiDPIService.shared
        let fullSize = CommandLine.arguments.contains("--verify-display-2560")
        let profile = VirtualHiDPIService.Profile(width: fullSize ? 2560 : 1920,
                                                  height: fullSize ? 1440 : 1080, rate: 60)
        hiDPI.enable(id, profile: profile, preferNative: false)
        for _ in 0..<120 {
            if hiDPI.confirmationDisplay == id || hiDPI.failure != nil { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        if let session = hiDPI.sessions[id], hiDPI.confirmationDisplay == id {
            let mode = CGDisplayCopyDisplayMode(session.virtualID ?? id) ?? CGDisplayCopyDisplayMode(id)
            record("hidpiActive", ["virtual": session.virtualID as Any? ?? "native", "width": mode?.width ?? 0,
                "height": mode?.height ?? 0, "pixelWidth": mode?.pixelWidth ?? 0, "pixelHeight": mode?.pixelHeight ?? 0])
            if crashMode {
                hiDPI.confirm()
                restorePreference(defaults, value: oldEnabled)
                if let oldProfiles { defaults.set(oldProfiles, forKey: "virtualHiDPIProfilesLocalV1") }
                else { defaults.removeObject(forKey: "virtualHiDPIProfilesLocalV1") }
                defaults.synchronize()
                record("crashArmed", ["pid": getpid()])
                _ = kill(getpid(), SIGKILL)
                return
            }
            // Intentionally do not confirm: independent helper must roll back.
            try? await Task.sleep(nanoseconds: 18_000_000_000)
            record("timeoutRollback", ["sessions": hiDPI.sessions.count, "baselineMatches": snapshotMatches(baseline)])
            hiDPI.enable(id, profile: profile, preferNative: false)
            for _ in 0..<120 {
                if hiDPI.confirmationDisplay == id || hiDPI.failure != nil { break }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            if hiDPI.confirmationDisplay == id {
                hiDPI.confirm()
                service.refresh(force: true)
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                record("confirmedHiDPI", ["session": hiDPI.sessions[id] != nil,
                    "physicalCard": service.displays.contains { $0.id == id },
                    "ddcVolumeReadable": (await read(0x62, id: id)) != nil])
                hiDPI.disable(id)
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                record("disabledHiDPI", ["baselineMatches": snapshotMatches(baseline)])
            }
        } else { record("hidpiFailed", ["reason": hiDPI.failure ?? "timeout"]) }
        hiDPI.stopAll()
        for code: UInt8 in [0x10, 0x12, 0x62, 0x8d] {
            let reading = await read(code, id: id)
            record("finalDDC", ["code": code, "current": reading?.current as Any? ?? "nil",
                                "matches": reading?.current == originals[code]])
        }
        record("done", ["baselineMatches": snapshotMatches(baseline), "remainingSessions": hiDPI.sessions.count])
        restorePreference(defaults, value: oldEnabled)
        NSApp.terminate(nil)
    }
    @MainActor private static func restorePreference(_ defaults: UserDefaults, value: Any?) {
        if let value { defaults.set(value, forKey: DefaultsKey.brightnessControlEnabled) }
        else { defaults.removeObject(forKey: DefaultsKey.brightnessControlEnabled) }
    }
    @MainActor private static func snapshotMatches(_ original: DisplayRecoverySnapshot) -> Bool {
        let current = DisplayRecoverySnapshot.capture()
        return original.screens.allSatisfy { before in
            current.screens.contains { after in
                before.uuid == after.uuid && before.modeID == after.modeID && before.x == after.x && before.y == after.y
                    && before.mirrorUUID == after.mirrorUUID && before.pixelWidth == after.pixelWidth
                    && before.pixelHeight == after.pixelHeight
            }
        } && original.screens.count == current.screens.count
    }
    @MainActor private static func read(_ code: UInt8, id: CGDirectDisplayID) async -> DisplayHardwareValue? {
        await withCheckedContinuation { continuation in
            BrightnessService.shared.readHardwareForValidation(code, for: id) { continuation.resume(returning: $0) }
        }
    }
    @MainActor private static func set(_ control: DisplayHardwareControl, value: Double, id: CGDirectDisplayID) async -> Bool {
        await withCheckedContinuation { continuation in
            BrightnessService.shared.setHardwareControl(control, value: value, for: id) { continuation.resume(returning: $0) }
        }
    }
}
#endif
