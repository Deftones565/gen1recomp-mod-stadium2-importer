# LUNA-003: Route and attachment resolver

## Objective

Create pure routing and attachment functions that select exactly one authored
dispatch channel and resolve source/target/world anchors from explicit context.

## Non-goals

- Particle scheduling, motion, materials, rendering, or battle hooks.
- Model bone lookup implementation; define its required callback contract only.

## Evidence and source of truth

- Route records and attachment flags in `lib/stadium2_battle_fx_rom.lua`.
- Current preview approximation in the Koffing/Croconaw visual harness.
- ROM requirement: no for unit tests; optional for the full check.

## Owned paths

- `lib/stadium2_battle_fx_router.lua`
- `lib/stadium2_battle_fx_attachment.lua`
- `tests/stadium2_battle_fx_routing_test.lua`

## Forbidden paths

- Existing battle-FX decoder/resource files and all integration/viewer files.
- Files owned by LUNA-001 and LUNA-002.

## Interface contract

Routing accepts a decoded catalog move row (`primaryDispatch` and
`alternateDispatch`) plus an explicit boolean `alternate`, and returns one
ordered dispatch list. It does not execute opcode branches. `condition` and
`conditionForMove` pass unchanged from `Runtime:trigger` to `Native.execute`.
Attachment accepts the decoded contract plus explicit source,
target, ground, camera-line, saved-origin, scale, and optional model-anchor
callback data. It must distinguish unresolved model attachments from valid
world positions.

## Acceptance commands

```sh
lua mods/STADIUM2_IMPORTER/tests/stadium2_battle_fx_routing_test.lua
LUNA_OWNED_PATHS="mods/STADIUM2_IMPORTER/lib/stadium2_battle_fx_router.lua mods/STADIUM2_IMPORTER/lib/stadium2_battle_fx_attachment.lua mods/STADIUM2_IMPORTER/tests/stadium2_battle_fx_routing_test.lua" \
  mods/STADIUM2_IMPORTER/tools/run_battle_fx_worker_checks.sh
```

## Required handoff

Use `docs/luna/TASK_TEMPLATE.md`. Include tests proving that channels are not
superimposed and every decoded attachment flag has deterministic behavior or an
explicit unsupported result.
