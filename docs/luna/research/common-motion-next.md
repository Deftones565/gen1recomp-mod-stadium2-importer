# Common size ramp and trig correction (US ROM)

Verified directly against the supported US ROM. Fragment 79 maps ROM
`0x36F890` to `0x84100000`; main data maps ROM `0x1000` to `0x80000400`.
Earlier audit notes contained signed-address and branch-direction mistakes;
this note supersedes them for the exact ranges below.

## Trig source

`0x841060C8` is `lui a3,0x8009`; `0x841060D4` is
`addiu a3,a3,-0x71b0`. Therefore TB is **0x80088E50**, not 0x80098E50.
TA is 0x80087E50. Each has 4096 single-precision values. TB overlaps TA
at a quarter-turn offset of 1024 entries. Their combined ROM byte range is
`[0x88A50,0x8DA50)`. No generated sin/cos approximation is needed.

The first TA values are 0, 0.0015339801320806146, 0.0030679567717015743;
the first TB values are 1, 0.9999988079071045, 0.9999952912330627.
`0x841060EC` loads 0x4F800000 (4294967296.0) for the unsigned float
conversion, correcting the earlier 2147483648.0 transcription.

The rotation-offset initializer runs before directional-vector construction:
`0x84106C00` updates particle halfwords +0x6a/+0x6c/+0x6e; `0x84106C48`
passes that same particle to `0x84105FC8`. Its angle context must therefore
contain the updated rotation, rather than an empty table or the pre-random
rotation.

## Common size ramp

At `0x84101DCC..0x84101DEC`, root+0x0c selects geometry, geometry+4
selects its 8-byte scale table, and particle byte +0x7d selects the entry.
`0x841067FC..0x84106830` initially loads entry+0, converts it to float,
multiplies by 0.001f, and stores particle scalar +0x1c.

`0x84101DF8` reads signed entry+4 (step). Zero skips this update.
`0x84101E08..0x84101E14` compares post-increment age against signed
entry+6 and branches past interpolation when age is LESS than that value.
Thus +6 is the ramp start age for this path, not an expiry threshold.

At age >= startAge, signed entry+2 gives target and signed entry+4 gives
step, each multiplied by the ROM binary32 constant 0.001f at 0x84188B98.
If current < target, add step and clamp only when the result exceeds target.
If target < current, subtract step and clamp only when the result falls
below target. The equality case leaves the scalar unchanged. Every float
operation rounds separately to binary32; there is no dt multiplier.

Fire Punch program 259 references root 0x8417B6C4, geometry 0x8417B62C
(selector 1), and scale entry 0x8417B624 = (300,500,25,1). Its first
particle's unscaled scalar is 0.30000001192092896 at birth, then
0.32500001788139343 at tick 1, reaching exactly 0.5 at tick 8 and staying
there. The particle must not expire at tick 1.

`0x84101AF4` additionally maps the source scalar +0x1c to rendered +0x18
through a model-dependent factor. The host adapter supplies model/world
scale at its renderer boundary; this ramp implementation tracks +0x1c.
This does not prove the remaining native model-context paths or callbacks.

## Remaining boundary

The existing name `directionalVelocity` describes decoded vector input, not
a proven Euler velocity. `0x84106C78 -> 0x84105F10` transforms that vector
through source-model orientation and adds it to particle offset +0x2c.
Geometry+8 supplies angle offsets (+0x6a...), while geometry+12 supplies
position offsets (+0x2c...). Existing legacy names need a separate contract
migration. Do not promote the newly resolved vector into position += velocity.
Common motion modes, model-context fields, alpha updates, and native-object
callbacks remain separate implementation work.
