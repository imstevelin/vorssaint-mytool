// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint contributors

import AppKit
import ApplicationServices

/// Used only on the window-memory serial query queue. Stable AX properties
/// are cached; modal/full-screen state is still read every pass, so an app
/// lacking notifications cannot make a dialog eligible for learning.
final class DisplayWindowAXCache {
    struct Key: Hashable { let pid: pid_t; let id: CGWindowID }
    private struct Entry { let element: AXUIElement; let eligible: Bool; let readAt: TimeInterval }
    private var entries: [Key: Entry] = [:]
    private var clock: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    private var readWindows: (pid_t) -> [CGWindowID: AXUIElement] = DisplayWindowAXCache.windows
    private var stableEligibility: (AXUIElement) -> Bool = DisplayWindowAXCache.stableEligible
    private var dynamicEligibility: (AXUIElement) -> Bool = DisplayWindowAXCache.dynamicEligible

    init() {}
    init(clock: @escaping () -> TimeInterval,
         windows: @escaping (pid_t) -> [CGWindowID: AXUIElement],
         stableEligibility: @escaping (AXUIElement) -> Bool,
         dynamicEligibility: @escaping (AXUIElement) -> Bool) {
        self.clock = clock; self.readWindows = windows
        self.stableEligibility = stableEligibility; self.dynamicEligibility = dynamicEligibility
    }

    func invalidate(pid: pid_t? = nil) {
        if let pid { entries = entries.filter { $0.key.pid != pid } }
        else { entries.removeAll() }
    }

    func resolve(_ keys: [Key]) -> (eligible: Set<Key>, elements: [pid_t: [AXUIElement]]) {
        let now = clock()
        let wanted = Set(keys)
        entries = entries.filter { wanted.contains($0.key) }
        var appWindows: [pid_t: [CGWindowID: AXUIElement]] = [:]
        var accepted = Set<Key>()
        var elements: [pid_t: [AXUIElement]] = [:]
        for key in keys {
            var cached = entries[key]
            if cached == nil || now - cached!.readAt >= 5 {
                if appWindows[key.pid] == nil {
                    appWindows[key.pid] = readWindows(key.pid)
                }
                guard let window = appWindows[key.pid]?[key.id] else { entries.removeValue(forKey: key); continue }
                let eligible = stableEligibility(window)
                cached = Entry(element: window, eligible: eligible, readAt: now)
                entries[key] = cached
            }
            guard let cached else { continue }
            elements[key.pid, default: []].append(cached.element)
            guard cached.eligible else {
                // A disabled minimize button or a temporarily fixed window
                // can become eligible without emitting a notification.
                entries.removeValue(forKey: key)
                continue
            }
            if dynamicEligibility(cached.element) { accepted.insert(key) }
            else { entries.removeValue(forKey: key) }

        }
        return (accepted, elements)
    }

    private static func windows(_ pid: pid_t) -> [CGWindowID: AXUIElement] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.1)
        var raw: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &raw)
        return Dictionary((raw as? [AXUIElement] ?? []).compactMap {
            window -> (CGWindowID, AXUIElement)? in
            guard let id = AXWindowResolver.windowID(for: window) else { return nil }
            return (id, window)
        }, uniquingKeysWith: { first, _ in first })
    }

    private static func stableEligible(_ window: AXUIElement) -> Bool {
        AXUIElementSetMessagingTimeout(window, 0.1)
        return DisplayWindowMemorySupport.eligibleWindow(
            role: attribute(kAXRoleAttribute, of: window) as? String,
            subrole: attribute(kAXSubroleAttribute, of: window) as? String,
            modal: false, resizable: true, hasMinimizeButton: true)
    }

    private static func dynamicEligible(_ window: AXUIElement) -> Bool {
        var resizable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(window, kAXSizeAttribute as CFString, &resizable) == .success,
              resizable.boolValue,
              let button = attribute(kAXMinimizeButtonAttribute, of: window),
              CFGetTypeID(button) == AXUIElementGetTypeID(),
              attribute(kAXEnabledAttribute, of: button as! AXUIElement) as? Bool == true else { return false }
        for name in [kAXModalAttribute, "AXFullScreen"] {
            var value: CFTypeRef?
            let status = AXUIElementCopyAttributeValue(window, name as CFString, &value)
            // Missing optional attributes remain compatible with the original
            // implementation, but defunct/unresponsive cached handles do not.
            guard status == .success || status == .attributeUnsupported || status == .noValue else { return false }
            if value as? Bool == true { return false }
        }
        return true
    }

    private static func attribute(_ name: String, of element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
}

