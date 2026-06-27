import XCTest

@testable import DonpaCore

/// A fake cloud: an in-memory blob dict shared between "devices" so the merge +
/// dual-write wiring can be tested without real KVS (which only works on device).
/// Writing notifies the *other* attached fakes' `onExternalChange`, modelling the
/// `didChangeExternallyNotification` that drives a live re-merge.
@MainActor
final class FakeCloud: CloudStatsStore {
    final class Shared {
        var blobs: [String: Data] = [:]
        var peers: [FakeCloud] = []
    }

    let shared: Shared
    var available: Bool
    var onExternalChange: (() -> Void)?

    init(shared: Shared = Shared(), available: Bool = true) {
        self.shared = shared
        self.available = available
        shared.peers.append(self)
    }

    var isAvailable: Bool { available }

    func writeOwnBlob(_ data: Data, deviceID: String) {
        guard available else { return }
        shared.blobs[deviceID] = data
        // Notify the other devices, as iCloud would.
        for peer in shared.peers where peer !== self {
            peer.onExternalChange?()
        }
    }

    func deleteOwnBlob(deviceID: String) {
        guard available else { return }
        shared.blobs[deviceID] = nil
        for peer in shared.peers where peer !== self { peer.onExternalChange?() }
    }

    func readAllBlobs() -> [String: Data] { available ? shared.blobs : [:] }
    func synchronize() {}
}

@MainActor
final class ScoreboardSyncTests: XCTestCase {
    private func defaults(_ id: String) -> UserDefaults {
        UserDefaults(suiteName: "sync-\(id)-\(UUID().uuidString)")!
    }

    func testWinSyncsToCloudAndMergesAcrossTwoDevices() {
        let shared = FakeCloud.Shared()
        let a = Scoreboard(defaults: defaults("a"), cloud: FakeCloud(shared: shared))
        let b = Scoreboard(defaults: defaults("b"), cloud: FakeCloud(shared: shared))

        a.submit(300, for: .beginner)  // A wins once → notifies B
        b.submit(250, for: .beginner)  // B wins once, faster → notifies A

        // Each device sees the union: 2 wins, best = the faster (min) time.
        XCTAssertEqual(a.wins(for: .beginner), 2)
        XCTAssertEqual(b.wins(for: .beginner), 2)
        XCTAssertEqual(a.best(for: .beginner), 250)
        XCTAssertEqual(b.best(for: .beginner), 250)
    }

    // MARK: "New record" is judged cross-device

    func testNewRecordComparesAgainstOtherDevicesBest() {
        let shared = FakeCloud.Shared()
        let a = Scoreboard(defaults: defaults("a"), cloud: FakeCloud(shared: shared))
        let b = Scoreboard(defaults: defaults("b"), cloud: FakeCloud(shared: shared))
        a.submit(250, for: .beginner)  // A sets 2.50s; B now sees it

        // B clears in 300 — slower than A's synced 250, so NOT a new record.
        XCTAssertFalse(
            b.submit(300, for: .beginner), "slower than another device's best is not a record")
        // B clears in 200 — beats the cross-device best, so it IS a record.
        XCTAssertTrue(b.submit(200, for: .beginner), "beating the cross-device best is a record")
        XCTAssertEqual(b.best(for: .beginner), 200)
    }

    func testNewLossProgressComparesCrossDevice() {
        let shared = FakeCloud.Shared()
        let a = Scoreboard(defaults: defaults("a"), cloud: FakeCloud(shared: shared))
        let b = Scoreboard(defaults: defaults("b"), cloud: FakeCloud(shared: shared))
        a.submitLossProgress(0.6, for: .expert)  // A's best loss %; B sees it
        XCTAssertFalse(
            b.submitLossProgress(0.5, for: .expert), "worse than another device's % is not best")
        XCTAssertTrue(
            b.submitLossProgress(0.8, for: .expert), "beating the cross-device % is a record")
    }

    func testOwnCountStaysSeparateFromOthers() {
        let shared = FakeCloud.Shared()
        let a = Scoreboard(defaults: defaults("a"), cloud: FakeCloud(shared: shared))
        let b = Scoreboard(defaults: defaults("b"), cloud: FakeCloud(shared: shared))
        a.submit(300, for: .beginner)
        a.submit(280, for: .beginner)
        b.submit(290, for: .beginner)
        XCTAssertEqual(a.wins(for: .beginner), 3, "2 own + 1 from B")
        XCTAssertEqual(b.wins(for: .beginner), 3, "1 own + 2 from A")
    }

