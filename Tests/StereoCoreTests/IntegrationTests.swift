import XCTest
import CryptoKit
@testable import StereoCore

private final class StatsRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var stats: [ProcessingStats] = []
    private var phases: [ProcessingPhase] = []
    func append(_ value: ProcessingStats) { lock.lock(); defer { lock.unlock() }; stats.append(value) }
    func append(_ value: ProcessingPhase) { lock.lock(); defer { lock.unlock() }; phases.append(value) }
    func result() -> ([ProcessingStats], [ProcessingPhase]) { lock.lock(); defer { lock.unlock() }; return (stats, phases) }
}

final class IntegrationTests: XCTestCase {
    var root: URL!
    var tools: ToolPaths!
    var engine: CleanupEngine!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("stereo-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        guard let found = ToolPaths.discover(custom: ProcessInfo.processInfo.environment["STEREO_TEST_TOOLS"]) else {
            throw XCTSkip("Install FFmpeg/ffprobe or set STEREO_TEST_TOOLS to run real-media tests.")
        }
        tools = found; engine = CleanupEngine(tools: found)
    }
    override func tearDownWithError() throws { if let root { try FileManager.default.removeItem(at: root) } }
    func run(_ args: [String]) throws -> ProcessResult {
        let r = try ProcessRunner.run(tools.ffmpeg, args, token: CancellationToken())
        guard r.status == 0 else { throw CleanupError.message(r.stderr) }
        return r
    }
    func generate(_ name: String, codec: String = "aac", channels: Int = 2, rate: Int = 48000) throws -> URL {
        let url = root.appendingPathComponent(name)
        _ = try run(["-v", "error", "-f", "lavfi", "-i", "color=size=64x64:rate=2:duration=1",
                     "-f", "lavfi", "-i", "anoisesrc=sample_rate=\(rate):duration=1", "-map", "0:v", "-map", "1:a",
                     "-c:v", "mpeg4", "-c:a", codec, "-ac", String(channels), "-strict", "-2", url.path])
        return url
    }
    func candidate(_ url: URL) throws -> MediaCandidate {
        MediaCandidate(url: url, probe: try engine.probe(url, token: CancellationToken()), stamp: try FileStamp.read(url))
    }
    func digest(_ url: URL) throws -> String { SHA256.hash(data: try Data(contentsOf: url)).description }
    func packetHash(_ url: URL, stream: String) throws -> Data {
        try run(["-v", "error", "-i", url.path, "-map", stream, "-c", "copy", "-f", "hash", "-hash", "sha256", "-"]).stdout
    }

    func testScanIsNonrecursiveAndExcludesReadyFiles() throws {
        _ = try generate("ready.MP4")
        _ = try generate("Dolby's movie.mkv", codec: "ac3", channels: 6)
        let sub = root.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: false)
        try FileManager.default.copyItem(at: root.appendingPathComponent("Dolby's movie.mkv"), to: sub.appendingPathComponent("hidden.mkv"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("alias.mkv"), withDestinationURL: root.appendingPathComponent("Dolby's movie.mkv"))
        let result = try engine.scan(root, token: CancellationToken())
        XCTAssertEqual(result.inspected, 2)
        XCTAssertEqual(result.ready, 1)
        XCTAssertEqual(result.candidates.map { $0.url.lastPathComponent }, ["Dolby's movie.mkv"])
    }

    func testDTSStereoActuallyBecomesAACAt44100AndOriginalNeverChanges() throws {
        let source = try generate("DTS stereo.mkv", codec: "dca", rate: 44100)
        let before = try digest(source)
        let output = try engine.convert(try candidate(source), allowMKV: false, token: CancellationToken())
        let probe = try engine.probe(output, token: CancellationToken())
        XCTAssertEqual(probe.audio.count, 1)
        XCTAssertEqual(probe.audio.first?.codec, "aac")
        XCTAssertEqual(probe.audio.first?.channels, 2)
        XCTAssertEqual(probe.audio.first?.rate, 44100)
        XCTAssertEqual(try packetHash(source, stream: "0:v:0"), try packetHash(output, stream: "0:v:0"))
        XCTAssertEqual(try digest(source), before)
        let outputBefore = try digest(output)
        XCTAssertThrowsError(try engine.convert(try candidate(source), allowMKV: false, token: CancellationToken()))
        XCTAssertEqual(try digest(output), outputBefore)
    }

    func testRealFFmpegPublishesStatisticsAndVerificationPhases() throws {
        let source = try generate("progress.mkv", codec: "ac3", channels: 6)
        let recorder = StatsRecorder()
        _ = try engine.convert(try candidate(source), allowMKV: false, token: CancellationToken(),
                               statistics: { recorder.append($0) }, phase: { recorder.append($0) })
        let (stats, phases) = recorder.result()
        XCTAssertFalse(stats.isEmpty)
        XCTAssertTrue(try XCTUnwrap(stats.last).ended)
        XCTAssertGreaterThan(try XCTUnwrap(stats.last?.seconds), 0)
        XCTAssertGreaterThan(try XCTUnwrap(stats.last?.bytes), 0)
        XCTAssertEqual(phases, [.processing, .verifying, .publishing])
    }

    func testCopyKeepsAACSubtitlesAttachmentAndChapters() throws {
        let source = root.appendingPathComponent("DTS and AAC.mkv")
        let sub = root.appendingPathComponent("captions.srt")
        let meta = root.appendingPathComponent("chapters.ffmeta")
        let attachment = root.appendingPathComponent("notes.txt")
        try "1\n00:00:00,000 --> 00:00:00,800\nSubtitle test\n".write(to: sub, atomically: true, encoding: .utf8)
        try ";FFMETADATA1\n[CHAPTER]\nTIMEBASE=1/1000\nSTART=0\nEND=1000\ntitle=Chapter One\n".write(to: meta, atomically: true, encoding: .utf8)
        try "attachment test".write(to: attachment, atomically: true, encoding: .utf8)
        _ = try run(["-v", "error", "-f", "lavfi", "-i", "color=size=64x64:rate=2:duration=1",
                     "-f", "lavfi", "-i", "anoisesrc=sample_rate=48000:duration=1", "-i", sub.path, "-i", meta.path,
                     "-map", "0:v", "-map", "1:a", "-map", "1:a", "-map", "2:s", "-map", "2:s",
                     "-map_metadata", "3", "-map_chapters", "3", "-c:v", "mpeg4", "-c:a:0", "dca", "-strict", "-2",
                     "-c:a:1", "aac", "-ac", "2", "-c:s", "srt", "-disposition:a:0", "default", "-disposition:a:1", "0",
                     "-attach", attachment.path, "-metadata:s:t:0", "mimetype=text/plain", source.path])
        let c = try candidate(source)
        XCTAssertEqual(c.selected.index, 2)
        let output = try engine.convert(c, allowMKV: false, token: CancellationToken())
        XCTAssertEqual(try packetHash(source, stream: "0:a:1"), try packetHash(output, stream: "0:a:0"))
        XCTAssertEqual(try packetHash(source, stream: "0:s:0"), try packetHash(output, stream: "0:s:0"))
        let p = try engine.probe(output, token: CancellationToken())
        XCTAssertEqual(p.streams.filter { $0.codec_type == "subtitle" }.count, 2)
        XCTAssertEqual(p.streams.filter { $0.codec_type == "attachment" }.count, 1)
        XCTAssertEqual(p.chapters?.count, 1)
    }

    func testWebMRequiresExplicitMKVApproval() throws {
        let source = root.appendingPathComponent("surround.webm")
        _ = try run(["-v", "error", "-f", "lavfi", "-i", "color=size=64x64:rate=2:duration=1",
                     "-f", "lavfi", "-i", "anoisesrc=sample_rate=48000:duration=1", "-map", "0:v", "-map", "1:a",
                     "-c:v", "libvpx-vp9", "-c:a", "libopus", "-ac", "6", source.path])
        let c = try candidate(source)
        XCTAssertThrowsError(try engine.convert(c, allowMKV: false, token: CancellationToken()))
        XCTAssertFalse(FileSafety.exists(c.outputURL))
        let output = try engine.convert(c, allowMKV: true, token: CancellationToken())
        XCTAssertEqual(output.lastPathComponent, "surround.st.mkv")
        XCTAssertEqual(try engine.probe(output, token: CancellationToken()).audio.first?.rate, 48000)
    }

    func testCancelDuringFFmpegRemovesOnlyOwnedTemporaryFiles() throws {
        let source = try generate("cancel.mkv", codec: "ac3", channels: 6)
        let c = try candidate(source), before = try digest(source), token = CancellationToken()
        XCTAssertThrowsError(try engine.convert(c, allowMKV: false, token: token, log: { text in
            if text.contains("Input #0") { token.cancel() }
        }))
        XCTAssertFalse(FileSafety.exists(c.outputURL))
        XCTAssertEqual(try digest(source), before)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix(".stereo-cleanup-") })
    }

    func testExclusivePublishProtectsFilesAndDanglingSymlinks() throws {
        let tmp = root.appendingPathComponent("temp"), target = root.appendingPathComponent("target")
        try Data("new".utf8).write(to: tmp)
        try Data("existing".utf8).write(to: target)
        XCTAssertThrowsError(try FileSafety.publish(tmp, to: target))
        XCTAssertEqual(try String(contentsOf: target), "existing")
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: root.appendingPathComponent("missing").path)
        XCTAssertTrue(FileSafety.exists(link))
        XCTAssertThrowsError(try FileSafety.publish(tmp, to: link))
        let fresh = root.appendingPathComponent("fresh")
        try FileSafety.publish(tmp, to: fresh)
        XCTAssertEqual(try String(contentsOf: fresh), "new")
    }

    func testSourceChangedSinceScanIsRefused() throws {
        let source = try generate("changed.mkv", codec: "ac3", channels: 6)
        let c = try candidate(source)
        let handle = try FileHandle(forWritingTo: source)
        try handle.seekToEnd(); try handle.write(contentsOf: Data([0])); try handle.close()
        XCTAssertThrowsError(try engine.convert(c, allowMKV: false, token: CancellationToken()))
        XCTAssertFalse(FileSafety.exists(c.outputURL))
    }
}
