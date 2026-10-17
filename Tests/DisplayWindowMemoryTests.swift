// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint contributors

import CoreGraphics
import Foundation

enum DisplayWindowMemoryTests {
    static func run(_ suite: TestSuite) {
        interactionTests(suite)
        normalWindowTests(suite)
        openingGeometryTests(suite)
        DisplayWindowMemoryScanTests.run(suite)
        suite.expect(Defaults.registeredDefaults[DefaultsKey.windowRememberSizes] as? Bool == false
            && Defaults.registeredDefaults[DefaultsKey.windowRestoreDisplayLayout] as? Bool == false,
            "display memory starts off until explicitly enabled")
        let exportKeys = SettingsBackupSupport.exportKeys()
        suite.expect(exportKeys.contains(DefaultsKey.windowRememberSizes)
            && exportKeys.contains(DefaultsKey.windowRestoreDisplayLayout)
            && !exportKeys.contains(DefaultsKey.windowDisplayMemory)
            && !exportKeys.contains(DefaultsKey.windowDisplayMemorySalt),
            "backups carry display-memory choices but no machine geometry or private title digest salt")
        for key in [DefaultsKey.windowRememberSizes, DefaultsKey.windowRestoreDisplayLayout] {
            suite.expect(AppFeature.windowLayout.monitorsPermissionChanges(
                edgeSnapDisabledZones: "",
                boolFor: { $0 == key }),
                "an enabled display-memory option keeps Accessibility permission monitoring active")
        }
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let visible = CGRect(x: 0, y: 24, width: 1920, height: 1000)
        let display = CGRect(x: 1920, y: 0, width: 1920, height: 1080)
        let usable = DisplayWindowMemorySupport.usableBounds(
            screenFrame: screen, visibleFrame: visible, displayBounds: display)
        suite.expect(usable == CGRect(x: 1920, y: 56, width: 1920, height: 1000),
                     "display memory converts AppKit visible frame to CG coordinates")

        let restored = DisplayWindowMemorySupport.fittedFrame(
            CGRect(x: 3000, y: 850, width: 1300, height: 1000), within: usable)
        suite.expect(restored == CGRect(x: 2540, y: 56, width: 1300, height: 1000),
                     "restoration adjusts both axes to fit around the Dock and menu bar")
        suite.expect(DisplayWindowMemorySupport.newlyConnected(
            previous: ["builtin"], current: ["builtin", "external:1"]) == ["external:1"],
            "only newly connected displays receive layout restoration")
        let saved = RememberedWindow(bundleID: "com.example.app", titleDigest: "abc",
                                     relativeFrame: CGRect(x: 10, y: 10, width: 300, height: 400))
        suite.expect(DisplayWindowMemorySupport.matches(saved, bundleID: "com.example.app", titleDigest: "abc")
            && !DisplayWindowMemorySupport.matches(saved, bundleID: "com.example.other", titleDigest: "abc")
            && !DisplayWindowMemorySupport.matches(saved, bundleID: "com.example.app", titleDigest: "different"),
            "layout restoration never assigns a saved window to the wrong app or known title")
    }

