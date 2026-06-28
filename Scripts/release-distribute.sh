#!/usr/bin/env bash
# Release step 4 (pure): regenerate the project from main's tip, then archive,
# export, and (unless --no-upload) upload each selected platform via the existing
# Scripts/distribute.sh. Reads nothing but its platform argument; builds straight
# from the checked-out main, which is the tagged merge commit after the prior step.
#
# Usage: release-distribute.sh <ios|macos|all> [--no-upload] [--require-tag]
#   --require-tag: verify a git tag already exists for project.yml's current
#   version+build (used by the standalone retry, so you can only re-distribute a
#   release that was actually tagged — not an unreleased main).
set -euo pipefail
cd "$(dirname "$0")/.."
. Scripts/release-lib.sh

platform="$(require_platform "${1:-}")"
shift || true
upload=1
require_tag=0
while [ $# -gt 0 ]; do
    case "$1" in
        --no-upload) upload=0 ;;
        --require-tag) require_tag=1 ;;
        *) die "unknown argument '$1'" ;;
    esac
    shift
done

if [ "$require_tag" -eq 1 ]; then
    version="$(read_unique MARKETING_VERSION)"
    build="$(read_unique CURRENT_PROJECT_VERSION)"
    for p in $([ "$platform" = all ] && echo "ios macos" || echo "$platform"); do
        tag_exists "$p" "$version" "$build" \
            || die "no $(tag_prefix "$p")/v${version}-${build} tag — nothing tagged to re-distribute. Run \`make release\` for a fresh cut."
    done
    echo "✓ tag(s) for v${version}-${build} present — re-distributing."
fi

Scripts/generate.sh >/dev/null

distribute() {
    if [ "$upload" -eq 1 ]; then
        Scripts/distribute.sh "$1"
    else
        Scripts/distribute.sh "$1" --no-upload
    fi
}

say "Distributing…"
case "$platform" in ios|all) distribute ios ;; esac
case "$platform" in macos|all) distribute macos ;; esac

echo
if [ "$upload" -eq 1 ]; then
    echo "✓ distributed (${platform}) — uploaded to App Store Connect."
else
    echo "✓ built (${platform}) — packages in dist/ (upload skipped)."
fi
