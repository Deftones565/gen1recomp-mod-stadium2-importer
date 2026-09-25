# Battle camera direction (in progress)

Web session, 2026-09-25. Sources: US assembly for fragment79 (user's pret
split), michiiik/pokestadiumgs `7fc529e5` C. Matches ROM assembly; nothing
here is visually confirmed. This note records the architecture decoded so
far and the plan; the mod still holds the field shot in battle.

## Two layers

1. **Camera programs.** 84111348(owner, program) copies 7 handler pointers
   from D_8418414C + program*0x1C into D_841911E0 +8/+0x10/.../+0x38 and
   stores the owner actor in +4/+0xC/.../+0x34; 841113F8 does the same for
   D_841911E4. There are 32 programs (0-31); most use slot 0 (eye path) and
   slot 1 (look/zoom), a few a third slot; unused slots hold the no-op
   8411123C. 52 distinct handlers, almost all GLOBAL_ASM. Reachable closure:
   129 functions, ~7,100 instructions (13 in main code, e.g. 800371B4).
2. **Shots.** D_841911E0+0x98 is the shot index into D_8418455C (39 rows,
   now all in `lib/battle_camera.lua`). 8410C934 / 8410CAE4 (C) set up a
   shot: 8410B974 computes the target from the actor (yaw from +0x20, or
   8411E140 for the eight species in D_8418393C), then pitch/yaw from the
   row (yaw relative to the actor's facing), distance = camera+0x74 * row
   distance, field of view 45 (80 for shot 0x24 and rows 37/38), and
   800371B4 places the eye. 841203B4 (C) eases values per frame
   (v += (goal - v) * rate). 8410B884 is the B-variant setup.
   The shot index 0x27 (written by 84113E7C) reads past row 38; unresolved.

## Who selects shots (writes to +0x98)

| Writer | Shot |
| --- | --- |
| 8411F94C (event 0x5A, turn start) | random of 5 from D_84183C60, program 10 |
| 841168A0 / 84116BC0 (attack) | random of 6 from D_84183BDC, or fixed 3 / 0x16, or per-move via D_841849BA + move*8 -> 841119CC |
| 8411A3D4 (faint) | random of 3 from D_84183C74 |
| 8411ABAC | random of 4 from D_84183C7C, 0x11 for event 0x20 |
| 84113E7C (codes 0x5C-0x69) | D_84183C44 / D_84183C54 / 0x27 |
| 8411BB04 (send-out family) | D_84183AA8 |
| 8411A19C | 0x24 / 0 |
| 841157D8 / 84115940 / 84115D4C / 84119CF0 | 8 / 0x10 / 0xE / 0x25 |
| many states | 0 on entry or exit |

84116BC0 also copies per-species, per-move dispatch row bytes +0x10..+0x13
to actor +0x628/+0x62A/+0x62C/+0x661, special-cases moves 0x17 (Stomp),
0x22 (Body Slam), 0xCD (Rollout), 0x12 (Whirlwind), 0x2E (Roar) and the
species list D_84183A0C via actor +0x61F, and branches on the event code.

Programs per state family (from the event-code chain in
battle-event-effects.md): 0, 1, 2, 3, 4, 6, 7, 8, 9, 10, 11, 12, 13, 14,
15, 21, 24, 25, 26, 27, 28, 29 are selected.

## Plan

1. (web) Decode the shot/program choice per event and per move into a
   director table: which program and shot each presented event selects,
   with the random tables and the per-move rows. Pure decoding, unit tested.
2. (local) Camera math with the ROM: run the program handlers in the FX
   MIPS VM (as lifecycle families already do), or port them and compare
   against the VM. Needs the ROM and the fragment image, so it belongs to
   the local session.
3. (web) Drive `battle_camera.lua` from battle events through the director,
   using step 2's evaluator.
Random choices must use an injected presentation RNG, never the battle RNG.
