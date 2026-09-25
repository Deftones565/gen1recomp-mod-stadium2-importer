# Move/impact sequencing, render modes and emission markers

Sources: pret/pokestadiumgs c0e10f23 US assembly (all fragment-79 functions)
and michiiik/pokestadiumgs 7fc529e decompiled C. Implemented 2026-09-25.

## Direct-shape transforms (84102B3C)

841031F4 draws a shape export through 84102B3C, switching on the shape's
geometry mode (jump table 84188BD4). All modes use the scalar at object
+0x18, position +0x20..+0x28 and halfword angles +0x6A..+0x6E; angle index
is `(u16)angle >> 4` into sin D_80087E50 / cos D_80088E50.

| Mode | Function | Transform |
| --- | --- | --- |
| 0 | 841043AC -> 84103A3C | row-vector Rz*Rx*Ry, every row scaled |
| 1 | 84104528 | billboard: camera matrix +0x64 transposed, scaled |
| 2 | 84104428 -> 84103BCC | as mode 0, only the Y row scaled |
| 3 | 84104668 | billboard rotated by +0x6E, only the Y row scaled |
| 4 | 84104590 | billboard rotated by +0x6E, every row scaled |
| 5/6 | 841039AC / 841039F4 | screen (already implemented) |

Camera +0x64 is the look-at of eye/focus/up (+0xA8/+0xB4/+0xC0). Kind-3
(compiled layout) exports are drawn by the model system from 841028DC and
keep the previous transform. Code: `Packets.shapeMatrix`, Player draw.

## Render mode (84102E84)

After the material callback and before each entry display list, 84102E84
emits G_SETOTHERMODE_L from entry halfword +6: low six bits 1/4/6 (else
default), variant = (0x40?1:0)+(0x80?2:0); 0x3F binds the owner texture via
84102D38 (unused by retail entries 1..301). Decoded words and blend/depth
are in `lib/stadium2_battle_fx_render_mode.lua`; the renderer applies them per
primitive. Anti-aliasing bits are not emulated; cutout discards texels with
alpha below 32/255 (no 3-bit coverage).

## Routes and effect entries

- D_84182A5C is indexed by effect ID. Entries 1..251 are moves; 252..301 are
  non-move battle effects. 8410890C(id, owner) stores the ID/owner and the
  next 8410545C pass plays the entry's primary route. Only ID 0x12C also
  latches the alpha gate D_841901A4.
- 841052AC route modes (D_84190188): 0 = primary (84108728), 2 = alternate
  (8410874C), 1 = D_84172A1A+primary*4, i.e. the +2 half of a 0x4000
  side-variant primary (841088CC). Only moves 13, 19, 76, 91, 130, 143 have
  such a primary; their +2 routes are P69, P70, P82, P37, P394, P122.
- Hit frame: 841146D4 copies dispatch row byte 0x0B to actor+0x619;
  84117CAC fires 841087B8 when actor+0x7E8 equals it and the result byte
  (D_84193DD0+9)&7 is not 6. The attack state resets +0x7E8 after its
  approach phase (for example 841170A0); hosts that start counting at the
  move start are approximate and the adapter reports this.
- 841087B8 with result 1: moves 0x2D, 0x2F, 0x30, 0x5F, 0x67, 0xAD, 0xC3
  still reach 8410874C; Surf reaches 8410878C (mode 2 and owner, no new
  dispatch); all others take 841089D8(1).
- 841089D8(1): 84105E3C releases every slot of the 64-entry scheduler at
  D_84190150; 841003AC(1) resets D_84190218, the background and both
  battlers' colors and frees every particle without object flag 0x10000;
  84109460(1) -> 841093E8 clears all lifecycle slots; 84108974 signals entry
  0x12D only for Dig after route mode 1 (D_841901A8, set by 841088CC).
- D_841901B8 (read by 841094EC as the lifecycle presentation signal) is
  cleared by 841086F0 and set by 8410874C/8410878C. It is the wave-grid
  (families 9-11) finish signal.

## Particle flags and releases

