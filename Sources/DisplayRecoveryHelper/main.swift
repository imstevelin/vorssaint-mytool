// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import CoreGraphics
import Darwin
#if canImport(DisplayRecoverySupport)
import DisplayRecoverySupport
#endif

guard CommandLine.arguments.count == 2 else { exit(64) }
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let done = url.appendingPathExtension("done")
let restored = url.appendingPathExtension("restored")
let ready = url.appendingPathExtension("ready")
guard let initialData = try? Data(contentsOf: url),
      let initial = try? JSONDecoder().decode(DisplayRecoveryJournal.self, from: initialData),
      initial.parentPID == getppid() else { exit(65) }
try? Data().write(to: ready, options: .atomic)
while !FileManager.default.fileExists(atPath: done.path) {
    let journal = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(DisplayRecoveryJournal.self, from: $0) } ?? initial
    let parentGone = getppid() != initial.parentPID || kill(initial.parentPID, 0) != 0
    let expired = !journal.confirmed && Date().timeIntervalSince1970 >= journal.deadline
    if parentGone || expired {
        // Hosts belong to this armed transaction and were spawned by the parent.
        // Their process exit also clears virtual-display objects that macOS retained.
        for pid in journal.hostPIDs where pid > 1 && pid != getpid() { _ = kill(pid, SIGTERM) }
        Thread.sleep(forTimeInterval: 0.5)
        var success = false
        // Hotplug and owner teardown may take a moment to settle.
        for _ in 0..<10 {
            if journal.snapshot.restore() { success = true; break }
            Thread.sleep(forTimeInterval: 0.3)
        }
        try? Data((success ? "restored" : "failed").utf8).write(to: restored, options: .atomic)
        exit(success ? 0 : 1)
    }
    Thread.sleep(forTimeInterval: 0.2)
}
