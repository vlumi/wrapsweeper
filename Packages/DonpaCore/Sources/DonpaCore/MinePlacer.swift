/// Places mines after the first click so the opening reveal is always safe.
///
/// The safety zone is the first-clicked cell *and all of its neighbours*. With
/// no mine adjacent to the first cell, that cell is guaranteed to be a 0 and the
/// flood-fill opens a region — satisfying the "first click always hits a 0"
/// requirement. The zone is computed via `topology.neighbors`, so it works
/// identically on wrapped and hex boards.
public struct MinePlacer {
    /// Returns the set of coordinates that should hold mines.
    ///
    /// - Parameters:
    ///   - topology: board geometry.
    ///   - mineCount: how many mines to place.
    ///   - firstClick: the cell the player opened first; it and its neighbours
    ///     are kept mine-free.
    ///   - rng: injected for reproducible tests.
    public static func placeMines<R: RandomNumberGenerator>(
        topology: any Topology,
        mineCount: Int,
        firstClick: Coord,
        using rng: inout R
    ) -> Set<Coord> {
        var safeZone: Set<Coord> = [firstClick]
        safeZone.formUnion(topology.neighbors(of: firstClick))

        var candidates = topology.allCoords().filter { !safeZone.contains($0) }

        // If the board is so dense that mines can't all avoid the safe zone,
        // fall back to allowing the neighbour ring (but never the clicked cell).
        if candidates.count < mineCount {
            candidates = topology.allCoords().filter { $0 != firstClick }
        }

        candidates.shuffle(using: &rng)
        return Set(candidates.prefix(mineCount))
    }
}
