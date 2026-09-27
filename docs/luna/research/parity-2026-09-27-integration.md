# Battle FX integration parity audit

Audit date: 2026-09-27. This is a research note only; no runtime or test
code was changed. The decomp source cited below is
`/tmp/stadium2-parity-decomp-20260927` at full commit
`0ed78d46e9cd11432f217203675a839efcb1cc1c`. The supported US assembly remains
the authority for functions left as `GLOBAL_ASM`. The working tree was clean
before this note except for the pre-existing untracked
`docs/luna/research/parity-2026-09-27-rendering.md` owned by another worker.

## Confirmed integration mismatch

### Gen 1 `ABSORB` is indistinguishable from Leech Seed residual

`lib/gen1_battle.lua:164-184` treats every `ABSORB` animation as the Leech
Seed residual when `battle.pendingHit == nil`, clears `def`, and signals entry
`0x103`. A real move 71 (`ABSORB`) also enters that branch. The host starts the
animation at `/opt/git/gen1recomp/src/battle/BattleState.lua:1499-1501`, but
only assigns `self.pendingHit` at line 1532. The mod wrapper calls
`presentAnimStart` after the original start returns at
`lib/gen1_battle.lua:724-733`, so `pendingHit` is still nil for the normal
move-start hook. The standalone move therefore gets the Leech Seed entry and
does not reach the ordinary move route; the residual path at
`/opt/git/gen1recomp/src/battle/BattleState.lua:2927-2930` has the same
animation name.

Affected context: Gen 1 move 71 (`ABSORB`), residual entry `0x103` (Leech
Seed). This is a caller/consumer ordering mismatch, not a visual-only
uncertainty. The native status dispatcher `func_84118DD4` calls
`func_8410890C(0x103)` in the supported US assembly
(`/opt/git/pokestadiumgs/asm/us/nonmatchings/fragments/79/fragment79_37A6E0/func_84118DD4.s`,
around `0x84118F34-0x84118F50`); it does not justify using a move-name test as
the discriminator. `func_8411ABAC` / `0x126` is the separate recall path.

## Confirmed missing integration inputs and dispatch

### Condition-dependent battle state has no live producer

`lib/stadium2_battle_fx_battle_adapter.lua:27-46` accepts explicit
`nativeBattleState`, then falls back to `attacker.nativeStatus` and
`owner.nativeStatusPattern`. Repository search found no host assignment for
`nativeBattleState`, `nativeStatus`, `nativeStatusPattern`, or `resultFlags`;
the only non-test consumers are `lib/stadium2_battle_fx_battle_state.lua:16-26`.
The viewer supplies neutral zeros at
`tests/stadium2_koffing_croconaw_visual/battle_fx.lua:100-104`, which is useful
for deterministic previews but is not battle state.

The unresolved inputs affect move/context IDs 168 (`THIEF`, result flag
`0x20`), 217 (`PRESENT`, result flag `0x40`), and 173 (`SNORE`, source status
low three bits plus result low three bits), plus condition-bearing entries
274, 290, 292, 298, and 299 (owner status pattern masked by `0x2FFF`). The
decomp's move state calls `func_841087B8` with the result from
`func_8411E164` in `func_84118138` at current source lines 2824-2831; the
native opcode-16 condition helper remains `GLOBAL_ASM` (`func_841083B0` in
`fragment79_377570.c:215`). These cases currently depend on an absent host
producer or the viewer's neutral default. They match the known dispatch
contract, but are not visually confirmed.

The damage result path does not repair this. `Adapter.takeHitResult` at
`lib/stadium2_battle_fx_battle_adapter.lua:764-821` converts queued host facts
to the compact `Sequence.resultByte` values used by impact routing. That value
is consulted for Curse's route gate and `impactAction`, but
`scheduleRoute`/`playMove` at lines 864-882 and `impact` at lines 672-700 do
not put it into `nativeBattleState` when they call `Player:trigger`. The
opcode-16 resolver consequently sees no `resultFlags` during an actual battle.
Even if the compact value were passed through, it has already discarded the
native `0x20`/`0x40` flag positions needed by Thief and Present. This leaves
those branches on the current condition/default path despite damaging-hit
bookkeeping being present.

