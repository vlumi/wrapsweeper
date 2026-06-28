# Roadmap

How Donpa gets from "classic Minesweeper" to the full "epic" vision at
**v1.0**. The architecture (two seams — `Topology` for logical neighbours,
`CellLayout` for pixel geometry) means most features land as a new conformer
plus UI, without touching the game logic.

Versions are indicative, not contractual; scope may shift between minor
releases. Each minor groups **related** work into one meaty release rather than
giving every feature its own number: v0.2.0 carries both cross-device sync and
big boards; v0.3.0 both board-topology variants; v0.4.0 achievements (held late,
once the feature set they reference is settled); v1.0.0 the composed epic set.
The project ships **0.2.0** on TestFlight today (pre-release, not yet a public
store release).

---

## v0.1.0 — Classic release (shipped to TestFlight)

The classic Minesweeper release on iOS + macOS — see [CHANGELOG.md](CHANGELOG.md)
for what's in it. Pre-release on TestFlight; not yet a public store release.

Carry-over notes that still inform later milestones:

- **Per-cell board VoiceOver deferred** — needs a scalable cursor model (swiping
  10k cells doesn't work on huge boards); co-design with big-board navigation.
- **JA/FI strings are drafts** (`needs_review`) — refined continuously as
  external-test feedback arrives; not a release gate.

## v0.2.0 — Cross-device & big boards

Two strands of "make the existing square game better and bigger" — grouped into
one milestone. Both have shipped; what remains for each is a real-device
verification pass (below), folded into the pre-1.0 device testing.

### Cross-device scoreboard sync

The "progress follows you across devices" pillar. **Shipped** — scores + career
totals sync via iCloud Key-Value Storage, keyed by Apple ID. Each device owns one
blob (its own counts); the display merges all devices conflict-free (counters sum,
best times merge by min) — so concurrent multi-device play Just Works with no
double-count. Opt-in (off by default) via a footer toggle on the stats sheet;
degrades to local-only when signed out; in-progress games stay local. See
[CHANGELOG.md](CHANGELOG.md) for the detail.

**Still open:**

- [ ] **Real two-device verification** — simulator KVS is unreliable, so the
      cross-device behaviour can only be confirmed on a real iPhone + Mac on one
      iCloud account (a win on one appears on the other; concurrent offline play
      reconciles without double-count; signed-out = local-only). Fold into the
      pre-1.0 real-device pass.
- [ ] **PRIVACY.md note** — one line that scores sync via the user's own iCloud
      (we still collect nothing, no server).
- [ ] **Churn / pruning** — a reinstall (esp. macOS, where the `DeviceID` is lost)
      mints a new slot, abandoning the old blob in KVS. Deferred: a dead reinstall
      can't be told from an offline device, and the blobs are tiny. Revisit only if
      KVS key/size limits are ever approached (a device registry with `lastUpdated`
      was specced but not built).

### Big boards

The "huge zoomable maps" pillar. **Largely shipped** — the full XS–XXXL size
ladder (up to 1000² = 1M cells), flat bit-packed storage, viewport culling +
texture batching, bounded zoom-out, the minimap overview, and the off-main-thread
work that keeps a million-cell board responsive. See [CHANGELOG.md](CHANGELOG.md)
for the detail.

Done for this milestone. A few non-blocking follow-ups live in the Backlog
(real-device pass, minimap polish) — none gate v0.2.0.

## Backlog (unversioned)

Polish and smaller features that can land in any release — not milestone gates.
The numbered milestones are the real pillars (scale, then board variants); these
slot into whichever release they're ready for.

**Gameplay fairness** (builds on the v0.1 logical solver):

- **"No-guess" boards — questioned, probably not wanted.** The machinery is cheap
  (the `Solver` + `TierAnalysis` already exist; generation would just resample
  until solvable), but the *desire* is in doubt: a chance of a forced guess is part
  of classic Minesweeper's character, and pure-deduction-only can feel sterile.
  Left here as a deliberate maybe, not planned work — revisit only if play
  testing says the guessing genuinely frustrates rather than spices. If it ever
  lands, ship it as an **optional per-config toggle**, never the default, so the
  classic risk stays the norm.
- [ ] Safe-reveal / question-mark flag cycle (classic third flag state).

**Navigation / UX:**

- [ ] **macOS `⌘1/2/3`** (classic presets) jump straight into a Classic game,
      jarringly switching mode mid-play. Rethink: pre-select in the New Game
      popup instead of starting immediately? Or be Modern-aware?
- [ ] **Minimap drag-to-reposition** — move the HUD out of the way (the toggle
      hides it; dragging relocates it). Also wire an opener for when it's hidden.
- [ ] **Minimap polish** — higher-contrast revealed shading; handedness-aware
      corner.

**Verify before 1.0:**

- [ ] **Real-device test pass** — everything so far is iPhone-sim + Mac only;
      need older/slower devices, iPad, and small screens (the SE status-bar
      truncation escaped exactly this gap). Profile huge boards on real hardware
      (the simulator software-renders SpriteKit and overstates cost), and confirm
      the XXXL (1M) first-arm/reveal feel + baseline memory in Instruments.

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
- [ ] Scoreboards keyed by topology — and **restructure the scoreboard UI** for
      the new axis: the per-board High Scores tables roughly triple (square /
      wrapped / hex × sizes), so scope them under a topology filter/toggle (mirrors
      the New Game shape axis). Career totals stay global (summed across all). The
      current section layout (Career + High Scores + sync footer) is the base; the
      filter just narrows the High Scores section.

### Hex grids

The "hex grids" pillar — exercises the second seam.

- [ ] `HexTopology` (6-neighbour adjacency, bounded + wrapped)
- [ ] `HexLayout` (axial/offset coords → pixels + hit-testing)
- [ ] Hex-aware tile/number rendering
- [ ] Verify game logic is genuinely unchanged (same test pattern as torus)

## v0.4.0 — Achievements

Achievements come **late on purpose**: they're a layer *over* gameplay, and their
IDs are permanent once shipped (like the scoreboard keys), so they're designed
against the (by-now) settled feature set — square + hex + wrapped boards all
exist, so achievements can reference the full variant matrix without churn. See
the **Achievements** section below for the architecture, the no-leaderboards
decision, and the design principles. The milestone is the build-out:

- [ ] Internal achievement layer (events on game-end → local store) + in-app UI
- [ ] Local + iCloud-KVS sync of the earned set (reuses the v0.2 sync blob)
- [ ] Game Center reporter bolted on behind the layer (achievements only)
- [ ] The curated achievement list defined (IDs locked) in App Store Connect

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

## Publishing & distribution

The paid account exists and both apps ship to TestFlight. How they reach the
public stores from here:

- **iOS is one universal app**: a single App Store Connect record + binary runs
  on **both iPhone and iPad** and appears on both stores automatically (shared
  page, reviews, price). No extra work — it's the default device family.
- **macOS is a separate native binary** (a distinct native build, not Mac
  Catalyst) — its own archive + review track.
- **Universal Purchase — done.** iOS and macOS now share the **one** bundle ID
  `fi.misaki.donpa` (unified this round), so they're a single App Store Connect
  record / Universal Purchase, not two. (Earlier this section assumed diverging
  IDs; that was reversed — see ARCHITECTURE.md.) Each platform still uploads its
  own binary under the shared record.
- **App age rating**: 4+ / PEGI 3 (set via the App Store Connect questionnaire;
  nothing in the feature set pushes it higher).
- **App age rating**: 4+ / PEGI 3 (set via the App Store Connect questionnaire;
  nothing in the feature set pushes it higher).
- **Release/CD strategy.** A **local release lane** now does the whole cut:
  `make release` bumps the version/build, opens an auto-merging PR, waits for CI,
  tags the merge commit, publishes the GitHub release, and uploads to App Store
  Connect (see [RELEASING.md](RELEASING.md)). Credentials (the ASC API key) stay
  on the dev machine, outside the repo — so no secret management and it runs from
  one command. **GitHub Actions CD** (tag-triggered, secrets scoped off fork PRs)
  remains a *possible* later step only if the solo local cadence ever becomes a
  bottleneck — not currently needed, since the lane already makes a release one
  command. A separate private pipeline repo is only warranted if private material
  appears (commissioned-art sources) — same trigger as the art-licensing question.
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

## Achievements (the v0.4 milestone — detail)

Achievements via Game Center — mostly an event-plumbing job, but with real
permanence to design around. The paid account now exists and the app ships to
TestFlight, so this is no longer account-gated; what remains is the App Store
Connect Game Center setup + the build-out.

**No leaderboards — deliberate.** Game Center *leaderboards* are out of scope, not
just deferred. Scores here are local and **user-editable by design** (see Design
principles — no anti-cheat), so a global leaderboard would fill with impossible
times almost immediately and there's no honest way to police it without the
server-side validation we've chosen not to build. Achievements don't have this
problem: they're personal (between the player and their own play), not a ranked
comparison, so a tampered local score only ever "cheats" yourself. So: Game Center
**achievements yes, leaderboards no.**

**Prerequisites:**

- App registered in **App Store Connect** with the **Game Center** capability
  enabled (the paid account exists; this is just the ASC setup).
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
`Scripts/assets/make-boot.swift`). The mode toggle is a single-tap dig|flag segmented
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
  the app icon is *procedural* (`Scripts/assets/make-icon.swift`), not DALL·E. If
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
- [x] **TestFlight** beta distribution (iOS + Mac) — live; the channel for
      pre-release testing.
- [ ] **watchOS version?** — a big maybe; minesweeper on a tiny screen is its
      own design problem. Parked.
- [ ] **Tip jar?** — see the monetization note below; would be a *deliberate*
      exception to the no-monetization stance, not ads/IAP-for-content.

## Design principles

- **No anti-cheat, by design.** Scores are local and user-editable (low
  security, by choice). This is *why* global leaderboards are out of scope (see
  Achievements): with no validation they'd just fill with impossible scores.
  Achievements stay personal, so tampering only cheats yourself.

## Deliberately out of scope

Per project conventions: **no ads, no microtransactions, no pay-to-win**; no
third-party dependencies; the older Intel Mac is not targeted. Online
multiplayer is not planned for v1.0. (Cross-device *score* sync via the user's
own iCloud **is** planned — see v0.2.0 — but that's local-iCloud KVS, not a
server or social layer.) A **tip jar** — optional, content-neutral support — is
the one monetization form under consideration; see Distribution & extras.
