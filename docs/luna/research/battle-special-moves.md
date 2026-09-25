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
