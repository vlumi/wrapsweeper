# Wrapsweeper

[![CI](https://github.com/vlumi/wrapsweeper/actions/workflows/ci.yml/badge.svg)](https://github.com/vlumi/wrapsweeper/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/vlumi/wrapsweeper/branch/main/graph/badge.svg)](https://codecov.io/gh/vlumi/wrapsweeper)

A Minesweeper game for Apple platforms (iOS 16+ and macOS 13+). Classic mode
ships first; the architecture is built for "epic" variants from day one —
huge zoomable maps, wrapped/torus edges, and hex grids — added later without
touching the game logic.

The first release will be **v0.1.0** (classic mode); see [ROADMAP.md](ROADMAP.md)
for the path to v1.0 and [CHANGELOG.md](CHANGELOG.md) for changes.

## How it's built to stay flexible

All variation is isolated behind two seams; everything else is written once:

- **`Topology`** — the logical "who are my neighbours?" relation
  (square ↔ hex, bounded ↔ wrapped). Mine placement, adjacency, flood-fill,
  and win/lose are expressed *only* in terms of `neighbors(of:)` / `allCoords()`,
  so a new variant is a new `Topology` and nothing else. A test already wins a
  full game on a wrapped (torus) board using the unchanged game logic.
- **`CellLayout`** — the visual coordinate → pixel mapping and hit-testing.
  `SquareLayout` ships now; `HexLayout` slots in here later with no change to
  the renderer or the game logic.

## Structure

```text
wrapsweeper/
├── project.yml                  XcodeGen spec (iOS + macOS app targets)
├── Scripts/generate.sh          Regenerates the .xcodeproj (refuses while Xcode is open)
├── Sources/{iOS,macOS}/         Thin @main app shells
└── Packages/WrapsweeperCore/    Swift package — ~90% of the code
    ├── Sources/WrapsweeperCore/ Pure logic, zero UI imports, fully tested
    └── Sources/WrapsweeperKit/  SpriteKit + SwiftUI, depends on Core
```

The rendering engine is **SpriteKit** (`SKScene` + `SKCameraNode`) hosted in a
SwiftUI `SpriteView`; the camera provides the pan/zoom that huge maps will lean
on. No third-party dependencies.

## Building

Requires Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`). The `.xcodeproj` is a generated artifact and is not
checked in.

```sh
# Run the logic test suite (no Xcode needed)
cd Packages/WrapsweeperCore && swift test

# Generate the Xcode project, then open it
./Scripts/generate.sh
open Wrapsweeper.xcodeproj
```

## Controls

A toolbar toggle switches a tap/click between **Reveal mode** (⛏️) and
**Flag mode** (🚩), so you can place flags without risking an accidental reveal.
A tap on a revealed number always chords in either mode, and a long-press is
always the opposite primary action.

The toggle shows ⛏️ in Reveal mode and 🚩 in Flag mode.

| Action            | Reveal mode   | Flag mode     |
| ----------------- | ------------- | ------------- |
| Tap/click hidden  | Reveal        | Flag / unflag |
| Tap/click number  | Chord         | Chord         |
| Long-press hidden | Flag / unflag | Reveal        |

| Other           | iOS   | macOS                        |
| --------------- | ----- | ---------------------------- |
| Flag (any mode) | —     | Right-click or Control-click |
| Pan             | Drag  | Two-finger scroll            |
| Zoom            | Pinch | Pinch (trackpad)             |

Panning is constrained to the board, so you can never scroll past its edges;
when the whole board already fits on screen, panning is disabled.

### Keyboard shortcuts

| Key     | Action                                        |
| ------- | --------------------------------------------- |
| Space   | Toggle reveal / flag mode                     |
| ⌘N      | New game (macOS menu)                         |
| ⌘F      | Toggle mode (macOS menu)                      |
| ⌘1/2/3  | Beginner / Intermediate / Expert (macOS menu) |

## Scores

Per-difficulty stats are kept locally (via `UserDefaults`) and shown from the
🏆 button: your best time and how many games you've cleared on each difficulty.
Beating a best time opens the scoreboard automatically.

## Settings

The ⚙️ button opens settings. Appearance can be set to **System**, **Light**,
or **Dark** — the board and chrome share one palette that follows the choice
(System tracks the OS). The selection is saved between launches.

## License

[MIT](LICENSE).
