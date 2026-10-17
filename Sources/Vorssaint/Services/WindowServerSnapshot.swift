// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint contributors

import AppKit

/// One snapshot per main-queue turn: mirrored islands and window memory can
/// share a system query without introducing a time-based stale-cache window.
/// The next turn always reads again, keeping overview detection responsive.
enum WindowServerSnapshot {
    private static var cached: [[String: Any]]?
    static func onScreen(read: () -> [[String: Any]] = {
        CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
    }) -> [[String: Any]] {
        precondition(Thread.isMainThread)
        if let cached { return cached }
        let windows = read()
        cached = windows
        DispatchQueue.main.async { cached = nil }
        return windows
    }
}
