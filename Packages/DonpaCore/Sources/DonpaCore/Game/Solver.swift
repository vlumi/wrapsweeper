/// A logical Minesweeper solver: plays a `Game` using only player-visible
/// information (revealed numbers and its own flags), never the hidden mine
/// layout. Applies the two classic single-constraint deductions to a fixpoint:
///
///   1. **All-mines:** number == hidden-neighbour count → flag them all.
///   2. **All-clear:** number == flagged-neighbour count → reveal the rest.
///
/// When neither makes progress, the position requires a guess. Single-constraint
/// logic only (no CSP) — the standard baseline for measuring guess-dependence.
public struct Solver {
    public struct Result: Sendable, Equatable {
        /// True if the game reached `.won` using only the two deduction rules.
        public var solvedWithoutGuessing: Bool
        /// Number of deduction steps (cells revealed or flagged by logic).
        public var deductions: Int
        /// Cells revealed by the very first click's flood-fill (the opening).
        public var firstOpenSize: Int
        /// Final game status when the solver stopped.
        public var status: GameStatus
    }

    public init() {}

    /// Play `game` to completion-or-stuck from `firstClick`, using deductions
    /// only. `game` should be freshly started (not yet revealed); mines are
    /// placed by the first reveal via the injected RNG, exactly as in real play.
    public func solve<R: RandomNumberGenerator>(
        _ game: inout Game, firstClick: Coord, using rng: inout R
    ) -> Result {
        game.reveal(firstClick, using: &rng)
        let firstOpen = revealedCount(in: game)

        var deductions = 0
        loop: while game.status == .playing {
            var progressed = false

            for c in game.board.allCoords {
                let cell = game.board[c]
                guard cell.state == .revealed, cell.adjacentMines > 0 else { continue }

                let neighbours = game.board.topology.neighbors(of: c)
                let hidden = neighbours.filter { game.board[$0].state == .hidden }
                let flagged = neighbours.filter { game.board[$0].state == .flagged }
                if hidden.isEmpty { continue }

                // Rule 1: remaining mines exactly fill the hidden neighbours.
                if cell.adjacentMines - flagged.count == hidden.count {
                    for h in hidden { game.toggleFlag(h) }
                    deductions += hidden.count
                    progressed = true
                    continue
                }
                // Rule 2: all mines accounted for → the rest are safe.
                if cell.adjacentMines == flagged.count {
                    for h in hidden {
                        game.reveal(h, using: &rng)
                        deductions += 1
                        if game.status == .lost { break loop }  // a wrong flag elsewhere
                    }
                    progressed = true
                }
            }

            if !progressed { break }  // stuck → a guess would be required
        }

        return Result(
            solvedWithoutGuessing: game.status == .won,
            deductions: deductions,
            firstOpenSize: firstOpen,
            status: game.status)
    }

    private func revealedCount(in game: Game) -> Int {
        game.board.allCoords.reduce(0) { $0 + (game.board[$1].state == .revealed ? 1 : 0) }
    }
}
