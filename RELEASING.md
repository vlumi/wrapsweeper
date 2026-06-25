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
|---|---|---|---|
| `MARKETING_VERSION` | `CFBundleShortVersionString` | User-facing version, e.g. `0.1.0` | SemVer. Bump on a meaningful milestone. |
| `CURRENT_PROJECT_VERSION` | `CFBundleVersion` | Build number, e.g. `5` | Unique & strictly increasing per upload. |

Both targets (`Donpa-iOS`, `Donpa-macOS`) carry their own copy of these. They're
**one app across two platforms** (§ Platforms — a Universal Purchase sharing the
bundle ID `fi.misaki.donpa`), but each platform builds and uploads its own binary,
so versions and build numbers *may* diverge — keep them in step only when you
choose to ship both at once. The build number is per-platform: iOS `(5)` and Mac
`(5)` are unrelated counters.

### When to bump what

- **New build of the same version** (`0.1.0 (5)` → `0.1.0 (6)`): bump only
  `CURRENT_PROJECT_VERSION`. No TestFlight Beta App Review.
- **New version** (`0.1.0` → `0.1.1` / `0.2.0` / `1.0`): bump
  `MARKETING_VERSION`. **The first external build of a new version triggers a
  one-time Beta App Review** (~hours). The review keys on the *version string*,
  not the size of the change — a patch bump reviews the same as a major one.

Practical loop: keep `MARKETING_VERSION` steady while iterating on a release,
letting the build number climb freely; bump the version when you cross a
milestone you'd write release notes for. **Internal** TestFlight testers never
need review — use an internal group for the fastest feedback loop.

> Xcode's Organizer auto-increments the build number past an existing one at
> distribution time. If that happens, resync `project.yml`'s
> `CURRENT_PROJECT_VERSION` to match so the repo doesn't drift from the upload.

## Build → commit traceability

Every build stamps the git commit it came from into its Info.plist as
`GitCommitSHA`, via [Scripts/embed-commit-sha.sh](Scripts/embed-commit-sha.sh)
(a post-build phase on both app targets — fires on `xcodebuild` and on an Xcode
Organizer archive). A dirty working tree gets a `-dirty` suffix; a non-git
checkout writes `unknown`. The SHA is shown in **About** (under the version),
so any installed build can be matched back to its source. Archive from a clean,
committed `main` so the stamp is meaningful.

## Cutting a release

1. **Versions set** in `project.yml`, committed, merged to `main`.
2. **Archive** in Xcode: Product → Archive (from a clean `main` checkout). The
   commit SHA stamps in automatically.
3. **Distribute**: Window → Organizer → Archives → select archive →
   **Distribute App** → **App Store Connect** (external-eligible; *not*
   "TestFlight Internal Only", *not* "Release Testing"). The same archive can be
   re-distributed any number of times without rebuilding.
4. **Tag the commit.** This is a monorepo with two independently-released apps,
   so every tag is **platform-prefixed** (`ios/` or `mac/`) — a bare `v0.1.0`
   tag is ambiguous. SemVer version, suffix for pre-releases:

   ```
   ios/v0.1.0-beta.1   # iOS TestFlight beta (dot before the number — sorts right)
   ios/v0.1.0-rc.1     # iOS release candidate
   ios/v0.1.0          # iOS store release (no prerelease suffix)
   mac/v0.1.0-beta.1   # the Mac track, versioned independently
   ```

   ```sh
   git tag -a ios/v0.1.0-beta.2 -m "Donpa Squad (iOS) 0.1.0 beta 2"
   git push origin ios/v0.1.0-beta.2
   ```

5. **GitHub Release** from the tag — name the platform in the title, mark
   betas/RCs as **pre-release** so they don't show as "Latest". Record the Apple
   build number and commit in the body:

   ```sh
   gh release create ios/v0.1.0-beta.2 --title "iOS v0.1.0-beta.2 — Donpa Squad" \
     --prerelease --notes "Marketing version 0.1.0 · Apple build 0.1.0 (3) · commit <sha>"
   ```

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
