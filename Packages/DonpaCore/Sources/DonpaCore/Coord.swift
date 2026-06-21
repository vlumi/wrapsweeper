/// An integer cell coordinate on the board.
///
/// For square grids this is `(col, row)`. The same two-field shape also serves
/// axial hex coordinates `(q, r)` when hex topologies land later — the field
/// names stay generic so no call site needs to change.
public struct Coord: Hashable, Sendable {
    public var x: Int
    public var y: Int

    public init(_ x: Int, _ y: Int) {
        self.x = x
        self.y = y
    }
}

extension Coord: CustomStringConvertible {
    public var description: String { "(\(x), \(y))" }
}
