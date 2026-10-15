// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint contributors

import CoreGraphics
import Foundation

enum DisplayWindowMemoryTests {
    static func run(_ suite: TestSuite) {
        interactionTests(suite)
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
