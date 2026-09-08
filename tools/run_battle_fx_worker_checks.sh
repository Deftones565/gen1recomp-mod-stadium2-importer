#!/bin/sh
set -eu

caller_dir=$(pwd)
tool_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
mod_root=$(CDPATH= cd -- "$tool_dir/.." && pwd)
repo_root=$(CDPATH= cd -- "$mod_root/../.." && pwd)

if [ -n "${LUA_BIN:-}" ]; then
  lua_bin=$LUA_BIN
elif command -v luajit >/dev/null 2>&1; then
  lua_bin=luajit
elif command -v lua >/dev/null 2>&1; then
  lua_bin=lua
else
  echo "ERROR: neither luajit nor lua is available" >&2
  exit 127
fi

rom_path=${STADIUM2_ROM:-}
if [ -n "$rom_path" ]; then
  case "$rom_path" in
    /*) ;;
    *) rom_path="$caller_dir/$rom_path" ;;
  esac
fi

cd "$repo_root"

"$lua_bin" mods/STADIUM2_IMPORTER/tests/stadium2_options_test.lua
"$lua_bin" mods/STADIUM2_IMPORTER/tests/stadium2_core_test.lua

if [ -z "$rom_path" ] && [ -f "$mod_root/baseroms/stadium2.z64" ]; then
  rom_path="$mod_root/baseroms/stadium2.z64"
fi

if [ -n "$rom_path" ] && [ -f "$rom_path" ]; then
  # ROM-backed tests discovered by the generic lane need the same normalized
  # absolute path as the catalog audit below.
  export STADIUM2_ROM="$rom_path"
  STADIUM2_ROM="$rom_path" \
    "$lua_bin" mods/STADIUM2_IMPORTER/tests/stadium2_battle_fx_rom_audit.lua
elif [ "${STADIUM2_REQUIRE_ROM:-0}" = "1" ]; then
  if [ -n "$rom_path" ]; then
    echo "ERROR: required Stadium 2 ROM not found: $rom_path" >&2
  else
    echo "ERROR: Stadium 2 ROM is required; set STADIUM2_ROM" >&2
  fi
  exit 2
else
  if [ -n "$rom_path" ]; then
    echo "SKIP: Stadium 2 ROM audit (ROM not found: $rom_path)"
  else
    echo "SKIP: Stadium 2 ROM audit (STADIUM2_ROM is not set)"
  fi
fi

for test_path in "$mod_root"/tests/stadium2_battle_fx_*_test.lua; do
  [ -f "$test_path" ] || continue
  "$lua_bin" "mods/STADIUM2_IMPORTER/tests/$(basename -- "$test_path")"
done

for test_name in stadium2_gen1_battle_fx_test.lua \
    stadium2_gen2_battle_fx_integration_test.lua; do
  if [ -f "$mod_root/tests/$test_name" ]; then
    "$lua_bin" "mods/STADIUM2_IMPORTER/tests/$test_name"
  fi
done

for owned_path in ${LUNA_OWNED_PATHS:-}; do
  case "$owned_path" in
    *.lua)
      [ -f "$repo_root/$owned_path" ] || {
        echo "ERROR: claimed Lua path not found: $owned_path" >&2
        exit 2
      }
      "$lua_bin" -e 'assert(loadfile(arg[1]))' "$repo_root/$owned_path"
      ;;
  esac
done

sh -n "$mod_root/tools/run_battle_fx_worker_checks.sh"
git -C "$mod_root" diff --check
echo "battle-FX worker checks passed"
