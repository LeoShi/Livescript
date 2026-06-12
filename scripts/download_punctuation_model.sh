#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/models_dir.sh
source "$ROOT_DIR/scripts/models_dir.sh"

MODELS_DIR="$(models_dir)"
TARGET_DIR="$MODELS_DIR/punctuation"
TARGET_FILE="$TARGET_DIR/model.onnx"
MIN_BYTES=100000
ARCHIVE="sherpa-onnx-punct-ct-transformer-zh-en-vocab272727-2024-04-12-int8.tar.bz2"
ARCHIVE_URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/punctuation-models/$ARCHIVE"

mkdir -p "$TARGET_DIR"

if [[ -f "$TARGET_FILE" ]]; then
  size=$(stat -f%z "$TARGET_FILE" 2>/dev/null || stat -c%s "$TARGET_FILE")
  if [[ "$size" -ge "$MIN_BYTES" ]]; then
    echo "==> Punctuation model already present at $TARGET_DIR"
    exit 0
  fi
  echo "==> Removing invalid punctuation model (${size} bytes) at $TARGET_DIR"
  rm -f "$TARGET_DIR/model.onnx" "$TARGET_DIR/tokens.json"
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

echo "==> Downloading punctuation model archive"
curl -L "$ARCHIVE_URL" -o "$tmpdir/$ARCHIVE"
tar -xjf "$tmpdir/$ARCHIVE" -C "$tmpdir"

model_path="$(find "$tmpdir" \( -name model.onnx -o -name model.int8.onnx \) -print -quit)"
if [[ -z "$model_path" ]]; then
  echo "Could not find model.onnx in $ARCHIVE" >&2
  exit 1
fi

src_dir="$(dirname "$model_path")"
cp "$model_path" "$TARGET_DIR/model.onnx"
if [[ -f "$src_dir/tokens.json" ]]; then
  cp "$src_dir/tokens.json" "$TARGET_DIR/tokens.json"
fi

size=$(stat -f%z "$TARGET_FILE" 2>/dev/null || stat -c%s "$TARGET_FILE")
if [[ "$size" -lt "$MIN_BYTES" ]]; then
  echo "Punctuation download failed (got ${size} bytes)." >&2
  rm -f "$TARGET_FILE"
  exit 1
fi

echo "==> Installed punctuation model to $TARGET_DIR"
