# LUNA-002: Deterministic particle motion evaluator

## Objective

Create a pure evaluator for authored initial vectors, injected random-vector
specs, velocity, rotation, scale, and frame rules without owning runtime state.

## Non-goals

- Scheduling, routing, attachments, materials, rendering, or battle hooks.
- Guessing unresolved controller-pointer behavior.

## Evidence and source of truth

- Descriptor fields decoded in `lib/stadium2_battle_fx_rom.lua`.
- Fragment-79 routines `func_84105E9C` through `func_84107170`.
- ROM requirement: no; use synthetic fixed inputs and injected RNG.

## Owned paths

- `lib/stadium2_battle_fx_motion.lua`
- `tests/stadium2_battle_fx_motion_test.lua`

## Forbidden paths

- Existing battle-FX decoder/resource files and all integration/viewer files.
- Files owned by LUNA-001 and LUNA-003.

## Interface contract

Expose pure initialization and one-tick evaluation functions. Never call global
random functions. Unknown controller pointers return structured unsupported
diagnostics rather than fabricated motion. Inputs and outputs must be plain Lua
tables suitable for runtime snapshots.

## Acceptance commands

```sh
lua mods/STADIUM2_IMPORTER/tests/stadium2_battle_fx_motion_test.lua
LUNA_OWNED_PATHS="mods/STADIUM2_IMPORTER/lib/stadium2_battle_fx_motion.lua mods/STADIUM2_IMPORTER/tests/stadium2_battle_fx_motion_test.lua" \
  mods/STADIUM2_IMPORTER/tools/run_battle_fx_worker_checks.sh
```

## Required handoff

Use `docs/luna/TASK_TEMPLATE.md`. Include deterministic traces using two fixed
RNG sequences and an explicit list of unresolved controller addresses.
