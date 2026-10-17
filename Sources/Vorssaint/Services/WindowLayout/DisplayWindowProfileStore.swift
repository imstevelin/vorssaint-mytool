// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint contributors

import Foundation
import SQLite3

/// Cold profiles stay on disk, rather than being deleted when the hot cache
/// fills. All access is serialized, and callers read from a background queue.
final class DisplayWindowProfileStore {
    private let queue = DispatchQueue(label: "com.vorssaint.window-memory-store", qos: .utility)
    private let url: URL?
    private var database: OpaquePointer?
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(url: URL? = PrivateFileStore.containerURL?.appendingPathComponent("window-memory.sqlite")) {
        self.url = url
    }

    deinit { sqlite3_close(database) }

    func close() {
        queue.sync {
            sqlite3_close(database)
            database = nil
        }
    }

    private func open() -> Bool {
        if database != nil { return true }
        guard let url, PrivateFileStore.createDirectory(at: url.deletingLastPathComponent()) else { return false }
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return false
        }
        sqlite3_busy_timeout(db, 1000)
        // DELETE journal is removed after commit; the app's private directory
        // protects transient journal files as well as the database itself.
        let schema = "CREATE TABLE IF NOT EXISTS profiles(display TEXT, key TEXT, value BLOB, PRIMARY KEY(display,key)); CREATE TABLE IF NOT EXISTS state(id INTEGER PRIMARY KEY, value BLOB);"
        guard sqlite3_exec(db, schema, nil, nil, nil) == SQLITE_OK else { sqlite3_close(db); return false }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        database = db
        return true
    }

    func load() -> DisplayWindowMemory? {
        queue.sync {
            guard open() else { return nil }
            return read("SELECT value FROM state WHERE id=1", strings: [])
                .flatMap { try? JSONDecoder().decode(DisplayWindowMemory.self, from: $0) }
        }
    }

    func profile(display: String, key: String) -> RememberedWindowGeometry? {
        queue.sync {
            guard open() else { return nil }
            return read("SELECT value FROM profiles WHERE display=? AND key=?", strings: [display, key])
                .flatMap { try? JSONDecoder().decode(RememberedWindowGeometry.self, from: $0) }
        }
    }

    /// Import/upsert profiles and the small layout snapshot in one transaction.
    /// A failed commit leaves the legacy preferences and hot profiles intact.
    func save(_ memory: DisplayWindowMemory) -> Bool {
        queue.sync {
            guard open(), sqlite3_exec(database, "BEGIN IMMEDIATE", nil, nil, nil) == SQLITE_OK else { return false }
            var committed = false
            defer { if !committed { sqlite3_exec(database, "ROLLBACK", nil, nil, nil) } }
            var compact = memory
            for (display, stored) in memory.displays {
                var profiles = stored.openingFrames ?? [:]
                // Legacy size-only profiles have no position. Keep them in the
                // small state until they acquire a complete opening geometry.
                for (key, geometry) in profiles {
                    guard let data = try? JSONEncoder().encode(geometry),
                          write("INSERT INTO profiles VALUES(?,?,?) ON CONFLICT(display,key) DO UPDATE SET value=excluded.value WHERE value!=excluded.value", strings: [display, key], data: data)
                    else { return false }
                }
                profiles = profiles.filter { $0.key.hasSuffix(":") }
                compact.displays[display]?.openingFrames = profiles
                compact.displays[display]?.sizes = stored.sizes.filter {
                    $0.key.hasSuffix(":") || stored.openingFrames?[$0.key] == nil
                }
            }
            guard let data = try? JSONEncoder().encode(compact),
                  write("INSERT INTO state VALUES(1,?) ON CONFLICT(id) DO UPDATE SET value=excluded.value WHERE value!=excluded.value", strings: [], data: data),
                  sqlite3_exec(database, "COMMIT", nil, nil, nil) == SQLITE_OK else { return false }
            committed = true
            return true
        }
    }

    private func read(_ sql: String, strings: [String]) -> Data? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        bind(strings, to: statement)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        let count = Int(sqlite3_column_bytes(statement, 0))
        guard count > 0, let bytes = sqlite3_column_blob(statement, 0) else { return nil }
        return Data(bytes: bytes, count: count)
    }

    private func write(_ sql: String, strings: [String], data: Data) -> Bool {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(statement) }
        bind(strings, to: statement)
        let status = data.withUnsafeBytes {
            sqlite3_bind_blob(statement, Int32(strings.count + 1), $0.baseAddress, Int32($0.count), transient)
        }
        return status == SQLITE_OK && sqlite3_step(statement) == SQLITE_DONE
    }

    private func bind(_ strings: [String], to statement: OpaquePointer?) {
        for (index, string) in strings.enumerated() {
            _ = string.withCString { sqlite3_bind_text(statement, Int32(index + 1), $0, -1, transient) }
        }
    }
}
