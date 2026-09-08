# LUNA-006: Native-object scheduler kernel

## Objective

Decode native-object command evidence without pretending it is the resolved
object, and implement the proven 64-slot scheduler state machine for modes
2/4/5/6/8.

## Evidence and source of truth

- `docs/luna/research/native-object-modes.md`.
- Fragment-79 scheduler `0x84105D08..0x84105E3C` and
  `0x84107B68..0x84108358`.
- ROM requirement: yes.

## Owned paths

- `lib/stadium2_battle_fx_rom.lua`
- `lib/stadium2_battle_fx_native_objects.lua`
- `tests/stadium2_battle_fx_native_objects_test.lua`
- `tests/stadium2_battle_fx_rom_audit.lua`

## Forbidden paths

- Runtime, Native bytecode, motion, attachment, resources, importer, scene,
  viewer, and every other test.

## Interface contract

For modes 2/4/5/6/8, the ROM decoder preserves `commandPointer` separately
from the unresolved object and never labels command bytes a complete
descriptor. Preserve at least 16 bytes as `encodedObjectRaw`, expose proven
`delayOffset` (`3` for 2/4/8, `1` for 5/6) and `encodedDelay`, but mark the
object unresolved because `0x80003240` owns resolution. Do not feed
`encodedDelay` to the live scheduler without an explicit resolver result.

Create a persistent scheduler with capacity 64 and injected
`resolve(commandPointer,event)` and `callbacks[mode]`. Enqueue allocates the
lowest free slot, stores the resolved object, initializes countdown from the
mode-specific byte, reload=0, age=0, state=1, active=true, and mode. Resolution
failure returns a frozen-schema diagnostic and allocates no slot.

One tick visits slots in index order, decrements positive countdowns, and
dispatches only when countdown reaches zero. Callback result `<=0` leaves the
slot active; `0xFF` reloads countdown; otherwise increment age and release on
equality. Release mirrors the proven cleared fields. Retain callback-produced
visual objects and raw fields, but unsupported update/draw callbacks remain
diagnostics—not fake common particles.

Expose stable deep-copy snapshots and explicit release. No global/host RNG.

## Acceptance commands

From `/opt/git/gen1recomp`:

```sh
lua mods/STADIUM2_IMPORTER/tests/stadium2_battle_fx_native_objects_test.lua
STADIUM2_REQUIRE_ROM=1 \
LUNA_OWNED_PATHS="mods/STADIUM2_IMPORTER/lib/stadium2_battle_fx_rom.lua mods/STADIUM2_IMPORTER/lib/stadium2_battle_fx_native_objects.lua mods/STADIUM2_IMPORTER/tests/stadium2_battle_fx_native_objects_test.lua mods/STADIUM2_IMPORTER/tests/stadium2_battle_fx_rom_audit.lua" \
  mods/STADIUM2_IMPORTER/tools/run_battle_fx_worker_checks.sh
```

Add ROM goldens for programs 98/mode2, 328/mode5, and 299/mode8, plus catalog
counts 403 records, 268 programs, modes 2=195, 5=121, 8=87, and zero retail
records for modes 4/6. Synthetic tests cover modes 4/6, capacity, countdown,
non-positive/`0xFF`/age-equality results, resolver failure, and immutability.

## Non-goals and risks

- Do not implement the external resolver, linked update/draw callbacks,
  battler/camera semantics, or native visual lifetime.
- Do not assume the command pointer equals the resolved pointer.

## Required handoff report

Use the standard task template and enumerate unresolved callback families.
