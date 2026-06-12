#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_DIR="$ROOT_DIR/ThirdParty/sherpa-onnx"
VERSION="v1.12.6"
ARCHIVE="sherpa-onnx-${VERSION}-osx-universal2-static.tar.bz2"
URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/${VERSION}/${ARCHIVE}"

if [[ -f "$TARGET_DIR/lib/libsherpa-onnx-c-api.a" ]]; then
  echo "==> sherpa-onnx already present at $TARGET_DIR"
  exit 0
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "==> Downloading sherpa-onnx ${VERSION}"
curl -L "$URL" -o "$TMP_DIR/$ARCHIVE"
tar -xjf "$TMP_DIR/$ARCHIVE" -C "$TMP_DIR"

rm -rf "$TARGET_DIR"
mv "$TMP_DIR/sherpa-onnx-${VERSION}-osx-universal2-static" "$TARGET_DIR"

echo "==> Installed sherpa-onnx to $TARGET_DIR"
