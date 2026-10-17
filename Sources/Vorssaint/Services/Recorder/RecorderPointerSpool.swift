// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint contributors

import CoreGraphics
import Foundation

/// Lossless, bounded buffering during recording, with no sampling-rate or
/// precision change. Slow/full/unavailable disks fall back to memory rather
/// than dropping pointer samples. Only the editing handoff materializes the
/// whole track, which the existing editor needs for offline smoothing.
final class RecorderPointerSpool {
    private struct Record {
        var time: Double
        var x: Double
        var y: Double
        var identity: UInt64
        var shape: Int64
        var visible: UInt64
    }
    private let queue = DispatchQueue(label: "com.vorssaint.recorder.pointer-spool", qos: .utility)
    private let stateLock = NSLock()
    private let writeData: (FileHandle, Data) throws -> Void
    private let chunkBytes: Int
    private var buffer = Data()
    private var deferredChunks: [Data] = [] // Sampling thread only.
    private var fallback = false
    private var pending = 0 // stateLock.
    private var writeFailed = false // stateLock.
    private var failedChunks: [Data] = [] // Writer queue only.
    private var writtenBytes = 0 // Writer queue only.
    private var handle: FileHandle?
    private let url: URL?
    private var count = 0
    private var preserveRecoveryFile = false

    init(directory: URL? = FileManager.default.temporaryDirectory, chunkSamples: Int = 4096,
         writeData: @escaping (FileHandle, Data) throws -> Void = { try $0.write(contentsOf: $1) }) {
        self.writeData = writeData
        chunkBytes = max(1, chunkSamples) * MemoryLayout<Record>.stride
        let path = directory?.appendingPathComponent("vorssaint-pointer-" + UUID().uuidString + ".spool")
        if let path, FileManager.default.createFile(atPath: path.path, contents: nil,
                                                     attributes: [.posixPermissions: 0o600]),
           let handle = try? FileHandle(forUpdating: path) {
            self.url = path
            self.handle = handle
        } else {
            if let path { try? FileManager.default.removeItem(at: path) }
            self.url = nil
            self.handle = nil
            fallback = true
        }
        buffer.reserveCapacity(chunkBytes)
    }

    deinit {
        // Enqueued writes capture self, so this runs only after they finish.
        try? handle?.close()
        if let url, !preserveRecoveryFile { try? FileManager.default.removeItem(at: url) }
    }

    func append(_ sample: RecorderMotion.Sample, identity: UInt64) {
        var record = Record(time: sample.time, x: sample.point.x, y: sample.point.y,
                            identity: identity, shape: Int64(sample.shapeIndex),
                            visible: sample.isPointerVisible ? 1 : 0)
        withUnsafeBytes(of: &record) { buffer.append(contentsOf: $0) }
        count += 1
        if buffer.count >= chunkBytes { flushBuffer() }
    }

    private func flushBuffer() {
        guard !buffer.isEmpty else { return }
        let data = buffer
        buffer = Data()
        buffer.reserveCapacity(chunkBytes)
        if !fallback {
            fallback = stateLock.withLock { () -> Bool in
                guard !writeFailed, pending < 4 else { return true }
                pending += 1
                return false
            }
        }
        if fallback { deferredChunks.append(data); return }
        queue.async { [self] in
            defer { stateLock.withLock { pending -= 1 } }
            if stateLock.withLock({ writeFailed }) { failedChunks.append(data); return }
            do {
                guard let handle else { throw CocoaError(.fileWriteUnknown) }
                try writeData(handle, data)
                writtenBytes += data.count
            } catch {
                // A failing write may have written only a prefix. Only count
                // complete successful chunks when reconstructing the track.
                try? handle?.truncate(atOffset: UInt64(writtenBytes))
                stateLock.withLock { writeFailed = true }
                failedChunks.append(data)
            }
        }
    }

    /// Stop the sampling producer before calling this method.
    func finish() throws -> (samples: [RecorderMotion.Sample], identities: [UInt64]) {
        flushBuffer()
        return try queue.sync {
            var samples: [RecorderMotion.Sample] = []
            var identities: [UInt64] = []
            samples.reserveCapacity(count)
            identities.reserveCapacity(count)
            func decode(_ data: Data) {
                data.withUnsafeBytes { bytes in
                    for offset in stride(from: 0, to: bytes.count - bytes.count % MemoryLayout<Record>.stride,
                                         by: MemoryLayout<Record>.stride) {
                        let record = bytes.loadUnaligned(fromByteOffset: offset, as: Record.self)
                        samples.append(RecorderMotion.Sample(time: record.time, point: CGPoint(x: record.x, y: record.y),
                                                             shapeIndex: Int(record.shape), isPointerVisible: record.visible != 0))
                        identities.append(record.identity)
                    }
                }
            }
            if writtenBytes > 0 {
                if let url, let data = try? Data(contentsOf: url, options: .mappedIfSafe), data.count >= writtenBytes {
                    decode(data.prefix(writtenBytes))
                } else if let handle {
                    // The temporary path can disappear while its descriptor
                    // remains valid. Read the already-open file in chunks.
                    try? handle.seek(toOffset: 0)
                    var remaining = writtenBytes
                    while remaining > 0 {
                        guard let data = try? handle.read(upToCount: min(chunkBytes, remaining)), !data.isEmpty else { break }
                        decode(data)
                        remaining -= data.count
                    }
                }
            }
            for data in failedChunks { decode(data) }
            for data in deferredChunks { decode(data) }
            guard samples.count == count, identities.count == count else {
                preserveRecoveryFile = true
                throw CocoaError(.fileReadUnknown, userInfo: url.map { [NSFilePathErrorKey: $0.path] } ?? [:])
            }
            failedChunks.removeAll(); deferredChunks.removeAll()
            count = 0
            try? handle?.close(); handle = nil
            if let url { try? FileManager.default.removeItem(at: url) }
            fallback = true
            return (samples, identities)
        }
    }
}
