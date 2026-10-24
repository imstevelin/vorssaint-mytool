// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Keep the evidence across the user's off/on recovery. The old live status
/// file was deleted on shutdown, losing exactly the episode we needed to see.
final class VirtualDisplayCursorHistory {
    struct Sample: Codable {
        let capturedAt: TimeInterval
        let status: VirtualDisplayCursorRefresh.Status
    }
    let currentURL: URL
    let previousURL: URL
    private var samples: [Sample] = []
    private var lastWrite = -TimeInterval.infinity
    private var lastStatus: VirtualDisplayCursorRefresh.Status?

    init(requestURL: URL) {
        let directory = requestURL.deletingLastPathComponent()
        let identity = requestURL.pathExtension // parent-owned host-<physical ID>
        currentURL = directory.appendingPathComponent("cursor-history-\(identity).json")
        previousURL = directory.appendingPathComponent("cursor-history-\(identity)-previous.json")
        if let data = try? Data(contentsOf: currentURL) {
            try? data.write(to: previousURL, options: .atomic)
        }
    }

    func record(_ status: VirtualDisplayCursorRefresh.Status, now: TimeInterval,
                capturedAt: TimeInterval = Date().timeIntervalSince1970, force: Bool = false) {
        guard now.isFinite, capturedAt.isFinite,
              force || (now - lastWrite >= 5 && status != lastStatus) else { return }
        samples.append(Sample(capturedAt: capturedAt, status: status))
        if samples.count > 12 { samples.removeFirst(samples.count - 12) }
        guard let data = try? JSONEncoder().encode(samples),
              (try? data.write(to: currentURL, options: .atomic)) != nil else { return }
        lastWrite = now
        lastStatus = status
    }
}
