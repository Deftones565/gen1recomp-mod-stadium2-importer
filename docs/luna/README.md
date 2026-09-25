# Luna Worker Harness

This harness uses one architect and bounded Luna workers to complete Stadium 2
battle FX without allowing parallel agents to improvise overlapping runtime or
battle changes.

## Architecture boundary

```text
ROM catalog/resources (existing immutable input layers)
    -> router
    -> persistent 30 Hz runtime
    -> motion / attachment / material evaluators
    -> deterministic draw packets
    -> renderer adapter
    -> battle.scene.geometry.v1
```

The existing input layers are:

- `lib/stadium2_battle_fx_rom.lua`
- `lib/stadium2_battle_fx_native.lua`
- `lib/stadium2_battle_fx_resources.lua`

The architect owns changes to those shared layers until a packet explicitly
assigns one of them. The architect also owns `main.lua`, `lib/importer.lua`,
Gen 1/Gen 2 battle adapters, public exports, and final integration.

## Dispatch procedure

1. The architect freezes the public contract needed by the next wave.
2. Create a task from `TASK_TEMPLATE.md` with exact owned and forbidden paths.
3. Confirm that no live worker owns the same path.
4. Spawn a `gpt-5.6-luna` worker with the entire packet in its prompt.
5. The worker records baseline status, implements only its packet, runs its
   acceptance commands, and returns a structured handoff.
6. The architect reviews `git diff -- <owned paths>`, reruns the gates, and
   either accepts the work or returns one focused correction.
7. Release the path claim before dispatching dependent work.

Workers share the same worktree. Parallelism is safe only for disjoint new
files. Changes to shared schemas and integration files are serialized through
the architect.

## Runtime contract to freeze first

The first worker must implement this shape without editing the ROM decoders:

```lua
local runtime = Runtime.new({
  catalog = catalog,
  clockHz = 30,
  rng = deterministicRandom,
  warn = warningSink,
})

local effectId = runtime:trigger({
  moveId = 7,
  sourceSide = "player",
  targetSide = "enemy",
  alternate = false,
  condition = 0,
})

runtime:step(1)       -- advance exactly one 30 Hz tick
runtime:update(dt)    -- presentation clock
local snapshot = runtime:snapshot()
runtime:release()
```

Snapshots must have stable ordering and persistent particle identity. The
minimum particle record is:

```lua
{
  id = 1,
  effectId = 1,
  schedulerIndex = 1,
  generation = 0,
  particleIndex = 0,
  born = 0,
  age = 0,
  lifetime = 1,
  position = {0, 0, 0},
  velocity = {0, 0, 0},
  rotation = {0, 0, 0},
  scale = {1, 1, 1},
  shapeId = 47,
  material = {},
  attachment = {},
}
```

`step(count)` accepts a non-negative integer tick count; zero is a no-op and
invalid/negative counts are errors. `update(dt)` accepts non-negative seconds,
adds `dt * clockHz` to a fractional accumulator, and advances the integral
number of available ticks. A configurable catch-up limit may bound work per
call, but surplus ticks must remain in the accumulator rather than being lost.

Particle and effect IDs are monotonically increasing for the lifetime of a
runtime and are never reused after expiry. Snapshot records and nested mutable
tables are copies owned by the caller; mutating a snapshot must not mutate the
runtime.

LUNA-001 receives a `lifetimeResolver(particle, event)` dependency. Synthetic
tests supply exact lifetimes. Until the native lifetime/controller rule is
accepted, an unresolved lifetime stays `nil`, emits a diagnostic, and remains
alive until explicit effect release; the worker must not invent a default.

Diagnostics use this stable schema:

```lua
{
  code = "unsupported-lifetime",
  severity = "warning", -- warning or error
  effectId = 1,
  programId = 259,
  address = 0x8417B624,
  kind = "particle",
  message = "human-readable detail",
}
```

Routing happens before bytecode execution: the router selects exactly one of
`move.primaryDispatch` or `move.alternateDispatch`. `Native.execute` then owns
program-local opcode 9/10/11 branching and opcode 17 state. `trigger.condition`
is the initial integer condition; `trigger.conditionForMove` is the optional
callback used by opcode 16. The router must not evaluate bytecode branches.

## Delivery waves

- Wave 1: persistent scheduler, motion evaluator, routing/attachment contract.
- Wave 2: native-object modes, lifecycle families, material/draw packets.
- Wave 3: renderer adapter and battle integration.
- Wave 4: ROM-wide regression audit and visual parity review.

Wave 1 packets live in `docs/luna/tasks/`. Later packets must be written only
after the architect accepts the runtime snapshot contract.

## Validation lanes

`tools/run_battle_fx_worker_checks.sh` always runs ROM-free core/options checks
and `git diff --check`. When `STADIUM2_ROM` points to the supported ROM—or the
usual ignored local ROM exists—it also runs the complete 251-move ROM audit.

Use strict ROM mode for any packet whose acceptance depends on retail data:

```sh
STADIUM2_REQUIRE_ROM=1 \
STADIUM2_ROM=/path/to/stadium2.z64 \
mods/STADIUM2_IMPORTER/tools/run_battle_fx_worker_checks.sh
```

A missing optional ROM prints `SKIP`; it is never described as a passed ROM
audit. Strict mode exits nonzero when the ROM is unavailable.

For worker handoff, pass owned Lua paths to the shared check:

```sh
LUNA_OWNED_PATHS="mods/STADIUM2_IMPORTER/lib/new_file.lua mods/STADIUM2_IMPORTER/tests/new_test.lua" \
  mods/STADIUM2_IMPORTER/tools/run_battle_fx_worker_checks.sh
```

The architect additionally reviews `git diff -- <claimed paths>` and the full
`git status --short`. A shared dirty worktree cannot be secured by a test runner
alone.
