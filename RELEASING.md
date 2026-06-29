# Releasing

How Donpa Squad versions, builds, and ships. Mechanical steps only — the
"why" behind the architecture lives in [ARCHITECTURE.md](ARCHITECTURE.md).

## Branching

Trunk-based: `main` is the single trunk. Every change is a short-lived branch →
PR → merge to `main`. Releases are **tags**, not long-lived branches (see Cutting
a release). No `develop` branch — `main` isn't continuously deployed, so a second
permanent trunk would only add merge overhead.

**Release branches** are the one exception, cut *only* when an in-progress
release needs to be finalized/approved while trunk has already moved on to the
next version:

- Cut `release/<minor>` (e.g. `release/0.1`) from the commit the release builds
  from. Forward work (the next version) continues on `main`.
- **Fixes for that release land on the release branch** (branch off it → PR into
  it → tag the new build from it), NOT on `main` directly.
- **Every release-branch fix must also reach `main`** — cherry-pick it over, or
  the next version silently regresses it. This is the only discipline a release
  branch demands.
- **Delete the release branch once that version ships for real** — it's
  temporary, not a maintained line.

## Versioning

Two numbers, both set in [project.yml](project.yml) (the source of truth — the
`.xcodeproj` is generated, never edited by hand):

| Setting | Info.plist key | Meaning | Rule |
| --- | --- | --- | --- |
| `MARKETING_VERSION` | `CFBundleShortVersionString` | User-facing version, e.g. `0.1.0` | SemVer. Bump on a meaningful milestone. |
| `CURRENT_PROJECT_VERSION` | `CFBundleVersion` | Build number, e.g. `5` | Unique & strictly increasing per upload. |

Both targets (`Donpa-iOS`, `Donpa-macOS`) carry their own copy of these. They're
**one app across two platforms** (§ Platforms — a Universal Purchase sharing the
bundle ID `fi.misaki.donpa`). The release lane keeps both numbers **in lock-step**:
`make release` bumps `CURRENT_PROJECT_VERSION` on *every* target together (even a
single-platform release), and `MARKETING_VERSION` only on an all-platform release.
So the two apps share one version and one build number — `0.2.0 (5)` means the
same source on both. (Each still uploads its own binary; the shared numbers are a
convention the tooling enforces, not an App Store requirement.)

### When to bump what

- **New build of the same version** (`0.1.0 (5)` → `0.1.0 (6)`): bump only
  `CURRENT_PROJECT_VERSION`. No TestFlight Beta App Review.
- **New version** (`0.1.0` → `0.1.1` / `0.2.0` / `1.0`): bump
  `MARKETING_VERSION`. **The first external build of a new version triggers a
  one-time Beta App Review** (~hours). The review keys on the *version string*,
  not the size of the change — a patch bump reviews the same as a major one.

**Version-bump policy (pre-1.0 beta).** Bump `MARKETING_VERSION` only when a
**roadmap milestone** lands (0.3.0 = board variants, 0.4.0 = achievements, etc.),
never for routine iteration — climb build numbers freely within a milestone. So
the version string stays *meaningful* (version = milestone, matching the tags /
GitHub releases / changelog), and each one's one-time Beta App Review is spread
across the project rather than dumped on a big-bang 1.0 (a feature-rich first
review is marginally likelier to snag). It also de-risks the eventual 1.0: by
then the major feature sets have each cleared review at least once.

Don't bump just to mark progress — that's pure review tax with no testing-loop
benefit (the review keys on the version string, not the change size). **Internal**
TestFlight testers never need review at all — use an internal group for the
fastest feedback loop within a milestone.

> Xcode's Organizer auto-increments the build number past an existing one at
> distribution time. If that happens, resync `project.yml`'s
> `CURRENT_PROJECT_VERSION` to match so the repo doesn't drift from the upload.

## Build → commit traceability

Every build stamps the git commit it came from into its Info.plist as
`GitCommitSHA`, via [Scripts/embed-commit-sha.sh](Scripts/embed-commit-sha.sh)
(a post-build phase on every app target — fires on `xcodebuild` and on an Xcode
Organizer archive). A dirty working tree gets a `-dirty` suffix; a non-git
checkout writes `unknown`. The SHA is shown in **About** (under the version),
so any installed build can be matched back to its source. Archive from a clean,
committed `main` so the stamp is meaningful.

