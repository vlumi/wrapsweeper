import SwiftUI

/// Tiny shared navigation state. Lives outside `GameView`'s private `@State` so
/// hosts that build the view (e.g. the macOS menu bar) can also drive it — e.g.
/// a "Title Screen" menu command returning to the title card.
@MainActor
public final class Navigator: ObservableObject {
    /// Whether the title card is showing over the game.
    @Published public var showingTitle: Bool

    public init(showingTitle: Bool = true) {
        self.showingTitle = showingTitle
    }
}
