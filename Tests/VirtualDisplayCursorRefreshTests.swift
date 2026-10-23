// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit

enum VirtualDisplayCursorRefreshTests {
    static func run(_ suite: TestSuite) {
        _ = NSApplication.shared
        guard let screen = NSScreen.screens.first,
              let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else {
            suite.expect(false, "cursor refresh requires a logged-in graphical session")
            return
        }
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let refresh = VirtualDisplayCursorRefresh(displayID: id, rate: 75)
        refresh.start()
        guard let panel = refresh.panel else {
            suite.expect(false, "a connected source receives its compositor refresh panel")
            refresh.stop()
            return
        }
        suite.expect(panel.isVisible && panel.frame.size == NSSize(width: 1, height: 1),
                     "refresh damage covers only one logical point on the source")
        suite.expect(panel.alphaValue == 0.01 && panel.ignoresMouseEvents && !panel.canBecomeKey && !panel.canBecomeMain,
                     "the refresh panel is imperceptible and cannot capture clicks or keyboard focus")
        suite.expect(NSWorkspace.shared.frontmostApplication?.processIdentifier == frontmost,
                     "starting the refresh leaves the user's foreground application alone")
        let point = NSPoint(x: screen.frame.midX, y: screen.frame.midY)
        refresh.pointerActivity(at: point, now: 10)
        suite.expect(waitForPaint(refresh, after: 0), "AppKit completes the first requested backing draw")
        let firstPaints = refresh.surfacePaintCount
        let firstColor = pixel(panel)
        suite.expect(firstPaints > 0 && panel.sharingType == .readOnly,
                     "pointer damage reaches a real content draw in a normally shareable compositor surface")
        refresh.pointerActivity(at: point, now: 10.001)
        suite.expect(refresh.redrawCount == 1, "submillisecond input bursts do not cause redundant rendering")
        let previousPaints = refresh.surfacePaintCount
        refresh.pointerActivity(at: point, now: 10.02)
        suite.expect(waitForPaint(refresh, after: previousPaints), "a later pointer frame reaches a later content draw")
        suite.expect(refresh.redrawCount == 2 && refresh.surfacePaintCount > firstPaints
                     && firstColor != nil && pixel(panel) != firstColor,
                     "successive pointer frames paint different backing pixels, not just different window properties")
        refresh.pointerActivity(at: point, now: 10.028)
        suite.expect(refresh.redrawCount == 3,
                     "125 Hz pointer input does not alias down to 62.5 Hz on a 75 Hz source")
        refresh.pointerActivity(at: NSPoint(x: screen.frame.maxX + 10, y: screen.frame.maxY + 10), now: 11)
        suite.expect(refresh.redrawCount == 3, "activity on another screen never damages this source")
        refresh.setSuspended(true)
        refresh.pointerActivity(at: point, now: 12)
        suite.expect(!panel.isVisible && refresh.redrawCount == 3, "sleep or an inactive login session pauses compositing")
        refresh.setSuspended(false)
        refresh.pointerActivity(at: point, now: 13)
        suite.expect(panel.isVisible && refresh.redrawCount == 4, "wake restores the source's refresh panel")
        panel.orderOut(nil)
        refresh.pointerActivity(at: point, now: 13.1)
        suite.expect(panel.isVisible && refresh.redrawCount == 5 && refresh.repairCount == 1,
                     "a hidden refresh surface recovers on input instead of silently disabling all future damage")
        refresh.stop()
        refresh.pointerActivity(at: point, now: 14)
        refresh.heartbeat(now: 14.2)
        suite.expect(refresh.panel == nil && !panel.isVisible && refresh.redrawCount == 5,
                     "host teardown removes observation and the panel without leaving any rendering work")

        // Drop native event delivery entirely. Movement still reaches the
        // independent host heartbeat, starts a bounded pump, then goes idle.
        var sampledPoint = point
        let fallback = VirtualDisplayCursorRefresh(displayID: id, rate: 75, pointerLocation: { sampledPoint })
        fallback.start()
        fallback.heartbeat(now: 20)
        suite.expect(fallback.redrawCount == 0 && !fallback.activityPolling,
                     "an idle host heartbeat does not animate or start high-rate pointer sampling")
        sampledPoint.x += 5
        fallback.heartbeat(now: 20.2)
        suite.expect(fallback.redrawCount == 1 && fallback.fallbackCount == 1 && fallback.activityPolling,
                     "movement with no native events still damages the source and starts recovery sampling")
        sampledPoint.x += 5
        fallback.heartbeat(now: 20.21)
        suite.expect(fallback.redrawCount == 2, "silent-observer recovery follows further pointer movement")
        fallback.heartbeat(now: 20.5)
        suite.expect(!fallback.activityPolling && fallback.redrawCount == 2,
                     "recovery sampling stops after idle without producing idle window damage")
        fallback.panel?.orderOut(nil)
        fallback.heartbeat(now: 20.7)
        suite.expect(fallback.panel?.isVisible == true && fallback.repairCount == 1,
                     "the host heartbeat repairs an ordered-out panel without recreating the HiDPI display")
        fallback.setSuspended(true)
        sampledPoint.x += 5
        fallback.heartbeat(now: 21)
        suite.expect(!fallback.activityPolling && fallback.redrawCount == 2,
                     "sleep never starts recovery rendering or polling")
        fallback.setSuspended(false)
        fallback.heartbeat(now: 22)
        suite.expect(fallback.redrawCount == 2, "wake resets the movement baseline instead of inventing input")
        sampledPoint = NSPoint(x: screen.frame.maxX + 10, y: screen.frame.maxY + 10)
        fallback.heartbeat(now: 22.2)
        suite.expect(!fallback.activityPolling && fallback.redrawCount == 2,
                     "movement outside the owned display cannot trigger fallback rendering")
        fallback.stop()

        sampledPoint = point
        let progress = VirtualDisplayCursorRefresh(displayID: id, rate: 75, pointerLocation: { sampledPoint })
        progress.start()
        progress.heartbeat(now: 30)
        sampledPoint.x += 5
        progress.nativeActivity(at: sampledPoint, now: 30.01, eventTime: 30)
        progress.heartbeat(now: 30.2)
        suite.expect(progress.fallbackCount == 0 && !progress.activityPolling,
                     "native input followed by a normal 190ms pause is not misclassified by a 200ms heartbeat")
        sampledPoint.x += 5
        progress.heartbeat(now: 30.4)
        suite.expect(progress.fallbackCount == 1 && progress.activityPolling,
                     "only movement without native progress over the same interval starts fallback")
        sampledPoint.x += 5
        progress.nativeActivity(at: sampledPoint, now: 30.405, eventTime: 30.4)
        progress.heartbeat(now: 30.41)
        suite.expect(!progress.activityPolling && progress.fallbackCount == 1,
                     "native progress stops the fallback without replacing the monitor")
        suite.expect(progress.maximumEventDelay > 0 && progress.maximumEventDelay < 0.02
                     && progress.maximumHeartbeatGap > 0.19 && progress.maximumHeartbeatGap < 0.21,
                     "diagnostics distinguish native delivery delay and host heartbeat scheduling gaps")
        progress.stop()
        historyTests(suite, status: progress.status)
        let disconnected = VirtualDisplayCursorRefresh(displayID: .max, rate: 75)
        disconnected.start()
        disconnected.pointerActivity(at: point, now: 1)
        suite.expect(disconnected.panel == nil && disconnected.redrawCount == 0,
                     "a missing source cannot accidentally refresh the main display")
        disconnected.stop()
    }

