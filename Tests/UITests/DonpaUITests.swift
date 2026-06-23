import XCTest

/// Local-only UI regression tests (run via `make uitest`, never on CI). They
/// cover the navigation/sheet flows that regressed repeatedly during UI work:
/// title → New Game popup → board, the Settings/High Scores sheets dismissing,
/// and pause/resume. Queries use accessibility identifiers (stable across
/// locales) set in the app via `.accessibilityIdentifier(...)`.
final class DonpaUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        // Force English so any label-based fallbacks are predictable.
        app.launchArguments += ["-AppleLanguages", "(en)"]
        app.launch()
    }

    // MARK: Helpers

    /// The title art ("press start") button.
    private var startButton: XCUIElement { app.buttons["title.start"] }

    private func waitFor(_ element: XCUIElement, _ timeout: TimeInterval = 5) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "missing: \(element)")
    }

    // MARK: Tests

    func testLaunchShowsTitle() {
        waitFor(startButton)
    }

    /// From the title, open the New Game popup and start a game. The in-game
    /// control strip (the Home button) appearing is the reliable "we're playing"
    /// signal — the board is an always-mounted SpriteView that doesn't surface
    /// cleanly as a queryable element.
    private func startGame() {
        waitFor(startButton)
        startButton.tap()
        let popupStart = app.buttons["newgame.start"]
        waitFor(popupStart)
        popupStart.tap()
        waitFor(app.buttons["game.home"])
    }

    func testStartOpensNewGamePopupThenStartsGame() {
        startGame()
        // The title's start button is no longer hittable once playing.
        XCTAssertFalse(startButton.isHittable)
    }

    func testHighScoresSheetOpensAndCloses() {
        waitFor(app.buttons["title.highScores"])
        app.buttons["title.highScores"].tap()
        let done = app.buttons["sheet.done"]
        waitFor(done)
        done.tap()
        XCTAssertTrue(startButton.waitForExistence(timeout: 5), "back on the title")
    }

    func testSettingsSheetOpensAndCloses() {
        waitFor(app.buttons["title.settings"])
        app.buttons["title.settings"].tap()
        let done = app.buttons["sheet.done"]
        waitFor(done)
        done.tap()
        waitFor(startButton)
    }

    func testHomeReturnsToTitleFromGame() {
        startGame()
        app.buttons["game.home"].tap()
        waitFor(startButton)
    }

    func testPauseAndResume() {
        startGame()
        // Pause only exists once the game is actually playing, so reveal a cell
        // first (tap the board to make the first move).
        app.otherElements["game.board"].tap()
        let pause = app.buttons["game.pause"]
        waitFor(pause)
        pause.tap()
        // The pause overlay (match by id across any element type).
        let paused = app.descendants(matching: .any)["game.paused"]
        waitFor(paused)
        paused.tap()  // tap-to-resume
        XCTAssertFalse(
            app.descendants(matching: .any)["game.paused"].waitForExistence(timeout: 2),
            "resumed")
    }
}
