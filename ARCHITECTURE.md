# Architecture & key decisions

The load-bearing design choices and *why* they're that way — the context that
isn't obvious from the code or the commit that introduced it. For the day-to-day
contributor/agent guide (commands, conventions, the `Topology` / `CellLayout`
seams, repo layout) see [AGENTS.md](AGENTS.md); for what shipped see
[CHANGELOG.md](CHANGELOG.md); for what's planned see [ROADMAP.md](ROADMAP.md).

## Module split: `DonpaCore` vs `DonpaKit`

- **`DonpaCore`** — pure game logic and value types (`Game`, `Board`, `Cell`,
  `Coord`, `GameConfig`, `Topology`, `Solver`, `GameSnapshot`). No SwiftUI, no
  SpriteKit, no platform APIs. Fully unit-tested; deterministic.
- **`DonpaKit`** — the SwiftUI + SpriteKit UI layer; depends on Core.
- The two app targets (`Sources/{iOS,macOS}`) are thin `@main` shells hosting
  `GameView()`.

Why: keeping the rules platform- and rendering-free means they're trivially
testable and the "epic" variants (hex, torus) drop in as new `Topology`
conformers without touching UI. It also keeps `swift test` fast (no Xcode
project, no simulator) as the inner loop.

## Game state lives in value types; the view model bridges

`Game`/`Board` are **structs** (value semantics) — a move produces a new state,
which makes reasoning and testing simple and snapshots cheap. `GameViewModel`
(`@MainActor`, `ObservableObject`) owns the current `Game`, the timer, and input
mode, and republishes a `revision` counter on every change so the SpriteKit
scene knows to re-render without diffing.

Win/progress is **O(1)**: `Game.revealedSafeCount` is an incremental counter, so
`checkWin` never scans the board. This matters for the v0.2 huge-board goal and
already backs the progress-% feature.

## SpriteKit board, owned by SwiftUI, input handled natively

The board is a single long-lived `BoardScene` (`SKScene` + `SKCameraNode`) in a
SwiftUI `SpriteView`. **All board input — tap, click, flag, chord, pan, zoom —
is handled inside the scene** (`UIGestureRecognizer` / `NSEvent`), not via
SwiftUI gestures, because native handling is far more responsive and gives the
right platform feel (two-finger trackpad pan, right-click flag, the mode cursor).

Ownership is a DAG, not a cycle: `GameView` owns both the `viewModel`
(`@StateObject`) and the `scene` (`@State`); the scene references the view model,
but the view model never references the scene. (Audited leak-free — the Combine
timer uses `[weak self]`, effects are declarative `SKAction`s, and gesture
recognizers hold their target weakly by framework convention.)

## Two native app targets — *not* Mac Catalyst

The Mac app is a separate native AppKit/SwiftUI target, not Catalyst. Catalyst
would simplify publishing (one universal-purchase record) but at the cost of the
native Mac UX this app leans on: the mode cursor (`NSCursor`), click-vs-drag and
right-click (`NSEvent`), two-finger `scrollWheel` pan, menu-bar commands, and
`keyDown`. Under Catalyst those are exactly the weakest interactions. The cost
(a second App Store submission + a distinct Mac bundle id, `fi.misaki.donpa.mac`)
is worth the better result. Bundle ids must diverge **before** registering with
Apple — changing them afterward is painful.

## Some UI workarounds are deliberate (don't "fix" them)

SwiftUI/SpriteKit interop on macOS needed a few non-obvious choices, each
documented at its call site:

- **Board cursor** uses an `NSTrackingArea` + explicit `NSCursor.set()`, not
  `addCursorRect` — cursor rects proved unreliable inside the hosted scene.
- **Palette/scheme** is resolved from one effective `ColorScheme` and pushed to
  the scene as a value (via `updateUIView`/`updateNSView`), because a view can't
  observe a scheme it forces on itself and `.onChange` was unreliable for the
  scene.
- **Escape / modal keys**: overlays use `.onExitCommand` (and a focusable
  `KeyCatcher` for the New Game popup) because an Escape menu key-equivalent
  isn't delivered by AppKit and the SpriteKit view holds first responder.
- **`onChangeCompat`** wraps `onChange` so the iOS-16 floor and macOS-14 share
  one warning-free call site (the zero/two-parameter form is iOS 17 / macOS 14
  only; the single-parameter form is deprecated on macOS 14).

## Persistence: compact, tagged, atomic, tolerant

The in-progress-game save (`GameSnapshot`) and the scoreboard (`Scoreboard`) are
the two persisted stores. Both follow the same compatibility rules so an app
update never costs a player their data — the scoreboard especially (losing a
mid-game is a shrug; losing your records is not).

- **Compact + tagged.** `GameSnapshot` stores the **`GameConfig`** (which
  *carries* the topology kind + params — the `any Topology` existential is never
  encoded) plus the first-click-safe mine layout and the revealed/flagged cells
  as **coordinate sets**, not the full cell dict (a 1000² board would be huge
  otherwise; dovetails with the v0.2 flat-storage rework). The scoreboard is a
  `[storageKey: ScoreRecord]` map (see below).
- **Atomic.** `SaveStore` writes the game save with `Data.write(.atomic)` (temp
  file + rename), so a crash mid-save can't corrupt it — the prior save survives.
- **Versioned + additive.** Each store has a format `version`. New fields are
  added **optional-with-default**, so an older save still decodes in a newer app
  (the common, non-breaking case is free — no migration needed). A save from a
  *newer* app (`version > current`) is refused rather than mis-read.
- **Migration seam, migrations later.** Each store routes loads through a
  `migrated(…)` step (identity today — there are no breaking changes yet). When a
  truly breaking change lands, add one versioned transform there with a
  fixture-based test, rather than re-architecting. Same forward-compatible
  instinct as `storageKey`; don't build speculative migration code before a real
  migration exists.
- **Per-entry resilience (scoreboard).** Records decode **independently** — one
  corrupt or incompatible row is dropped, never failing the whole table. (The
  game save is a single object, so it's all-or-nothing by nature: a bad save is
  discarded and you start fresh.)
- **Never a crash or a broken state.** Anything unreadable / wrong-version /
  out-of-bounds is discarded; a restored game also filters out-of-bounds coords
  and recomputes its safe-cell count from the board.

`GameConfig.storageKey` (`v1|modern|sq|bounded|16x16|m41`) is itself a versioned,
geometry-bearing token naming future shape/edges axes with defaults, so adding
wrapped/hex boards or re-tuning tiers creates **new** scoreboard entries rather
than colliding with old ones. Scores are local and user-editable by design (no
anti-cheat; lean on Game Center's server-side validation if leaderboards land).

## Assets are generated, not hand-drawn-in-repo

The app icon, the B&W variant, the launch image, and the in-grid detonation mark
all come from **one procedural source** (`Scripts/make-icon.swift`, pure
CoreGraphics) — reproducible, no binary-blob churn, and the launch screen and
in-app splash share the *same* rendered PNG so they can't drift. The manga
result/title panels are the exception: swappable PNG asset slots (currently
AI-generated; a commissioned artist could replace the slot with no code change —
verify commercial-use licensing before shipping).
