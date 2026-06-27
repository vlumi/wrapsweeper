/// Places mines so the opening reveal is safe.
///
/// The safety zone is the first-clicked cell *and all of its neighbours*. With no
/// mine adjacent to the first cell, that cell is guaranteed to be a 0 and the
/// flood-fill opens a region — the "first click always hits a 0" rule. The zone is
/// computed via `topology.neighbors`, so it works identically on wrapped/hex too.
public struct MinePlacer {
    /// Mines for a board where the first click is already known — the clicked cell
    /// and its neighbours are kept mine-free. Used by the direct place-on-first-
    /// reveal path; the off-thread pre-arm path uses `randomMines` (no safe zone)
    /// + `Board.relocateMines` instead.
    public static func placeMines<R: RandomNumberGenerator>(
        topology: any RectangularTopology,
        mineCount: Int,
        firstClick: Coord,
        using rng: inout R
    ) -> Set<Coord> {
        var safeZone: Set<Coord> = [firstClick]
        safeZone.formUnion(topology.neighbors(of: firstClick))
        // If the board is so dense the whole safe zone can't be honoured, keep only
        // the clicked cell mine-free (never the click itself).
        let exclude = (topology.cellCount - safeZone.count) >= mineCount ? safeZone : [firstClick]
        return randomMines(topology: topology, mineCount: mineCount, exclude: exclude, using: &rng)
    }

    /// Place `mineCount` mines uniformly at random, avoiding `exclude`. With an
    /// empty `exclude` this arms a board before the first click is known (the
    /// off-thread pre-generation path).
    ///
    /// Rejection-samples flat indices — O(mineCount), and crucially never
    /// materializes/filters all cells (the old `allCoords().filter` was slow through
    /// `AnySequence` on a 1000² board). Falls back to a shuffled candidate list only
    /// when the board is dense enough that rejection would thrash.
    public static func randomMines<R: RandomNumberGenerator>(
        topology: any RectangularTopology,
        mineCount: Int,
        exclude: Set<Coord> = [],
        using rng: inout R
    ) -> Set<Coord> {
        let cellCount = topology.cellCount
        let available = cellCount - exclude.count
        let take = min(mineCount, max(0, available))

        // Sparse case (the norm): rejection-sample until we have `take` distinct
        // non-excluded cells.
        if take > 0, take * 4 <= available * 3 {
            var mines = Set<Coord>()
            mines.reserveCapacity(take)
            while mines.count < take {
                let c = topology.coord(at: Int.random(in: 0..<cellCount, using: &rng))
                if !exclude.contains(c) { mines.insert(c) }
            }
            return mines
        }

        // Dense fallback: shuffle the explicit candidate list (partial Fisher–Yates,
        // only `take` slots) — used when free cells are too scarce for rejection.
        var candidates = topology.allCoords().filter { !exclude.contains($0) }
        for i in 0..<min(take, candidates.count) {
            let j = Int.random(in: i..<candidates.count, using: &rng)
            candidates.swapAt(i, j)
        }
        return Set(candidates.prefix(take))
    }
}