/// Registrations can themselves wait on another app, so they use a serial
/// background queue. Delivery remains on main. A retained callback context is
/// released on main only after its source has been removed, avoiding a race
/// between notification delivery and observer teardown.
final class DisplayWindowEventObserver {
    private final class Subscription {
        let pid: pid_t
        let changed: (pid_t) -> Void
        var observer: AXObserver?
        var elements: [AXUIElement] = []
        init(pid: pid_t, changed: @escaping (pid_t) -> Void) { self.pid = pid; self.changed = changed }

    }
    private let queue = DispatchQueue(label: "com.vorssaint.window-memory-events", qos: .utility)
    private var subscriptions: [pid_t: Subscription] = [:] // queue only.
    private let changed: (pid_t) -> Void
    init(changed: @escaping (pid_t) -> Void) { self.changed = changed }

    func update(_ elements: [pid_t: [AXUIElement]]) {
        queue.async { [self] in updateOnQueue(elements) }
    }

    private func retire(_ subscription: Subscription) {
        guard let observer = subscription.observer else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        subscription.observer = nil
        DispatchQueue.main.async { Unmanaged.passUnretained(subscription).release() }
    }

    private func updateOnQueue(_ elements: [pid_t: [AXUIElement]]) {
        for (pid, subscription) in subscriptions where elements[pid] == nil {
            retire(subscription)
            subscriptions.removeValue(forKey: pid)
        }
        for (pid, windows) in elements {
            let subscription: Subscription
            if let existing = subscriptions[pid] { subscription = existing }
            else {
                subscription = Subscription(pid: pid, changed: changed)
                let callback: AXObserverCallback = { _, _, _, context in
                    guard let context else { return }
                    let subscription = Unmanaged<Subscription>.fromOpaque(context).takeUnretainedValue()
                    subscription.changed(subscription.pid)
                }
                var observer: AXObserver?
                guard AXObserverCreate(pid, callback, &observer) == .success, let observer else { continue }
                subscription.observer = observer
                subscriptions[pid] = subscription
                let context = Unmanaged.passRetained(subscription).toOpaque()
                let app = AXUIElementCreateApplication(pid)
                for name in [kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification] {
                    AXObserverAddNotification(observer, app, name as CFString, context)
                }
                CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
            }
            guard let observer = subscription.observer else { continue }
            // Keep subscriptions stable when the same AX handles are returned.
            let removed = subscription.elements.filter { old in !windows.contains { CFEqual(old, $0) } }
            let added = windows.filter { new in !subscription.elements.contains { CFEqual(new, $0) } }
            let names = [kAXMovedNotification, kAXResizedNotification, kAXUIElementDestroyedNotification,
                         kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification]
            for window in removed {
                for name in names { AXObserverRemoveNotification(observer, window, name as CFString) }
            }
            for window in added {
                for name in names {
                    AXObserverAddNotification(observer, window, name as CFString, Unmanaged.passUnretained(subscription).toOpaque())
                }
            }
            subscription.elements = windows
        }
    }

    func stop() {
        queue.async { [self] in
            subscriptions.values.forEach(retire)
            subscriptions.removeAll()
        }
    }

    deinit {
        // Queued operations retain this owner, so none can still mutate the
        // dictionary here. Deinit may itself run at the end of a queue job.
        subscriptions.values.forEach(retire)
    }
}
