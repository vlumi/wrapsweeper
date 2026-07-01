import XCTest

@testable import DonpaCore

/// The cross-device merge is a pure function, so these are the high-value sync
/// tests (KVS itself can only be verified on real devices). Each `ScoreRecord`
/// here uses `DeviceCounter(mine:)` to stand for one device's own count.
final class StatsMergeTests: XCTestCase {
    private let key = GameConfig.beginner.storageKey

    private func rec(
        wins: Int = 0, games: Int = 0, tiles: Int = 0, best: Int? = nil, loss: Double? = nil
    ) -> ScoreRecord {
        // A device-owned best is a (time, date) pair kept in `topTimes`; the merge
        // projects `best` from it. Date is fixed — the merge picks by time, not date.
        let bestTime = best.map {
            BestTime(centiseconds: $0, achievedAt: Date(timeIntervalSince1970: 0))
        }
        return ScoreRecord(
            wins: .init(mine: wins), gamesPlayed: .init(mine: games),
            tilesOpened: .init(mine: tiles), best: bestTime,
            topTimes: bestTime.map { [$0] } ?? [], bestLossProgress: loss)
    }

    // MARK: Counters sum across devices

    func testCountersSumOwnPlusOthers() {
        let mine = [key: rec(wins: 3, tiles: 100)]
        let others = ["dev-b": [key: rec(wins: 5, tiles: 40)]]
        let merged = StatsMerge.merge(mine: mine, others: others)
        let r = merged[key]!
        XCTAssertEqual(r.wins.mine, 3, "my own count is untouched")
        XCTAssertEqual(r.wins.othersTotal, 5, "others' counts are cached as othersTotal")
        XCTAssertEqual(r.wins.total, 8, "displayed total sums all devices")
        XCTAssertEqual(r.tilesOpened.total, 140)
    }

    func testSumsAcrossManyDevices() {
        let mine = [key: rec(games: 1)]
        let others = [
            "b": [key: rec(games: 2)],
            "c": [key: rec(games: 4)],
        ]
        XCTAssertEqual(StatsMerge.merge(mine: mine, others: others)[key]!.gamesPlayed.total, 7)
    }

    // MARK: Idempotent / order-independent (the conflict-free guarantees)

    func testReReadingSameBlobDoesNotInflate() {
        // A stored blob carries a stale othersTotal; the merge must ignore it and
        // only ever sum `mine`, so re-syncing the same data can't double-count.
        var theirs = rec(wins: 5)
        theirs.wins.setOthersTotal(999)  // stale junk in their stored blob
        let merged = StatsMerge.merge(mine: [key: rec(wins: 3)], others: ["b": [key: theirs]])
        XCTAssertEqual(merged[key]!.wins.total, 8, "stale othersTotal in a blob is ignored")
    }

    func testOrderIndependent() {
        let a = [key: rec(wins: 1)]
        let b = [key: rec(wins: 2)]
        let c = [key: rec(wins: 4)]
        let m1 = StatsMerge.merge(mine: a, others: ["b": b, "c": c])
        let m2 = StatsMerge.merge(mine: a, others: ["c": c, "b": b])
        XCTAssertEqual(m1, m2)
        XCTAssertEqual(m1[key]!.wins.total, 7)
    }

    func testConcurrentTwoDevicePlayDoesNotDoubleCount() {
        // Each device independently played 10 games offline; after sync each sees
        // 20 total, with its own 10 in `mine` — no double-count, no lost updates.
        let deviceA = [key: rec(games: 10)]
        let deviceB = [key: rec(games: 10)]
        let aSees = StatsMerge.merge(mine: deviceA, others: ["B": deviceB])
        let bSees = StatsMerge.merge(mine: deviceB, others: ["A": deviceA])
        XCTAssertEqual(aSees[key]!.gamesPlayed.total, 20)
        XCTAssertEqual(bSees[key]!.gamesPlayed.total, 20)
        XCTAssertEqual(aSees[key]!.gamesPlayed.mine, 10)
    }

    // MARK: Best fields → min/max across all devices

    func testBestTimeIsMinAcrossDevices() {
        let mine = [key: rec(best: 500)]
        let others = ["b": [key: rec(best: 320)], "c": [key: rec(best: 900)]]
        XCTAssertEqual(StatsMerge.merge(mine: mine, others: others)[key]!.bestCentiseconds, 320)
    }

    func testBestLossProgressIsMaxAcrossDevices() {
        let mine = [key: rec(loss: 0.4)]
        let others = ["b": [key: rec(loss: 0.7)]]
        XCTAssertEqual(
            StatsMerge.merge(mine: mine, others: others)[key]!.bestLossProgress ?? 0, 0.7,
            accuracy: 1e-9)
    }

    func testBestTimeNilWhenNobodyHasOne() {
        let merged = StatsMerge.merge(mine: [key: rec(wins: 1)], others: ["b": [key: rec(wins: 1)]])
        XCTAssertNil(merged[key]!.bestCentiseconds)
    }

    // MARK: Config keys present on only some devices

