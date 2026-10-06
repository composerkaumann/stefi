import Foundation

public struct ToolPaths: Sendable {
    public let ffmpeg: URL
    public let ffprobe: URL
    public init(directory: URL) {
        ffmpeg = directory.appendingPathComponent("ffmpeg")
        ffprobe = directory.appendingPathComponent("ffprobe")
    }
    public var available: Bool {
        FileManager.default.isExecutableFile(atPath: ffmpeg.path) && FileManager.default.isExecutableFile(atPath: ffprobe.path)
    }
    public static func discover(custom: String? = nil, searchDirectories: [String]? = nil) -> ToolPaths? {
        var dirs = [URL]()
        if let custom, !custom.isEmpty { dirs.append(URL(fileURLWithPath: custom)) }
        let defaults = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]
            + (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        dirs += (searchDirectories ?? defaults).filter { $0.hasPrefix("/") }.map { URL(fileURLWithPath: $0) }
        return dirs.map(ToolPaths.init(directory:)).first { $0.available }
    }
}

public struct ScanResult: Sendable {
    public var candidates: [MediaCandidate] = []
    public var inspected = 0
    public var ready = 0
    public var warnings: [String] = []
}

public struct CleanupEngine: Sendable {
    public let tools: ToolPaths
    public init(tools: ToolPaths) { self.tools = tools }

    public func probe(_ url: URL, token: CancellationToken) throws -> MediaProbe {
        let result = try ProcessRunner.run(tools.ffprobe, [
            "-v", "error", "-show_entries",
            "stream=index,codec_type,codec_name,channels,sample_rate:stream_disposition=default:stream_tags=language,title:format=duration:chapter=id",
            "-of", "json", url.path
        ], token: token)
        guard result.status == 0 else { throw CleanupError.message("Cannot read \(url.lastPathComponent): \(result.stderr)") }
        return try JSONDecoder().decode(MediaProbe.self, from: result.stdout)
    }

