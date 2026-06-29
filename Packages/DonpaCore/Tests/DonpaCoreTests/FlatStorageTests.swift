import XCTest

@testable import DonpaCore

/// Big-board groundwork: `Board` stores cells in a flat row-major array, the
/// huge-board memory/speed path. These pin the new seam — index mapping, storage
/// behaviour, and that a 1M-cell board is actually usable (cell writes O(1), not
/// O(n) array copies).
final class FlatStorageTests: XCTestCase {
    // MARK: RectangularTopology index mapping

    func testIndexRoundTrip() {
        let topo = BoundedSquareTopology(width: 7, height: 5)
        for c in topo.allCoords() {
            let i = topo.index(of: c)
            XCTAssertNotNil(i)
            XCTAssertEqual(topo.coord(at: i!), c, "index→coord must invert coord→index")
        }
    }

    func testIndexIsRowMajorAndDense() {
        let topo = BoundedSquareTopology(width: 4, height: 3)
        XCTAssertEqual(topo.index(of: Coord(0, 0)), 0)
        XCTAssertEqual(topo.index(of: Coord(3, 0)), 3)
        XCTAssertEqual(topo.index(of: Coord(0, 1)), 4)
        XCTAssertEqual(topo.index(of: Coord(3, 2)), 11)  // cellCount - 1
        // Indices densely fill 0..<cellCount.
        let indices = Set(topo.allCoords().map { topo.index(of: $0)! })
        XCTAssertEqual(indices, Set(0..<topo.cellCount))
    }

    func testIndexRejectsOffBoard() {
        let topo = BoundedSquareTopology(width: 4, height: 4)
        XCTAssertNil(topo.index(of: Coord(-1, 0)))
        XCTAssertNil(topo.index(of: Coord(4, 0)))
        XCTAssertNil(topo.index(of: Coord(0, 4)))
    }

    func testWrappedTopologyIsRectangular() {
        // Wrapped grids are dense rectangles too → flat storage eligible.
        let topo = WrappedSquareTopology(width: 6, height: 6)
        XCTAssertTrue((topo as Topology) is RectangularTopology)
        XCTAssertEqual(topo.index(of: Coord(5, 5)), 35)
    }

    // MARK: Board behaviour parity (flat-backed)

    func testFlatBoardStoresAndReturnsCells() {
        var board = Board(topology: BoundedSquareTopology(width: 5, height: 5))
        XCTAssertEqual(board[Coord(2, 3)].state, .hidden)  // default
        board[Coord(2, 3)].state = .revealed
        board[Coord(4, 4)].state = .flagged
        XCTAssertEqual(board[Coord(2, 3)].state, .revealed)
        XCTAssertEqual(board[Coord(4, 4)].state, .flagged)
        // Untouched cells stay default.
        XCTAssertEqual(board[Coord(0, 0)].state, .hidden)
    }

    /// Cell is bit-packed into one byte (state + isMine + adjacentMines), so a
    /// 1000² board's cell array is ~1MB, not ~16MB. Guard against a field being
    /// widened back to a padded struct. Also check the packed fields round-trip
    /// independently (no bit clobbering between them).
    func testCellIsByteSizedAndFieldsAreIndependent() {
        XCTAssertEqual(MemoryLayout<Cell>.stride, 1, "Cell must stay one byte")
        var board = Board(topology: BoundedSquareTopology(width: 3, height: 3))
        board.placeMines(at: [Coord(0, 0)])  // (1,1) gets adjacentMines = 1, not a mine
        board[Coord(1, 1)].state = .flagged
        let c = board[Coord(1, 1)]
        XCTAssertEqual(c.state, .flagged)
        XCTAssertFalse(c.isMine)
        XCTAssertEqual(c.adjacentMines, 1)  // setting state didn't clobber the count
        // A max neighbour count (8) fits the 4 bits.
        var full = Board(topology: BoundedSquareTopology(width: 3, height: 3))
        let ring = [(0, 0), (1, 0), (2, 0), (0, 1), (2, 1), (0, 2), (1, 2), (2, 2)]
        full.placeMines(at: Set(ring.map { Coord($0.0, $0.1) }))
        XCTAssertEqual(full[Coord(1, 1)].adjacentMines, 8)
    }

    func testDerivedCoordSetsMatchWrites() {
        var board = Board(topology: BoundedSquareTopology(width: 6, height: 6))
        board.placeMines(at: [Coord(1, 1), Coord(2, 2)])
        board[Coord(0, 0)].state = .revealed
        board[Coord(5, 5)].state = .flagged
        XCTAssertEqual(board.mineCoords, [Coord(1, 1), Coord(2, 2)])
        XCTAssertEqual(board.revealedCoords, [Coord(0, 0)])
        XCTAssertEqual(board.flaggedCoords, [Coord(5, 5)])
        XCTAssertEqual(board.revealedSafeCount, 1)
    }

