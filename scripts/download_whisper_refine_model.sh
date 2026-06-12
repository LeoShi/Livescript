#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/models_dir.sh
source "$ROOT_DIR/scripts/models_dir.sh"

MODELS_DIR="$(models_dir)"
TARGET_REPO="$MODELS_DIR/models/argmaxinc/whisperkit-coreml"
VARIANT_DIR="distil-whisper_distil-large-v3"
TARGET_DIR="$TARGET_REPO/$VARIANT_DIR"

if [[ -d "$TARGET_DIR" ]] && ls "$TARGET_DIR"/MelSpectrogram*.mlmodelc >/dev/null 2>&1; then
  echo "==> distil-large-v3 refine model already present at $TARGET_DIR"
  exit 0
fi

mkdir -p "$TARGET_REPO"

if command -v huggingface-cli >/dev/null 2>&1; then
  echo "==> Downloading distil-large-v3 (refine) via huggingface-cli"
  huggingface-cli download argmaxinc/whisperkit-coreml \
    --include "$VARIANT_DIR/*" \
    --local-dir "$TARGET_REPO"
  echo "==> Installed refine model to $TARGET_DIR"
  exit 0
fi

echo "==> huggingface-cli not found."
echo "    Install: pip install huggingface_hub"
echo "    Or start Smart profile once — WhisperKit will download distil-large-v3 into:"
echo "    $TARGET_DIR"
