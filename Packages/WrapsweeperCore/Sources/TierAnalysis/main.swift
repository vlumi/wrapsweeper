import Foundation
import WrapsweeperCore

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
let densities: [(String, Double)] = [
    ("Easy", 0.10), ("Normal", 0.13), ("Hard", 0.16), ("Brutal", 0.19), ("Insane", 0.22),
]

var candidates: [Candidate] = [
    Candidate(label: "Classic Beginner   9x9", width: 9, height: 9, mines: 10),
    Candidate(label: "Classic Intermed. 16x16", width: 16, height: 16, mines: 40),
    Candidate(label: "Classic Expert    30x16", width: 30, height: 16, mines: 99),
]

let sizeSets: [(String, [(String, Int)])] = [
    ("Modern", [("Small", 9), ("Medium", 16), ("Large", 25)])
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

print("config                       cells  mines  density  solve%  guess%  deduce  open")
print(String(repeating: "-", count: 86))

for c in candidates {
    let cells = c.width * c.height
    var solved = 0
    var deductSum = 0
    var openSum = 0
    let topo = BoundedSquareTopology(width: c.width, height: c.height)
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
        pad(c.label, 28) + " " + pad("\(cells)", 6) + " " + pad("\(c.mines)", 6) + " "
        + pad(col(density) + "%", 8) + " " + pad(col(solvePct) + "%", 7) + " "
        + pad(col(100 - solvePct) + "%", 7) + " " + pad(col(avgDeduce), 7) + " "
        + pad(col(avgOpen), 6)
    print(row)
}
