# LUNA-008: Lossless common-particle material state

## Objective

Create a pure material-state layer that preserves the exact fragment-79
preload results and makes every unresolved update/draw decision explicit.

## Evidence and source of truth

- `docs/luna/research/material-motion-controllers.md`, especially
  `0x84106F34..0x8410716C`.
- ROM requirement: yes.

## Owned paths

- `lib/stadium2_battle_fx_material.lua`
- `tests/stadium2_battle_fx_material_test.lua`

## Forbidden paths

- Every existing source/test file and other workers' deliverables.

## Interface contract

Expose pure `Material.init(material, context)`, `Material.step(state, options)`,
and `Material.snapshot(state)`. Initialization must preserve primary and
secondary shape IDs, controller/table pointers, and detached copies of primary,
secondary, and constant RGBA bytes. Validate RGBA as four byte values without
normalizing to floats.

State carries persistent ID context (`effectId`, `programId`, `address`, age).
Without a color-controller resolver, retain the preloaded bytes unchanged and
emit one frozen-schema `unsupported-color-controller` diagnostic when a
nonzero pointer exists. Without a shape-selection resolver, retain both shape
IDs and emit `unsupported-secondary-shape` when the secondary ID is nonzero;
do not choose or blend them. `step` advances age but changes colors/selected
shape only from explicit injected resolver results. Invalid resolver output is
diagnosed and does not mutate the previous state.

No interpolation formula, frame animation, renderer packet, resource lookup,
host RNG, or fallback color/shape is allowed. Inputs and snapshots are deeply
detached and diagnostics deduplicated.

## Acceptance commands

From `/opt/git/gen1recomp`:

```sh
lua mods/STADIUM2_IMPORTER/tests/stadium2_battle_fx_material_test.lua
STADIUM2_REQUIRE_ROM=1 \
LUNA_OWNED_PATHS="mods/STADIUM2_IMPORTER/lib/stadium2_battle_fx_material.lua mods/STADIUM2_IMPORTER/tests/stadium2_battle_fx_material_test.lua" \
  mods/STADIUM2_IMPORTER/tools/run_battle_fx_worker_checks.sh
```

Tests cover byte-exact preload, invalid RGBA, unresolved diagnostics,
resolver-driven updates, invalid resolver preservation, diagnostic dedup,
age, and immutability.

## Required handoff report

Use the standard template and list unresolved update/draw ownership.
