# Donpa Squad

[![CI](https://github.com/vlumi/donpa/actions/workflows/ci.yml/badge.svg)](https://github.com/vlumi/donpa/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/vlumi/donpa/branch/main/graph/badge.svg)](https://codecov.io/gh/vlumi/donpa)

**Donpa Squad** (ドンパ隊) — a Minesweeper game for Apple platforms (iOS 16+ and macOS 13+). Classic mode
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
donpa/
├── project.yml                  XcodeGen spec (iOS + macOS app targets)
├── Scripts/generate.sh          Regenerates the .xcodeproj (refuses while Xcode is open)
├── Sources/{iOS,macOS}/         Thin @main app shells
└── Packages/DonpaCore/    Swift package — ~90% of the code
    ├── Sources/DonpaCore/ Pure logic, zero UI imports, fully tested
    └── Sources/DonpaKit/  SpriteKit + SwiftUI, depends on Core
```

The rendering engine is **SpriteKit** (`SKScene` + `SKCameraNode`) hosted in a
SwiftUI `SpriteView`; the camera provides the pan/zoom that huge maps will lean
on. No third-party dependencies.

## Building

Requires Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`). The `.xcodeproj` is a generated artifact and is not
checked in.

A `Makefile` drives everything from the command line, so you never have to open
Xcode just to run the app (the generated project regenerates only when
`project.yml` or an `Info.plist` changes):

```sh
make            # list the available targets
make run-mac    # build + launch the macOS app
make run-ios    # build + launch in an iOS simulator (newest iOS 16+ iPhone)
make build-mac  # build the macOS app
make build-ios  # build the iOS app (simulator)
make test       # run the package logic tests (no Xcode project needed)
make generate   # regenerate Donpa.xcodeproj from project.yml (if stale)
make clean      # remove the generated project + local build output
```

The targets delegate to `Scripts/*.sh` (each does one step); the Makefile wires
up the dependencies. To work in Xcode instead, `make generate && open Donpa.xcodeproj`.

## Modes

A **Classic / Modern** switch in the bottom bar chooses the board:

- **Classic** — the original Beginner / Intermediate / Expert presets.
- **Modern** — pick a **Size** (Small 9×9 · Medium 16×16 · Large 25×25) and a
  **Difficulty** (Easy · Normal · Hard · Brutal · Insane). Difficulty is mine
  density, so it composes with any size; Insane is the deliberately brutal,
  near-unguessable tier. The chosen mode and selections are remembered.

## Controls

A toolbar toggle switches a tap/click between **Reveal mode** and **Flag mode**,
so you can place flags without risking an accidental reveal. A tap on a revealed
number always chords in either mode, and a long-press is always the opposite
primary action.

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

On macOS the pointer reflects the mode while a game is in progress — a crosshair
to reveal, a flag to flag (a plain arrow otherwise). Panning is constrained to
the board, so you can never scroll past its edges; when the whole board already
fits on screen, panning is disabled.

### Keyboard shortcuts

| Key    | Action                                               |
| ------ | ---------------------------------------------------- |
| Space  | Toggle mode while playing; restart after a game ends |
| ⌘R     | Restart the current board (macOS menu)               |
| ⌘T     | Return to the title screen (macOS menu)              |
| ⌘F     | Toggle mode (macOS menu)                             |
| ⌘1/2/3 | Beginner / Intermediate / Expert (macOS menu)        |

## Start and end of a game

The app opens on a **title screen**; tap it (or press Space / Return on macOS)
to start. You can return to it any time from the end-of-game screen, or via the
**Title Screen** menu item (⌘T) on macOS.

When a game ends, a comic **result panel** slides in over the board — a
triumphant one on a win, a dramatic one on a loss, with a "new record" flourish
when you beat your best time. It stays until you choose:

- **Continue** (or tap anywhere / Return) — dismiss it to look over the finished
  board.
- **Title** (or Esc) — go back to the title screen.
- **Restart** the same board instantly with **Space** or **⌘R** — no need to
  dismiss the panel first.

## Scores

Per-board stats are kept locally (via `UserDefaults`) and shown from the 🏆
button in Classic and Modern sections: your best time and how many games you've
cleared on each board. A new best is celebrated on the result panel; the full
table is always available from the 🏆 button.

Stats are keyed by board geometry, not by tier name, so the format stays stable
toward the "epic" variants: adding wrapped or hex boards — or re-tuning a tier —
creates new scoreboard entries rather than reinterpreting existing scores.

## Settings

The ⚙️ button opens settings. Appearance can be set to **System**, **Light**,
or **Dark** — the board and chrome share one palette that follows the choice
(System tracks the OS). The selection is saved between launches.

## License

[MIT](LICENSE).
