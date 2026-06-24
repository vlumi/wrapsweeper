# Roadmap

How Donpa gets from "classic Minesweeper" to the full "epic" vision at
**v1.0**. The architecture (two seams — `Topology` for logical neighbours,
`CellLayout` for pixel geometry) means most features land as a new conformer
plus UI, without touching the game logic.

Versions are indicative, not contractual; scope may shift between minor
releases. Each minor groups **related** work into one meaty release rather than
giving every feature its own number (so v0.2.0 carries both cross-device sync
and big boards; v0.3.0 carries both board-topology variants). The former v0.2
"fairer boards" lives on as un-versioned backlog items. The project is
**currently unversioned** — the first cut is v0.1.0 (TestFlight pre-release; not
a public store release).

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
  10k cells doesn't work on huge boards); co-design with v0.2 big-board navigation.
- **Window grow-to-fit** assumes a board that fits a window — revisit for v0.2
  huge maps / v0.3 edgeless wrapped boards (panned, not framed).
- **JA/FI strings are my drafts** (`needs_review`) — revisit on native/test
  feedback; not blocking 0.1.

**Remaining for release:**

- [ ] Tag v0.1.0, signed builds (gated on the paid Apple account). Any version
      string is fine for the App Store; the build number must increment per
      upload. `MARKETING_VERSION = 0.1.0`; TestFlight is the pre-release channel.

## v0.2.0 — Cross-device & big boards

Two strands of "make the existing square game better and bigger" — grouped into
one milestone rather than a minor each. Cloud sync (below) is independent of the
big-board work and can land first.

### Cross-device scoreboard sync

Make a player's progress follow them across their Mac, iPhone, and iPad, keyed
by Apple ID — no accounts, no server, no UI.

- [ ] **iCloud scoreboard sync** via `NSUbiquitousKeyValueStore` (iCloud KVS) —
      right-sized for the small `Codable` scoreboard blob; CloudKit / Core Data
      sync would be overkill. **Silent auto-sync** (no toggle); degrades to
      local-only when not signed into iCloud (== today's behaviour).
  - **Merge is lossless and needs no conflict UI:** records are keyed
    independently by `GameConfig.storageKey`, and each `ScoreRecord` merges
    field-wise — `max(wins)`, `min(bestCentiseconds)`, `max(bestLossProgress)`
    (all nil-safe). Order-independent + idempotent, so any sync order converges.
  - **`wins` merges with `max`, not `sum`** — a deliberate choice: summing would
    double-count the same offline session across devices. `max` can under-count
    a genuine divergence, but inflating a "games cleared" stat is worse, and true
    dedup would need per-win IDs (not worth it). Document in code, not silently.
  - **Implementation seam is already clean:** `Scoreboard` funnels through one
    `load()`/`persist()` and is injectable. Plan: abstract the backing store
    behind a tiny protocol, dual-write to `UserDefaults` (fast local cache) AND
    KVS (cross-device truth), merge-on-read, and observe
    `didChangeExternallyNotification` so an open scoreboard updates live. The
    versioned `StatsFile` envelope (the per-entry-tolerant format) carries over
    as the wire format unchanged.
  - **Entitlement / signing** is the one careful part: add the iCloud +
    Key-Value Storage capability to BOTH app targets (regenerates the
    provisioning profile; automatic signing handles it). **iOS and macOS must
    share an explicit KVS identifier** — by default `fi.misaki.donpa` and
    `fi.misaki.donpa.mac` wouldn't see each other's scores, which would defeat
    the Mac-sharing goal. No App Store Connect metadata change; PRIVACY.md gets a
    one-line note that scores sync via the user's own iCloud (we still collect
    nothing).
  - **In-progress games stay strictly local** — deliberately not synced. A
    half-played board on two devices has no lossless merge (one would overwrite
    the other), and it's transient by nature; only the high-stakes scoreboard is
    worth syncing.
  - **Testing:** the merge is a pure function → unit-tested headless (the
    high-value tests). KVS itself can only be verified on real devices on the
    same iCloud account (simulator KVS is unreliable).

