#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_PATH="$DIST_DIR/Livescript.app"
DMG_PATH="$DIST_DIR/Livescript-local.dmg"
VOL_NAME="Livescript"

if [[ ! -d "$APP_PATH" ]]; then
  echo "App not found at $APP_PATH" >&2
  echo "Run scripts/build_release_local.sh first." >&2
  exit 1
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

cp -R "$APP_PATH" "$TMP_DIR/Livescript.app"
ln -s /Applications "$TMP_DIR/Applications"
rm -f "$DMG_PATH"

hdiutil create \
  -volname "$VOL_NAME" \
  -srcfolder "$TMP_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "DMG created: $DMG_PATH"
