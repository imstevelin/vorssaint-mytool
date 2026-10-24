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
    private final class RefreshView: NSView {
        private var white = false
        private var requestedAt: TimeInterval?
        private(set) var paintCount: UInt64 = 0
        private(set) var maximumPaintDelay: TimeInterval = 0
        override func draw(_ dirtyRect: NSRect) {
            (white ? NSColor.white : NSColor.black).setFill()
            bounds.fill()
            paintCount &+= 1
            if let requestedAt {
                maximumPaintDelay = max(maximumPaintDelay, ProcessInfo.processInfo.systemUptime - requestedAt)
                self.requestedAt = nil
            }
        }
        func advance() {
            white.toggle()
            // Preserve the oldest outstanding request when AppKit coalesces
            // frames; newer input must not hide a long pending paint.
            if requestedAt == nil { requestedAt = ProcessInfo.processInfo.systemUptime }
            // An NSWindow background setter and displayIfNeeded are not a
            // completed content draw. Submit explicit backing-store damage.
            needsDisplay = true
            display()
        }
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
    private var lastSampledNativeEvents: UInt64 = 0
    private var lastHeartbeat: TimeInterval?
    private var lastSampledPoint: NSPoint?
    private var lastMovement = -TimeInterval.infinity
    private var activityTimer: Timer?
    private(set) var panel: NSPanel?
    private(set) var redrawCount: UInt64 = 0
    private(set) var nativeEventCount: UInt64 = 0
    private(set) var fallbackCount: UInt64 = 0
    private(set) var repairCount: UInt64 = 0
    private(set) var maximumEventDelay: TimeInterval = 0
    private(set) var maximumHeartbeatGap: TimeInterval = 0
    var surfacePaintCount: UInt64 { (panel?.contentView as? RefreshView)?.paintCount ?? 0 }
    var activityPolling: Bool { activityTimer != nil }
    struct Status: Codable, Equatable {
        let nativeEvents: UInt64
        let redraws: UInt64
        let fallbacks: UInt64
        let repairs: UInt64
        let polling: Bool
        let visible: Bool
        let suspended: Bool
        let surfacePaints: UInt64
        let maximumEventDelay: TimeInterval
        let maximumHeartbeatGap: TimeInterval
        let maximumPaintDelay: TimeInterval
    }
    var status: Status {
        Status(nativeEvents: nativeEventCount, redraws: redrawCount, fallbacks: fallbackCount,
               repairs: repairCount, polling: activityPolling, visible: panel?.isVisible == true,
               suspended: suspended, surfacePaints: surfacePaintCount,
               maximumEventDelay: maximumEventDelay, maximumHeartbeatGap: maximumHeartbeatGap,
               maximumPaintDelay: (panel?.contentView as? RefreshView)?.maximumPaintDelay ?? 0)
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
        lastSampledNativeEvents = nativeEventCount
        lastHeartbeat = nil
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
        ]) { [weak self] event in
            guard let self else { return }
            let now = ProcessInfo.processInfo.systemUptime
            self.nativeActivity(at: self.pointerLocation(), now: now, eventTime: event.timestamp)
        }
    }

    func nativeActivity(at point: NSPoint, now: TimeInterval, eventTime: TimeInterval) {
        guard running, !suspended else { return }
        nativeEventCount &+= 1
        if now.isFinite, eventTime.isFinite, eventTime > 0, now >= eventTime {
            maximumEventDelay = max(maximumEventDelay, now - eventTime)
        }
        pointerActivity(at: point, now: now)
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
            created.backgroundColor = .clear
            created.contentView = RefreshView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
            // Remain above full-screen/menu surfaces: damage hidden beneath
            // another window does not keep the mirror compositor advancing.
            created.level = .screenSaver
            created.ignoresMouseEvents = true
            created.hidesOnDeactivate = false
            created.isReleasedWhenClosed = false
            created.isExcludedFromWindowsMenu = true
            // This surface contains only a changing pixel. It must participate
            // in normal compositor/capture paths, not opt out of sharing.
            created.sharingType = .readOnly
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
        (panel.contentView as? RefreshView)?.advance()
    }

    /// Called by the host's existing parent-liveness heartbeat, not an idle
    /// animation timer. A live NSEvent monitor is not proof of event delivery.
    /// Recover from a silent monitor without an input tap or new permissions.
    func heartbeat(now: TimeInterval) {
        guard running, !suspended, now.isFinite else { return }
        if let previous = lastHeartbeat { maximumHeartbeatGap = max(maximumHeartbeatGap, now - previous) }
        lastHeartbeat = now
        if screenFrame == nil || panel?.isVisible != true {
            updateLayout()
            if panel?.isVisible == true { repairCount &+= 1 }
        }
        samplePointer(now: now)
    }

    private func samplePointer(now: TimeInterval) {
        let point = pointerLocation()
        // Compare progress over the SAME sampling interval. A 0.1-second age
        // threshold with a 0.2-second heartbeat misclassified normal pauses
        // and repeatedly tore down a perfectly functional global monitor.
        let nativeProgress = nativeEventCount != lastSampledNativeEvents
        defer {
            lastSampledPoint = point
            lastSampledNativeEvents = nativeEventCount
        }
        guard let screenFrame, NSMouseInRect(point, screenFrame, false) else {
            stopActivityPolling()
            return
        }
        if let previous = lastSampledPoint, previous != point {
            lastMovement = now
            if !nativeProgress {
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
                    Self.log.notice("using independent pointer refresh for display \(self.displayID)")
                }
            }
        }
        if now - lastMovement >= 0.25 || nativeProgress {
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
        lastSampledNativeEvents = nativeEventCount
        lastHeartbeat = nil
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
