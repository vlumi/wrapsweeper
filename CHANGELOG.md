# Changelog

All notable changes to Donpa are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

Work toward **v0.2.0** — cross-device sync & big boards (see ROADMAP.md). The
big-board pillar largely landed; iCloud score sync is still open.

### Added

- **Big boards, XS–XXXL.** The Modern size ladder is now XS / S / M / L / XL /
  XXL / XXXL (9 / 16 / 25 / 50 / 100 / 300 / 1000²; ja 極小…超巨大). XS is the new
  floor, L (50²) fills the old gap, XXL (300²) is an epic-but-finishable summit,
  and XXXL (1000², 1M cells) is the sandbox extreme. Scoreboard keys are
  geometry-based, so the rename leaves existing scores intact.
- **Save/restore camera view.** Resuming a saved game returns to where you were
  looking — `GameSnapshot` persists the camera centre (normalized) + zoom,
  re-clamped to the current viewport so it restores sensibly across window/device.
- **Carousel board-config picker.** The New Game difficulty and size rows are now
  a horizontal "drum" of cards (the segmented control truncated once a row had
  many or long options — Size's 7 tiers, "Intermediate"). A `detail · tagline`
  line under the pick shows the board facts plus a short flavour line, and the
  difficulty cards carry the rank insignia. On iOS the selected card centres with
  edge-clamped scrolling; on macOS cards lay out statically when they fit, and a
  click moves keyboard focus to that row.
- **Cumulative career stats.** Per-device, conflict-free running totals (games
  played, tiles opened, flags placed, mines hit, mines disarmed, playtime) shown
  in the scoreboard — no win/loss ratio. Built on a grow-only `DeviceCounter`,
  ready for the planned cross-device sync.
- **Mouse + keyboard zoom (macOS).** ⌘-scroll and ⌘+/⌘− zoom the board; ⌘0 opens
  the board overview.

### Changed

- **Huge boards are responsive.** Reveal/mine-placement compute off the main
  thread (the board never freezes; a debounced overlay gates input); mines are
  pre-armed off-thread on New Game so the first tap is instant; placement and
  end-game effects scale with the mine count, not the cell count; the minimap
  overview renders off the main thread; autosave is debounced + written on a
  background actor; `Cell` is bit-packed to one byte. Mine-hit shows the burst
  tile instantly; Esc closes the fullscreen overview.
- Build number is shared across iOS + macOS (one value, bumped together).
- The game logic and view model moved into the pure `DonpaCore` target, and the
  `DonpaCore`/`DonpaKit` sources are grouped into domain folders.

### Fixed

- The in-game clear-% and the loss screen's "best %" now floor (matching the
  scoreboard) instead of rounding up; flags survive a loss; correctly-flagged
  ("disarmed") mines no longer detonate in the loss shockwave.

### Tooling

- `Scripts/bump-build.sh` bumps the shared build number (+ optional PR), and
  `Scripts/distribute.sh` archives → exports → uploads to App Store Connect via an
  ASC API key (credentials kept outside the repo).

## [0.1.0] - 2026-06-27

First release — classic Minesweeper on iOS and macOS (TestFlight pre-release).

### Added

- Classic Minesweeper game logic with first-click safety, flood-fill reveal,
  flagging, chording, and win/lose detection.
- Two board modes: **Classic** (the original Beginner / Intermediate / Expert
  presets) and **Modern** — a Difficulty (Easy / Normal / Hard / Brutal / Insane
  mine-density) × Size (Small 9×9 / Medium 16×16 / Large 25×25) grid, chosen in
  the New Game popup and persisted between launches.
- A logical Minesweeper solver (single-constraint deduction) plus a dev-only
  `TierAnalysis` tool (`swift run TierAnalysis`) used to pick the Modern
  difficulty tiers from measured guess-dependence.
- `Topology` and `CellLayout` seams that isolate all future "epic" variation
  (wrapped/torus boards already pass a full-game test with unchanged logic).
- SpriteKit board renderer (`SKScene` + camera) hosted in SwiftUI, with
  pan and zoom.
- iOS and macOS app targets (XcodeGen-generated project).
- A board-side **dig / flag** input-mode toggle (a single-tap segmented pair, so
  flags can be placed without risk of an accidental reveal). A long-press (or
  macOS Control-click) performs the opposite primary action; tapping a revealed
  number always chords. Unopened tiles carry a faint manga screentone keyed to
  the mode (dots for dig, hatch for flag).
- Local per-config stats (`UserDefaults`), shown from the 🏆 button in Classic
  and Modern sections: best time plus games cleared for each board. Beating a
  best time opens the scoreboard. Stats are keyed by a versioned, geometry-
  bearing key (`v1|modern|sq|bounded|16x16|m41`) that names future shape/edges
  axes with defaults — so adding wrapped/hex boards or re-tuning tiers later
  creates new entries rather than corrupting old scores (no migration).
- macOS: a mode-aware board cursor — a pointing hand to dig, a flag to flag (a
  plain arrow otherwise); holding Control shows the other mode's cursor, since
  Control-click does the opposite action.
