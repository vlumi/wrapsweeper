#!/usr/bin/env bash
# Archive, export, and upload an app to App Store Connect — the whole local
# release lane (the ROADMAP's "manual for v0.1, one local lane run by hand").
#
# Usage:
#   Scripts/distribute.sh ios            # archive → export → upload iOS
#   Scripts/distribute.sh macos          # same for macOS
#   Scripts/distribute.sh ios --no-upload    # build the .ipa/.pkg, skip the upload
#   Scripts/distribute.sh ios --upload-only  # upload the already-built dist/ package
#
# Requires (one-time):
#   • A paid Apple Developer account (you already upload via Xcode).
#   • An App Store Connect API key: App Store Connect → Users and Access →
#     Integrations → App Store Connect API → generate (App Manager role).
#       - Put the downloaded key at ~/.appstoreconnect/private_keys/AuthKey_<KEYID>.p8
#       - Copy Scripts/.asc-config.example → Scripts/.asc-config and fill in the
#         Key ID + Issuer ID (both gitignored / outside the repo).
# Signing is automatic (matches Xcode's Organizer); no cert/profile to install.
set -euo pipefail

cd "$(dirname "$0")/.."

platform="${1:-}"
upload=1          # 0 = build only, skip upload
build=1           # 0 = upload-only, skip archive/export
shift || true
while [ $# -gt 0 ]; do
    case "$1" in
        --no-upload) upload=0 ;;
        --upload-only) build=0 ;;
        *) echo "error: unknown argument '$1'" >&2; exit 2 ;;
    esac
    shift
done
[ "$upload" -eq 1 ] || [ "$build" -eq 1 ] \
    || { echo "error: --no-upload and --upload-only are mutually exclusive." >&2; exit 2; }

case "$platform" in
    ios)   scheme="Donpa-iOS";   destination="generic/platform=iOS";   ext="ipa" ;;
    macos) scheme="Donpa-macOS"; destination="generic/platform=macOS"; ext="pkg" ;;
    *) echo "usage: distribute.sh <ios|macos> [--no-upload|--upload-only]" >&2; exit 2 ;;
esac

out="dist/${platform}"
archive="${out}/Donpa-${platform}.xcarchive"

if [ "$build" -eq 1 ]; then
    project="Donpa.xcodeproj"
    [ -d "$project" ] || { echo "error: $project missing — run Scripts/generate.sh first." >&2; exit 1; }
    rm -rf "$out"
    mkdir -p "$out"

    echo "▶︎ Archiving ${scheme}…"
    xcodebuild archive \
        -project "$project" \
        -scheme "$scheme" \
        -destination "$destination" \
        -archivePath "$archive" \
        -allowProvisioningUpdates

    echo "▶︎ Exporting (.${ext})…"
    xcodebuild -exportArchive \
        -archivePath "$archive" \
        -exportPath "$out" \
        -exportOptionsPlist Scripts/ExportOptions.plist \
        -allowProvisioningUpdates
fi

# The exported package's name varies (Xcode names it after the product); find it.
# Tolerate a missing dir (upload-only with nothing built) so the check below gives
# the helpful message rather than find's raw error.
pkg="$( [ -d "$out" ] && /usr/bin/find "$out" -maxdepth 1 -name "*.${ext}" | head -1 || true )"
[ -n "$pkg" ] || {
    if [ "$build" -eq 0 ]; then
        echo "error: no .${ext} in $out to upload — run a build (e.g. make release-build) first." >&2
    else
        echo "error: no .${ext} produced in $out" >&2
    fi
    exit 1
}
echo "  → $pkg"

if [ "$upload" -eq 0 ]; then
    echo "✓ Built $pkg (upload skipped)."
    exit 0
fi

# Load the API key IDs (gitignored). The .p8 is auto-discovered by Key ID from
# ~/.appstoreconnect/private_keys/.
config="Scripts/.asc-config"
[ -f "$config" ] || {
    echo "error: $config missing. Copy Scripts/.asc-config.example to it and fill in" >&2
    echo "       your ASC API Key ID + Issuer ID (see this script's header)." >&2
    exit 1
}
# shellcheck disable=SC1090
. "$config"
: "${ASC_KEY_ID:?set ASC_KEY_ID in $config}"
: "${ASC_ISSUER_ID:?set ASC_ISSUER_ID in $config}"

echo "▶︎ Uploading to App Store Connect…"
xcrun altool --upload-app \
    --type "$([ "$platform" = ios ] && echo ios || echo macos)" \
    --file "$pkg" \
    --apiKey "$ASC_KEY_ID" \
    --apiIssuer "$ASC_ISSUER_ID"

echo "✓ Uploaded ${platform} build to App Store Connect (processing takes a few min)."
