// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint contributors

import AVFoundation
import CoreMedia
import CoreVideo
import Foundation

/// Exercise the actual AVFoundation readiness path, including an audio track.
enum ResourceMediaTests {
    static func run(_ suite: TestSuite) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("vorssaint-ready-test-" + UUID().uuidString)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        do {
            let fixture = root.appendingPathComponent("source.mov")
            try makeFixture(fixture)
            let asset = AVURLAsset(url: fixture)
            let video = try wait { try await asset.loadTracks(withMediaType: .video) }
            let audio = try wait { try await asset.loadTracks(withMediaType: .audio) }
            guard let track = video.first else { throw TestError.fixture }
            let size = try wait { try await track.load(.naturalSize) }
            let transform = try wait { try await track.load(.preferredTransform) }
            let source = MediaVideoTargetEncoder.Source(asset: asset, videoTrack: track, audioTracks: audio,
                naturalSize: size, preferredTransform: transform, frameRate: 15)
            for includeAudio in [true, false] {
                var input = source
                if !includeAudio {
                    input = MediaVideoTargetEncoder.Source(asset: asset, videoTrack: track, audioTracks: [],
                        naturalSize: size, preferredTransform: transform, frameRate: 15)
                }
                let destination = root.appendingPathComponent(includeAudio ? "audio.mp4" : "silent.mp4")
                var progress: [Double] = []
                let bytes = try MediaVideoTargetEncoder.encode(source: input, trim: MediaTrimRange(start: 0, end: 2),
                    targetBytes: 200_000, destination: destination, isCancelled: { false }, progress: { progress.append($0) })
                let result = AVURLAsset(url: destination)
                let duration = try wait { try await result.load(.duration) }
                let resultVideo = try wait { try await result.loadTracks(withMediaType: .video) }
                let resultAudio = try wait { try await result.loadTracks(withMediaType: .audio) }
                suite.expect(bytes > 0 && bytes <= 200_000 && abs(duration.seconds - 2) < 0.15,
                             "readiness writer completes a real two-second target-size encode, audio=\(includeAudio)")
                suite.expect(resultVideo.count == 1
                    && resultAudio.count == (includeAudio ? 1 : 0),
                             "readiness writer preserves requested video/audio tracks without deadlock")
                suite.expect(zip(progress, progress.dropFirst()).allSatisfy { $0 <= $1 } && (progress.last ?? 0) > 0.9,
                             "readiness progress remains monotonic through actual frame writes")
            }
            var progressed = false
            do {
                _ = try MediaVideoTargetEncoder.encode(source: source, trim: MediaTrimRange(start: 0, end: 2),
                    targetBytes: 200_000, destination: root.appendingPathComponent("cancel.mp4"),
                    isCancelled: { progressed }, progress: { _ in progressed = true })
                suite.expect(false, "cancellation must abort a readiness encode")
            } catch MediaVideoTargetEncoder.EncodeError.cancelled {
                suite.expect(true, "mid-encode cancellation exits the actual AVFoundation readiness path")
            }
        } catch {
            suite.expect(false, "real readiness media test failed: \(error)")
        }
    }

    private enum TestError: Error { case fixture }

    private static func wait<T>(_ work: @escaping () async throws -> T) throws -> T {
        let done = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var result: Result<T, Error>?
        Task.detached {
            do { result = .success(try await work()) }
            catch { result = .failure(error) }
            done.signal()
        }
        guard done.wait(timeout: .now() + 15) == .success, let result else { throw TestError.fixture }
        return try result.get()
    }

    private static func makeFixture(_ url: URL) throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let video = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 64,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 64, kCVPixelBufferHeightKey as String: 64,
        ])
        let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false,
        ])
        writer.add(video); writer.add(audio)
        guard writer.startWriting() else { throw writer.error ?? TestError.fixture }
        writer.startSession(atSourceTime: .zero)
        var format = AudioStreamBasicDescription(mSampleRate: 48_000, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 8, mFramesPerPacket: 1, mBytesPerFrame: 8, mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0)
        var description: CMAudioFormatDescription?
        guard CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &format,
            layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil,
            formatDescriptionOut: &description) == noErr, let description else { throw TestError.fixture }
        let queue = DispatchQueue(label: "com.vorssaint.fixture-writer")
        let drained = DispatchGroup()
        drained.enter(); drained.enter()
        var frame = 0
        var audioFrame = 0
        var fixtureFailed = false
        video.requestMediaDataWhenReady(on: queue) {
            while video.isReadyForMoreMediaData {
                guard frame < 30 else { video.markAsFinished(); drained.leave(); return }
                var pixel: CVPixelBuffer?
                guard CVPixelBufferCreate(kCFAllocatorDefault, 64, 64, kCVPixelFormatType_32BGRA, nil, &pixel) == kCVReturnSuccess,
                      let pixel else { fixtureFailed = true; video.markAsFinished(); drained.leave(); return }
                CVPixelBufferLockBaseAddress(pixel, [])
                if let base = CVPixelBufferGetBaseAddress(pixel) {
                    memset(base, Int32(frame * 3), CVPixelBufferGetDataSize(pixel))
                }
                CVPixelBufferUnlockBaseAddress(pixel, [])
                if !adaptor.append(pixel, withPresentationTime: CMTime(value: Int64(frame), timescale: 15)) { fixtureFailed = true }
                frame += 1
            }
        }
        audio.requestMediaDataWhenReady(on: queue) {
            while audio.isReadyForMoreMediaData {
                guard audioFrame < 96_000 else { audio.markAsFinished(); drained.leave(); return }
                var block: CMBlockBuffer?
                var sample: CMSampleBuffer?
                let frames = 4800
                let bytes = frames * 8
                guard CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil,
                    blockLength: bytes, blockAllocator: kCFAllocatorDefault, customBlockSource: nil,
                    offsetToData: 0, dataLength: bytes, flags: 0, blockBufferOut: &block) == noErr,
                    let block else { fixtureFailed = true; audio.markAsFinished(); drained.leave(); return }
                _ = CMBlockBufferFillDataBytes(with: 0, blockBuffer: block, offsetIntoDestination: 0, dataLength: bytes)
                let status = CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: kCFAllocatorDefault,
                    dataBuffer: block, formatDescription: description, sampleCount: frames,
                    presentationTimeStamp: CMTime(value: Int64(audioFrame), timescale: 48_000),
                    packetDescriptions: nil, sampleBufferOut: &sample)
                if status != noErr || sample == nil || !audio.append(sample!) { fixtureFailed = true }
                audioFrame += frames
            }
        }
        guard drained.wait(timeout: .now() + 15) == .success else { writer.cancelWriting(); throw TestError.fixture }
        if fixtureFailed { writer.cancelWriting(); throw TestError.fixture }
        writer.endSession(atSourceTime: CMTime(value: 2, timescale: 1))
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        guard done.wait(timeout: .now() + 15) == .success, writer.status == .completed else { throw writer.error ?? TestError.fixture }
    }
}
