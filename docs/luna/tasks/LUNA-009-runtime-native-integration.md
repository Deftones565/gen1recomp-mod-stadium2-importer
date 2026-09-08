# LUNA-009: Integrate native objects, lifecycle, and materials

## Objective

Make the persistent battle-FX runtime own all three accepted state engines:
common particles, native-object scheduler slots, and lifecycle instances.

## Evidence and source of truth

- Accepted LUNA-004/005/006/007/008 modules and tests.
- `docs/luna/README.md` snapshot/diagnostic invariants.
- ROM requirement: yes.

## Owned paths

- `lib/stadium2_battle_fx_native.lua`
- `lib/stadium2_battle_fx_runtime.lua`
- `tests/stadium2_battle_fx_runtime_test.lua`
- `tests/stadium2_battle_fx_runtime_integration_test.lua`

## Forbidden paths

- ROM decoder/audit, evaluator/manager modules, resources, importer, battle,
  scene/viewer, and all other tests.

## Interface contract

`Native.execute` must preserve native-object `commandPointer`,
`encodedObjectRaw`, `delayOffset`, `encodedDelay`, and `resolution` on its
scheduled events without treating them as common particle descriptors.

`Runtime.new` accepts injected manager instances `nativeObjects` and
`lifecycle`, or creates conservative defaults from accepted modules using
`nativeObjectOptions` and `lifecycleOptions`. It also accepts `material` and
`materialOptions` evaluator overrides.

During trigger, common particle events remain in the existing Native births
path. Native-object events are enqueued exactly once with effect/program/event
context. Lifecycle dispatches spawn exactly one lifecycle instance with the
same context. Unsupported resolver/callback paths surface manager diagnostics;
the runtime must not additionally emit obsolete unconditional
`unsupported-native-object`/`unsupported-lifecycle` duplicates.

Each runtime tick advances each active common-particle motion/material state,
the native-object manager, and lifecycle manager exactly once in this order:
common particles, native objects, lifecycle. Material initializes once per
common particle and updates once per active tick. Evaluated material snapshots
are detached and renderer-facing.

Runtime snapshots include stable `nativeObjects`, `lifecycles`, and material
state, and merge new manager/evaluator diagnostics exactly once into the frozen
runtime stream. Snapshotting is pure. `release` releases both managers.
Preserve monotonic IDs, route behavior, accumulator, and host RNG isolation.

## Acceptance commands

From `/opt/git/gen1recomp`:

```sh
lua mods/STADIUM2_IMPORTER/tests/stadium2_battle_fx_runtime_test.lua
lua mods/STADIUM2_IMPORTER/tests/stadium2_battle_fx_runtime_integration_test.lua
STADIUM2_REQUIRE_ROM=1 \
LUNA_OWNED_PATHS="mods/STADIUM2_IMPORTER/lib/stadium2_battle_fx_native.lua mods/STADIUM2_IMPORTER/lib/stadium2_battle_fx_runtime.lua mods/STADIUM2_IMPORTER/tests/stadium2_battle_fx_runtime_test.lua mods/STADIUM2_IMPORTER/tests/stadium2_battle_fx_runtime_integration_test.lua" \
  mods/STADIUM2_IMPORTER/tools/run_battle_fx_worker_checks.sh
```

Tests prove exact-once scheduling/spawning/initialization/stepping, manager
context propagation, Native field retention, cross-engine order, diagnostic
deduplication, pure deep-copy snapshots, and release. Include a ROM-backed
fixture using one move with native objects and one lifecycle-routed move.

## Non-goals and risks

- No renderer or battle integration.
- No fallback external native/lifecycle/material behavior.

## Required handoff report

Use the standard task template and provide per-engine snapshot evidence.
