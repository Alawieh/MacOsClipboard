#!/bin/zsh
#
#  release.sh
#  ClipBoard
#
#  Builds the downloadable installer: build/release/ClipBoard-<version>.dmg (drag-to-Applications),
#  plus its SHA-256. Runs the gate audit first and refuses to package a red build.
#  The release is ad-hoc signed (no personal certificate inside), universal (Apple Silicon + Intel).
#

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "▸ Gate audit"
scripts/audit.sh gate > /dev/null || { echo "Gate audit failed; not packaging. See build/audit/."; exit 1; }

VERSION="$(xcodebuild -showBuildSettings -project ClipBoard.xcodeproj -scheme ClipBoard -configuration Release 2>/dev/null \
  | awk -F' = ' '/ MARKETING_VERSION = / { print $2; exit }')"
OUT="build/release"
DMG="$OUT/ClipBoard-$VERSION.dmg"
STAGE="$OUT/stage"

echo "▸ Building ClipBoard $VERSION (Release, universal, ad-hoc signed)"
xcodebuild build \
  -project ClipBoard.xcodeproj \
  -scheme ClipBoard \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath build/DerivedData \
  CODE_SIGN_IDENTITY=- \
  DEVELOPMENT_TEAM= \
  -quiet

APP="build/DerivedData/Build/Products/Release/ClipBoard.app"
codesign --verify --deep --strict "$APP"

echo "▸ Packaging $DMG"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "ClipBoard" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" > /dev/null
rm -rf "$STAGE"
shasum -a 256 "$DMG" | tee "$DMG.sha256"

echo "▸ Done: $DMG ($(lipo -archs "$APP/Contents/MacOS/ClipBoard"))"
