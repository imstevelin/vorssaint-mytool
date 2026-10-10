// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint contributors

import CoreGraphics

enum DisplayWindowMemoryTests {
    static func run(_ suite: TestSuite) {
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
}