84107170 maps descriptor flags to object flags: 0x10->0x1, 0x400->0x40,
0x8->0x200, 0x4->0x100, 0x100->0x400, 0x20000000->0x10000 (held),
0x10000000->0x20000, 0x08000000->0x8000, 0x80000000->0x40000, flags2
0x4->0x80000. 84108A10(owner) clears 0x10080 on the owner's held particles
and ends those with 0x8000. Held bits occur only in entries 254, 256, 301.
Not implemented: 84108AF8/84108CE8/84108E00/84108F88 (status-shape
exemptions need battler status inputs) and 84109118.

## Camera ray anchor (84105930)

84105B90 caches D_84190114: +0x40 eye, +0x4C focus, +0x58 normalize(focus -
eye) (84105880; coincident points give (0,0,1)), +0x64 the reverse. With
descriptor flag 0x1, 84104D28 anchors the particle at
`eye + (f32)(s16)material+6 * dir` (BattleAnim_GetPointAlongCameraRay).

## Emission markers (84107998)

Scheduler modes 0/1 call 84107998; it calls 841072BC(emitter, label,
secondary) per marker, each creating the full particle set (label at +0x7E,
flag 0x2 when secondary):

- flags2 0x1: every owner marker (owner +0xA7 count, +0xA8 list) except
  labels 0xFF and 100;
- flags 0x8: 8411E244(owner, emitter+0xA) context marker;
- D_84190178 == 0: primary (+61C, dispatch byte 2) and secondary (+61D,
  byte 3); otherwise primary only, or secondary only with flags 0x2000000.

D_84190178 is global: opcode 1 (84107CEC) and 3 (84107D24) clear it, opcode
17 (84108630) sets it, and emissions read it later. 8411E244 reads the
species table at actor+67C (the 8411E358 table) or dispatch rows 253/254.

## Still open

- 8410668C particle-pool origin (moves 55, 140, 188, 190): scans the 300-slot
  pool in slot order for a live particle whose descriptor has 0x400000 and
  whose flag 0x2 matches, then adds its +0x20..+0x28 position to the new
  particle's +0x2C offset. Slots come from the round-robin allocator
  84100260 (cursor D_8418C954, NULL when all 300 are live); the runtime does
  not model slots or the 300-particle cap yet.
- 84103394 second draw pass (object flag 0x1000, gated by D_80094910+0x18).
- Meaning of each non-move entry 252..301 and the host events that trigger
  them.

## Battle result byte and defender reaction (2026-09-25)

Source: decompiled C in michiiik/pokestadiumgs `7fc529e5`
(fragment79_37A6E0.c); matches decomp C, not checked against ROM execution.
Consumers of the result byte D_84193DD0+9 found in C:

- 84117880 at defender hit frame + 1 calls 8410B578 (writes
  D_841911E0+0x8C, zeroes +0x96) with 15.0 for low bits 0, 10.0 for 2,
  20.0 for 3, 25.0 for 4; nothing for 1, 5, 6. The reader of +0x8C is still
  asm, so its visual meaning is unconfirmed.
- 84117948 selects context 254 (0xFE) through 84112158 unless the low bits
  are 6, 2 or 5 or the move (+0x618) is 0xD4; event code (+4) 0xE forces it.
  841179C4 withholds its 84111D64/84111DB4 pair for 6, 2 and 5.
- Bit 0x10: 84116B40 lengthens the defender's hit timer to at least 40
  frames after +0x620, and 841176E0 (from 84118138) signals entry 0xFD with
  sound 0x10 at the hit frame.
- 84114600/84114678 pass mode 2 instead of 0 to 800231A0 when the low bits
  are 1.
- 84118138 and 841182E0 select 0xFE at state counter 0 unconditionally and
  signal entry 0xFE at counter 8.

Which host outcome writes each value is not in C (the writer is asm), so
hosts still pass no result byte. Implemented: the adapter calls the host's
`onImpact(target, source, moveId)` when 841087B8 plays the impact, and the
Gen 1/Gen 2 hosts play the defender's own hit clip (Actor:hit, no fallback).
Timing is approximate (the ROM starts the clip when the defender state
begins) and the 84117948 result gating is not applied because the move to
hit-state mapping is not decoded.
