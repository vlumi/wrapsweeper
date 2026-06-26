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
        // Clean, isolated state per run: no saved game restored, and the app uses
        // an ephemeral save store — so tests are deterministic and never touch the
        // developer's real save.
        app.launchArguments += ["-uitest-clean"]
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

    /// Going Home from an in-progress game saves it (rather than discarding), and
    /// tapping the title art resumes that game directly — no New Game popup. This
    /// is the save-on-home behaviour; the regression it guards is Home silently
    /// ending the game.
    func testHomeSavesAndTitleResumes() {
        startGame()
        // Make a move so there's a genuine in-progress (playing) game to save.
        XCTAssertTrue(
            app.buttons["newgame.start"].waitForNonExistence(timeout: 5),
            "New Game popup dismissed")
        app.otherElements["game.board"].tap()
        // Go home — should pause + save, not discard.
        app.buttons["game.home"].tap()
        waitFor(startButton)
        // Tapping the title resumes straight into the game (Home button present),
        // and must NOT open the New Game popup (that would mean nothing was saved).
        startButton.tap()
        waitFor(app.buttons["game.home"])
        XCTAssertFalse(
            app.buttons["newgame.start"].exists,
            "resumed directly, no New Game popup")
    }

    func testPauseAndResume() {
        startGame()
        // Wait for the New Game popup to finish fading out — its dimmed scrim
        // captures taps until then, so tapping the board too early hits the scrim
        // (no first move, no pause). The popup's Start button vanishing is the
        // "popup gone" signal.
        XCTAssertTrue(
            app.buttons["newgame.start"].waitForNonExistence(timeout: 5),
            "New Game popup dismissed")
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

    /// The big-board overview opens from the toolbar and dismisses. (Needs a board
    /// bigger than the viewport, so it picks Modern XL.)
    func testOverviewOpensAndCloses() {
        waitFor(startButton)
        startButton.tap()
        waitFor(app.buttons["newgame.start"])
        if app.buttons["Modern"].waitForExistence(timeout: 3) { app.buttons["Modern"].tap() }
        if app.buttons["XL"].waitForExistence(timeout: 3) { app.buttons["XL"].tap() }
        app.buttons["newgame.start"].tap()
        waitFor(app.buttons["game.home"])
        app.otherElements["game.board"].tap()
        waitFor(app.buttons["game.overview"])
        app.buttons["game.overview"].tap()
        XCTAssertTrue(app.buttons["overview.close"].waitForExistence(timeout: 5), "overview opened")
        app.buttons["overview.close"].tap()
        XCTAssertTrue(
            app.buttons["overview.close"].waitForNonExistence(timeout: 3), "overview closed")
    }
}
