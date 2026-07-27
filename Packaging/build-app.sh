#!/bin/bash
# Builds a release binary and assembles it into a proper ShowClock.app bundle
# in ./dist, ad-hoc signed (see the codesign step below — no Developer ID or
# paid account involved, that's a separate thing notarization would need).
set -euo pipefail

VERSION="${1:?Usage: build-app.sh <version, e.g. 1.0.0>}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

APP_NAME="ShowClock"
DIST_DIR="$REPO_ROOT/dist"
APP_DIR="$DIST_DIR/${APP_NAME}.app"

echo "Building release binary..."
swift build -c release

rm -rf "$DIST_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp ".build/release/${APP_NAME}" "$APP_DIR/Contents/MacOS/${APP_NAME}"
cp "Packaging/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"

sed "s/VERSION_PLACEHOLDER/${VERSION}/g" Packaging/Info.plist > "$APP_DIR/Contents/Info.plist"

# swiftc's linker ad-hoc-signs the raw executable at compile time, but that
# signature only covers the executable itself — assembled afterward into a
# .app with this script, Info.plist and Resources end up outside what it
# seals ("Info.plist=not bound", "Sealed Resources=none" per `codesign -dv`).
# On Apple Silicon, which requires every executable to carry *some* valid
# signature to run at all, Gatekeeper reports that mismatch as "is damaged
# and can't be opened" — not the milder "unidentified developer" warning,
# and not something right-click > Open can bypass. Re-signing the whole
# assembled bundle (still just ad-hoc, no identity/account needed) is what
# actually seals it correctly.
echo "Ad-hoc signing bundle..."
codesign --force --deep --sign - "$APP_DIR"

echo "Built $APP_DIR"
