#!/bin/bash
# Builds a release binary and assembles it into a proper ShowClock.app bundle
# in ./dist. Runs locally (for testing the bundling itself) and in CI (before
# signing/notarizing, which needs a Developer ID cert this script doesn't
# touch).
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

echo "Built $APP_DIR"
