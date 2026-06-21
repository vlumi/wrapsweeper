import Combine
import Foundation
import WrapsweeperCore

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
    case won(seconds: Int, config: GameConfig)
    /// Lost — `at` is the mine that detonated (for a focused loss animation).
    case lost(at: Coord?)
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
    @Published public private(set) var elapsedSeconds: Int = 0

    /// Bumped on every state-changing action so the SpriteKit scene knows to
    /// re-render without diffing the whole board.
    @Published public private(set) var revision: Int = 0

    /// Bumped only when a fresh game starts, so the scene can reset its camera
    /// (re-fit and re-center) without doing so on every reveal.
    @Published public private(set) var gameID: Int = 0

    /// Set once at the moment a game is won, carrying the final time and the
    /// config it was won on, so a host can record/prompt for a high score.
    /// Cleared on the next new game.
    @Published public private(set) var lastWin: (config: GameConfig, seconds: Int)?

    /// The most recent game outcome, for end-of-game feedback (animation,
    /// banner, haptics). The `id` makes each result distinct so observers fire
    /// even on identical consecutive outcomes; cleared on the next new game.
    @Published public private(set) var lastResult: GameResultEvent?
    private var resultCounter = 0

    /// What a plain tap on a hidden cell does. Toggled from the toolbar so the
    /// player can place flags without risking an accidental reveal.
    @Published public var inputMode: InputMode = .reveal

    private var timer: AnyCancellable?

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
        game.toggleFlag(c)
        bump()
    }

    public func chord(_ c: Coord) {
        game.chord(c)
        finishIfEnded()
        bump()
    }

    public func newGame(config: GameConfig? = nil) {
        if let config { self.config = config }
        game = Game(config: self.config)
        elapsedSeconds = 0
        lastWin = nil
        lastResult = nil
        stopTimer()
        gameID &+= 1
        bump()
    }

    /// Stop the clock when the game ends, capture a win for scoring, and publish
    /// the outcome for end-of-game feedback.
    private func finishIfEnded() {
        guard game.status == .won || game.status == .lost else { return }
        stopTimer()
        let result: GameResult
        if game.status == .won {
            lastWin = (config: config, seconds: elapsedSeconds)
            result = .won(seconds: elapsedSeconds, config: config)
        } else {
            result = .lost(at: game.lossCoord)
        }
        resultCounter += 1
        lastResult = GameResultEvent(id: resultCounter, result: result)
    }

    // MARK: Timer

    private func startTimer() {
        elapsedSeconds = 0
        timer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                if self.elapsedSeconds < 999 { self.elapsedSeconds += 1 }
            }
    }

    private func stopTimer() {
        timer?.cancel()
        timer = nil
    }

    private func bump() { revision &+= 1 }
}
