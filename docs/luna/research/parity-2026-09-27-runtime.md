# Runtime and lifecycle parity audit (2026-09-27)

This note audits the persistent runtime, native-object scheduler, particle pool,
and lifecycle callback boundary. It is research only; it does not change the
runtime. The conclusions below are execution and source-parity findings. No
GPU output or visual parity is claimed.

## Evidence and scope

The current decomp source is `/tmp/stadium2-parity-decomp-20260927` at commit
`0ed78d46e9cd11432f217203675a839efcb1cc1c`. Relevant current-source files are
`src/fragments/79/fragment79_3749B0.c`,
`src/fragments/79/fragment79_377570.c`,
`src/fragments/79/fragment79_377F80.c`,
`src/fragments/79/fragment79_37A6E0.c`, and
`src/fragments/79/fragment79_38D510.c`. The US assembly was checked in the
older local clone at commit `c0e10f23d90cc4f335b654711f13e53c2c07323b` and
the supported ROM is `baseroms/stadium2.z64` (MD5
`1561c75d11cedf356a8ddb1a4a5f9d5d`). Fragment 79 is loaded at VRAM
`0x84100000`; the addresses below are VRAM addresses.

The current Lua implementation under review is
`lib/stadium2_battle_fx_runtime.lua`,
`lib/stadium2_battle_fx_lifecycle.lua`,
`lib/stadium2_battle_fx_native.lua`,
`lib/stadium2_battle_fx_native_objects.lua`, and
`lib/stadium2_battle_fx_player.lua`. Existing behavior that is a deliberate
renderer or VM adapter is called an alias below. An alias is not treated as
byte-for-byte native behavior.

## Status-shape release and visibility helpers

The US callbacks in `fragment79_377F80.c` are still `GLOBAL_ASM`, so their
semantics come from the US assembly/ROM rather than neighboring C.

| Native function | Proven US behavior | Current runtime status |
| --- | --- | --- |
| `84108AF8(owner)` | Scans all 300 particle slots, restricted to active slots whose owner is `owner`. It preserves particles for the status/shape cases `(status low 3 != 0 and shape 0x12)`, `(status == 0x20 and shape 0x13D)`, and `(status bit 0x4 and shape 0xD3)`. Every other matching particle has runtime flags `0x10080` cleared through `84100030`; if object flag `0x8000` is set, `84100348` clears the particle completion byte, then the linked renderer's bit 0 is cleared in place. | **Missing.** `Runtime:releaseHeld` is the separate `84108A10` held-particle operation and does not implement these status exemptions, completion-byte clear, or renderer-bit operation. |
| `84108CE8(owner)` | Scans active particles owned by `owner`; shape `0xD3` is exempt. All other matches clear `0x10080`, clear the completion byte when object flag `0x8000` is set, and clear linked-renderer bit 0. | **Missing.** |
| `84108E00(owner, mode)` | Mode 0 clears renderer bit 0 for shape `0xD3`; mode 1 clears it for shape `0x13D`; mode 2 sets particle object flag `0x100000` for shape `0x12` through `84100020` (US instruction `84108F44`). | **Missing.** `nativeHidden` in draw packets is not the native renderer flag operation, and no current path performs this owner/shape-specific operation. |
| `84108F88(owner, mode)` | Mode 0/1 sets renderer bit 0 for shape `0xD3`/`0x13D`; mode 2 clears particle object flag `0x100000` for shape `0x12`. Each successful mode exits after the first match. | **Missing.** The first-match behavior and the three shape-specific paths are absent. |
| `84109118(arg0)` | For `arg0 == 1`, calls `84105E3C` and emits context `0x11F` through `8410890C`. Otherwise scans all active particles without an owner filter, tests object flag `0x40000`, and clears `0x40080` on matching particles through `84100030`. | **Missing.** There is no equivalent global `0x40000` test/clear or proven `0x11F` callback path in the runtime. |

These are real missing native operations, rather than stale diagnostics. The
current decomp shows their status callers. `841136E8` clears actor status bits
and calls `84108AF8` when the corresponding status-table condition ends
(`fragment79_37A6E0.c`). `84118138`/`841182E0` call `84108E00(actor, 1)` at
the frame-9 frozen/status branch, and `8411EE74` calls mode 2 for a nonzero
status and mode 1 for frozen status (`fragment79_37A6E0.c` and
`fragment79_38D510.c`). Those callers establish status context; this audit does
not infer move IDs from them.

The current router/runtime can carry `nativeBattleState` into opcode-16
branch selection, but that only chooses a native program branch. It does not
provide the pool-wide shape/status operations above. A future implementation
needs the raw owner/status-table inputs and must retain an unsupported
diagnostic until those inputs are available. It must not replace these paths
with a generic hide or kill operation.

## Frame helpers and callback-table boundary

The native frame driver in `fragment79_3749B0.c` is
`841055D8`: it runs route setup, then `84107B68` (the 64-slot native-object
scheduler), then `841029DC` (the 300-slot particle update/cleanup pass), and
then frame teardown. This ordering is a useful reference for the runtime
findings below.

