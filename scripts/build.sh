#!/usr/bin/env bash
# Builds Brim.app (and optionally a DMG) into ./build.
#   scripts/build.sh            # release build → build/Brim.app
#   scripts/build.sh --dmg      # also build/Brim-<version>.dmg, build/Brim.dmg and website/appcast.json
#   scripts/build.sh --install  # also copy to /Applications and launch
#
# Release settings (all optional, via environment). Forks should set the first two to their own.
#   SOURCE_URL=https://…        the repository (default github.com/hukpo/brim); the DMG is downloaded
#                               from its GitHub release v$VERSION
#   WEBSITE_URL=https://…       where website/ is hosted; the update feed is $WEBSITE_URL/appcast.json
#   UPDATE_FEED_URL=https://…   override the update feed ("" turns updates off)
#   VERSION=1.1                 marketing version (default 1.0)
#   NOTES="Fix A|Add B"         release notes for appcast.json, separated by |
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
SOURCE_URL="${SOURCE_URL:-https://github.com/hukpo/brim}"
WEBSITE_URL="${WEBSITE_URL:-https://hukpo.github.io/brim}"
UPDATE_FEED_URL="${UPDATE_FEED_URL-${WEBSITE_URL%/}/appcast.json}"
plutil -replace BrimUpdateFeedURL -string "$UPDATE_FEED_URL" "$PLIST"
plutil -replace BrimSourceURL -string "$SOURCE_URL" "$PLIST"
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
  cp "$DMG" build/Brim.dmg   # the stable name the website links to (releases/latest/download/Brim.dmg)

  echo "→ Writing website/appcast.json"
  SHA="$(shasum -a 256 "$DMG" | cut -d' ' -f1)"
  python3 -I - "$VERSION" "$BUILD" "$SHA" "${NOTES:-Improvements and fixes.}" "${SOURCE_URL%/}" > website/appcast.json <<'PY'
import json, sys, datetime
version, build, sha, notes, source = sys.argv[1:6]
print(json.dumps({
    "version": version,
    "build": int(build),
    "url": f"{source}/releases/download/v{version}/Brim-{version}.dmg",
    "sha256": sha,
    "date": datetime.date.today().isoformat(),
    "minimumSystemVersion": "13.0",
    "notes": [n.strip() for n in notes.split("|") if n.strip()],
}, indent=2))
PY
  echo "   publish:   gh release create v$VERSION $DMG build/Brim.dmg, then push website/appcast.json"
fi

if [[ " $* " == *" --install "* ]]; then
  echo "→ Installing to /Applications"
  pkill -x Brim 2>/dev/null || true
  rm -rf /Applications/Brim.app
  cp -R "$APP" /Applications/
  open /Applications/Brim.app
fi

echo "✓ Done: $APP"
