import Foundation

public enum ProcessingPhase: String, Sendable {
    case processing = "Processing"
    case verifying = "Verifying output"
    case publishing = "Saving verified output"
}

public struct ProcessingStats: Equatable, Sendable {
    public var frame: Int64?
    public var fps: Double?
    public var speed: Double?
    public var seconds: Double?
    public var bytes: Int64?
    public var ended: Bool
    public init(frame: Int64? = nil, fps: Double? = nil, speed: Double? = nil,
                seconds: Double? = nil, bytes: Int64? = nil, ended: Bool = false) {
        self.frame = frame; self.fps = fps; self.speed = speed
        self.seconds = seconds; self.bytes = bytes; self.ended = ended
    }
    public func fraction(duration: Double) -> Double? {
        guard duration.isFinite, duration > 0, let seconds, seconds.isFinite else { return nil }
        return min(1, max(0, seconds / duration))
    }
    public func remaining(duration: Double) -> Double? {
        guard duration.isFinite, duration > 0, let seconds, seconds.isFinite,
              let speed, speed.isFinite, speed > 0 else { return nil }
        return max(0, duration - seconds) / speed
    }
}

/// FFmpeg -progress publishes complete key=value blocks ending in progress=.
/// Ignore unrelated fields and treat N/A/invalid numbers as unavailable, not zero.
public final class ProgressParser: @unchecked Sendable {
    private let lock = NSLock()
    private var fields: [String: String] = [:]
    public init() {}
    public func consume(_ line: String) -> ProcessingStats? {
        lock.lock(); defer { lock.unlock() }
        guard let separator = line.firstIndex(of: "=") else { return nil }
        let key = String(line[..<separator])
        let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard ["frame", "fps", "speed", "out_time_us", "total_size", "progress"].contains(key) else { return nil }
        fields[key] = value
        guard key == "progress" else { return nil }
        defer { fields.removeAll(keepingCapacity: true) }
        guard value == "continue" || value == "end" else { return nil }
        func number(_ key: String) -> Double? {
            guard let raw = fields[key], let result = Double(raw.replacingOccurrences(of: "x", with: "")),
                  result.isFinite, result >= 0 else { return nil }
            return result
        }
        func integer(_ key: String) -> Int64? {
            guard let raw = fields[key], let result = Int64(raw), result >= 0 else { return nil }
            return result
        }
        return ProcessingStats(frame: integer("frame"), fps: number("fps"), speed: number("speed"),
            seconds: number("out_time_us").map { $0 / 1_000_000 }, bytes: integer("total_size"), ended: value == "end")
    }
}
