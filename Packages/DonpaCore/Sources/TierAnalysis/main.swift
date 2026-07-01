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

// Classic presets (sanity-check anchors) + Modern candidates across two size
// sets and three densities (Easy 12% / Normal 16% / Hard 20%).
// Locked Modern tiers (chosen from this analysis): five densities forming a
// smooth ramp from fair (Easy) to near-unsolvable-by-logic (Insane), across
// three square sizes. Classic presets included as calibration anchors.
// The five Modern tiers, SHARED by square and hex. Hex plays a touch easier per
// tier (6 neighbours vs 8 → less logic cascade), but its guess% spreads more evenly
// across the tiers where square bunches Brutal/Insane near 100% — so the same table
// gives hex a nicely distinct-per-tier curve. Decision (2026-07-01): keep shared,
// hex-a-bit-easier is fine. SWEEP=1 replaces the tiers with a fine density ramp to
// re-check the mapping if that's ever revisited.
var densities: [(String, Double)] = [
    ("Easy", 0.10), ("Normal", 0.13), ("Hard", 0.16), ("Brutal", 0.19), ("Insane", 0.22),
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
    ("Modern", [("S", 16), ("M", 32), ("L", 64)])
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

// Hex cells have 6 neighbours vs square's 8, so each revealed number constrains
// fewer cells and logic cascades less — meaning the SAME mine% plays harder on
// hex. This pass runs the identical solver over both topologies so the hex tiers
// can be re-picked to match the square difficulty CURVE (same solve% per tier),
// not the same density. `SHAPE=hex` (or `both`, default) selects which to run.
enum Shape: String { case square, hex }

func run(_ shape: Shape, _ c: Candidate) {
    let cells = c.width * c.height
    var solved = 0
    var deductSum = 0
    var openSum = 0
    let topo: any RectangularTopology =
        shape == .hex
        ? HexTopology(width: c.width, height: c.height)
        : BoundedSquareTopology(width: c.width, height: c.height)
    let click = Coord(c.width / 2, c.height / 2)

    for seed in 0..<games {
        var game = Game(topology: topo, mineCount: c.mines)
        var rng = SeededRNG(seed: UInt64(seed))
        let r = solver.solve(&game, firstClick: click, using: &rng)
        openSum += r.firstOpenSize
        if r.solvedWithoutGuessing {
            solved += 1
            deductSum += r.deductions
        }
    }

    let density = Double(c.mines) / Double(cells) * 100
    let solvePct = Double(solved) / Double(games) * 100
    let avgDeduce = solved > 0 ? Double(deductSum) / Double(solved) : 0
    let avgOpen = Double(openSum) / Double(games)

    let row =
        pad(shape.rawValue, 6) + " " + pad(c.label, 28) + " " + pad("\(cells)", 6) + " "
        + pad("\(c.mines)", 6) + " " + pad(col(density) + "%", 8) + " "
        + pad(col(solvePct) + "%", 7) + " " + pad(col(100 - solvePct) + "%", 7) + " "
        + pad(col(avgDeduce), 7) + " " + pad(col(avgOpen), 6)
    print(row)
}

let shapesToRun: [Shape] = {
    switch ProcessInfo.processInfo.environment["SHAPE"]?.lowercased() {
    case "hex": return [.hex]
    case "square": return [.square]
    default: return [.square, .hex]
    }
}()

print("shape  config                       cells  mines  density  solve%  guess%  deduce  open")
print(String(repeating: "-", count: 93))
for shape in shapesToRun {
    for c in candidates { run(shape, c) }
    print(String(repeating: "-", count: 93))
}