    func testActivityCountsSumAcrossDevices() {
        let shared = FakeCloud.Shared()
        let a = Scoreboard(defaults: defaults("a"), cloud: FakeCloud(shared: shared))
        let b = Scoreboard(defaults: defaults("b"), cloud: FakeCloud(shared: shared))
        a.recordActivity(for: .beginner, tilesOpened: 100, flagsPlaced: 5, playtimeCentiseconds: 0)
        b.recordActivity(for: .beginner, tilesOpened: 40, flagsPlaced: 2, playtimeCentiseconds: 0)
        XCTAssertEqual(a.totalTilesOpened, 140)
        XCTAssertEqual(b.totalFlagsPlaced, 7)
    }

    func testSyncDisabledStaysLocalOnly() {
        let shared = FakeCloud.Shared()
        let a = Scoreboard(defaults: defaults("a"), cloud: FakeCloud(shared: shared))
        a.submit(300, for: .beginner)
        // B has sync OFF — doesn't see A, doesn't publish.
        let b = Scoreboard(
            defaults: defaults("b"), cloud: FakeCloud(shared: shared), syncEnabled: false)
        XCTAssertEqual(b.wins(for: .beginner), 0, "sync off → cloud not read")
        b.submit(100, for: .beginner)
        XCTAssertEqual(a.wins(for: .beginner), 1, "B (sync off) didn't publish to A")
    }

    func testSignedOutCloudIsLocalOnly() {
        let shared = FakeCloud.Shared()
        let a = Scoreboard(
            defaults: defaults("a"), cloud: FakeCloud(shared: shared, available: false))
        a.submit(300, for: .beginner)
        XCTAssertEqual(a.wins(for: .beginner), 1, "still works locally")
        XCTAssertTrue(shared.blobs.isEmpty, "nothing written to an unavailable cloud")
        XCTAssertFalse(a.isCloudActive)
    }

    func testOthersTotalsSurviveGoingOffline() {
        // A merges in B's win, then A's cloud goes unavailable (airplane mode):
        // the combined total must stay (from the cache), not collapse to A's own.
        let shared = FakeCloud.Shared()
        let aCloud = FakeCloud(shared: shared)
        let a = Scoreboard(defaults: defaults("a"), cloud: aCloud)
        let b = Scoreboard(defaults: defaults("b"), cloud: FakeCloud(shared: shared))
        a.submit(300, for: .beginner)  // A: 1
        b.submit(280, for: .beginner)  // B: 1 → A sees 2
        XCTAssertEqual(a.wins(for: .beginner), 2)

        aCloud.available = false  // A goes offline
        a.refreshFromCloud()  // a foreground refresh while offline (no-op on cloud)
        XCTAssertEqual(
            a.wins(for: .beginner), 2, "combined total persists offline (cached), not just own")
    }

    func testCachedMergeShownOnOfflineLaunch() {
        // A device that has synced before, relaunched while offline, shows the
        // last-known combined totals from the persisted cache.
        let shared = FakeCloud.Shared()
        let aDefaults = defaults("a")
        let a = Scoreboard(defaults: aDefaults, cloud: FakeCloud(shared: shared))
        let b = Scoreboard(defaults: defaults("b"), cloud: FakeCloud(shared: shared))
        a.submit(300, for: .beginner)
        b.submit(280, for: .beginner)
        XCTAssertEqual(a.wins(for: .beginner), 2)

        // Relaunch A on the SAME defaults but with an unavailable cloud (offline).
        let aOffline = Scoreboard(
            defaults: aDefaults, cloud: FakeCloud(shared: shared, available: false))
        XCTAssertEqual(
            aOffline.wins(for: .beginner), 2, "offline launch shows the cached merge")
    }

    func testTogglingSyncOnMergesInOtherDevices() {
        let shared = FakeCloud.Shared()
        let a = Scoreboard(defaults: defaults("a"), cloud: FakeCloud(shared: shared))
        a.submit(300, for: .beginner)
        let b = Scoreboard(
            defaults: defaults("b"), cloud: FakeCloud(shared: shared), syncEnabled: false)
        XCTAssertEqual(b.wins(for: .beginner), 0)
        b.syncEnabled = true  // flip on → pulls A's blob
        XCTAssertEqual(b.wins(for: .beginner), 1, "enabling sync merges in other devices")
        XCTAssertTrue(b.isCloudActive)
    }

