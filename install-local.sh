#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DATA_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}"
DEFAULT_TARGET="${DATA_HOME}/pokemon-love2d/mods/STADIUM2_IMPORTER"
TARGET_DIR="${1:-${DEFAULT_TARGET}}"

if [[ ! -f "${SCRIPT_DIR}/manifest.json" ]]; then
  printf 'error: run this script from a Stadium 2 Importer source checkout\n' >&2
  exit 1
fi

if [[ ! -f "${TARGET_DIR}/manifest.json" ]]; then
  printf 'error: installed Stadium 2 Importer was not found at:\n  %s\n' \
    "${TARGET_DIR}" >&2
  printf 'Import it once through the launcher, or pass its directory as argument 1.\n' >&2
  exit 1
fi

if ! command -v rsync >/dev/null 2>&1; then
  printf 'error: rsync is required for the safe in-place update\n' >&2
  exit 1
fi

# Update only distributable mod files. Never copy, remove, or replace the
# launcher-managed ROM, validation marker, generated caches, arena dumps, or
# development metadata. Omitting --delete also preserves any launcher-owned
# files introduced by newer engine versions.
rsync -a --itemize-changes \
  --exclude='/.git/' \
  --exclude='/.agents/' \
  --exclude='/.codex/' \
  --exclude='/.gitignore' \
  --exclude='/.modkitignore' \
  --exclude='/install-local.sh' \
  --exclude='/baseroms/' \
  --exclude='/build/' \
  --exclude='/tests/' \
  --exclude='/stadium2_arena_dump/' \
  "${SCRIPT_DIR}/" "${TARGET_DIR}/"

printf 'Updated Stadium 2 Importer in:\n  %s\n' "${TARGET_DIR}"
if [[ -f "${TARGET_DIR}/baseroms/stadium2.z64" ]]; then
  printf 'The imported Stadium 2 ROM was preserved; no reimport is required.\n'
else
  printf 'Warning: no imported Stadium 2 ROM exists in this installation.\n' >&2
fi
