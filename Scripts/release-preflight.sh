#!/usr/bin/env bash
# Release step 1 (pure): refuse to start unless we're on a clean main that matches
# origin, with gh available — so the commit we eventually tag and build is exactly
# what reviewers see and what lands on main. Mutates nothing; safe to run anytime.
set -euo pipefail
cd "$(dirname "$0")/.."
. Scripts/release-lib.sh

command -v gh >/dev/null || die "gh CLI not found (needed to open + auto-merge the PR)."
[ -z "$(git status --porcelain)" ] || die "working tree not clean — commit or stash first."
branch_now="$(git rev-parse --abbrev-ref HEAD)"
[ "$branch_now" = "main" ] || die "not on main (on '$branch_now'). Release from main."
say "Fetching origin…"
git fetch --quiet origin main
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] \
    || die "local main differs from origin/main — pull/push to sync first."
echo "✓ preflight: on a clean main matching origin."
