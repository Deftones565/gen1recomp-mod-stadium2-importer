# Moves with empty FX banks, and per-move actor behaviours

Web session, 2026-09-25. Sources: US assembly for fragment79 (user's pret
split), michiiik/pokestadiumgs `7fc529e5` C (Math_StepToF 8003730C).
Matches ROM assembly; not visually confirmed.

Growth (74), Agility (97), Double Team (104), Minimize (107), Metronome
(118), Splash (150) and Rest (156) have empty move and impact banks. What
Stadium shows for them:

- Every move plays the species' own attack clip from its dispatch row
  (84114804 -> 841146D4). For Growth, Metronome and Splash that clip is the
  whole presentation: 84114804 gives them no behaviour kind (0xFF). The mod
  already plays it (Actor:attack). Metronome's called move is presented by
  the host as its own move.
- 84114804 also sets a behaviour kind at actor+0x61F per move: 0x39 Surf
  0xA, 0x42 4, 0x45 8, 0x60 0xD, 0x61 Agility 6, 0x68 Double Team 7, 0x6E
  0xC (unless the species is in D_841839EC), 0x7F 0xE, 0xB9 0x19, 0xE5
  0x13, 0x6B Minimize 9, 0xBB 0x1A, 0xC2 0x18; others 0xFF.
  8411845C runs the kind's start routine (84123F60, jtbl_84189D40) at the
  hit frame and its update (84124104, jtbl_84189DA0) every later frame of
  the attack state. Agility: 841218EC / 84121920 (108 lines); Double Team:
  84121CAC / 84121DE8 (81 / 349 lines). Decoded below.
- Minimize (kind 9): start 84122990 is empty; update 84122998 sets the
  uniform scale (actor +0x30/+0x34/+0x38) to Math_StepToF(scale, 0.8f,
  0.01, 0.01) unless it equals 0.8 as a double (a float 0.8 never does, so
  the step clamps). 84112580 at hit+10 only sets an event flag; the state
  runs until its clip ends. Implemented as an actor size factor, kept until
  the Pokemon is replaced. Assumes the base scale is 1.0 (84123858, kind
  0xF, also computes scale as 1.0 - x): needs ROM confirmation.
- Rest: BattleAnim_Dispatch_017 sends move 0x9C to 841153DC. At the hit
  frame it plays the empty move route, sound 0xC, 841122D4 (sleep context
  261) and signals entry 0x100 on the user. Implemented: entry 0x100 at the
  hit frame; the sleep pose follows from the presented sleep status.

## Kinds ported 2026-10-01 (second batch)

Kind -> start / update (84123F60 / 84124104 cases via jtbl_84189D40 /
jtbl_84189DA0, index kind - 3). US asm (pret `c0e10f2`) and fork C
`15201a6`; constants read from the ROM. Each is checked against the ROM in
the VM by `tests/stadium2_behaviour_kinds_rom_test.lua` (scale or
position, tick by tick). Port: `Special.ROUTINES`, applied as
`nativeAxisScale` / `nativeOffset` by the actor and `Scene:modelMatrix`.

- 0xC Withdraw (110; not for D_841839EC's species 7/8/9): 84123914 (empty)
  / 8412391C: each scale axis steps toward 0 by 0.05; at Y <= 0.1 (double)
  all three become 0.001.
- 0x1A Belly Drum (187, counter-0 start): 84122C94 / 84122CCC: phase +=
  speed (0xAAA, += 0x4FA), amplitude 0.2 * 0.85 per tick, scale (b - s,
  b + s, b - s), the base back once the amplitude <= 0.01.
- 0xE Waterfall (127): 84122D74 / 84122DD8 with the ballistic pair
  84120464 / 841204BC (speed 1.0 straight up, toward 2.0 by 0.002, drag
  0.01, factors 0.05, gravity 18); holds at 90 above +0x650.
- 0xA Surf (57): 84122A04 / 84122A0C: height = +0x650 + 84159FA8(x, z)
  (the running terrain grid, `W.heightAt`, through lifecycle -> player ->
  adapter -> actor). The X tilt (+0x1E = trunc(slope) * 182) is kept but
  not applied: the battler model's rotation order is not checked.
- 0x18 Destiny Bond (194): 84123E74 / 84123EB0: targets X/Z * 0.3, Y * 2;
  from the 15th tick a speed (toward 0.2 by 0.0017) steps the scale there.
- 0xF (the defender of Stomp 23 / Body Slam 34, 84116BC0): 84123828 /
  84123858: phase 0x71C += 0xCCC, amplitude 0.4 toward 0 by 0.02, s =
  SINS(-|phase|) * amplitude, scale (1 - s, 1 + s, 1 - s) on the constant
  base 1.0. Started by `Actor:hit` at the defender's row byte 7.
- The kind reset 8412063C re-places the battler and sets scale 1,1,1, so a
  kind's scale and offset end with its state (the port clears them when
  the attack or hit clip ends).

