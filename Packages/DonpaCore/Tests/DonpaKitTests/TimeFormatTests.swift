import XCTest

@testable import DonpaKit

final class TimeFormatTests: XCTestCase {
    func testZero() {
        XCTAssertEqual(TimeFormat.mmsst(centiseconds: 0), "0:00.0")
    }

    func testSubMinute() {
        XCTAssertEqual(TimeFormat.mmsst(centiseconds: 470), "0:04.7")  // 4.70s
        XCTAssertEqual(TimeFormat.mmsst(centiseconds: 9), "0:00.1")  // rounds 0.09→0.1
    }

    func testSecondsPadToTwoDigits() {
        XCTAssertEqual(TimeFormat.mmsst(centiseconds: 530), "0:05.3")
        XCTAssertEqual(TimeFormat.mmsst(centiseconds: 5900), "0:59.0")
    }

    func testMinutesRollOver() {
        XCTAssertEqual(TimeFormat.mmsst(centiseconds: 6000), "1:00.0")  // 60.00s
        XCTAssertEqual(TimeFormat.mmsst(centiseconds: 12553), "2:05.5")  // 125.53s → 2:05.5
    }

    func testUncappedLongTimes() {
        // Well past the old 999s cap (1000s = 16:40.0).
        XCTAssertEqual(TimeFormat.mmsst(centiseconds: 100_000), "16:40.0")
    }

    func testRoundsToNearestTenth() {
        XCTAssertEqual(TimeFormat.mmsst(centiseconds: 474), "0:04.7")  // 4.74 → 4.7
        XCTAssertEqual(TimeFormat.mmsst(centiseconds: 475), "0:04.8")  // 4.75 → 4.8
    }
}
