import XCTest

@testable import DonpaCore

@MainActor
final class CumulativeStatsTests: XCTestCase {
    private var defaults: UserDefaults!
    private let storeKey = "donpa.stats.v1"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "cumulative-\(UUID().uuidString)")
    }
    override func tearDown() {
        defaults.removePersistentDomain(forName: defaults.description)
        super.tearDown()
    }

    // MARK: DeviceCounter

    func testCounterAddsToOwnSlotAndSums() {
        var c = DeviceCounter()
        c.add(3)
        c.add(4)
        XCTAssertEqual(c.mine, 7)
        XCTAssertEqual(c.total, 7, "with no other devices, total == mine")
        c.setOthersTotal(10)  // as a sync read would
        XCTAssertEqual(c.mine, 7, "others doesn't touch mine")
        XCTAssertEqual(c.total, 17, "total sums mine + others")
    }

    func testCounterCodableRoundTripAndTolerantDecode() throws {
        let c = DeviceCounter(mine: 5, othersTotal: 2)
        let back = try JSONDecoder().decode(
            DeviceCounter.self, from: try JSONEncoder().encode(c))
        XCTAssertEqual(back, c)
        // Missing othersTotal defaults to 0 (only sync writes it).
        let partial = try JSONDecoder().decode(DeviceCounter.self, from: Data(#"{"mine":9}"#.utf8))
        XCTAssertEqual(partial.mine, 9)
        XCTAssertEqual(partial.othersTotal, 0)
    }

    // MARK: recordActivity + recordGameOutcome → per-config + global totals

    func testActivityAndOutcomeAccumulateAndGlobalTotalsSumAcrossConfigs() {
        let board = Scoreboard(defaults: defaults)
        board.recordActivity(
            for: .beginner, tilesOpened: 50, flagsPlaced: 6, playtimeCentiseconds: 1200)
        board.recordGameOutcome(for: .beginner, minesHit: 1, minesDisarmed: 4)
        board.recordActivity(
            for: .expert, tilesOpened: 200, flagsPlaced: 30, playtimeCentiseconds: 8000)
        board.recordGameOutcome(for: .expert, minesHit: 0, minesDisarmed: 99)
        // Per-config kept.
        XCTAssertEqual(board.record(for: .beginner)?.tilesOpened.total, 50)
        XCTAssertEqual(board.record(for: .expert)?.minesDisarmed.total, 99)
        // Global = sum across configs.
        XCTAssertEqual(board.totalGamesPlayed, 2)
        XCTAssertEqual(board.totalTilesOpened, 250)
        XCTAssertEqual(board.totalFlagsPlaced, 36)
        XCTAssertEqual(board.totalMinesHit, 1)
        XCTAssertEqual(board.totalMinesDisarmed, 103)
        XCTAssertEqual(board.totalPlaytimeCentiseconds, 9200)
    }

    func testGamesPlayedCountsEachOutcome() {
        let board = Scoreboard(defaults: defaults)
        for _ in 0..<5 { board.recordGameOutcome(for: .beginner, minesHit: 1, minesDisarmed: 0) }
        XCTAssertEqual(board.totalGamesPlayed, 5)
    }

    /// Activity accrues live during play (and an abandoned game keeps its effort)
    /// WITHOUT counting a game played — only an outcome bumps games-played.
    func testActivityAloneIsNotAGamePlayed() {
        let board = Scoreboard(defaults: defaults)
        // Two flushes during play, then the game is abandoned (no outcome).
        board.recordActivity(
            for: .beginner, tilesOpened: 8, flagsPlaced: 2, playtimeCentiseconds: 250)
        board.recordActivity(
            for: .beginner, tilesOpened: 4, flagsPlaced: 1, playtimeCentiseconds: 150)
        XCTAssertEqual(board.totalGamesPlayed, 0, "activity alone is not a game played")
        XCTAssertEqual(board.totalTilesOpened, 12, "but the dug tiles still count")
        XCTAssertEqual(board.totalFlagsPlaced, 3)
        XCTAssertEqual(board.totalPlaytimeCentiseconds, 400)
        XCTAssertEqual(board.totalMinesHit, 0)

        // A later finished game records the outcome → games-played increments.
        board.recordActivity(
            for: .beginner, tilesOpened: 5, flagsPlaced: 1, playtimeCentiseconds: 100)
        board.recordGameOutcome(for: .beginner, minesHit: 1, minesDisarmed: 0)
        XCTAssertEqual(board.totalGamesPlayed, 1)
        XCTAssertEqual(board.totalTilesOpened, 17, "activity accumulates across all flushes")
    }

    /// An empty flush (no deltas) records nothing — keeps idle pauses cheap.
    func testEmptyActivityFlushIsANoOp() {
        let board = Scoreboard(defaults: defaults)
        board.recordActivity(
            for: .beginner, tilesOpened: 0, flagsPlaced: 0, playtimeCentiseconds: 0)
        XCTAssertNil(board.record(for: .beginner))
    }

    // MARK: wins still works through the counter; persists

    func testWinsCountViaCounterAndPersists() {
        let board = Scoreboard(defaults: defaults)
        board.submit(30, for: .beginner)
        board.submit(40, for: .beginner)
        XCTAssertEqual(board.wins(for: .beginner), 2)
        XCTAssertEqual(board.totalWins, 2)
        // Reload from the same defaults — counters persist.
        let reloaded = Scoreboard(defaults: defaults)
        XCTAssertEqual(reloaded.wins(for: .beginner), 2)
    }

    // MARK: disarmed mines (the board-level computation)

    func testDisarmedMineCountIsFlaggedMinesOnly() {
        var board = Board(topology: BoundedSquareTopology(width: 4, height: 4))
        board.placeMines(at: [Coord(0, 0), Coord(3, 3), Coord(0, 3)])
        XCTAssertEqual(board.disarmedMineCount, 0)
        board[Coord(0, 0)].state = .flagged  // correct
        board[Coord(1, 1)].state = .flagged  // wrong (not a mine)
        XCTAssertEqual(board.disarmedMineCount, 1, "only flagged MINES count")
        board[Coord(3, 3)].state = .flagged
        XCTAssertEqual(board.disarmedMineCount, 2)
    }
}
