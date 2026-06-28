#!/usr/bin/env bash
# Release step 3 (pure): tag the released commit and publish a GitHub release, per
# platform. Re-derives everything from durable state — the version/build from the
# merged project.yml on main, the commit from main's tip — so it needs nothing
# passed in and is safe to re-run (it refuses to clobber an existing tag).
#
# iOS is the repo's "latest" (GitHub allows one); macOS is a full release without
# the badge. Tags are ios/vX.Y.Z-N and mac/vX.Y.Z-N (no beta/rc).
#
# Usage: release-tag.sh <ios|macos|all>   (run after release-publish.sh merges)
set -euo pipefail
cd "$(dirname "$0")/.."
. Scripts/release-lib.sh

platform="$(require_platform "${1:-}")"

say "Refreshing main…"
git checkout -q main
git pull --quiet --ff-only origin main
version="$(read_unique MARKETING_VERSION)"
build="$(read_unique CURRENT_PROJECT_VERSION)"
merge_sha="$(git rev-parse HEAD)"
git log -1 --pretty=%s | grep -q "Merge pull request" \
    || echo "  note: main tip isn't a merge commit (subject: $(git log -1 --pretty=%s)) — tagging it anyway."
echo "tagging v${version} build ${build} at ${merge_sha:0:7}"

release_one() {  # $1 = ios|macos
    local plat="$1" prefix label tag
    prefix="$(tag_prefix "$plat")"
    label="$(plat_label "$plat")"
    tag="${prefix}/v${version}-${build}"

    # Idempotent per platform, so a partial re-run (e.g. iOS done, macOS failed)
    # finishes only what's missing rather than dying:
    #   tag + release exist → skip; tag only → just create the release; neither →
    #   tag then release.
    if tag_exists "$plat" "$version" "$build" && gh_release_exists "$tag"; then
        echo "  $tag already tagged + released — skipping."
        return
    fi
    if tag_exists "$plat" "$version" "$build"; then
        echo "  $tag already tagged; creating its GitHub release."
    else
        git tag -a "$tag" "$merge_sha" -m "Donpa ${label} v${version} (build ${build})"
        git push --quiet origin "$tag"
        echo "  tagged $tag → ${merge_sha:0:7}"
    fi

    # Changelog: the commit subjects since this platform's previous tag.
    local prev notes_changes since
    prev="$(git tag --list "${prefix}/v*" --sort=-creatordate | grep -v "^${tag}$" | head -1)"
    if [ -n "$prev" ]; then
        notes_changes="$(git log --no-merges --pretty='- %s' "${prev}..${merge_sha}")"
        since=" since ${prev#"$prefix"/}"
    else
        notes_changes="- Initial ${label} release."
        since=""
    fi
    local notes
    notes="$(cat <<EOF
${label} release for ${version} build ${build}.

| | |
|---|---|
| Marketing version | ${version} |
| Apple build number | ${version} (${build}) |
| Commit | ${merge_sha:0:7} |

**Changes${since}**
${notes_changes}
EOF
)"
    local latest; latest="$([ "$plat" = ios ] && echo true || echo false)"
    gh release create "$tag" --verify-tag \
        --title "${label} v${version} (build ${build}) — Donpa Squad" \
        --notes "$notes" --latest="$latest" >/dev/null
    echo "  published GitHub release for $tag (latest=$latest)"
}

say "Tagging + publishing GitHub releases…"
case "$platform" in ios|all) release_one ios ;; esac
case "$platform" in macos|all) release_one macos ;; esac
echo "✓ tagged + released (${platform})."
