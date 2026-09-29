# Move record inputs: Thief, Present, Curse, Snore, shiny contexts — 2026-09-29

Local session. Sources: US assembly in pret/pokestadiumgs
`c0e10f23d90cc4f335b654711f13e53c2c07323b` (`asm/us/nonmatchings/fragments/79/`,
data table in `asm/us/data/fragments/79/fragment79_data.data.s`) and C in
michiiik/pokestadiumgs `15201a6` (`src/fragments/79/`). Read from the
assembly; not run in the emulator. Nothing here is visually confirmed.

## The record

`D_84193DD0` points at the battle engine's current event record (copied by
84137BD4 into D_84199D80; see `sequencing-render-emission.md`). 841083B0
(opcode 16) reads result byte +9, and per battler (16-byte stride from +0x10)
the status byte +0x10 and the word +0x14. The builder 84134A6C copies +0x10
from battle mon +0x24 and +0x14 from battle mon +0x16.

## Result flags (byte +9, bits above the low three)

Writers are 84134E00 (OR into the record at the write index) and 84134EC8
(OR into the record before it, i.e. the last committed one). All callers:

| Bit | Writer | Handler | Meaning |
| --- | --- | --- | --- |
| 0x08 | 84134E00 | 84124DEC | not needed here |
| 0x08 | 84134EC8 | 8413146C | not needed here |
| 0x10 | 84134E00 | 8412FD24 | paired with low bits 6/5 (existing note) |
| 0x20 | 84134EC8 | 8412DC20 | Thief: user item empty, target item non-zero and not mail (80063754), D_841951D3 clear → item moved, text 0x2D |
| 0x40 | 84134E00 | 8412EC70 | Present: the D_84185454 roll fell to the heal branch (text 0x50, or 0x9A when the target's HP +0x26 equals max +0x28) |
| 0x80 | 84134EC8 | 8412DE98 | Curse: 84126390(user, 8) is the Ghost-type test; target not semi-invulnerable (+0xF & 0x60), no substitute (+0x10 & 0x10), not already cursed (+0xD & 2) → curse set, half HP paid, text 0x67 |

The handlers are entries of the battle-command table at 0x84185EB0 (first
entry 84127194, the turn check). Stadium's order differs from pokecrystal's
`macros/scripts/battle_commands.asm`, so the identification is by behaviour,
not by index.

84114BF4 plays Curse's move route only when bit 0x80 is set, so the stat
(non-Ghost) Curse plays no route.

Open: the low three bits of the Ghost Curse record. 84130E04 commits the move
record before the flag is ORed in, and the handler's 84134E30(5) then lands
on the next record. The move record keeps whatever was written earlier
(841246AC writes 1 when the move is used). If that is 1, 841087B8 would take
the failure path for Curse, which contradicts the route gate. The port keeps
its previous impact behaviour (no hit record → treated as 0) and does not
derive these bits. An emulator capture of a Ghost Curse would settle it.

## Status byte (+0x10) and Snore

841083B0: Snore (0xAD) is 0 when status & 7 is 0, else 1 when the result low
bits are 1, else 2. 84130E04 also checks move 0xAD against the user's
+0x24 & 7. The Gen 2 layout (pokecrystal `constants/battle_constants.asm`):
SLP_MASK %111, PSN 0x08, BRN 0x10, FRZ 0x20, PAR 0x40.

## Word +0x14 is the DVs

841083B0's test for contexts 274/290/292/298/299 is `(w & 0x2FFF) ==
0x2AAA`. 84108358 passes the same word to 8006456C, which is exactly that
test (`asm/us/nonmatchings/641E0/func_8006456C.s`), and it matches
pokecrystal's CheckShininess (Attack DV bit 1 set, Defense, Speed and Special
10). So the input the port called `ownerStatusPattern` is the owner's DV word,
and these contexts take their shiny branch. Context 290 is 0x122, the
send-out entry (8411BCC8).

## Host facts used

The Gen 2 host (gen1recomp `src/battle/gen2/Battle.lua`, local `ff8373b`;
upstream `f22e1ad` is the same for these moves):

- Curse: `EFFECT_CURSE` sets `moveEvent.animParam = 1` only on the non-Ghost
  branch (following pokecrystal curse.asm:39); a failed Ghost Curse calls
  `markMissed`. So a presented, non-missed Curse without animParam 1 is the
  Ghost curse landing → 0x80.
- Thief is `EFFECT_THIEF = "damage"` and Present has no effect handler:
  the host never steals or heals, so 0x20 and 0x40 stay clear. The record's
  low bits still come from the recorded hit (`battle.damage_dealt`).
- Status: `mon.status` and `mon.statusTurns` (the cart's sleep counter,
  Battle:canAct), sampled when the move event is emitted
  (`Scene:recordEvent`), like 84134A6C builds the record when the move is used.
- DVs: `mon.dvs` {attack, defense, speed, special} → word
  attack<<12 | defense<<8 | speed<<4 | special, on the shown actor.

Gen 1 battles do not supply DVs or status yet (no Snore, Curse, Thief or
Present in Gen 1; the shiny contexts stay diagnosed there).

## Code

`lib/stadium2_battle_fx_sequence.lua` (RESULT_* constants),
`lib/stadium2_battle_fx_battle_adapter.lua` (`playMoveAndImpact` facts,
`_moveState`, passed to this move's route and impact only),
`lib/gen2_battle.lua` (`dvWord`, `statusByte`, facts on the move event).
Tests: `tests/stadium2_battle_fx_move_record_test.lua`,
`tests/stadium2_gen2_battle_fx_integration_test.lua` (new section). The
opcode-16 conditions themselves were already checked against the ROM
(`tests/stadium2_battle_fx_battle_state_rom_test.lua`, 4,628 cases).