    public func scan(_ directory: URL, token: CancellationToken,
                     progress: @Sendable (String, Int, Int) -> Void = { _, _, _ in }) throws -> ScanResult {
        let files = try FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: [])
            .filter { url in
                guard AudioPolicy.videoExtensions.contains(url.pathExtension.lowercased()),
                      let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else { return false }
                return values.isRegularFile == true && values.isSymbolicLink != true
            }.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        var result = ScanResult()
        for (index, url) in files.enumerated() {
            try token.check()
            progress(url.lastPathComponent, index + 1, files.count)
            do {
                let stamp = try FileStamp.read(url)
                let p = try probe(url, token: token)
                guard stamp == (try FileStamp.read(url)) else { throw CleanupError.message("File changed during scan: \(url.lastPathComponent)") }
                result.inspected += 1
                if p.audio.isEmpty { result.warnings.append("No audio: \(url.lastPathComponent)") }
                else if AudioPolicy.needsCleanup(p) { result.candidates.append(MediaCandidate(url: url, probe: p, stamp: stamp)) }
                else { result.ready += 1 }
            } catch {
                try token.check()
                result.warnings.append(error.localizedDescription)
            }
        }
        return result
    }

    public static func arguments(for candidate: MediaCandidate, temporary: URL) -> [String] {
        let stream = candidate.selected
        var args = ["-hide_banner", "-nostdin", "-n", "-xerror", "-progress", "pipe:1", "-stats_period", "0.5", "-nostats", "-i", candidate.url.path,
            "-map", "0:v?", "-map", "0:\(stream.index)", "-map", "0:s?", "-map", "0:d?", "-map", "0:t?",
            "-map_metadata", "0", "-map_chapters", "0"]
        if AudioPolicy.canCopy(stream) { args += ["-c", "copy"] }
        else {
            args += ["-c:v", "copy", "-c:s", "copy", "-c:d", "copy", "-c:t", "copy",
                     "-c:a:0", "aac", "-b:a:0", "320k", "-ac:a:0", "2", "-ar:a:0", String(stream.rate)]
        }
        args.append(temporary.path)
        return args
    }

    public static func validate(_ output: MediaProbe, against candidate: MediaCandidate) throws {
        guard output.audio.count == 1, let audio = output.audio.first, AudioPolicy.canCopy(audio) else {
            throw CleanupError.message("Validation failed: output must contain exactly one non-Dolby/non-DTS stereo stream.")
        }
        let original = candidate.selected
        let expected = AudioPolicy.canCopy(original) ? original.codec : "aac"
        guard audio.codec == expected, audio.rate == original.rate else {
            throw CleanupError.message("Validation failed: audio codec or sample rate changed unexpectedly.")
        }
        for type in ["video", "subtitle", "attachment", "data"] {
            let before = candidate.probe.streams.filter { $0.codec_type == type }.map(\.codec)
            let after = output.streams.filter { $0.codec_type == type }.map(\.codec)
            guard before == after else { throw CleanupError.message("Validation failed: \(type) stream count or codecs changed.") }
        }
        guard (candidate.probe.chapters?.count ?? 0) == (output.chapters?.count ?? 0) else {
            throw CleanupError.message("Validation failed: chapter count changed.")
        }
    }

    public func convert(_ candidate: MediaCandidate, allowMKV: Bool, token: CancellationToken,
                        progress: @escaping @Sendable (Double) -> Void = { _ in },
                        statistics: @escaping @Sendable (ProcessingStats) -> Void = { _ in },
                        phase: @escaping @Sendable (ProcessingPhase) -> Void = { _ in },
                        log: @escaping @Sendable (String) -> Void = { _ in }) throws -> URL {
        try token.check()
        guard !candidate.requiresMKV || allowMKV else { throw CleanupError.message("MKV output needs your approval.") }
        guard candidate.stamp == (try FileStamp.read(candidate.url)) else {
            throw CleanupError.message("Source changed since scanning. Please rescan before processing.")
        }
        let output = candidate.outputURL
        guard !FileSafety.exists(output) else { throw CleanupError.exists(output) }
        guard candidate.selected.rate > 0 else { throw CleanupError.message("Unknown source sample rate. No conversion performed.") }
        let scratch = candidate.url.deletingLastPathComponent().appendingPathComponent(".stereo-cleanup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        // Only our uniquely created scratch directory is ever removed.
        defer { try? FileManager.default.removeItem(at: scratch) }
        let temporary = scratch.appendingPathComponent("output").appendingPathExtension(output.pathExtension)
        log("\n\(candidate.url.lastPathComponent)\nSource: \(candidate.selected.label)\nOutput: \(output.lastPathComponent)\n")
        let parser = ProgressParser()
        phase(.processing)
        let result = try ProcessRunner.run(tools.ffmpeg, Self.arguments(for: candidate, temporary: temporary), token: token,
            onLine: { line in
                if let stats = parser.consume(line) {
                    statistics(stats)
                    if let fraction = stats.fraction(duration: candidate.probe.duration) {
                        progress(min(0.99, fraction))
                    }
                }
            }, onErrorText: log)
        guard result.status == 0 else { throw CleanupError.message("FFmpeg failed (\(result.status)).\n\(result.stderr.suffix(2500))") }
        try token.check()
        phase(.verifying)
        log("Checking audio, sample rate, copied streams and chapters…\n")
        let verified = try probe(temporary, token: token)
        try Self.validate(verified, against: candidate)
        guard candidate.stamp == (try FileStamp.read(candidate.url)) else {
            throw CleanupError.message("Source changed while processing. Output was not published.")
        }
        try token.check()
        phase(.publishing)
        try FileSafety.publish(temporary, to: output)
        progress(1)
        log("Verified and created: \(output.lastPathComponent)\n")
        return output
    }
}
