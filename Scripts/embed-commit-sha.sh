#!/bin/sh
#
# Stamp the current git commit into the built app's Info.plist as a custom
# `GitCommitSHA` key, so every build (TestFlight, App Store, local) self-
# identifies the exact source it came from. Wired as a run-script build phase
# in project.yml for both app targets, so it fires on `xcodebuild` AND on an
# Xcode Organizer "Archive" (Apple sets INFOPLIST_PATH / TARGET_BUILD_DIR for us).
#
# It only writes the built product's plist (the bundled copy), never the source
# Info.plist — that one is XcodeGen-owned. A non-git checkout (e.g. a source
# tarball) writes "unknown" rather than failing the build, and a genuinely dirty
# tree gets a "-dirty" suffix so a build off uncommitted changes is never mistaken
# for a clean commit.
#
# The dirty check IGNORES *.xcstrings: Xcode's string extraction re-touches the
# String Catalogs DURING the build (reformat, extraction-state flags), so they
# show as modified mid-archive even from a clean checkout. Treating that churn as
# "dirty" would non-deterministically taint clean builds, so changes confined to
# *.xcstrings don't count — anything else modified still does.

set -eu

PLIST="${TARGET_BUILD_DIR:-}/${INFOPLIST_PATH:-}"
if [ -z "${TARGET_BUILD_DIR:-}" ] || [ -z "${INFOPLIST_PATH:-}" ] || [ ! -f "$PLIST" ]; then
    echo "embed-commit-sha: no built Info.plist (TARGET_BUILD_DIR/INFOPLIST_PATH unset) — skipping"
    exit 0
fi

if git -C "${SRCROOT:-.}" rev-parse --git-dir >/dev/null 2>&1; then
    SHA=$(git -C "${SRCROOT:-.}" rev-parse --short HEAD)
    # Modified tracked files, excluding the build-churned String Catalogs. Any
    # remaining entry means a genuine uncommitted change → mark the build dirty.
    DIRTY=$(git -C "${SRCROOT:-.}" diff --name-only HEAD 2>/dev/null \
        | grep -v '\.xcstrings$' || true)
    if [ -n "$DIRTY" ]; then
        SHA="${SHA}-dirty"
    fi
else
    SHA="unknown"
fi

/usr/libexec/PlistBuddy -c "Set :GitCommitSHA $SHA" "$PLIST" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :GitCommitSHA string $SHA" "$PLIST"

echo "embed-commit-sha: stamped GitCommitSHA = $SHA into $PLIST"
