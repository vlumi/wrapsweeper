#!/usr/bin/env bash
# Release step 2 (the dirty middle): the interactive + stateful core that can't
# decompose into pure Make steps. Bumps the version/build (with prompts), opens an
# auto-merging PR, and blocks until CI passes and it merges. All the cross-step
# state (new version/build, branch name) lives here, in memory, within this one
# run. The pure steps that follow (tag, distribute) read the result back from the
# merged commit on main — so nothing is passed between scripts.
#
# Versioning (project.yml, shared across all app targets):
#   • MARKETING_VERSION — bumped only on an `all` release, and only if you say so.
#   • CURRENT_PROJECT_VERSION — the build number, always bumped on every target.
#
# Usage: release-publish.sh <ios|macos|all>
# On CI failure it stops with the PR left open: no merge, and (since the later
# steps never run) no tag, build, or upload.
set -euo pipefail
cd "$(dirname "$0")/.."
. Scripts/release-lib.sh

platform="$(require_platform "${1:-}")"

# Releasing all is the common path (just confirm). Single-platform is explicit.
if [ "$platform" = "all" ]; then
    printf 'Release ALL platforms (iOS + macOS)? [Y/n] '
    read -r ans || ans=""
    case "$ans" in [nN]*) die "aborted." ;; esac
fi

# ── Decide the next version + build ───────────────────────────────────────────
cur_version="$(read_unique MARKETING_VERSION)"
cur_build="$(read_unique CURRENT_PROJECT_VERSION)"
echo "current: version ${cur_version}, build ${cur_build}"

# Resume guard: if main's build is already ahead of every tag, a previous run's
# bump merged but wasn't tagged — publishing is done. Skip (don't re-bump / open
# a second PR); the chain flows on to release-tag. The tags are the record, so no
# state file is needed.
if [ "$cur_build" -gt "$(highest_tagged_build)" ]; then
    echo "✓ build ${cur_build} already merged to main but untagged — publish already done, skipping to tag."
    exit 0
fi

new_version="$cur_version"
if [ "$platform" = "all" ]; then
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
    echo "single-platform release ($platform): keeping version ${cur_version} (build still bumps every target)."
fi
new_build=$(( cur_build + 1 ))
echo "release: version ${new_version}, build ${new_build} (build applies to every target)"

# ── Apply the bump to project.yml ─────────────────────────────────────────────
if [ "$new_version" != "$cur_version" ]; then
    sed -i '' -E "s/(MARKETING_VERSION: *)\"[^\"]+\"/\1\"${new_version}\"/" "$PROJECT_FILE"
fi
sed -i '' -E "s/(CURRENT_PROJECT_VERSION: *)\"[0-9]+\"/\1\"${new_build}\"/" "$PROJECT_FILE"
[ "$(read_unique MARKETING_VERSION)" = "$new_version" ] || die "version not applied to all targets."
[ "$(read_unique CURRENT_PROJECT_VERSION)" = "$new_build" ] || die "build not applied to all targets."

# ── Stamp the changelog: Unreleased → build N (stages CHANGELOG.md if it had entries)
say "Stamping the changelog…"
promote_changelog_build "$new_build"

# ── Branch, commit, push, PR with auto-merge ──────────────────────────────────
rel_branch="release/v${new_version}-${new_build}"
git rev-parse --verify "$rel_branch" >/dev/null 2>&1 && die "branch '$rel_branch' already exists."
git checkout -q -b "$rel_branch"
# project.yml always; CHANGELOG.md too when the stamp promoted entries (a no-op add
# is harmless if it was already staged or had nothing to promote).
git add "$PROJECT_FILE" "$CHANGELOG_FILE"
git commit --quiet -m "$(cat <<EOF
Release v${new_version} build ${new_build} (${platform})

Marketing version ${new_version}, shared build number ${new_build} (bumped
on every target). The changelog Unreleased section is stamped as build
${new_build}. Opened by Scripts/release-publish.sh, which tags this merge
commit and distributes ${platform} once CI passes.
EOF
)"
git push --quiet -u origin "$rel_branch"

say "Opening PR…"
gh pr create \
    --title "Release v${new_version} build ${new_build} (${platform})" \
    --body "Version **${new_version}**, build **${new_build}** (build bumped on every target; release scope: **${platform}**). Opened by \`Scripts/release-publish.sh\`; set to auto-merge once CI passes. The resulting merge commit on main is tagged and distributed." \
    --head "$rel_branch" >/dev/null

say "Enabling auto-merge (merge commit) — will merge when CI passes…"
gh pr merge "$rel_branch" --auto --merge

# ── Wait for CI; stop (PR left open) before anything irreversible if it fails ──
# Right after `pr create`, gh may report "no checks" before the workflow appears.
# Poll (exit 8 = pending) until a check exists, then --watch to completion;
# distinguish a real failure from merely-pending so we never proceed unverified.
say "Waiting for CI to register…"
tries=0
while true; do
    gh pr checks "$rel_branch" >/dev/null 2>&1 && break          # all checks already done & green
    rc=$?
    [ "$rc" -eq 8 ] && break                                     # pending — checks exist, go watch
    tries=$(( tries + 1 ))
    [ "$tries" -ge 12 ] && die "no CI checks registered after ~60s — PR left open at $rel_branch."
    sleep 5
done
say "Waiting for CI to finish (auto-merge completes on green)…"
if ! gh pr checks "$rel_branch" --watch --fail-fast; then
    die "CI failed — PR left open at $rel_branch. No merge, tag, build, or upload was done."
fi

say "Confirming merge…"
state="$(gh pr view "$rel_branch" --json state --jq .state)"
[ "$state" = "MERGED" ] || die "PR is '$state', not MERGED (auto-merge may need a review). Re-run the tag + distribute steps once it merges."

echo "✓ published: v${new_version} build ${new_build} merged to main."