Third batch (same day), also ROM-checked in the kinds test:
- 0x4 Submission (66): 84121260 / 841212A0: the facing spins (+0x604 ->
  +0x20): speed toward 0x3330 by 0x16C (800372CC) for 3 passes of the
  side's facing (841211CC), then a wind-down (speed * the turn left, double
  0.8 = D_84189C68, at least 0xE38) to the facing. `Actor.nativeYaw`,
  applied by `Scene:modelMatrix`. 84120464's velocity is set but unused.
- 0x13 Rapid Spin (229): 8412142C / 841214C0: the other way (-speed,
  toward 0x3A4C by 0x2D8) for 13 passes, Y scale toward Y * 1.3, a hop
  (841204BC(1.24, 0.009, 0x4000, 18), never below +0x650) from the 4th
  pass; wind-down 0.7 (double), at least 0x1554; lands with Y = target /
  1.3.
- 0x19 Faint Attack (185, counter-0 start): 8412230C / 84122448: two copy
  slots (+0x2D8, stride 0x170): alpha toward 0x80 by 0xF, speed toward
  0x222 by 0x64, phase held at 0x3F46 from 0x4000, placed SINS(phase) *
  body height / 4 * (+1 / -1) along the facing; the battler's alpha by
  copy 0's phase as Double Team's (0.9), at least 0x80. The copies' pose
  calls (8003EB84 / 8003F2C4) are the port's shared-pose afterimages.
- 0x8 Seismic Toss (69): 84121AB8 / 84121B18 roll the camera: two
  84120310 steps (toward 0x5B0 by 0x3C; toward -0x8000 by that) turn the
  GeoCamera's up vector (+0xC0) around the view direction. Ported in the
  camera (`Native:seismicStart` / `seismicUpdate`, run by `attackFrame`
  for kind 8 at and after the hit frame, before the camera's tick); the
  attack's end (84111BEC -> 841206D0) does not reset the up vector, so the
  next shot's setup does. The view now takes the GeoCamera's up vector
  (`Renderer.lookAt` up argument, `battle_camera.lua`), which also lets
  the existing rolled shots (camera native line 1669) roll on screen. The
  camera director oracle clears +0x61F in its attack rounds, whose kinds
  are stubbed there.

Surf's X tilt (+0x1E), same day: the battler is a display object (fork
`S1_unk_D_86002F58_004_000`: rotation +0x1E, position +0x24, scale +0x30).
Its matrix is built by 8003BCB4 (US asm): flag +0x02 bit 0x80 picks
80036284, otherwise 8003614C, then 80036C6C applies the scale. Both
builders are GLOBAL_ASM in the fork; their order comes from ROM execution
in the VM: 8003614C is translate * Ry * Rx * Rz (column vectors; the
model is turned about Z, tilted about X, then faced about Y); 80036284 is
v -> (v + p) * R^T in row vectors (move by +p, then the opposite angles in
reverse order: a camera-style transform, not the inverse of 8003614C);
80036C6C scales the model first.
The scene already builds translate * Ry * scale in Stadium's axes with the
ROM's Y sign, so the tilt (`Actor.nativeTilt`, from `surfTilt`) goes
between the facing and the scale, and its angle is also the lighting's
pitch. Kinds test: the scene's battler matrix equals 8003614C's for two
tilts at the battler's facing.

