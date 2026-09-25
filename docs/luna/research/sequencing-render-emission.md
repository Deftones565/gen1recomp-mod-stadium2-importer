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

- Particle pool: implemented 2026-09-25, see below.
- 84103394 draw pass: see "Particle pool and draw passes" below.
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

Writer (decoded 2026-09-25 from the US assembly for fragment79_393CA0,
the Gen 2 battle engine; C from the fork where matched): the battle engine
queues 0x280-byte event records in a 30-slot ring at D_84195280 (write
index +0x4D81, read index +0x4D80). 84134CBC(side, code) -> 84134A6C builds
one: +0 side, +2 = 1, +4 event code, and per battler (16-byte stride from
+0xC) +C, +E HP, +10 status byte (battle mon +0x24), +12 volatile flags,
+14. 84134DD8 writes the move (+8), 84134E30 the low three result bits and
84134E00 ORs flags into +9. 84137BD4 copies the next record into
D_84199D80, which 8413E2EC passes to 8410AA18 as D_84193DD0.

Result low bits (84134E30 call sites):
- 1: 841246AC when the move is used; 84130E04 when D_841951D2 is set.
  84128298 sets D_841951D2 and zeroes damage unless the effect is 0x2D
  (the Gen 2 engine's Jump Kick crash effect), so D_841951D2 is "attack
  missed" and 1 marks a miss or failure.
- 84124A7C (damaging hits, e.g. BattleAnim_Table_84186004_080): 4 when
  D_841951E4 is 1 or 2 (84127C88 sets 1 from the D_84185484 critical-hit
  table; 8412A804 sets 2 for a one-hit KO and 0xFF when it fails), else 3
  when D_841951E5 > 10, 2 when < 10, 0 when 10 (type modifier; 84127194
  and 84132350 reset it to 10). Then 5 for moves 0x14/0x23/0x84 (Bind, Wrap,
  Constrict) or when 80062D20(move) == 0x75.
- 5 and 6 are also written by about 20 effect handlers (8412E420, 8412FD24
  and others) that are not decoded; 8412FD24 pairs 6 with flag 0x10, so
  bit 0x10 is not a critical-hit flag.

`Sequence.resultByte(facts)` builds the byte for misses and damaging hits
only and returns nil for other moves. Hosts feed it through Gen1Recomp's
`battle.damage_dealt` event (bryanthaboi/gen1recomp `8d1e155`: Gen 1
src/battle/EffectRegistry.lua and Gen 2 src/battle/gen2/Battle.lua emit
crit and the x10 type multiplier per landed hit while the turn resolves).
OHKO comes from the move's effect name (EFFECT_OHKO, Gen 1 OHKO_EFFECT) and
effect 0x75 is EFFECT_ROLLOUT (pret/pokecrystal `e058e4f`,
constants/move_effect_constants.asm).
main.lua forwards it to `Adapter.recordHit`; `playMoveAndImpact` takes the
attacker's first recorded hit for that move. Presented misses do
not reach the adapter, and status moves stay nil. With the current
consumers (841087B8 only distinguishes 1 and 6) this changes nothing on
screen yet; it is the input the result-gated behaviour above needs. Implemented: the adapter calls the host's
`onImpact(target, source, moveId)` when 841087B8 plays the impact, and the
Gen 1/Gen 2 hosts play the defender's own hit clip (Actor:hit, no fallback).
Timing is approximate (the ROM starts the clip when the defender state
begins) and the 84117948 result gating is not applied because the move to
hit-state mapping is not decoded.

## Particle pool and draw passes (2026-09-25)

Source: US assembly for fragment79_36F8B0/375530 (uploaded from the user's
pret split) and fork C `7fc529e5` for 84103394/84103478. Matches ROM
assembly; not checked against ROM execution or visually.

- 84100260 (via 84100328): from cursor D_8418C954, take the first of the 300
  0x9C-byte slots at D_8418C950 whose +0x98 is clear, wrapping at 300; mark
  it live, clear it with 84100174 (zeroes +0x20..+0x34 among others) and
  move the cursor to the next slot. When all 300 are live it returns NULL
  and leaves the cursor unchanged.
- 841072BC loops over the emission's particle count and stops the whole
  loop when 84100328 returns NULL, so the rest of that emission (for that
  marker) is not created.
- In 841072BC, emitter +9 (scheduler mode) 0 anchors through 84104D28.
  Mode 1 first sets runtime flag 0x1000 (84100020), then descriptor flag
  0x800000 selects 8410668C, otherwise 84104A00.
- 8410668C scans slots 0..299 in order for the first live slot whose
  descriptor (+0x10, flags at +4) has 0x400000 and whose runtime flag 0x2
  equals the new particle's, and adds that slot's +0x20..+0x28 to the new
  particle's +0x2C..+0x34. No match adds nothing. The new particle already
  occupies its slot; a slot not yet updated still holds zero at +0x20.
- 84101D54 (update) calls 84104A00 again only for descriptor flag 0x20000,
  so the pool origin is a construction-time anchor.
- Draw passes: 84103478 draws live slots with 0x1000 and 0x2000 set and
  0x100800 clear (0x4000 selects the 841032F0 screen path). 84103394 draws
  slots with 0x1000 set and 0x102800 clear when D_80094910+0x18 equals 3
  for shapes whose +8 has bit 2, else 0. So every mode-1 particle carries
  0x1000; which render layer each pass runs in is not traced yet, and the
  mod does not model these layers.

Runtime implementation: `Runtime:_allocateNativeSlot` (84100260),
`Runtime:nativePoolOrigin` (8410668C), and the Player anchor resolver uses
the pool origin at construction for mode-1 descriptors with 0x800000.
Slots free when a particle is inactive or dropped by abortAll/releaseHeld.
A particle counts as updated after its first runtime step. Affected moves:
55, 140, 188, 190 (origin) and every move for the cap. Cost: allocation is
one slot probe per particle unless the pool is nearly full; the origin scan
is at most 300 slots and runs only for those descriptors.
