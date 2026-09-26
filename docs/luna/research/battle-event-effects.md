# Battle events -> Stadium non-move effects

Web session, 2026-09-25. Sources: US assembly for fragment79 (user's pret
split), michiiik/pokestadiumgs `7fc529e5` C, pret/pokecrystal `e058e4f`
(effect IDs and status/substatus bits), bryanthaboi/gen1recomp `8d1e155`
(host events). Matches ROM assembly; not visually confirmed.

## Event code -> actor state family

Stadium's Gen 2 battle engine (fragment79_393CA0) queues event records
(84134CBC(side, code)). 8411FF1C switches on the code (jtbl_84189A80, 0x6A
entries) and calls a wrapper that selects a state family through
841125F4(actor, family): 7 consecutive entries of D_84183D54 (252 states).

| Codes | Family | Contexts used | Entries signalled |
| --- | --- | --- | --- |
| 0x00 / 0x01 | 15 / 16 | 251 | move route |
| 0x02-0x09, 0x2C | 17 | 251, 258 | - |
| 0x0A-0x15, 0x3B, 0x4B | 4 (defender hit) | 251, 254, 258, 261, 262 | 0xFD, 0xFE, 0x100, impact route |
| 0x16-0x19 | 8 | 251 | - |
| 0x1A / 0x1B | 6 / 7 | 251 (6 also 258, 262) | - |
| 0x1C | 5 (faint) | 251, 253 | 0x119, 0x11A |
| 0x1D | 19 | 251, 258, 261 | - |
| 0x1E-0x20 | 18 | 251 | 0x126 |
| 0x21, 0x23, 0x24, 0x29-0x2B, 0x38-0x3A | 12 (send-out) | 251, 252 | 0x100, 0x122, 0xFE |
| 0x22 | 24 / 34 | 251, 252 | 0x124 / 0x12B |
| 0x25 | 3 | 251 | - |
| 0x26 | 20 | 251, 258 | 0x104 |
| 0x27 | 21 | 251, 258 | move route |
| 0x28 | 23 | 251, 258 | 0x100 |
| 0x2D-0x2F | 25 | 251 | 0x100, 0x12C, 0xFE |
| 0x30-0x36 | 28 (84119630) | 251, 258 | weather, 0x10C |
| 0x37 / 0x65 / 0x66 / 0x67 | 32 / 33 / 29 / 30 | - | 0x12A (33) |
| 0x06, 0x3C-0x59 | 9 (84118DD4) | 251, 258 | table in sequencing-render-emission.md |
| 0x5A | 0 | 251, 258 | - |
| 0x5C-0x64, 0x68, 0x69 | 31 | - | 0x11C-0x11E |

(Contexts 258/261/262 in most families come from 841139D0, the resting
pose.)

## Codes named from the engine

| Code | Queued by | Meaning | Entry |
| --- | --- | --- | --- |
| 0x3C / 0x3D | 84131AF8 (ResidualDamage) | poison / toxic (status bit 0x08; toxic flag +0x11 bit 1), 1/8 | 0x101 |
| 0x3E | 84131AF8 | burn (bit 0x10), 1/8 | 0x102 |
| 0x3F | 84131AF8 | Leech Seed (+0x10 bit 0x80), 1/8 to the other side | 0x103 on the seeded mon |
| 0x40 | 84131AF8 | Nightmare (bit 0x01), 1/4 | 0x10A |
| 0x43 | 84131AF8 | Curse (bit 0x02), 1/4 | 0x109 |
| 0x46 | 84131EAC | Spikes on switch-in (not type 2, Flying), 1/8 | 0x10B |
| 0x06 | 84127194 (turn check) | in love / immobilized by love (text 0x78/0x79, 50% roll) | 0x108 |
| 0x36 | 84127194 | fully paralyzed | 0x10C |
| 0x41 | 8412FC9C->84124DEC, 84128CB8, 84130284 | stat rose on the user's side, Rage building, Belly Drum | 0xFC |
| 0x42 | 8412FD24 | stat fell, only for moves 28, 45, 81, 103, 108, 148, 178, 204, 230 | 0xFD |
| 0x4A | 841292C4, 84129180, 84132A94, 841330BC | HP restored: drain, Leftovers (1/16), berries | 0x10D |
| 0x51-0x54 | 84129180 | drain heal by move: 141, 72, 202, 71 | 0x117, 0x115, 0x116, 0x114 |
| 0x48 / 0x30-0x35 | 841324EC | weather (see sequencing-render-emission.md) | |

84124DEC queues 0x41 only when the stat belongs to the attacker; raising
the foe's stat sets result 5 instead. 8412FD24 sets result 6 (Tail Whip,
Leer, Kinesis, Scary Face) or 5 (other moves) without 0x42.

Faint: 8411A3D4 copies context 253's row bytes 0x0B/0x0A/0x09 to
actor+0x619/+0x61A/+0x620; 8411A620 signals 0x119 (sound 7) when the state
counter reaches +0x619 unless 8411E244(actor, 0x119) is 0xFF, and 0x11A
(sound 6) at +0x61A, then hides the model at +0x61A + 25.

Send-out: family 12's 8411BCC8 signals 0x122 (sound 5) as the state starts.

## Host pairing

