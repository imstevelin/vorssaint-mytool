// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint contributors

import CoreGraphics
import Foundation

struct RememberedWindow: Codable, Equatable {
    let bundleID: String
    let titleDigest: String?
    /// Origin relative to CGDisplayBounds, so rearranging displays does not move the layout off screen.
    let relativeFrame: CGRect
}

struct RememberedDisplay: Codable, Equatable {
    var windows: [RememberedWindow] = []
    var sizes: [String: CGSize] = [:]
}

struct DisplayWindowMemory: Codable {
    var displays: [String: RememberedDisplay] = [:]
}

enum DisplayWindowMemorySupport {
    static func profileKey(bundleID: String, titleDigest: String?) -> String {
        bundleID + ":" + (titleDigest ?? "")
    }

    static func newlyConnected(previous: Set<String>, current: Set<String>) -> Set<String> {
        current.subtracting(previous)
    }

    static func usableBounds(screenFrame: CGRect, visibleFrame: CGRect,
                             displayBounds: CGRect) -> CGRect {
        CGRect(x: displayBounds.minX + visibleFrame.minX - screenFrame.minX,
               y: displayBounds.minY + screenFrame.maxY - visibleFrame.maxY,
               width: visibleFrame.width, height: visibleFrame.height)
    }

    static func fittedFrame(_ frame: CGRect, within bounds: CGRect) -> CGRect {
        let width = min(max(frame.width, 1), bounds.width)
        let height = min(max(frame.height, 1), bounds.height)
        let x = min(max(frame.minX, bounds.minX), bounds.maxX - width)
        let y = min(max(frame.minY, bounds.minY), bounds.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    static func matches(_ saved: RememberedWindow, bundleID: String,
                        titleDigest: String?) -> Bool {
        saved.bundleID == bundleID &&
            (saved.titleDigest == nil || titleDigest == nil || saved.titleDigest == titleDigest)
    }
}
