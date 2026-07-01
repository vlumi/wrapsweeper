import DonpaCore
import Foundation

func pad(_ s: String, _ width: Int) -> String {
    s.count >= width ? s : s + String(repeating: " ", count: width - s.count)
}
func col(_ value: Double, _ decimals: Int = 1) -> String {
    String(format: "%.\(decimals)f", value)
}

// Dev tool: estimate how "fair" / guess-dependent candidate board configs are,
// to choose Modern-mode difficulty tiers. For each config we run N seeded,
// first-click-safe games through the logical solver and report:
//   - density: mines / cells
//   - guess%:  share of games the single-constraint solver could NOT finish
//              without a guess (higher = more frustrating / luck-dependent)
//   - solve%:  share fully solved by logic (100 - guess%)
//   - deduce:  average deduction steps in solved games
//   - open:    average opening flood-fill size (bigger = gentler start)
//
// The solver is single-constraint only, so guess% is an upper bound on true
// unfairness — but it's a consistent yardstick for comparing configs.

struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

struct Candidate {
    let label: String
    let width: Int
    let height: Int
    let mines: Int
}

func mines(width: Int, height: Int, density: Double) -> Int {
    Int((Double(width * height) * density).rounded())
}

// The five Modern SQUARE tiers (the base ladder). Classic presets are calibration
// anchors. Hex is NOT shared: `run()` adds +2 density points for the hex pass,
// mirroring the ship rule (`Density.fraction(shape:)`) — hex's 6-neighbour cascades
// play easier at a given mine%, and small hex Easy was near one-tap on the shared
// table. `1tap%` (share of games the first flood-fill clears the whole board) is the
// metric that caught it. SWEEP=1 replaces the tiers with a fine density ramp.
var densities: [(String, Double)] = [
    ("Easy", 0.10), ("Normal", 0.12), ("Hard", 0.14), ("Brutal", 0.16), ("Insane", 0.18),
]
if ProcessInfo.processInfo.environment["SWEEP"] == "1" {
    densities = stride(from: 0.11, through: 0.30, by: 0.01).map {
        (String(format: "d%02d", Int(($0 * 100).rounded())), $0)
    }
}

var candidates: [Candidate] = [
    Candidate(label: "Classic Beginner   9x9", width: 9, height: 9, mines: 10),
    Candidate(label: "Classic Intermed. 16x16", width: 16, height: 16, mines: 40),
    Candidate(label: "Classic Expert    30x16", width: 30, height: 16, mines: 99),
]

// The rebalanced power-of-2 ladder (8/16/32/64/128/256/1024). Sample a few rungs
// for the density sweep; playability is roughly size-stable above ~S.
let sizeSets: [(String, [(String, Int)])] = [
    ("Modern", [("XS", 8), ("S", 16), ("M", 32)])
]
for (setName, sizes) in sizeSets {
    for (sizeLabel, side) in sizes {
        for (dLabel, d) in densities {
            candidates.append(
                Candidate(
                    label: "Set\(setName) \(sizeLabel)·\(dLabel) \(side)x\(side)",
                    width: side, height: side, mines: mines(width: side, height: side, density: d)))
        }
    }
}

let games = 2000
let solver = Solver()

// Runs the identical solver over both topologies (`SHAPE=hex|square|both`). The hex
// pass adds the ship's +2 density points (see `run`), so the two columns show the
// ACTUAL shipping boards side by side rather than the same mine% on different grids.
enum Shape: String { case square, hex }

func run(_ shape: Shape, _ c: Candidate) {
    let cells = c.width * c.height
    // Ship rule: hex runs +2 density points over the base (square) tier — its 6-
    // neighbour cascades play easier, so mirror `Density.fraction(shape:)` here so
    // the tool measures the ACTUAL hex boards, not the square mine count on a hex
    // grid. Candidate.mines is the square baseline.
    let mineCount = shape == .hex ? c.mines + Int((0.02 * Double(cells)).rounded()) : c.mines
    let safe = cells - mineCount  // non-mine cells; a one-tap clear opens them all
    var solved = 0
    var deductSum = 0
    var openSum = 0
    var oneTap = 0  // games the FIRST flood-fill opened the whole board (won on one tap)
    let topo: any RectangularTopology =
        shape == .hex
        ? HexTopology(width: c.width, height: c.height)
        : BoundedSquareTopology(width: c.width, height: c.height)
    let click = Coord(c.width / 2, c.height / 2)

    for seed in 0..<games {
        var game = Game(topology: topo, mineCount: mineCount)
        var rng = SeededRNG(seed: UInt64(seed))
        let r = solver.solve(&game, firstClick: click, using: &rng)
        openSum += r.firstOpenSize
        if r.firstOpenSize >= safe { oneTap += 1 }
        if r.solvedWithoutGuessing {
            solved += 1
            deductSum += r.deductions
        }
    }

    let density = Double(mineCount) / Double(cells) * 100
    let solvePct = Double(solved) / Double(games) * 100
    let avgDeduce = solved > 0 ? Double(deductSum) / Double(solved) : 0
    let avgOpen = Double(openSum) / Double(games)
    let oneTapPct = Double(oneTap) / Double(games) * 100

    let row =
        pad(shape.rawValue, 6) + " " + pad(c.label, 28) + " " + pad("\(cells)", 6) + " "
        + pad("\(mineCount)", 6) + " " + pad(col(density) + "%", 8) + " "
        + pad(col(solvePct) + "%", 7) + " " + pad(col(100 - solvePct) + "%", 7) + " "
        + pad(col(avgDeduce), 7) + " " + pad(col(avgOpen), 6) + " " + pad(col(oneTapPct) + "%", 7)
    print(row)
}

let shapesToRun: [Shape] = {
    switch ProcessInfo.processInfo.environment["SHAPE"]?.lowercased() {
    case "hex": return [.hex]
    case "square": return [.square]
    default: return [.square, .hex]
    }
}()

print(
    "shape  config                       cells  mines  density  solve%  guess%  deduce  open   1tap%"
)
print(String(repeating: "-", count: 93))
for shape in shapesToRun {
    for c in candidates { run(shape, c) }
    print(String(repeating: "-", count: 93))
}