## Cutting a release

One command from a clean, up-to-date `main`:

```sh
make release                  # both platforms → App Store Connect
make release PLATFORM=ios      # iOS only (keeps the version; still bumps the build)
make release PLATFORM=macos    # macOS only
make release UPLOAD=0          # everything through export, no ASC upload
make release-build             # alias for UPLOAD=0
```

`make release` runs a four-step chain (each step is its own
[`Scripts/release-*.sh`](Scripts/); the Makefile wires the order). The pure
steps re-derive their inputs from git + `project.yml`, so the only state passed
between them is the merged commit on `main` — no state file:

1. **preflight** — refuse unless on a clean `main` that matches `origin/main`.
2. **publish** — the interactive, stateful step. Prompts to bump
   `MARKETING_VERSION` (all-platform releases only; blank = keep, `p` = patch
   bump, or type `X.Y.Z`); always bumps the shared build number. Commits the
   bump on a `release/vX.Y.Z-N` branch, opens a PR, sets it to **auto-merge**
   (merge commit), and **blocks until CI passes and it merges**. A red CI stops
   here — PR left open, nothing tagged or built.
3. **tag** — tags the merge commit per platform and publishes a GitHub release
   with a version/build/commit table and the commits since the platform's
   previous tag. **iOS is pinned "latest"** (GitHub allows one); macOS is a full
   release without the badge.
4. **distribute** — archives, exports, and (unless `UPLOAD=0`) uploads each
   platform to App Store Connect.

### Tags

Every tag MUST be exactly:

```text
<prefix>/vMAJOR.MINOR.PATCH-BUILD
```

— platform `<prefix>` is `ios` or `mac`; the version is plain SemVer; the suffix
is the **build number**, not a beta/rc label.

```sh
ios/v0.2.0-5    # iOS, version 0.2.0, build 5
mac/v0.2.0-5    # macOS, same version + build (lock-step)
```

This format is **load-bearing, not cosmetic** — keep it strict:

- **Platform prefix is required** — a bare `v0.2.0` is ambiguous in a monorepo
  with two independently-uploaded apps.
- **The suffix is a plain integer build number.** No `-beta.N` / `-rc.N` / any
  non-numeric suffix. The release lane orders tags with `git … --sort=-v:refname`
  and parses `(version, build)` to pick the previous release for a changelog
  (see `previous_tag` in [Scripts/release-lib.sh](Scripts/release-lib.sh)). A
  pre-release-style suffix would sort *below* the bare version (git reads `-beta`
  as a SemVer pre-release) and silently corrupt the "previous tag" choice.
- **Build numbers are shared across platforms** (lock-step), so `ios/v0.2.0-5`
  and `mac/v0.2.0-5` name the same source.

The **git tags are the source of truth** — immutable pointers to the exact commit
each build shipped from. The GitHub releases are a presentation layer on top.

> **Never delete an immutable GitHub release.** GitHub permanently reserves that
> release's tag name — even after deletion you **cannot** create a new release on
> the same tag (`tag_name was used by an immutable release`). To revise a
> release's notes/title, *edit* it (the tag can't change); to re-point it, you'd
> have to publish under a *new* tag. A delete is effectively irreversible for that
> tag. (We learned this the hard way and restarted the release list from a later
> build; the underlying git tags were kept.)

`make release` creates these; you never tag by hand in the normal flow. The
changelog for a release diffs against the **highest existing tag not newer than
it** — so a forward release (0.3.0) diffs against the prior version (0.2.0), and
an out-of-line one (a 0.1.0 patch cut after 0.2.0 shipped) diffs against the
prior 0.1.0, never against something ahead of it.

### By hand (fallback)

If you must bypass the lane — e.g. Xcode-Organizer archive while debugging
signing — archive from a clean `main` (the `GitCommitSHA` stamps in), Distribute
→ App Store Connect, then create the tag + GitHub release matching the scheme
above. Prefer re-running the lane; this is the escape hatch, not the path.

## Recovering from a failed release

The steps are **idempotent against the real artifacts** (tags, merge state) — no
progress file to go stale. Re-enter the chain at the right point:

