import XCTest
@testable import StereoCore

final class ProgressTests: XCTestCase {
    func testCompleteProgressBlockAndUnits() throws {
        let parser = ProgressParser()
        for line in ["frame=240", "fps= 120.50", "out_time_us=10000000", "total_size=1048576", "speed=2.0x", "bitrate=838.9kbits/s"] {
            XCTAssertNil(parser.consume(line))
        }
        let stats = try XCTUnwrap(parser.consume("progress=continue"))
        XCTAssertEqual(stats.frame, 240)
        XCTAssertEqual(stats.fps, 120.5)
        XCTAssertEqual(stats.seconds, 10)
        XCTAssertEqual(stats.speed, 2)
        XCTAssertEqual(stats.bytes, 1048576)
        XCTAssertEqual(stats.fraction(duration: 100), 0.1)
        XCTAssertEqual(stats.remaining(duration: 100), 45)
        XCTAssertFalse(stats.ended)
    }

    func testMissingAndInvalidStatisticsDoNotBecomeMisleadingZeros() throws {
        let parser = ProgressParser()
        for line in ["fps=N/A", "speed=NaNx", "out_time_us=-9223372036854775808", "frame=-1", "total_size=N/A"] {
            _ = parser.consume(line)
        }
        let stats = try XCTUnwrap(parser.consume("progress=continue"))
        XCTAssertNil(stats.fps); XCTAssertNil(stats.speed); XCTAssertNil(stats.seconds)
        XCTAssertNil(stats.bytes); XCTAssertNil(stats.frame)
        XCTAssertNil(stats.fraction(duration: 20)); XCTAssertNil(stats.remaining(duration: 20))
    }

    func testEachBlockIsFreshAndEndIsNotPublication() throws {
        let parser = ProgressParser()
        _ = parser.consume("speed=4x")
        _ = parser.consume("progress=continue")
        _ = parser.consume("out_time_us=150000000")
        let stats = try XCTUnwrap(parser.consume("progress=end\r"))
        XCTAssertTrue(stats.ended)
        XCTAssertNil(stats.speed)
        XCTAssertEqual(stats.fraction(duration: 100), 1)
        XCTAssertNil(stats.remaining(duration: 100))
        XCTAssertNil(stats.fraction(duration: 0))
        XCTAssertNil(stats.fraction(duration: .infinity))
    }

    func testZeroSpeedCannotProduceInfiniteETA() {
        let stats = ProcessingStats(speed: 0, seconds: 5)
        XCTAssertNil(stats.remaining(duration: 10))
        XCTAssertEqual(ProcessingStats(speed: 2, seconds: 11).remaining(duration: 10), 0)
    }
}