### Big boards

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
      Leaks). The v0.1 groundwork retain audit was clean at current scale (see
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
      alternative here (and again for edgeless wrapped boards in v0.3).

## Backlog (unversioned)

Polish and smaller features that can land in any release — not milestone gates.
The numbered milestones are the real pillars (scale, then board variants); these
slot into whichever release they're ready for.

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

**Code cleanup (next refactor round):**

- [ ] **Pause as a UI play-state.** `isPaused` is a UI-only flag on
      `GameViewModel` while `GameStatus` (Core) stays pure (`notStarted/playing/
      won/lost`, also Codable-saved + used by the `Solver`). The smell is the
      scattered `status == .playing && !isPaused` checks. Fold them into one
      view-model computed enum (e.g. `playState` with a `.paused` case) the UI
      reads — without pushing a UI concept into Core/solver/save. Decide during a
      later refactor pass.
- [ ] **`GameStatus` convenience accessors.** Replace the repeated
      `status == .notStarted || status == .playing` with computed properties on
      the enum (`isLive` / `isFinished` / `isPlaying`). Pure readability; no
      behaviour change.

## v0.3.0 — Board variants (wrapped + hex)

The two board-topology pillars, grouped: both exercise the `Topology` /
`CellLayout` seams the same way and share the "select a variant, score it
separately" UI work, so they're one milestone rather than two minors.

### Wrapped (torus) boards

The "wrapped edges" pillar. Logic already proven — a `WrappedSquareTopology`
test wins a full game with unchanged rules. This release makes it playable.

- [ ] Mode selector exposing bounded vs wrapped
- [ ] Rendering that conveys wrap-around (edge ghosting / seamless scroll, or
      explicit "this edge connects to that one" affordance)
- [ ] Pan behaviour for a seamless/torus surface (no hard edges to clamp to)
- [ ] Scoreboards keyed by topology

### Hex grids

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
- **Release/CD strategy.** Decision: **manual for v0.1** — archive + upload via
  Xcode (or one local `fastlane` lane run by hand). The solo pre-release cadence
  doesn't justify automation, and it sidesteps secret-management entirely. When
  uploads get tedious, add **GitHub Actions CD on the (public) repo, triggered
  only on version tags**, with the App Store Connect API key + signing certs as
  repo secrets scoped so they NEVER run on untrusted fork PRs — the repo staying
  public is fine, the *secrets* stay private. A **separate private repo for the
  pipeline** is only warranted if private material appears (commissioned-art
  sources, or wanting the signing flow fully walled off) — same trigger as the
  art-licensing question, so don't do it preemptively.
- **AI disclosure.** The README carries an honest "AI assistance" note
      (human-directed; code largely AI-written; current art AI-generated;
      procedural chrome is AI-written code, not generated images). Remaining
      action **at submission**: mirror a short version into the App Store
      description. Apple has no dedicated "AI-generated" flag and doesn't ask
      about AI-written code, so the description text is the only store-side lever.
- [ ] **Art assets — repo/licensing strategy (open question).** Decision for
      **now: keep everything in this repo** under the current blanket MIT — the
      assets are AI-generated PNGs with no sensitive source files, so a private
      repo / placeholders would add friction for no gain (and anything shipped in
      the `.app` is extractable regardless).

      **The concern is commissioned art**: MIT lets anyone copy/modify/redistribute
      (even commercially) with only attribution — that is *wrong* for art you pay
      an artist to make. So **before committing any commissioned or hand-made
      art**, split the licensing (a single repo can carry two — standard for OSS
      games):
      - **`LICENSE` (MIT)** scoped to *code*, with a carve-out line pointing to
        the asset license.
      - **`ASSETS-LICENSE`** for the art. Default for paid commissioned work:
        **all-rights-reserved / proprietary** (no reuse). Looser alternatives if
        desired: CC BY-NC (non-commercial + credit) or CC BY-NC-ND (also no
        derivatives).
      - A short `README` in the asset folder(s) naming which license applies.
      - **Upstream piece (most important): the commission contract** must grant
        you the rights you need — ideally a full copyright assignment, or a broad
        exclusive licence to ship *and sublicense within the app*. How you then
        license to the public (above) is downstream of owning those rights.
      - **Caveat:** do the split *before* the first commissioned-art commit — git
        history would otherwise retain it under the old blanket MIT. And an
        all-rights-reserved licence makes reuse unlawful, not impossible (shipped
        `.app` pixels are still extractable) — a private *source* repo (option b)
        only protects unshipped WIP/source files, not the shipped images.

      Repo options if source files ever need privacy: (b) **separate private repo**
      for source art, export-ready assets vendored here; (c) **git submodule** to
      a private art repo. Leaning split-license-same-repo, escalating to (b) only
      if source files are large/sensitive. (Ties into the AI-disclosure note.)

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

**Shipped:** manga end-of-game result screen (win/loss/new-record panels), a
"squad resting" pause panel, the interactive title screen, a procedural app
icon, and **procedural manga chrome glyphs** (`MangaIcon`): a war-medal High
Scores button, a Quonset-hut "home"
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
- **Art sources** — the scene panels (title / win / loss / pause) are DALL·E
  (commercial-use OK via OpenAI TOS on a personal account; verify before ship);
  the app icon is *procedural* (`Scripts/make-icon.swift`), not DALL·E. If
  iterating on an icon: keep it a single bold focal subject, no baked title text,
  readable at 64px.
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
multiplayer is not planned for v1.0. (Cross-device *score* sync via the user's
own iCloud **is** planned — see v0.2.0 — but that's local-iCloud KVS, not a
server or social layer.) A **tip jar** — optional, content-neutral support — is
the one monetization form under consideration; see Distribution & extras.
