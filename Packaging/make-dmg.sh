#!/bin/bash
# Builds a standard "drag ShowClock.app to Applications" DMG from an
# already-built .app bundle. Requires `create-dmg` (brew install create-dmg).
set -euo pipefail

APP_PATH="${1:?Usage: make-dmg.sh <path-to-.app> <output-dmg-path>}"
DMG_PATH="${2:?Usage: make-dmg.sh <path-to-.app> <output-dmg-path>}"
APP_FILENAME="$(basename "$APP_PATH")"
VOLUME_NAME="$(basename "$APP_PATH" .app)"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKGROUND_IMAGE="$SCRIPT_DIR/dmg-background.png"

rm -f "$DMG_PATH"

# create-dmg's Finder-driven icon-layout step is known to sometimes report a
# non-zero exit even when the DMG was built successfully (a documented quirk,
# not specific to this project) — so the real success check is "did the file
# show up", not the exit code.
#
# Separately: create-dmg runs its own layout AppleScript against a randomized
# staging volume name (e.g. "dmg.XXXXXX"), then renames the volume to
# $VOLUME_NAME and compresses it. The background-picture reference it sets is
# bound to that staging name, so it silently dangles after the rename — on
# the final DMG, querying it throws "AppleEvent handler failed (-10000)",
# and the icon arrangement reverts to Finder's generic "arranged by name"
# default. Neither of those is visible from create-dmg's own output. So the
# layout/background step below doesn't trust create-dmg's pass at all — it
# re-applies everything itself, fresh, on the already-final-named volume.
create-dmg \
    --volname "$VOLUME_NAME" \
    --background "$BACKGROUND_IMAGE" \
    --window-size 500 320 \
    --icon-size 100 \
    --icon "$APP_FILENAME" 130 130 \
    --app-drop-link 370 130 \
    --hide-extension "$APP_FILENAME" \
    "$DMG_PATH" \
    "$APP_PATH" || true

if [ ! -f "$DMG_PATH" ]; then
    echo "create-dmg did not produce $DMG_PATH" >&2
    exit 1
fi

echo "Applying icon layout and background..."
RW_BASE="${DMG_PATH%.dmg}-rw"
rm -f "${RW_BASE}.dmg"
hdiutil convert "$DMG_PATH" -format UDRW -o "$RW_BASE"
RW_DMG="${RW_BASE}.dmg"

ATTACH_OUTPUT="$(hdiutil attach "$RW_DMG" -nobrowse)"
# Not the first "/dev/" line: that's the whole-disk GUID entry with no mount
# point (empty 3rd field). The line with the actual filesystem + mount point
# is the one containing "/Volumes/".
MOUNT_LINE="$(echo "$ATTACH_OUTPUT" | grep '/Volumes/')"
DEVICE="$(echo "$MOUNT_LINE" | awk -F'\t' '{print $1}' | xargs)"
MOUNT_POINT="$(echo "$MOUNT_LINE" | awk -F'\t' '{print $3}' | xargs)"

# create-dmg already copied the background image into .background/ on the
# volume — reuse that instead of copying it again.
BACKGROUND_FILENAME="$(basename "$BACKGROUND_IMAGE")"

# Addressing the volume via `disk "$VOLUME_NAME"` + `container window` (a
# relative reference resolved fresh in this script, not a frozen alias) is
# what avoids the dangling-reference problem described above: every property
# below is set directly against the volume under its real, final name.
osascript <<EOF
tell application "Finder"
    tell disk "$VOLUME_NAME"
        open
        delay 1
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {400, 100, 900, 420}
        set theViewOptions to the icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 100
        set background picture of theViewOptions to file ".background:$BACKGROUND_FILENAME"
        set position of item "$APP_FILENAME" of container window to {130, 130}
        set position of item "Applications" of container window to {370, 130}
        close
        open
        update without registering applications
        delay 2
        close
    end tell
end tell
EOF

sleep 1
hdiutil detach "$DEVICE"

rm -f "$DMG_PATH"
FINAL_BASE="${DMG_PATH%.dmg}-final"
rm -f "${FINAL_BASE}.dmg"
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$FINAL_BASE"
mv "${FINAL_BASE}.dmg" "$DMG_PATH"
rm -f "$RW_DMG"

echo "Built $DMG_PATH"
