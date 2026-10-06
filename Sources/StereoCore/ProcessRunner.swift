import Foundation
import Darwin

public final class CancellationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false
    private var process: Process?
    public init() {}
    public var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
    public func check() throws { if isCancelled { throw CleanupError.cancelled } }
    fileprivate func launch(_ p: Process) throws {
        lock.lock(); defer { lock.unlock() }
        if stopped { throw CleanupError.cancelled }
        try p.run()
        process = p
    }
    fileprivate func clear(_ p: Process) {
        lock.lock(); defer { lock.unlock() }
        if process === p { process = nil }
    }
    public func cancel() {
        lock.lock(); stopped = true; let p = process; lock.unlock()
        if let p, p.isRunning {
            p.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                if p.isRunning { kill(p.processIdentifier, SIGKILL) }
            }
        }
    }
}

private final class DataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    func set(_ value: Data) { lock.lock(); data = value; lock.unlock() }
    func get() -> Data { lock.lock(); defer { lock.unlock() }; return data }
}

public struct ProcessResult: Sendable {
    public let status: Int32
    public let stdout: Data
    public let stderr: String
}

public enum ProcessRunner {
    /// Must be called off the main actor. Both pipes are continuously drained,
    /// including on cancellation, so FFmpeg cannot deadlock on a full stderr pipe.
    public static func run(_ executable: URL, _ arguments: [String], token: CancellationToken,
                           onLine: (@Sendable (String) -> Void)? = nil,
                           onErrorText: (@Sendable (String) -> Void)? = nil) throws -> ProcessResult {
        let p = Process()
        p.executableURL = executable
        p.arguments = arguments
        p.standardInput = FileHandle.nullDevice
        let output = Pipe(), errors = Pipe()
        p.standardOutput = output; p.standardError = errors
        let outBox = DataBox(), errBox = DataBox(), readers = DispatchGroup()
        try token.launch(p)
        defer { token.clear(p) }
        for (handle, box, isOutput) in [(output.fileHandleForReading, outBox, true), (errors.fileHandleForReading, errBox, false)] {
            readers.enter()
            DispatchQueue.global(qos: .utility).async {
                defer { readers.leave(); try? handle.close() }
                var capture = Data(), pending = Data()
                while true {
                    let data = handle.availableData
                    if data.isEmpty { break }
                    // Probe JSON and diagnostic tails are bounded in memory.
                    capture.append(data)
                    let limit = isOutput ? 16 * 1024 * 1024 : 512 * 1024
                    if capture.count > limit { capture.removeFirst(capture.count - limit) }
                    if isOutput, let onLine {
                        pending.append(data)
                        while let end = pending.firstIndex(of: 10) {
                            onLine(String(decoding: pending[..<end], as: UTF8.self))
                            pending.removeSubrange(...end)
                        }
                    } else if !isOutput {
                        onErrorText?(String(decoding: data, as: UTF8.self))
                    }
                }
                if isOutput, !pending.isEmpty { onLine?(String(decoding: pending, as: UTF8.self)) }
                box.set(capture)
            }
        }
        p.waitUntilExit()
        readers.wait()
        try token.check()
        return ProcessResult(status: p.terminationStatus, stdout: outBox.get(), stderr: String(decoding: errBox.get(), as: UTF8.self))
    }
}
