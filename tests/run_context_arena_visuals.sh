#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MOD_DIR="$(CDPATH= cd -- "${SCRIPT_DIR}/.." && pwd)"
ROOT_DIR="$(CDPATH= cd -- "${MOD_DIR}/../.." && pwd)"
OUT_DIR="${STADIUM2_ARENA_VISUAL_DIR:-/tmp/stadium2-context-arenas}"
GAME="${POKEPORT_GAME:-crystal}"
DRIVER="mods/STADIUM2_IMPORTER/tests/drivers/gen2_context_arena_visual.lua"

mkdir -p "${OUT_DIR}"

run_case() {
  local case_name="$1"
  printf 'Running contextual arena visual: %s\n' "${case_name}"
  if command -v xvfb-run >/dev/null 2>&1 && [[ -z "${DISPLAY:-}" ]]; then
    (cd "${ROOT_DIR}" && xvfb-run -a env \
      POKEPORT_GAME="${GAME}" \
      POKEPORT_DRIVER="${DRIVER}" \
      STADIUM2_ARENA_VISUAL_CASE="${case_name}" \
      STADIUM2_ARENA_VISUAL_DIR="${OUT_DIR}" \
      love .)
  else
    (cd "${ROOT_DIR}" && env \
      POKEPORT_GAME="${GAME}" \
      POKEPORT_DRIVER="${DRIVER}" \
      STADIUM2_ARENA_VISUAL_CASE="${case_name}" \
      STADIUM2_ARENA_VISUAL_DIR="${OUT_DIR}" \
      love .)
  fi
}

run_case wild
run_case fishing
run_case outdoor_trainer
run_case indoor_trainer
run_case gym

printf 'Contextual arena visual tests passed. Screenshots:\n  %s\n' "${OUT_DIR}"
