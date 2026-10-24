// SPDX-License-Identifier: GPL-3.0-or-later
// Run: swift Tools/DiagnoseDisplayInput.swift [seconds, default 60, max 600]
// Read-only snapshots; no input capture, event injection or display changes.
import AppKit
import Foundation

let seconds = CommandLine.arguments.dropFirst().first.flatMap(Int.init) ?? 60
guard (1...600).contains(seconds) else {
    fputs("Duration must be 1...600 seconds\n", stderr)
    exit(64)
}
let formatter = ISO8601DateFormatter()
func emit(_ object: [String: Any]) {
    guard JSONSerialization.isValidJSONObject(object),
          let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
          let line = String(data: data, encoding: .utf8) else { return }
    print(line)
    fflush(stdout)
}
func snapshot(_ index: Int) {
    var taps = [CGEventTapInformation](repeating: CGEventTapInformation(), count: 256)
    var count: UInt32 = 0
    let result = CGGetEventTapList(UInt32(taps.count), &taps, &count)
    let tapRows: [[String: Any]] = taps.prefix(min(Int(count), taps.count)).map { tap in
        ["id": tap.eventTapID, "pid": tap.tappingProcess,
         "process": NSRunningApplication(processIdentifier: tap.tappingProcess)?.localizedName ?? "unknown",
         "enabled": tap.enabled, "mask": String(tap.eventsOfInterest, radix: 16),
         "listenOnly": tap.options == .listenOnly,
         "averageMicroseconds": tap.avgUsecLatency,
         "maximumMicroseconds": tap.maxUsecLatency]
    }
    var ids = [CGDirectDisplayID](repeating: 0, count: 32)
    var displayCount: UInt32 = 0
    let displayResult = CGGetOnlineDisplayList(UInt32(ids.count), &ids, &displayCount)
    let displays: [[String: Any]] = ids.prefix(min(Int(displayCount), ids.count)).map { id in
        let mode = CGDisplayCopyDisplayMode(id)
        return ["id": id, "mirrorSource": CGDisplayMirrorsDisplay(id),
                "width": mode?.width ?? 0, "height": mode?.height ?? 0,
                "pixelWidth": mode?.pixelWidth ?? 0, "pixelHeight": mode?.pixelHeight ?? 0,
                "refreshHz": mode?.refreshRate ?? 0, "asleep": CGDisplayIsAsleep(id) != 0]
    }
    // The first tap snapshot includes history (including sleep). Subsequent
    // min/max values cover intervals since our preceding query. A query resets
    // the tap latency extrema; an average is not a per-interval average.
    emit(["time": formatter.string(from: Date()), "sample": index,
          "historicalExtrema": index == 0, "tapResult": result.rawValue,
          "displayResult": displayResult.rawValue, "taps": tapRows, "displays": displays])
}
for index in 0...seconds {
    snapshot(index)
    if index < seconds { Thread.sleep(forTimeInterval: 1) }
}
