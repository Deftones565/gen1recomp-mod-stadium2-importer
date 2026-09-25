# LUNA-004: Integrate routing and motion into the persistent runtime

## Objective

Make the accepted router and motion evaluator the only route-selection and
common-particle state paths used by the persistent 30 Hz runtime.

## Non-goals

- Native-object and lifecycle execution.
- Implementing unresolved fragment-79 controller arithmetic.
- Attachment resolution, materials, drawing, or battle integration.
- Changes to ROM decoding, resources, or the standalone evaluator contracts.

## Evidence and source of truth

- `docs/luna/README.md`: frozen runtime and diagnostic contracts.
- `lib/stadium2_battle_fx_router.lua`: one-channel route selection.
- `lib/stadium2_battle_fx_motion.lua`: detached common-particle states.
- `lib/stadium2_battle_fx_native.lua`: bytecode execution and births.
- ROM requirement: yes for the shared acceptance lane.

## Owned paths

- `lib/stadium2_battle_fx_runtime.lua`
- `tests/stadium2_battle_fx_runtime_test.lua`

## Forbidden paths

- Every other `lib/stadium2_battle_fx_*.lua` file.
- `main.lua`, `lib/importer.lua`, battle/scene files, and visual viewers.
- Research reports and files claimed by another worker.

## Interface contract

`Runtime.new(options)` keeps its existing API and additionally accepts
dependency overrides `router`, `motion`, and `motionOptions`. Defaults are the
accepted Router and Motion modules. The runtime must inject `options.rng` into
the motion options unless an explicit motion RNG was supplied.

`trigger` must call the router exactly once and pass only its selected channel
to native execution. A routing failure returns `nil, error` without allocating
an effect ID or mutating runtime state. Program-local branches remain wholly in
`Native.execute`.

Every common particle owns one persistent motion state created exactly once at
birth. Each runtime tick advances each active state exactly once with
`Motion.step(state, 1, motionOptions)`. The runtime particle record reflects the
evaluated age, lifetime, alive state, position, velocity, rotation, and scale.
It must never reinitialize a particle during `snapshot` or draw.

Motion diagnostics are appended to the runtime diagnostic stream once per
particle/code/address/message combination and normalized to the frozen schema.
An unresolved lifetime remains `nil` and alive until release. Do not apply a
fallback integrator or random-vector formula.

Existing monotonic IDs, stable ordering, deep-copy snapshots, frame-zero
births, catch-up accounting, and explicit native-object/lifecycle diagnostics
remain unchanged.

## Acceptance commands

Run from `/opt/git/gen1recomp`:

```sh
lua mods/STADIUM2_IMPORTER/tests/stadium2_battle_fx_runtime_test.lua
STADIUM2_REQUIRE_ROM=1 \
LUNA_OWNED_PATHS="mods/STADIUM2_IMPORTER/lib/stadium2_battle_fx_runtime.lua mods/STADIUM2_IMPORTER/tests/stadium2_battle_fx_runtime_test.lua" \
  mods/STADIUM2_IMPORTER/tools/run_battle_fx_worker_checks.sh
```

Tests must prove one-channel routing, no ID allocation on routing failure,
single motion initialization per birth, one evaluation per active particle per
tick, injected RNG propagation, diagnostic de-duplication, expiry, snapshot
immutability, and unchanged accumulator behavior.

## Baseline

- Record `git status --short` before editing.
- Preserve all unrelated dirty paths.

## Risks and open questions

- Motion is intentionally incomplete until the controller disassembly report
  is accepted. Integration must expose unsupported diagnostics, not hide them.
- Do not merge runtime lifetime resolution and Motion lifetime decoding into
  competing policies. The explicit runtime resolver wins when it returns a
  value; otherwise the authored scale-entry lifetime may be used by Motion.

## Required handoff report

- Status:
- Files changed:
- Diff summary:
- Commands and results:
- Behavioral evidence:
- Limitations:
- Unresolved assumptions:
