# Wrapsweeper — agent & contributor guide

A Minesweeper game for Apple platforms. Classic mode first; "epic" variants
(huge zoomable maps, wrapped/torus edges, hex grids) are designed for from day
one but built later. This file is the canonical guidance for both humans and
AI coding agents working in this repo.

## Project facts

- **Platforms:** iOS 16+ and macOS 13+. (An older Intel Mac was intentionally
  dropped — its macOS ceiling forced obsolete SwiftUI APIs.)
- **Toolchain:** Xcode 16+ / Swift 6, XcodeGen.
- **Bundle id:** `fi.misaki.wrapsweeper`. **License:** MIT. No monetization.
- The `.xcodeproj` is a **generated artifact** (gitignored) — never edit or
  commit it. Signing/team settings live only in that local file, never in
  `project.yml`, so nothing sensitive is committed.

## Architecture: classic-first, epic-ready

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
wrapsweeper/
├── project.yml                  XcodeGen spec (iOS + macOS app targets)
├── Scripts/generate.sh          Regenerates the .xcodeproj (refuses if THIS project is open in Xcode)
├── Scripts/make-icon.swift      Regenerates the app icon PNGs into Sources/Shared
├── Sources/{iOS,macOS}/         Thin @main app shells
├── Sources/Shared/              Assets shared by both targets (the AppIcon set)
└── Packages/WrapsweeperCore/    Swift package — most of the code
    ├── Sources/WrapsweeperCore/ Pure logic (GameConfig, Solver, …), fully tested
    ├── Sources/WrapsweeperKit/  SpriteKit + SwiftUI, depends on Core
    └── Sources/TierAnalysis/    Dev-only CLI: `swift run TierAnalysis` (not shipped)
```

- `GameConfig` is the single source of board dimensions, mine count, topology,
  label, and the **scoreboard key** — a versioned, geometry-bearing token
  string built to stay stable through future board variants (no migrations).

- App targets are thin: `@main` app + a view hosting `GameView()`.
- Engine: **SpriteKit** (`SKScene` + `SKCameraNode`) in a SwiftUI `SpriteView`.
  All board input (tap/click/flag/chord/pan/zoom) is handled natively inside
  `BoardScene`, not via SwiftUI gestures. First-party only, no third-party deps.

## Commands

```sh
# Logic tests (no Xcode needed) — the fast inner loop
cd Packages/WrapsweeperCore && swift test

# Build just the package (compiles the macOS branch of WrapsweeperKit)
cd Packages/WrapsweeperCore && swift build

# Generate the Xcode project, then build an app target
./Scripts/generate.sh
xcodebuild -project Wrapsweeper.xcodeproj -scheme Wrapsweeper-macOS -destination 'platform=macOS' build
xcodebuild -project Wrapsweeper.xcodeproj -scheme Wrapsweeper-iOS  -destination 'generic/platform=iOS Simulator' build
```

`swift build` on macOS only compiles the `#if os(macOS)` branch of platform
code — build the iOS target via `xcodebuild` to exercise the iOS branch.

### Lint & format

```sh
swiftlint lint --strict                 # style + light correctness (config: .swiftlint.yml)
swift format lint --strict --recursive --configuration .swift-format \
  Packages/WrapsweeperCore/Sources Packages/WrapsweeperCore/Tests Sources
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

- SourceKit in-IDE diagnostics may report `No such module 'WrapsweeperCore'`
  for files it hasn't indexed — these are **false**. The authoritative checks
  are `swift build` / `swift test` / `xcodebuild`.
- `BoardScene` uses `SKScene`'s built-in `camera`; the camera node is held as
  `cameraNode`. Don't add a separate `camera` stored property.