    // MARK: Turning sync off / removing from all devices

    func testTurningSyncOffDeletesThisDeviceBlobFromCloud() {
        let shared = FakeCloud.Shared()
        let a = Scoreboard(defaults: defaults("a"), cloud: FakeCloud(shared: shared))
        let b = Scoreboard(defaults: defaults("b"), cloud: FakeCloud(shared: shared))
        a.submit(300, for: .beginner)
        b.submit(280, for: .beginner)
        XCTAssertEqual(b.wins(for: .beginner), 2)

        a.syncEnabled = false  // A opts out → its blob leaves the cloud
        // B no longer sees A's contribution (B keeps its own).
        XCTAssertEqual(b.wins(for: .beginner), 1, "A's blob removed from the cloud")
        // A still has its own scores locally.
        XCTAssertEqual(a.wins(for: .beginner), 1)
    }

    func testResetRemovesThisDeviceContributionFromOtherDevices() {
        let shared = FakeCloud.Shared()
        let a = Scoreboard(defaults: defaults("a"), cloud: FakeCloud(shared: shared))
        let b = Scoreboard(defaults: defaults("b"), cloud: FakeCloud(shared: shared))
        a.submit(300, for: .beginner)
        b.submit(280, for: .beginner)
        XCTAssertEqual(b.wins(for: .beginner), 2)

        a.reset()  // clears A's own count locally AND deletes its cloud blob
        // A's contribution is gone from the shared total on B (B keeps its own 1).
        XCTAssertEqual(b.wins(for: .beginner), 1, "A's contribution removed from B")
        // With sync ON, A still SEES B's win (it merges the cloud) — reset clears
        // A's own data, not the whole shared table.
        XCTAssertEqual(a.wins(for: .beginner), 1, "A now shows only B's contribution")
    }

    func testRefreshFromCloudPullsLatest() {
        // Simulates the app coming to the foreground: B pulls the cloud and picks
        // up A's win even without a live notification. (Use a non-notifying shared
        // store so only the explicit refresh delivers it.)
        let shared = FakeCloud.Shared()
        let aCloud = FakeCloud(shared: shared)
        let bCloud = FakeCloud(shared: shared)
        let a = Scoreboard(defaults: defaults("a"), cloud: aCloud)
        let b = Scoreboard(defaults: defaults("b"), cloud: bCloud)
        // Suppress B's live notification so we can prove refreshFromCloud is what
        // delivers the update.
        bCloud.onExternalChange = nil
        a.submit(300, for: .beginner)
        XCTAssertEqual(b.wins(for: .beginner), 0, "no live notification reached B yet")
        b.refreshFromCloud()
        XCTAssertEqual(b.wins(for: .beginner), 1, "foreground refresh pulls A's win")
    }

    func testRefreshFromCloudIsNoOpWhenSyncOff() {
        let shared = FakeCloud.Shared()
        let a = Scoreboard(defaults: defaults("a"), cloud: FakeCloud(shared: shared))
        a.submit(300, for: .beginner)
        let b = Scoreboard(
            defaults: defaults("b"), cloud: FakeCloud(shared: shared), syncEnabled: false)
        b.refreshFromCloud()  // sync off → must stay local-only
        XCTAssertEqual(b.wins(for: .beginner), 0)
    }

    func testRemovingADeviceLiveReducesOtherDeviceTotals() {
        // The key cross-device behaviour: when one device removes its scores, the
        // other device's totals drop LIVE via the external-change notification.
        let shared = FakeCloud.Shared()
        let a = Scoreboard(defaults: defaults("a"), cloud: FakeCloud(shared: shared))
        let b = Scoreboard(defaults: defaults("b"), cloud: FakeCloud(shared: shared))
        a.submit(300, for: .beginner)
        a.submit(290, for: .beginner)  // A: 2 wins
        b.submit(280, for: .beginner)  // B: 1 win
        XCTAssertEqual(b.wins(for: .beginner), 3, "B sees the combined total")

        a.syncEnabled = false  // A opts out elsewhere → B is notified and re-merges
        XCTAssertEqual(b.wins(for: .beginner), 1, "B's total drops to its own as A leaves")
    }
}