Fly and Dig's charge turns (same day; fork C 15201a6, US asm pret
c0e10f2; kinds ROM-checked in the kinds test, the flow in the special
moves test):
- Fly (event 0x1A): 841155E8 loads row 0x100 (841155B0: kind 3) and plays
  its clip from frame 0 (84111DB4(actor, 0); the port used to seek row
  byte 6, which is non-zero for one species). Dispatch_045 / 841156D0: at
  counter == +0x619 (row byte 0x0B) kind 3 starts (841210CC: 84120464(1.0,
  0x4000)) and updates every later tick (84121130: 841204BC(1.45, 0.015,
  0x4000, 18), held at origin + 200); a clip end plays 0x106 (262, looped
  by the port); at 200 above +0x650 the kind ends (841206D0: flags only,
  the height stays) and 841157D8 loops 0x106.
- Dig (event 0x1B): 84115A64 loads row 0x102 (84115940: kind 5) and plays
  nothing new; 84115B34 substate 1 (the tick after frame 0x19) plays the
  row's clip from frame 0 and, except for Diglett / Dugtrio, starts kind 5
  (841217C8), updated from substate 2 (841217E4: the facing spins, speed
  toward 0x3FFC by 0x16C, 3 passes of the side's facing, then keeps
  spinning while Y steps toward (s32)(-(+0x648) * 3.5) by 5). 84115988
  replays the clip at its end and hides the battler (8411EE74) once
  Y <= -3 x +0x648 (+0x648 = profile +0x14). Diglett / Dugtrio play the
  clip to its end (84115A24) and stay shown.
- 84120700 (every re-pose) puts the battler at home, then at home + 200
  while record +0x12 bit 1 (flying) or +0x7F4 bit 3 (set by 84114A04 for
  move 0x13, cleared at the attack end), and hides it for bit 2
  (underground) unless Diglett / Dugtrio.
Port (battle FX on; with it off the hosts' own presentation stays):
`Actor:startNativeCharge` / `stepNativeCharge`, `Actor.nativeLift`,
`Scene:stepNativeCharge` / `nativeChargeVisibility` / `hostCharging`
(Gen 1: invulnerable + charging; Gen 2: the presented chargeMove), a
`visualState` wrapper in both hosts over the renamed `hostVisualState`
(the host bookkeeping still runs), Gen 1's pic lift off while it runs,
and the camera's Fly height / Dig sunk checks read the actor's state.
Shot resets (same day, replacing two earlier approximations): with the
camera director running, the battlers' pose and the Fly / Dig visibility
follow Stadium's shot resets exactly:
- 84120BB4 (every plain new shot, fork C): 8411EF2C (the shot's battler
  shown, the other hidden: +1 bit 0) and 84120700 on both. The camera port
  left 8411EF2C to an unimplemented callback; `StadiumCamera:
  statusVisibility` now writes it, so the camera's +1 bits are Stadium's.
- 84120700 (US asm): `StadiumCamera:actorReset` hides for record bit 2
  (not Diglett / Dugtrio), +0x7F4 bit 2 and record HP 0, and
  `Actor:nativeReset` re-homes, sets scale 1 and lifts 200 for record
  bit 1 or +0x7F4 bit 3 (the camera's own Fly attack bit, set by
  84114A04, cleared at the attack end). 8411EFE4 is `Actor:nativeHome`.
- The record's +0x12 / +0x22 flags (84134A6C, US asm): bit 0 Substitute
  (substatus4 bit 4), 1 flying / 2 underground (substatus3 bits 6 / 5),
  3 minimized (battle mon +0x2A, set by 84125CF8 for evasion by Minimize,
  0x6B), 4-6 the weather (+0x9C4 1 / 2 / 3). Written each sync from the
  presented host state (`Scene:stadiumRecordFlags`: Substitute and the
  charge); the charge turn's own record has neither charge bit, since
  8412C47C builds it (84134CBC) before setting them. Bit 3 stays 0: the
  engines keep no minimized flag (open question: Minimize's program-10
  scale, 84120AC4, therefore never applies). Bits 4-6 are not written;
  nothing in the port reads them.
- A behaviour kind's position, facing and scale persist after the attack
  (841206D0 only clears flags) until the next 8411EFE4 / 84120700
  (`Actor:endNative`); the copies end and the alpha returns to 0xFF at
  the attack's end. This holds for every kind (Waterfall stays 90 up until
  the next reset, Minimize's 0.8 until then).
- Fly: program 15 (84120A50) re-poses only the other battler, so the
  risen battler stays up; every later record has bit 1 and lifts it; its
  attack's resets lift it by +0x7F4 bit 3; the first reset without either
  brings it home and ends the state.
- Dig's attack (Dispatch_107 / 108, 84115D98): program 6's reset
  (84120D34) hides the attacker (not Diglett / Dugtrio); the state keeps
  Stadium's visibility until a later shot shows the battler.
Without the director there are no shot resets: the earlier host-driven
end (the host's charge and the attack state) remains as a degraded path.
Not ported here: 84120700's status particle calls (84108F88 / 84108E00,
84112290), already listed as missing in parity-2026-09-27-runtime.md.
Tests: camera controller (shot resets, flags), special moves (pose
persistence, Fly / Dig under the director).

Flag bit 0x80 (traced, same day; US asm pret c0e10f2, fork C 15201a6):
the battler never gets it, so it always uses 8003614C.
- Every store of a value with bit 0x80 to a +0x02 byte in all US asm
  (main and every fragment; immediate or ori, same register, within 12
  instructions): 80041548, 80042D8C, 80043C14, and in fragment 79 only
  colour tables (841254E0, 841003AC, 84105120) and battle-engine move data
  (8414E2A8, 84149F30, 84149FB8). The matched C has no such write.
- 80041548 is the model-file loader's creator (thread 80041A78, message
  type 1 via 800416C8; message from 80041FD0). Fragment 79 does call it,
  for the battler (84112FD0 from 84116460 / 8411B75C / dispatch 0x99),
  with argument 4 = 8006456C(DVs), the Gen 2 shiny rule
  ((DVs & 0x2FFF) == 0x2AAA). But the object it flags is the loaded model
  file (part count +3, relocated part table +8, palette variant in +2's low
  nibble, 0x80 = shiny variant from 8004B98C), not the display object that
  8003BCB4 draws.
