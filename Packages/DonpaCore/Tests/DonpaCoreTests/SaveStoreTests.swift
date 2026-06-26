import XCTest

@testable import DonpaCore

final class SaveStoreTests: XCTestCase {
    private var store: SaveStore!
    private var dir: URL!
    private var filename: String!

    override func setUp() {
        super.setUp()
        // A unique file in the temp dir, so tests don't collide or touch the
        // real App Support save.
        dir = FileManager.default.temporaryDirectory
        filename = "test-save-\(UUID().uuidString).json"
        store = SaveStore(directory: dir, filename: filename)
        store.clear()
    }

    override func tearDown() {
        store.clear()
        super.tearDown()
    }

    private func sampleSnapshot() -> GameSnapshot {
        let config = GameConfig.classic(.beginner)
        var game = Game(config: config)
        game.reveal(Coord(0, 0))
        return GameSnapshot(game: game, config: config, elapsedCentiseconds: 500)!
    }

    func testSaveThenLoadRoundTrips() {
        XCTAssertNil(store.load())
        let snap = sampleSnapshot()
        store.save(snap)
        XCTAssertTrue(store.hasSave)
        let loaded = store.load()
        XCTAssertEqual(loaded?.elapsedCentiseconds, 500)
        XCTAssertEqual(loaded?.mines, snap.mines)
    }

    func testAppSupportFactoryProducesAUsableStore() {
        // Exercise the production factory (App Support dir), but with a unique
        // filename so it can't touch a real save; clean up after.
        let appStore = SaveStore.appSupport(filename: "test-appsupport-\(UUID().uuidString).json")
        defer { appStore.clear() }
        XCTAssertNil(appStore.load())
        appStore.save(sampleSnapshot())
        XCTAssertTrue(appStore.hasSave)
        XCTAssertEqual(appStore.load()?.elapsedCentiseconds, 500)
    }

    func testClearRemovesTheSave() {
        store.save(sampleSnapshot())
        store.clear()
        XCTAssertFalse(store.hasSave)
        XCTAssertNil(store.load())
    }

    func testLoadToleratesGarbage() throws {
        // A corrupt/partial file must decode to nil, never throw or crash.
        let url = dir.appendingPathComponent(filename)
        try Data("not json at all".utf8).write(to: url)
        XCTAssertNil(store.load())
    }

    func testLoadRejectsNewerVersion() throws {
        // A save from a *newer* app (version > current) may rely on a breaking
        // change this build predates, so it's discarded rather than mis-read.
        let url = dir.appendingPathComponent(filename)
        let json =
            #"{"version":999,"config":{"classic":{"_0":"beginner"}},"mines":[],"#
            + #""revealed":[],"flagged":[],"status":"playing","revealedSafeCount":0,"#
            + #""elapsedCentiseconds":0}"#
        try Data(json.utf8).write(to: url)
        XCTAssertNil(store.load(), "a version this build doesn't understand is discarded")
    }

    func testLoadAcceptsOlderVersion() throws {
        // The format is additive: a save at or below currentVersion still loads
        // (an in-progress game survives a compatible app upgrade).
        let url = dir.appendingPathComponent(filename)
        let json = #"{"version":0,"config":{"classic":{"_0":"beginner"}},"mines":[[0,0]]}"#
        try Data(json.utf8).write(to: url)
        let loaded = store.load()
        XCTAssertNotNil(loaded, "an older, compatible save is preserved across upgrade")
        XCTAssertEqual(loaded?.config, .classic(.beginner))
    }

    // MARK: UI-test isolation

    func testEphemeralStoreStartsEmpty() {
        // The UI-test store is a fresh temp dir with no save, so load() is nil and
        // it never touches the real App Support store.
        XCTAssertNil(SaveStore.ephemeral().load(), "a fresh ephemeral store has no saved game")
    }

    func testUITestCleanLaunchFlagFalseInUnitTests() {
        // The -uitest-clean arg is only passed by the XCUITest harness; a plain
        // unit-test run is a normal launch.
        XCTAssertFalse(SaveStore.isUITestCleanLaunch)
    }
}
