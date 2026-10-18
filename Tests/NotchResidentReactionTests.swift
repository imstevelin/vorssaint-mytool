// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import QuartzCore

/// Execute the production reaction delivery against both presentation modes.
enum NotchResidentReactionTests {
    enum NotchMascotSupport { static func reacts() -> Bool { true } }
    final class Gate {
        var allowed = true
        func admits(_ reaction: NotchMascotReaction, at: CFTimeInterval) -> Bool { allowed }
    }
    final class Host {
        func reactMascotBridge(_ event: NotchMascotReactionEvent, lift: CGFloat) {}
    }
    class State {
        var mascotVisit: NotchMascotVisit?
        var compactActivity: NotchCompactActivity?
        var pendingMascotReaction: (reaction: NotchMascotReaction, deadline: CFTimeInterval, notBefore: CFTimeInterval)?
        var mascotReactionFlushWork: DispatchWorkItem?
        var mascotResidentShows = false, canHost = false
        var mascotRestsInView = true, mascotBridging = false, mascotRestedInView = false
        var mascotBackAtRest: CFTimeInterval = -100
        var mascotReactionGate = Gate()
        var lastMascotGroove: CFTimeInterval = 0
        var mascotReaction: NotchMascotReactionEvent?
        var windowHost: Host? = Host()
        var mascotBridgeLift: CGFloat = 0
        var mascotJustRested = false
        var cameos = 0
        func canHostMascotVisit() -> Bool { canHost }
        func endMascotCountdown(retreating: Bool) { mascotVisit = nil }
        func beginMascotCameo(_ reaction: NotchMascotReaction, lingering: Bool) { cameos += 1 }
        func enqueue() {
            pendingMascotReaction = (.celebrate, CACurrentMediaTime() + 30, 0)
        }
    }

    static func run(_ suite: TestSuite) {
        let expanded = Service()
        expanded.mascotResidentShows = true
        expanded.enqueue()
        expanded.flushMascotReaction()
        suite.expect(expanded.mascotReaction?.reaction == .celebrate && expanded.pendingMascotReaction == nil,
                     "expanded resident reacts immediately without waiting for a closed-strip crossfade")
        suite.expect(expanded.cameos == 0, "expanded resident reacts in place without starting a closed-island visit")

        let hidden = Service()
        hidden.enqueue()
        hidden.flushMascotReaction()
        suite.expect(hidden.mascotReaction == nil && hidden.pendingMascotReaction != nil,
                     "a hidden companion retains the waiting reaction rather than animating offscreen")

        let closed = Service()
        closed.canHost = true
        closed.mascotRestsInView = false
        closed.enqueue()
        closed.flushMascotReaction()
        suite.expect(closed.cameos == 1 && closed.mascotReaction == nil,
                     "a closed activity still uses the upstream cameo route")

        let limited = Service()
        limited.mascotResidentShows = true
        limited.mascotReactionGate.allowed = false
        limited.enqueue()
        limited.flushMascotReaction()
        suite.expect(limited.mascotReaction == nil && limited.cameos == 0,
                     "expanded reactions preserve the existing rate and repetition gate")
    }
}