    func testConfigOnlyOnAnotherDeviceStillAppears() {
        let expert = GameConfig.expert.storageKey
        let mine: [String: ScoreRecord] = [:]  // this device never played expert
        let others = ["b": [expert: rec(wins: 2, best: 1234)]]
        let merged = StatsMerge.merge(mine: mine, others: others)
        XCTAssertEqual(merged[expert]?.wins.total, 2)
        XCTAssertEqual(merged[expert]?.bestCentiseconds, 1234)
        XCTAssertEqual(merged[expert]?.wins.mine, 0, "this device contributed nothing")
    }

    func testEmptyOthersIsIdentityOnTotals() {
        let mine = [key: rec(wins: 3, tiles: 50, best: 200)]
        let merged = StatsMerge.merge(mine: mine, others: [:])
        XCTAssertEqual(merged[key]!.wins.total, 3)
        XCTAssertEqual(merged[key]!.tilesOpened.total, 50)
        XCTAssertEqual(merged[key]!.bestCentiseconds, 200)
    }

    // MARK: Device-owned best time + timestamp (merged only for view)

    /// The whole point of device-owned bests: the winning time's TIMESTAMP travels
    /// with it. Merging must pick the faster device's (time, date) pair intact —
    /// never the fast time with the wrong device's date.
    func testBestTimestampTravelsWithItsValue() {
        let mineDate = Date(timeIntervalSince1970: 1000)
        let fastDate = Date(timeIntervalSince1970: 2000)
        var mine = ScoreRecord()
        mine.best = BestTime(centiseconds: 500, achievedAt: mineDate)
        mine.topTimes = [mine.best!]
        var theirs = ScoreRecord()
        theirs.best = BestTime(centiseconds: 300, achievedAt: fastDate)
        theirs.topTimes = [theirs.best!]
        let merged = StatsMerge.merge(mine: [key: mine], others: ["b": [key: theirs]])[key]!
        XCTAssertEqual(merged.best?.centiseconds, 300, "view shows the cross-device fastest")
        XCTAssertEqual(
            merged.best?.achievedAt, fastDate, "and its OWN timestamp, not the loser's date")
    }

    /// A device's OWN record keeps its own best untouched by the merge — the display
    /// projection doesn't overwrite the stored own value.
    func testOwnBestIsNotOverwrittenByAFasterOtherDevice() {
        var mine = ScoreRecord()
        mine.best = BestTime(centiseconds: 500, achievedAt: Date(timeIntervalSince1970: 0))
        mine.topTimes = [mine.best!]
        let orig = mine
        var theirs = ScoreRecord()
        theirs.best = BestTime(centiseconds: 100, achievedAt: Date(timeIntervalSince1970: 0))
        theirs.topTimes = [theirs.best!]
        _ = StatsMerge.merge(mine: [key: mine], others: ["b": [key: theirs]])
        XCTAssertEqual(mine, orig, "merge is pure — this device's own stored record is unchanged")
    }

    /// Top-N merges to the fastest `topTimeLimit` across all devices, fastest first.
    func testTopTimesMergeToFastestAcrossDevices() {
        func t(_ cs: Int) -> BestTime {
            BestTime(centiseconds: cs, achievedAt: Date(timeIntervalSince1970: 0))
        }
        var mine = ScoreRecord()
        mine.topTimes = [t(300), t(500), t(700)]
        var theirs = ScoreRecord()
        theirs.topTimes = [t(200), t(400), t(600), t(800)]
        let merged = StatsMerge.merge(mine: [key: mine], others: ["b": [key: theirs]])[key]!
        XCTAssertEqual(
            merged.topTimes.map(\.centiseconds), [200, 300, 400, 500, 600],
            "fastest 5 across both devices")
    }

    /// Dates merge as earliest-first-played / latest-last-played.
    func testPlayedDatesMergeMinFirstMaxLast() {
        var mine = ScoreRecord()
        mine.firstPlayed = Date(timeIntervalSince1970: 500)
        mine.lastPlayed = Date(timeIntervalSince1970: 800)
        var theirs = ScoreRecord()
        theirs.firstPlayed = Date(timeIntervalSince1970: 300)
        theirs.lastPlayed = Date(timeIntervalSince1970: 900)
        let merged = StatsMerge.merge(mine: [key: mine], others: ["b": [key: theirs]])[key]!
        XCTAssertEqual(
            merged.firstPlayed, Date(timeIntervalSince1970: 300), "earliest first-played")
        XCTAssertEqual(merged.lastPlayed, Date(timeIntervalSince1970: 900), "latest last-played")
    }

    /// The new skill counters sum across devices like the others.
    func testSkillCountersSumAcrossDevices() {
        var mine = ScoreRecord()
        mine.noFlagWins.add(2)
        mine.chordsUsed.add(10)
        var theirs = ScoreRecord()
        theirs.noFlagWins.add(3)
        theirs.chordsUsed.add(5)
        let merged = StatsMerge.merge(mine: [key: mine], others: ["b": [key: theirs]])[key]!
        XCTAssertEqual(merged.noFlagWins.total, 5)
        XCTAssertEqual(merged.chordsUsed.total, 15)
    }
}
