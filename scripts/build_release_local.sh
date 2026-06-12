#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/Livescript.xcodeproj"
SCHEME="Livescript"
CONFIGURATION="Release"
DERIVED_DATA="$ROOT_DIR/dist/DerivedData"
DIST_DIR="$ROOT_DIR/dist"
APP_PATH="$DERIVED_DATA/Build/Products/$CONFIGURATION/Livescript.app"
OUTPUT_APP="$DIST_DIR/Livescript.app"

"$ROOT_DIR/scripts/download_all_models.sh"

echo "==> Building $SCHEME ($CONFIGURATION)"
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "platform=macOS" \
  -derivedDataPath "$DERIVED_DATA" \
  clean build

if [[ ! -d "$APP_PATH" ]]; then
  echo "Build completed but app bundle not found: $APP_PATH" >&2
  exit 1
fi

mkdir -p "$DIST_DIR"
rm -rf "$OUTPUT_APP"
cp -R "$APP_PATH" "$OUTPUT_APP"

# shellcheck source=scripts/models_dir.sh
source "$ROOT_DIR/scripts/models_dir.sh"
echo "==> Models directory: $(models_dir) (not bundled in app)"

echo "==> Verifying required privacy usage strings"
/usr/libexec/PlistBuddy -c "Print :NSMicrophoneUsageDescription" "$OUTPUT_APP/Contents/Info.plist" >/dev/null

echo
echo "Build successful."
echo "App bundle: $OUTPUT_APP"
