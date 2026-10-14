#!/bin/bash
#
#  get.sh
#  ClipBoard
#
#  One-line installer: downloads the latest ClipBoard release from GitHub and puts it in
#  /Applications. Usage:
#    curl -fsSL https://raw.githubusercontent.com/Alawieh/MacOsClipboard/main/scripts/get.sh | bash
#

set -euo pipefail

REPO="Alawieh/MacOsClipboard"
APP_NAME="ClipBoard.app"
TMP="$(mktemp -d)"
trap 'hdiutil detach "$TMP/mount" -quiet 2>/dev/null || true; rm -rf "$TMP"' EXIT

echo "→ Finding the latest ClipBoard release…"
DMG_URL="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
  | grep -o '"browser_download_url": *"[^"]*\.dmg"' | head -1 | sed 's/.*"\(https[^"]*\)"/\1/')"
if [ -z "$DMG_URL" ]; then
  echo "Couldn't find a .dmg in the latest release of $REPO." >&2
  exit 1
fi

echo "→ Downloading $(basename "$DMG_URL")…"
curl -fL --progress-bar "$DMG_URL" -o "$TMP/ClipBoard.dmg"

echo "→ Installing to /Applications…"
mkdir -p "$TMP/mount"
hdiutil attach "$TMP/ClipBoard.dmg" -nobrowse -readonly -mountpoint "$TMP/mount" -quiet
pkill -x ClipBoard 2>/dev/null || true
rm -rf "/Applications/$APP_NAME"
cp -R "$TMP/mount/$APP_NAME" /Applications/
xattr -dr com.apple.quarantine "/Applications/$APP_NAME" 2>/dev/null || true

open "/Applications/$APP_NAME"
echo "✓ ClipBoard is installed and running. Press ⌘⇧V to open your clipboard history."
