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
    /// Whether the New Game config popup is presented. Opened both by the in-game
    /// "New Game" action and by tapping the title art ("press start"); picking a
    /// config and confirming starts a fresh game and dismisses the title.
    @Published public var showingNewGame = false

    public init(showingTitle: Bool = true) {
        self.showingTitle = showingTitle
    }
}
