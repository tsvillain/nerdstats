#!/usr/bin/env bash
# Builds the universal release NerdStats.app and packages it into a compressed, read-only
# drag-to-install disk image at build/NerdStats-<version>.dmg.
#
# The version comes from Resources/Info.plist (CFBundleShortVersionString) unless VERSION
# is set, e.g. VERSION=1.2.0 scripts/build-dmg.sh (a leading "v" is stripped, so a git tag
# such as v1.2.0 works as-is). Only tools that ship with macOS/Xcode are used.
#
# Without an Apple Developer ID the app is ad-hoc signed only, so Gatekeeper asks users to
# allow it once; the DMG includes a short how-to for that.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLIST="$ROOT/Resources/Info.plist"
VERSION="${VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")}"
VERSION="${VERSION#v}"
if [[ ! "$VERSION" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]]; then
  echo "error: version '$VERSION' must look like 1.2 or 1.2.3" >&2
  exit 1
fi
export VERSION

APP="$ROOT/build/NerdStats.app"
DMG="$ROOT/build/NerdStats-$VERSION.dmg"
RW_DMG="$ROOT/build/NerdStats-$VERSION-rw.dmg"
STAGING="$ROOT/build/dmg-staging"

"$ROOT/scripts/build-app.sh" release

echo "==> Verifying signature"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "==> Staging disk image contents"
rm -rf "$STAGING"
mkdir -p "$STAGING"
ditto "$APP" "$STAGING/NerdStats.app"
ln -s /Applications "$STAGING/Applications"
cat > "$STAGING/How to open NerdStats.txt" <<TXT
NerdStats $VERSION

INSTALL
1. Drag NerdStats.app onto the Applications folder in this window.
2. Eject this disk image.
3. Open NerdStats from your Applications folder. It lives in the menu bar (no Dock icon).

FIRST LAUNCH: "NerdStats cannot be opened" / "Apple could not verify"
NerdStats is not signed with an Apple Developer ID, so macOS blocks it the first time.
You only need to allow it once:
1. Try to open NerdStats and click Done (or OK) on the warning.
2. Open System Settings > Privacy & Security.
3. Scroll down to the Security section and click "Open Anyway" next to the NerdStats message.
4. Confirm with "Open Anyway" and your password or Touch ID.
After that NerdStats opens normally, including at login.

ADVANCED ALTERNATIVE
Instead of the steps above, you can remove the download quarantine flag in Terminal:
    xattr -dr com.apple.quarantine /Applications/NerdStats.app
Only do this for a copy you downloaded from the official NerdStats releases.

LAUNCH AT LOGIN
NerdStats starts at login by default; change it in NerdStats Settings. Keep the app in
/Applications so macOS can find it at login.
TXT

# Finder shows a volume icon only when the disk image root carries .VolumeIcon.icns
# *and* has the "custom icon" Finder flag, which can only be set on a writable,
# mounted volume - hence the writable image that is compressed at the end.
cp "$ROOT/Resources/AppIcon.icns" "$STAGING/.VolumeIcon.icns"

echo "==> Creating $DMG"
rm -f "$DMG" "$RW_DMG"
hdiutil create -volname "NerdStats $VERSION" -srcfolder "$STAGING" -fs HFS+ \
  -format UDRW -ov "$RW_DMG"
MOUNT="$(mktemp -d)"
hdiutil attach "$RW_DMG" -nobrowse -readwrite -mountpoint "$MOUNT" >/dev/null
# Byte 8 of a folder's FinderInfo holds kHasCustomIcon (0x04 of the high flags byte).
xattr -wx com.apple.FinderInfo \
  "00 00 00 00 00 00 00 00 04 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00" \
  "$MOUNT"
hdiutil detach "$MOUNT" >/dev/null
rmdir "$MOUNT"
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null
hdiutil verify "$DMG"
rm -f "$RW_DMG"
rm -rf "$STAGING"

echo "==> Done: $DMG"
