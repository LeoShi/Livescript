#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/models_dir.sh
source "$ROOT_DIR/scripts/models_dir.sh"

MODELS_DIR="$(models_dir)"
TARGET_DIR="$MODELS_DIR/vad"
TARGET_FILE="$TARGET_DIR/silero_vad.onnx"
MIN_BYTES=100000
VAD_URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx"

mkdir -p "$TARGET_DIR"

if [[ -f "$TARGET_FILE" ]]; then
  size=$(stat -f%z "$TARGET_FILE" 2>/dev/null || stat -c%s "$TARGET_FILE")
  if [[ "$size" -ge "$MIN_BYTES" ]]; then
    echo "==> VAD model already present at $TARGET_DIR"
    exit 0
  fi
  echo "==> Removing invalid VAD model (${size} bytes) at $TARGET_FILE"
  rm -f "$TARGET_FILE"
fi

echo "==> Downloading Silero VAD model to $TARGET_DIR"
curl -L "$VAD_URL" -o "$TARGET_FILE"

size=$(stat -f%z "$TARGET_FILE" 2>/dev/null || stat -c%s "$TARGET_FILE")
if [[ "$size" -lt "$MIN_BYTES" ]]; then
  echo "VAD download failed (got ${size} bytes). Check network and retry." >&2
  rm -f "$TARGET_FILE"
  exit 1
fi

echo "==> Installed VAD model to $TARGET_DIR"