    private static func pixel(_ panel: NSPanel) -> NSColor? {
        guard let view = panel.contentView,
              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        return bitmap.colorAt(x: 0, y: 0)
    }

    private static func waitForPaint(_ refresh: VirtualDisplayCursorRefresh, after count: UInt64) -> Bool {
        let deadline = Date(timeIntervalSinceNow: 1)
        while refresh.surfacePaintCount <= count, Date() < deadline {
            _ = RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.002))
        }
        return refresh.surfacePaintCount > count
    }

    private static func historyTests(_ suite: TestSuite, status: VirtualDisplayCursorRefresh.Status) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        catch { suite.expect(false, "cursor history fixture directory is writable"); return }
        defer { try? FileManager.default.removeItem(at: directory) }
        let request = directory.appendingPathComponent("journal.json.host-2")
        let old = VirtualDisplayCursorHistory(requestURL: request)
        old.record(status, now: 1, capturedAt: 100)
        old.record(status, now: 2, capturedAt: 101)
        let initial = try? Data(contentsOf: old.currentURL)
        let one = initial.flatMap { try? JSONDecoder().decode([VirtualDisplayCursorHistory.Sample].self, from: $0) }
        suite.expect(one?.count == 1, "unchanged status and sub-five-second samples do not write idle history")
        for i in 0..<15 { old.record(status, now: Double(i + 10), capturedAt: Double(i + 110), force: true) }
        let final = try? Data(contentsOf: old.currentURL)
        let bounded = final.flatMap { try? JSONDecoder().decode([VirtualDisplayCursorHistory.Sample].self, from: $0) }
        suite.expect(bounded?.count == 12 && bounded?.last?.capturedAt == 124,
                     "shutdown history retains only the latest twelve samples")
        let restarted = VirtualDisplayCursorHistory(requestURL: directory.appendingPathComponent("next.json.host-2"))
        restarted.record(status, now: 30, capturedAt: 200)
        suite.expect((try? Data(contentsOf: restarted.previousURL)) == final,
                     "a HiDPI off/on cycle preserves the old host's final evidence before new counters start")
        let other = VirtualDisplayCursorHistory(requestURL: directory.appendingPathComponent("next.json.host-3"))
        other.record(status, now: 30, capturedAt: 200)
        suite.expect(other.currentURL != restarted.currentURL && (try? Data(contentsOf: restarted.previousURL)) == final,
                     "each physical display keeps its own bounded history without overwriting another display")
    }
}