The same compression makes Curse (move 174) a confirmed route mismatch:
`playMoveAndImpact` tests native result bit `0x80` at lines 844-849, but
`Sequence.resultByte` can only return 0 through 5 at lines 64-83. The actual
Gen 1 and Gen 2 callers pass no raw result byte, so the authored Curse route
cannot be selected by the normal battle path. An explicit test caller can
still supply a raw value, so the route program itself is not being called
absent.

### Gen 2 event cases still have no source-side FX event

The bridge handles status animations, recovery, drain, stages, send-out, and
one enemy-withdraw message in `lib/gen2_battle.lua:596-661`. The following
native-facing cases have no reliable event in the current host path:

| Native case | Affected entry/context | Host evidence and current consequence |
| --- | --- | --- |
| Spikes switch-in damage | `0x10B`, event code `0x46` | `/opt/git/gen1recomp/src/battle/gen2/Battle.lua:4268-4282` emits message plus `damage` with `anim=false`, but no `animMove`; `signalEventFx` therefore selects no Spikes entry. The Spikes setup move itself remains on the normal move path. |
| Attraction turn-state | `0x108`, event code `0x06`, native `84127194` | `/opt/git/gen1recomp/src/battle/gen2/Battle.lua:1032-1046` emits only the side-less love/immobilization messages during the turn check. The bridge has no side-specific event for this state. The application move 213 at lines 2905-2923 is a separate volatile-setting path. Text is not a safe substitute for the native event identity. |
| Fully paralyzed turn | `0x10C`, event code `0x36` | `/opt/git/gen1recomp/src/battle/gen2/Battle.lua:3233-3247` emits only a message. No side-specific FX event reaches the bridge. |
| Leftovers recovery | `0x10D`, event code `0x4A` | `tickHeldItem` heals and emits a message at `/opt/git/gen1recomp/src/battle/gen2/Battle.lua:5298-5319`, without the item recovery animation field that the bridge recognizes. |
| Destiny Bond | `0x123`, event code `0x55` | The current event bridge has no Destiny Bond handler; the older event research maps the native code, but no host event carries it. |

Gen 1's stat-change and paralysis mechanics have no presentation events in the
current bridge. Attract and Destiny Bond are outside the Gen 1 mechanics, so
their later Stadium contexts are not integration backlog items.

### Native special actor kinds are mostly absent

`lib/battle_actor.lua:15-22,273-275` and
`lib/battle_special_moves.lua` currently implement only kinds 6 (Agility), 7
(Double Team), and 9 (Minimize). The current decomp's
`func_8411845C` at `fragment79_37A6E0.c:2880-2900` calls
`func_84123F60` (start) and `func_84124104` (per-frame update) for the
per-move kind at actor offset `0x61F`; both dispatchers are still
`GLOBAL_ASM` at `fragment79_38EFE0.c:880-882`.

The supported US dispatcher assembly confirms this is a 24-entry switch on
`kind - 3` (`func_84123F60.s` and `func_84124104.s` under
`/opt/git/pokestadiumgs/asm/us/nonmatchings/fragments/79/fragment79_38EFE0/`),
with distinct native start/update routines for the kinds below. The gap is in
the host implementation, not an inference from move names.

The missing kind mappings affect move IDs 57 (Surf, kind `0x0A`), 66
(Submission, `0x04`), 69 (Seismic Toss, `0x08`), 96 (Meditate, `0x0D`), 110
(Withdraw, `0x0C`, except the native `D_841839EC` species set), 127
(Waterfall, `0x0E`), 185 (Faint Attack, `0x19`), 187 (Belly Drum, `0x1A`),
194 (Destiny Bond, `0x18`), and 229 (Rapid Spin, `0x13`). The existing research
maps these IDs in `docs/luna/research/battle-special-moves.md:16-23`.
This is decomp/assembly parity evidence; no visual result is asserted.

### Height input for native external-scale attachments is unpopulated

