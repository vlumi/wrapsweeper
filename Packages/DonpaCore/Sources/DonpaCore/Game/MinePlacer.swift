/// Places mines so the opening reveal is safe.
///
/// The safe zone is the first-clicked cell and all its neighbours: with no mine
/// adjacent, that cell is a guaranteed 0 and the flood-fill opens a region (the
/// "first click always hits a 0" rule).
public struct MinePlacer {
    /// Mines for a board where the first click is known — the clicked cell and its
    /// neighbours stay mine-free. The off-thread pre-arm path instead uses
    /// `randomMines` (no safe zone) + `Board.relocateMines`.
    public static func placeMines<R: RandomNumberGenerator>(
        topology: any RectangularTopology,
        mineCount: Int,
        firstClick: Coord,
        using rng: inout R
    ) -> Set<Coord> {
        var safeZone: Set<Coord> = [firstClick]
        safeZone.formUnion(topology.neighbors(of: firstClick))
        // If too dense to honour the whole safe zone, keep only the click mine-free.
        let exclude = (topology.cellCount - safeZone.count) >= mineCount ? safeZone : [firstClick]
        return randomMines(topology: topology, mineCount: mineCount, exclude: exclude, using: &rng)
    }

    /// Place `mineCount` mines uniformly at random, avoiding `exclude`. Empty
    /// `exclude` arms a board before the first click is known.
    ///
    /// Rejection-samples flat indices (O(mineCount), never materializes all cells);
    /// falls back to a shuffled candidate list when the board is too dense for
    /// rejection to be efficient.
    public static func randomMines<R: RandomNumberGenerator>(
        topology: any RectangularTopology,
        mineCount: Int,
        exclude: Set<Coord> = [],
        using rng: inout R
    ) -> Set<Coord> {
        let cellCount = topology.cellCount
        let available = cellCount - exclude.count
        let take = min(mineCount, max(0, available))

        // Sparse case (the norm): rejection-sample `take` distinct non-excluded cells.
        if take > 0, take * 4 <= available * 3 {
            var mines = Set<Coord>()
            mines.reserveCapacity(take)
            while mines.count < take {
                let c = topology.coord(at: Int.random(in: 0..<cellCount, using: &rng))
                if !exclude.contains(c) { mines.insert(c) }
            }
            return mines
        }

        // Dense fallback: partial Fisher–Yates over the explicit candidate list.
        var candidates = topology.allCoords().filter { !exclude.contains($0) }
        for i in 0..<min(take, candidates.count) {
            let j = Int.random(in: i..<candidates.count, using: &rng)
            candidates.swapAt(i, j)
        }
        return Set(candidates.prefix(take))
    }
}
