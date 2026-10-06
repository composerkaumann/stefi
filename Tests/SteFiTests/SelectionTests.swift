import XCTest
import StereoCore
@testable import SteFi

final class SelectionTests: XCTestCase {
    private func candidate() throws -> MediaCandidate {
        let probe = try JSONDecoder().decode(MediaProbe.self, from: Data(#"{"streams":[{"index":0,"codec_type":"audio","codec_name":"dts","channels":2,"sample_rate":"48000"}]}"#.utf8))
        let url = URL(fileURLWithPath: #filePath)
        return MediaCandidate(url: url, probe: probe, stamp: try FileStamp.read(url))
    }

    func testRowsStartUnchecked() throws {
        XCTAssertFalse(MovieRow(candidate: try candidate()).checked)
    }

    func testExplicitSelectionAndClearing() async throws {
        let candidate = try candidate()
        await MainActor.run {
            let model = AppModel()
            model.rows = [MovieRow(candidate: candidate)]
            XCTAssertEqual(model.pending.count, 1)
            XCTAssertTrue(model.selected.isEmpty)
            model.selectAll(true)
            XCTAssertEqual(model.selected.count, 1)
            model.selectAll(false)
            XCTAssertTrue(model.selected.isEmpty)
            model.rows[0].checked = true
            model.rows[0].output = candidate.url
            XCTAssertTrue(model.selected.isEmpty, "Completed outputs cannot be selected for processing again")
        }
    }

    func testScanAndRescanClearSelection() async throws {
        guard let tools = ToolPaths.discover() else { throw XCTSkip("FFmpeg required for scan integration test") }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("stefi-selection-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let result = try ProcessRunner.run(tools.ffmpeg, ["-v", "error", "-n", "-f", "lavfi", "-i", "anullsrc=r=48000:cl=5.1", "-t", "0.2", "-c:a", "ac3", root.appendingPathComponent("movie.mkv").path], token: CancellationToken())
        XCTAssertEqual(result.status, 0, result.stderr)
        let model = await MainActor.run { AppModel() }
        await MainActor.run { model.folder = root; model.scan() }
        try await waitUntilIdle(model)
        await MainActor.run {
            XCTAssertEqual(model.rows.count, 1)
            XCTAssertTrue(model.selected.isEmpty)
            model.selectAll(true)
            XCTAssertEqual(model.selected.count, 1)
            model.scan()
        }
        try await waitUntilIdle(model)
        await MainActor.run {
            XCTAssertEqual(model.rows.count, 1)
            XCTAssertTrue(model.selected.isEmpty, "Rescan must not restore previous selections")
        }
    }

    private func waitUntilIdle(_ model: AppModel) async throws {
        for _ in 0..<100 {
            if await MainActor.run(body: { !model.busy }) { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        await MainActor.run { model.stop() }
        XCTFail("Scan timed out")
    }
}
