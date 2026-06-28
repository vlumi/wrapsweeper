# Donpa — agent & contributor guide

A Minesweeper game for Apple platforms. Classic mode first; "epic" variants
(huge zoomable maps, wrapped/torus edges, hex grids) are designed for from day
one but built later. This file is the canonical guidance for both humans and
AI coding agents working in this repo.

## Project facts

- **Platforms:** iOS 16+ and macOS 14+. (Intel Macs are out of scope — Apple-
  silicon only — so the macOS floor tracks a recent OS and current SwiftUI APIs;
  macOS 13 was dropped when focus/keyboard APIs there proved unreliable.)
- **Toolchain:** Xcode 16+ / Swift 6, XcodeGen.
- **Bundle id:** `fi.misaki.donpa`. **License:** MIT. No monetization.
- The `.xcodeproj` is a **generated artifact** (gitignored) — never edit or
  commit it. Signing/team settings live only in that local file, never in
  `project.yml`, so nothing sensitive is committed.

## Architecture: classic-first, epic-ready

The load-bearing design decisions and their rationale live in
[ARCHITECTURE.md](ARCHITECTURE.md) (module split, state model, why native
SpriteKit input, no-Catalyst, persistence format, the deliberate UI workarounds).
The essentials:

Two seams isolate all "epic" variation; everything else is written once.

- **`Topology`** — the logical "who are my neighbours?" relation (square ↔ hex,
  bounded ↔ wrapped). All game logic (mine placement, adjacency, flood-fill,
  win/lose) is written *only* in terms of `neighbors(of:)` / `allCoords()`, so a
  new variant is a new `Topology` and nothing else.
- **`CellLayout`** — the visual coordinate → pixel mapping and hit-testing.
  `SquareLayout` ships now; `HexLayout` slots in here later with no change to
  the renderer or the game logic.

### Structure

```text
donpa/
├── project.yml                  XcodeGen spec (iOS + macOS app targets)
├── Scripts/generate.sh          Regenerates the .xcodeproj (refuses if THIS project is open in Xcode)
├── Scripts/assets/              Asset generators (hand-run, rare) + their committed art sources:
│     make-icon.swift            Regenerates the app icon + launch PNGs (pure CoreGraphics)
│     make-boot.swift            Boot-print "dig" glyph: SVG → tintable template (needs ImageMagick)
│     make-panels.swift          Win/loss/pause panels: source PNG → keyed transparent asset
│     *.svg / *-source.png       The SVG / cleaned DALL·E PNG sources the above consume
├── Sources/{iOS,macOS}/         Thin @main app shells
├── Sources/Shared/              Assets shared by both targets (the AppIcon set)
└── Packages/DonpaCore/    Swift package — most of the code
    ├── Sources/DonpaCore/ Pure logic (GameConfig, Solver, CellLayout, …), tested + coverage-gated
    ├── Sources/DonpaKit/  SpriteKit + SwiftUI, depends on Core; coverage-ignored wholesale
    └── Sources/TierAnalysis/    Dev-only CLI: `swift run TierAnalysis` (not shipped)
```

- `GameConfig` is the single source of board dimensions, mine count, topology,
  label, and the **scoreboard key** — a versioned, geometry-bearing token
  string built to stay stable through future board variants (no migrations).

- App targets are thin: `@main` app + a view hosting `GameView()`.
- Engine: **SpriteKit** (`SKScene` + `SKCameraNode`) in a SwiftUI `SpriteView`.
  All board input (tap/click/flag/chord/pan/zoom) is handled natively inside
  `BoardScene`, not via SwiftUI gestures. First-party only, no third-party deps.

### Art assets

Images are kept reproducible: the **source** lives in `Scripts/assets/`, a
**script** turns it into the catalog asset, and both are committed. To change an
asset, replace the source and re-run its script — don't hand-edit the catalog
PNGs. (See the README "AI assistance" note: the source art is AI-generated;
licensing for any future commissioned art is an open ROADMAP item.)

- **App icon / launch** — `swift Scripts/assets/make-icon.swift <outDir> [--mono|--launch]`.
  Pure CoreGraphics (a detonating mine in a halftone burst); no external source.
