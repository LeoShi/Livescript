#!/usr/bin/env bash
# Shared default for on-disk model storage.
models_dir() {
  echo "${LIVESCRIPT_MODELS_DIR:-$HOME/workspace/models}"
}
