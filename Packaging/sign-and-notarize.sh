#!/bin/bash
# Signs the .app, builds a "drag to Applications" DMG from it, then
# notarizes and staples the DMG itself (not a zip) — the DMG is what gets
# distributed, so it's what needs to carry the notarization ticket.
#
# Requires DEVELOPER_ID_APPLICATION (the exact signing identity string, e.g.
# "Developer ID Application: Your Name (TEAMID1234)") and either:
#   - APPLE_API_KEY_PATH + APPLE_API_KEY_ID + APPLE_API_ISSUER (App Store
#     Connect API key, the recommended path — used in CI), or
#   - an Apple ID + app-specific password + team ID already configured via
#     `xcrun notarytool store-credentials` under a profile named "notarize"
#     (handy for testing this script locally without wiring up API key env
#     vars — see docs/release-process.md).
set -euo pipefail

APP_PATH="${1:?Usage: sign-and-notarize.sh <path-to-.app>}"
IDENTITY="${DEVELOPER_ID_APPLICATION:?Set DEVELOPER_ID_APPLICATION to your signing identity}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DMG_PATH="${APP_PATH%.app}.dmg"

echo "Signing $APP_PATH..."
codesign --force --deep --options runtime --timestamp --sign "$IDENTITY" "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

echo "Building DMG..."
"$SCRIPT_DIR/make-dmg.sh" "$APP_PATH" "$DMG_PATH"

echo "Submitting for notarization..."
if [ -n "${APPLE_API_KEY_PATH:-}" ]; then
    xcrun notarytool submit "$DMG_PATH" \
        --key "$APPLE_API_KEY_PATH" \
        --key-id "${APPLE_API_KEY_ID:?}" \
        --issuer "${APPLE_API_ISSUER:?}" \
        --wait
else
    xcrun notarytool submit "$DMG_PATH" --keychain-profile "notarize" --wait
fi

echo "Stapling..."
xcrun stapler staple "$DMG_PATH"

echo "Signed, notarized, and stapled: $DMG_PATH"
