# LUNA-007: Lifecycle metadata and persistent callback kernel

## Objective

Represent all 30 lifecycle families losslessly and implement only the state,
counter gates, termination rules, and draw-command evidence proven in the ROM.

## Evidence and source of truth

- `docs/luna/research/lifecycle-families.md`.
- Tables `0x84183700`, `0x84183778`, `0x841837F0`.
- Callback ranges `0x84156BD4..0x84159D0C`.
- ROM requirement: yes.

## Owned paths

- `lib/stadium2_battle_fx_lifecycle.lua`
- `tests/stadium2_battle_fx_lifecycle_test.lua`
- `tests/stadium2_battle_fx_lifecycle_rom_test.lua`

## Forbidden paths

- ROM decoder/audit, runtime, Native, motion, attachment, resources, importer,
  scene/viewer, and other workers' files.

## Interface contract

Expose immutable metadata for all 30 families: callback addresses, empty flag,
known signed-16 counter address, proven termination threshold, draw gate, and
family grouping. Do not give unresolved helpers semantic names.

Create a persistent lifecycle manager with injected phase resolver
`callback(phase,address,instance,context)`. Spawning an empty row is a safe
no-op diagnostic; a non-empty row gets a monotonic ID and copied context.
Advance at 30 Hz in stable ID order. Apply only proven counter increment,
phase/modulo gates, ordering, and direct `-1` termination for families 12, 17,
and 20. Any result owned by an unresolved helper comes only from the injected
resolver. Without one, retain the instance and emit a deduplicated diagnostic.

Draw snapshots for eligible non-empty families contain exact command words
`0xDA380003` and `0x841A4D08`, the family draw-helper address, instance ID,
and raw context. Family 12 emits no packet below counter 2. A packet is
evidence for native dispatch—not portable geometry—and must be labelled as
requiring its unresolved draw helper.

Use frozen-schema diagnostics, stable deep-copy snapshots, explicit release,
and no host RNG or invented side/resource/attachment behavior.

## Acceptance commands

From `/opt/git/gen1recomp`:

```sh
lua mods/STADIUM2_IMPORTER/tests/stadium2_battle_fx_lifecycle_test.lua
STADIUM2_ROM=mods/STADIUM2_IMPORTER/baseroms/stadium2.z64 \
  lua mods/STADIUM2_IMPORTER/tests/stadium2_battle_fx_lifecycle_rom_test.lua
STADIUM2_REQUIRE_ROM=1 \
LUNA_OWNED_PATHS="mods/STADIUM2_IMPORTER/lib/stadium2_battle_fx_lifecycle.lua mods/STADIUM2_IMPORTER/tests/stadium2_battle_fx_lifecycle_test.lua mods/STADIUM2_IMPORTER/tests/stadium2_battle_fx_lifecycle_rom_test.lua" \
  mods/STADIUM2_IMPORTER/tools/run_battle_fx_worker_checks.sh
```

ROM acceptance proves 30 rows, six empty rows, 24 non-empty rows, 34 route
entries, 29 moves, 18 alternate-bank entries, and the paired routes for moves
20/50/81. Synthetic goldens cover family 4 frames 119/120/126/180/181,
family 2 frames 1769/1770/1773/1800/1801, family 12 frames 1/2/49/50,
family 17 termination at 50, family 20 at 180/181, draw gating, diagnostic
deduplication, ordering, and snapshot immutability.

## Non-goals and risks

- Do not implement direct callee bodies, resource ownership, model geometry,
  side/camera/attachment semantics, or guessed lifetimes for other families.

## Required handoff report

Use the standard task template and list which families still depend entirely
or partly on the injected phase resolver.
