// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import QuartzCore

/// Records where the pointer went while a recording runs.
///
/// A fixed-cadence sampler on its own thread rather than an event tap, for
/// three reasons: it needs no permission at all, it costs about a hundred
/// nanoseconds per sample, and a filter that runs offline wants its input on
/// an even grid anyway. The presses come from a mouse-only global monitor,
/// which is exact and, unlike key events, ungated.
///
/// Nothing here exists between recordings: the thread, the monitor and the
/// buffer are all created in `start()` and gone after `stop()`.
final class RecorderPointerSampler {

    private let region: RecorderSupport.Region
    private let displayBounds: CGRect
    private let pauseClock: RecorderPauseClock

    private var thread: Thread?
    private var clickMonitor: Any?
    private let lock = NSLock()
    private var spool: RecorderPointerSpool?
    private var clicks: [RecorderMotion.Click] = []
    private let cursors = RecorderCursorCatalog()
    private var running = false
    private var generation = 0
    private var lastSeed: Int32?
    private var currentIdentity: UInt64 = 0
    private let displayScale: Double

    /// 125 Hz: comfortably above any mouse report rate we care about, and
    /// still around fourteen microseconds of work per second of recording.
    private static let sampleRate: Double = 125

    init(region: RecorderSupport.Region, pauseClock: RecorderPauseClock) {
        self.region = region
        self.pauseClock = pauseClock
        displayBounds = CGDisplayBounds(region.displayID)
        displayScale = region.scale > 0 ? region.scale : 2
    }

    // MARK: - Lifecycle

    func start() {
        guard thread == nil else { return }
        let generation = lock.withLock { () -> Int in
            self.generation += 1
            running = true
            spool = RecorderPointerSpool()
            lastSeed = nil
            currentIdentity = 0
            clicks.removeAll(keepingCapacity: true)
            return self.generation
        }

        // Mouse-only monitors need no Accessibility grant, and a press is
        // never coalesced the way a move is, so these timestamps are exact.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp]
        ) { [weak self] event in
            self?.record(event, generation: generation)
        }

        let thread = Thread { [weak self] in
            self?.loop(generation: generation)
        }
        thread.qualityOfService = .userInteractive
        thread.name = "com.vorssaint.recorder.pointer"
        self.thread = thread
        thread.start()
    }

    /// Stops sampling and hands over what was collected.
    func stop() async throws -> RecorderPointerTrack {
        let stopped = await MainActor.run {
            self.thread = nil
            if let monitor = self.clickMonitor { NSEvent.removeMonitor(monitor) }
            self.clickMonitor = nil
            return self.lock.withLock {
                self.running = false
                let spool = self.spool
                self.spool = nil
                let clicks = self.clicks
                self.clicks.removeAll()
                return (spool, clicks, self.cursors.collected(), self.cursors.systemScale)
            }
        }
        // Disk drain and offline packing can be sizeable after a long take;
        // keep them away from the main actor and its finishing UI.
        // The producer is stopped under its lock. This exclusively owned
        // spool/catalog snapshot is handed to one worker and never mutated by main.
        nonisolated(unsafe) let handoff = stopped
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [displayScale] in
                do {
                    let recorded = try handoff.0?.finish() ?? (samples: [], identities: [])
                    let track = RecorderPointerTrack.packing(samples: recorded.samples,
                        identities: recorded.identities, clicks: handoff.1, catalog: handoff.2,
                        systemScale: handoff.3, displayScale: displayScale)
                    continuation.resume(returning: track)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    // MARK: - Sampling

    private func loop(generation: Int) {
        let interval = 1.0 / Self.sampleRate
        while lock.withLock({ running && self.generation == generation }) {
            let now = CACurrentMediaTime()
            if let time = pauseClock.eventTime(now),
               let point = normalizedPointerLocation() {
                // Two nanoseconds to ask whether the pointer changed, twenty
                // two microseconds to read the new one. So the question rides
                // every sample and the answer is fetched only on a change.
                lock.withLock {
                    guard running, self.generation == generation else { return }
                    let seed = cursors.currentSeed()
                    if seed != lastSeed {
                        lastSeed = seed
                        let identity = cursors.captureCurrentShape()
                        if identity != 0 { currentIdentity = identity }
                    }
                    let sample = RecorderMotion.Sample(
                        time: time,
                        point: point,
                        isPointerVisible: cursors.isPointerVisible()
                    )
                    spool?.append(sample, identity: currentIdentity)
                }
            }
            let elapsed = CACurrentMediaTime() - now
            if elapsed < interval {
                Thread.sleep(forTimeInterval: interval - elapsed)
            }
        }
    }

    /// The pointer inside the recorded area, 0...1 with a top-left origin.
    /// `CGEvent(source: nil)?.location` is already in the window server's
    /// top-left global space, which is the same space the recorded rectangle
    /// is expressed in, so there is no flipping to get wrong.
    private func normalizedPointerLocation() -> CGPoint? {
        guard let location = CGEvent(source: nil)?.location,
              location.x.isFinite, location.y.isFinite
        else { return nil }
        let scale = region.scale > 0 ? region.scale : 1
        let originX = displayBounds.origin.x + region.pixelRect.origin.x / scale
        let originY = displayBounds.origin.y + region.pixelRect.origin.y / scale
        let width = region.pixelRect.width / scale
        let height = region.pixelRect.height / scale
        guard width > 0, height > 0 else { return nil }
        return CGPoint(x: (location.x - originX) / width,
                       y: (location.y - originY) / height)
    }

    private func record(_ event: NSEvent, generation: Int) {
        lock.withLock {
            guard running, self.generation == generation else { return }
            guard let time = pauseClock.eventTime(CACurrentMediaTime())
            else { return }
            let isDown = event.type == .leftMouseDown || event.type == .rightMouseDown
            let click = RecorderMotion.Click(time: time, isDown: isDown)
            clicks.append(click)
        }
    }

}
