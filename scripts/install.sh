#!/bin/zsh
#
#  install.sh
#  ClipBoard
#
#  Builds a Release copy, replaces /Applications/ClipBoard.app, and opens it.
#  On its first run from /Applications the app turns on Launch at Login by itself.
#

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

xcodebuild build \
  -project ClipBoard.xcodeproj \
  -scheme ClipBoard \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build/DerivedData \
  -quiet

pkill -x ClipBoard 2>/dev/null || true
rm -rf /Applications/ClipBoard.app
cp -R build/DerivedData/Build/Products/Release/ClipBoard.app /Applications/
open /Applications/ClipBoard.app
echo "Installed /Applications/ClipBoard.app — press ⌘⇧V."
