#!/usr/bin/env bash
# Builds Brim.app (and optionally a DMG) into ./build.
#   scripts/build.sh            # release build → build/Brim.app
#   scripts/build.sh --dmg      # also build/Brim-<version>.dmg
#   scripts/build.sh --install  # also copy to /Applications and launch
#
# Release settings (all optional, via environment):
#   VERSION=1.1                 marketing version (default 1.0)
#   WEBSITE_URL=https://…       where website/ is hosted; also sets the update feed to $WEBSITE_URL/appcast.json
#   UPDATE_FEED_URL=https://…   override the update feed
#   CHECKOUT_URL=https://…      "Buy" link (Paddle, Lemon Squeezy, Gumroad…)
#   NOTES="Fix A|Add B"         release notes for appcast.json, separated by |
#   FREE=1                      no trial/licensing even if .secrets/license-public.key exists
# Signing: uses $SIGN_IDENTITY, else the first "Apple Development"/"Developer ID" identity, else ad-hoc.
# A stable identity matters: macOS ties the Accessibility grant to the signature.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-1.0}"
BUILD="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
APP="build/Brim.app"

echo "→ Compiling (release)"
swift build -c release --arch arm64 --arch x86_64 2>/dev/null \
  || swift build -c release
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path 2>/dev/null || swift build -c release --show-bin-path)/Brim"

if [ ! -f Resources/AppIcon.icns ]; then
  echo "→ Rendering icon"
  mkdir -p .build
  swiftc scripts/IconTool/main.swift Sources/Brim/BrandArt.swift -o .build/icontool
  .build/icontool Resources
  iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns
  rm -rf Resources/AppIcon.iconset
fi

echo "→ Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Brim"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" Resources/Info.plist > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

PLIST="$APP/Contents/Info.plist"
WEBSITE_URL="${WEBSITE_URL:-}"
UPDATE_FEED_URL="${UPDATE_FEED_URL:-${WEBSITE_URL:+${WEBSITE_URL%/}/appcast.json}}"
PUBLIC_KEY=""
if [ -z "${FREE:-}" ] && [ -f .secrets/license-public.key ]; then PUBLIC_KEY="$(cat .secrets/license-public.key)"; fi
plutil -replace BrimLicensePublicKey -string "$PUBLIC_KEY" "$PLIST"
plutil -replace BrimUpdateFeedURL -string "$UPDATE_FEED_URL" "$PLIST"
plutil -replace BrimCheckoutURL -string "${CHECKOUT_URL:-}" "$PLIST"
plutil -replace BrimWebsiteURL -string "$WEBSITE_URL" "$PLIST"
echo "   licensing: $([ -n "$PUBLIC_KEY" ] && echo "on (14-day trial)" || echo "off (free)")"
echo "   updates:   ${UPDATE_FEED_URL:-off}"

IDENTITY="${SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
  IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | grep -E 'Developer ID Application|Apple Development' | head -1 | sed -E 's/.*"(.*)"/\1/' || true)"
fi
if [ -n "$IDENTITY" ]; then
  echo "→ Signing with: $IDENTITY"
  codesign --force --options runtime --timestamp=none --sign "$IDENTITY" "$APP"
else
  echo "→ Signing ad-hoc (Accessibility must be re-granted after each rebuild)"
  codesign --force --sign - "$APP"
fi
codesign --verify --strict "$APP"

if [[ " $* " == *" --dmg "* ]]; then
  DMG="build/Brim-$VERSION.dmg"
  echo "→ Packaging $DMG"
  STAGE="$(mktemp -d)"
  cp -R "$APP" "$STAGE/"
  ln -s /Applications "$STAGE/Applications"
  rm -f "$DMG"
  hdiutil create -volname "Brim" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
  rm -rf "$STAGE"
  cp "$DMG" website/Brim.dmg   # the website's download link
  mkdir -p website/downloads
  cp "$DMG" "website/downloads/Brim-$VERSION.dmg"

  echo "→ Writing website/appcast.json"
  SHA="$(shasum -a 256 "$DMG" | cut -d' ' -f1)"
  python3 -I - "$VERSION" "$BUILD" "$SHA" "${NOTES:-Improvements and fixes.}" > website/appcast.json <<'PY'
import json, sys, datetime
version, build, sha, notes = sys.argv[1:5]
print(json.dumps({
    "version": version,
    "build": int(build),
    "url": f"downloads/Brim-{version}.dmg",
    "sha256": sha,
    "date": datetime.date.today().isoformat(),
    "minimumSystemVersion": "13.0",
    "notes": [n.strip() for n in notes.split("|") if n.strip()],
}, indent=2))
PY
fi

if [[ " $* " == *" --install "* ]]; then
  echo "→ Installing to /Applications"
  pkill -x Brim 2>/dev/null || true
  rm -rf /Applications/Brim.app
  cp -R "$APP" /Applications/
  open /Applications/Brim.app
fi

echo "✓ Done: $APP"
