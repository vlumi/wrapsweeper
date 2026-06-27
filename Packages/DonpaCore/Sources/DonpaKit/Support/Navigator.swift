import SwiftUI

/// Shared navigation state, outside `GameView`'s private `@State` so hosts (e.g.
/// the macOS menu bar) can also drive sheet presentation and the title command.
@MainActor
public final class Navigator: ObservableObject {
    /// Whether the title card is showing over the game.
    @Published public var showingTitle: Bool
    /// Whether the scoreboard sheet is presented.
    @Published public var showingScores = false
    /// Whether the settings sheet is presented.
    @Published public var showingSettings = false
    /// Whether the About sheet is presented.
    @Published public var showingAbout = false
    /// Whether the New Game config popup is presented.
    @Published public var showingNewGame = false

    /// Bumped on a title-art tap. `GameContent` routes it (resume a saved game, or
    /// open the New Game popup). A counter, not a Bool, so repeated taps fire.
    @Published public var startRequested = 0

    /// Bumped to "go home". Routed through `GameContent` rather than setting
    /// `showingTitle` directly, so going home pauses and saves rather than discards.
    @Published public var homeRequested = 0

    /// Bumped to zoom in / out (macOS ⌘+ / ⌘−). Routed to the board scene, which
    /// zooms about the centre (keyboard has no cursor). Mouse/trackpad zoom is
    /// separate.
    @Published public var zoomInRequested = 0
    @Published public var zoomOutRequested = 0

    /// Whether the fullscreen board overview is presented.
    @Published public var showingOverview = false

    /// Whether any modal is presented. Gameplay commands are disabled while one is
    /// up, so their keyboard shortcuts don't mutate the game underneath.
    public var isModalPresented: Bool {
        showingScores || showingSettings || showingAbout || showingNewGame || showingOverview
    }

    public init(showingTitle: Bool = true) {
        self.showingTitle = showingTitle
    }
}
