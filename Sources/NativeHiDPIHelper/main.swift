// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Darwin

typealias Receipt = NativeHiDPIOverride.Receipt
let fm = FileManager.default
func protectedPath(_ url: URL, directory: Bool) throws {
    var info = stat()
    guard lstat(url.path, &info) == 0,
          info.st_uid == 0, info.st_mode & 0o022 == 0,
          info.st_mode & S_IFMT == (directory ? S_IFDIR : S_IFREG) else {
        throw NativeHiDPIOverride.Failure.unsafePath
    }
}
func ensureDirectory(_ url: URL) throws {
    if !fm.fileExists(atPath: url.path) {
        try ensureDirectory(url.deletingLastPathComponent())
        try fm.createDirectory(at: url, withIntermediateDirectories: false,
                               attributes: [.posixPermissions: 0o755])
    }
    try protectedPath(url, directory: true)
}
func contents(_ url: URL) throws -> Data? {
    var info = stat()
    if lstat(url.path, &info) != 0 {
        guard errno == ENOENT else { throw NativeHiDPIOverride.Failure.unsafePath }
        return nil
    }
    try protectedPath(url, directory: false)
    guard info.st_size <= 4 * 1024 * 1024 else { throw NativeHiDPIOverride.Failure.invalid }
    return try Data(contentsOf: url)
}
func write(_ data: Data, _ url: URL) throws {
    _ = try contents(url)
    try data.write(to: url, options: .atomic)
    try fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
    try protectedPath(url, directory: false)
}
do {
    let args = CommandLine.arguments
    guard geteuid() == 0, (args.count == 4 || args.count == 6),
          let vendor = UInt32(args[2]), let product = UInt32(args[3]) else { throw NativeHiDPIOverride.Failure.invalid }
    let identity = NativeHiDPIOverride.Identity(vendor: vendor, product: product)
    guard identity.valid else { throw NativeHiDPIOverride.Failure.invalid }
    let base = URL(fileURLWithPath: "/Library/Displays/Contents/Resources/Overrides")
    let backup = URL(fileURLWithPath: "/Library/Application Support/com.imstevelin.vorssaint-imstevelin/NativeHiDPI")
    try ensureDirectory(base)
    try ensureDirectory(backup)
    let lockURL = backup.appendingPathComponent("transaction.lock")
    _ = try contents(lockURL)
    let lockFD = open(lockURL.path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o644)
    guard lockFD >= 0, flock(lockFD, LOCK_EX) == 0 else { throw NativeHiDPIOverride.Failure.unsafePath }
    defer { flock(lockFD, LOCK_UN); close(lockFD) }
    try protectedPath(lockURL, directory: false)
    let target = base.appendingPathComponent(identity.relativePath)
    try ensureDirectory(target.deletingLastPathComponent())
    let receiptURL = backup.appendingPathComponent("\(vendor)-\(product).json")
    let current = try contents(target)
    let receipt = try contents(receiptURL).map { try JSONDecoder().decode(Receipt.self, from: $0) }
    if args[1] == "--apply", args.count == 6, let width = Int(args[4]), let height = Int(args[5]) {
        // An interrupted transaction may still have the original file. Both
        // known states are safe; an unrelated third-party edit is not.
        if let receipt, !receipt.accepts(current) { throw NativeHiDPIOverride.Failure.conflict }
        let installed = try NativeHiDPIOverride.configuration(identity: identity,
            sizes: [.init(width: width, height: height)], existing: current)
        let next = Receipt(original: receipt == nil ? current : receipt!.original, installed: installed, previous: current)
        // Preserve the original before any system file change, including crash
        // recovery if the process exits between these two atomic writes.
        try write(JSONEncoder().encode(next), receiptURL)
        try write(installed, target)
        print("Installed native scaled modes. Reconnect the display or restart macOS to activate. Backup: \(receiptURL.path)")
    } else if args[1] == "--restore", args.count == 4, let receipt {
        guard receipt.accepts(current) else { throw NativeHiDPIOverride.Failure.conflict }
        if let original = receipt.original { try write(original, target) }
        else if current != nil { try fm.removeItem(at: target) }
        try fm.removeItem(at: receiptURL)
        print("Restored the original model override. Reconnect the display or restart macOS to activate.")
    } else { throw NativeHiDPIOverride.Failure.invalid }
} catch {
    FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
    exit(1)
}
