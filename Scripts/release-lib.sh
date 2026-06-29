# Shared helpers for the release scripts (sourced, not executed).
#
# The release flow is split by concern: release-preflight.sh, release-publish.sh,
# release-tag.sh, distribute.sh — wired in order by the Makefile. The pure steps
# (preflight, tag, distribute) re-derive their inputs from git + project.yml so
# each runs standalone; only the dirty middle (publish: bump prompts + PR +
# CI-wait) carries in-memory state, all within one script.

# shellcheck shell=bash

PROJECT_FILE="project.yml"
CHANGELOG_FILE="CHANGELOG.md"

say() { printf '\033[36m▶︎ %s\033[0m\n' "$*"; }
die() { echo "error: $*" >&2; exit 1; }

# Stamp the changelog's "Unreleased (next build)" section with a build number at
# release time, so the human-written entries accumulated there during the cycle get
# promoted to a `### build N` heading (and a fresh empty Unreleased takes its place).
# The release author still writes the entries as PRs merge; this only does the
# mechanical promotion — closing the gap where a build could ship without a heading.
# No-op (exit 0, nothing staged) if Unreleased has no real content yet, so a build
# with only doc/internal changes doesn't get an empty heading.
promote_changelog_build() {
    local build="$1"
    local heading="### Unreleased (next build)"
    [ -f "$CHANGELOG_FILE" ] || { say "no $CHANGELOG_FILE — skipping changelog stamp."; return 0; }

    # The format keeps the Unreleased heading immediately followed by its list items
    # (nothing in between — see CHANGELOG.md's preamble), so "is there anything to
    # promote" is just: a list item before the next "### " heading. No-op otherwise,
    # so a doc/internal-only build doesn't get an empty heading.
    awk '
        f && /^#/ { exit 1 }               # hit the next heading first → no items
        f && /^[[:space:]]*-[[:space:]]/ { exit 0 }   # a list item → promote
        $0 == h { f = 1 }
    ' h="$heading" "$CHANGELOG_FILE" || {
        echo "  (Unreleased has no entries — nothing to promote)"
        return 0
    }

    # Promote: rename the heading to "### build N", and put a fresh empty Unreleased
    # heading back above it. One substitution on the single heading line — the entries
    # below it are already in the right place, so nothing else moves.
    local tmp; tmp="$(mktemp)"
    awk -v build="$build" '
        $0 == h && !done {
            print h "\n\n### build " build
            done = 1
            next
        }
        { print }
    ' h="$heading" "$CHANGELOG_FILE" > "$tmp"
    mv "$tmp" "$CHANGELOG_FILE"
    git add "$CHANGELOG_FILE"
    echo "  promoted Unreleased → build ${build}"
}

# Echo the sole distinct value of a quoted setting in project.yml, or die if it's
# missing or differs between the two targets (they're kept in lock-step).
read_unique() {
    local key="$1" vals
    vals="$(grep -oE "${key}: *\"[^\"]+\"" "$PROJECT_FILE" | grep -oE '"[^"]+"' | tr -d '"' | sort -u)"
    [ -n "$vals" ] || die "no ${key} found in $PROJECT_FILE"
    [ "$(printf '%s\n' "$vals" | wc -l)" -eq 1 ] \
        || die "${key} differs between targets in $PROJECT_FILE: $(echo "$vals" | tr '\n' ' ')"
    printf '%s' "$vals"
}

# Validate a platform argument (ios|macos|all), echoing it back.
require_platform() {
    case "${1:-}" in
        ios|macos|all) printf '%s' "$1" ;;
        *) die "platform must be ios|macos|all (got '${1:-}')" ;;
    esac
}

# git prefix (ios|mac) and display label (iOS|macOS) for a platform.
tag_prefix() { [ "$1" = macos ] && echo mac || echo ios; }
plat_label() { [ "$1" = macos ] && echo macOS || echo iOS; }

# The highest build number N across all ios/ + mac/ vX.Y.Z-N tags, or 0 if none.
# Lets publish tell "main is a bumped-but-untagged tip" (already merged) from a
# fresh release, without any state file — the tags are the record.
highest_tagged_build() {
    local n max=0
    while IFS= read -r n; do [ "$n" -gt "$max" ] && max="$n"; done < <(
        git tag --list 'ios/v*' 'mac/v*' | grep -oE -- '-[0-9]+$' | tr -d '-')
    printf '%s' "$max"
}

# True if a git tag exists for this platform at version-build.
tag_exists() { git rev-parse --verify "$(tag_prefix "$1")/v${2}-${3}" >/dev/null 2>&1; }

# The previous release tag to diff a changelog against: the highest-versioned
# tag for this platform that is NOT newer than the release at $2-$3 (and not that
# tag itself). So a normal forward release diffs against the prior version, and an
# out-of-line release (e.g. a 0.1.0 back-port cut after 0.2.0 shipped) diffs
# against the prior 0.1.0 — never against a version ahead of it. Echoes nothing if
# there's no earlier tag.
#
# Tags MUST be `<prefix>/vMAJOR.MINOR.PATCH-BUILD` (see RELEASING.md). The order
# key is (version, build); `v:refname` sorts these correctly only because every
# tag shares the single `-BUILD` suffix form — a stray `-beta.N` would mis-sort
# (git reads it as a semver pre-release), so the strict scheme is load-bearing.
previous_tag() {
    local plat="$1" version="$2" build="$3"
    local prefix; prefix="$(tag_prefix "$plat")"
    local this="${prefix}/v${version}-${build}"
    # Numeric sort key per tag: MAJOR*1e12 + MINOR*1e8 + PATCH*1e4 + BUILD, paired
    # with the tag, descending. First entry whose key < this tag's key wins.
    local this_key; this_key="$(tag_sort_key "$this")"
    local t k
    while IFS= read -r t; do
        [ "$t" = "$this" ] && continue
        k="$(tag_sort_key "$t")"
        if [ "$k" -le "$this_key" ]; then printf '%s' "$t"; return; fi
    done < <(git tag --list "${prefix}/v*" --sort=-v:refname)
}

# A sortable integer for a `<prefix>/vX.Y.Z-N` tag: X*1e12 + Y*1e8 + Z*1e4 + N.
# (Comfortably within 64-bit; each field is assumed < 10000.)
tag_sort_key() {
    local v="${1#*/v}"            # strip "<prefix>/v"
    local ver="${v%-*}" build="${v##*-}"
    # Split sequentially — a single `local a=… b=${a…}` can't see `a` yet.
    local maj="${ver%%.*}"
    local rest="${ver#*.}"
    local min="${rest%%.*}"
    local pat="${rest#*.}"
    printf '%d' "$(( maj * 1000000000000 + min * 100000000 + pat * 10000 + build ))"
}

# True if a GitHub release exists for the given tag.
gh_release_exists() { gh release view "$1" >/dev/null 2>&1; }
