// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint contributors

import AppKit
import ApplicationServices
import CryptoKit

/// Optional, local display memory for windows that are still open. It owns no
/// shortcuts or event taps and stops observing as soon as both options are off.
final class DisplayWindowMemoryService {
    static let shared = DisplayWindowMemoryService()

    private struct VisibleWindow {
        let id: CGWindowID
        let pid: pid_t
        let bundleID: String
        let titleDigest: String?
        let frame: CGRect
        let screen: NSScreen
    }

    private struct Observation {
        var display: String
        var size: CGSize
        var stableScans: Int
        var expectedFrame: CGRect?
        var attempts: Int = 0
        var skipLearning = false
        var lastSeen: Date
    }

    private let defaults = UserDefaults.standard
    private var memory: DisplayWindowMemory
    private var salt: String
    private var observations: [CGWindowID: Observation] = [:]
    private var knownDisplays = Set<String>()
    private var timer: Timer?
    private var displayObserver: NSObjectProtocol?
    private var scanResumeAt = Date.distantPast
    private var captureResumeAt = Date.distantPast
    private var transitionGeneration = 0

    private init() {
        if let data = defaults.data(forKey: DefaultsKey.windowDisplayMemory),
           let decoded = try? JSONDecoder().decode(DisplayWindowMemory.self, from: data) {
            memory = decoded
        } else {
            memory = DisplayWindowMemory()
        }
        if let saved = defaults.string(forKey: DefaultsKey.windowDisplayMemorySalt) {
            salt = saved
        } else {
            salt = UUID().uuidString
            defaults.set(salt, forKey: DefaultsKey.windowDisplayMemorySalt)
        }
        SessionActivity.shared.onChange { [weak self] _ in self?.syncWithPreferences() }
    }

