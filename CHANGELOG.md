# Changelog

All notable changes to Donpa are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Grouped by **marketing version** (a roadmap milestone), then by **build number**
within it — the version stays steady while the build climbs each TestFlight
upload (see [RELEASING.md](RELEASING.md)). Newest first.

Each version's top section, **Unreleased (next build)**, collects entries merged
to `main` but not yet in a TestFlight build; cutting a release renames it to that
build's heading and opens a fresh empty one. Keep that heading immediately
followed by its list items (no prose between), so the release script can promote
it with a one-line edit.

## [0.2.0] — Cross-device & big boards

**Cross-device sync & big boards** (see ROADMAP.md). Both pillars have landed;
cross-device sync awaits a real two-device verification pass.

### Unreleased (next build)

- **Toggle-side picker reads the right way.** The Left/Right control in Settings
  showed its options reversed (Right on the left); they're now in natural order.
- **iCloud sync row is honest when signed out.** The toggle no longer turns on
  when iCloud isn't available (it can't sync), and on iOS the status is plain
  guidance to sign in rather than a link that just opened the app's own settings.

### build 8

- **Scoreboard orientation.** The board you're playing gets a persistent "you are
  here" row band; opening the scoreboard mid-game scrolls that row into view (from
  the title it stays at the top). The result panel now shows the *improvement* —
  how much faster a new best ("−m:ss.t", or "first clear") and "+N%" on a
  better-than-before loss — instead of the final time (already on the timer). The
  just-improved value carries a small "↑" marker (a shape, not colour, so it's
  colour-blind safe and accent-independent).
- **Minimap is a navigator.** Tap or drag inside the corner minimap to move the
  camera there — the quick way around a board too big to see at once.
- **Resizable minimap.** Drag the caret hugging its corner to resize it freely, or
  tap the caret to snap between min and max; on macOS ⌘0 toggles the size. The
  chosen size persists across new game, restart, and resume. (Replaces the old
  full-screen board overview.)
- **Over-flagged numbers are flagged.** A revealed number with more flags around it
  than its value gets a faint ring — a guaranteed mistake, surfaced so you can fix
  the slip. It marks only the impossible number, not which flag is wrong, so it's a
  nudge, not a solver.
- **Huge boards stay smooth.** Fixed a runaway where a very large board (超特大)
  could peg the CPU and stall after opening tiles; reveals, flagging, and idle are
  all much lighter now, especially on macOS.

### build 7

- **Minimap appears immediately** on a board that only slightly exceeds the
  viewport (e.g. Modern S on an iPhone 14) — it no longer stayed hidden until a
  small pan.

### build 6

- **Resuming keeps the dig/flag input mode** — it no longer reset to dig on
  restore.
- **Wider pan margin on all edges** so edge tiles never sit flush to the window,
  minimap or not.
- The in-game clear-% and the loss screen's "best %" now floor (matching the
  scoreboard) instead of rounding up; flags survive a loss; correctly-flagged
  ("disarmed") mines no longer detonate in the loss shockwave.
- **Offline merged-stats cache** so combined cross-device totals survive going
  offline; a fix so a new record set on another device isn't double-counted.
- Carousel modal no longer overflows on small iPhones (edges fade instead).

### builds 4–5 (initial 0.2.0)

- **Cross-device scoreboard sync (iCloud).** High scores and career totals follow
  the player across their devices via iCloud Key-Value Storage. Opt-in (off by
  default), in a footer toggle on the stats sheet; silent and account-free
  otherwise, degrading to local-only when signed out. The merge is conflict-free —
  each device owns its slot; counters sum across devices and best times merge by
  min — so concurrent play on two devices Just Works. Turning sync off (or
  resetting) removes this device's contribution everywhere. In-progress games stay
  local.
- **Stats sheet, reworked.** The scoreboard is now a single "Service Record" sheet
  — "Tour of Duty" (career totals) beside "Commendations" (per-board high scores),
  two-column on a wide window — with the sync control in the footer. Lifetime
  totals use locale digit-grouping and localized time units.
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
  in the scoreboard — no win/loss ratio. Built on a grow-only `DeviceCounter` (the
  foundation the cross-device sync above builds on).
- **Mouse + keyboard zoom (macOS).** ⌘-scroll and ⌘+/⌘− zoom the board; ⌘0 opens
  the board overview.
- **Huge boards are responsive.** Reveal/mine-placement compute off the main
  thread (the board never freezes; a debounced overlay gates input); mines are
  pre-armed off-thread on New Game so the first tap is instant; placement and
  end-game effects scale with the mine count, not the cell count; the minimap
  overview renders off the main thread; autosave is debounced + written on a
  background actor; `Cell` is bit-packed to one byte. Mine-hit shows the burst
  tile instantly; Esc closes the fullscreen overview.

## [0.1.0] — TestFlight beta

First release — classic Minesweeper on iOS and macOS. TestFlight pre-release
only. iOS shipped builds 2–3; macOS build 1.

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

<!-- Releases are tagged per platform + build (ios/vX.Y.Z-N, mac/vX.Y.Z-N) — no
single plain vX.Y.Z tag — so each version links to its filtered list of GitHub
releases rather than one tag. -->

[0.2.0]: https://github.com/vlumi/donpa/releases?q=v0.2.0
[0.1.0]: https://github.com/vlumi/donpa/releases?q=v0.1.0