| Helper | US behavior | Current implementation and parity result |
| --- | --- | --- |
| `84105120` | Resets global frame state (`D_84190180/84/88/90`, `D_841901A8`), writes the unit vector to `D_84190078`, fills the nine-entry `D_84190218` table with `0xFF`, then calls `8410358C`, `8410474C`, `84105D00`, `84100134`, `841091CC`, and `84105CA8`. | **Representation difference only.** `Runtime.new` constructs fresh Lua managers. No stale-state or externally observable mismatch caused by omitting these native globals was demonstrated, so this is not recorded as a confirmed runtime bug. |
| `84105630(buffer, mode)` | The jump table is exact in the US data: mode 0 allocates the `0x5BE0` command buffer and initializes `D_84190070/74`; modes 1 and 2 return without this helper's work; mode 3 calls `8410933C`, emits the display-list setup and 160x120 orthographic state, then calls `84103478`; mode 4 calls `84105CF0`. | **Adapter alias.** The Lua player and packet layer intentionally expose renderer-neutral packets, so they do not model the native command/display-list setup side effects. This is a renderer boundary, not proof of a wrong GPU result. |
| `84108654(arg0, arg1)` | Sets `D_84190170` from the route table, stores `D_8416A214`, then walks a linked command-record list and indirectly calls `D_8416A218[record opcode]` until the global route pointer is null. | **Partial VM alias.** `Native.execute` reproduces the decoded synchronous opcode walk for supported records and emits diagnostics for unsupported records, but it does not execute the raw global callback table. Opcode 12 still emits `unsupported-native-program-call`. |
| `8410922C(family, arg1)` | Calls the family init pointer from `D_84183700`, reads and wraps the signed eight-slot counter `D_841901B4`, and stores that family’s update/draw pointers in `D_841901C0`/`D_841901E0`. | **Representation difference only.** `Manager:spawn` calls the Lua family init and keeps stable instance order. The shared native table is not modeled, but no caller-visible mismatch was demonstrated. |
| `84109394()` | Clears the eight callback slots and associated words in `D_841901C0/E0`, resets `D_841901B4`, and clears the callback-side state used by the frame session. | **Representation difference only.** `Manager:release` removes Lua instances. Treating the native table clear as a separate bug would require an observable stale callback case, which this audit did not establish. |
| `841037A0(mtx)` | Allocates a 64-byte command record at `D_84190074 + cursor*64`, writes `0xDA380003` and the next-record pointer, and increments `D_84190070` while the cursor is below `0x16C`; once full it emits nothing. | **Renderer plumbing alias.** Lifecycle draw packets preserve the authored command and pointer as evidence. This audit did not establish that the retail cursor reaches `0x16C` for battle FX, so command-buffer exhaustion is an open renderer question rather than a confirmed runtime gap. |

`8410580C` in the current decomp identifies the frame entry points: mode 0
calls `84105120`, mode 2 calls `841055D8`, and mode 5 calls `84105630`. The
`84105630` mode argument is a separate jump-table selector; its display-list
work is case 3 and its helper teardown is case 4, as shown by
`jtbl_84188C30` in the US data. The reset, scheduler, particle pass, and
command-buffer helpers are therefore native frame plumbing, while the Lua
packet layer intentionally keeps that plumbing behind its renderer adapter.

## Lifecycle callbacks and termination

The current lifecycle table has hard termination thresholds in
`lib/stadium2_battle_fx_lifecycle.lua:718-736`. The thresholds reviewed here
are supported by current callback evidence rather than an inferred default:
current decomp `fragment79_3C60B0.c` shows `84156E8C` (family 4), and the
US assembly shows `8415758C` (family 6) and `841579EC` (family 21),
incrementing their counters and returning `-1` at `0xB5`.
The same source/US callback evidence shows the
family-2 `0x709` cutoff and family-20 `0xB5` cutoff. Family 12 and family 17
also have direct `0x32` callback returns. The current Lua thresholds therefore
are not a confirmed lifecycle bug.

The current manager has explicit native-backed kernels for the families it
claims to simulate: stochastic families 3/15, four-stream 12, terrain family
7, spike family 16, needle family 17, textured families 8/13, tri-attack 20,
radial families 4/6/21, Swift family 2, beam families, wave-grid families
9/10/11, and ribbon families 23/26/27 (`lib/stadium2_battle_fx_lifecycle.lua:
211-647`). Those paths should not be labeled unimplemented merely because
their retail callees remain outside the callback range. In particular,
`Beam.families` includes 0/5/18; those wrappers are implemented. A ROM
catalog scan of primary, alternate and variant dispatch for entries 1..301
finds no route to family 19, but finds family 29 at entry 261 (`0x105`).

**Confirmed missing event geometry: family 29.** `Ribbon.families` only
includes 23/26/27, so entry 261 reaches `_missing` and has no geometry.
`Sequence.TRAP_ENTRIES[20]` and `[35]` select this entry for Bind/Wrap
residual damage, and Gen 2's `signalEventFx` forwards it. The initial move
banks for Bind/Wrap are a separate, implemented path.