    private static func openingGeometryTests(_ suite: TestSuite) {
        let display = CGRect(x: 1920, y: -300, width: 2560, height: 1440)
        let usable = CGRect(x: 1920, y: -275, width: 2560, height: 1340)
        let original = CGRect(x: 2110, y: -185, width: 1800, height: 1100)
        let app = "com.example.browser"
        var stored = RememberedDisplay()
        func remember(_ frame: CGRect) {
            DisplayWindowMemorySupport.rememberOpeningFrame(frame, in: &stored,
                bundleID: app, titleDigest: "tab-one", displayBounds: display, usableBounds: usable)
        }
        func restore(_ current: CGRect, title: String? = "tab-one",
                     bounds: CGRect? = nil, workArea: CGRect? = nil) -> CGRect? {
            DisplayWindowMemorySupport.openingFrame(in: stored, bundleID: app,
                titleDigest: title, currentFrame: current, displayBounds: bounds ?? display,
                usableBounds: workArea ?? usable)
        }
        remember(original)
        let opened = CGRect(x: 2200, y: 100, width: 1800, height: 1100)
        suite.expect(restore(opened) == original,
                     "reopening restores position even when the size already matches, preserving the Dock gap")
        suite.expect(restore(opened, title: "tab-two") == original,
                     "browser title changes use the last app frame on the same display")
        let relocatedDisplay = display.offsetBy(dx: -3000, dy: 500)
        suite.expect(restore(opened, bounds: relocatedDisplay,
                             workArea: usable.offsetBy(dx: -3000, dy: 500)) == original.offsetBy(dx: -3000, dy: 500),
                     "saved positions follow the physical display when its desktop origin changes")
        suite.expect(DisplayWindowMemorySupport.openingFrame(in: stored, bundleID: "other.app",
            titleDigest: "tab-one", currentFrame: opened, displayBounds: display, usableBounds: usable) == nil,
            "opening geometry cannot leak to another application")
        let beforeTile = stored
        remember(CGRect(x: usable.minX, y: usable.minY, width: usable.width / 2, height: usable.height))
        suite.expect(stored == beforeTile, "temporary tiling retains the last normal opening frame")
        remember(usable)
        suite.expect(restore(opened) == usable,
                     "windowed maximum replaces a stale smaller profile and reopens without right or bottom gaps")
        let smallerDisplay = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let smallerUsable = CGRect(x: 0, y: 38, width: 1512, height: 900)
        suite.expect(restore(opened, bounds: smallerDisplay, workArea: smallerUsable) == smallerUsable,
                     "maximized windows follow the current work area after resolution or Dock changes")
        let insetMaximum = usable.insetBy(dx: 8, dy: 8)
        remember(insetMaximum)
        suite.expect(restore(opened) == insetMaximum,
                     "near-maximum manual frames retain their exact insets instead of being discarded as tiles")
        remember(original)
        let smaller = restore(opened, bounds: smallerDisplay, workArea: smallerUsable)
        suite.expect(smaller.map { smallerUsable.contains($0) } == true,
                     "frames learned at a larger resolution still fit the current work area")
        let legacyJSON = #"{"windows":[],"sizes":{"com.example.browser:":[900,600]}}"#
        let legacy = try? JSONDecoder().decode(RememberedDisplay.self, from: Data(legacyJSON.utf8))
        suite.expect(legacy != nil && legacy?.openingFrames == nil,
                     "size-only preferences decode without losing saved layouts")
        suite.expect(DisplayWindowMemorySupport.openingFrame(in: legacy, bundleID: app,
            titleDigest: nil, currentFrame: usable, displayBounds: display, usableBounds: usable) == nil,
            "a legacy smaller size never shrinks a window opened maximized")
        suite.expect(DisplayWindowMemorySupport.openingFrame(in: legacy, bundleID: app,
            titleDigest: nil, currentFrame: opened, displayBounds: display, usableBounds: usable)?.size
                == CGSize(width: 900, height: 600),
            "ordinary legacy sizes remain usable until a full frame is learned")
        let encoded = try? JSONEncoder().encode(stored)
        let decoded = encoded.flatMap { try? JSONDecoder().decode(RememberedDisplay.self, from: $0) }
        suite.expect(decoded == stored, "opening position, size and zoom state survive preference round trips")
    }

    private static func normalWindowTests(_ suite: TestSuite) {
        let eligible = DisplayWindowMemorySupport.eligibleWindow
        suite.expect(eligible("AXWindow", "AXStandardWindow", false, true, true),
                     "resizable document windows support display memory")
        for subrole in ["AXDialog", "AXSystemDialog", "AXFloatingWindow", "AXUnknown", nil] {
            suite.expect(!eligible("AXWindow", subrole, false, true, true),
                         "auxiliary windows cannot receive or overwrite main-window sizes")
        }
        suite.expect(!eligible("AXSheet", "AXStandardWindow", false, true, true)
            && !eligible("AXWindow", "AXStandardWindow", true, true, true)
            && !eligible("AXWindow", "AXStandardWindow", false, false, true)
            && !eligible("AXWindow", "AXStandardWindow", false, true, false),
            "sheets, modal dialogs, fixed windows and panels are excluded")
        let bounds = CGRect(x: 1920, y: 25, width: 1920, height: 1000)
        for size in [CGSize(width: 960, height: 1000), CGSize(width: 940, height: 980),
                     CGSize(width: 1920, height: 1000), CGSize(width: 960, height: 500),
                     CGSize(width: 640, height: 1000)] {
            suite.expect(DisplayWindowMemorySupport.arrangedSize(size, within: bounds),
                         "tile and maximized geometry cannot overwrite normal opening sizes")
        }
        suite.expect(!DisplayWindowMemorySupport.arrangedSize(CGSize(width: 850, height: 650), within: bounds),
                     "ordinary manual sizes are still learned")
        let now = Date(timeIntervalSince1970: 100)
        let frame = CGRect(x: 50, y: 50, width: 800, height: 600)
        let previous = DisplayWindowObservation(display: "builtin", frame: frame, stableSince: now)
        suite.expect(DisplayWindowMemorySupport.action(previous: previous, display: "builtin", frame: frame,
            now: now, interacting: false, generation: 1) == .restore,
            "open windows restore on topology or resolution changes even on the same display")
        suite.expect(DisplayWindowMemorySupport.action(previous: previous, display: "builtin", frame: frame,
            now: now, interacting: true, generation: 1) == .wait,
            "topology changes still wait for manual interaction to finish")
        var consumed = previous
        consumed.generation = 1
        suite.expect(DisplayWindowMemorySupport.action(previous: consumed, display: "builtin", frame: frame,
            now: now, interacting: false, generation: 1) == .observe,
            "topology restore is consumed once instead of fighting later manual changes")
    }

