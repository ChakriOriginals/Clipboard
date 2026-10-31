#!/usr/bin/env bash
# Packages build/Clipboard.app (from `make app`) into a zip with a SHA-256 checksum.
#
# Default: ad-hoc signed (what `make app` produces). Gatekeeper will quarantine it; see README.
# Developer ID + notarization runs only when all of these are set:
#   DEVELOPER_ID_APPLICATION   e.g. "Developer ID Application: Jane Doe (TEAMID)" (in the keychain)
#   NOTARY_APPLE_ID, NOTARY_TEAM_ID, NOTARY_PASSWORD (app-specific password)
set -euo pipefail
cd "$(dirname "$0")/.."

app="build/Clipboard.app"
[[ -d "$app" ]] || { echo "Missing $app — run 'make app' first." >&2; exit 1; }
version=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$app/Contents/Info.plist")
zip="build/Clipboard-$version.zip"

if [[ -n "${DEVELOPER_ID_APPLICATION:-}" ]]; then
    echo "Signing with Developer ID…"
    codesign --force --deep --options runtime --timestamp \
        --entitlements Clipboard/Resources/Clipboard.entitlements --sign "$DEVELOPER_ID_APPLICATION" "$app"
fi
codesign --verify --strict --verbose=2 "$app"
if codesign -d --entitlements :- "$app" 2>/dev/null | grep -q "get-task-allow"; then
    echo "Refusing to package: build carries the get-task-allow debugging entitlement." >&2
    exit 1
fi
if nm "$app/Contents/MacOS/Clipboard" 2>/dev/null | grep -q "__llvm_profile"; then
    echo "Refusing to package: build is instrumented for code coverage." >&2
    exit 1
fi

rm -f "$zip"
ditto -c -k --keepParent "$app" "$zip"

if [[ -n "${DEVELOPER_ID_APPLICATION:-}" && -n "${NOTARY_APPLE_ID:-}" && -n "${NOTARY_TEAM_ID:-}" && -n "${NOTARY_PASSWORD:-}" ]]; then
    echo "Notarizing…"
    xcrun notarytool submit "$zip" --apple-id "$NOTARY_APPLE_ID" --team-id "$NOTARY_TEAM_ID" \
        --password "$NOTARY_PASSWORD" --wait
    xcrun stapler staple "$app"
    rm -f "$zip"
    ditto -c -k --keepParent "$app" "$zip"
    spctl --assess --type execute --verbose "$app"
else
    echo "Not notarized (ad-hoc build). Users must approve it in Gatekeeper — see README."
fi

shasum -a 256 "$zip" | tee "$zip.sha256"
