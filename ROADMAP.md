# Roadmap

How Donpa gets from "classic Minesweeper" to the full "epic" vision at
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
      (a custom crosshair/flag, shown only while a game is in progress)
- [x] Local scoreboard: best time + games-cleared count per board
- [x] iOS + macOS app targets, CI
- [x] App icon (manga-style; PR #33 — placeholder pending a final title-free,
      single-focal-subject icon, see "Creative identity & theme")
- [x] Light / dark / system appearance (settings sheet, persisted)
- [x] Persisted board selection (mode + size/density/preset)
- [x] Win/loss feedback: board animation, restart pop, iOS haptics. The early
      bottom result banner (PRs #20–24) was **replaced** by the manga
      end-of-game result screen (PR #33) — see "Start and end of a game".
- [x] Manga title screen on launch + comic end-of-game result screen
      (win/loss/new-record), with Continue / Title (Esc) and Space/⌘R restart
      (PR #33)
- [x] Precise wall-clock timing; m:ss.t results, classic LED toolbar
- [x] macOS: Space restarts after a game ends
- [x] Reset input mode to Reveal on each new game (decided against persisting
      it — flag mode never makes sense at the start of a game)
- [ ] **Remaining for release:**
  - [x] Launch / title screen (the manga title card on launch, PR #33 — covers
        this; a separate instant-flash `UILaunchScreen` is still the empty `{}`
        if a pre-title splash is ever wanted)
  - [x] Accessibility: chrome is VoiceOver-labelled (buttons, counters, pickers,
        sheets) and uses Dynamic-Type semantic fonts; the board announces a
        state summary. **Per-cell board VoiceOver deferred** — it needs a
        scalable cursor model (swiping 10k cells doesn't work on huge boards),
        so co-design it with the v0.3 huge-map navigation rather than build twice.
  - [x] About view: version + credits (PR #36) — shared view; macOS app menu +
        iOS Settings row; bundle version, MIT/copyright, GitHub link.
  - [ ] Final app icon: a title-free, single-focal-subject manga icon to
        replace the PR #33 placeholder (see "Creative identity & theme"). The
        light/dark question is moot now the icon is B/W manga on a flat field.
  - [x] Window sizing: macOS grows the window to fit a board but never shrinks a
        maximized/hand-sized one (PR #33); per-board cell size targets a
        consistent footprint, and the on-screen cell cap is relative to the
        viewport so small boards fill big windows without blowing up. **Revisit
        for v0.3 huge maps / v0.4 wrapping** — this still assumes a board that
        fits a window, which huge/edgeless boards reject (panned, not framed).
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
- [x] **Progress-% scoring** — *shipped early in v0.1.0 (PR #35).* Best-% of
      safe tiles cleared per board (loss consolation for the brutal/insane
      tiers); `Game.revealedSafeCount` made win detection O(1); backward-compatible
      `bestLossProgress` scoreboard field; shown in the scoreboard + loss panel.

## Navigation restructure — title as home / selection off the game screen (planned)

Today the title card dismisses straight into the game, and the board config
pickers (mode / size / density) live on the game screen — which eats space,
especially on phone. Direction:

- **Title becomes a home/menu hub** that holds board selection. Flow:
  Title/Home → (pick mode + size/difficulty) → Game. The game screen sheds the
  picker bar and shows just the board + minimal chrome.
- **Split "Restart" from "New Game"**: *Restart* replays the current board
  (today's restart button / Space / Cmd-R); *New Game* returns to the selection
  screen pre-filled with the current selections, then starts fresh. *Return to
  title* already ships on the end-of-game result screen (Title button / Esc) and
  the macOS menu (Cmd-T).
- Groundwork already in place: `Navigator` (DonpaKit) holds `showingTitle` and is
  injected into `GameView` so any host can drive navigation; the title screen is
  an always-mounted overlay toggled by it.

## Session quality-of-life (planned — pause/persist wanted sooner for mobile)

Pause and resume — two related features that share a foundation: serializing
full game state and tracking elapsed time as accumulated segments rather than
`now − startDate`. **Prioritised up:** on mobile you may need to stop suddenly
and resume later, and a backgrounded app can be killed by the OS — so persistence
isn't just nice-to-have.

- [ ] **Segmented timer** (prerequisite for both): replace the single `startDate`
      in `GameViewModel` with `accumulatedCentiseconds` + an optional
      `runningSince`. Pause folds the running span into the accumulated total;
      resume restarts the span. Persists cleanly (store the number, never a
      wall-clock delta).
- [ ] **Pause**: stop the clock, hide/blur the board so it can't be studied
      while paused; resume continues the same game. Bind to **Esc** on macOS
      (distinct from Esc = "return to title" on the *result* screen — pause is
      mid-play).
- [ ] **Persist & restore on quit**: save the in-progress game on
      background/quit (iOS `scenePhase`) and offer to resume it on next launch.
      Needs `Game` / `Board` / `Cell` / `Coord` `Codable`, plus a **tagged
      encoding for the `any Topology` existential** (store kind + params, rebuild
      via a factory — don't encode the protocol). Save the *exact* placed mine
      layout (`Set<Coord>` + `minesPlaced`); mines are first-click-safe and must
      not be re-randomized. Store config + accumulated elapsed too. Use a
      **compact format** (mines/revealed/flagged as coord sets or a bitset, not
      the full `[Coord: Cell]` dict) — a 1000×1000 save is large otherwise; this
      dovetails with the v0.3 data-model rework below.

## v0.3.0 — Big boards

The "huge zoomable maps" pillar — targeting **500×500 (250k) up to 1000×1000
(1M) cells**. Both a data-model and a rendering/perf effort; profile with
Instruments (Allocations + Leaks) at those sizes throughout.

**Data model (Core):**

- [ ] Replace `Board`'s `[Coord: Cell]` storage — a dict keyed by a struct is
      ~100MB+ and slow at 1M entries. For bounded rectangular topologies use a
      **flat `[Cell]` of size w·h** indexed `y·w + x`; pack `Cell` tight (state
      2 bits + mine 1 + adjacency 0–8 in 4 bits ≈ 1 byte/cell → 1000×1000 ≈ 1MB).
      Keep the `Topology` seam (dict path can stay for sparse/odd topologies).
- [ ] Kill the O(n) full-board scans: `Game.checkWin` (scans every cell per
      reveal), `Board.mineCount`/`flagCount` (reduce over all cells per call) →
      **incremental counters** (`revealedSafeCount`, flag count). Win is then an
      O(1) check. (The progress-% feature introduces `revealedSafeCount` first.)

**Rendering (Kit):**

- [ ] Viewport culling in `BoardScene.rebuild` — only build nodes for cells in
      the camera rect (+ margin); refresh the visible set on pan/zoom. Today it
      makes one `SKShapeNode` (+ `SKLabelNode`) per cell → millions of nodes at
      scale.
- [ ] Incremental re-render (update changed cells instead of full `rebuild()`,
      which currently re-runs on every palette push / tick).
- [ ] Node reuse / pooling as the viewport moves; consider `SKTileMapNode` or a
      drawn texture instead of per-cell `SKShapeNode` (shape nodes are pricey).
- [ ] Leak audit: `BoardScene` ↔ `GameViewModel` retain, long-lived scene
      teardown on config change, effects-node cleanup.

**Navigation / window:**

- [ ] Large presets (e.g. 50×50, 100×100, … up to 1000²) + smooth pan/zoom.
- [ ] Minimap / overview for navigation.
- [ ] Rethink macOS window grow-to-fit (from v0.1): huge boards don't "fit" a
      window, so the grow-to-fit / cell-cap / fit-zoom model needs a pan-first
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
- [ ] **UI smoke tests (XCUITest)** — a small happy-path suite (launch →
      start → board, win → result panel, About opens, restart) as a
      pre-release regression guard. Deferred from v0.1: needs a new CI job that
      builds the `.xcodeproj` and boots a simulator (today CI only runs the SPM
      `swift test`), plus accessibility IDs on key elements; not worth the
      flakiness/maintenance mid-iteration. Logic is already unit-tested at the
      `Game`/`Scoreboard`/`MangaPanelView.Kind` seams; visual issues are caught
      by running the app. Revisit when the app is feature-stable near 1.0.

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
  `fi.misaki.donpa`). Pick the Mac ID (e.g. `fi.misaki.donpa.mac`)
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
around. Targeted once a **paid Apple Developer account** exists (Game Center
can't be provisioned under a free personal ID).

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
- **Identity / epic-tied** — feats unique to Donpa's variants once they
  ship: first torus clear, hex Insane, "went around the world" (a wrap exploit).
  Generic Minesweeper can't offer these — the strongest long-term hook.

Lean toward a curated set where each entry is interesting; a couple of gentle
starters (first clear) are fine as an on-ramp, but the bulk should be earned.

**Steps when ready:** internal achievement layer + local UI → GameKit auth on
launch → report progress on events → GC achievements UI → define achievements in
App Store Connect.

---

## Creative identity & theme

**Shipped:** manga end-of-game result screen (win/loss/new-record panels), the
interactive title screen, and a manga-style app icon. The manga flavour lives in
these; the **board itself stays the classic look** (a tried "inked paper" board
theme wasn't distinct enough from classic to justify itself, so it was dropped —
revisit only with a genuinely different treatment: real screentone texture,
heavier ink, custom number styling).

**Ideas to revisit:**

- **Manga-style toolbar icons** — the status-bar chrome (trophy, gear, mode
  toggle, new-game) still uses plain SF Symbols; matching them to the manga
  style would tie the in-game look to the panels/title.
- **Art sources** — current panels/title/icon are DALL·E (commercial-use OK via
  OpenAI TOS on a personal account; verify before ship). If iterating: keep the
  *icon* a single bold focal subject, no baked title text, readable at 64px.
  Alternatives to DALL·E worth a look when commissioning final art: a real manga
  artist (Fiverr/commission for a consistent character sheet + assets), or other
  gen tools — but a human pass to replace AI kana with proper typeset lettering
  is recommended for production regardless.

Direction notes (earlier brainstorm; mostly realized above):

- **Theme**: a cheeky, nostalgic, manga-flavoured take. The signature beat is a
  **comic-book panel** at the end of a game — a dramatic, cheesy *manga* panel
  (speed-lines, screentone, kana SFX, a chibi character mid-step) on **loss**,
  and a smaller triumphant panel on **win**. The melodrama is the joke; it
  evolves the existing detonation/banner. No persistent story required ("stories
  might be too much") — the comic *style* carries the flavour.
  - **Panel size is responsive / try-it-out**: likely full-screen-ish on phone,
    a non-blocking overlay on Mac (must not break the snappy Space-to-restart).
  - **Build split — code vs art**: the panel *framing and FX* (speed-lines,
    halftone/screentone, kana SFX lettering, flash, border) are procedural —
    buildable in SpriteKit/CoreGraphics, no drawn assets, crisp at any size, no
    licensing concerns. The drawn part is the **panel image in a swappable asset
    slot**, so the framework can be built first with a placeholder.
  - **Style**: B/W manga with **screentone/halftone** (not flat outline) — it
    matches the theme, composites with the mono code FX, and **inverts/tints per
    light-dark mode** (full colour would fight the appearance theming). An
    optional win=green / loss=red accent can be applied *in code* over the mono
    art.
  - **Panel as one transparent PNG (incl. its border)**: the art is the complete
    bordered panel with **transparency outside the panel shape**. Drop it in as a
    single image — no code-drawn frame, no clip math. The **breakout flourish**
    (a fist / SFX poking past the border) is just drawn past the edge in the same
    image, opaque-over-transparent — free, no extra layer. Alpha is only the
    easy kind (outside a clear bordered shape), not a hair-level cut-out.
  - **Art source**: AI-generated panels for now (exported @1x/2x/3x). A
    commissioned artist could replace the same swappable slot later, no code
    change. **Verify commercial-use licensing of any AI art before shipping.**
- **Sounds** (open): usually a mute-play genre, but a melodramatic manga
  "ドーン!" sting could fit the panel gag specifically. Needs a mute toggle.
- **Name**: settled on **Donpa Squad / ドンパ隊** — the repo, `Donpa*`
  package/type names, and docs were renamed in PR #32 (reads to both JP and EN
  and fits the manga theme). Still worth a JP-native gut-check **before
  registering bundle IDs with Apple**, since the store name + bundle ID are
  painful to change after registration. Candidate history in
  `.local/NAME-OPTIONS.md` (gitignored).

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
