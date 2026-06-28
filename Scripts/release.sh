#!/usr/bin/env bash
# One command to cut a release: bump versions, open an auto-merging PR, wait for
# CI, tag the released commit, and archive/export/upload to App Store Connect.
#
# Versioning model (project.yml, shared by both app targets):
#   • MARKETING_VERSION   — the human version (e.g. 0.2.0). Bumped only on a
#     `both` release, and only if you say so when prompted.
#   • CURRENT_PROJECT_VERSION — the build number. Always bumped (both targets),
#     for every release, single-platform or both.
# Tags are derived from these, per platform, no beta/rc:  ios/vX.Y.Z-N , mac/…
#
# Flow:
#   preflight (clean main, up to date) → bump → branch+commit+push → PR with
#   auto-merge (--merge) → wait for CI → on green+merged: tag → archive/export
#   → upload. CI failure stops before any tag/build/upload (PR left open).
#
# Usage:
#   Scripts/release.sh [ios|macos|both]            # default: both, upload to ASC
#   Scripts/release.sh both --no-upload            # everything through export, no upload
#   Scripts/release.sh ios                         # iOS only (no version-bump prompt)
#
# Requires: gh (authenticated), and the App Store Connect API key set up exactly
# as Scripts/distribute.sh documents (only needed when uploading).
set -euo pipefail

cd "$(dirname "$0")/.."

platform="${1:-both}"
upload=1
shift || true
while [ $# -gt 0 ]; do
    case "$1" in
        --no-upload) upload=0 ;;
        *) echo "error: unknown argument '$1'" >&2; exit 2 ;;
    esac
    shift
done

case "$platform" in
    ios|macos|both) ;;
    *) echo "usage: release.sh [ios|macos|both] [--no-upload]" >&2; exit 2 ;;
esac

file="project.yml"
say() { printf '\033[36m▶︎ %s\033[0m\n' "$*"; }
die() { echo "error: $*" >&2; exit 1; }

# ── 1. Preflight ────────────────────────────────────────────────────────────
# Start from a known-clean main that matches origin, so the commit we tag (and
# build) is exactly what reviewers see and what lands on main after merge.
command -v gh >/dev/null || die "gh CLI not found (needed to open + auto-merge the PR)."
[ -z "$(git status --porcelain)" ] || die "working tree not clean — commit or stash first."
branch_now="$(git rev-parse --abbrev-ref HEAD)"
[ "$branch_now" = "main" ] || die "not on main (on '$branch_now'). Release from main."
say "Fetching origin…"
git fetch --quiet origin main
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] \
    || die "local main differs from origin/main — pull/push to sync first."

# ── 2. Read current versions ──────────────────────────────────────────────────
read_unique() {  # echo the sole distinct value of setting $1 in project.yml, or die
    local key="$1" vals
    vals="$(grep -oE "${key}: *\"[^\"]+\"" "$file" | grep -oE '"[^"]+"' | tr -d '"' | sort -u)"
    [ -n "$vals" ] || die "no ${key} found in $file"
    [ "$(printf '%s\n' "$vals" | wc -l)" -eq 1 ] \
        || die "${key} differs between targets in $file: $(echo "$vals" | tr '\n' ' ')"
    printf '%s' "$vals"
}
cur_version="$(read_unique MARKETING_VERSION)"
cur_build="$(read_unique CURRENT_PROJECT_VERSION)"
echo "current: version ${cur_version}, build ${cur_build}"

# ── 3. Decide the next version + build ────────────────────────────────────────
new_version="$cur_version"
if [ "$platform" = "both" ]; then
    # Suggest a patch bump; let the user keep, accept, or type any X.Y.Z.
    IFS='.' read -r MA MI PA <<EOF
