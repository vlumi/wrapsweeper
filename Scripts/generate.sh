#!/usr/bin/env bash
# Regenerate Donpa.xcodeproj from project.yml.
# Refuses only if *this* project is open in Xcode: regenerating it on disk
# while Xcode holds its in-memory model causes a save conflict and can clobber
# the regenerated file. Unrelated projects open in Xcode are fine.
set -euo pipefail

cd "$(dirname "$0")/.."

project_name="Donpa.xcodeproj"

if pgrep -x Xcode >/dev/null; then
    # Ask Xcode which documents it has open; refuse only if ours is among them.
    open_docs="$(osascript -e 'tell application "Xcode" to get name of documents' 2>/dev/null || true)"
    if printf '%s' "$open_docs" | grep -q "$project_name"; then
        echo "error: $project_name is open in Xcode. Close it before regenerating." >&2
        exit 1
    fi
fi

if ! command -v xcodegen >/dev/null; then
    echo "error: xcodegen not found (brew install xcodegen)." >&2
    exit 1
fi

xcodegen generate
echo "Generated Donpa.xcodeproj"
