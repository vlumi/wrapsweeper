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
- [x] Difficulty presets (Beginner / Intermediate / Expert)
- [x] SpriteKit board with pan/zoom, board-constrained panning
- [x] Reveal/Flag mode toggle + long-press alternate action
- [x] Local scoreboard: best time + games-cleared count per difficulty
- [x] iOS + macOS app targets, CI
- [x] App icon
- [x] Light / dark / system appearance (settings sheet, persisted)
- [ ] **Remaining for release:**
  - [ ] Launch screen
  - [ ] First-run polish: empty-state, win/lose feedback (haptics on iOS, subtle animation)
  - [ ] Accessibility pass (VoiceOver labels for cells, Dynamic Type in chrome)
  - [ ] Persist last difficulty and input mode (appearance already persisted)
  - [ ] Localization / language setting (Settings sheet has room for it)
  - [ ] Tag v0.1.0, signed builds

## v0.2.0 — Curated board configs & restraint

Groundwork that later epic features lean on. Deliberately **not** free-form
custom boards — too much choice — but two curated axes instead.

- [ ] **Split size from difficulty into two fixed-set axes:**
  - **Size** — a curated set (e.g. Small / Medium / Large; Huge later for the
    epic maps).
  - **Difficulty** — a curated set of **mine densities** (% of cells), e.g.
    Easy / Normal / Hard. Size-independent by nature, so the two axes compose
    cleanly: `mineCount = round(density × width × height)`. Every size is
    available at every difficulty (difficulty is just a percentage).
  - The classic Beginner/Intermediate/Expert presets become specific
    size×density points.
  - Scoreboards key by the **combination** (e.g. "Medium · Hard"); the existing
    per-name stats store already supports this once the config name encodes both
    axes. This replaces the earlier idea of free-form custom difficulty.
- [ ] "No-guess" board generation option (solvable without guessing)
- [ ] Safe-reveal / question-mark flag cycle (classic third flag state)

## v0.3.0 — Big boards

The "huge zoomable maps" pillar. Mostly a rendering/perf effort behind the
existing `BoardScene` seam.

- [ ] Viewport culling in `BoardScene.rebuild` (only build visible cells)
- [ ] Incremental re-render (update changed cells instead of full rebuild)
- [ ] Large presets (e.g. 50×50, 100×100) + smooth pan/zoom at scale
- [ ] Minimap / overview for navigation

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

---

## Deliberately out of scope

Per project conventions: no monetization, ads, or microtransactions; no
third-party dependencies; the older Intel Mac is not targeted. Online
multiplayer and cloud-synced scores are not planned for v1.0.
