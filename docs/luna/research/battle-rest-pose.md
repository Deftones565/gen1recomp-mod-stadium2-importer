# Battle resting pose and animation contexts

Web session, 2026-09-25. Sources: US assembly for fragment79 (user's pret
split), michiiik/pokestadiumgs `7fc529e5` C, pret/pokecrystal `e058e4f`
constants. Matches ROM assembly; not checked against ROM execution or
visually.

## Which contexts battle selects

Contexts are rows 251..270 of the species' 20-byte animation-dispatch
table (actor+0x2D4). 84112158(actor, ctx) plays row ctx: body clip byte 0
(84111D64), auxiliary clip byte 1 (84111E50), frame 0. 84112218 and
841120AC do the same from a given frame. Every call to these three uses a
constant context, and the only fixed-offset row reads anywhere in the
uploaded assembly are rows 251, 253, 254, 261 and 262. So battle selects
only 251, 252, 253, 254, 258, 261 and 262; rows 255-257, 259-260 and
263-270 are never read.

## Resting pose (841139D0)

The idle state BattleAnim_Dispatch_001 (84113BE8) runs 841139D0 every frame
and plays 251 only when it selects nothing. 841139D0 reads the battler's
snapshot in the current event record (built by 84134A6C):

| Check (in order) | Source | Pose |
| --- | --- | --- |
| +0x12 bit 2 | battle mon +0xF bit 0x40, set by 8412C47C for move 0x13 Fly | 8411388C: context 262 looping |
| +0x12 bit 4, species 50/51 | +0xF bit 0x20, set for move 0x5B Dig | 84112218: context 258 held at frame 0x28 (Diglett) / 0x30 (Dugtrio) |
| +0x12 bit 4, other species | same | 8411EE74: model visible bit cleared |
| status +0x10 == 0x20 | frozen | 84112464: context 254 held at frame 6, frame 0 for species in D_84183A50 (35, 73, 252, 41, 188; 8411DC80 over 5 halfwords); species 252 holds 251 at frame 0 |
| status & 7 | asleep | 84112324: context 261 looping |
| HP +0x0E == 0 | fainted | 8411EE74 |

8412C47C is the two-turn charge handler: it sets +0xF bit 0x10 (charged),
then 0x40 for Fly or 0x20 for Dig. Poses are held because the selector is
re-run each frame (84112218 re-seeks, 84112464 calls 84111FEC).

So: 261 = asleep, 262 = in the air during Fly, 258 = Diglett/Dugtrio
underground. The existing `"sleep"` name on context 268 (commit 2e9306a)
has no call site; not renamed here (pack/build are local-owned and the name
is in the cache).

## Implementation

- `lib/battle_rest_pose.lua`: the selection rules.
- `Actor:setRest(condition)` / `Actor:applyRest()`: applied while idle,
  switching only when the pose changes; held poses do not advance. A missing
  clip keeps idle and is reported once.
- Gen 2: status from presented `status` events (Gold resolves the turn
  before presenting it), Fly/Dig from the vanish state once the departing
  animation ends, told apart by `chargeMove`. Flying and Diglett/Dugtrio
  underground stay visible.
- Gen 1: live battler state (Red's engine runs in step with its queue):
  `SLP`/`FRZ`, and `invulnerable` with `charging.id` FLY/DIG once no
  animation is playing. Non-Diglett species underground are hidden.

Limitations: auxiliary clips (byte 1) are not in the model pack, so only
body clips play; Gen 1 status can appear slightly before its message.
