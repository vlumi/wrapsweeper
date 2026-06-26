import SwiftUI

/// Tiny shared navigation state. Lives outside `GameView`'s private `@State` so
/// hosts that build the view (e.g. the macOS menu bar) can also drive it — the
/// "Title Screen" command, and (on macOS) opening Settings / the scoreboard from
/// the menu bar instead of toolbar buttons.
@MainActor
public final class Navigator: ObservableObject {
    /// Whether the title card is showing over the game.
    @Published public var showingTitle: Bool
    /// Whether the scoreboard sheet is presented.
    @Published public var showingScores = false
    /// Whether the settings sheet is presented.
    @Published public var showingSettings = false
    /// Whether the About sheet is presented (the title screen's "i" button, and
    /// the macOS app menu's "About").
    @Published public var showingAbout = false
    /// Whether the New Game config popup is presented. Opened by the in-game
    /// "New Game" action, the result screen, and — when there's no saved game to
    /// resume — by the title art tap; picking a config and confirming starts a
    /// fresh game and dismisses the title.
    @Published public var showingNewGame = false

    /// Bumped when the title art is tapped ("press start"). The decision of what
    /// that does — resume a saved game, or open the New Game popup — depends on
    /// the save store, which `GameContent` owns; it watches this counter and
    /// routes accordingly. A counter (not a Bool) so repeated taps always fire.
    @Published public var startRequested = 0

    /// Bumped to request "go home" (the in-game Home button and the macOS "Title
    /// Screen" menu command). Routed through `GameContent` — rather than setting
    /// `showingTitle` directly — so going home PAUSES AND SAVES the game instead
    /// of discarding it. A counter so repeated requests always fire.
    @Published public var homeRequested = 0

    /// Whether the fullscreen board overview (big navigable map) is presented.
    /// Opened from the minimap's expand icon; navigation happens in that view.
    @Published public var showingOverview = false

    /// Whether any modal (a sheet, the New Game popup, or the overview) is
    /// presented. Gameplay commands (New Game / Restart / mode toggle / presets)
    /// are disabled while one is up, so their keyboard shortcuts don't mutate the
    /// game underneath it.
    public var isModalPresented: Bool {
        showingScores || showingSettings || showingAbout || showingNewGame || showingOverview
    }

    public init(showingTitle: Bool = true) {
        self.showingTitle = showingTitle
    }
}
