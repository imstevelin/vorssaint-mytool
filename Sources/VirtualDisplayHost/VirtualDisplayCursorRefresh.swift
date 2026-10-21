// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import os

/// Keeps an idle virtual mirror source compositing when the pointer is active.
/// macOS can otherwise leave the physical mirror showing a stale cursor frame.
/// See docs/verification/hidpi-cursor-refresh-2026-10-21.md for the evidence and
/// the limits of this workaround. Nothing intercepts or rewrites input here.
final class VirtualDisplayCursorRefresh {
    private final class RefreshPanel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }

    private static let log = Logger(subsystem: "com.imstevelin.vorssaint-imstevelin", category: "display-refresh")
    private let displayID: CGDirectDisplayID
    private let minimumInterval: TimeInterval
    private var monitor: Any?
    private var screenObserver: NSObjectProtocol?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var screenFrame: NSRect?
    private var lastRefreshTime = -TimeInterval.infinity
    private var suspended = false
    private(set) var panel: NSPanel?
    private(set) var redrawCount: UInt64 = 0

    init(displayID: CGDirectDisplayID, rate: Double) {
        self.displayID = displayID
        // Allow two updates per display interval so a 125 Hz input stream
        // does not alias down to 62.5 Hz on a 75 Hz source. The compositor
        // coalesces window damage; cap only very high-rate device bursts.
        minimumInterval = 1 / (rate.isFinite ? min(240, max(24, rate) * 2) : 120)
    }

    func start() {
        guard screenObserver == nil else { return }
        updateLayout()
        // Mouse-only global observation needs no keyboard monitoring grant.
        // Cache the screen rectangle outside this callback: no WindowServer
        // queries or Accessibility calls belong in a pointer notification.
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [
            .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
            .leftMouseDown, .rightMouseDown, .otherMouseDown,
            .leftMouseUp, .rightMouseUp, .otherMouseUp, .scrollWheel
        ]) { [weak self] _ in
            self?.pointerActivity(at: NSEvent.mouseLocation, now: ProcessInfo.processInfo.systemUptime)
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.updateLayout() }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.screensDidSleepNotification, NSWorkspace.willSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            workspaceObservers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.setSuspended(true)
            })
        }
        for name in [NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            workspaceObservers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.setSuspended(false)
            })
        }
        Self.log.log("cursor refresh started for virtual display \(self.displayID); observer available \(self.monitor != nil)")
    }

    private func updateLayout() {
        guard !suspended, let screen = NSScreen.screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID
        }) else {
            screenFrame = nil
            panel?.orderOut(nil)
            return
        }
        screenFrame = screen.frame
        if panel == nil {
            let created = RefreshPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                       backing: .buffered, defer: false)
            created.isOpaque = false
            created.hasShadow = false
            created.alphaValue = 0.01
            created.backgroundColor = .black
            created.level = .statusBar
            created.ignoresMouseEvents = true
            created.hidesOnDeactivate = false
            created.isReleasedWhenClosed = false
            created.isExcludedFromWindowsMenu = true
            created.sharingType = .none
            created.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            panel = created
        }
        // A single logical point (at most 2x2 pixels on our Retina source).
        panel?.setFrame(NSRect(origin: screen.frame.origin, size: NSSize(width: 1, height: 1)), display: false)
        panel?.orderFrontRegardless()
        lastRefreshTime = -.infinity
    }

    func pointerActivity(at point: NSPoint, now: TimeInterval) {
        guard !suspended, let screenFrame, NSMouseInRect(point, screenFrame, false),
              now.isFinite, now - lastRefreshTime >= minimumInterval,
              let panel, panel.isVisible else { return }
        lastRefreshTime = now
        redrawCount &+= 1
        panel.backgroundColor = redrawCount.isMultiple(of: 2) ? .black : .white
        panel.displayIfNeeded()
    }

    func setSuspended(_ value: Bool) {
        suspended = value
        updateLayout()
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        workspaceObservers = []
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
        screenFrame = nil
    }

    deinit { stop() }
}
