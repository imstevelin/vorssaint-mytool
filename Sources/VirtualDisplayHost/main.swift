// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import VirtualDisplayBridge
import Darwin
#if canImport(DisplayRecoverySupport)
import DisplayRecoverySupport
#endif

guard CommandLine.arguments.count == 2 else { exit(64) }
let url = URL(fileURLWithPath: CommandLine.arguments[1])
guard let data = try? Data(contentsOf: url),
      let request = try? JSONDecoder().decode(VirtualDisplayHostRequest.self, from: data),
      request.parentPID == getppid() else { exit(65) }
let app = NSApplication.shared
// The nonactivating compositor refresh panel needs window support, but the
// helper must never become the frontmost app or show a Dock icon.
app.setActivationPolicy(.accessory)
let id = VSDCreateVirtualDisplay(request.width, request.height, request.rate, request.serial,
                                 0, 0, request.name)
guard id != 0 else { exit(1) }
guard let profile = request.colorProfile else { VSDDestroyVirtualDisplay(id); exit(66) }
// The virtual display is not mirrored until ColorSync and WindowServer both
// expose the physical monitor's exact profile. Registration is asynchronous.
let profileURL = url.appendingPathExtension("icc")
var profileApplied = false
var profileAttempts = 0
var published = false
let cursorRefresh = VirtualDisplayCursorRefresh(displayID: id, rate: request.rate)
let cursorHistory = VirtualDisplayCursorHistory(requestURL: url)
let cursorStatusURL = url.appendingPathExtension("cursor-status")
var lastStatusTime = -TimeInterval.infinity
var lastCursorStatus: VirtualDisplayCursorRefresh.Status?
func finish(_ status: Int32) -> Never {
    cursorHistory.record(cursorRefresh.status, now: ProcessInfo.processInfo.systemUptime, force: true)
    cursorRefresh.stop()
    DisplayColorProfile.resetOwnedVirtualDisplay(id)
    VSDDestroyVirtualDisplay(id)
    try? FileManager.default.removeItem(at: profileURL)
    try? FileManager.default.removeItem(at: cursorStatusURL)
    exit(status)
}
// Process.terminate uses SIGTERM. Handle cleanup on the run loop, never inside
// a signal handler, so ColorSync retains no override for our deleted display.
signal(SIGTERM, SIG_IGN)
let termination = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
termination.setEventHandler { finish(0) }
termination.resume()
let timer = Timer(timeInterval: 0.2, repeats: true) { _ in
    if !published {
        profileAttempts += 1
        if !profileApplied { profileApplied = DisplayColorProfile.apply(profile, to: id, url: profileURL) }
        if profileApplied, DisplayColorProfile.matches(profile, display: id) {
            try? JSONEncoder().encode(id).write(to: url.appendingPathExtension("display"), options: .atomic)
            published = true
            cursorRefresh.start()
        } else if profileAttempts >= 15 { finish(67) }
    }
    if getppid() != request.parentPID || kill(request.parentPID, 0) != 0 {
        finish(0)
    }
    if published {
        let now = ProcessInfo.processInfo.systemUptime
        cursorRefresh.heartbeat(now: now)
        cursorHistory.record(cursorRefresh.status, now: now)
        if now - lastStatusTime >= 5 {
            // Bounded, local counters only: no key contents or pointer positions.
            let status = cursorRefresh.status
            if status != lastCursorStatus {
                try? JSONEncoder().encode(status).write(to: cursorStatusURL, options: .atomic)
                lastCursorStatus = status
            }
            lastStatusTime = now
        }
    }
}
RunLoop.main.add(timer, forMode: .common)
app.run()
finish(0)
