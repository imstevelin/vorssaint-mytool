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
    // Optional so preferences written by size-only releases still decode.
    var openingFrames: [String: RememberedWindowGeometry]?
}

struct RememberedWindowGeometry: Codable, Equatable {
    let relativeFrame: CGRect
    let maximized: Bool
}

struct DisplayWindowMemory: Codable {
    var displays: [String: RememberedDisplay] = [:]
}

struct DisplayWindowObservation {
    var display: String
    var frame: CGRect
    var stableSince: Date
    var learned = false
    var generation = 0
}

enum DisplayWindowMemorySupport {
    struct SnapshotIdentity: Equatable {
        let pid: pid_t
        let bundleID: String
        let frame: CGRect
    }

    /// A busy/changing window must not starve unrelated applications. Titles
    /// are read from the fresh snapshot and do not invalidate stable geometry.
    static func validSnapshotIDs(previous: [CGWindowID: SnapshotIdentity],
                                 current: [CGWindowID: SnapshotIdentity],
                                 previousEvents: [pid_t: Int], currentEvents: [pid_t: Int]) -> Set<CGWindowID> {
        Set(previous.compactMap { id, identity in
            guard current[id] == identity,
                  previousEvents[identity.pid, default: 0] == currentEvents[identity.pid, default: 0]
            else { return nil }
            return id
        })
    }

    /// WindowServer lists front-to-back. Order changes do not change the
    /// geometry this feature restores (it never restores stacking order).
    static func canonicalLayout(_ windows: [RememberedWindow]) -> [RememberedWindow] {
        windows.sorted {
            if $0.bundleID != $1.bundleID { return $0.bundleID < $1.bundleID }
            if $0.titleDigest != $1.titleDigest { return ($0.titleDigest ?? "") < ($1.titleDigest ?? "") }
            let a = [$0.relativeFrame.minX, $0.relativeFrame.minY, $0.relativeFrame.width, $0.relativeFrame.height]
            let b = [$1.relativeFrame.minX, $1.relativeFrame.minY, $1.relativeFrame.width, $1.relativeFrame.height]
            return a.lexicographicallyPrecedes(b)
        }
    }

    enum Action { case wait, restore, observe, learn }

    /// A restore belongs only to a new window or a display transition. Once
    /// consumed, all subsequent geometry changes belong to the app or user.
    static func action(previous: DisplayWindowObservation?, display: String,
                       frame: CGRect, now: Date, interacting: Bool, generation: Int = 0) -> Action {
        if previous == nil || previous?.display != display || previous?.generation != generation {
            return interacting ? .wait : .restore
        }
        guard let previous, !interacting, !previous.learned,
              close(previous.frame, frame),
              now.timeIntervalSince(previous.stableSince) >= 1.5 else { return .observe }
        return .learn
    }

    /// AX metadata is required before either learning or restoring geometry.
    /// Dialogs, sheets, floating panels and fixed-size windows have no app fallback.
    /// hasMinimizeButton requires an enabled button, not a disabled decoration.
    static func eligibleWindow(role: String?, subrole: String?, modal: Bool,
                               resizable: Bool, hasMinimizeButton: Bool) -> Bool {
        role == "AXWindow" && subrole == "AXStandardWindow" && !modal
            && resizable && hasMinimizeButton
    }

    /// macOS tiling includes margins; allow a small inset around edges.
    /// Keep arrangement snapshots separate from the app's normal opening size.
    static func arrangedSize(_ size: CGSize, within bounds: CGRect) -> Bool {
        let tolerance: CGFloat = 32
        let fractions: [CGFloat] = [1, 0.5, 1.0 / 3, 2.0 / 3, 0.25, 0.75]
        let fullHeight = abs(size.height - bounds.height) <= tolerance
        let fullWidth = abs(size.width - bounds.width) <= tolerance
        let tileWidth = fractions.contains { abs(size.width - bounds.width * $0) <= tolerance }
        let tileHeight = fractions.contains { abs(size.height - bounds.height * $0) <= tolerance }
        return (fullHeight && tileWidth) || (fullWidth && tileHeight)
            || (abs(size.height - bounds.height / 2) <= tolerance
                && abs(size.width - bounds.width / 2) <= tolerance)
    }

    static func maximizedFrame(_ frame: CGRect, within bounds: CGRect) -> Bool {
        close(frame, bounds)
    }

    static func rememberOpeningFrame(_ frame: CGRect, in stored: inout RememberedDisplay,
                                     bundleID: String, titleDigest: String?,
                                     displayBounds: CGRect, usableBounds: CGRect) {
        let maximized = maximizedFrame(frame, within: usableBounds)
        // Keep temporary tiles out of opening profiles, but retain windowed zoom.
        let fillsWorkArea = abs(frame.width - usableBounds.width) <= 32
            && abs(frame.height - usableBounds.height) <= 32
        guard fillsWorkArea || !arrangedSize(frame.size, within: usableBounds) else { return }
        let geometry = RememberedWindowGeometry(
            relativeFrame: frame.offsetBy(dx: -displayBounds.minX, dy: -displayBounds.minY),
            maximized: maximized)
        stored.openingFrames = stored.openingFrames ?? [:]
        for key in Set([profileKey(bundleID: bundleID, titleDigest: titleDigest),
                        profileKey(bundleID: bundleID, titleDigest: nil)]) {
            stored.openingFrames?[key] = geometry
            stored.sizes[key] = frame.size
        }
    }

    static func openingFrame(in stored: RememberedDisplay?, bundleID: String,
                             titleDigest: String?, currentFrame: CGRect,
                             displayBounds: CGRect, usableBounds: CGRect) -> CGRect? {
        let keys = [profileKey(bundleID: bundleID, titleDigest: titleDigest),
                    profileKey(bundleID: bundleID, titleDigest: nil)]
        for key in keys {
            if let geometry = stored?.openingFrames?[key] {
                if geometry.maximized { return usableBounds }
                return fittedFrame(geometry.relativeFrame.offsetBy(
                    dx: displayBounds.minX, dy: displayBounds.minY), within: usableBounds)
            }
        }
        // An old normal size must not shrink a window the app opened maximized.
        guard !maximizedFrame(currentFrame, within: usableBounds) else { return nil }
        for key in keys {
            if let size = stored?.sizes[key], !arrangedSize(size, within: usableBounds) {
                return fittedFrame(CGRect(origin: currentFrame.origin, size: size), within: usableBounds)
            }
        }
        return nil
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
