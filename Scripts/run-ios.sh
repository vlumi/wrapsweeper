#!/usr/bin/env bash
# Build, install, and launch the iOS app in a simulator. Usage: run-ios.sh [device-name]
# Builds for the generic simulator destination, then installs to a booted sim
# (an already-booted one, else the named / first available iPhone).
set -euo pipefail
cd "$(dirname "$0")/.."

bundle_id="fi.misaki.donpa"
derived=".build-xcode"
device="${1:-}"

# Pick a simulator: an already-booted one if present, else the newest available
# iPhone on iOS >= 16 (the app's minimum). Done in Python for reliable JSON
# parsing and version comparison.
udid="$(xcrun simctl list devices --json 2>/dev/null | DEVICE="$device" python3 -c '
import json, os, re, sys
d = json.load(sys.stdin)["devices"]
want = os.environ.get("DEVICE", "")
booted, best = None, None
for runtime, devs in d.items():
    m = re.search(r"iOS-(\d+)-(\d+)", runtime)
    ver = (int(m.group(1)), int(m.group(2))) if m else None
    if not ver or ver < (16, 0):  # app requires iOS 16+
        continue
    for dev in devs:
        if not dev.get("isAvailable") or "iPhone" not in dev["name"]:
            continue
        if want and want.lower() not in dev["name"].lower():
            continue
        if dev["state"] == "Booted":
            booted = dev["udid"]
        if best is None or ver > best[0]:
            best = (ver, dev["udid"])
print(booted or (best[1] if best else ""))
')"
[ -n "$udid" ] || { echo "error: no available iOS>=16 simulator found" >&2; exit 1; }

echo "Simulator: $udid"
open -a Simulator
xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || true

# Build for the generic simulator destination (robust — no per-device matching),
# then install the product to the chosen sim.
echo "Building Donpa-iOS..."
xcodebuild -project Donpa.xcodeproj -scheme Donpa-iOS \
    -destination "generic/platform=iOS Simulator" \
    -derivedDataPath "$derived" -configuration Debug build \
    >/dev/null 2>&1 || {
    echo "build failed; re-running with full output:" >&2
    xcodebuild -project Donpa.xcodeproj -scheme Donpa-iOS \
        -destination "generic/platform=iOS Simulator" \
        -derivedDataPath "$derived" -configuration Debug build
    exit 1
}

app="$derived/Build/Products/Debug-iphonesimulator/Donpa Squad.app"
[ -d "$app" ] || { echo "error: built app not found at $app" >&2; exit 1; }

echo "Installing and launching $bundle_id"
xcrun simctl install "$udid" "$app"
xcrun simctl launch "$udid" "$bundle_id"
