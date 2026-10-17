// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint contributors

import ApplicationServices
import CoreGraphics
import Foundation

enum ResourceUsageTests {
    static func run(_ suite: TestSuite) {
        snapshotSharing(suite)
        staleQueries(suite)
        ResourceMediaTests.run(suite)
        windowCache(suite)
        profileStorage(suite)
        ResourceHotProfileTests.run(suite)
        ResourceRemovalBarrierTests.run(suite)
        pointerSpool(suite)
        layoutComparison(suite)
    }

    private static func staleQueries(_ suite: TestSuite) {
        typealias Identity = DisplayWindowMemorySupport.SnapshotIdentity
        let first = Identity(pid: 10, bundleID: "one", frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        let second = Identity(pid: 20, bundleID: "two", frame: first.frame)
        let previous: [CGWindowID: Identity] = [1: first, 2: second]
        var current = previous
        current[2] = Identity(pid: 20, bundleID: "two", frame: second.frame.offsetBy(dx: 100, dy: 0))
        suite.expect(DisplayWindowMemorySupport.validSnapshotIDs(previous: previous, current: current,
            previousEvents: [:], currentEvents: [:]) == [1],
            "a moving window rejects only its own stale geometry, without starving another app")
        suite.expect(DisplayWindowMemorySupport.validSnapshotIDs(previous: previous, current: previous,
            previousEvents: [:], currentEvents: [20: 1]) == [1],
            "an AX event invalidates only the app queried before that event")
        current[1] = Identity(pid: 30, bundleID: "replacement", frame: first.frame)
        suite.expect(DisplayWindowMemorySupport.validSnapshotIDs(previous: previous, current: current,
            previousEvents: [:], currentEvents: [:]).isEmpty,
            "a recycled window ID cannot receive another process's geometry")
    }

    private static func snapshotSharing(_ suite: TestSuite) {
        var reads = 0
        let read = { () -> [[String: Any]] in reads += 1; return [["generation": reads]] }
        _ = WindowServerSnapshot.onScreen(read: read)
        let shared = WindowServerSnapshot.onScreen(read: read)
        suite.expect(reads == 1 && shared.first?["generation"] as? Int == 1,
                     "multiple island/window-memory callers share one WindowServer read in the same turn")
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        let fresh = WindowServerSnapshot.onScreen(read: read)
        suite.expect(reads == 2 && fresh.first?["generation"] as? Int == 2,
                     "the next main-queue turn obtains a fresh snapshot without a time-based stale window")
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }

    private static func windowCache(_ suite: TestSuite) {
        var now: TimeInterval = 0
        var reads = 0
        var stableReads = 0
        var dynamicReads = 0
        var dynamic = true
        let element = AXUIElementCreateApplication(getpid()) // No system AX query.
        let cache = DisplayWindowAXCache(clock: { now }, windows: { _ in
            reads += 1
            return [10: element, 11: element]
        }, stableEligibility: { _ in stableReads += 1; return true }, dynamicEligibility: { _ in
            dynamicReads += 1
            return dynamic
        })
        let a = DisplayWindowAXCache.Key(pid: getpid(), id: 10)
        let b = DisplayWindowAXCache.Key(pid: getpid(), id: 11)
        suite.expect(cache.resolve([a, b]).eligible == [a, b] && reads == 1 && stableReads == 2,
                     "a window-memory pass queries each process once and retains distinct window IDs")
        for _ in 0..<8 { now += 0.5; _ = cache.resolve([a, b]) }
        suite.expect(reads == 1 && stableReads == 2 && dynamicReads == 18,
                     "stable roles are cached while modal/full-screen state is checked every half-second")
        dynamic = false
        suite.expect(cache.resolve([a]).eligible.isEmpty,
                     "a newly modal/full-screen/invalid cached window is rejected immediately")
        dynamic = true
        _ = cache.resolve([a])
        suite.expect(reads == 2, "rejected handles are re-resolved rather than hiding a replacement for five seconds")
        cache.invalidate(pid: getpid())
        _ = cache.resolve([a])
        suite.expect(reads == 3, "an AX event invalidates the affected process immediately")
        now += 5
        _ = cache.resolve([a])
        suite.expect(reads == 4, "apps missing AX notifications retain a five-second stable-property refresh")
        _ = cache.resolve([])
        _ = cache.resolve([a])
        suite.expect(reads == 5, "closed or offscreen windows cannot retain stale AX handles")
    }

    private static func profileStorage(_ suite: TestSuite) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("vorssaint-profile-test-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("memory.sqlite")
        let store = DisplayWindowProfileStore(url: url)
        var memory = DisplayWindowMemory()
        var display = RememberedDisplay()
        let base = RememberedWindowGeometry(relativeFrame: CGRect(x: 10, y: 20, width: 800, height: 600), maximized: false)
        display.openingFrames = ["app:": base]
        display.sizes = ["app:": base.relativeFrame.size, "legacy:old": CGSize(width: 640, height: 480)]
        for index in 0..<1100 {
            let key = "app:title-\(index)"
            let geometry = RememberedWindowGeometry(relativeFrame: base.relativeFrame.offsetBy(dx: CGFloat(index), dy: 0), maximized: index == 1099)
            display.openingFrames?[key] = geometry
            display.sizes[key] = geometry.relativeFrame.size
        }
        display.windows = [RememberedWindow(bundleID: "app", titleDigest: "title-1099", relativeFrame: base.relativeFrame)]
        memory.displays["monitor"] = display
        suite.expect(store.save(memory), "legacy window profiles and layout migrate in one transaction")
        let cold = store.load()?.displays["monitor"]
        suite.expect(cold?.openingFrames?.count == 1 && cold?.openingFrames?["app:"] == base,
                     "startup reads the small app fallback instead of all historical titles")
        suite.expect(cold?.sizes["legacy:old"] == CGSize(width: 640, height: 480) && cold?.windows == display.windows,
                     "migration preserves legacy size-only profiles and complete layouts")
        suite.expect(store.profile(display: "monitor", key: "app:title-1099") == display.openingFrames?["app:title-1099"],
                     "a cold title preserves exact geometry and maximum state beyond the hot-cache budget")
        if let compact = store.load() { suite.expect(store.save(compact), "saving a compact cache succeeds") }
        let reopened = DisplayWindowProfileStore(url: url)
        suite.expect(reopened.profile(display: "monitor", key: "app:title-0") == base,
                     "saving after hot eviction and reopening never deletes an older title profile")
        suite.expect(reopened.profile(display: "other-monitor", key: "app:title-0") == nil,
                     "profiles remain isolated by physical display")
        let obstruction = root.appendingPathComponent("not-a-directory")
        try? Data([1]).write(to: obstruction)
        let unavailable = DisplayWindowProfileStore(url: obstruction.appendingPathComponent("memory.sqlite"))
        suite.expect(!unavailable.save(memory), "an unavailable cold store reports failure so callers retain legacy memory")
    }

    private static func pointerSpool(_ suite: TestSuite) {
        let samples = (0..<12000).map { index in
            RecorderMotion.Sample(time: Double(index) / 125, point: CGPoint(x: Double(index) / 12345.6789, y: -Double(index) / 9876.54321),
                                  shapeIndex: index % 7, isPointerVisible: index % 5 != 0)
        }
        for mode in 0..<3 {
            var writes = 0
            let spool = RecorderPointerSpool(directory: mode == 1 ? nil : FileManager.default.temporaryDirectory,
                                            chunkSamples: 64, writeData: { handle, data in
                writes += 1
                if mode == 2 && writes == 2 {
                    try handle.write(contentsOf: data.prefix(13)) // Partial write before disk-full.
                    throw CocoaError(.fileWriteOutOfSpace)
                }
                try handle.write(contentsOf: data)
            })
            for (index, sample) in samples.enumerated() {
                spool.append(sample, identity: UInt64(index % 31))
                // Let the first chunks reach the simulated disk error before
                // exercising the memory fallback for the rest of the take.
                if index == 64 || index == 128 { Thread.sleep(forTimeInterval: 0.02) }
            }
            guard let restored = try? spool.finish() else {
                suite.expect(false, "pointer spool must reconstruct a complete track in mode \(mode)")
                continue
            }
            suite.expect(restored.samples == samples,
                         "pointer samples retain all 125 Hz timestamps, Double precision, visibility and shapes in spool mode \(mode)")
            suite.expect(restored.identities == samples.indices.map { UInt64($0 % 31) },
                         "pointer identity ordering survives backlog, missing disk and partial write failure in mode \(mode)")
        }
    }

    private static func layoutComparison(_ suite: TestSuite) {
        let a = RememberedWindow(bundleID: "app", titleDigest: "document", relativeFrame: CGRect(x: 1, y: 2, width: 800, height: 600))
        let b = RememberedWindow(bundleID: "app", titleDigest: "document", relativeFrame: CGRect(x: 3, y: 4, width: 800, height: 600))
        suite.expect(DisplayWindowMemorySupport.canonicalLayout([a, b]) == DisplayWindowMemorySupport.canonicalLayout([b, a]),
                     "focus/Z-order changes do not rewrite an identical display layout")
        let moved = RememberedWindow(bundleID: a.bundleID, titleDigest: a.titleDigest, relativeFrame: a.relativeFrame.offsetBy(dx: 0.25, dy: 0))
        suite.expect(DisplayWindowMemorySupport.canonicalLayout([a, b]) != DisplayWindowMemorySupport.canonicalLayout([moved, b]),
                     "deliberate sub-point position changes are preserved without a new tolerance")
    }
}

/// The production eviction method must protect active and not-yet-saved edits.
enum ResourceHotProfileTests {
    class Fixture {
        var memory = DisplayWindowMemory()
        var activeProfiles: [String: Set<String>] = [:]
        var persistedProfiles: [String: [String: RememberedWindowGeometry]] = [:]
        var profileTouches: [String: [String: TimeInterval]] = [:]
    }
    static func run(_ suite: TestSuite) {
        let host = Host()
        let base = RememberedWindowGeometry(relativeFrame: CGRect(x: 1, y: 2, width: 800, height: 600), maximized: false)
        var display = RememberedDisplay()
        display.openingFrames = ["app:": base]
        for index in 0..<500 {
            let key = "app:title-\(index)"
            display.openingFrames?[key] = base
            display.sizes[key] = base.relativeFrame.size
            host.profileTouches["screen", default: [:]][key] = Double(index)
        }
        host.persistedProfiles["screen"] = display.openingFrames
        display.openingFrames?["app:title-0"] = RememberedWindowGeometry(relativeFrame: base.relativeFrame.offsetBy(dx: 99, dy: 0), maximized: false)
        host.memory.displays["screen"] = display
        host.activeProfiles["screen"] = ["app:title-499"]
        host.trimHotProfiles()
        let trimmed = host.memory.displays["screen"]
        suite.expect(trimmed?.openingFrames?["app:"] == base && trimmed?.openingFrames?["app:title-499"] == base,
                     "hot eviction preserves app fallbacks and currently visible titles")
        suite.expect(trimmed?.openingFrames?["app:title-0"]?.relativeFrame.minX == 100,
                     "an in-flight unsaved edit is never replaced by its older cold version")
        suite.expect((trimmed?.openingFrames?.count ?? 999) <= 258,
                     "only protected unsaved profiles may temporarily exceed the 256-title hot budget")
        host.persistedProfiles["screen"]?["app:title-0"] = trimmed?.openingFrames?["app:title-0"]
        host.trimHotProfiles()
        suite.expect(host.memory.displays["screen"]?.openingFrames?.count == 257,
                     "once the edit commits, cold storage permits the exact hot-cache bound without deleting history")
    }
}

enum ResourceRemovalBarrierTests {
    class Fixture {
        final class Store { var closed = false; func close() { closed = true } }
        var removing = false
        var stopped = false
        var queryFinished = false
        var saveFinished = false
        let queryQueue = DispatchQueue(label: "resource-removal-query-test")
        let persistenceQueue = DispatchQueue(label: "resource-removal-save-test")
        let profileStore = Store()
        func stop() { stopped = true }
    }
    static func run(_ suite: TestSuite) {
        let host = Host()
        host.queryQueue.async { Thread.sleep(forTimeInterval: 0.01); host.queryFinished = true }
        host.persistenceQueue.async { Thread.sleep(forTimeInterval: 0.01); host.saveFinished = true }
        host.prepareForRemoval()
        suite.expect(host.removing && host.stopped && host.queryFinished && host.saveFinished && host.profileStore.closed,
                     "full removal stops queries, drains saves and closes SQLite before container deletion")
    }
}
