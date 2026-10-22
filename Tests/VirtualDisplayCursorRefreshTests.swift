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
        let firstColor = panel.backgroundColor
        refresh.pointerActivity(at: point, now: 10.001)
        suite.expect(refresh.redrawCount == 1, "submillisecond input bursts do not cause redundant rendering")
        refresh.pointerActivity(at: point, now: 10.02)
        suite.expect(refresh.redrawCount == 2 && panel.backgroundColor != firstColor,
                     "successive pointer frames cause actual window damage instead of a no-op redraw")
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
        let disconnected = VirtualDisplayCursorRefresh(displayID: .max, rate: 75)
        disconnected.start()
        disconnected.pointerActivity(at: point, now: 1)
        suite.expect(disconnected.panel == nil && disconnected.redrawCount == 0,
                     "a missing source cannot accidentally refresh the main display")
        disconnected.stop()
    }
}
