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
        let pid: pid_t
        let bundleID: String
        var state: DisplayWindowObservation
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
    private var pendingLayoutDisplays = Set<String>()
    private var interactionResumeAt = Date.distantPast

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
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
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
        pendingLayoutDisplays.removeAll()
        transitionGeneration += 1
    }

    private func displayConfigurationChanged() {
        let current = Set(NSScreen.screens.compactMap(displayKey))
        guard current != knownDisplays else { return }
        let added = DisplayWindowMemorySupport.newlyConnected(previous: knownDisplays, current: current)
        knownDisplays = current
        pendingLayoutDisplays.formUnion(added)
        pendingLayoutDisplays.formIntersection(current)
        captureResumeAt = Date().addingTimeInterval(2)
        scanResumeAt = Date().addingTimeInterval(0.6)
        transitionGeneration += 1
        let generation = transitionGeneration
        // Coalesce topology notifications, then let the ordinary scan wait for
        // mouse interaction to finish before moving any windows.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self, self.transitionGeneration == generation, self.timer != nil else { return }
            self.scan()
        }
    }

    private func scan() {
        guard AXIsProcessTrusted(), SessionActivity.shared.isActive,
              Date() >= scanResumeAt else { return }
        let now = Date()
        if NSEvent.pressedMouseButtons != 0 {
            interactionResumeAt = now.addingTimeInterval(0.25)
        }
        let interacting = now < interactionResumeAt
        if !interacting, !pendingLayoutDisplays.isEmpty {
            let displays = pendingLayoutDisplays
            pendingLayoutDisplays.removeAll()
            if defaults.bool(forKey: DefaultsKey.windowRestoreDisplayLayout) {
                restoreLayouts(on: displays)
                captureResumeAt = now.addingTimeInterval(2)
                return // Never capture the pre-placement WindowServer snapshot.
            }
        }
        let windows = visibleWindows()
        let rememberSizes = defaults.bool(forKey: DefaultsKey.windowRememberSizes)
        var appliedFrame = false
        if rememberSizes {
            for window in windows {
                guard let display = displayKey(window.screen) else { continue }
                var previous = observations[window.id]
                if previous?.pid != window.pid || previous?.bundleID != window.bundleID {
                    previous = nil // WindowServer can recycle a closed window's ID.
                }
                let decision = DisplayWindowMemorySupport.action(
                    previous: previous?.state, display: display, frame: window.frame,
                    now: now, interacting: interacting)
                if decision == .wait { continue }
                if decision == .restore {
                    let profile = memory.displays[display]
                    let exact = profile?.sizes[DisplayWindowMemorySupport.profileKey(
                        bundleID: window.bundleID, titleDigest: window.titleDigest)]
                    let fallback = profile?.sizes[DisplayWindowMemorySupport.profileKey(
                        bundleID: window.bundleID, titleDigest: nil)]
                    if let target = exact ?? fallback {
                        let desired = DisplayWindowMemorySupport.fittedFrame(
                            CGRect(origin: window.frame.origin, size: target),
                            within: usableBounds(window.screen))
                        if !DisplayWindowMemorySupport.close(window.frame.size, desired.size) {
                            appliedFrame = setFrame(desired, for: window) || appliedFrame
                        }
                    }
                    // Consume the transition even if the app rejects the request.
                    // Retrying a stale frame fights manual moves and app size limits.
                    observations[window.id] = Observation(
                        pid: window.pid, bundleID: window.bundleID,
                        state: DisplayWindowObservation(display: display, frame: window.frame,
                                                        stableSince: now), lastSeen: now)
                    continue
                }
                var observation = previous!
                observation.lastSeen = now
                if !DisplayWindowMemorySupport.close(window.frame, observation.state.frame) || interacting {
                    observation.state.frame = window.frame
                    observation.state.stableSince = now
                    observation.state.learned = false
                } else if decision == .learn {
                    var stored = memory.displays[display] ?? RememberedDisplay()
                    stored.sizes[DisplayWindowMemorySupport.profileKey(
                        bundleID: window.bundleID, titleDigest: window.titleDigest)] = window.frame.size
                    stored.sizes[DisplayWindowMemorySupport.profileKey(
                        bundleID: window.bundleID, titleDigest: nil)] = window.frame.size
                    memory.displays[display] = stored
                    observation.state.learned = true
                    persist()
                }
                observations[window.id] = observation
            }
            // Hidden/minimized windows and other Spaces are not new windows.
            // Keep their consumed transition so revealing them cannot reapply
            // an app fallback size over a manual adjustment.
            observations = observations.filter {
                now.timeIntervalSince($0.value.lastSeen) < 3600
            }
        } else {
            observations.removeAll()
        }
        guard !interacting, !appliedFrame else { return }

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
                    observations[window.id] = Observation(
                        pid: window.pid, bundleID: window.bundleID,
                        state: DisplayWindowObservation(display: key, frame: target,
                                                        stableSince: Date()), lastSeen: Date())
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
        AXUIElementSetMessagingTimeout(app, 0.1)
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &raw) == .success,
              let windows = raw as? [AXUIElement] else { return false }
        // Position alone is ambiguous for overlapping windows of the same app.
        guard let window = windows.first(where: {
            AXWindowResolver.windowID(for: $0) == item.id
        }) else { return false }
        AXUIElementSetMessagingTimeout(window, 0.1)
        // Recheck input immediately before writing AX attributes.
        guard NSEvent.pressedMouseButtons == 0 else { return false }
        var fullScreen: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &fullScreen) == .success,
           (fullScreen as? Bool) == true { return false }
        var position = target.origin
        var size = target.size
        guard let positionValue = AXValueCreate(.cgPoint, &position),
              let sizeValue = AXValueCreate(.cgSize, &size) else { return false }
        let suspension = EnhancedUserInterfaceSuspension.suspend(forAppOf: window)
        defer { suspension?.resume() }
        guard NSEvent.pressedMouseButtons == 0 else { return false }
        // A size-only restore normally needs no position writes. Moving to a
        // different display first allows sizes larger than the source display.
        if abs(target.minX - item.frame.minX) > 2 || abs(target.minY - item.frame.minY) > 2 {
            _ = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
        }
        let resized = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        var rawPosition: CFTypeRef?
        var actualPosition = CGPoint.zero
        if AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &rawPosition) == .success,
           let rawPosition, CFGetTypeID(rawPosition) == AXValueGetTypeID(),
           AXValueGetValue(rawPosition as! AXValue, .cgPoint, &actualPosition),
           abs(actualPosition.x - target.minX) > 2 || abs(actualPosition.y - target.minY) > 2,
           NSEvent.pressedMouseButtons == 0 {
            _ = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
        }
        return resized == .success
    }

    private func distance(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        abs(lhs.midX - rhs.midX) + abs(lhs.midY - rhs.midY)
    }
}

private extension CGRect {
    var area: CGFloat { isNull ? 0 : width * height }
}
