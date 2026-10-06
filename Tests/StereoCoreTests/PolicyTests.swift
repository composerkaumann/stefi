import XCTest
@testable import StereoCore

final class PolicyTests: XCTestCase {
    func testMissingToolsAndExternalDiscovery() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        XCTAssertNil(ToolPaths.discover(searchDirectories: [folder.path]))
        let ffmpeg = folder.appendingPathComponent("ffmpeg")
        let ffprobe = folder.appendingPathComponent("ffprobe")
        try Data("test placeholder".utf8).write(to: ffmpeg)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ffmpeg.path)
        XCTAssertNil(ToolPaths.discover(searchDirectories: [folder.path]), "Both tools are required")
        try Data("test placeholder".utf8).write(to: ffprobe)
        XCTAssertNil(ToolPaths.discover(searchDirectories: [folder.path]), "Both tools must be executable")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ffprobe.path)
        XCTAssertEqual(ToolPaths.discover(searchDirectories: [folder.path])?.ffmpeg, ffmpeg)
        XCTAssertEqual(ToolPaths.discover(custom: folder.path, searchDirectories: [])?.ffprobe, ffprobe)
        XCTAssertNil(ToolPaths.discover(searchDirectories: []), "No fallback to bundled tools")
    }

    func stream(_ index: Int = 1, codec: String = "aac", channels: Int = 2, rate: String = "48000", isDefault: Bool = false, type: String = "audio") -> MediaStream {
        MediaStream(index: index, codec_type: type, codec_name: codec, channels: channels,
                    sample_rate: rate, tags: nil, disposition: ["default": isDefault ? 1 : 0])
    }
    func probe(_ streams: [MediaStream]) -> MediaProbe { MediaProbe(streams: streams, format: nil, chapters: []) }
    func candidate(_ streams: [MediaStream], name: String = "film.mkv") -> MediaCandidate {
        let p = probe(streams)
        return MediaCandidate(url: URL(fileURLWithPath: "/tmp/\(name)"), probe: p,
                              stamp: FileStamp(size: 0, modified: .distantPast, inode: 0))
    }

    func testAlreadyCleanAndNoAudioAreExcluded() {
        XCTAssertFalse(AudioPolicy.needsCleanup(probe([stream()])))
        XCTAssertFalse(AudioPolicy.needsCleanup(probe([])))
        XCTAssertTrue(AudioPolicy.needsCleanup(probe([stream(channels: 1)])))
    }

    func testAllDolbyAndDTSVariantsMustBeConvertedEvenAtTwoChannels() {
        for codec in AudioPolicy.excluded {
            let s = stream(codec: codec.uppercased())
            XCTAssertFalse(AudioPolicy.canCopy(s), codec)
            XCTAssertTrue(AudioPolicy.needsCleanup(probe([s])), codec)
        }
        XCTAssertFalse(AudioPolicy.canCopy(stream(codec: "unknown")))
    }

    func testExistingAACWinsOverDefaultDTSAndShowsWarning() {
        let p = probe([stream(1, codec: "dts", isDefault: true), stream(2)])
        XCTAssertEqual(AudioPolicy.preferred(p)?.index, 2)
        XCTAssertTrue(AudioPolicy.sourceWarning(probe: p, chosen: p.audio[1]))
    }

    func testItalianMonoAndEnglishStereoAreExplicitlyFlagged() {
        var italian = stream(1, channels: 1, isDefault: true)
        italian.tags = ["language": "ita"]
        var english = stream(2); english.tags = ["language": "eng", "title": "Commentary"]
        let c = candidate([italian, english])
        XCTAssertTrue(c.warning)
        XCTAssertEqual(c.selected.language, "eng")
        XCTAssertTrue(c.selected.label.contains("Commentary"))
        var override = c; override.selectedIndex = 1
        XCTAssertFalse(override.warning)
        XCTAssertFalse(AudioPolicy.canCopy(override.selected))
    }

    func testDefaultStereoPreferredAndTieBreakIsStable() {
        XCTAssertEqual(AudioPolicy.preferred(probe([stream(2), stream(4, codec: "flac", isDefault: true)]))?.index, 4)
        XCTAssertEqual(AudioPolicy.preferred(probe([stream(7), stream(3)]))?.index, 3)
    }

    func testSourcePreferenceMatchesScript() {
        let a = stream(1, codec: "ac3", channels: 6, rate: "44100")
        let b = stream(2, codec: "dts", channels: 8, rate: "48000")
        XCTAssertEqual(AudioPolicy.preferred(probe([a, b]))?.index, 2)
        var defaultA = a; defaultA.disposition = ["default": 1]
        XCTAssertEqual(AudioPolicy.preferred(probe([defaultA, b]))?.index, 1)
    }

    func testPathsAndMKVConsent() {
        let c = candidate([stream(codec: "opus", channels: 6)], name: "Film's [test].WEBM")
        XCTAssertTrue(c.requiresMKV)
        XCTAssertEqual(c.outputURL.lastPathComponent, "Film's [test].st.mkv")
        let copy = candidate([stream(), stream(2)], name: "Film.MKV")
        XCTAssertFalse(copy.requiresMKV)
        XCTAssertEqual(copy.outputURL.lastPathComponent, "Film.st.MKV")
    }

    func testArgumentsKeepInputAsSingleArgumentAndPreserveRate() {
        let c = candidate([stream(codec: "dts", rate: "44100")], name: "Film's $(touch NOTHING).mkv")
        let args = CleanupEngine.arguments(for: c, temporary: URL(fileURLWithPath: "/tmp/output.mkv"))
        XCTAssertEqual(args[args.firstIndex(of: "-i")! + 1], c.url.path)
        XCTAssertEqual(args[args.firstIndex(of: "-ar:a:0")! + 1], "44100")
        XCTAssertEqual(args[args.firstIndex(of: "-b:a:0")! + 1], "320k")
        XCTAssertTrue(args.contains("0:1")); XCTAssertTrue(args.contains("0:s?"))
        XCTAssertTrue(args.contains("-n")); XCTAssertTrue(args.contains("-xerror"))
        XCTAssertFalse(args.contains("0:a?"))
        let copy = CleanupEngine.arguments(for: candidate([stream(), stream(2)]), temporary: URL(fileURLWithPath: "/tmp/out.mkv"))
        XCTAssertFalse(copy.contains("-ar:a:0"))
        XCTAssertEqual(copy[copy.firstIndex(of: "-c")! + 1], "copy")
    }

    func testValidationRejectsWrongAudioOrDroppedStreams() throws {
        let video = stream(0, codec: "h264", type: "video")
        let subtitle = stream(2, codec: "subrip", type: "subtitle")
        let c = candidate([video, stream(codec: "dts"), subtitle])
        XCTAssertNoThrow(try CleanupEngine.validate(probe([video, stream(), subtitle]), against: c))
        XCTAssertThrowsError(try CleanupEngine.validate(probe([video, stream(codec: "dts"), subtitle]), against: c))
        XCTAssertThrowsError(try CleanupEngine.validate(probe([video, stream(rate: "44100"), subtitle]), against: c))
        XCTAssertThrowsError(try CleanupEngine.validate(probe([video, stream(), stream(3), subtitle]), against: c))
        XCTAssertThrowsError(try CleanupEngine.validate(probe([video, stream()]), against: c))
        XCTAssertThrowsError(try CleanupEngine.validate(probe([stream(), subtitle]), against: c))
    }
}
