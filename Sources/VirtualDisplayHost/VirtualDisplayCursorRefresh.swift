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
    private let pointerLocation: () -> NSPoint
    private var monitor: Any?
    private var screenObserver: NSObjectProtocol?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var screenFrame: NSRect?
    private var lastRefreshTime = -TimeInterval.infinity
    private var suspended = false
    private var running = false
    private var lastNativeActivity = -TimeInterval.infinity
    private var lastSampledPoint: NSPoint?
    private var lastMovement = -TimeInterval.infinity
    private var activityTimer: Timer?
    private(set) var panel: NSPanel?
    private(set) var redrawCount: UInt64 = 0
    private(set) var nativeEventCount: UInt64 = 0
    private(set) var fallbackCount: UInt64 = 0
    private(set) var repairCount: UInt64 = 0
    var activityPolling: Bool { activityTimer != nil }
    struct Status: Codable, Equatable {
        let nativeEvents: UInt64
        let redraws: UInt64
        let fallbacks: UInt64
        let repairs: UInt64
        let polling: Bool
        let visible: Bool
        let suspended: Bool
    }
    var status: Status {
        Status(nativeEvents: nativeEventCount, redraws: redrawCount, fallbacks: fallbackCount,
               repairs: repairCount, polling: activityPolling, visible: panel?.isVisible == true,
               suspended: suspended)
    }

    init(displayID: CGDirectDisplayID, rate: Double,
         pointerLocation: @escaping () -> NSPoint = { NSEvent.mouseLocation }) {
        self.displayID = displayID
        self.pointerLocation = pointerLocation
        // Allow two updates per display interval so a 125 Hz input stream
        // does not alias down to 62.5 Hz on a 75 Hz source. The compositor
        // coalesces window damage; cap only very high-rate device bursts.
        minimumInterval = 1 / (rate.isFinite ? min(240, max(24, rate) * 2) : 120)
    }

    func start() {
        guard !running else { return }
        running = true
        lastSampledPoint = pointerLocation()
        updateLayout()
        // Mouse-only global observation needs no keyboard monitoring grant.
        // Cache the screen rectangle outside this callback: no WindowServer
        // queries or Accessibility calls belong in a pointer notification.
        installMonitor()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.updateLayout() }
        let workspace = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(workspace.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.updateLayout() })
        for name in [NSWorkspace.screensDidSleepNotification, NSWorkspace.willSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            workspaceObservers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.setSuspended(true)
            })
        }
        for name in [NSWorkspace.screensDidWakeNotification, NSWorkspace.didWakeNotification,
                     NSWorkspace.sessionDidBecomeActiveNotification] {
            workspaceObservers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.setSuspended(false)
            })
        }
        Self.log.log("cursor refresh started for virtual display \(self.displayID); observer available \(self.monitor != nil)")
    }

    private func installMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [
            .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
            .leftMouseDown, .rightMouseDown, .otherMouseDown,
            .leftMouseUp, .rightMouseUp, .otherMouseUp, .scrollWheel
        ]) { [weak self] _ in
            guard let self else { return }
            let now = ProcessInfo.processInfo.systemUptime
            self.nativeEventCount &+= 1
            self.lastNativeActivity = now
            self.pointerActivity(at: self.pointerLocation(), now: now)
        }
    }

    private func updateLayout() {
        guard running, !suspended, let screen = NSScreen.screens.first(where: {
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
            // Remain above full-screen/menu surfaces: damage hidden beneath
            // another window does not keep the mirror compositor advancing.
            created.level = .screenSaver
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
        guard running, !suspended, now.isFinite else { return }
        if let panel, !panel.isVisible {
            repairCount &+= 1
            updateLayout()
        }
        guard let screenFrame, NSMouseInRect(point, screenFrame, false),
              now - lastRefreshTime >= minimumInterval,
              let panel, panel.isVisible else { return }
        lastRefreshTime = now
        redrawCount &+= 1
        panel.backgroundColor = redrawCount.isMultiple(of: 2) ? .black : .white
        panel.displayIfNeeded()
    }

    /// Called by the host's existing parent-liveness heartbeat, not an idle
    /// animation timer. A live NSEvent monitor is not proof of event delivery.
    /// Recover from a silent monitor without an input tap or new permissions.
    func heartbeat(now: TimeInterval) {
        guard running, !suspended, now.isFinite else { return }
        if screenFrame == nil || panel?.isVisible != true {
            updateLayout()
            if panel?.isVisible == true { repairCount &+= 1 }
        }
        samplePointer(now: now)
    }

    private func samplePointer(now: TimeInterval) {
        let point = pointerLocation()
        defer { lastSampledPoint = point }
        guard let screenFrame, NSMouseInRect(point, screenFrame, false) else {
            stopActivityPolling()
            return
        }
        if let previous = lastSampledPoint, previous != point {
            lastMovement = now
            if now - lastNativeActivity > 0.1 {
                fallbackCount &+= 1
                pointerActivity(at: point, now: now)
                if activityTimer == nil {
                    // Only moving input starts this pump. It stops after a
                    // quarter second idle; no display damage occurs at rest.
                    let timer = Timer(timeInterval: minimumInterval, repeats: true) { [weak self] _ in
                        self?.samplePointer(now: ProcessInfo.processInfo.systemUptime)
                    }
                    activityTimer = timer
                    RunLoop.main.add(timer, forMode: .common)
                    installMonitor()
                    Self.log.notice("cursor refresh recovered silent observation for display \(self.displayID)")
                }
            }
        }
        if now - lastMovement >= 0.25 || now - lastNativeActivity <= 0.1 {
            stopActivityPolling()
        }
    }

    private func stopActivityPolling() {
        activityTimer?.invalidate()
        activityTimer = nil
    }

    func setSuspended(_ value: Bool) {
        suspended = value
        stopActivityPolling()
        lastSampledPoint = pointerLocation()
        if !value, running { installMonitor() }
        updateLayout()
    }

    func stop() {
        running = false
        stopActivityPolling()
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
        lastSampledPoint = nil
    }

    deinit { stop() }
}
