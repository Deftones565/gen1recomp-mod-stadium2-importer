# LUNA-001: Persistent battle-FX scheduler

## Objective

Create the persistent, deterministic 30 Hz runtime that spawns common particles
once, advances their ages, expires them, and returns stable snapshots.

## Non-goals

- Motion integration beyond zero/default state.
- Native-object or lifecycle execution.
- Rendering and battle integration.
- Changes to ROM parsing or resource extraction.

## Evidence and source of truth

- `lib/stadium2_battle_fx_native.lua`: program execution and birth selection.
- `tests/stadium2_battle_fx_rom_audit.lua`: Fire Punch timing invariants.
- ROM requirement: no for the targeted unit test; optional for the full check.

## Owned paths

- `lib/stadium2_battle_fx_runtime.lua`
- `tests/stadium2_battle_fx_runtime_test.lua`

## Forbidden paths

- All existing `lib/stadium2_battle_fx_*.lua` files.
- `main.lua`, `lib/importer.lua`, battle/scene files, and visual viewers.
- Files owned by LUNA-002 and LUNA-003.

## Interface contract

Implement the `Runtime.new`, `trigger`, `step`, `update`, `snapshot`, and
`release` contract in `docs/luna/README.md`. Use injected catalog/program
fixtures and `Native.execute`/`Native.births`. Snapshot order is
effect ID, scheduler index, generation, particle index.

Accept the frozen `lifetimeResolver` dependency. Do not derive a fallback from
ambiguous descriptor fields. Use monotonic non-reused IDs, caller-owned snapshot
copies, the shared diagnostic schema, and the documented accumulator behavior.

Unsupported lifecycle and native-object dispatches must be retained as explicit
diagnostics; they must never be silently converted into particles.

## Acceptance commands

```sh
lua mods/STADIUM2_IMPORTER/tests/stadium2_battle_fx_runtime_test.lua
LUNA_OWNED_PATHS="mods/STADIUM2_IMPORTER/lib/stadium2_battle_fx_runtime.lua mods/STADIUM2_IMPORTER/tests/stadium2_battle_fx_runtime_test.lua" \
  mods/STADIUM2_IMPORTER/tools/run_battle_fx_worker_checks.sh
```

## Required handoff

Use `docs/luna/TASK_TEMPLATE.md`. Include fixed-step snapshots for frames 0, 1,
2, and expiry, plus evidence that drawing/snapshotting does not create particles.