| Stadium | Gen 2 (Gold) event | Gen 1 (Red) |
| --- | --- | --- |
| 0x101 / 0x102 | damage `anim` ANIM_PSN / ANIM_BRN | BURN_PSN_ANIM row, by `status` PSN/BRN |
| 0x103 | damage `anim` ANIM_SAP (seeded side) | ABSORB row without hit data (from the healing side) |
| 0x109 / 0x10A | damage ANIM_IN_NIGHTMARE, cursed / not | - |
| 0x10D | heal `anim` RECOVER (berry); heal during a presented drain move | - |
| 0x114-0x117 | heal during Absorb/Mega Drain/Giga Drain/Leech Life | - |
| 0xFC / 0xFD | `stage` event with the presented move (Sequence.statChangeEntry) | - |
| 0x122 | `send` / `sendout` | host send-out grow start |
| 0x119 / 0x11A | faint clip start, timed from row 253 | faint clip start |

Not wired, missing event detail: Leftovers heals (no source on Gold's heal
event), Spikes (a plain damage event after a message), full paralysis and
Attract (messages without a side), Gen 1 stat changes (no stat event or
hook). Gen 2 has no Nightmare tick.

## Switching, trapping, items, balls (2026-09-25)

Same sources; fork C `7fc529e5`, US assembly for the GLOBAL_ASM functions.
Matches the assembly by reading; not visually confirmed.

**Recall.** 841334D8 is the switch-out routine (callers: 84133ACC switch,
84133C10 after a faint). It prints its "come back" text, then 84124C10
queues 0x1E (normal), 0x1F (asleep, status & 7) or 0x20 (frozen, 0x20),
or 0x37 when the mon's HP is 0. 0x1E-0x20 select family 18:

- 8411AB5C sets +0x618 = 1 and preloads entry 0x126 (84113560).
- 8411ABAC (once 84113430 is ready): counter reset, camera shot
  D_84183C7C[rand & 3] and program 0x1B (84111348), then by code: 0x20 ->
  shot 0x11, 84108A10, frozen hold (84112464); 0x1E -> 84111D64 restarts the
  idle row's body clip (dispatch +0x139C = row 251 byte 0); 0x1F -> 84108A10,
  the same restart, sleep pose (84112324). Then 84112564 and entry 0x126 on
  the outgoing mon.
- 8411ACE8 ends the state at counter 0x46 (70 frames), clearing +0x7F4
  bits 0-1 and the afterimage slots (841206D0).

No model hide or scale happens in family 18 itself; whatever 0x126 does to
the model comes from the entry's own effect data (not traced).

Family 32 (code 0x37, fainted mon) plays no entry; 8411A76C hides the model
(8411EE74) for 0x37.

**Trapping.** 84132778 is HandleWrap. Per battler with a wrap count
(+0x1B > 0) and not +0x10 bit 0x10: count -1; if still > 0, 1/16 damage,
text 0xA1, then by the trapping move (+0x1C): 0x53 Fire Spin -> 0x4C,
0x80 Clamp -> 0x58, 0xFA Whirlpool -> 0x50, else (Bind, Wrap) -> 0x45; at 0
text 0xA2 and 84124594 (codes 2-4). Entries via 84118DD4: 0x45 -> 0x105,
0x4C -> 0xFF, 0x50 -> 0x118, 0x58 -> 0x129, on the trapped mon.

**Destiny Bond.** 84124768 sets move 0xC2 and queues 0x55 -> 0x123 (on the
battler passed in; not wired, no matching host event checked yet).

**Items and balls.** Stadium 2 battles have no bag items and no wild
catching, so there is no Stadium presentation for bag item use or ball
throws. Held items are what Stadium shows: berries and Leftovers (0x4A ->
0x10D). Other held-item codes (0x49/0x57 from 8413293C, 0x4D from 84132B9C,
0x4E, 0x4F) are not named yet.

Host pairing:

| Stadium | Gen 2 (Gold) | Gen 1 (Red) |
| --- | --- | --- |
| 0x126 recall | enemy: the AI's "<trainer> withdrew <mon>!" message (Battle:switchEnemy), matched with the engine's Strings call against the shown mon; player: none, the engine skips Gold's withdraw step | player: the host's retreat (`shrinkOut`) rising edge, 7 frames before the swap; enemy AI switch: no withdraw step |
| 0x105/0xFF/0x118/0x129 trap tick | damage event with `anim = false` and `animMove` = trapping move (Battle:tickWrap) | none (Red has no end-of-turn wrap damage) |

Timing differs from Stadium, where the recall state runs 70 frames before
the send-out: Gen 1's cue is 7 frames before the swap, so 0x126 keeps
playing on the player's slot into the new mon's send-out. Gen 2's cue is
the message line, before the send-out animation.

## Recall fade and model colour ownership (2026-09-27)

Measured with the port's player (test room, US ROM data): entry 0x126 turns
the outgoing model white and fades its opacity (8003F4DC) to 0 within about
50 ticks, and the write holds. Entry 0x122 (send-out) holds opacity 0 while
the ball opens, then shows the model white and fades the blend back out.
8003F454/8003F4DC write into the model object, so a newly sent-out Pokemon is
a fresh model at full opacity. The port kept these writes per side, so the
replacement inherited the recall's 0 and stayed invisible whenever the
send-out did not run (POKE BALL off). `NativeObjects:resetModel(side)` now
drops the side's colour state and stops writes still aimed at the old model
when the shown Pokemon changes (Gen 1 and Gen 2 scene `sync`). POKE BALL OFF
(non-native user option) skips both 0x122 and 0x126.
