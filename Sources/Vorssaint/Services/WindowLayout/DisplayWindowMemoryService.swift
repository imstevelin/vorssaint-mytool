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

    private let queryQueue = DispatchQueue(label: "com.vorssaint.window-memory-query", qos: .utility)
    private let persistenceQueue = DispatchQueue(label: "com.vorssaint.window-memory-save", qos: .utility)
    private let axCache = DisplayWindowAXCache()
    private let profileStore = DisplayWindowProfileStore()
    private var storeLoaded = false
    private var removing = false
    private var loadingStore = false
    private var queryInFlight = false
    private var lifecycleGeneration = 0
    private var eventVersions: [pid_t: Int] = [:]
    private var eventWork: DispatchWorkItem?
    private var persistenceInFlight = false
    private var persistencePending = false
    private var activeProfiles: [String: Set<String>] = [:]
    private var persistedProfiles: [String: [String: RememberedWindowGeometry]] = [:]
    private var profileTouches: [String: [String: TimeInterval]] = [:]
    private lazy var windowEvents = DisplayWindowEventObserver { [weak self] pid in
        guard let self, self.timer != nil else { return }
        self.eventVersions[pid, default: 0] += 1
        self.queryQueue.async { [self] in self.axCache.invalidate(pid: pid) }
        guard self.eventWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.eventWork = nil
            self?.scan()
        }
        self.eventWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
    }
    private let defaults = UserDefaults.standard
    private var memory: DisplayWindowMemory
    private var salt: String
    private var observations: [CGWindowID: Observation] = [:]
    private var knownDisplays = Set<String>()
    private var knownDisplayGeometry: [String: CGRect] = [:]
    private var timer: Timer?
    private var displayObserver: NSObjectProtocol?
    private var scanResumeAt = Date.distantPast
    private var captureResumeAt = Date.distantPast
    private var transitionGeneration = 0
    private var pendingLayoutDisplays = Set<String>()
    private var interactionResumeAt = Date.distantPast
    private var interaction = DisplayWindowMemorySupport.Interaction()

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
        guard !removing else { return }
        let wanted = AppFeature.windowLayout.isAvailable
            && (defaults.bool(forKey: DefaultsKey.windowRememberSizes)
                || defaults.bool(forKey: DefaultsKey.windowRestoreDisplayLayout))
            && AXIsProcessTrusted() && SessionActivity.shared.isActive
        guard wanted else { stop(); return }
        guard timer == nil else { return }
        knownDisplayGeometry = displayGeometry()
        knownDisplays = Set(knownDisplayGeometry.keys)
        displayObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.displayConfigurationChanged() }
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.scan()
        }
        scan()
    }

    /// Called before process termination, after normal updates are stopped.
    /// Normal saving is asynchronous; this final barrier preserves the latest
    /// geometry even when its earlier completion has not reached main yet.
    func flush() {
        guard !removing else { return }
        guard storeLoaded else { queryQueue.sync {}; return }
        let snapshot = memory
        persistenceQueue.sync { [self] in
            if profileStore.save(snapshot) {
                if defaults.data(forKey: DefaultsKey.windowDisplayMemory) != nil {
                    defaults.removeObject(forKey: DefaultsKey.windowDisplayMemory)
                }
            } else if let data = try? JSONEncoder().encode(snapshot) {
                defaults.set(data, forKey: DefaultsKey.windowDisplayMemory)
            }
        }
    }

    func suspend() { stop() }

    /// Complete uninstall must drain background writes BEFORE removing the
    /// app container; later termination callbacks must not recreate it.
    func prepareForRemoval() {
        removing = true
        stop()
        queryQueue.sync {}
        persistenceQueue.sync {}
        profileStore.close()
    }

    private func stop() {
        lifecycleGeneration += 1
        eventWork?.cancel(); eventWork = nil
        windowEvents.stop()
        queryQueue.async { [self] in axCache.invalidate() }
        timer?.invalidate()
        timer = nil
        if let displayObserver { NotificationCenter.default.removeObserver(displayObserver) }
        displayObserver = nil
        observations.removeAll()
        interaction = DisplayWindowMemorySupport.Interaction()
        pendingLayoutDisplays.removeAll()
        transitionGeneration += 1
    }

    private var managedDisplayTransition = false
    func beginManagedDisplayTransition() {
        managedDisplayTransition = true
        transitionGeneration += 1
        // Keep the reconnect offer frozen until the final HiDPI geometry exists.
        // Clearing it here loses full-layout restoration for the new monitor.
    }
    func endManagedDisplayTransition() {
        managedDisplayTransition = false
        observations.removeAll()
        let geometry = displayGeometry()
        let current = Set(geometry.keys)
        pendingLayoutDisplays.formUnion(DisplayWindowMemorySupport.newlyConnected(
            previous: knownDisplays, current: current))
        pendingLayoutDisplays.formIntersection(current)
        knownDisplayGeometry = geometry
        knownDisplays = current
        captureResumeAt = Date().addingTimeInterval(2)
        // HiDPI has already verified its final mode. Only allow the apps a
        // short geometry settle, then restore instead of waiting for polling.
        scanResumeAt = Date().addingTimeInterval(0.2)
        let generation = transitionGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, self.transitionGeneration == generation, self.timer != nil else { return }
            self.scan()
        }
    }

    private func displayConfigurationChanged() {
        guard !managedDisplayTransition else { return }
        let geometry = displayGeometry()
        let current = Set(geometry.keys)
        guard geometry != knownDisplayGeometry else { return }
        knownDisplayGeometry = geometry
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
        guard timer != nil, !managedDisplayTransition, AXIsProcessTrusted(),
              SessionActivity.shared.isActive, Date() >= scanResumeAt else { return }
        let candidates = visibleWindows()
        trackInteraction(candidates)
        if NSEvent.pressedMouseButtons != 0 {
            interactionResumeAt = Date().addingTimeInterval(0.25)
            return // Track user geometry without AX traffic while dragging.
        }
        guard Date() >= interactionResumeAt, !queryInFlight else { return }
        guard storeLoaded else {
            guard !loadingStore else { return }
            loadingStore = true
            let hasLegacy = defaults.data(forKey: DefaultsKey.windowDisplayMemory) != nil
            queryQueue.async { [self] in
                let stored = profileStore.load()
                DispatchQueue.main.async { [self] in
                    if let stored, !hasLegacy { memory = stored }
                    storeLoaded = true
                    loadingStore = false
                    // Import legacy title profiles before allowing eviction.
                    if stored == nil || hasLegacy { persist() }
                    scan()
                }
            }
            return
        }
        let generation = lifecycleGeneration
        let transition = transitionGeneration
        let events = eventVersions
        queryInFlight = true
        let keys = candidates.map { DisplayWindowAXCache.Key(pid: $0.pid, id: $0.id) }
        let profileRequests = candidates.compactMap { window -> (String, String)? in
            guard let display = displayKey(window.screen), let title = window.titleDigest else { return nil }
            let key = DisplayWindowMemorySupport.profileKey(bundleID: window.bundleID, titleDigest: title)
            guard memory.displays[display]?.openingFrames?[key] == nil else { return nil }
            return (display, key)
        }
        queryQueue.async { [self] in
            let resolved = axCache.resolve(keys)
            var profiles: [String: [String: RememberedWindowGeometry]] = [:]
            for (display, key) in profileRequests {
                if let profile = profileStore.profile(display: display, key: key) {
                    profiles[display, default: [:]][key] = profile
                }
            }
            DispatchQueue.main.async { [self] in
                queryInFlight = false
                guard timer != nil, lifecycleGeneration == generation,
                      transitionGeneration == transition,
                      !managedDisplayTransition, SessionActivity.shared.isActive else { return }
                let current = visibleWindows()
                trackInteraction(current)
                if NSEvent.pressedMouseButtons != 0 {
                    interactionResumeAt = Date().addingTimeInterval(0.25)
                    return
                }
                // AX may have waited on another app. Never learn or restore a
                // geometry that moved while the query was outstanding.
                func identities(_ windows: [VisibleWindow]) -> [CGWindowID: DisplayWindowMemorySupport.SnapshotIdentity] {
                    Dictionary(windows.map { ($0.id, .init(pid: $0.pid, bundleID: $0.bundleID, frame: $0.frame)) },
                               uniquingKeysWith: { first, _ in first })
                }
                let valid = DisplayWindowMemorySupport.validSnapshotIDs(previous: identities(candidates),
                    current: identities(current), previousEvents: events, currentEvents: eventVersions)
                let complete = valid.count == candidates.count && valid.count == current.count
                windowEvents.update(resolved.elements)
                activeProfiles.removeAll(keepingCapacity: true)
                let now = ProcessInfo.processInfo.systemUptime
                for window in current {
                    guard let display = displayKey(window.screen) else { continue }
                    let key = DisplayWindowMemorySupport.profileKey(bundleID: window.bundleID, titleDigest: window.titleDigest)
                    activeProfiles[display, default: []].insert(key)
                    if memory.displays[display]?.openingFrames?[key] != nil || profiles[display]?[key] != nil {
                        profileTouches[display, default: [:]][key] = now
                    }
                }
                for (display, items) in profiles {
                    var stored = memory.displays[display] ?? RememberedDisplay()
                    stored.openingFrames = (stored.openingFrames ?? [:]).merging(items) { current, _ in current }
                    memory.displays[display] = stored
                    persistedProfiles[display, default: [:]].merge(items) { _, cold in cold }
                }
                trimHotProfiles()
                let queriedTitles = Dictionary(candidates.map { ($0.id, $0.titleDigest) }, uniquingKeysWith: { first, _ in first })
                let deferredOpenings = Set(current.compactMap { window -> CGWindowID? in
                    guard window.titleDigest != (queriedTitles[window.id] ?? nil),
                          let title = window.titleDigest, let display = displayKey(window.screen),
                          memory.displays[display]?.openingFrames?[
                            DisplayWindowMemorySupport.profileKey(bundleID: window.bundleID, titleDigest: title)] == nil
                    else { return nil }
                    return window.id
                })
                let eligibleWindows = current.filter {
                    valid.contains($0.id) && resolved.eligible.contains(.init(pid: $0.pid, id: $0.id))
                }
                processWindows(eligibleWindows, capturesLayout: complete, deferredOpeningWindows: deferredOpenings,
                               manualWindowIDs: Set(interaction.claimed.keys))
                for window in eligibleWindows {
                    guard let state = observations[window.id]?.state,
                          state.generation == transitionGeneration,
                          DisplayWindowMemorySupport.close(state.frame, window.frame) else { continue }
                    interaction.claimed.removeValue(forKey: window.id)
                }
                if !deferredOpenings.isEmpty {
                    // A title changed during AX I/O. Look up its cold profile
                    // promptly rather than consuming the restore with an app
                    // fallback before that document's profile is available.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in self?.scan() }
                }
            }
        }
    }

    private func trackInteraction(_ windows: [VisibleWindow]) {
        let current = Dictionary(windows.map {
            ($0.id, DisplayWindowMemorySupport.SnapshotIdentity(pid: $0.pid, bundleID: $0.bundleID, frame: $0.frame))
        }, uniquingKeysWith: { first, _ in first })
        let previous = observations.mapValues {
            DisplayWindowMemorySupport.SnapshotIdentity(pid: $0.pid, bundleID: $0.bundleID, frame: $0.state.frame)
        }
        interaction.update(current: current, previous: previous, pressed: NSEvent.pressedMouseButtons != 0)
    }

    private func processWindows(_ windows: [VisibleWindow], capturesLayout: Bool = true,
                                deferredOpeningWindows: Set<CGWindowID> = [],
                                manualWindowIDs: Set<CGWindowID> = []) {
        guard !managedDisplayTransition, AXIsProcessTrusted(), SessionActivity.shared.isActive,
              Date() >= scanResumeAt else { return }
        let now = Date()
        if NSEvent.pressedMouseButtons != 0 {
            interactionResumeAt = now.addingTimeInterval(0.25)
        }
        let interacting = now < interactionResumeAt
        if !interacting, !pendingLayoutDisplays.isEmpty {
            guard capturesLayout else { return } // Keep the full reconnect offer until the geometry settles.
            let displays = pendingLayoutDisplays
            pendingLayoutDisplays.removeAll()
            if defaults.bool(forKey: DefaultsKey.windowRestoreDisplayLayout) {
                restoreLayouts(on: displays, available: windows.filter { !manualWindowIDs.contains($0.id) })
                for window in windows where manualWindowIDs.contains(window.id) {
                    guard let display = displayKey(window.screen) else { continue }
                    observations[window.id] = Observation(pid: window.pid, bundleID: window.bundleID,
                        state: DisplayWindowObservation(display: display, frame: window.frame,
                            stableSince: now, generation: transitionGeneration), lastSeen: now)
                }
                captureResumeAt = now.addingTimeInterval(2)
                return // Never capture the pre-placement WindowServer snapshot.
            }
        }
        let rememberSizes = defaults.bool(forKey: DefaultsKey.windowRememberSizes)
        var appliedFrame = false
        var dirty = false
        defer { if dirty { persist() } }
        if rememberSizes {
            for window in windows {
                guard let display = displayKey(window.screen) else { continue }
                var previous = observations[window.id]
                if previous?.pid != window.pid || previous?.bundleID != window.bundleID {
                    previous = nil // WindowServer can recycle a closed window's ID.
                }
                if manualWindowIDs.contains(window.id) {
                    // A user drag consumes any pending opening/topology restore.
                    previous = Observation(pid: window.pid, bundleID: window.bundleID,
                        state: DisplayWindowObservation(display: display, frame: window.frame,
                            stableSince: now, generation: transitionGeneration), lastSeen: now)
                }
                let decision = DisplayWindowMemorySupport.action(
                    previous: previous?.state, display: display, frame: window.frame,
                    now: now, interacting: interacting, generation: transitionGeneration)
                if decision == .wait { continue }
                if decision == .restore {
                    if deferredOpeningWindows.contains(window.id) { continue }
                    var acceptedFrame = window.frame
                    var restored = false
                    var matchesSaved = false
                    if let desired = DisplayWindowMemorySupport.openingFrame(
                        in: memory.displays[display], bundleID: window.bundleID,
                        titleDigest: window.titleDigest, currentFrame: window.frame,
                        displayBounds: displayBounds(window.screen), usableBounds: usableBounds(window.screen)) {
                        matchesSaved = DisplayWindowMemorySupport.close(window.frame, desired)
                        if !matchesSaved {
                            restored = setFrame(desired, for: window)
                            if restored { acceptedFrame = desired; appliedFrame = true }
                        }
                    }
                    // Consume the transition even if the app rejects the request.
                    // Retrying a stale frame fights manual moves and app size limits.
                    observations[window.id] = Observation(
                        pid: window.pid, bundleID: window.bundleID,
                        state: DisplayWindowObservation(display: display, frame: acceptedFrame,
                                                        stableSince: now, learned: restored || matchesSaved, generation: transitionGeneration), lastSeen: now)
                    continue
                }
                var observation = previous!
                observation.lastSeen = now
                if !DisplayWindowMemorySupport.close(window.frame, observation.state.frame) || interacting {
                    observation.state.frame = window.frame
                    observation.state.stableSince = now
                    observation.state.learned = false
                } else if decision == .learn, now >= captureResumeAt {
                    var stored = memory.displays[display] ?? RememberedDisplay()
                    DisplayWindowMemorySupport.rememberOpeningFrame(
                        window.frame, in: &stored, bundleID: window.bundleID,
                        titleDigest: window.titleDigest, displayBounds: displayBounds(window.screen),
                        usableBounds: usableBounds(window.screen))
                    if memory.displays[display] != stored {
                        memory.displays[display] = stored
                        dirty = true
                    }
                    observation.state.learned = true
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

        if capturesLayout, defaults.bool(forKey: DefaultsKey.windowRestoreDisplayLayout), now >= captureResumeAt {
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
                let canonical = DisplayWindowMemorySupport.canonicalLayout(windows)
                if DisplayWindowMemorySupport.canonicalLayout(stored.windows) != canonical {
                    stored.windows = windows // Retain the original matching order when geometry changes.
                    memory.displays[display] = stored
                    changed = true
                }
            }
            dirty = dirty || changed
        }
    }

    private func restoreLayouts(on displays: Set<String>, available windows: [VisibleWindow]) {
        guard !displays.isEmpty else { return }
        var available = windows
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
                                                        stableSince: Date(), generation: transitionGeneration), lastSeen: Date())
                }
            }
        }
    }

    private func persist() {
        guard !removing else { return }
        guard !persistenceInFlight else { persistencePending = true; return }
        persistenceInFlight = true
        persistencePending = false
        let snapshot = memory
        persistenceQueue.async { [self] in
            let saved = profileStore.save(snapshot)
            if saved {
                if defaults.data(forKey: DefaultsKey.windowDisplayMemory) != nil {
                    defaults.removeObject(forKey: DefaultsKey.windowDisplayMemory)
                }
            } else if let data = try? JSONEncoder().encode(snapshot) {
                // Disk unavailable: retain the complete legacy representation.
                defaults.set(data, forKey: DefaultsKey.windowDisplayMemory)
            }
            DispatchQueue.main.async { [self] in
                persistenceInFlight = false
                if saved {
                    for (display, stored) in snapshot.displays {
                        persistedProfiles[display, default: [:]].merge(stored.openingFrames ?? [:]) { _, committed in committed }
                    }
                    trimHotProfiles()
                }
                if persistencePending { persist() }
            }
        }
    }

    private func trimHotProfiles() {
        for (display, stored) in memory.displays {
            let titles = (stored.openingFrames ?? [:]).keys.filter { !$0.hasSuffix(":") }
            let removable = titles.filter { !(activeProfiles[display] ?? []).contains($0) }.sorted {
                (profileTouches[display]?[$0] ?? 0) < (profileTouches[display]?[$1] ?? 0)
            }
            for key in removable.prefix(max(0, titles.count - 256)) {
                // Only evict a version successfully committed to cold storage.
                guard stored.openingFrames?[key] == persistedProfiles[display]?[key] else { continue }
                memory.displays[display]?.openingFrames?.removeValue(forKey: key)
                memory.displays[display]?.sizes.removeValue(forKey: key)
                profileTouches[display]?.removeValue(forKey: key)
                persistedProfiles[display]?.removeValue(forKey: key)
            }
        }
    }

    private func digest(_ title: String?) -> String? {
        guard let title, !title.isEmpty else { return nil }
        return SHA256.hash(data: Data((salt + title).utf8))
            .map { String(format: "%02x", $0) }.joined()
    }

    private func visibleWindows() -> [VisibleWindow] {
        let entries = WindowServerSnapshot.onScreen()
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

    private func eligible(_ window: AXUIElement) -> Bool {
        AXUIElementSetMessagingTimeout(window, 0.1)
        func attribute(_ name: String) -> CFTypeRef? {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(window, name as CFString, &value) == .success else { return nil }
            return value
        }
        var resizable = DarwinBoolean(false)
        _ = AXUIElementIsAttributeSettable(window, kAXSizeAttribute as CFString, &resizable)
        var minimizeEnabled: CFTypeRef?
        if let button = attribute(kAXMinimizeButtonAttribute),
           CFGetTypeID(button) == AXUIElementGetTypeID() {
            let element = button as! AXUIElement
            AXUIElementSetMessagingTimeout(element, 0.1)
            _ = AXUIElementCopyAttributeValue(element, kAXEnabledAttribute as CFString, &minimizeEnabled)
        }
        return DisplayWindowMemorySupport.eligibleWindow(
            role: attribute(kAXRoleAttribute) as? String,
            subrole: attribute(kAXSubroleAttribute) as? String,
            modal: attribute(kAXModalAttribute) as? Bool ?? false,
            resizable: resizable.boolValue,
            hasMinimizeButton: minimizeEnabled as? Bool == true)
            && (attribute("AXFullScreen") as? Bool != true)
    }

    private func displayGeometry() -> [String: CGRect] {
        Dictionary(NSScreen.screens.compactMap { screen in
            displayKey(screen).map { ($0, usableBounds(screen)) }
        }, uniquingKeysWith: { first, _ in first })
    }

    private func displayKey(_ screen: NSScreen) -> String? {
        guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                as? CGDirectDisplayID else { return nil }
        let physical = VirtualHiDPIService.physicalDisplay(for: id)
        if CGDisplayIsBuiltin(physical) != 0 { return "builtin" }
        return "external:\(CGDisplayVendorNumber(physical)):\(CGDisplayModelNumber(physical)):\(CGDisplaySerialNumber(physical))"
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
        guard eligible(window) else { return false }
        var rawCurrentPosition: CFTypeRef?
        var rawCurrentSize: CFTypeRef?
        var currentPosition = CGPoint.zero
        var currentSize = CGSize.zero
        let positionStatus = AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &rawCurrentPosition)
        let sizeStatus = AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &rawCurrentSize)
        guard positionStatus != .invalidUIElement, positionStatus != .cannotComplete,
              sizeStatus != .invalidUIElement, sizeStatus != .cannotComplete else { return false }
        if positionStatus == .success, sizeStatus == .success,
           let rawCurrentPosition, let rawCurrentSize,
           CFGetTypeID(rawCurrentPosition) == AXValueGetTypeID(), CFGetTypeID(rawCurrentSize) == AXValueGetTypeID(),
           AXValueGetValue(rawCurrentPosition as! AXValue, .cgPoint, &currentPosition),
           AXValueGetValue(rawCurrentSize as! AXValue, .cgSize, &currentSize),
           !DisplayWindowMemorySupport.close(CGRect(origin: currentPosition, size: currentSize), item.frame) {
            return false
        }
        // Apps exposing a writable but unreadable geometry attribute retain
        // the original compatibility path, using the freshly verified WS frame.
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
