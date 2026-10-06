import Foundation
import Darwin

public struct MediaStream: Codable, Equatable, Sendable, Identifiable {
    public var index: Int
    public var codec_type: String?
    public var codec_name: String?
    public var channels: Int?
    public var sample_rate: String?
    public var tags: [String: String]?
    public var disposition: [String: Int]?
    public var id: Int { index }
    public var codec: String { codec_name?.lowercased() ?? "unknown" }
    public var isDefault: Bool { disposition?["default"] == 1 }
    public var rate: Int { Int(sample_rate ?? "") ?? 0 }
    public var language: String { tag("language") ?? "und" }
    public var title: String { tag("title") ?? "" }
    private func tag(_ name: String) -> String? {
        tags?.first { $0.key.lowercased() == name }?.value
    }
    public var label: String {
        var parts = ["#\(index)", language, codec.uppercased(), "\(channels ?? 0) ch", "\(rate) Hz"]
        if !title.isEmpty { parts.append(title) }
        if isDefault { parts.append("default") }
        return parts.joined(separator: " · ")
    }
}

public struct MediaProbe: Codable, Equatable, Sendable {
    public var streams: [MediaStream]
    public var format: FormatInfo?
    public var chapters: [Chapter]?
    public struct FormatInfo: Codable, Equatable, Sendable { public var duration: String? }
    public struct Chapter: Codable, Equatable, Sendable { public var id: Int? }
    public var audio: [MediaStream] { streams.filter { $0.codec_type == "audio" } }
    public var duration: Double { Double(format?.duration ?? "") ?? 0 }
}

public struct FileStamp: Equatable, Sendable {
    let size: UInt64
    let modified: Date
    let inode: UInt64
    public static func read(_ url: URL) throws -> FileStamp {
        let a = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let size = a[.size] as? NSNumber, let date = a[.modificationDate] as? Date,
              let inode = a[.systemFileNumber] as? NSNumber else {
            throw CleanupError.message("Cannot inspect source: \(url.lastPathComponent)")
        }
        return FileStamp(size: size.uint64Value, modified: date, inode: inode.uint64Value)
    }
}

public enum CleanupError: LocalizedError {
    case message(String)
    case cancelled
    case exists(URL)
    public var errorDescription: String? {
        switch self {
        case .message(let value): return value
        case .cancelled: return "Cancelled. The original is untouched."
        case .exists(let url): return "Output already exists; nothing overwritten: \(url.lastPathComponent)"
        }
    }
}

public enum AudioPolicy {
    public static let excluded: Set<String> = ["ac3", "eac3", "truehd", "mlp", "ac4", "dolby_e", "dts", "dca"]
    public static let videoExtensions: Set<String> = [
        "mkv", "mk3d", "mp4", "m4v", "mov", "qt", "avi", "divx", "mpg", "mpeg", "mpe", "m2v",
        "vob", "ts", "m2ts", "mts", "webm", "wmv", "asf", "flv", "f4v", "ogv", "ogm", "3gp", "3g2"
    ]
    public static func canCopy(_ s: MediaStream) -> Bool {
        s.codec_type == "audio" && s.channels == 2 && s.codec != "unknown" && !excluded.contains(s.codec)
    }
    public static func needsCleanup(_ p: MediaProbe) -> Bool {
        !p.audio.isEmpty && !(p.audio.count == 1 && canCopy(p.audio[0]))
    }
    public static func preferred(_ p: MediaProbe) -> MediaStream? {
        let stereo = p.audio.filter(canCopy)
        if !stereo.isEmpty {
            return stereo.sorted {
                if $0.isDefault != $1.isDefault { return $0.isDefault }
                return $0.index < $1.index
            }.first
        }
        return p.audio.sorted {
            if $0.isDefault != $1.isDefault { return $0.isDefault }
            if $0.channels != $1.channels { return ($0.channels ?? 0) > ($1.channels ?? 0) }
            if $0.rate != $1.rate { return $0.rate > $1.rate }
            return $0.index < $1.index
        }.first
    }
    public static func requiresMKV(_ input: URL, stream: MediaStream) -> Bool {
        !canCopy(stream) && ["webm", "ogv", "ogm"].contains(input.pathExtension.lowercased())
    }
    public static func outputURL(_ input: URL, mkv: Bool = false) -> URL {
        input.deletingPathExtension().appendingPathExtension("st").appendingPathExtension(mkv ? "mkv" : input.pathExtension)
    }
    public static func sourceWarning(probe: MediaProbe, chosen: MediaStream) -> Bool {
        probe.audio.contains { $0.isDefault && $0.index != chosen.index }
    }
}

public struct MediaCandidate: Identifiable, Sendable {
    public let url: URL
    public let probe: MediaProbe
    public let stamp: FileStamp
    public var selectedIndex: Int
    public var id: String { url.path }
    public var selected: MediaStream { probe.audio.first { $0.index == selectedIndex }! }
    public var requiresMKV: Bool { AudioPolicy.requiresMKV(url, stream: selected) }
    public var outputURL: URL { AudioPolicy.outputURL(url, mkv: requiresMKV) }
    public var warning: Bool { AudioPolicy.sourceWarning(probe: probe, chosen: selected) }
    public init(url: URL, probe: MediaProbe, stamp: FileStamp) {
        self.url = url; self.probe = probe; self.stamp = stamp
        self.selectedIndex = AudioPolicy.preferred(probe)!.index
    }
}

public enum FileSafety {
    public static func exists(_ url: URL) -> Bool {
        var info = stat()
        return url.path.withCString { lstat($0, &info) == 0 }
    }
    /// Atomic publication on macOS, with exclusive destination creation. Unlike
    /// a pre-check followed by move, RENAME_EXCL also protects concurrent writers.
    public static func publish(_ temporary: URL, to output: URL) throws {
        let result = temporary.path.withCString { src in
            output.path.withCString { dst in renamex_np(src, dst, UInt32(RENAME_EXCL)) }
        }
        if result != 0 {
            let code = errno
            if code == EEXIST { throw CleanupError.exists(output) }
            throw CleanupError.message("Could not safely publish output: \(String(cString: strerror(code))). Original untouched.")
        }
    }
}
