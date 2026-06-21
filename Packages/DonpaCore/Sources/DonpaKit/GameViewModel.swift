import Combine
import DonpaCore
import Foundation

/// What a plain tap/click on a *hidden* cell does. A revealed number always
/// chords and a long-press always does the opposite primary action, regardless
/// of mode — so the mode only decides reveal-vs-flag for a hidden-cell tap.
public enum InputMode: Sendable {
    case reveal
    case flag

    public mutating func toggle() { self = self == .reveal ? .flag : .reveal }
}

/// The outcome of a finished game, used to drive end-of-game feedback.
public enum GameResult: Equatable, Sendable {
    case won(centiseconds: Int, config: GameConfig)
    /// Lost — `at` is the mine that detonated (for a focused loss animation).
    case lost(at: Coord?)

    public var isWin: Bool { if case .won = self { return true } else { return false } }
}

/// A game result tagged with a monotonic id, so observers fire on every
/// outcome — even two identical results in a row.
public struct GameResultEvent: Equatable, Sendable {
    public let id: Int
    public let result: GameResult
}

/// Bridges the pure `Game` value type to SwiftUI/SpriteKit: owns the current
/// game, the selected difficulty, the timer, and the mine counter, and
/// republishes whenever the board changes so views and the scene can redraw.
@MainActor
public final class GameViewModel: ObservableObject {
    @Published public private(set) var game: Game
    @Published public private(set) var config: GameConfig
    /// Elapsed play time in centiseconds (hundredths). Driven by the wall clock
    /// (not a tick count) so it's accurate and uncapped; the UI rounds to 0.1s.
    @Published public private(set) var elapsedCentiseconds: Int = 0

    /// Bumped on every state-changing action so the SpriteKit scene knows to
    /// re-render without diffing the whole board.
    @Published public private(set) var revision: Int = 0

    /// Bumped only when a fresh game starts, so the scene can reset its camera
    /// (re-fit and re-center) without doing so on every reveal.
    @Published public private(set) var gameID: Int = 0

    /// Set once at the moment a game is won, carrying the final time
    /// (centiseconds) and the config it was won on. Cleared on the next new game.
    @Published public private(set) var lastWin: (config: GameConfig, centiseconds: Int)?

    /// The most recent game outcome, for end-of-game feedback (animation,
    /// banner, haptics). The `id` makes each result distinct so observers fire
    /// even on identical consecutive outcomes; cleared on the next new game.
    @Published public private(set) var lastResult: GameResultEvent?
    private var resultCounter = 0

    /// What a plain tap on a hidden cell does. Toggled from the toolbar so the
    /// player can place flags without risking an accidental reveal.
    @Published public var inputMode: InputMode = .reveal

    private var timer: AnyCancellable?
    private var startDate: Date?

    public init(config: GameConfig = .classic(.beginner)) {
        self.config = config
        self.game = Game(config: config)
    }

    public var status: GameStatus { game.status }
    public var flagsRemaining: Int { game.flagsRemaining }
    public var boardWidth: Int { config.width }
    public var boardHeight: Int { config.height }

    // MARK: Actions

    public func reveal(_ c: Coord) {
        guard game.status == .notStarted || game.status == .playing else { return }
        let wasNotStarted = game.status == .notStarted
        game.reveal(c)
        if wasNotStarted, game.status == .playing { startTimer() }
        finishIfEnded()
        bump()
    }

    public func toggleFlag(_ c: Coord) {
        guard game.status == .notStarted || game.status == .playing else { return }
        game.toggleFlag(c)
        bump()
    }

    public func chord(_ c: Coord) {
        // Once the game is over, input is inert — chording a revealed cell must
        // not re-publish the result (which would replay the end-game animation
        // and panel on every post-loss click).
        guard game.status == .playing else { return }
        game.chord(c)
        finishIfEnded()
        bump()
    }

    public func newGame(config: GameConfig? = nil) {
        if let config { self.config = config }
        game = Game(config: self.config)
        elapsedCentiseconds = 0
        lastWin = nil
        lastResult = nil
        inputMode = .reveal  // every game starts in reveal mode
        stopTimer()
        gameID &+= 1
        bump()
    }

    /// Stop the clock when the game ends, capture a win for scoring, and publish
    /// the outcome for end-of-game feedback.
    private func finishIfEnded() {
        guard game.status == .won || game.status == .lost else { return }
        // Capture the precise final time from the wall clock before stopping.
        let finalCentiseconds = centisecondsSinceStart()
        stopTimer()
        elapsedCentiseconds = finalCentiseconds
        let result: GameResult
        if game.status == .won {
            lastWin = (config: config, centiseconds: finalCentiseconds)
            result = .won(centiseconds: finalCentiseconds, config: config)
        } else {
            result = .lost(at: game.lossCoord)
        }
        resultCounter += 1
        lastResult = GameResultEvent(id: resultCounter, result: result)
    }

    // MARK: Timer

    private func startTimer() {
        elapsedCentiseconds = 0
        startDate = Date()
        // Refresh ~10×/sec for a smooth tenths display; the value itself is
        // computed from the wall clock, so it never drifts.
        timer = Timer.publish(every: 0.1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                self.elapsedCentiseconds = self.centisecondsSinceStart()
            }
    }

    private func centisecondsSinceStart() -> Int {
        guard let startDate else { return elapsedCentiseconds }
        return max(0, Int((Date().timeIntervalSince(startDate) * 100).rounded()))
    }

    private func stopTimer() {
        timer?.cancel()
        timer = nil
        startDate = nil
    }

    private func bump() { revision &+= 1 }
}
