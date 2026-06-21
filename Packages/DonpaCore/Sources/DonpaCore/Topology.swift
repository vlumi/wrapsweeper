/// The single seam through which "epic" board variants are introduced.
///
/// Everything above this protocol — mine placement, adjacency counts,
/// flood-fill, win/lose detection — is written in terms of `neighbors(of:)`
/// and `allCoords()` only. Swapping square↔hex or bounded↔wrapped therefore
/// requires a new `Topology` and nothing else.
public protocol Topology: Sendable {
    /// Total number of playable cells on the board.
    var cellCount: Int { get }

    /// The neighbours of `c` that are on the board, already normalized.
    ///
    /// 8 for square grids, 6 for hex. For wrapped topologies the returned
    /// coordinates are the normalized (wrapped) cells, so callers never see
    /// off-board coordinates.
    func neighbors(of c: Coord) -> [Coord]

    /// Maps a raw coordinate onto the board.
    ///
    /// Returns `nil` for bounded topologies when `c` lies outside the board.
    /// Wrapped topologies instead fold `c` back onto the board (modulo) and
    /// never return `nil`.
    func normalize(_ c: Coord) -> Coord?

    /// Every playable coordinate, in a stable order.
    func allCoords() -> AnySequence<Coord>
}