- App icon: a procedural detonating mine in a halftone comic burst, generated by
  `Scripts/make-icon.swift` (pure CoreGraphics; `--mono` renders a B&W variant,
  `--launch` the launch image). The same flat burst-mine marks the hit cell on a
  loss in-game.
- iOS launch screen (`UILaunchScreen`: the mono burst-mine on a charcoal ground)
  plus a brief matching in-app splash that fades into the title.
- Manga theme: comic end-of-game result panels (win / loss / new-record) and a
  "squad resting" pause panel over the board, an interactive manga title screen,
  and procedural manga chrome glyphs (`MangaIcon`) — a war-medal High Scores
  button, a Quonset-hut Home, a swallowtail flag, a pause/play toggle, and an
  army boot-print "dig" glyph. The framed panels are keyed assets built by
  `Scripts/make-panels.swift` (transparent margin + thin white "page" outline);
  the title is a full-bleed poster.
- Modern difficulty shown as ascending **military rank insignia** (chevron
  stripes → star → star-in-laurel) instead of text, so the five tiers stay
  compact and language-independent — in the New Game picker, the in-game config
  badge, and the scoreboard.
- Pause + resume: a pause control (and Esc on macOS) freezes the clock and blurs
  the board behind the pause panel; tapping the panel or the play toggle resumes.
  The timer is segmented (`accumulatedCentiseconds` + `runningSince`).
- Save & restore: an in-progress game is autosaved (atomic, crash-safe) and, on
  next launch, offered to Resume or Discard. The save clears on finish / new game
  / returning home.
- The scoreboard highlights the row whose record was just set, until the next
  game ends.
- Local-only UI tests (XCUITest, `Tests/UITests/`, run via `make uitest`) covering
  the title → New Game → game, sheet, and pause/resume flows. Not run by CI.
- Light/dark/system appearance, chosen from a ⚙️ settings sheet and saved
  between launches. The board and chrome share one palette resolved from a
  single effective scheme.
- macOS: pan a zoomed-in board by click-drag (with a small threshold so clicks
  aren't mistaken for drags) or two-finger trackpad scroll.
- Win/loss feedback: the board animates on game end (the hit mine detonates with
  a staggered mine wave and a brief shake on loss; a green ripple on win), the
  restart button pops, iOS plays a success/error haptic, and a small banner at
  the bottom shows the result (with the finishing time on a win). Respects
  Reduce Motion.
- Precise timing: play time is tracked from the wall clock and best times are
  recorded and shown as `m:ss.t` (tenths, uncapped) in the scoreboard and
  banner. The top status strip keeps the classic 3-digit whole-second LED (capped
  at 999 for display). A loss on the last cell shows "N tiles left" rather than a
  misleading "100%" (the scoreboard floors the cleared %, so only a true clear
  reads 100%).
- An **About** screen (app name, version, credits), opened from the title
  screen's ⓘ button and, on macOS, the app menu.
- Keyboard shortcuts: Space toggles mode (handled in the scene so it fires
  reliably), plus macOS menu commands ⌘N (new game), ⌘F (toggle mode),
  ⌘1/2/3 (classic presets).
- GitHub Actions CI: SwiftLint + swift-format checks, logic tests (with
  coverage), plus iOS and macOS builds.
- SwiftLint (`.swiftlint.yml`) and swift-format (`.swift-format`) configuration.

- The title screen doubles as the home hub: tapping the manga art opens the New
  Game popup; the 🏆 High Scores, ⚙️ Settings, and ⓘ About buttons sit on the
  art's corner. Return to it any time via the in-game Home action or ⌘T (macOS).
- Navigation: all game configuration lives in one **New Game popup** (Mode, then
  Difficulty + Size for Modern), opened from the title art, the status-bar config
  badge, the result screen, or ⌘N; keyboard-drivable on macOS (arrows choose,
  Return starts, Esc closes). The result panel dims the board only, leaving the
  control strip live, so it carries no buttons. Settings/High Scores are on the
  macOS menus (`⌘,` / `⇧⌘S`) and the title hub.
- Sheets (Settings, High Scores, About): on iOS, a `NavigationStack` with a Done
  nav-bar item and a fit-content detent; on macOS, inline with a bottom Done.

### Project decisions

- Minimum platforms: **iOS 16** and **macOS 14 (Sonoma)** — two native targets,
  no Mac Catalyst.
- Panning is constrained to the board edges; when the whole board fits on screen,
  panning is disabled so a stray drag can't move it.

### Fixed

- The board follows system light/dark changes on iOS/iPadOS (a
  System → Dark → System toggle could leave the grid stuck dark).
- Restoring a saved game ignores out-of-bounds coordinates and recomputes the
  cleared-cell count from the board, so a corrupt or tampered save can't produce a
  broken or unwinnable game.

[Unreleased]: https://github.com/vlumi/donpa/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/vlumi/donpa/releases/tag/v0.1.0
