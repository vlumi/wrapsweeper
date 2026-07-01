import XCTest

@testable import DonpaCore

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
        XCTAssertEqual(r?.wins.total, 2)
        XCTAssertEqual(r?.bestCentiseconds, 20)
    }

    // MARK: Progress %

    func testEmptyHasNoBestProgress() {
        let board = Scoreboard(defaults: defaults)
        XCTAssertNil(board.bestProgress(for: .beginner))
    }

    /// A recorded best TIME means the board was cleared → 100%, even if the wins
    /// counter reads 0 (the tolerant decode keeps best times but can reset counters;
    /// across devices the time merges independently of the wins sum). Guards the bug
    /// where a row showed "<100% AND a best time" for a board that was in fact
    /// cleared (often only on another synced device).
    func testBestTimeImpliesFullProgressEvenIfWinsCounterIsZero() {
        // A record carrying a best time but a zero wins counter and an old loss %.
        let key = GameConfig.beginner.storageKey
        writeRaw(
            #"{"version":1,"epoch":1,"records":{"\#(key)":"#
                + #"{"bestCentiseconds":1234,"bestLossProgress":0.97}}}"#
        )
        let board = Scoreboard(defaults: defaults)
        XCTAssertEqual(board.wins(for: .beginner), 0, "wins counter is zero in this record")
        XCTAssertEqual(board.best(for: .beginner), 1234, "but a best time is present")
        XCTAssertEqual(
            board.bestProgress(for: .beginner) ?? 0, 1.0, accuracy: 1e-9,
            "a best time means cleared → 100%, never the stale loss %")
    }

    func testLossProgressIsRecordedAndOnlyRises() {
        let board = Scoreboard(defaults: defaults)
        XCTAssertTrue(board.submitLossProgress(0.5, for: .beginner))
        XCTAssertEqual(board.bestProgress(for: .beginner) ?? 0, 0.5, accuracy: 1e-9)
        // A worse loss doesn't lower it.
        XCTAssertFalse(board.submitLossProgress(0.3, for: .beginner))
        XCTAssertEqual(board.bestProgress(for: .beginner) ?? 0, 0.5, accuracy: 1e-9)
        // A better loss raises it.
        XCTAssertTrue(board.submitLossProgress(0.8, for: .beginner))
        XCTAssertEqual(board.bestProgress(for: .beginner) ?? 0, 0.8, accuracy: 1e-9)
    }

    func testWinImpliesFullProgressRegardlessOfLosses() {
        let board = Scoreboard(defaults: defaults)
        board.submitLossProgress(0.6, for: .beginner)
        XCTAssertEqual(board.bestProgress(for: .beginner) ?? 0, 0.6, accuracy: 1e-9)
        board.submit(42, for: .beginner)  // a win
        XCTAssertEqual(
            board.bestProgress(for: .beginner) ?? 0, 1.0, accuracy: 1e-9,
            "any win means the board has been fully cleared")
    }

    func testLossAfterWinIsNeverANewBest() {
        let board = Scoreboard(defaults: defaults)
        board.submit(42, for: .beginner)  // a win → effective best is 100%
        // A subsequent loss, however far it got, can't beat a cleared board.
        XCTAssertFalse(
            board.submitLossProgress(0.58, for: .beginner),
            "a loss can't be a new best once the board has been won")
    }

    func testProgressPersistsAcrossInstances() {
        let first = Scoreboard(defaults: defaults)
        first.submitLossProgress(0.42, for: .expert)
        let second = Scoreboard(defaults: defaults)
        XCTAssertEqual(second.bestProgress(for: .expert) ?? 0, 0.42, accuracy: 1e-9)
    }

    /// A loss-only board (never won) still has a record, so the scoreboard view
    /// can list it to show its best %. A 0% loss records nothing (not a score).
    func testLossOnlyBoardHasARecord() {
        let board = Scoreboard(defaults: defaults)
        XCTAssertNil(board.record(for: .expert), "untouched board has no record")

        XCTAssertFalse(board.submitLossProgress(0, for: .expert))
        XCTAssertNil(board.record(for: .expert), "a 0% loss records nothing")

        board.submitLossProgress(0.3, for: .expert)
        XCTAssertNotNil(board.record(for: .expert), "a partial loss creates a record")
        XCTAssertEqual(board.wins(for: .expert), 0, "without a win")
    }

    // MARK: Recent-record highlight

    func testNewBestTimeMarksRecentRecord() {
        let board = Scoreboard(defaults: defaults)
        XCTAssertNil(board.recentRecord)
        board.submit(42, for: .beginner)
        XCTAssertEqual(board.recentRecord, GameConfig.beginner.storageKey)
    }

    func testSlowerTimeDoesNotMarkRecentRecord() {
        let board = Scoreboard(defaults: defaults)
        board.submit(30, for: .beginner)
        board.clearRecentRecord()
        board.submit(45, for: .beginner)  // a win, but not a new best
        XCTAssertNil(board.recentRecord)
    }

    func testNewBestLossProgressMarksRecentRecord() {
        let board = Scoreboard(defaults: defaults)
        board.submitLossProgress(0.5, for: .expert)
        XCTAssertEqual(board.recentRecord, GameConfig.expert.storageKey)
    }

    func testClearRecentRecordClearsIt() {
        let board = Scoreboard(defaults: defaults)
        board.submit(42, for: .beginner)
        board.clearRecentRecord()
        XCTAssertNil(board.recentRecord)
    }

    func testResetClearsRecentRecord() {
        let board = Scoreboard(defaults: defaults)
        board.submit(42, for: .beginner)
        board.reset()
        XCTAssertNil(board.recentRecord)
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

    // MARK: Format compatibility / resilience

    private let storeKey = "donpa.stats.v1"

    private func writeRaw(_ json: String) {
        defaults.set(Data(json.utf8), forKey: storeKey)
    }

    /// One corrupt record must not wipe the whole table — good rows survive.
    /// (A row with no salvageable best at all is dropped; see the per-entry loader.)
    func testOneBadRecordDoesNotWipeTheTable() {
        let good = GameConfig.beginner.storageKey
        let bad = GameConfig.expert.storageKey
        writeRaw(
            """
            {"version":1,"epoch":1,"records":{
              "\(good)":{"wins":{"mine":3},"bestCentiseconds":1234},
              "\(bad)":"totally-not-a-record"
            }}
            """)
        let board = Scoreboard(defaults: defaults)
        XCTAssertEqual(board.wins(for: .beginner), 3, "the valid record survived")
        XCTAssertEqual(board.best(for: .beginner), 1234)
        XCTAssertNil(board.record(for: .expert), "only the bad record was dropped")
    }

    /// Any pre-epoch local store (no `epoch` stamp — includes all pre-0.3 data) is
    /// dropped wholesale by the reset-epoch floor: this build ships at epoch 1, so
    /// blobs stamped below it are the one-off pre-release clean slate (see
    /// `StatsSyncCoordinator.epochFloor`). Even a best time doesn't survive — the
    /// board size/difficulty rebalance made those scores meaningless anyway.
    func testPreEpochRecordIsDroppedByTheResetFloor() {
        let key = GameConfig.intermediate.storageKey
        writeRaw(#"{"version":1,"records":{"\#(key)":{"wins":{"mine":2},"bestCentiseconds":900}}}"#)
        let board = Scoreboard(defaults: defaults)
        XCTAssertNil(
            board.record(for: .intermediate), "pre-epoch data is wiped, best time included")
        XCTAssertEqual(board.wins(for: .intermediate), 0)
    }

    /// A blob with no `epoch` field decodes as epoch 0 (the pre-upgrade baseline),
    /// so the reset floor treats it as pre-wipe data.
    func testDecodeEpochDefaultsToZeroWhenAbsent() {
        let key = GameConfig.beginner.storageKey
        let noEpoch = #"{"version":1,"records":{"\#(key)":{"wins":{"mine":1}}}}"#
        XCTAssertEqual(Scoreboard.decodeEpoch(Data(noEpoch.utf8)), 0)
        let withEpoch = #"{"version":1,"epoch":3,"records":{}}"#
        XCTAssertEqual(Scoreboard.decodeEpoch(Data(withEpoch.utf8)), 3)
    }

    /// The legacy bare-dict fallback (records at the top level, before the versioned
    /// envelope existed) still decodes — tested on the decoder directly, since the
    /// load path's epoch floor would otherwise drop such a blob before this matters.
    func testDecodeBlobReadsLegacyBareDict() {
        let key = GameConfig.beginner.storageKey
        let bare = #"{"\#(key)":{"wins":{"mine":4},"bestCentiseconds":700}}"#
        let records = Scoreboard.decodeBlob(Data(bare.utf8))
        XCTAssertEqual(records[key]?.wins.total, 4)
        XCTAssertEqual(records[key]?.bestCentiseconds, 700)
    }

    /// A save from a *newer* app (version > current) is not mis-read; rather than
    /// risk corrupting it we start empty (and a later write re-stamps it).
    func testRejectsNewerEnvelopeVersion() {
        let key = GameConfig.beginner.storageKey
        writeRaw(#"{"version":999,"records":{"\#(key)":{"wins":5}}}"#)
        let board = Scoreboard(defaults: defaults)
        XCTAssertEqual(board.wins(for: .beginner), 0, "a newer-version store isn't read")
    }

    /// Round-trips through the versioned envelope across instances.
    func testEnvelopeRoundTrips() {
        let first = Scoreboard(defaults: defaults)
        first.submit(50, for: .beginner)
        first.submitLossProgress(0.6, for: .expert)
        let second = Scoreboard(defaults: defaults)
        XCTAssertEqual(second.best(for: .beginner), 50)
        XCTAssertEqual(second.bestProgress(for: .expert) ?? 0, 0.6, accuracy: 1e-9)
    }
}
