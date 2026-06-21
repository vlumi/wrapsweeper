# Roadmap

How Wrapsweeper gets from "classic Minesweeper" to the full "epic" vision at
**v1.0**. The architecture (two seams — `Topology` for logical neighbours,
`CellLayout` for pixel geometry) means most features land as a new conformer
plus UI, without touching the game logic.

Versions are indicative, not contractual; scope may shift between minor
releases. The project is **currently unversioned** — the first cut is v0.1.0.

---

## v0.1.0 — Classic release (next)

Ship a polished classic Minesweeper on iOS and macOS.

- [x] Core logic: first-click safety, flood-fill, flagging, chording, win/lose
- [x] Classic presets (Beginner / Intermediate / Expert)
- [x] Modern mode: Size × mine-density grid (curated, two fixed-set axes) —
      brought forward from v0.2
- [x] Logical solver + tier-analysis tool (chose the Modern tiers from data)
- [x] 1.0-stable, geometry-keyed, versioned scoreboard format (no migrations)
- [x] SpriteKit board with pan/zoom, board-constrained panning
- [x] Reveal/Flag mode toggle + long-press alternate action; macOS mode cursor
- [x] Local scoreboard: best time + games-cleared count per board
- [x] iOS + macOS app targets, CI
- [x] App icon
- [x] Light / dark / system appearance (settings sheet, persisted)
- [x] Persisted board selection (mode + size/density/preset)
- [x] Win/loss feedback: board animation, restart pop, iOS haptics, bottom
      result banner with the finishing time (PRs #20–24)
- [x] Precise wall-clock timing; m:ss.t results, classic LED toolbar
- [x] macOS: Space restarts after a game ends
- [x] Reset input mode to Reveal on each new game (decided against persisting
      it — flag mode never makes sense at the start of a game)
- [ ] **Remaining for release:**
  - [ ] Launch screen
  - [x] Accessibility: chrome is VoiceOver-labelled (buttons, counters, pickers,
        sheets) and uses Dynamic-Type semantic fonts; the board announces a
        state summary. **Per-cell board VoiceOver deferred** — it needs a
        scalable cursor model (swiping 10k cells doesn't work on huge boards),
        so co-design it with the v0.3 huge-map navigation rather than build twice.
  - [ ] About view: version number + credits
  - [ ] Light-mode app icon variant (current icon is dark-tuned)
  - [x] Window sizing: macOS snaps to a snug fit per board on config change
        (Beginner→square, Expert→wide); cells cap their on-screen size and the
        board centers with padding on oversized/full-screen windows. Manual
        resize still works. **Revisit for v0.3 huge maps / v0.4 wrapping** —
        snap-to-fit assumes a board that fits a window, which huge/edgeless
        boards reject (they're meant to be panned, not framed whole).
  - [ ] Localization: Japanese + Finnish + English (Settings has a language row;
        also affects the App Store listing)
  - [ ] Tag v0.1.0, signed builds — note: any version string is fine for the
        App Store (no "must be 1.0"); the build number must increment per
        upload. Currently `MARKETING_VERSION = 0.1.0` (not marked pre-release;
        TestFlight is the channel for pre-release testing).

## v0.2.0 — Fairer boards & restraint

The curated Size × Density model already shipped in v0.1.0. What's left here
builds on the existing logical solver.

- [ ] "No-guess" board generation: reject layouts the solver can't finish
      without a guess (the `Solver` and `TierAnalysis` from v0.1.0 are the
      foundation — generation just resamples until solvable).
- [ ] Optional per-config "no-guess" toggle (esp. for the harder densities).
- [ ] Safe-reveal / question-mark flag cycle (classic third flag state).

## Session quality-of-life (planned)

Pause and resume — two related features that share a foundation: serializing
full game state and tracking elapsed time as accumulated segments rather than
`now − startDate`.

- [ ] **Pause**: stop the clock, hide/blur the board so it can't be studied
      while paused; resume continues the same game. Bind to **Esc** on macOS.
      Requires the timer to accumulate elapsed across pause/resume segments
      (not a single start date).
- [ ] **Persist & restore on quit**: save the in-progress game on
      background/quit and offer to resume it on next launch. Needs `Game` /
      `Board` / `Topology` to be `Codable` and the *exact* placed mine layout
      saved (mines are placed first-click-safe mid-game and must not be
      re-randomized). Store the config + accumulated elapsed time too.

## v0.3.0 — Big boards

The "huge zoomable maps" pillar. Mostly a rendering/perf effort behind the
existing `BoardScene` seam.

- [ ] Viewport culling in `BoardScene.rebuild` (only build visible cells)
- [ ] Incremental re-render (update changed cells instead of full rebuild)
- [ ] Large presets (e.g. 50×50, 100×100) + smooth pan/zoom at scale
- [ ] Minimap / overview for navigation
- [ ] Rethink macOS window snap-to-fit (from v0.1): huge boards don't "fit" a
      window, so the snug-fit / cell-cap / fit-zoom model needs a pan-first
      alternative here (and again for edgeless wrapped boards in v0.4).

## v0.4.0 — Wrapped (torus) boards

The "wrapped edges" pillar. Logic already proven — a `WrappedSquareTopology`
test wins a full game with unchanged rules. This release makes it playable.

- [ ] Mode selector exposing bounded vs wrapped
- [ ] Rendering that conveys wrap-around (edge ghosting / seamless scroll, or
      explicit "this edge connects to that one" affordance)
- [ ] Pan behaviour for a seamless/torus surface (no hard edges to clamp to)
- [ ] Scoreboards keyed by topology

## v0.5.0 — Hex grids

The "hex grids" pillar — exercises the second seam.

- [ ] `HexTopology` (6-neighbour adjacency, bounded + wrapped)
- [ ] `HexLayout` (axial/offset coords → pixels + hit-testing)
- [ ] Hex-aware tile/number rendering
- [ ] Verify game logic is genuinely unchanged (same test pattern as torus)

## v1.0.0 — The epic set

Everything composes: square **or** hex, bounded **or** wrapped, any size.

- [ ] Full board-type matrix selectable and combinable
- [ ] Unified game configuration + scoreboards across all variants
- [ ] Settings, theming, polish pass across all modes
- [ ] Documentation + screenshots for each mode
- [ ] Performance validated on the largest supported boards
- [ ] Release builds for iOS + macOS

## Publishing & distribution (planned — gated on a paid account)

How the apps reach the stores once a paid Apple Developer account exists:

- **iOS is one universal app**: a single App Store Connect record + binary runs
  on **both iPhone and iPad** and appears on both stores automatically (shared
  page, reviews, price). No extra work — it's the default device family.
- **macOS is a separate native app**: our Mac target is a distinct native build
  (not Mac Catalyst), so it's its **own** App Store Connect record + binary +
  review. The Mac and iOS stores are browsed independently.
- **Bundle IDs likely need to diverge**: iOS and the separate native Mac app
  generally need **distinct bundle IDs** (both currently share
  `fi.misaki.wrapsweeper`). Pick the Mac ID (e.g. `fi.misaki.wrapsweeper.mac`)
  and split it in `project.yml` **before** registering IDs with Apple — changing
  it after registration is painful. (Unifying them into a single "universal
  purchase" is a deliberate Catalyst/SwiftUI-app setup, not automatic.)
- **App age rating**: 4+ / PEGI 3 (set via the App Store Connect questionnaire;
  nothing in the feature set pushes it higher).

**Decision: stay with two native targets (no Mac Catalyst).** Catalyst would
simplify publishing (one universal-purchase record) but at the cost of the
native Mac UX already built on AppKit — the mode cursor (`NSCursor`),
click-vs-drag and right-click (`NSEvent`), two-finger `scrollWheel` pan,
menu-bar commands, and `keyDown`. Under Catalyst the Mac app is the iOS app in
UIKit-on-Mac, where exactly those interactions are weakest. Since that native
cost is already paid and gives the better result, the small one-time publishing
overhead (a second submission + distinct bundle ID) is the right trade.

## Game Center & achievements (planned — gated on a paid account)

Achievements (and possibly leaderboards) via Game Center. Mostly an
event-plumbing job, but with real prerequisites and some permanence to design
around. Targeted once a **paid Apple Developer account** exists (the user is
planning to go paid; Game Center can't be provisioned under a free personal ID).

**Prerequisites (the real gate, not the code):**

- Paid Apple Developer account; app registered in **App Store Connect** with the
  **Game Center** capability enabled.
- Each achievement defined in App Store Connect (ID, title, description, points,
  hidden/visible, icon). Achievement **IDs are permanent once shipped** — like
  the scoreboard keys, you can add but not cleanly rename/remove. Design the ID
  scheme up front (e.g. `clear.modern.large.insane`, `streak.10`, `time.sub60`).

**Design — keep it decoupled:**

- Add an **internal achievement layer** the game emits to (an `AchievementEvent`
  on each win carrying the `GameConfig` + time + streak), with a local store and
  in-app display. Game Center becomes just *one backend* behind that layer.
- This means achievements can be designed, tracked, and shown **offline now**,
  and GameKit bolts on later as a thin reporter — no rework. (Same
  forward-compatible instinct as `GameConfig.storageKey`.)
- Note this crosses a line the app hasn't yet: **online + account-bound**. The
  GC auth flow can be declined/fail — must degrade gracefully to the local layer.

**Achievement design principles** (decide the actual list when building — IDs are
permanent, so design carefully). Avoid filler: plain "clear each size/difficulty"
is *inevitable, not earned* — attrition, no skill or surprise. Every achievement
should reward one of:

- **Skill / mastery** — speed thresholds (sub-N seconds), no-flag wins (flag
  count stayed 0), efficiency (few clicks), conquering the near-unsolvable Insane
  tier, or boards the solver rated unsolvable-without-guessing.
- **Streaks / tension** — N wins in a row (a loss resets); rewards nerve, far
  better than "total wins" grind milestones.
- **Hidden / playful** — quirky surprises players stumble into and screenshot:
  win in under 3 clicks, oddly-specific times (the "13-second cursed clear"), a
  flag-everything win, losing on the *second* click (a wink — the first is safe).
- **Identity / epic-tied** — feats unique to Wrapsweeper's variants once they
  ship: first torus clear, hex Insane, "went around the world" (a wrap exploit).
  Generic Minesweeper can't offer these — the strongest long-term hook.

Lean toward a curated set where each entry is interesting; a couple of gentle
starters (first clear) are fine as an on-ramp, but the bulk should be earned.

**Steps when ready:** internal achievement layer + local UI → GameKit auth on
launch → report progress on events → GC achievements UI → define achievements in
App Store Connect.

---

## Creative identity & theme (exploring — not committed)

Direction under discussion (brainstorm; nothing locked):

- **Theme**: a cheeky, nostalgic, manga-flavoured take. The signature beat is a
  **comic-book panel** at the end of a game — a dramatic, cheesy *manga* panel
  (speed-lines, screentone, kana SFX, a chibi character mid-step) on **loss**,
  and a smaller triumphant panel on **win**. The melodrama is the joke; it
  evolves the existing detonation/banner. No persistent story required ("stories
  might be too much") — the comic *style* carries the flavour.
  - **Panel size is responsive / try-it-out**: likely full-screen-ish on phone,
    a non-blocking overlay on Mac (must not break the snappy Space-to-restart).
- **Sounds** (open): usually a mute-play genre, but a melodramatic manga
  "ドーン!" sting could fit the panel gag specifically. Needs a mute toggle.
- **Name** (time-sensitive — do before registering bundle IDs with Apple):
  reconsidering "Wrapsweeper". Maker is a **Finn in Japan**; wants **Japanese
  localization**; name should read to both JP and EN (not pure-English, not
  pure-Japanese). Candidates collected in `.local/NAME-OPTIONS.md` (gitignored);
  current lead family is **Donpan/Donpa** (manga boom). Getting JP-native
  (teen) feedback before deciding. The rename is one sweep: repo + bundle IDs +
  `Wrapsweeper*` package/type names + doc URLs.

## Distribution & extras (later)

- [ ] **Static home page** (marketing/landing site for the app).
- [ ] **TestFlight** beta distribution (iOS + Mac) — comes with the paid
      account; the channel for pre-release testing.
- [ ] **watchOS version?** — a big maybe; minesweeper on a tiny screen is its
      own design problem. Parked.
- [ ] **Tip jar?** — see the monetization note below; would be a *deliberate*
      exception to the no-monetization stance, not ads/IAP-for-content.

## Design principles

- **No anti-cheat, by design.** Scores are local and user-editable (low
  security, by choice). If Game Center leaderboards land later, lean on GC's
  own server-side validation rather than building anti-cheat here.

## Deliberately out of scope

Per project conventions: **no ads, no microtransactions, no pay-to-win**; no
third-party dependencies; the older Intel Mac is not targeted. Online
multiplayer and cloud-synced scores are not planned for v1.0. (A **tip jar** —
optional, content-neutral support — is the one monetization form under
consideration; see Distribution & extras.)