${cur_version}
EOF
    suggested="${MA}.${MI}.$(( ${PA:-0} + 1 ))"
    printf 'Bump marketing version? current %s — enter new (blank = keep, "p" = %s): ' \
        "$cur_version" "$suggested"
    read -r answer || answer=""
    case "$answer" in
        "")  new_version="$cur_version" ;;
        p|P) new_version="$suggested" ;;
        *)   [[ "$answer" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
                 || die "version must be X.Y.Z (got '$answer')"
             new_version="$answer" ;;
    esac
else
    echo "single-platform release ($platform): keeping version ${cur_version} (build still bumps both)."
fi
new_build=$(( cur_build + 1 ))
echo "release: version ${new_version}, build ${new_build} (build applies to both targets)"

# ── 4. Apply the bump to project.yml ──────────────────────────────────────────
# Both numbers are quoted and shared across targets; rewrite every occurrence.
if [ "$new_version" != "$cur_version" ]; then
    sed -i '' -E "s/(MARKETING_VERSION: *)\"[^\"]+\"/\1\"${new_version}\"/" "$file"
fi
sed -i '' -E "s/(CURRENT_PROJECT_VERSION: *)\"[0-9]+\"/\1\"${new_build}\"/" "$file"
[ "$(read_unique MARKETING_VERSION)" = "$new_version" ] || die "version not applied to all targets."
[ "$(read_unique CURRENT_PROJECT_VERSION)" = "$new_build" ] || die "build not applied to all targets."

# ── 5. Branch, commit, push, PR with auto-merge ───────────────────────────────
rel_branch="release/v${new_version}-${new_build}"
git rev-parse --verify "$rel_branch" >/dev/null 2>&1 && die "branch '$rel_branch' already exists."
git checkout -q -b "$rel_branch"
git add "$file"
git commit --quiet -m "$(cat <<EOF
Release v${new_version} build ${new_build} (${platform})

Marketing version ${new_version}, shared build number ${new_build} (both
targets). Tagged $( [ "$platform" = both ] && echo "ios/ + mac/" || echo "${platform}/" )v${new_version}-${new_build} and distributed via Scripts/release.sh.
EOF
)"
git push --quiet -u origin "$rel_branch"

say "Opening PR…"
gh pr create \
    --title "Release v${new_version} build ${new_build} (${platform})" \
    --body "Version **${new_version}**, build **${new_build}** (both targets). Opened by \`Scripts/release.sh\`; set to auto-merge once CI passes. The resulting merge commit on main is tagged and distributed." \
    --head "$rel_branch" >/dev/null

say "Enabling auto-merge (merge commit) — will merge when CI passes…"
gh pr merge "$rel_branch" --auto --merge

# ── 6. Wait for CI; stop before tagging/building if it fails ──────────────────
say "Waiting for CI (auto-merge completes on green)…"
if ! gh pr checks "$rel_branch" --watch --fail-fast; then
    die "CI failed — PR left open at $rel_branch. No tag, build, or upload was done."
fi

# Confirm it actually merged (auto-merge can stall on review/branch-protection).
say "Confirming merge…"
state="$(gh pr view "$rel_branch" --json state --jq .state)"
[ "$state" = "MERGED" ] || die "PR is '$state', not MERGED (auto-merge may need a review). Re-run distribution after it merges."

# ── 7. Refresh main, then tag the merge commit (per platform), push tags ──────
# Pull the post-merge main; the merge commit is its tip. We tag and build that,
# so the tag, the source, and the embedded GitCommitSHA are all the same commit.
say "Refreshing main…"
git checkout -q main
git pull --quiet --ff-only origin main
merge_sha="$(git rev-parse HEAD)"
expected_subject="Merge pull request"
git log -1 --pretty=%s | grep -q "$expected_subject" \
    || echo "  note: main tip isn't a merge commit (subject: $(git log -1 --pretty=%s)) — tagging it anyway."

tag_one() {  # $1 = ios|macos → prefix ios|mac
    local prefix; prefix="$([ "$1" = macos ] && echo mac || echo ios)"
    local tag="${prefix}/v${new_version}-${new_build}"
    git rev-parse --verify "$tag" >/dev/null 2>&1 && die "tag '$tag' already exists."
    git tag -a "$tag" "$merge_sha" -m "Donpa $1 v${new_version} (build ${new_build})"
    git push --quiet origin "$tag"
    echo "  tagged $tag → ${merge_sha:0:7}"
}
say "Tagging the merge commit on main…"
case "$platform" in ios|both) tag_one ios ;; esac
case "$platform" in macos|both) tag_one macos ;; esac

# ── 8. Archive / export / upload the selected platform(s) ─────────────────────
# Built straight from main's tip (the tagged merge commit).
Scripts/generate.sh >/dev/null

distribute() {  # $1 = ios|macos
    if [ "$upload" -eq 1 ]; then
        Scripts/distribute.sh "$1"
    else
        Scripts/distribute.sh "$1" --no-upload
    fi
}
say "Distributing…"
case "$platform" in ios|both) distribute ios ;; esac
case "$platform" in macos|both) distribute macos ;; esac

echo
if [ "$upload" -eq 1 ]; then
    echo "✓ Released v${new_version} build ${new_build} (${platform}) — uploaded to App Store Connect."
else
    echo "✓ Built v${new_version} build ${new_build} (${platform}) — packages in dist/ (upload skipped)."
fi
