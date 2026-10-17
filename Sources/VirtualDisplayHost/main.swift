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
app.setActivationPolicy(.prohibited)
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
func finish(_ status: Int32) -> Never {
    DisplayColorProfile.resetOwnedVirtualDisplay(id)
    VSDDestroyVirtualDisplay(id)
    try? FileManager.default.removeItem(at: profileURL)
    exit(status)
}
// Process.terminate uses SIGTERM. Handle cleanup on the run loop, never inside
// a signal handler, so ColorSync retains no override for our deleted display.
signal(SIGTERM, SIG_IGN)
let termination = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
termination.setEventHandler { finish(0) }
termination.resume()
let timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
    if !published {
        profileAttempts += 1
        if !profileApplied { profileApplied = DisplayColorProfile.apply(profile, to: id, url: profileURL) }
        if profileApplied, DisplayColorProfile.matches(profile, display: id) {
            try? JSONEncoder().encode(id).write(to: url.appendingPathExtension("display"), options: .atomic)
            published = true
        } else if profileAttempts >= 15 { finish(67) }
    }
    if getppid() != request.parentPID || kill(request.parentPID, 0) != 0 {
        finish(0)
    }
}
app.run()
finish(0)
