// swift-tools-version:5.9
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import PackageDescription

let package = Package(
    name: "Vorssaint",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "VirtualDisplayBridge", path: "Sources/VirtualDisplayBridge",
                cSettings: [.unsafeFlags(["-fno-objc-arc"])],
                linkerSettings: [.linkedFramework("CoreGraphics"), .linkedFramework("Foundation")]),
        .target(name: "DisplayRecoverySupport", path: "Sources/DisplayRecoverySupport"),
        .executableTarget(name: "VirtualDisplayHost", dependencies: ["VirtualDisplayBridge", "DisplayRecoverySupport"],
                          path: "Sources/VirtualDisplayHost"),
        .executableTarget(name: "DisplayRecoveryHelper", dependencies: ["DisplayRecoverySupport"],
                          path: "Sources/DisplayRecoveryHelper"),
        .systemLibrary(
            name: "HIDEventSystem",
            path: "Sources/HIDEventSystem"
        ),
        .systemLibrary(
            name: "VMStatisticsCompat",
            path: "Sources/VMStatisticsCompat"
        ),
        .executableTarget(
            name: "Vorssaint",
            dependencies: ["VMStatisticsCompat", "HIDEventSystem", "VirtualDisplayBridge", "DisplayRecoverySupport"],
            path: "Sources/Vorssaint"
        )
    ]
)
