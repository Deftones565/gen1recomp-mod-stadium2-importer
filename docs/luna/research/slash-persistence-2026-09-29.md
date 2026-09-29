# Slash marks staying on screen (Scratch / Slash / Cut / Fury Swipes)

Date: 2026-09-29. Research only; no runtime change. Status: **cause in the
port identified, native end of the effect not yet found**.

Sources: supported US ROM (`baseroms/stadium2.z64`), assembly from
`pret/pokestadiumgs` `c0e10f23d90cc4f335b654711f13e53c2c07323b`
(fragment 79 functions below are still `GLOBAL_ASM`). ROM offset =
vaddr − `0x83D90770`. The michiiik fork was not consulted for this note.

## User report

In battle, the slashing effects stay on screen after they have played.
(The per-move table rated Scratch (10) "good" in the viewer, which predates
the 2026-09-27 screen-particle changes.)

## What persists in the port

CPU probe with the audit harness setup (`tools/audit_battle_fx.lua`, real
ROM catalog, Koffing/Croconaw skeletons), sampling the player snapshot every
30 ticks for 480 ticks, both banks, player side:

| Move | Bank | Common particles | Screen colour layer (mode 8) |
|---|---|---|---|
| 10 SCRATCH, 15 CUT, 154 FURY SWIPES, 163 SLASH | move (P206 / P221 / P206 / P212) | **1 particle alive until ~tick 285** | ends at age 16 (inactive, alpha 0) |
| same | impact (P207 / P222 / P377 / P213) | none after tick 30 | ends at age 18 |

The screen colour layers retire correctly and the player skips inactive
ones (`stadium2_battle_fx_player.lua` `drawOverlay`). Finished instances stay
in `screenInstances` (see timing audit T04), which is storage, not drawing.

The long-lived object, move 10 (P206):

- program 206 records 7 and 10 (the two arms of the opcode-16 branch),
  opcode 14, **mode 7** (common screen particle, `stadium2_battle_fx_rom.lua`
  treats modes 0/1/7 as common), one particle, shape **82**, born tick 30
  (descriptor start delay `0x1E`);
- screen position (0, 240), rotation Z −10240, drawn with `matrixYScale`
  (geometry mode 6, `841038F4` scales only the second model axis);
- scale 1.0 → 6.2 in about 6 ticks, then held; material alpha 255 the whole
  time; `nativeHidden` never set;
- dies at age 255 (the exact `0xFF` check), i.e. about 8.5 s at 30 Hz.

ROM records (vaddr, bytes):

- descriptor `0x841797B4`: `1E000101 00000000 00000000 84179790 00000000
  841797A4 03E81838 03620000` — start delay 30, count 1; material
  `0x841797A4`; inline scale entry initial 1000, target 6200, step 866,
  start age 0 (decoded `lifetime` field = 0).
- material `0x841797A4`: `00520000 00000000 00000000 00000000` — shape 82;
  `+4` end age 0; `+0xC` alpha-ramp pointer 0.
- geometry `0x84179790`; event `0x84179848`.

By contrast the impact bank's slash (P207 record 3, same shape) has
`nativeAlphaRamp {startAge 0, step 16, target 0}` and fades out in ~16 ticks.

Shape 82 (`tools/dump_fx_colors.lua 10`): geometry mode 6, one 64×64 texture
(fmt 3 siz 1), combiner alpha = TEXEL0 × PRIM; controller mode 1 (clamps),
11 frames, environment 255,160,0 → 255,0,0 and primitive 255,255,0 → 255,0,0,
**primitive alpha 255 throughout**; no texture scroll. So the shape does not
fade itself.

## Native retirement rules checked

`8410009C` (called from `841029DC`) returns "retire" when any of:

1. object byte `+0x92` is 0;
2. age `+0x7F` == 0xFF and object flag bit 1 is clear (`84100074`, see T03);
3. object flag `0x20000` is set and `+0x24` (Y) ≤ 0.

`+0x92` is set to 1 by the constructor `84100174` and cleared by
`84100094` / `84100348`. Callers of the clear, and why none applies here:

| Clear site | Condition | This particle |
|---|---|---|
| `84101D54` @ `84102354` | material `+4` end age == age (flag bit 1 selects hide `0x80` instead) — already ported (`nativeMaterialEndAge`) | end age 0 |
| `84101D54` @ `84102618` | alpha ramp at material `+0xC`→`+4` reaches its target with flag `0x40000000` | no ramp |
| `84100DE4` | colour tracks finished | descriptor `+4/+8` are 0 |
| `84100B3C`, `84100C68` | mode 2/8 and mode 5 colour controllers | not those modes |
| `8410291C` | model animation finished (mode 0 with a secondary shape) | mode 7 |
| `84108A10` → `84100348` | owner's held particles (flag `0x10000`, killed if `0x8000`) | flags 0 |
| `84108AF8` / `84108CE8` → `84100348` | status-shape releases | not a status shape |

