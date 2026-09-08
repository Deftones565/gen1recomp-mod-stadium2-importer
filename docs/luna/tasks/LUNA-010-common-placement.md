# LUNA-010: Correct common-particle placement contracts

## Objective

Remove contradicted high-bit attachment labels and implement the exact low-bit
placement operations proven by fragment 79.

## Evidence and source of truth

- `docs/luna/research/attachment-semantics.md`.
- `0x84104A00..0x84104F38`, `0x8410668C..0x84106798`, and
  `0x841072BC..0x841076B4`.
- ROM requirement: yes.

## Owned paths

- `lib/stadium2_battle_fx_rom.lua`
- `lib/stadium2_battle_fx_attachment.lua`
- `tests/stadium2_battle_fx_routing_test.lua`
- `tests/stadium2_battle_fx_rom_audit.lua`

## Forbidden paths

- Native/runtime/motion/material/lifecycle/resources, importer, battle,
  scene/viewer, and other tests.

## Interface contract

The ROM decoder attachment record preserves `flags`, `flags2`, descriptor
identity, `status="unresolved-common-flags"`, and only proven low-bit operation
names. Remove the contradicted world/side/battler/camera/opposite/ground labels.
Expose: bit `0x1` placement preparation, `0x2` primary policy, `0x4` zero-Y,
`0x8` external scale/offset/Y family, `0x10` anchor callback, `0x20`
model/fallback plus saved-origin branch, `0x80` fixed initial scale and
anchor-vs-shared-origin selection, `0x100` zero anchor, `0x400` lane-scalar
callback, and `0x4000` secondary visual policy. `flags2` has no inferred
placement behavior.

Redesign `Attachment.resolve(contract, context)` around raw flags and injected
external callbacks. Implement exact branch precedence, `0x100` zero anchor,
`0x400` signed scalar × `-150.0` X with zero Y/Z, explicit anchor/model
callbacks for `0x10/0x20`, `0x4/0x8` Y overrides, fixed initial scale 1.0,
explicit saved-origin copy/offset clear, and shared-origin vector addition only
when the necessary context/resolver data exists. Actor-table tail behavior must
remain an explicit resolver boundary.

Expose a pure placement sum of anchor + common offset + transform + motion in
that exact order for X/Y/Z. Never substitute a battler/world/camera/ground
position. Missing callbacks/data return raw unresolved state plus frozen-schema
diagnostics. Deep-copy all results.

## Acceptance commands

From `/opt/git/gen1recomp`:

```sh
lua mods/STADIUM2_IMPORTER/tests/stadium2_battle_fx_routing_test.lua
STADIUM2_REQUIRE_ROM=1 \
LUNA_OWNED_PATHS="mods/STADIUM2_IMPORTER/lib/stadium2_battle_fx_rom.lua mods/STADIUM2_IMPORTER/lib/stadium2_battle_fx_attachment.lua mods/STADIUM2_IMPORTER/tests/stadium2_battle_fx_routing_test.lua mods/STADIUM2_IMPORTER/tests/stadium2_battle_fx_rom_audit.lua" \
  mods/STADIUM2_IMPORTER/tools/run_battle_fx_worker_checks.sh
```

Tests cover every proven low bit, branch precedence, callback arguments, Y
matrix, fixed scale, saved/shared origin, exact four-vector sum, `flags2`
negative controls, unresolved diagnostics, and ROM counts/goldens from the
report. Assert old semantic fields are absent.

## Non-goals and risks

- External callback implementations, actor table internals, camera/opposite
  side semantics, post-initialization reattachment, and rendering.

## Required handoff report

Use the standard template and enumerate unresolved external addresses.