- 80042D8C (display objects: it calls 8003F2C4, then clears 0x40 and sets
  0x80) and 80043C14 are reached only through 80042EB8 / 8004300C /
  80043064 / 80043E70, whose callers are fragments 14, 20, 22, 31, 32, 33,
  37, 38, 44, 45, 59, 68, 72 and 73; never fragment 79. Static call graph;
  calls through function pointers would not show.

## Meditate (kind 0xD) (2026-10-01)

Source: US asm `fragment79_38EFE0/func_84122AB8.s` (GLOBAL_ASM in the fork)
and fork C for 84122A78 (michiiik/pokestadiumgs, the commit recorded in
battle-camera.md for this span); constants read from the ROM: D_84189CB8
0.4, D_84189CBC 0.01, D_84189CC0 0.8. Case labels 8412400C (start) and
841241B0 (update) in 84123F60 / 84124104 call them.

- Start 84122A78: +0x5FC = 0x16C, +0x5FE (phase) = 0, +0x600 (speed) = 0,
  +0x60C (amplitude) = 0.4, +0x5E4 / +0x5F0 = the X scale, +0x5F4 / +0x5F8 =
  Y / Z scale, stage +0x624 = 0.
- Update 84122AB8, stage 0: if 0 <= +0x5FC <= 0x8000 it gains 0x2D; speed =
  trunc(SINS(+0x5FC) * 182 * 15); if 0 <= phase <= 0x4000 phase += speed;
  s = SINS(phase) * amplitude; scale = (base - s, base + s, base - s) (tall
  and thin). Once phase >= 0x4000: speed 0x1554, stage 1.
- Stage 1: phase += speed; if SINS(phase) * amplitude <= 0.01 then speed +=
  0x444 and amplitude *= 0.8; the same formula sets the scale; once the
  amplitude is <= 0.01 the scale is the base on all three axes.
- Port: `Special` kind 13, `Actor.nativeAxisScale`, applied by
  `Scene:modelMatrix` after the battler's uniform scale (the floor offset
  uses the Y factor so the feet stay on the ground). The base is the
  battler's own scale (1.0 relative). Test:
  `tests/stadium2_meditate_rom_test.lua` runs both routines in the VM for
  240 ticks and matches the Lua tick by tick. Matches ROM execution; not
  visually confirmed.

