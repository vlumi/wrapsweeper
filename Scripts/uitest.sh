#!/usr/bin/env bash
# Run the local-only iOS UI tests (XCUITest). Not part of CI — CI runs the
# package logic suite (`swift test`) and `xcodebuild build` only. Usage: uitest.sh
# Assumes the Xcode project is already generated (the Makefile handles that).
set -euo pipefail
cd "$(dirname "$0")/.."

# A booted simulator if there is one, else the latest available iPhone.
destination="platform=iOS Simulator,name=iPhone 17 Pro"
if ! xcrun simctl list devices available | grep -q "iPhone 17 Pro"; then
    # Fall back to whatever iPhone the host has.
    name=$(xcrun simctl list devices available | grep -oE "iPhone [0-9][^(]*" | head -1 | xargs)
    destination="platform=iOS Simulator,name=${name}"
fi

echo "Running UI tests on: ${destination}"
if command -v xcbeautify >/dev/null; then
    set -o pipefail
    xcodebuild -project Donpa.xcodeproj -scheme Donpa-iOS \
        -destination "$destination" test | xcbeautify
else
    xcodebuild -project Donpa.xcodeproj -scheme Donpa-iOS \
        -destination "$destination" test
fi