Opcode 3 at the end of P206 only clears the condition / marker select
(`84107D24`); it does not release particles.

Pool lifetime: `84100134` allocates and zeroes the 300-slot pool
(`0xB6D0` bytes). Its only caller is the FX init `84105120`, reached from
`8410580C` command 0, which is issued only by `8410AA18`, called from
`8413E2EC` (pushes a main-pool state: battle-scene setup). The per-frame
update (command 2, `841055D8`) and draw (command 5, `84105630` →
`84103394` / `84103478`) are issued from `8413D37C` (and `8413C820`).
`84103478` has no global gate. So the pool is not cleared per move.

## Also ruled out (second pass, same day)

- **Per-frame loop.** `841029DC` walks the 300 slots, dispatches on the
  object mode `+0x7C` through `jtbl_84188BB0` (ROM `0x3F8440`), then calls
  `8410009C` and on retire `8410488C` + `84100350`. Table: mode 0
  `84102A3C` (common `841027B4` + model animation `8410291C`), 1 `84102A54`
  (common unless flag `0x800`), 2 `84102A9C` (`84100B3C`), 3 none, 4
  `84102AAC` (`84105930` + `84100B3C`), 5 `84102ADC` (`84100C68`), 6
  `84102AEC` (`84100DE4`), **7 `84102A78` (common unless flag `0x800`,
  same as mode 1)**, 8 `84102ACC` (`84100B3C`). So mode 7 has no update or
  retirement of its own. Flag `0x800` would freeze a particle (no aging);
  the port never sets it for this particle.
- **Clock.** The FX update `841055D8` calls `841029DC` once per call; no
  multi-tick loop.
- **Screen orientation.** `84105630` emits `guOrtho(0, 320, 0, 240, -2, 2, 1)`
  before `84103478` (Y up). The port's overlay projection
  (`y_ndc = -y/120 + 1`) draws into the scene canvas, where raw clip +1 is
  the bottom (`LOVE_CANVAS_Y`, `battle_camera.lua`), so it is already Y up.
  **Not a bug** (an earlier suspicion of a vertical flip was wrong).
- **Placement.** `8410383C` and `841038F4` match the port's `matrix` /
  `matrixYScale`. Position table `0x84179788` = (−160, 120, 0), moved to
  (0, 240) by the screen-centre step `84107784/90` exactly as the port does.
  Shape 82 is one quad, x −64..64, y −63..0. At scale 6.2, angle −10240,
  its native corners are about (−36,187) (289,−30) (360,76) (36,293): a
  diagonal from the top-left to the bottom-right of the 320×240 screen, fully
  visible. It does not leave the screen.

## Conclusion so far

By every decoded field, the P206 slash particle is alive and at full alpha
for 255 ticks in the ROM as well. The user sees it disappear in Stadium 2,
so at least one of these holds (not yet established):

1. ~~Stadium places the stretched slash off-screen~~ — ruled out above;
2. another retirement path exists outside the particle module (a battle-side
   routine writing the pool directly) that this search did not reach;
3. ~~a faster FX clock~~ — ruled out above;
4. the battle path in the port differs from the preview harness used here
   (for example the route re-fires, or the scene stops updating the FX
   between turns so the particle never ages). Not yet checked: the Gen 1
   integration test mocks the adapter, so it cannot show this.

The user's own observation decides between "matches the ROM" and "port
bug": does the slash vanish after about 8 s in our battle, or stay until the
next move / for good?

Do not add a fade, timeout or clear that the ROM does not have (AGENTS.md
accuracy rules). A temporary non-native stopgap is only acceptable if the
user asks for it, labelled as such.

## Next steps

- Ground truth: capture Scratch (move 10) in Stadium 2 itself (ares or
  mupen64plus are installed locally) or from a reference video, and compare
  frame by frame with the viewer's SEQ playback of the same move and side.
- If the slash leaves the screen in Stadium: compare the mode-7 matrix built
  in `Packets.build` against `8410383C` / `841038F4` (axis, units, origin,
  the screen viewProjection in `Player:drawOverlay`).
- If it is cleared: trace which routine writes `+0x92` or `+0x98` for that
  slot at that frame (the emulator's memory watch on the pool at
  `D_8418C950`, 0x9C-byte records).

## Reproducing

From `/opt/git/gen1recomp`, copy the setup of `tools/audit_battle_fx.lua`
(lines 1–76: ROM, catalog, actors, `Preview.new`), then per move:
`preview:start(move, "player", alternate, scene)`, `preview:finish()` at
tick 120, and every 30 ticks read `preview.player:snapshot()`:
`particles` (count, and each particle's `age`, `scale`, `material.nativeAlpha`,
`event.mode`, `shapeId`) and `nativeObjects.screenInstances` (`active`,
`age`, `rgba[4]`).
