#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_APP="$ROOT_DIR/dist/Livescript.app"
INSTALL_APP="/Applications/Livescript.app"

"$ROOT_DIR/scripts/run_unit_tests.sh"
"$ROOT_DIR/scripts/download_all_models.sh"
"$ROOT_DIR/scripts/build_release_local.sh"

if [[ ! -d "$DIST_APP" ]]; then
  echo "Built app not found at $DIST_APP" >&2
  exit 1
fi

echo "==> Installing to $INSTALL_APP"
if pgrep -xq Livescript; then
  echo "==> Quitting running Livescript"
  osascript -e 'quit app "Livescript"' || true
  sleep 1
fi

rm -rf "$INSTALL_APP"
cp -R "$DIST_APP" "$INSTALL_APP"

echo "==> Launching Livescript"
open "$INSTALL_APP"

echo
echo "Installed and launched: $INSTALL_APP"
