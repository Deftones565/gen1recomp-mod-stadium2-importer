# Battle FX parity: camera and validation — 2026-09-27

Research only; no runtime changes or new visual-parity claim.

## Sources and baseline

- Importer checkout: `aede59e9c230b994eeddd5fb527e3b885d0813ab`;
  `git status --short` and `git diff --check` were clean before this audit.
- Current merged `michiiik/pokestadiumgs` master, verified with `git ls-remote`
  and cloned to a temporary directory:
  `0ed78d46e9cd11432f217203675a839efcb1cc1c`.
  [Pinned fragment-79 source](https://github.com/michiiik/pokestadiumgs/tree/0ed78d46e9cd11432f217203675a839efcb1cc1c/src/fragments/79).
  The existing local fork was at `204b7d8b88a27f920d2b538cc5bca278d00aed79`;
  the newer checkout changes `37A6E0`, `38EFE0`, and `393CA0` in this fragment.
- Still-`GLOBAL_ASM` functions were read from the supported US split in
  `pret/pokestadiumgs` commit `c0e10f23d90cc4f335b654711f13e53c2c07323b`.
  Pre-existing unrelated modifications in that checkout were left alone.
- Supported local US ROM: 67,108,864 bytes, SHA-1
  `d8343e69a7dc63b869cf6361d87cde64444281d3`.

## Camera remains a presentation-parity gap

`lib/battle_camera.lua` has the 39 shot rows and a field/manual-shot camera.
It does not execute the native camera programs or select them from battle
events. `Camera.update` (line 238) updates user steering; `arenaPresetPose`
(line 294) reads `state.arenaMode` and `state.arenaTarget`, and `arenaFrame`
(line 323) builds that pose. The Gen 1/Gen 2 update paths call the camera
update and steering APIs, not an event-driven camera-program evaluator.

Native evidence in `fragment79_37A6E0.c` at the pinned fork commit:

- `84111348` and `841113F8` copy seven handler pointers from
  `D_8418414C + program * 0x1C`, together with the owning actor, into the two
  camera controllers. A static shot table is only part of that contract.
- `841168A0` selects from `D_84183BDC` when an attack is initialized.
  `84114A04` chooses camera programs for explicit move IDs, including
  Fly (19), Surf (57), Waterfall (127), and Rapid Spin (229).
- `84116BC0` is still assembly. Its US body reads the move/event state and
  calls `841119CC`; that function either writes a literal shot selector or
  picks from the authored random tables for selectors `0x28..0x32`.
- `8410C934`/`8410CAE4` call `8410B974` for native actor-relative anchors
  and distance, then build the camera from the shot row. The US body of
  `8410B974` reads actor fields `+0x634..+0x654`, battle state, and species
  branches. The importer instead uses model-bound heuristics such as
  `max(40, radius, top * .5)` and `max(20, top * .45)`.

There is also a concrete manual-shot FOV discrepancy: the importer reads
`preset[7]` unchanged. Both native setup functions overwrite that table
value with 45 degrees, except shot `0x24` and the rows at `D_84184968` and
`D_84184984` (indices 37/38), which use 80 degrees. Importer rows currently
contain values such as 60 and 70. This is a code-versus-native mismatch;
the default field camera and every possible native camera-program phase
have not been compared numerically to ROM execution.

Consequences: battle framing, camera motion and effects anchored to the
camera can differ even when particle positions and textures are correct.
Camera-ray anchors (`84105930`) and wave-grid placement (`8415FC60`) already
consume the host camera; that does not make the camera itself native.
Implementing event selection and the native camera evaluator is separate
from fixing those already-implemented particle transforms. Random shot
choices must use an injected presentation RNG.

This corroborates the open work in [battle-camera.md](battle-camera.md),
now against current merged C and the relevant US assembly. It does not
promote the older field-shot assumptions to ROM-verified camera behavior.

## Validation method

Commands are run from `/opt/git/gen1recomp`. Temporary logs and research
harnesses stay in `/tmp`; they are not deliverables.

1. `STADIUM2_REQUIRE_ROM=1 mods/STADIUM2_IMPORTER/tools/run_battle_fx_worker_checks.sh`.
   The ROM catalog audit passed (251 moves, 395 programs, 18 opcodes,
   30 lifecycle families). The runner then stopped at the pre-existing
   `stadium2_battle_fx_sequence_test.lua:238` assertion, "impact bank starts
   at the dispatch hit frame". It is a failed gate, not a complete pass.
   See the integration note for the timing-expectation diagnosis.
2. The tests after `sequence_test` in the runner's glob order were executed
   separately with the same ROM, followed by both Gen 1/Gen 2 integration
   tests. These passed. Passing them does not repair the failing gate.
3. `luajit mods/STADIUM2_IMPORTER/tools/audit_battle_fx.lua` regenerated the
   251-move sweep: 1,004 scenarios, 360 ticks each, draws every 15 ticks,
   finish at tick 120, zero execution failures. This uses separate banks,
   both source sides, Koffing/Croconaw bind-pose battlers and a neutral
   battle-state fixture; it is not an in-battle sequence or GPU audit.
4. A second temporary copy of that same sweep replaces only its
   `renderer(model)` stub with `Renderer.new(model, {flipY=false})` and
   replaces that renderer's `drawScene` with the existing finite-matrix
   validator. It therefore exercises real FX-model pose/marker evaluation
   without invoking GPU draws. The original repository harness is unchanged.
   This specifically tests whether its animation/dynamic-anchor diagnostics
   are caused by absent `seekFrame` and marker APIs in the original stub.

The current results and interpretation are recorded at the top of
[the implementation audit](../../battle_fx_missing_implementation_audit.md).
Neither sweep proves final colors, texture filtering, visibility, layer
order, frame time, all species, all result/status branches, charge variants,
or the 252..301 battle-event entry sequences. The earlier 502-bank
draw-count/peak-particle table and the 528-function call-graph census were
not regenerated. Keep their historical counts separate from this sweep.