    func syncWithPreferences() {
        let wanted = AppFeature.windowLayout.isAvailable
            && (defaults.bool(forKey: DefaultsKey.windowRememberSizes)
                || defaults.bool(forKey: DefaultsKey.windowRestoreDisplayLayout))
            && AXIsProcessTrusted() && SessionActivity.shared.isActive
        guard wanted else { stop(); return }
        guard timer == nil else { return }
        knownDisplays = Set(NSScreen.screens.compactMap(displayKey))
        displayObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.displayConfigurationChanged() }
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.scan()
        }
        scan()
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        if let displayObserver { NotificationCenter.default.removeObserver(displayObserver) }
        displayObserver = nil
        observations.removeAll()
        transitionGeneration += 1
    }

    private func displayConfigurationChanged() {
        let current = Set(NSScreen.screens.compactMap(displayKey))
        guard current != knownDisplays else { return }
        let added = DisplayWindowMemorySupport.newlyConnected(previous: knownDisplays, current: current)
        knownDisplays = current
        observations.removeAll()
        captureResumeAt = Date().addingTimeInterval(10)
        scanResumeAt = Date().addingTimeInterval(3)
        transitionGeneration += 1
        let generation = transitionGeneration
        // AppKit and other applications need a moment to settle after display changes.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, self.transitionGeneration == generation, self.timer != nil,
                  AXIsProcessTrusted(), SessionActivity.shared.isActive else { return }
            if self.defaults.bool(forKey: DefaultsKey.windowRestoreDisplayLayout) {
                self.restoreLayouts(on: added)
            }
            // A removed display needs its remaining windows resized now. A
            // reconnected display gets a short grace period after placement.
            self.scanResumeAt = added.isEmpty ? .distantPast : Date().addingTimeInterval(3)
            if added.isEmpty { self.scan() }
        }
    }

    private func scan() {
        guard AXIsProcessTrusted(), SessionActivity.shared.isActive,
              Date() >= scanResumeAt else { return }
        let windows = visibleWindows()
        guard !windows.isEmpty else { return }
        let now = Date()
        let rememberSizes = defaults.bool(forKey: DefaultsKey.windowRememberSizes)
        if rememberSizes {
            for window in windows {
                guard let display = displayKey(window.screen) else { continue }
                let previous = observations[window.id]
                let size = window.frame.size
                if previous == nil || previous?.display != display {
                    let profile = memory.displays[display]
                    let exact = profile?.sizes[DisplayWindowMemorySupport.profileKey(
                        bundleID: window.bundleID, titleDigest: window.titleDigest)]
                    let fallback = profile?.sizes[DisplayWindowMemorySupport.profileKey(
                        bundleID: window.bundleID, titleDigest: nil)]
                    var desired: CGRect?
                    if let target = exact ?? fallback,
                       abs(target.width - size.width) > 12 || abs(target.height - size.height) > 12 {
                        desired = DisplayWindowMemorySupport.fittedFrame(
                            CGRect(origin: window.frame.origin, size: target),
                            within: usableBounds(window.screen))
                        if let desired { _ = setFrame(desired, for: window) }
                    }
                    observations[window.id] = Observation(display: display, size: size,
                                                          stableScans: 0, expectedFrame: desired,
                                                          lastSeen: now)
                    continue
                }
                var observation = previous!
                observation.lastSeen = now
                if let expected = observation.expectedFrame {
                    if close(window.frame, expected) {
                        observation.expectedFrame = nil
                        observation.size = window.frame.size
                        observation.stableScans = 0
                    } else if observation.attempts < 2 {
                        _ = setFrame(expected, for: window)
                        observation.attempts += 1
                    } else {
                        observation.expectedFrame = nil
                        observation.skipLearning = true
                    }
                } else if close(size, observation.size) {
                    observation.stableScans += 1
                    if observation.stableScans == 2 && !observation.skipLearning {
                        var stored = memory.displays[display] ?? RememberedDisplay()
                        stored.sizes[DisplayWindowMemorySupport.profileKey(
                            bundleID: window.bundleID, titleDigest: window.titleDigest)] = size
                        // Titles can be unavailable without Screen Recording; keep a usable app fallback.
                        stored.sizes[DisplayWindowMemorySupport.profileKey(
                            bundleID: window.bundleID, titleDigest: nil)] = size
                        memory.displays[display] = stored
                        persist()
                    }
                } else {
                    observation.size = size
                    observation.stableScans = 0
                    observation.skipLearning = false
                }
                observations[window.id] = observation
            }
            observations = observations.filter {
                now.timeIntervalSince($0.value.lastSeen) < 3600
            }
        } else {
            observations.removeAll()
        }

        if defaults.bool(forKey: DefaultsKey.windowRestoreDisplayLayout), now >= captureResumeAt {
            var captured: [String: [RememberedWindow]] = [:]
            for window in windows {
                guard let display = displayKey(window.screen) else { continue }
                let bounds = displayBounds(window.screen)
                let relative = CGRect(x: window.frame.minX - bounds.minX,
                                      y: window.frame.minY - bounds.minY,
                                      width: window.frame.width, height: window.frame.height)
                captured[display, default: []].append(RememberedWindow(
                    bundleID: window.bundleID, titleDigest: window.titleDigest,
                    relativeFrame: relative))
            }
            var changed = false
            for (display, windows) in captured where !windows.isEmpty {
                var stored = memory.displays[display] ?? RememberedDisplay()
                if stored.windows != windows {
                    stored.windows = windows
                    memory.displays[display] = stored
                    changed = true
                }
            }
            if changed { persist() }
        }
    }

    private func restoreLayouts(on displays: Set<String>) {
        guard !displays.isEmpty else { return }
        var available = visibleWindows()
        for screen in NSScreen.screens {
            guard let key = displayKey(screen), displays.contains(key),
                  let saved = memory.displays[key]?.windows else { continue }
            let bounds = displayBounds(screen)
            let usable = usableBounds(screen)
            for entry in saved {
                let target = DisplayWindowMemorySupport.fittedFrame(
                    entry.relativeFrame.offsetBy(dx: bounds.minX, dy: bounds.minY), within: usable)
                let matches = available.filter {
                    DisplayWindowMemorySupport.matches(entry, bundleID: $0.bundleID,
                                                       titleDigest: $0.titleDigest)
                }
                guard let window = matches.min(by: {
                    distance($0.frame, target) < distance($1.frame, target)
                }) else { continue }
                if setFrame(target, for: window) {
                    available.removeAll { $0.id == window.id }
                    observations.removeValue(forKey: window.id)
                }
            }
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(memory) else { return }
        defaults.set(data, forKey: DefaultsKey.windowDisplayMemory)
    }

    private func digest(_ title: String?) -> String? {
        guard let title, !title.isEmpty else { return nil }
        return SHA256.hash(data: Data((salt + title).utf8))
            .map { String(format: "%02x", $0) }.joined()
    }

    private func visibleWindows() -> [VisibleWindow] {
        guard let entries = CGWindowListCopyWindowInfo(
            [.excludeDesktopElements, .optionOnScreenOnly], kCGNullWindowID
        ) as? [[String: Any]] else { return [] }
        let screens = NSScreen.screens
        return entries.compactMap { item in
            guard let layer = item[kCGWindowLayer as String] as? Int, layer == 0,
                  let id = item[kCGWindowNumber as String] as? CGWindowID,
                  let pid = item[kCGWindowOwnerPID as String] as? pid_t,
                  pid != getpid(),
                  let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier,
                  let raw = item[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: raw as CFDictionary),
                  bounds.width >= 100, bounds.height >= 100,
                  let screen = screens.max(by: {
                      displayBounds($0).intersection(bounds).area < displayBounds($1).intersection(bounds).area
                  }), displayBounds(screen).intersects(bounds) else { return nil }
            return VisibleWindow(id: id, pid: pid, bundleID: bundleID,
                                 titleDigest: digest(item[kCGWindowName as String] as? String),
                                 frame: bounds, screen: screen)
        }
    }

    private func displayKey(_ screen: NSScreen) -> String? {
        guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                as? CGDirectDisplayID else { return nil }
        if CGDisplayIsBuiltin(id) != 0 { return "builtin" }
        return "external:\(CGDisplayVendorNumber(id)):\(CGDisplayModelNumber(id)):\(CGDisplaySerialNumber(id))"
    }

    private func displayBounds(_ screen: NSScreen) -> CGRect {
        guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                as? CGDirectDisplayID else { return screen.frame }
        return CGDisplayBounds(id)
    }

    private func usableBounds(_ screen: NSScreen) -> CGRect {
        DisplayWindowMemorySupport.usableBounds(screenFrame: screen.frame,
                                                visibleFrame: screen.visibleFrame,
                                                displayBounds: displayBounds(screen))
    }

    private func setFrame(_ target: CGRect, for item: VisibleWindow) -> Bool {
        let app = AXUIElementCreateApplication(item.pid)
        AXUIElementSetMessagingTimeout(app, 0.3)
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &raw) == .success,
              let windows = raw as? [AXUIElement] else { return false }
        let closest = windows.compactMap { window -> (AXUIElement, CGFloat)? in
            AXUIElementSetMessagingTimeout(window, 0.3)
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &value) == .success,
                  let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
            var position = CGPoint.zero
            guard AXValueGetValue(value as! AXValue, .cgPoint, &position) else { return nil }
            return (window, abs(position.x - item.frame.minX) + abs(position.y - item.frame.minY))
        }.min { $0.1 < $1.1 }?.0
        guard let window = closest else { return false }
        var fullScreen: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &fullScreen) == .success,
           (fullScreen as? Bool) == true { return false }
        var position = target.origin
        var size = target.size
        guard let positionValue = AXValueCreate(.cgPoint, &position),
              let sizeValue = AXValueCreate(.cgSize, &size) else { return false }
        let first = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
        let resized = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        let last = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
        return resized == .success && (first == .success || last == .success)
    }

    private func close(_ lhs: CGSize, _ rhs: CGSize) -> Bool {
        abs(lhs.width - rhs.width) <= 12 && abs(lhs.height - rhs.height) <= 12
    }

    private func close(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        close(lhs.size, rhs.size) && abs(lhs.minX - rhs.minX) <= 12 && abs(lhs.minY - rhs.minY) <= 12
    }

    private func distance(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        abs(lhs.midX - rhs.midX) + abs(lhs.midY - rhs.midY)
    }
}

private extension CGRect {
    var area: CGFloat { isNull ? 0 : width * height }
}
