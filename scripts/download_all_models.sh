#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$ROOT_DIR/scripts/download_sherpa_onnx.sh"
"$ROOT_DIR/scripts/download_sensevoice_model.sh"
"$ROOT_DIR/scripts/download_vad_model.sh"
"$ROOT_DIR/scripts/download_punctuation_model.sh"
"$ROOT_DIR/scripts/download_whisper_refine_model.sh"

# shellcheck source=scripts/models_dir.sh
source "$ROOT_DIR/scripts/models_dir.sh"
echo "==> All Livescript models are in $(models_dir)"
