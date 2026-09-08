# LUNA-005: Proven common-particle initializer semantics

## Objective

Replace the remaining provisional common-particle initialization behavior with
the instruction-level rules proven in
`docs/luna/research/material-motion-controllers.md`.

## Non-goals

- Per-frame integration, color interpolation, or secondary-shape drawing.
- Trigonometric modes 2/3/5 without an explicit resolver.
- Calling external Stadium RNG functions or the host battle RNG.
- ROM decoder, Native selector, runtime, attachment, or rendering changes.

## Evidence and source of truth

- `docs/luna/research/material-motion-controllers.md`.
- Fragment-79 ranges `0x84105E9C..0x8410653C` and
  `0x84106AC4..0x84106EBC`.
- ROM requirement: yes.

## Owned paths

- `lib/stadium2_battle_fx_motion.lua`
- `tests/stadium2_battle_fx_motion_test.lua`

## Forbidden paths

- All other source and test files.

## Interface contract

Add an injected `randomScalar(variant, bound, context)` option. Random-vector
mode 0 calls variant 0 in X/Y/Z order; mode 1 calls variant 1 in X/Y/Z order.
Zero bounds produce zero without consuming RNG. Preserve the original signed
halfword bounds and pass effect/program/address, age, channel, component, angle
context, and injected `rng` through the context. Invalid/missing external
resolvers produce frozen-schema diagnostics and zero contribution.

Modes 2, 3, and 5 remain behind `randomVector` because the external angle
tables are not yet represented in the runtime. Unknown modes remain explicit.

Implement the proven frame rules: mode 1 is `value * generation + 1`; mode 2
is `(generation % value) + 1` with an error diagnostic for zero; mode 3 calls
the injected external scalar resolver with variant 0 and returns its exact
result; every other mode returns the authored value. The evaluator must receive
the scheduler generation separately from particle age.

Do not treat the scale-entry field at offset `+6` as a proven expiry threshold.
Retain it as `authoredLifetime`, but leave runtime `lifetime=nil` unless the
particle contains an explicit resolved `lifetime`. Emit one
`unsupported-lifetime` diagnostic and keep the particle alive. This supersedes
the earlier synthetic scale-lifetime assumption.

Do not add a default per-frame integrator. Keep all input/output detached and
all diagnostics in the frozen schema.

## Acceptance commands

From `/opt/git/gen1recomp`:

```sh
lua mods/STADIUM2_IMPORTER/tests/stadium2_battle_fx_motion_test.lua
STADIUM2_REQUIRE_ROM=1 \
LUNA_OWNED_PATHS="mods/STADIUM2_IMPORTER/lib/stadium2_battle_fx_motion.lua mods/STADIUM2_IMPORTER/tests/stadium2_battle_fx_motion_test.lua" \
  mods/STADIUM2_IMPORTER/tools/run_battle_fx_worker_checks.sh
```

Tests must verify call variant/order/bounds/context, zero-bound behavior, frame
modes 1/2/3/default, modulo-zero diagnostics, no host RNG call, unresolved raw
lifetime behavior, explicit resolved lifetime expiry, and immutability.

## Required handoff report

Use the standard task template and identify every behavior still waiting on an
external resolver.
