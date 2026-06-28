# Donpa Squad

[![CI](https://github.com/vlumi/donpa/actions/workflows/ci.yml/badge.svg)](https://github.com/vlumi/donpa/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/vlumi/donpa/branch/main/graph/badge.svg)](https://codecov.io/gh/vlumi/donpa)

**Donpa Squad** (ドンパ隊) — a manga-styled Minesweeper for Apple platforms
(iOS 16+ and macOS 14+). Classic mode ships first; the architecture is built for
"epic" variants from day one — huge zoomable maps, wrapped/torus edges, and hex
grids — added later without touching the game logic.

**v0.1.0** (classic mode) shipped to TestFlight; **v0.2.0** (big boards +
cross-device sync) is in progress. See [CHANGELOG.md](CHANGELOG.md) for the
version history, [ROADMAP.md](ROADMAP.md) for the path to v1.0, and
[ARCHITECTURE.md](ARCHITECTURE.md) for the key design decisions.

## Contents

- [Modes](#modes)
- [Controls](#controls)
- [Start and end of a game](#start-and-end-of-a-game)
- [Scores](#scores)
- [Settings](#settings)
- [AI assistance](#ai-assistance)
- [Version history](#version-history)
- [Development](#development)
- [License](#license)

## Modes

A **Classic / Modern** switch in the **New Game popup** chooses the board (open
it from the title art, the in-game **config badge**, the result screen, or
`⌘N`):

- **Classic** — the original Beginner / Intermediate / Expert presets.
- **Modern** — pick a **Difficulty** then a **Size**. The size ladder runs
  XS / S / M / L / XL / XXL / XXXL (9² up to 1000² = a million cells); the larger
  boards are panned and zoomed, with a minimap for navigation. Difficulty is mine
  density (the deliberately brutal top tier is near-unguessable), so it composes
  with any size. Each tier carries its **military rank insignia** — chevron
  stripes for the lower ranks, a star, then a star-in-laurel for the apex. The
  chosen mode and selections are remembered.

Both rows are a horizontal **carousel**: scroll/swipe (or click) to pick, with a
line below the selection showing the board facts and a short flavour tagline.

On macOS the popup is keyboard-drivable: **↑/↓** move between the rows (Mode /
Difficulty / Size), **←/→** cycle the selection within the highlighted row,
**Return** starts, **Esc** closes.

## Controls

A **toggle** in a thumb-reachable corner of the board switches a tap/click
between **Dig mode** and **Flag mode**, so you can place flags without risking an
accidental reveal. Its corner follows the **Toggle side** setting (left/right)
for your grip. A tap on a revealed number always chords in either mode, and a
long-press is always the opposite primary action.

The board chrome is split in two: a thin top strip shows a tappable **config
badge** (the current game — its rank insignia + size — which opens the New Game
popup to switch) and read-only metrics — the flag counter, a live **clear-%**,
the timer, and the 🎖️ High Scores button — while a strip beside or below the
board (whichever the board's shape leaves room for) holds the **Retry / Pause /
Home** actions plus the dig/flag toggle. Unopened tiles carry a faint manga
screentone keyed to the toggle (dots for dig, hatch for flag).

| Action            | Dig mode      | Flag mode     |
| ----------------- | ------------- | ------------- |
| Tap/click hidden  | Reveal        | Flag / unflag |
| Tap/click number  | Chord         | Chord         |
| Long-press hidden | Flag / unflag | Reveal        |

| Other           | iOS   | macOS                        |
| --------------- | ----- | ---------------------------- |
| Flag (any mode) | —     | Right-click or Control-click |
| Pan             | Drag  | Two-finger scroll            |
| Zoom            | Pinch | Pinch (trackpad)             |

On macOS the pointer reflects the mode while a game is in progress — a pointing
hand to dig, a flag to flag (a plain arrow otherwise); holding **Control** shows
the other mode's cursor, since Control-click does the opposite action. Panning is
bounded to the board: it rests with a little breathing room past each edge, and
pulling further rubber-bands with resistance before springing back. When the
whole board already fits on screen, panning is disabled.

### Keyboard shortcuts

| Key      | Action                                             |
| -------- | -------------------------------------------------- |
| Space    | Toggle mode while playing                          |
| ⌘N       | New Game (opens the config popup, macOS menu)      |
| ⌘R       | Restart the current board (macOS menu)             |
| ⌘T       | Return to the title screen (macOS menu)            |
| ⌘F       | Toggle mode (macOS menu)                           |
| ⌘+ / ⌘−  | Zoom the board in / out (also ⌘-scroll)            |
| ⌘0       | Open the board overview (macOS menu)               |
| ⌘1/2/3   | Beginner / Intermediate / Expert (macOS menu)      |
| Esc      | Close the New Game popup, overview, or result panel|

## Start and end of a game

The app opens on a **title screen** that doubles as the home hub: tapping the
art opens the **New Game popup** to pick a board and start. The 🎖️ High Scores,
⚙️ Settings, and ⓘ About buttons sit on the art's corner. You can return to the
title any time from the in-game **Home** button or the **Title Screen** menu item
(⌘T) on macOS.

When a game ends, a comic **result panel** slides in over the **board** — a
triumphant one on a win, a dramatic one on a loss, with a "new record" flourish
when you beat your best time. It dims only the board, so the control strip stays
live:

- **Retry / Home** (and the config badge for a different game) remain usable on
  the chrome — no need to dismiss the panel first. Retry replays the same board;
  the config badge opens the New Game popup.
- Dismiss the panel to inspect the finished board via the **X**, a tap anywhere,
  or **Esc**.

## Scores

Per-board stats are kept locally (via `UserDefaults`) and shown from the 🎖️
button (in the top strip in-game, or on the title art): your best time and how
many games you've cleared on each board. A new best is celebrated on the result
panel; the full table is always available from the 🎖️ button.

Stats are keyed by board geometry, not by tier name, so the format stays stable
toward the "epic" variants: adding wrapped or hex boards — or re-tuning a tier —
creates new scoreboard entries rather than reinterpreting existing scores.

## Settings

The ⚙️ button opens settings. Appearance can be set to **System**, **Light**,
or **Dark** — the board and chrome share one palette that follows the choice
(System tracks the OS). The selection is saved between launches.

## AI assistance

Donpa Squad is built with substantial AI assistance, and that's stated openly
here rather than hidden. The project is human-directed — design, gameplay, and
every visual decision are the author's — but the **code is largely AI-written**
and the **current scene art (the title, result, and pause panels) is
AI-generated** (DALL·E). The procedural visuals — the app icon, the manga UI
glyphs, and the board screentone — are AI-*written code*, not generated images.
If hand-made or commissioned art replaces the generated pieces later, this note
will be updated to credit it.

## Version history

High-level only — see [CHANGELOG.md](CHANGELOG.md) for the full detail. Donpa is
in TestFlight beta; releases ship as rolling per-platform betas on iOS and macOS.

### 0.2.0 — cross-device sync & big boards

- **New:** iCloud cross-device sync for high scores and career totals (opt-in,
  off by default; conflict-free, degrades to local-only when signed out).
- **New:** lifetime career stats (games, tiles, flags, mines, playtime) in a
  reworked one-sheet Service Record.
- **New:** bigger Modern boards — the size ladder now runs XS to XXXL (up to a
  million cells), panned/zoomed with a minimap.
- **New:** the New Game difficulty/size pickers became a swipeable carousel; a
  resumed game restores your camera position; macOS gained mouse/keyboard zoom.
- **Changed:** huge boards stay responsive (reveal, mine placement, and the
  minimap compute off the main thread; the first tap is always instant).
- **Fixed:** the cleared-% and loss "best %" now floor consistently; flags
  survive a loss; correctly-flagged mines don't detonate.

### 0.1.0 — first release

- Classic Minesweeper on iOS and macOS: first-click safety, flood-fill reveal,
  flagging, and chording, with a dig/flag input-mode toggle.
- Two board modes — **Classic** (Beginner / Intermediate / Expert) and
  **Modern** (a difficulty × size grid), chosen in the New Game popup.
- A SpriteKit board with pan/zoom, a manga theme (comic result, pause, and title
  panels), and a procedural detonating-mine app icon.
- Per-board best times + games-cleared stats, autosave/resume, pause, light/dark
  appearance, haptics, and an About screen.

## Development

The codebase is mostly a Swift package (`Packages/DonpaCore`): a pure
`DonpaCore` logic target with zero UI imports (fully tested) and a `DonpaKit`
SpriteKit + SwiftUI target on top; thin iOS/macOS app shells host it. All board
variation is isolated behind two seams — **`Topology`** (logical neighbours:
square ↔ hex, bounded ↔ wrapped) and **`CellLayout`** (coordinate → pixel) — so
new board types land as new conformers without touching the game logic.
[ARCHITECTURE.md](ARCHITECTURE.md) covers the load-bearing decisions and
[AGENTS.md](AGENTS.md) the conventions, build commands, and asset pipeline.

Requires Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`); the `.xcodeproj` is generated, not checked in. A
`Makefile` drives everything from the command line:

```sh
make            # list the available targets
make run-mac    # build + launch the macOS app
make run-ios    # build + launch in an iOS simulator
make test       # run the package logic tests (no Xcode project needed)
make uitest     # run the iOS UI tests in a simulator (local only; not on CI)
```

No third-party dependencies. CI runs SwiftLint + swift-format, the logic tests
(with coverage), and both platform builds.

## License

Code: [MIT](LICENSE). The **name and brand assets** ("Donpa Squad" / ドンパ隊, the
icon, and the artwork) are reserved and **not** covered by the MIT grant — see
[TRADEMARKS.md](TRADEMARKS.md). In short: fork the code freely, but a public fork
needs its own name and branding.
