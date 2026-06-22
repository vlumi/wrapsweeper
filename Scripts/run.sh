#!/usr/bin/env bash
# Build and launch the macOS app. Usage: run.sh
# Builds into a local .build-xcode dir so the product path is deterministic.
set -euo pipefail
cd "$(dirname "$0")/.."

derived=".build-xcode"
echo "Building Donpa-macOS..."
xcodebuild -project Donpa.xcodeproj -scheme Donpa-macOS -destination "platform=macOS" \
    -derivedDataPath "$derived" -configuration Debug build \
    >/dev/null 2>&1 || {
    echo "build failed; re-running with full output:" >&2
    xcodebuild -project Donpa.xcodeproj -scheme Donpa-macOS -destination "platform=macOS" \
        -derivedDataPath "$derived" -configuration Debug build
    exit 1
}

app="$derived/Build/Products/Debug/Donpa Squad.app"
[ -d "$app" ] || { echo "error: built app not found at $app" >&2; exit 1; }

# Relaunch cleanly: quit any running instance first.
osascript -e 'quit app "Donpa Squad"' 2>/dev/null || true
sleep 0.3
echo "Launching $app"
open "$app"
