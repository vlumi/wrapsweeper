import DonpaCore
import XCTest

@testable import DonpaKit

@MainActor
final class ScoreboardTests: XCTestCase {
    private let suiteName = "donpa.tests"
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    // MARK: Best time

    func testEmptyHasNoBestAndNoWins() {
        let board = Scoreboard(defaults: defaults)
        XCTAssertNil(board.best(for: .beginner))
        XCTAssertEqual(board.wins(for: .beginner), 0)
        XCTAssertTrue(
            board.isNewRecord(999, for: .beginner), "any time is a record on an empty board")
    }

    func testFirstSubmitSetsBest() {
        let board = Scoreboard(defaults: defaults)
        XCTAssertTrue(board.submit(42, for: .beginner))
        XCTAssertEqual(board.best(for: .beginner), 42)
    }

    func testFasterTimeReplacesBest() {
        let board = Scoreboard(defaults: defaults)
        board.submit(42, for: .beginner)
        XCTAssertTrue(board.isNewRecord(30, for: .beginner))
        XCTAssertTrue(board.submit(30, for: .beginner))
        XCTAssertEqual(board.best(for: .beginner), 30)
    }

    func testSlowerTimeKeepsBestButStillCounts() {
        let board = Scoreboard(defaults: defaults)
        board.submit(30, for: .beginner)
        XCTAssertFalse(board.isNewRecord(45, for: .beginner))
        XCTAssertFalse(board.submit(45, for: .beginner), "a slower time is not a new best")
        XCTAssertEqual(board.best(for: .beginner), 30, "best time is unchanged")
        XCTAssertEqual(board.wins(for: .beginner), 2, "but the win still counts")
    }

    func testEqualTimeIsNotABetterRecord() {
        let board = Scoreboard(defaults: defaults)
        board.submit(30, for: .beginner)
        XCTAssertFalse(board.isNewRecord(30, for: .beginner), "ties are not new records")
        XCTAssertFalse(board.submit(30, for: .beginner))
    }

    // MARK: Win counts

    func testEveryWinIncrementsTheClearCount() {
        let board = Scoreboard(defaults: defaults)
        board.submit(50, for: .beginner)  // best
        board.submit(40, for: .beginner)  // new best
        board.submit(60, for: .beginner)  // slower, still a clear
        XCTAssertEqual(board.wins(for: .beginner), 3)
        XCTAssertEqual(board.best(for: .beginner), 40)
    }

    func testWinsAndBestAreIndependentPerDifficulty() {
        let board = Scoreboard(defaults: defaults)
        board.submit(30, for: .beginner)
        board.submit(31, for: .beginner)
        board.submit(120, for: .expert)
        XCTAssertEqual(board.wins(for: .beginner), 2)
        XCTAssertEqual(board.wins(for: .expert), 1)
        XCTAssertEqual(board.wins(for: .intermediate), 0)
        XCTAssertEqual(board.best(for: .beginner), 30)
        XCTAssertEqual(board.best(for: .expert), 120)
    }

    func testRecordExposesWinsAndBest() {
        let board = Scoreboard(defaults: defaults)
        board.submit(30, for: .beginner)
        board.submit(20, for: .beginner)
        let r = board.record(for: .beginner)
        XCTAssertEqual(r?.wins, 2)
        XCTAssertEqual(r?.bestCentiseconds, 20)
    }

    // MARK: Persistence

    func testStatsPersistAcrossInstances() {
        let first = Scoreboard(defaults: defaults)
        first.submit(33, for: .intermediate)
        first.submit(35, for: .intermediate)
        let second = Scoreboard(defaults: defaults)
        XCTAssertEqual(second.best(for: .intermediate), 33)
        XCTAssertEqual(second.wins(for: .intermediate), 2)
    }

    func testResetClearsEverythingAndPersists() {
        let board = Scoreboard(defaults: defaults)
        board.submit(30, for: .beginner)
        board.submit(120, for: .expert)
        board.reset()
        XCTAssertNil(board.best(for: .beginner))
        XCTAssertEqual(board.wins(for: .expert), 0)
        let reloaded = Scoreboard(defaults: defaults)
        XCTAssertNil(reloaded.best(for: .beginner))
        XCTAssertEqual(reloaded.wins(for: .beginner), 0)
    }
}
