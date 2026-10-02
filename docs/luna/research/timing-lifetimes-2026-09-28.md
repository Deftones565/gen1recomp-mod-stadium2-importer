# Animation timing and FX lifetime audit — 2026-09-28–29

Research only. Host battle mechanics remain authoritative. A demonstrated
Lua/ROM timing difference is not a user-confirmed visual defect. New findings
are mirrored in `battle_FX_bugs.md` when verified; previous findings are not
counted again.

## Sources and method

- Importer baseline: `410e5ec`, with pre-existing concurrent changes to
  Gen 2 recall scaling and model-color invalidation, importer/options and
  their tests. This audit does not edit those implementations.
- Host baseline: `ff8373b76d4911d083a7d46a4aae8d6eab2cc4e5`.
- Primary merged decomp: [michiiik/pokestadiumgs
  `026460f8a239c720fa38ac8c5a702b51a5bdfc2e`](https://github.com/michiiik/pokestadiumgs/tree/026460f8a239c720fa38ac8c5a702b51a5bdfc2e),
  fetched from master on this audit. Source snapshot in
  `/tmp/stadium2-timing-decomp-20260928`; remaining GLOBAL_ASM behavior is
  checked against US assembly or executable ROM, not inferred from C.
- Supported US ROM: `baseroms/stadium2.z64`, expected MD5
  `1561c75d11cedf356a8ddb1a4a5f9d5d`.
- Reproducer: from repository root,
  `luajit mods/STADIUM2_IMPORTER/tools/audit_battle_fx_timing.lua`.
  Controlled scheduler inputs isolate orchestration bugs; they are not
  misrepresented as a particular species' native dispatch row. ROM checks
  are distinguished below. GPU and user visual acceptance are separate.

## T01: delayed queue service is not invariant to update batching

**Status 2026-09-29: fixed in the adapter** (local session). `Runtime:step`
calls an `afterTick(frame)` hook once per tick, after the particle and
manager passes (8413D37C runs the battle actors after each FX update). The
battle adapter sets it to `Adapter:_serviceQueues`, so every queue is
serviced on its own tick, in chronological order, however many ticks one
update advances. `Adapter:update` services directly only for a player
without that hook. Test: `tests/stadium2_battle_fx_queue_timing_test.lua`
(the three-tick batch now gives `impact@1, route@2`, the same as three
single ticks). `tools/audit_battle_fx_timing.lua` still prints the old
three-tick line: its fixture player has no `runtime.step`, so it takes the
fallback path.

`lib/stadium2_battle_fx_battle_adapter.lua:Adapter:update` calls
`player:update(dt)` before checking any delayed work. Runtime:update can
advance several 30 Hz frames. All due work then uses the final frame, in
queue-type order: route, finish, impact, signals, variants.

Controlled schedule: route at tick 2, impact at tick 1. Three updates of
1/30 second produce `impact@1, route@2`, leaving the route signal 0. One
update of 3/30 produces `route@3, impact@3`, leaving signal 1. These are the
real adapter methods with an injected recording player. Both live adapters
accept up to 0.1 seconds per presentation update, so up to two ticks of
lateness are possible without exceeding their clamp. Queued work must be
dispatched at its due simulation boundary, preserving chronological order.
Native frame driver `841055D8` runs one scheduler/particle pass per tick;
the old documented intra-tick phase-order gap is separate from this new
multi-tick batching defect.

## T02: queued work outlives its move/model identity

**Status 2026-09-29: fixed in the adapter** (local session). Queued
impacts and move-owned signals record the move generation
(`playMoveAndImpact` starts a new one) and are dropped when a newer move
has begun. Impacts record their target's model generation, signals their
owner's, and variants their source's; `modelChanged(side)` bumps that
side's generation and drops a pending route whose attacker was replaced.
Event effects that are not tied to a move (status/weather signals) are not
dropped by a newer move. Test: `tests/stadium2_battle_fx_queue_timing_test.lua`.

`scheduleRoute` replaces only the pending route and finish. Pending impacts,
signals and variants have no move-generation or actor-instance guard.
`modelChanged(side)` only calls `player:resetModel(side)`. The concurrent
model-color fix guards native writes by effect ID, but a future queued
impact creates a *new* effect after replacement and is outside that guard.

Reproduction: queue move 55 route@8/impact@10; at tick 1 begin a new fixture
move 33. Move 33 runs but move 55 still impacts at tick 10. Separately,
queue impact@8, replace its target model, and it still fires. The IDs label
independent fixture jobs; no assertion about their retail authored delays
is made. Actual host overlap frequency remains to be measured. Faint,
charge and event queues also need identity-aware lifetime review; do not
indiscriminately cancel deliberately persistent status/weather particles.

## T03: particle age exemption and Y termination are conflated

**Status 2026-09-29: fixed in the runtime** (local session). The constructor
mapping was re-read in the US assembly (`841071B0..C0`: descriptor `0x10` →
object flag 1; `84107240..54`: bit 28 → `0x20000`; `841071F8..8`: bit 29 →
`0x10000`) and `8410009C`'s age branch calls `84100074` with mask 1.
`stadium2_battle_fx_motion.lua` now exempts age 255 only for descriptor
`0x10` (`nativeAgeExempt`); the Y rule stays separate. The motion test
covers all four rows of the table below. Not yet visually retested.

Confirmed by executing supported-ROM `8410009C` and reading current C in
`fragment79_36F8B0.c`. A particle completes when its completion byte is
zero, or when its byte age is 255 and object flag 1 is absent, or when
object flag `0x20000` is set and final Y is nonpositive. These are independent
conditions. Constructor `84107170` maps descriptor `0x10` to object flag 1,
and descriptor `0x10000000` to object flag `0x20000`.

| Descriptor flags | Object flags | Age / Y | ROM completes | Lua alive |
|---|---|---|---|---|
| `0` | `0` | 255 / 1 | yes | no (matches) |
| `0x10` | `1` | 255 / 1 | no | no (**wrong**) |
| `0x10000000` | `0x20000` | 255 / 1 | yes | yes (**wrong**) |
| `0x10000010` | `0x20001` | 255 / 1 | no | yes (matches) |

`stadium2_battle_fx_motion.lua:nativeYTermination` and the end of its step
function use the Y flag to suppress age retirement. The old
`common-particle-update.md` note and `stadium2_battle_fx_motion_test.lua`
agree with that wrong implementation and need correction when fixed.
Catalog flag presence includes Mist (54), powders (77–79), Haze (114),
Powder Snow (181), Icy Wind (196), Rapid Spin (229), Rain Dance (240),
and numerous impact routes. This list establishes exposure, not that each
particle survives all other gates to age 255 in a live battle.

## T04: dead history remains in the simulation and snapshot walk

**Status 2026-09-29: fixed in the runtime** (local session). After each
tick, `Runtime:_retireFinished` removes an effect that has no live particle,
no birth left in its schedule (the `Native.births` start/interval/repeats;
an endless 0xFF emitter counts as pending until cancelled), no active
lifecycle instance and no active native-object slot. Retiring releases its
lifecycle instances (whose update order is now pruned too) and its
lifecycle finish flag. Finished particle rows of running effects are
dropped each tick. This is bookkeeping only: Stadium keeps no per-move
record once its particles, scheduler slots and lifecycle slots are free.
The audit's 1,000 Pound routes + 360 ticks now leave 0 effects. Synthetic
benchmark (LuaJIT, `os.clock`, 200 moves of 10 particles, one move per 60
ticks, shared snapshot every tick): late-battle tick + snapshot 0.189 ms
before, 0.005 ms after. It was not measured in game. Test:
`tests/stadium2_battle_fx_effect_retirement_test.lua`.

`Runtime:trigger` always appends to `effects` and `effectOrder`.
`Runtime:step`, `_spawn`, and `snapshot` keep visiting historical effects;
normal expiration leaves inactive particle rows in each effect's list.
Only full `Runtime:release` clears the effect collection. Failure/held
release filters some particles but does not retire effect records.

With the real ROM catalog, repeat Pound's empty primary program 1,000
times, then advance 360 ticks: snapshot contains 1,000 effects, zero live
particles. The native 300-live-particle bound is respected, but historical
work/storage grows with total effects over the battle. This invalidates a
blanket claim that all per-frame work is bounded by that live pool. No
frame-time benchmark or visible lag attribution was performed here.

## T05: zero-repeat emitter becomes a one-shot

ThunderShock (84), alternate bank program 167, descriptor `84177B4C`:
start 0, interval 102, repeat byte 0. Native `84107B68`, calling the signed
count predicate at `84107C60`, keeps a nonpositive-count slot active with
countdown zero. It emits on every subsequent scheduler pass until an
explicit release. `Native.births` instead iterates `0..max(0,repeats-1)`
and produces one birth for zero.

The audit tool executes the real ROM scheduler, substituting only its
emission call and slot-release operation so it can record passes without
building GPU objects. Six passes produce native `0,1,2,3,4,5`, Lua `0`.
This is a concrete retail descriptor, not a made-up repeat-zero case.
`fragment79_377570.c` plus remaining US scheduler assembly establish the
field meanings. Positive start-delay phase is reviewed separately below;
it is not needed to prove the repeat-count mismatch.

## T06: material endpoint freezes age, not visibility

For descriptor bit `0x2`, `84102320` sets object bit `0x80` at the material
endpoint. `841054D4/841055A0` skip the age increment while that bit is set.
The mode-1 native draw exclusion mask in `84103394` is `0x102800`, which
does not include `0x80`. Lua's `nativeHideAge` interpretation sets
`nativeHidden`; `DrawPackets.build` then drops the particle while Motion
continues incrementing its age.

Executing the ROM age prepass on an active particle at age 3 with flag
`0x80` leaves age 3. Advancing the Lua particle past its endpoint gives age
4 and `nativeHidden=true`. Catalog entries carrying the flag:
Baton Pass (226, program 4, `8416E144`, endpoint 79); event 254
(`8416AC84`, 32); event 256 (`8416AD00`, 4); 275/285/288
(`84175434`, 0); 286 (`84175244`, 0); and 301 (`84170718`, 2).
Endpoint zero and mode-0 visibility require full caller/draw traces before
assigning a visible duration to those entries. The age-freeze discrepancy
is directly proven; do not turn this catalog list into visual confirmation.

Fixed 2026-10-02: Motion sets `nativeAgeFrozen` at the endpoint (object
flag 0x80) and skips the age increment while it is set; nothing hides the
particle. The releases clear it (`Runtime:releaseHeld` 84108A10,
`releaseStatusEnded` 84108AF8, `releaseHeldButDust` 84108CE8). Probe (the
viewer's preview runtime, 600 ticks): entries 254 (0x13D) and 256 (0x12)
held and frozen until released, then end at byte age 0xFF; 226 frozen,
not held (ends at the next 841089D8 clear); 301 (0xD3) held, frozen and
0x8000 (ended by its release). Tests: diagnostics, surf_material_rom (the
VM's flag 0x80 now compared with the freeze), status_particles.

## T07: Magnitude's announcement and animation use different FX ownership

Host `src/battle/gen2/Battle.lua`'s EFFECT_MAGNITUDE branch marks its move
row `deferAnim=true`, emits the magnitude-number text, and emits a later
message row with `moveAnim`. `src/ui/gen2/BattleState.lua:advanceQueue`
honors that split. Importer `Scene:handleEvent` dispatches move FX for the
deferred row anyway; its `animForMove` hook only starts the actor clip.
There is no corresponding FX start for the later `moveAnim` row.

The actual Scene adapter probe records one start on the deferred move row,
and still only one after the later animation row. The first row also passes
through `syncBattleFxAnimation(true)` with no runner, allowing premature
finish signaling. This explains a definite clip/FX start disagreement for
Magnitude (222) without depending on guessed Stadium timing. Native move
row timing (`84114BF4/8411845C`) must be anchored to the presented animation,
not to an earlier host announcement.

## T08: pre-roll transition consumes the full crossing delta twice

`Actor:stepPendingClip` accumulates the idle pre-roll, switches clips, and
returns. The containing `Actor:update` then calls `renderer:step(dt)` with
the entire current delta instead of just elapsed time after the transition.
For a fixture row with signed hit -2 and clip start 0, elapsed time 3/30
produces clip frame 2 under three single-tick updates, versus frame 3 under
one three-tick update. The proof is delta-partition dependence; this report
does not claim frame 2 is the native boundary's exact correct answer.
`84114A04/84114BF4` define the negative-counter idle/start transition;
the existing rebased row schedule itself is a different concern.

## Audit completion

In progress: host start/finish clocks, actor clips and readiness, status and
weather lifetimes, per-family finish flags, interrupted/skipped/multiple-hit
animations, viewer equivalence, and focused/full validation. No move sweep
or diagnostic counts have been regenerated by these targeted probes.