    private static func interactionTests(_ suite: TestSuite) {
        let now = Date(timeIntervalSince1970: 100)
        let original = CGRect(x: 10, y: 50, width: 800, height: 600)
        let observation = DisplayWindowObservation(display: "builtin", frame: original,
                                                   stableSince: now)
        suite.expect(DisplayWindowMemorySupport.action(previous: nil, display: "builtin",
            frame: original, now: now, interacting: false) == .restore,
            "a newly opened window gets one immediate restore opportunity")
        for previous in [nil, observation] {
            suite.expect(DisplayWindowMemorySupport.action(previous: previous, display: "external",
                frame: original, now: now, interacting: true) == .wait,
                "new windows and display transitions wait while the user drags")
        }
        suite.expect(DisplayWindowMemorySupport.action(previous: observation, display: "external",
            frame: original, now: now, interacting: false) == .restore,
            "a display transition restores after the drag ends")
        let moved = original.offsetBy(dx: 200, dy: 100)
        let resized = CGRect(origin: original.origin, size: CGSize(width: 500, height: 400))
        for frame in [original, moved, resized] {
            for seconds in [0.5, 3.0, 6.0, 9.0, 60.0] {
                suite.expect(DisplayWindowMemorySupport.action(previous: observation, display: "builtin",
                    frame: frame, now: now.addingTimeInterval(seconds), interacting: false) != .restore,
                    "same-display polling never reapplies a stale frame, including rejected sizes")
            }
        }
        suite.expect(DisplayWindowMemorySupport.action(previous: observation, display: "builtin",
            frame: original, now: now.addingTimeInterval(1), interacting: false) == .observe,
            "learning waits for geometry to settle rather than overwriting a profile immediately")
        suite.expect(DisplayWindowMemorySupport.action(previous: observation, display: "builtin",
            frame: original, now: now.addingTimeInterval(1.5), interacting: false) == .learn,
            "stable accepted geometry is learned after 1.5 seconds")
        suite.expect(DisplayWindowMemorySupport.action(previous: observation, display: "builtin",
            frame: resized, now: now.addingTimeInterval(3), interacting: false) == .observe,
            "manual resizing resets the quiet period before the new size is learned")
        suite.expect(DisplayWindowMemorySupport.action(previous: observation, display: "builtin",
            frame: original, now: now.addingTimeInterval(3), interacting: true) == .observe,
            "mouse interaction suppresses profile learning even with stable geometry")
        var learned = observation
        learned.learned = true
        suite.expect(DisplayWindowMemorySupport.action(previous: learned, display: "builtin",
            frame: original, now: now.addingTimeInterval(60), interacting: false) == .observe,
            "unchanged windows do not rewrite preferences on every fast scan")
    }
}

/// Run the production scan against deterministic window and input boundaries.
enum DisplayWindowMemoryScanTests {
    struct Screen {
        let key: String
        let bounds: CGRect
        let usable: CGRect
    }
    typealias NSScreen = Screen
    enum NSEvent { static var pressedMouseButtons = 0 }
    final class SessionActivity {
        static let shared = SessionActivity()
        var isActive = true
    }
    struct Preferences {
        var sizes = true
        var layouts = false
        func bool(forKey key: String) -> Bool {
            key == DefaultsKey.windowRememberSizes ? sizes : layouts
        }
    }
    class Fixture {
        var managedDisplayTransition = false
        var scanResumeAt = Date.distantPast
        var captureResumeAt = Date.distantPast
        var interactionResumeAt = Date.distantPast
        var transitionGeneration = 0
        var pendingLayoutDisplays = Set<String>()
        var defaults = Preferences()
        var memory = DisplayWindowMemory()
        var observations: [CGWindowID: Observation] = [:]
        var windows: [VisibleWindow] = []
        var writes: [CGRect] = []
        var persists = 0
        func AXIsProcessTrusted() -> Bool { true }
        func visibleWindows() -> [VisibleWindow] { windows }
        func displayKey(_ screen: Screen) -> String? { screen.key }
        func displayBounds(_ screen: Screen) -> CGRect { screen.bounds }
        func usableBounds(_ screen: Screen) -> CGRect { screen.usable }
        func setFrame(_ frame: CGRect, for window: VisibleWindow) -> Bool {
            writes.append(frame)
            windows = windows.map {
                $0.id == window.id ? VisibleWindow(id: $0.id, pid: $0.pid, bundleID: $0.bundleID,
                    titleDigest: $0.titleDigest, frame: frame, screen: $0.screen) : $0
            }
            return true
        }
        func restoreLayouts(on displays: Set<String>, available windows: [VisibleWindow]) {}
        func persist() { persists += 1 }
    }
    static func run(_ suite: TestSuite) {
        NSEvent.pressedMouseButtons = 0
        let screen = Screen(key: "external", bounds: CGRect(x: 1600, y: 0, width: 2560, height: 1440),
                            usable: CGRect(x: 1600, y: 25, width: 2560, height: 1340))
        let app = "com.example.browser"
        func window(_ frame: CGRect, id: CGWindowID = 10) -> VisibleWindow {
            VisibleWindow(id: id, pid: 123, bundleID: app, titleDigest: nil, frame: frame, screen: screen)
        }
        let original = CGRect(x: 1800, y: 125, width: 1800, height: 1100)
        let service = Service()
        service.windows = [window(original)]
        service.scan() // Consume first appearance, then let the geometry settle.
        service.observations[10]?.state.stableSince = Date().addingTimeInterval(-2)
        service.scan()
        suite.expect(service.persists == 1 && service.memory.displays[screen.key]?.openingFrames != nil,
                     "production scan learns the complete stable opening frame")
        service.windows = [window(original.offsetBy(dx: 90, dy: 100), id: 11)]
        service.scan()
        suite.expect(service.writes == [original],
                     "production scan restores a reopened window's position even without a size change")
        let manual = original.offsetBy(dx: 30, dy: 20)
        service.windows = [window(manual, id: 11)]
        service.scan(); service.scan()
        suite.expect(service.writes == [original], "polling never snaps a manual move back after restoration")
        service.observations[11]?.state.stableSince = Date().addingTimeInterval(-2)
        service.scan()
        suite.expect(service.memory.displays[screen.key]?.openingFrames?[app + ":"]?.relativeFrame
            == manual.offsetBy(dx: -screen.bounds.minX, dy: -screen.bounds.minY),
            "a settled manual position replaces the last opening position")
        service.windows = [window(screen.usable, id: 11)]
        service.scan()
        service.observations[11]?.state.stableSince = Date().addingTimeInterval(-2)
        service.scan()
        suite.expect(service.memory.displays[screen.key]?.openingFrames?[app + ":"]?.maximized == true,
                     "production scan learns windowed maximum instead of retaining the older normal size")
        service.windows = [window(original, id: 12)]
        NSEvent.pressedMouseButtons = 1
        service.scan()
        suite.expect(service.writes.count == 1 && service.observations[12] == nil,
                     "reopening while dragging defers the restore and leaves its opportunity unconsumed")
        NSEvent.pressedMouseButtons = 0
        service.interactionResumeAt = .distantPast
        service.scan()
        suite.expect(service.writes.last == screen.usable && service.writes.count == 2,
                     "after interaction ends a reopened window returns to its saved maximum")
        service.scan()
        suite.expect(service.writes.count == 2, "a successful maximized restore is applied only once")
        let deferred = Service()
        deferred.windows = [window(original, id: 30)]
        deferred.processWindows(deferred.windows, deferredOpeningWindows: [30])
        suite.expect(deferred.observations[30] == nil,
                     "a title changing during a cold lookup does not consume its document-specific restore")
        deferred.scan()
        suite.expect(deferred.observations[30] != nil,
                     "the next resolved title snapshot receives its original one-shot restore opportunity")
        let batch = Service()
        batch.defaults.layouts = true
        batch.windows = [window(original, id: 20), window(original.offsetBy(dx: 40, dy: 40), id: 21)]
        batch.scan()
        batch.observations[20]?.state.stableSince = Date().addingTimeInterval(-2)
        batch.observations[21]?.state.stableSince = Date().addingTimeInterval(-2)
        let beforeBatch = batch.persists
        batch.scan()
        suite.expect(batch.persists == beforeBatch + 1,
                     "learning several stable windows plus a layout persists only once per pass")
        let beforeFocus = batch.persists
        batch.windows.reverse()
        batch.scan()
        suite.expect(batch.persists == beforeFocus,
                     "the production scan does not persist geometry when only WindowServer Z-order changes")

    }
}