The native callbacks are `8415703C` (setup via `841569C0` and `841569A0`,
then `8415BBA0`), `841570B4` (update `8415BD48(1)`), and `841570D4`
(draw `8415C2E0`), all present in current `fragment79_3C60B0.c`.
Do not alias it blindly to family 23: that family uses different setup
inputs and `8415BD48(0)`.

A targeted CPU run of entry 261 with the real pose evaluator, both banks
and both owners for 360 ticks, returns zero execution failures but reports
`unsupported-lifecycle-callback` and `lifecycle-model-unresolved` on both
primary-side scenarios. This is a confirmed missing draw path excluded by
the 251-move sweep. The temporary probe derives from that sweep with its
loop restricted to entry 261; no repository test or runtime was modified.

The family draw packets correctly preserve the observed common display-list
shape (`0xDA380003` and pointer `0x841A4D08`) as renderer evidence. They do not
prove archive resource, model, side, camera, or visual output. Unsupported
lifecycle callbacks still need to remain diagnostic and alive until explicit
release or a ROM-proven termination result; assigning a synthetic lifetime
would be a parity regression. The existing threshold paths are not evidence
that all other helper lifetimes have been solved.

## Pool allocation, update order, and cleanup

The allocator is one of the stronger matches. US `84100260` begins at
`D_8418C954`, scans up to 300 slots, wraps the cursor, leaves the cursor
unchanged when all slots are active, and initializes the selected slot. The
current `Runtime:_allocateNativeSlot` follows that cursor/wrap/full behavior.
US `8410668C` scans the same pool in slot order for an active descriptor with
flag `0x400000` and object flag `0x2`, then copies the candidate origin into
the new particle; current `Runtime:nativePoolOrigin` implements a bounded
300-slot scan with the corresponding descriptor/secondary-emission filter.

The frame order does not match. Retail `841055D8` invokes native-object
callbacks (`84107B68`) before the common particle update/cleanup pass
(`841029DC`). In the current runtime, `Runtime:step` calls `_stepEffect` for
all effects first, which advances existing particles and spawns new ones,
then `_stepManagers`, which ticks native objects and lifecycle managers.
This establishes a phase-order difference. Its consequences for particle
birth, sampled colors and pool-origin readers need a complete native frame
trace; this audit did not execute that complete frame against the ROM.
Existing integration tests intentionally assert the current Lua
order (`motion, material, native, lifecycle:update`); that test describes the
adapter contract, not the US order.

The Lua runtime's logical-slot reuse and cached-renderer release replace
native unlink/detach bookkeeping. No observable stale render or leaked
callback was demonstrated from that representation difference, so it is
not listed as a separate confirmed visual bug.

## Performance and bounded-work observations

The current design has useful bounded properties: the native pool is capped at
300, origin lookup scans at most 300 entries, the native-object scheduler has
64 slots, and `Player:draw` reuses one shared runtime snapshot until the frame
revision changes. This is consistent with the persistent-snapshot architecture
and avoids rebuilding particles from frame zero per draw.

There is still measurable work that has not been profiled in this audit.
`_stepEffect` visits every active particle for every effect each 30 Hz tick;
`Runtime:snapshot` copies particle/material state; lifecycle snapshots copy
packet evidence and geometry; and native-object snapshots copy slot and color
state. These costs are bounded by the current pool/effect counts, but no
target-machine benchmark was run here. Existing historical timing notes must
not be treated as a current performance result.

## Open questions for the next parity pass

1. Trace the status-table producers and the owner/descriptor layout needed by
   `84108AF8`, `84108CE8`, `84108E00`, `84108F88`, and `84109118`. Preserve
   their shape-specific flags and renderer visibility behavior rather than
   mapping them to a generic hide/kill API.
2. Decide where the runtime frame boundary should expose the retail sequence
   `84107B68` before `841029DC`, including whether a newly allocated particle
   receives its first update on the birth tick. The answer must be verified
   against the route/particle caller, not inferred from the Lua test order.
3. Implement the separately proven family-29 setup/update contract and
   verify entry 261 in actual Bind/Wrap residual-damage sequences.
4. Model or explicitly document the eight-slot lifecycle callback table and
   `84109394/841093E8` cleanup side effects if callers can observe them.
5. Add a target-machine profile after behavior is settled. No visual or GPU
   result is established by this document.

## Validation

Architect completion: the strict-ROM runner was rerun after the concurrent
`f3eac59` test correction and passes on `c029438` plus UI work. The initial
failure discussed below is historical. The architect also reviewed the US
set/clear helpers (`84100020` sets, `84100030` clears), verified the direct
lifecycle timeout returns, and reproduced the missing family-29 path.

No runtime or test source was changed. The repository-wide worker runner was
not rerun here because the architect reported a pre-existing baseline failure
at `sequence_test.lua:238`; the architect owns the full required checks. The
research-only validation for this file is `git diff --check` plus inspection
of the cited decomp and US assembly. The targeted lifecycle and particle-pool
tests both passed under `luajit` (50 and 10 checks). System `lua` cannot load
the repository's `ffi` dependency, so it was not used as the test interpreter.
No ROM-backed visual acceptance was run, and no conclusion here relies on the
absence of a diagnostic or on a passing test as evidence of visual parity.
