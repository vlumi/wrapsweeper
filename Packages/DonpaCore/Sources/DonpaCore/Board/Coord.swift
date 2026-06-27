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

/// Encodes as a compact two-element array `[x, y]` rather than `{"x":…,"y":…}`,
/// so persisted coordinate sets (mines/revealed/flagged) stay small.
extension Coord: Codable {
    public init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        self.init(try c.decode(Int.self), try c.decode(Int.self))
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode(x)
        try c.encode(y)
    }
}

extension Coord: CustomStringConvertible {
    public var description: String { "(\(x), \(y))" }
}
