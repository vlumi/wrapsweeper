#!/usr/bin/env bash
# Build an app target. Usage: build.sh <macos|ios>
# Assumes the Xcode project is already generated (the Makefile handles that).
set -euo pipefail
cd "$(dirname "$0")/.."

platform="${1:-macos}"
case "$platform" in
    macos) scheme="Donpa-macOS"; destination="platform=macOS" ;;
    ios) scheme="Donpa-iOS"; destination="generic/platform=iOS Simulator" ;;
    *) echo "usage: build.sh <macos|ios>" >&2; exit 2 ;;
esac

echo "Building ${scheme}..."
# Pipe through xcbeautify if it's installed (nicer output); otherwise raw.
if command -v xcbeautify >/dev/null; then
    set -o pipefail
    xcodebuild -project Donpa.xcodeproj -scheme "$scheme" \
        -destination "$destination" build | xcbeautify
else
    xcodebuild -project Donpa.xcodeproj -scheme "$scheme" \
        -destination "$destination" build
fi