    /// `forEachCellIndexed` is the fast bulk-scan seam (minimap raster, autosave):
    /// it must visit every cell exactly once in dense row-major order, with the flat
    /// index matching `index(of:)` so callers can derive `x = i % w`, `y = i / w`.
    func testForEachCellIndexedIsRowMajorAndComplete() {
        var board = Board(topology: BoundedSquareTopology(width: 4, height: 3))
        board[Coord(0, 0)].state = .revealed
        board[Coord(3, 2)].state = .flagged  // last cell, index 11

        var seen: [Int: Cell] = [:]
        board.forEachCellIndexed { i, cell in seen[i] = cell }

        XCTAssertEqual(seen.count, board.cellCount, "every cell visited once")
        XCTAssertEqual(Set(seen.keys), Set(0..<board.cellCount), "indices dense 0..<count")
        // Index → coord mapping the callers rely on.
        XCTAssertEqual(seen[0]?.state, .revealed)  // (0,0)
        XCTAssertEqual(seen[11]?.state, .flagged)  // (3,2) = 2*4 + 3
        XCTAssertEqual(seen[5]?.state, .hidden)  // a middle cell, untouched
    }

    func testAdjacencyComputedOnFlatBoard() {
        var board = Board(topology: BoundedSquareTopology(width: 3, height: 3))
        board.placeMines(at: [Coord(0, 0)])
        // Centre touches the single corner mine → 1; opposite corner → 0.
        XCTAssertEqual(board[Coord(1, 1)].adjacentMines, 1)
        XCTAssertEqual(board[Coord(2, 2)].adjacentMines, 0)
    }

    /// Adjacency is *scattered* from each mine onto its neighbours, so overlapping
    /// neighbourhoods must accumulate: the centre of a 3×3 with two corner mines
    /// counts both. Pins the scatter (vs. the old gather-per-cell) math.
    func testAdjacencyAccumulatesFromMultipleMines() {
        var board = Board(topology: BoundedSquareTopology(width: 3, height: 3))
        board.placeMines(at: [Coord(0, 0), Coord(2, 2)])
        XCTAssertEqual(board[Coord(1, 1)].adjacentMines, 2, "centre touches both corner mines")
        XCTAssertEqual(board[Coord(1, 0)].adjacentMines, 1, "edge touches only the near mine")
        XCTAssertEqual(board.mineCoords, [Coord(0, 0), Coord(2, 2)])
    }

    func testOffBoardWriteIsIgnored() {
        var board = Board(topology: BoundedSquareTopology(width: 4, height: 4))
        board[Coord(99, 99)].state = .revealed  // off-board: no-op, no crash
        XCTAssertEqual(board.revealedCoords, [])
    }

    // MARK: Huge board — the point of the whole change

    /// A 1000×1000 (1M-cell) board must build and take per-cell writes without
    /// O(n) array copies (which would make this hang). If flat storage isn't
    /// copy-on-write-in-place, this test wouldn't finish in reasonable time.
    func testMillionCellBoardIsUsable() {
        let n = 1000
        var board = Board(topology: BoundedSquareTopology(width: n, height: n))
        XCTAssertEqual(board.cellCount, n * n)
        // Many scattered single-cell writes — each must be O(1).
        for k in stride(from: 0, to: n * n, by: 1000) {
            board[Coord(k % n, k / n)].state = .flagged
        }
        XCTAssertEqual(board.flagCount, (n * n) / 1000)
    }

    /// `placeMines` scatters adjacency from each mine onto its neighbours, so it
    /// scales with the mine count, not the cell count — and each write must stay
    /// O(1) (if flat storage lost copy-on-write-in-place, per-write array copies
    /// would make this O(n²): a 250k-cell board took ~27s). Guards that regression.
    func testPlaceMinesScalesLinearly() {
        var board = Board(topology: BoundedSquareTopology(width: 500, height: 500))
        var mines: Set<Coord> = []
        for k in stride(from: 0, to: 250_000, by: 7) { mines.insert(Coord(k % 500, k / 500)) }
        let start = Date()
        board.placeMines(at: mines)
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertEqual(board.mineCount, mines.count)
        // O(n) finishes in well under a second on CI hardware; O(n²) took ~27s.
        // Generous ceiling to avoid flakiness while still catching the blowup.
        XCTAssertLessThan(elapsed, 5.0, "placeMines on 250k cells must be O(n)")
    }
}