| Where it died | What happened | Recovery |
| --- | --- | --- |
| preflight / publish, **before** the PR merged | nothing irreversible; PR (if any) left open | `make release` again — a clean restart |
| **after** the PR merged, before tagging | `main` has the bumped build but no tag yet | `make release` — **publish self-skips** (its build is already ahead of every tag) and the chain tags + distributes |
| **partway through tagging** (e.g. iOS tagged, macOS failed) | one platform tagged/released, the other not | `make release-tag` — per platform: skips a done one, creates a missing release for an existing tag, tags the rest |
| **upload only** (export succeeded, ASC upload flaked) | the `.ipa`/`.pkg` is already in `dist/` | `make release-upload` — uploads the existing package, no rebuild |
| **archive/export** (or you want a clean rebuild) | release is tagged; the build itself failed | `make release-distribute-retry` (optionally `PLATFORM=macos`) — verifies the tag exists, then re-archives/exports/uploads **without** touching git/PR/tags |

To repeat a single step in isolation (rare), call its script directly —
`Scripts/release-tag.sh all` — since the scripts stand alone; the Make targets
chain prerequisites, so `make release-tag` would re-run preflight + publish
first (both no-op if already done).

> The lane writes the **GitHub release** notes automatically (commits since the
> last tag) but does **not** touch [CHANGELOG.md](CHANGELOG.md) — that stays a
> hand-curated, human-readable history. Update it separately when a release is
> worth a narrative entry.

## TestFlight notes

- **Export compliance** is pre-declared (`ITSAppUsesNonExemptEncryption: false`)
  — no per-upload prompt.
- **External testers** need the one-time Beta App Review per version, plus a
  Beta App Description and "What to Test" in App Store Connect.
- **Internal testers** (your team, no review) are the fast path for iteration.
- A build must finish **processing** (a few minutes) before it's installable,
  review or not.

## Platforms

iOS and macOS are **one App Store Connect record** — a **Universal Purchase**:
both platforms share the bundle ID `fi.misaki.donpa`, the same Apple ID, SKU, and
name (no platform qualifier — and don't put "Mac" in the name, it's an Apple
trademark, rejected under guideline 5.2.5). Not Catalyst — a separate native
macOS target qualifies for Universal Purchase; it just needs the shared bundle ID.
Each platform still archives and uploads its **own binary** (own build numbers,
own `ios/`–`mac/` tag prefix, own beta review); metadata is entered per-platform
within the one record, and screenshots are per-platform size.

(If a macOS record ever needs adding from scratch: in App Store Connect, open the
iOS record and use the platform **⌄** dropdown next to the app name → add macOS —
do NOT create a second app record.)

### iOS (the flow above, by default)

One universal app, one binary, runs on iPhone **and** iPad. Testers install betas
via the **TestFlight app**.

### macOS — same shape, but mind these deltas

The cut-a-release steps are identical (archive → Organizer → Distribute → App
Store Connect → tag `mac/…` → GitHub release). What differs:

- **Testers install via the App Store app, not TestFlight.** There is no
  TestFlight app on macOS — a Mac beta is redeemed through the **App Store app**
  itself. Tester instructions differ from iOS accordingly.
- **Notarization is part of App Store distribution.** The macOS target already
  sets `ENABLE_HARDENED_RUNTIME: YES` (required); the upload pipeline notarizes.
  It's a validation gate that doesn't exist on iOS — expect it in the Organizer
  flow.
- **Different signing certs.** Mac App Store uses a *Mac App Distribution* +
  *Mac Installer Distribution* cert pair (vs iOS *Apple Distribution*). Automatic
  signing handles it, but the **first** Mac archive may prompt Xcode to generate
  these certs.
- **Uploads a `.pkg`,** not an `.ipa` — mechanical, Xcode does it.
- **Screenshots are Mac sizes** (1280×800 / 1440×900 / 2560×1600 / 2880×1800),
  needed only for the eventual store submission, not for TestFlight.
- **Min OS is macOS 14** (`deploymentTarget`, Apple-silicon focus) — testers on
  older macOS or Intel Macs can't run it.

Nothing extra to wire in `project.yml`: hardened runtime, bundle ID, and signing
team are already set on `Donpa-macOS`.
