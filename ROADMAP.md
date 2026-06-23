# Roadmap

How Donpa gets from "classic Minesweeper" to the full "epic" vision at
**v1.0**. The architecture (two seams — `Topology` for logical neighbours,
`CellLayout` for pixel geometry) means most features land as a new conformer
plus UI, without touching the game logic.

Versions are indicative, not contractual; scope may shift between minor
releases (the numbers name the **pillars**, so there are gaps — e.g. the
former v0.2 "fairer boards" became un-versioned backlog items). The project is
**currently unversioned** — the first cut is v0.1.0.

---

## v0.1.0 — Classic release (next)

**Shipped** (see [CHANGELOG.md](CHANGELOG.md) for the detail, git for the how):
classic + Modern (Size × density) modes, the logical solver + tier-analysis
tool, geometry-keyed versioned scoreboard, SpriteKit board with pan/zoom,
reveal/flag toggle + macOS mode cursor, light/dark/system theming, the manga
title + result screens and procedural app icon + launch screen, the
title-as-home-hub navigation (New Game popup, board-aware control strip,
handedness), pause + crash-safe save/restore, progress-% scoring, About,
EN/JA/FI localization, accessibility labels, and CI. Also done as pre-release
groundwork: local UI tests, an `onChangeCompat` shim, save-restore hardening,
and a clean leak/retain audit.

Carry-over notes for later milestones:

- **Per-cell board VoiceOver deferred** — needs a scalable cursor model (swiping
  10k cells doesn't work on huge boards); co-design with v0.3 navigation.
- **Window grow-to-fit** assumes a board that fits a window — revisit for v0.3
  huge maps / v0.4 edgeless boards (panned, not framed).
- **JA/FI strings are my drafts** (`needs_review`) — revisit on native/test
  feedback; not blocking 0.1.

**Remaining for release:**

- [ ] Tag v0.1.0, signed builds (gated on the paid Apple account). Any version
      string is fine for the App Store; the build number must increment per
      upload. `MARKETING_VERSION = 0.1.0`; TestFlight is the pre-release channel.

## Backlog (unversioned)

Polish and smaller features that can land in any release — not milestone gates.
The numbered milestones below are the real pillars (scale, then board variants).

**Gameplay fairness** (builds on the v0.1 logical solver):

- [ ] "No-guess" board generation: reject layouts the solver can't finish
      without a guess (the `Solver` and `TierAnalysis` are the foundation —
      generation just resamples until solvable).
- [ ] Optional per-config "no-guess" toggle (esp. for the harder densities).
- [ ] Safe-reveal / question-mark flag cycle (classic third flag state).

**Navigation / UX:**

- [ ] **macOS `⌘1/2/3`** (classic presets) jump straight into a Classic game,
      jarringly switching mode mid-play. Rethink: pre-select in the New Game
      popup instead of starting immediately? Or be Modern-aware?

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
      (Win/mine/flag counts are *already* O(1) incremental counters, so this is
      purely the storage swap.)

**Rendering (Kit):**

- [ ] Viewport culling in `BoardScene.rebuild` — only build nodes for cells in
      the camera rect (+ margin); refresh the visible set on pan/zoom. Today it
      makes one `SKShapeNode` (+ `SKLabelNode`) per cell → millions of nodes at
      scale.
- [ ] Incremental re-render (update changed cells instead of full `rebuild()`,
      which currently re-runs on every palette push / tick).
- [ ] Node reuse / pooling as the viewport moves; consider `SKTileMapNode` or a
      drawn texture instead of per-cell `SKShapeNode` (shape nodes are pricey).
- [ ] Re-profile memory + teardown with Instruments at 500²–1000² (Allocations +
      Leaks). The pre-v0.3 retain audit was clean at current scale (see
      ARCHITECTURE.md); the open question is behaviour under the flat-storage +
      culling rework above.

**Navigation / window:**

- [ ] Large presets (e.g. 50×50, 100×100, … up to 1000²) + smooth pan/zoom.
      Modern sizes use clothing-size labels (S/M/L; 小/中/大 in JA), so bigger
      boards extend naturally to XL/XXL/XXXL (特大/超特大…) — add `BoardSize`
      cases + catalog entries; the rawValue keys the scoreboard, label is display.
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
- [ ] **UI smoke tests on CI?** A local XCUITest suite already exists (`make
      uitest`, `Tests/UITests/`, shipped in v0.1) but is deliberately *not* run
      by CI — it needs a job that builds the `.xcodeproj` and boots a simulator
      (today CI runs SPM `swift test` + `xcodebuild build` only), which is slow
      and flaky mid-iteration. Decide near 1.0 whether the regression value is
      worth wiring it into CI.

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
- [ ] **AI-generated disclosure (open question).** Decide how/whether to mark
      the app as AI-assisted. The App Store has **no dedicated "AI-generated"
      flag** today; relevant levers are the description text, and — for any
      AI-generated *art* — whether to credit/label it. Code being AI-written is
      not something Apple asks about. Action: revisit near submission; likely a
      short note in the description + the repo README rather than a store field.
      (Tie in with the art-licensing question below if art ends up AI-made.)
- [ ] **Art assets — repo/licensing strategy (open question).** When better
      graphics arrive, decide where they live and under what terms. Options:
      (a) **same repo, split license** — code stays open (current license),
      art under a separate, more-restrictive license file (e.g. CC-BY-NC or
      all-rights-reserved) with a clear `ASSETS-LICENSE` and per-folder note;
      (b) **separate private repo** for source art, with only export-ready
      assets vendored into this repo (keeps WIP/source files private);
      (c) **git submodule** referencing a private art repo. Leaning (a) for
      simplicity unless the source files are large/sensitive, then (b). Decide
      before importing non-AI or commissioned art (provenance matters for the
      AI-disclosure question above).

(The **two-native-targets, no-Catalyst** decision and the distinct Mac bundle id
that follows from it are recorded in [ARCHITECTURE.md](ARCHITECTURE.md).)

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
interactive title screen, a manga-style app icon, and **procedural manga chrome
glyphs** (`MangaIcon`): a war-medal High Scores button, a Quonset-hut "home"
barracks, a swallowtail flag, a pause/play toggle, and an army boot-print
reveal/"dig" glyph (a CC0 silhouette baked to a tintable template via
`Scripts/make-boot.swift`). The mode toggle is a single-tap dig|flag segmented
pair in distinct mode colours; the status bar carries a tappable config "change
game" badge (replacing the separate New-Game button, mirroring the title splash).
The **board's unopened tiles carry a faint manga screentone keyed to the input
mode** — Ben-Day dots for dig, diagonal hatch for flag (opposite per-tile
vignettes), the same patterns echoed on the mode-toggle segments. The cue is the
*pattern*, not colour, so it's colour-blind safe; the ink is brightness-balanced
per appearance so a screentoned tile averages back to the bare-tile gray. The
manga flavour lives in these; the **board grid itself stays the classic look** (a
tried full "inked paper" board theme wasn't distinct enough from classic to
justify itself, so it was dropped — revisit only with a genuinely different
treatment: heavier ink, custom number styling).

**Ideas to revisit:**

- **More screentone accents** — the dot/hatch screentone vocabulary could extend
  to other UI (panels, buttons, backgrounds). Tempting, but easy to overdo: keep
  it sparing and meaningful (it currently *means* "unopened / this mode") rather
  than decorative everywhere, or the UI gets noisy.
- **Pause panel art** — a "squad taking a rest" manga frame on the pause overlay
  (same panel slot as win/loss). The current blurred "Paused" overlay is the
  placeholder; pairs with the next art batch (DALL·E → `.local` → `Panels.xcassets`).
- **Art sources** — current panels/title/icon are DALL·E (commercial-use OK via
  OpenAI TOS on a personal account; verify before ship). If iterating: keep the
  *icon* a single bold focal subject, no baked title text, readable at 64px.
  Alternatives to DALL·E worth a look when commissioning final art: a real manga
  artist (Fiverr/commission for a consistent character sheet + assets), or other
  gen tools — but a human pass to replace AI kana with proper typeset lettering
  is recommended for production regardless.

Still open:

- **Sounds** — usually a mute-play genre, but a melodramatic manga "ドーン!"
  sting could fit the result-panel gag specifically. Would need a mute toggle.
- **Name native-check** — **Donpa Squad / ドンパ隊** is settled (repo + types +
  docs renamed), but worth a JP-native gut-check **before registering bundle IDs
  with Apple** (store name + bundle ID are painful to change post-registration).

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
