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

struct DisplayWindowObservation {
    var display: String
    var frame: CGRect
    var stableSince: Date
    var learned = false
}

enum DisplayWindowMemorySupport {
    enum Action { case wait, restore, observe, learn }

    /// A restore belongs only to a new window or a display transition. Once
    /// consumed, all subsequent geometry changes belong to the app or user.
    static func action(previous: DisplayWindowObservation?, display: String,
                       frame: CGRect, now: Date, interacting: Bool) -> Action {
        if previous == nil || previous?.display != display {
            return interacting ? .wait : .restore
        }
        guard let previous, !interacting, !previous.learned,
              close(previous.frame, frame),
              now.timeIntervalSince(previous.stableSince) >= 1.5 else { return .observe }
        return .learn
    }

    static func close(_ lhs: CGSize, _ rhs: CGSize) -> Bool {
        abs(lhs.width - rhs.width) <= 2 && abs(lhs.height - rhs.height) <= 2
    }

    static func close(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        close(lhs.size, rhs.size) && abs(lhs.minX - rhs.minX) <= 2 && abs(lhs.minY - rhs.minY) <= 2
    }

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
