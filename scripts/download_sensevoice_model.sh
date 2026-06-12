#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/models_dir.sh
source "$ROOT_DIR/scripts/models_dir.sh"

MODELS_DIR="$(models_dir)"
TARGET_DIR="$MODELS_DIR/sensevoice"
LEGACY_DIR="$ROOT_DIR/ThirdParty/sensevoice"
BASE_URL="https://huggingface.co/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/resolve/main"

mkdir -p "$TARGET_DIR"

if [[ -f "$TARGET_DIR/model.int8.onnx" && -f "$TARGET_DIR/tokens.txt" ]]; then
  echo "==> SenseVoice-Small already present at $TARGET_DIR"
  exit 0
fi

if [[ -f "$LEGACY_DIR/model.int8.onnx" && -f "$LEGACY_DIR/tokens.txt" ]]; then
  echo "==> Migrating SenseVoice-Small from $LEGACY_DIR to $TARGET_DIR"
  cp "$LEGACY_DIR/model.int8.onnx" "$TARGET_DIR/"
  cp "$LEGACY_DIR/tokens.txt" "$TARGET_DIR/"
  echo "==> Installed SenseVoice-Small to $TARGET_DIR"
  exit 0
fi

echo "==> Downloading SenseVoice-Small (int8) to $TARGET_DIR"
curl -L "$BASE_URL/model.int8.onnx" -o "$TARGET_DIR/model.int8.onnx"
curl -L "$BASE_URL/tokens.txt" -o "$TARGET_DIR/tokens.txt"

echo "==> Installed SenseVoice-Small to $TARGET_DIR"