- **Boot-print "dig" glyph** — `swift Scripts/assets/make-boot.swift`. Rasterises
  `assets/boot-print.svg` (CC0) and keys it to a tintable **template** PNG in the
  `BootPrint` imageset. Needs ImageMagick (`brew install imagemagick`); Quick
  Look was tried but crops the tall print.
- **Framed panels (win / loss / pause)** — `swift Scripts/assets/make-panels.swift [win loss pause]`.
  These three are the *same kind* of art — a black-bordered manga panel where art
  may **spill past the border** (rocks/boot/detector breaking the frame). The
  sources are **already keyed** (`assets/<panel>-source.png`, alpha baked in:
  transparent where the page was, opaque art). The script does only the
  packaging: it adds a thin white "page" **outline** at every transparent↔opaque
  edge (so the black-ink art and the spilled bits still read in **dark mode**),
  crops to the opaque content, and writes `@1x/2x/3x`. No keying/flooding in code
  — automatic keying proved fiddly on busy panels (clouds/explosions), so the
  transparency is done in an editor and the script just outlines + scales.
  - **Authoring a new panel image**: prompt for a single bold framed manga panel,
    black ink on white, thin rectangular border; a little art breaking the frame
    is good (it's preserved). Then **key it in an editor** — make the page/margin
    transparent, leaving the frame + interior + spilled art opaque (keep the
    *insides* of spilled clouds/rocks opaque) — and save as the source. The
    script handles the white outline; don't bake an outline into the source.
- **Title screen** — NOT a framed panel: it's a full-bleed **poster** shown on a
  white plate (no border, no transparency), so it ships as its raw PNG
  (`TitleScreen` imageset) with no keying script. `assets/title-screen-source.png`
  is kept for reference only.

## Commands

```sh
# Logic tests (no Xcode needed) — the fast inner loop
cd Packages/DonpaCore && swift test

# Build just the package (compiles the macOS branch of DonpaKit)
cd Packages/DonpaCore && swift build

# Generate the Xcode project, then build an app target
./Scripts/generate.sh
xcodebuild -project Donpa.xcodeproj -scheme Donpa-macOS -destination 'platform=macOS' build
xcodebuild -project Donpa.xcodeproj -scheme Donpa-iOS  -destination 'generic/platform=iOS Simulator' build

# Local-only UI regression tests (XCUITest) — drive the iOS app in a simulator.
make uitest   # NOT run by CI (CI does `swift test` + `xcodebuild build` only)
```

`swift build` on macOS only compiles the `#if os(macOS)` branch of platform
code — build the iOS target via `xcodebuild` to exercise the iOS branch.

UI tests live in `Tests/UITests/` and query stable `accessibilityIdentifier`s
(e.g. `title.start`, `newgame.start`, `game.home`, `game.pause`, `sheet.done`).
They run only locally via `make uitest`; CI never invokes `xcodebuild test`.

### Lint & format

```sh
swiftlint lint --strict                 # style + light correctness (config: .swiftlint.yml)
swift format lint --strict --recursive --configuration .swift-format \
  Packages/DonpaCore/Sources Packages/DonpaCore/Tests Sources
swift format --in-place --recursive --configuration .swift-format <paths>   # auto-format
```

CI runs both with `--strict` (warnings fail). **swift-format is the authority
on whitespace/punctuation**; where SwiftLint conflicts (trailing commas, brace
placement) those SwiftLint rules are disabled rather than fought. Run the
formatter before committing.

## Conventions

- **Comments minimal:** explain only what isn't obvious from the code. No
  historical / roadmap ("lands later") narration in source — that goes in
  commit messages.
- Mine placement is **seedable** (`RandomNumberGenerator` injected) for
  deterministic tests; production paths use `SystemRandomNumberGenerator`.
- First click is always safe: mines are placed after the first reveal,
  excluding the clicked cell and its neighbours.
- `.vscode/` is gitignored and must not be pushed.
- When you change game rules or controls, update `README.md` too.

## Gotchas

- SourceKit in-IDE diagnostics may report `No such module 'DonpaCore'`
  for files it hasn't indexed — these are **false**. The authoritative checks
  are `swift build` / `swift test` / `xcodebuild`.
- `BoardScene` uses `SKScene`'s built-in `camera`; the camera node is held as
  `cameraNode`. Don't add a separate `camera` stored property.