`lib/stadium2_battle_fx_battle_adapter.lua:126-150` passes
`actor.nativeFxHeightPoint` into `Endpoints.anchorHeight`, and
`lib/stadium2_battle_fx_endpoints.lua:10-21` needs it for species 95 (Onix).
No host writer for `nativeFxHeightPoint` exists in the current Lua tree, so
Onix falls through to the missing height path. The placement code reports
`approximate-common-anchor-height` for the external-scale operation at
`lib/stadium2_battle_fx_battle_adapter.lua:252-255`, associated with native
`func_8411EF90`; current decomp `fragment79_38D510.c:185-198` computes that
height from the native point and body-height result. This can shift or flatten
height-flagged particles for Onix. It is code evidence, not visual
confirmation.

## Timing, recall, and failure paths

### The sequence test assertion is stale

`tests/stadium2_battle_fx_sequence_test.lua:230-239` expects one new effect at
the dispatch hit frame. `Adapter:playMoveAndImpact` now schedules the primary
route at `timing.route` and, when no defender row is available, schedules the
fallback impact at that same frame (`lib/stadium2_battle_fx_battle_adapter.lua:824-858`).
For the test's move 2 row, `Sequence.attackTiming` computes route 14 and no
defender impact (`lib/stadium2_battle_fx_sequence.lua:222-260`), so both banks
are released on frame 14 and the effect count increases by two. The worker
baseline failure at line 238 is therefore a stale assertion against the newer
route-at-hit implementation, not evidence that the scheduler missed the hit
frame. A test using a defender dispatch row can assert route and impact
separately; root owns that test change. After changing only the count to two,
the same probe reaches line 244: the test still expects the old
`attack-state approach phases are not emulated` warning, while this fallback
passes `native=true` and emits the newer defender-row-unavailable diagnostic
at `lib/stadium2_battle_fx_battle_adapter.lua:852-858`. That second assertion
is stale for the same implementation revision.

The viewer still differs: `tests/stadium2_koffing_croconaw_visual/battle_fx.lua:97-123`
starts the primary route immediately and schedules only the impact at the
attacker hit frame. Battle scenes use the newer delayed primary route through
`playMoveAndImpact`. This is a user-visible viewer/battle sequencing divergence
and remains visually unconfirmed.

### Miss and recall behavior needs a ROM-backed decision

Gen 2 deliberately marks failed moves and says the screen skips their attack
animation at `/opt/git/gen1recomp/src/battle/gen2/Battle.lua:1442-1449`; the
bridge consequently drops `event.missed` moves at
`lib/gen2_battle.lua:440-452`. The Stadium move path nevertheless reaches
`func_84108728`/`func_841087B8` (current decomp
`fragment79_377F80.c:9-12,27-60`), where result 1 can select the authored move
family or call `func_841089D8(1)` for failure. Whether the native battle
controller suppresses the whole route before that state for each miss class is
not established here; this is an open ROM/visual question rather than an
invented fallback.

Recall coverage is asymmetric by host evidence. Gen 1 uses the host's player
`shrinkOut` edge to signal `0x126` at `lib/gen1_battle.lua:419-428`, matching
native `func_8411ABAC` and its `func_8410890C(0x126)` at current decomp lines
3384-3389. Gen 2 recognizes only the enemy trainer withdraw message at
`lib/gen2_battle.lua:557-570,645-647`; the host documents that a player switch
has no withdraw event. Treating arbitrary text as a recall signal would invent
native behavior, so player Gen 2 recall remains an open integration gap until a
side-specific host event or ROM trace is available.

## Resolved or stale claims and verification limits

- The older claim that the battle route starts immediately is stale for battle
  integration: the current adapter intentionally delays the primary route to
  the attacker's dispatch hit frame and reports approximate timing when
  approach phases are unavailable.
- Existing residual, send-out, recall, faint, weather, drain, stage, Agility,
  Double Team, Minimize, and Rest rows have implementation evidence in the
  current Lua paths, but this note does not call them visually fixed. The user
  bug log remains the authority for visual confirmation.
- No ROM-backed full worker run was performed by this worker; the known
  baseline failure is the stale line-238 assertion above. `git diff --check`
  and the final status check are the applicable checks for this research-only
  deliverable; root owns the required full worker runner and final bug log.
