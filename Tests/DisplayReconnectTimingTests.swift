// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import CoreGraphics

/// Execute the actual reconnect scheduling and managed-transition methods.
enum DisplayReconnectTimingTests {
    final class Queue {
        var jobs: [() -> Void] = []
        var delays: [Double] = []
        func asyncAfter(deadline: DispatchTime, execute job: DispatchWorkItem) {
            delays.append(Double(deadline.uptimeNanoseconds - DispatchTime.now().uptimeNanoseconds) / 1e9)
            jobs.append { if !job.isCancelled { job.perform() } }
        }
        func asyncAfter(deadline: DispatchTime, execute job: @escaping () -> Void) {
            delays.append(Double(deadline.uptimeNanoseconds - DispatchTime.now().uptimeNanoseconds) / 1e9)
            jobs.append(job)
        }
        func drain() { while !jobs.isEmpty { jobs.removeFirst()() } }
    }
    enum DispatchQueue { static let main = Queue() }
    class ResumeState {
        var resumeWork: DispatchWorkItem?
        var saved: [String: Int] = ["monitor": 1]
        var resumes = 0
        func savedProfiles() -> [String: Int] { saved }
        func resumeSavedProfiles() { resumes += 1 }
    }
    class MemoryState {
        var managedDisplayTransition = false
        var observations: [String: Int] = ["window": 1]
        var transitionGeneration = 0
        var pendingLayoutDisplays = Set<String>()
        var knownDisplayGeometry: [String: CGRect] = [:]
        var knownDisplays: Set<String> = ["builtin"]
        var geometry: [String: CGRect] = [:]
        var captureResumeAt = Date.distantPast
        var scanResumeAt = Date.distantPast
        var timer: Bool? = true
        var scans = 0
        func displayGeometry() -> [String: CGRect] { geometry }
        func scan() { scans += 1 }
    }
    static func run(_ suite: TestSuite) {
        DispatchQueue.main.jobs = []; DispatchQueue.main.delays = []
        let resume = ResumeService()
        for _ in 0..<100 { resume.scheduleSavedProfiles() }
        suite.expect(DispatchQueue.main.jobs.count == 1,
                     "a topology notification burst keeps one fixed HiDPI resume instead of restarting its delay")
        suite.expect(DispatchQueue.main.delays.first.map { $0 > 0.45 && $0 <= 0.5 } == true,
                     "reconnect starts HiDPI after half a second rather than three seconds")
        DispatchQueue.main.drain()
        suite.expect(resume.resumes == 1 && resume.resumeWork == nil,
                     "completed scheduling releases its slot for future reconnects")
        resume.scheduleSavedProfiles(); DispatchQueue.main.drain()
        suite.expect(resume.resumes == 2, "a later reconnect can resume again")
        resume.saved = [:]; resume.scheduleSavedProfiles()
        suite.expect(DispatchQueue.main.jobs.isEmpty, "no HiDPI profile means no extra reconnect delay")

        let memory = MemoryService()
        memory.pendingLayoutDisplays = ["external"]
        memory.beginManagedDisplayTransition()
        suite.expect(memory.managedDisplayTransition && memory.pendingLayoutDisplays == ["external"],
                     "HiDPI preserves the pending reconnect layout until geometry is ready")
        memory.geometry = ["builtin": CGRect(x: 0, y: 0, width: 1440, height: 900),
                           "external": CGRect(x: 1440, y: 0, width: 2560, height: 1440)]
        let now = Date()
        memory.endManagedDisplayTransition()
        suite.expect(!memory.managedDisplayTransition && memory.pendingLayoutDisplays == ["external"],
                     "the new monitor still receives its full layout after HiDPI verification")
        suite.expect(memory.scanResumeAt.timeIntervalSince(now) < 0.25
                     && memory.captureResumeAt.timeIntervalSince(now) >= 2,
                     "restore resumes promptly while learning retains the safe two-second pause")
        DispatchQueue.main.drain()
        suite.expect(memory.scans == 1, "verification completion schedules restoration without waiting for the polling timer")
        memory.pendingLayoutDisplays = ["disconnected"]
        memory.beginManagedDisplayTransition(); memory.endManagedDisplayTransition()
        suite.expect(memory.pendingLayoutDisplays.isEmpty, "disconnected displays cannot retain a stale layout offer")
        memory.beginManagedDisplayTransition() // Supersede the queued end callback.
        DispatchQueue.main.drain()
        suite.expect(memory.scans == 1, "an old settle callback cannot run inside a new HiDPI transition")
        memory.endManagedDisplayTransition(); memory.timer = nil
        DispatchQueue.main.drain()
        suite.expect(memory.scans == 1, "stopping display memory cancels pending restoration callbacks")
    }
}