## Agility (kind 6) and Double Team (kind 7)

Decoded 2026-09-25 from the US assembly (fork C `7fc529e5` for the helpers
named there). Implemented in `lib/battle_special_moves.lua`; matches the
assembly by reading, not checked against ROM execution or visually.

8411845C calls the start routine on the hit frame and the update on every
frame whose counter (+0x7E8) is at or past the hit frame (+0x619), start
first; move 0xCD (Rollout) skips both.

Afterimage slots: two model instances at actor+0x2D8, stride 0x170, same
struct as the battler's model (S1_unk_D_86002F58_004_000): +0x01 bit 0
enabled, +0x1D materialAlpha, +0x1E rotation, +0x24 position, +0x30 scale.
8411283C/84112A40 load the battler's model into them; 8412060C/8412063C/
841206D0 clear bit 0 and are called by most other states, so the copies
vanish when the attack state ends.

**Agility.** Start 841218EC zeroes +0x5FE (phase), +0x5FC, +0x623, +0x624
(stage), +0x60C (amplitude), then 84120E7C enables both slots with alpha
0x80 and copies position, rotation and scale. Update 84121920:

- stage 0: amp = 841203B4(amp, 50.0, 0.1) (v += (t - v) * r, snapped to 0
  inside +/-0.001, D_84189C30/38); stage 1: target 0.0.
- phase += 0xE38; s = SINS(phase) * amp; 8412041C gives (COSS(yaw) * s, 0,
  SINS(yaw) * s) with yaw = actor+0x20; 8411EFE4 resets the home position,
  800357CC adds the vector. So the sway is lateral to the facing.
- stage 0 -> 1 when amp > 49.0 (tick 38); in stage 1, amp <= 0.5 calls
  8411EFE4 again after the add (back home).
- 84120F5C(actor, 0) for each slot i: copy the battler's animation frame
  and speed; (dist, pitch, yaw) = 80037120(battler, slot); 800371B4 puts the
  slot at dist * D_84183C98[i] (0.3, 0.45) along the same angles; the slot
  yaw steps toward the battler's by 10 / 40 (D_84183CA4, 84120310). The mod
  uses the equivalent lerp without the 4096-step angle quantisation; the
  battler does not turn, so the slot yaw is unchanged.

**Double Team.** Start 84121CAC: per slot enable, +0x444 (speed) = 0,
+0x442 (phase) = D_84183CB8[i] (0, -0xE38), alpha 0, position and rotation
copied, scale set to 1.0 (800357A8), animation frame and speed copied.
Update 84121DE8, per slot i:

- alpha = Math_StepToS32(alpha, 0x80, 15, 15) (800372CC);
- speed = Math_StepToS32(speed, 0x222, 100, 100); phase += speed (s16);
- s = D_84183CCC[i] * (SINS(phase) * actor+0x64C / 4.0), with
  D_84183CCC = 1.0, -1.0 (two more floats, -0.2 and 0.4, are copied but not
  read); slot position = battler position + 8412041C(s, yaw);
- animation frame and speed copied from the battler.

Then the battler's own alpha (+0x1D) comes from slot 0's phase p: 0 <= p <
0x4000 uses COSS(p), p >= 0x4000 COSS(p + 0x8000), p < 0 SINS(p); value =
trunc((w * 0.9 + 1.0) * 255.0) stored with sb, so results above 255 wrap
(p = 0 gives 484 -> 228); then any value <= 0x80 becomes 0x80.

actor+0x64C is the species battle profile +04 (84112704; profile 0x30 bytes
at ROM 0x49DA60 + (species - 1) * 0x30, already read as
`Dispatch.battleProfile(...).bodyHeight`).

Mod mapping: the offsets are Stadium units relative to the home slot and
are scaled by the arena scale in `Scene:modelMatrix`; the copies are drawn
by the scene with the battler's renderer, their own matrix and
tint alpha = materialAlpha / 255. The Double Team copies' scale 1.0 is taken
as the battler's base scale (same assumption as Minimize). Open: the sign
of the lateral axis in the mod's arena space (the mod uses Stadium X/Z
as-is for the slots) and how Stadium's render mode treats depth for a
materialAlpha model; the mod draws the copies with depth writes on.
