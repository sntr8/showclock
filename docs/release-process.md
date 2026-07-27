# Release process

## How a release happens

1. Merge whatever you want released into `main`. `ci.yml` builds on every push/PR — this is just a build check, it never publishes anything.
2. When you're ready to cut a release: `git tag v1.0.0 && git push origin v1.0.0` (semver, `v` prefix required — that's what `release.yml`'s trigger matches on).
3. `release.yml` builds a release binary, bundles it into `ShowClock.app`, builds a standard "drag to Applications" `ShowClock.dmg` from it (via `create-dmg`), and publishes it to GitHub Releases with auto-generated notes (from merged PR titles since the last tag) plus a fixed disclaimer about Gatekeeper (see below).
4. Recipients: download the DMG, double-click to mount it, drag ShowClock into Applications. Since the build isn't signed or notarized, the **first** launch will be blocked by Gatekeeper ("Apple could not verify ShowClock is free of malware") — right-click (or Control-click) `ShowClock.app` → **Open** → **Open** again in the confirmation dialog. Only needed once per machine.

Version numbers are taken from the tag (`v1.2.3` → app version `1.2.3`), not tracked anywhere else — there's no version number to bump in a file before tagging.

## Why unsigned

Code signing with a "Developer ID Application" certificate, and notarization, both require a paid Apple Developer Program membership ($99/year) — this is separate from (and required regardless of) App Store distribution. This project doesn't have one, so the release pipeline doesn't attempt either. A free Apple ID only gets you an "Apple Development" certificate, which is for running/debugging your own builds on your own registered devices via Xcode — it doesn't help with Gatekeeper for other people's machines at all, so there's no point using it here.

## Testing the packaging locally before relying on CI

`Packaging/build-app.sh` just builds and bundles — no signing, safe to run anytime:

```
./Packaging/build-app.sh 1.0.0-test
open dist/ShowClock.app
```

`Packaging/make-dmg.sh` builds the drag-to-Applications DMG (needs `brew install create-dmg`):

```
./Packaging/make-dmg.sh dist/ShowClock.app dist/ShowClock.dmg
open dist/ShowClock.dmg
```

The background image (`Packaging/dmg-background.png`, with the arrow between the icon positions) is a static, committed asset — regenerate it by hand in something like Preview/Sketch/Figma if it ever needs to change, matching the `--icon`/`--app-drop-link` coordinates in `make-dmg.sh` (currently 130,130 and 370,130 in a 500×320 window). It has to be exactly 500×320 *pixels* (not the 1000×640 a Retina screenshot/export would produce) — create-dmg has no `@2x` convention for `--background`, so a 2x image renders at double size/wrong scale.

The app icon (`Packaging/AppIcon.icns`, built from `Packaging/AppIcon-source.png`) is also a static, committed asset. To regenerate it after changing the source art:

```
mkdir AppIcon.iconset
for size in 16 32 128 256 512; do
  sips -z $size $size Packaging/AppIcon-source.png --out "AppIcon.iconset/icon_${size}x${size}.png"
  sips -z $((size*2)) $((size*2)) Packaging/AppIcon-source.png --out "AppIcon.iconset/icon_${size}x${size}@2x.png"
done
iconutil -c icns AppIcon.iconset -o Packaging/AppIcon.icns
rm -rf AppIcon.iconset
```

## Notes

- Switching from the raw `swift run` executable to a proper `.app` bundle changes `UserDefaults.standard`'s effective domain from the bare process name (`ShowClock`) to the bundle identifier (`com.sntr8.ShowClock`, set in `Packaging/Info.plist`). Existing dev/test settings under the old domain won't carry over — a fresh install of the bundled app just starts with defaults, which is expected.
- `release.yml` needs `contents: write` permission (already set) to publish releases via `gh release create`.
- `make-dmg.sh`'s Finder-layout step (icon positions, arrangement, background) doesn't trust `create-dmg`'s own AppleScript pass to have stuck — it re-applies everything itself directly against the final-named volume. This isn't defensive-for-no-reason: `create-dmg` binds its background-picture reference to a temporary staging volume name that gets renamed during compression, silently dangling the reference and reverting the arrangement to Finder's generic default. If the DMG's layout or background is ever wrong again, this is the first thing to check.

## If you later get a paid Developer ID (not currently used)

`Packaging/sign-and-notarize.sh` still exists and works if this ever changes — it signs the `.app`, builds the DMG, notarizes and staples it. It's just not wired into `release.yml` right now. To bring it back:

1. Get a **Developer ID Application** certificate (Xcode → Settings → Accounts → your Apple ID → Manage Certificates → **+** → Developer ID Application) — requires the paid membership.
2. Export it from Keychain Access as a `.p12`, base64-encode it (`base64 -i DeveloperIDApplication.p12 | pbcopy`), and add as secrets `DEVELOPER_ID_CERTIFICATE_P12` + `DEVELOPER_ID_CERTIFICATE_PASSWORD` (the export password, picked by you).
3. Add `DEVELOPER_ID_APPLICATION_IDENTITY` — the exact identity string from `security find-identity -v -p codesigning`, e.g. `Developer ID Application: Your Name (TEAMID1234)`.
4. Add `KEYCHAIN_PASSWORD` — any random string (`openssl rand -base64 24`), only used for a throwaway CI keychain.
5. Generate an App Store Connect API key (appstoreconnect.apple.com → Users and Access → Integrations → Keys, needs Admin role) for notarization. Download the `.p8` immediately (one-time download), base64-encode it, add as `APPLE_API_KEY_P8_BASE64`, plus `APPLE_API_KEY_ID` and `APPLE_API_ISSUER` from that same page.
6. In `release.yml`, replace the "Build DMG" step with the certificate-import + `sign-and-notarize.sh` steps (see git history for the exact steps this file had before — `git log -p -- .github/workflows/release.yml`), and drop the Gatekeeper disclaimer from the release notes.
