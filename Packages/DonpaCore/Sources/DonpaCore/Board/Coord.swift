/// An integer cell coordinate. `(col, row)` for square grids; the same shape also
/// serves axial hex `(q, r)` later, so field names stay generic.
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
