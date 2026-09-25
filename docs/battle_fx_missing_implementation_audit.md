# Battle FX missing implementation audit — 2026-09-23

## Remaining-gap inventory (2026-09-25, code vs. decomp cross-reference)

Method: every fragment-79 address cited in `lib/` (497) and in docs/bug log
(1,194 incl. code) was matched against michiiik/pokestadiumgs `7fc529e5`
(1,729 of 1,785 fragment-79 functions located; 674 still GLOBAL_ASM). A call
graph was walked through the fork's C from those functions plus the FX entry
points (8410580C, 8410545C, 84108728, 8410874C, 841087B8, 841088CC,
8410890C, 841089D8, 84108A10..84109118, 84103478, 84103394, 84102B3C).
It reached 281 functions: 223 cited in `lib/`, 26 cited only in docs, 32 not
cited. GLOBAL_ASM functions are opaque in this walk (their callees need the
US assembly), so this complements, and does not replace, the pret-asm call
graph used for the 528-function audit in `battle_FX_bugs.md`. No ROM was
available; the ROM sweep above has not been regenerated.

Most of the 32 uncited functions are not gaps: 841094F8/84109590/841095DC/
84109848/84109884/84109B1C and their 841569xx wrappers are lifecycle-slot
accessors whose sibling accessors (84109544, 841098C0) and callee families
are implemented or run under the ROM VM; ParticleGfx_Build* (84103EA8,
84103FF0, 8410413C) are the bodies of the implemented billboard modes
84104528/84104590/84104668; 84109B9C is an empty function.

Implemented since the 2026-09-23 per-move table (rows there are stale):
84107998 secondary/all-marker emission (54, 73, 108, 114, 123, 139, 207, 223,
234-236), 84105930 camera-ray anchor (37 moves), 8411E244 context marker
(240), the dynamic-anchor rows (audit stub artifact), wave-grid finish
signal, 841089D8 failure path, 84108A10 held release, move-then-impact
sequencing, 84102B3C billboards and 84102E84 render modes.

Still missing. "Blocked" names what is needed to implement it from evidence.

| # | Gap | Affects | Decomp status | Blocked on |
|---:|---|---|---|---|
| 1 | 84119630's entries are weather (0x106/0x107/0x113 ongoing, 0x11F/0x120/0x121 ended, 0x125 sandstorm hit; wired in Gen 2 2026-09-25) and full paralysis (0x10C; not wired, the host message has no side). Other status visuals (sleep, poison, burn, freeze, confusion) are among the unnamed 84118DD4 codes | status visuals | asm (read) | name the remaining codes |
| 2 | Host triggers for non-move entries 252-301. Code -> entry tables decoded (research note); wired 2026-09-25: weather, residual damage, stat changes, drain/berry heals, send-out, faint, charge turns, recall (0x126), trap ticks. Blocked on host event detail: Leftovers, Spikes, full paralysis, Attract, Gen 1 stat changes, Gen 2 player recall. Not named: held-item codes 0x49/0x4D-0x4F/0x57, Destiny Bond 0x123 unpaired | stat changes, faint, switch, etc. | callers in C: 841176E0 (0xFD at hit frame when result&0x10), 84118138/841182E0 (0xFE at state counter 8), 8411862C/8411A3D4 (0x100), BattleAnim_Dispatch_143 (0x104), 8411ABAC (0x126), BattleAnim_Dispatch_177 (0x12C), BattleAnim_Dispatch_184 (0x112); selectors 84118DD4/841189EC asm | which battle event selects each actor state; result-byte bit meanings |
| 3 | Host battle inputs. Done 2026-09-25: the result byte for damaging hits (decoded from fragment79_393CA0, fed by `battle.damage_dealt`). Still missing: status-move results, `sourceStatus`, `ownerStatusPattern` | opcode-16 moves 168, 173, 217 and contexts 274/290/292/298/299 | asm (readable now) | decode the remaining effect handlers |
| 4 | ~~Two-turn variant route~~ charge turns wired 2026-09-25 (contexts 255-260 plus the variant FX) | 13, 19, 76, 91, 130, 143 | asm (read) | visual retest |
| 5 | ~~Exact hit timing~~ attack-state timeline implemented 2026-09-25 (Sequence.attackTiming: route at the rebased hit frame, defender release rules, impact at the defender row's byte 7, clip from byte 6, negative-hit pre-roll). Open: release latency, 0xFC at +0x620, other defender handlers | every move with an impact bank | asm (read) | visual retest |
| 6 | Status-shape release variants 84108AF8/84108CE8/84108E00/84108F88/84109118 | shapes 0x12/0xD3/0x13D; entry 0x11F | asm (behaviour summarised in bug log) | US asm for exact conditions |
| 7 | ~~300-slot particle pool, allocator 84100260 and pool-origin spawn 8410668C~~ implemented 2026-09-25 from the US asm | 55, 140, 188, 190; cap on all moves | asm (read) | visual retest |
| 8 | Draw passes 84103394/84103478: every mode-1 particle carries flag 0x1000 (841072BC); the render layer (D_80094910+0x18) each pass runs in is not traced | mode-1 particles | C + asm | trace the layer callers |
| 9 | ~~Moves with both banks empty~~ all 7 handled 2026-09-25: 74/118/150 are the attack clip only; 107 Minimize (84122998), 156 Rest (841153DC), 97 Agility (84121920/84120F5C) and 104 Double Team (84121DE8) ported. Other behaviour kinds at actor+0x61F (moves 57, 66, 69, 96, 110, 127, 185, 187, 194, 229) not decoded | those moves | asm (read for 6/7/9) | visual retest; US asm for the other kinds |
| 10 | 810024E0 path without a colour block (inherits previous RDP combiner) | Swords Dance and likely other compiled-layout FX | asm | US asm + submission-order state |
| 11 | Frame-loop helpers not cited: 84105120, 84105630 (from 8410580C), 84108654, 8410922C (from 841051D8), 84109394 (from 84109460), 841037A0 | unknown | asm | US asm review |
| 12 | Lag on moves with 20-40 live particles (7, 9, 37, 52, 53) | many | n/a | profiling on the target machine |
| 13 | Visual retests, moves 57-251 | all | n/a | user retest |

Out of scope, checked: fragment79_393CA0 (`BattleAnim_Table_84185F10_*`, battle
mechanics on per-party-member records) and 379450/379E90 (scene setup, main
loop).

251 moves; 1004 scenarios (both banks and both source sides); 360 ticks each; draw samples every 15 ticks; finish signal at tick 120.
395 programs inspected, 343 referenced by move dispatch; 30 lifecycle table rows; 0 execution failures.
Real Koffing/Croconaw ROM skeletons, bind-pose markers, dispatch profiles and FX resource extraction. Renderer is a CPU validation stub: GPU shaders, animated poses, timing between draw samples, other species, arenas and every battle-state combination are not verified.

Diagnostics indicate unsupported or approximate paths; absence of diagnostics does not establish visual parity.

These counts are the audit baseline before the shared scaling implementation
described below; the full sweep has not been regenerated after that change.

Subsequent anchor correction: common particles now use the native high-bit
anchor selection (84104A00), posed model markers with center fallback, frozen
spawn anchors or flag-0x20000 following, and flags2 0x10/0x20 saved-origin
write/read behavior. The prior 209-move “shared-origin” count largely classified
ordinary model-marker placement incorrectly because the old adapter used low
bits. Do not interpret that baseline as a remaining shared-origin workload.
384 ROM comparisons cover marker/fallback, ground/lane/zero anchors and saved
origins. Player tests cover frozen anchors, saved offsets, and viewer conversion.
Context-selected markers, emission across multiple markers, prepared emitter
lines, special height inputs and prior-particle-pool origins remain diagnosed.

Mode-7 update: screen particles now use the native (160,120) constructor
offset, unit initialization scale, XY-only geometry offsets, and an overlay
pass independent of battle anchors and camera matrices. Resource geometry
modes 5 and 6 select the ROM's uniform or Y-only scale matrices, including
signed-16 pixel truncation and quantized Z rotation. All 68 decoded screen
descriptors match ROM initialization and three updates; matrix tests execute
8410383C/841038F4. Scratch/Mist viewer tests cover both sides and renderer
reuse/disposal. The earlier 34-move screen-space diagnostic is now resolved.
Mixed overlays are ordered by birth tick; exact native pool-slot reuse order
and GPU pixel parity have not been verified.

Special-context scaling update (2026-09-24): 8411E358 is implemented with all
jump-table aliases, its three dispatch-byte sources and native zero defaults.
The scheduler context is the original effect ID (or explicit nativeContextId),
not the selected program ID. The separate 80-byte species table is extracted
from ROM 4A40F0 and retained in the optional FXCS model-cache extension.
The player resolves it for constructor size/offsets and live size/movement.
1,505 ROM comparisons plus normal/shiny cache round trips pass. Old caches
without FXCS still load; special contexts requiring that table report missing
input until their model is rebuilt. This removes the unimplemented lookup,
not unrelated context-marker or battle-context scheduling gaps.

Ribbon/height update (2026-09-24): families 23/26/27 now receive their distinct
ROM center/scale inputs, then follow the current owner's posed marker and
animation offsets on every 30 Hz update. Bind, Wrap, Disable, String Shot and
Constrict use this path in the existing viewer bridge. Missing inputs retain
explicit diagnostics and preserve the last available anchor. Six setup cases
execute the ROM wrappers; moving-anchor vertices agree with the ROM kernel
within 0.0001 native units for the first two frames. Ten move/side scenarios
cover viewer packet integration; GPU visual parity has not been checked.

Common flag-0x80000 height now uses 8411EF90, profile+04 body height and the
8411DD8C species marker rules, including marker-100/9 fallback. 502 ROM cases
cover all species with/without marker 100, and 480 common-anchor cases include
the height flag and grounded override. Onix still needs the battle-owned
D_841911E0+50 point supplied as actor.nativeFxHeightPoint in native world units;
absent special geometry or required posed markers remains diagnosed. No cache
format change is needed for body height: existing FXBP records contain it.

Battle-state/controller update (2026-09-24): opcode 16 now has the exact
841083B0 species list, Thief/Present result bits, Snore status/result branches,
and five special-context status-pattern branches. 4,628 ROM cases pass.
The player obtains owner species from the scene; host battle state can supply
`nativeBattleState={resultFlags=...,sourceStatus=...,ownerStatusPattern=...}`
on the scene or trigger. Missing required state remains diagnosed. The visual
viewer uses an explicit neutral status/result fixture unless its options
provide another fixture; it does not simulate host battle mechanics.

The global alpha gate is independent of lifecycle finish: `signalContext(300)`
matches 8410890C, and each gated particle constructor resets it (841072A4).
The viewer's Finish action sends this context before its lifecycle signal;
the battle adapter exposes the same explicit presentation hook. The initial
alpha controller at material.colors+0 now runs while the end controller is
inactive (84102648). All 79 distinct retail material/gate combinations match
32 ROM ticks. Descriptor-bit-1 material-end-age transitions now set hidden
state, retain simulation/lifetime, and suppress draw packets; ROM comparisons
cover the actual flag and distinguish hiding from destruction.

Dynamic anchors are selected by **transform+10**, not a zero material shape.
The old Water Gun diagnostic misidentified a valid non-drawing controller.
47 decoded writer/reader records span 11 retail move routes. The player keeps
the slot table, updates posed FX-model marker 1 at simulation ticks, and
supplies native table reads to common anchors. Tests execute both native
slots' write helper, check persistent writer-before-reader stepping and model
reuse, and exercise Heal Bell's real exported marker model. Missing pose
support/unwritten slots remain explicit diagnostics. Full caller-order,
animated-pose and GPU equivalence across all 11 routes remains to be checked.

| Diagnostic | Moves | Contexts |
|---|---:|---:|
| approximate-common-anchor | 26 | 54 |
| approximate-common-anchor-height | 2 | 4 |
| approximate-common-model-anchor | 51 | 122 |
| approximate-common-shared-origin | 209 | 646 |
| approximate-ribbon-anchor | 5 | 10 |
| approximate-ribbon-scale | 5 | 10 |
| unsupported-alpha-gate | 2 | 4 |
| unsupported-common-screen-space | 34 | 94 |
| unsupported-dynamic-anchor | 1 | 2 |
| unsupported-native-condition | 13 | 43 |
| unsupported-native-constructor-scale (static) | 227 | 350 |
| unsupported-native-hide-transition (static) | 1 | 1 |

## approximate-common-anchor

- common-particle anchor uses the source slot; native center height and battle flags are not applied

Moves: 011 VICEGRIP, 012 GUILLOTINE, 013 RAZOR WIND, 016 GUST, 018 WHIRLWIND, 044 BITE, 046 ROAR, 054 MIST, 059 BLIZZARD, 077 POISONPOWDER, 078 STUN SPORE, 079 SLEEP POWDER, 087 THUNDER, 108 SMOKESCREEN, 114 HAZE, 123 SMOG, 128 CLAMP, 139 POISON GAS, 145 BUBBLE, 147 SPORE, 158 HYPER FANG, 162 SUPER FANG, 207 SWAGGER, 240 RAIN DANCE, 241 SUNNY DAY, 242 CRUNCH

## approximate-common-anchor-height

- native attachment height/scale adjustment is not applied; using source-slot height

Moves: 240 RAIN DANCE, 241 SUNNY DAY

## approximate-common-model-anchor

- common-particle model anchor and saved-origin state are unavailable; using the source slot

Moves: 006 PAY DAY, 019 FLY, 043 LEER, 044 BITE, 051 ACID, 053 FLAMETHROWER, 063 HYPER BEAM, 071 ABSORB, 072 MEGA DRAIN, 082 DRAGON RAGE, 091 DIG, 092 TOXIC, 093 CONFUSION, 094 PSYCHIC, 096 MEDITATE, 099 RAGE, 101 NIGHT SHADE, 109 CONFUSE RAY, 112 BARRIER, 113 LIGHT SCREEN, 115 REFLECT, 116 FOCUS ENERGY, 117 BIDE, 122 LICK, 124 SLUDGE, 126 FIRE BLAST, 137 GLARE, 138 DREAM EATER, 140 BARRAGE, 141 LEECH LIFE, 143 SKY ATTACK, 149 PSYWAVE, 151 ACID ARMOR, 170 MIND READER, 182 PROTECT, 184 SCARY FACE, 193 FORESIGHT, 197 DETECT, 202 GIGA DRAIN, 205 ROLLOUT, 207 SWAGGER, 208 MILK DRINK, 212 MEAN LOOK, 215 HEAL BELL, 219 SAFEGUARD, 223 DYNAMICPUNCH, 225 DRAGONBREATH, 234 MORNING SUN, 235 SYNTHESIS, 236 MOONLIGHT, 237 HIDDEN POWER

## approximate-common-shared-origin

- native shared-origin state is unavailable; using the source slot

Moves: 001 POUND, 002 KARATE CHOP, 003 DOUBLESLAP, 004 COMET PUNCH, 005 MEGA PUNCH, 006 PAY DAY, 007 FIRE PUNCH, 008 ICE PUNCH, 009 THUNDERPUNCH, 010 SCRATCH, 011 VICEGRIP, 012 GUILLOTINE, 013 RAZOR WIND, 014 SWORDS DANCE, 015 CUT, 016 GUST, 017 WING ATTACK, 018 WHIRLWIND, 019 FLY, 021 SLAM, 022 VINE WHIP, 023 STOMP, 024 DOUBLE KICK, 025 MEGA KICK, 026 JUMP KICK, 027 ROLLING KICK, 028 SAND-ATTACK, 029 HEADBUTT, 030 HORN ATTACK, 031 FURY ATTACK, 032 HORN DRILL, 033 TACKLE, 034 BODY SLAM, 036 TAKE DOWN, 037 THRASH, 038 DOUBLE-EDGE, 039 TAIL WHIP, 040 POISON STING, 041 TWINEEDLE, 042 PIN MISSILE, 043 LEER, 049 SONICBOOM, 051 ACID, 052 EMBER, 053 FLAMETHROWER, 054 MIST, 055 WATER GUN, 056 HYDRO PUMP, 057 SURF, 058 ICE BEAM, 059 BLIZZARD, 060 PSYBEAM, 061 BUBBLEBEAM, 062 AURORA BEAM, 063 HYPER BEAM, 064 PECK, 065 DRILL PECK, 066 SUBMISSION, 067 LOW KICK, 068 COUNTER, 069 SEISMIC TOSS, 070 STRENGTH, 071 ABSORB, 072 MEGA DRAIN, 073 LEECH SEED, 075 RAZOR LEAF, 076 SOLARBEAM, 077 POISONPOWDER, 078 STUN SPORE, 079 SLEEP POWDER, 080 PETAL DANCE, 082 DRAGON RAGE, 083 FIRE SPIN, 085 THUNDERBOLT, 087 THUNDER, 088 ROCK THROW, 089 EARTHQUAKE, 090 FISSURE, 091 DIG, 092 TOXIC, 098 QUICK ATTACK, 099 RAGE, 100 TELEPORT, 105 RECOVER, 106 HARDEN, 108 SMOKESCREEN, 109 CONFUSE RAY, 110 WITHDRAW, 111 DEFENSE CURL, 112 BARRIER, 113 LIGHT SCREEN, 114 HAZE, 115 REFLECT, 116 FOCUS ENERGY, 117 BIDE, 119 MIRROR MOVE, 120 SELFDESTRUCT, 121 EGG BOMB, 122 LICK, 123 SMOG, 124 SLUDGE, 125 BONE CLUB, 126 FIRE BLAST, 127 WATERFALL, 128 CLAMP, 129 SWIFT, 130 SKULL BASH, 131 SPIKE CANNON, 133 AMNESIA, 134 KINESIS, 135 SOFTBOILED, 136 HI JUMP KICK, 137 GLARE, 138 DREAM EATER, 139 POISON GAS, 140 BARRAGE, 141 LEECH LIFE, 142 LOVELY KISS, 143 SKY ATTACK, 144 TRANSFORM, 145 BUBBLE, 146 DIZZY PUNCH, 147 SPORE, 148 FLASH, 151 ACID ARMOR, 152 CRABHAMMER, 153 EXPLOSION, 154 FURY SWIPES, 155 BONEMERANG, 157 ROCK SLIDE, 158 HYPER FANG, 159 SHARPEN, 161 TRI ATTACK, 162 SUPER FANG, 163 SLASH, 164 SUBSTITUTE, 165 STRUGGLE, 167 TRIPLE KICK, 168 THIEF, 169 SPIDER WEB, 170 MIND READER, 171 NIGHTMARE, 172 FLAME WHEEL, 174 CURSE, 175 FLAIL, 177 AEROBLAST, 178 COTTON SPORE, 179 REVERSAL, 180 SPITE, 181 POWDER SNOW, 182 PROTECT, 183 MACH PUNCH, 184 SCARY FACE, 185 FAINT ATTACK, 186 SWEET KISS, 187 BELLY DRUM, 188 SLUDGE BOMB, 189 MUD-SLAP, 190 OCTAZOOKA, 191 SPIKES, 192 ZAP CANNON, 194 DESTINY BOND, 196 ICY WIND, 198 BONE RUSH, 199 LOCK-ON, 200 OUTRAGE, 201 SANDSTORM, 202 GIGA DRAIN, 204 CHARM, 205 ROLLOUT, 206 FALSE SWIPE, 208 MILK DRINK, 209 SPARK, 210 FURY CUTTER, 211 STEEL WING, 212 MEAN LOOK, 213 ATTRACT, 214 SLEEP TALK, 215 HEAL BELL, 216 RETURN, 217 PRESENT, 218 FRUSTRATION, 219 SAFEGUARD, 220 PAIN SPLIT, 221 SACRED FIRE, 222 MAGNITUDE, 223 DYNAMICPUNCH, 224 MEGAHORN, 225 DRAGONBREATH, 226 BATON PASS, 227 ENCORE, 228 PURSUIT, 229 RAPID SPIN, 230 SWEET SCENT, 231 IRON TAIL, 232 METAL CLAW, 233 VITAL THROW, 237 HIDDEN POWER, 238 CROSS CHOP, 239 TWISTER, 241 SUNNY DAY, 242 CRUNCH, 243 MIRROR COAT, 244 PSYCH UP, 245 EXTREMESPEED, 246 ANCIENTPOWER, 249 ROCK SMASH, 250 WHIRLPOOL, 251 BEAT UP

## approximate-ribbon-anchor

- native ribbon setup anchor is unavailable; using zero local origin

Moves: 020 BIND, 035 WRAP, 050 DISABLE, 081 STRING SHOT, 132 CONSTRICT

## approximate-ribbon-scale

- native ribbon setup scale is unavailable; using scale 1

Moves: 020 BIND, 035 WRAP, 050 DISABLE, 081 STRING SHOT, 132 CONSTRICT

## unsupported-alpha-gate

- native alpha ramp requires its battle signal

Moves: 018 WHIRLWIND, 046 ROAR

## unsupported-common-screen-space

- native mode 7 requires screen-space setup and draw (841076B8); common packets currently use world space

Moves: 010 SCRATCH, 015 CUT, 017 WING ATTACK, 022 VINE WHIP, 054 MIST, 077 POISONPOWDER, 078 STUN SPORE, 079 SLEEP POWDER, 108 SMOKESCREEN, 114 HAZE, 123 SMOG, 139 POISON GAS, 147 SPORE, 152 CRABHAMMER, 154 FURY SWIPES, 163 SLASH, 170 MIND READER, 171 NIGHTMARE, 174 CURSE, 180 SPITE, 181 POWDER SNOW, 196 ICY WIND, 199 LOCK-ON, 201 SANDSTORM, 206 FALSE SWIPE, 210 FURY CUTTER, 211 STEEL WING, 229 RAPID SPIN, 231 IRON TAIL, 232 METAL CLAW, 238 CROSS CHOP, 239 TWISTER, 241 SUNNY DAY, 250 WHIRLPOOL

## unsupported-dynamic-anchor

- shape-zero particle requires the native dynamic-anchor table write (84102750), not a drawable shape

Moves: 055 WATER GUN

## unsupported-native-condition

- opcode 16 requires native species/battle-state branch selection (841083B0); using current branch

Moves: 010 SCRATCH, 015 CUT, 022 VINE WHIP, 154 FURY SWIPES, 163 SLASH, 168 THIEF, 173 SNORE, 206 FALSE SWIPE, 210 FURY CUTTER, 211 STEEL WING, 217 PRESENT, 231 IRON TAIL, 232 METAL CLAW

## unsupported-native-constructor-scale

Update: ordinary source/dispatch scaling is now implemented in the shared
motion runtime: constructor visual size, yaw-rotated geometry/random offsets,
position-track initialization, live direction movement, and animated visual
size. Descriptor flags 0x80, 0x40 and 0x100 retain their distinct ROM semantics.
The viewer's existing placement context supplies the scale and facing.
ROM execution tests cover 120 scale/flag/yaw combinations plus live scale changes.
The 227-move list below is the original affected-path baseline, not a current
missing-implementation count or a count of completed moves. Missing actor input
and the separate flag-8 context scale still produce explicit diagnostics.
The static audit now supplies ordinary scale input to distinguish these cases.

- native common constructor model/dispatch scale is not applied to all geometry and transform inputs (841072BC)

Moves: 001 POUND, 002 KARATE CHOP, 003 DOUBLESLAP, 004 COMET PUNCH, 005 MEGA PUNCH, 006 PAY DAY, 007 FIRE PUNCH, 008 ICE PUNCH, 009 THUNDERPUNCH, 010 SCRATCH, 011 VICEGRIP, 012 GUILLOTINE, 013 RAZOR WIND, 014 SWORDS DANCE, 015 CUT, 016 GUST, 017 WING ATTACK, 018 WHIRLWIND, 019 FLY, 021 SLAM, 022 VINE WHIP, 023 STOMP, 024 DOUBLE KICK, 025 MEGA KICK, 026 JUMP KICK, 027 ROLLING KICK, 028 SAND-ATTACK, 029 HEADBUTT, 030 HORN ATTACK, 031 FURY ATTACK, 032 HORN DRILL, 033 TACKLE, 034 BODY SLAM, 036 TAKE DOWN, 037 THRASH, 038 DOUBLE-EDGE, 039 TAIL WHIP, 040 POISON STING, 041 TWINEEDLE, 042 PIN MISSILE, 043 LEER, 044 BITE, 049 SONICBOOM, 051 ACID, 052 EMBER, 053 FLAMETHROWER, 054 MIST, 055 WATER GUN, 056 HYDRO PUMP, 057 SURF, 058 ICE BEAM, 059 BLIZZARD, 060 PSYBEAM, 061 BUBBLEBEAM, 062 AURORA BEAM, 063 HYPER BEAM, 064 PECK, 065 DRILL PECK, 066 SUBMISSION, 067 LOW KICK, 068 COUNTER, 069 SEISMIC TOSS, 070 STRENGTH, 071 ABSORB, 072 MEGA DRAIN, 073 LEECH SEED, 075 RAZOR LEAF, 076 SOLARBEAM, 077 POISONPOWDER, 078 STUN SPORE, 079 SLEEP POWDER, 080 PETAL DANCE, 082 DRAGON RAGE, 083 FIRE SPIN, 084 THUNDERSHOCK, 085 THUNDERBOLT, 086 THUNDER WAVE, 087 THUNDER, 088 ROCK THROW, 089 EARTHQUAKE, 090 FISSURE, 091 DIG, 092 TOXIC, 093 CONFUSION, 094 PSYCHIC, 098 QUICK ATTACK, 099 RAGE, 100 TELEPORT, 101 NIGHT SHADE, 102 MIMIC, 105 RECOVER, 106 HARDEN, 108 SMOKESCREEN, 109 CONFUSE RAY, 110 WITHDRAW, 111 DEFENSE CURL, 112 BARRIER, 113 LIGHT SCREEN, 114 HAZE, 115 REFLECT, 116 FOCUS ENERGY, 117 BIDE, 119 MIRROR MOVE, 120 SELFDESTRUCT, 121 EGG BOMB, 122 LICK, 123 SMOG, 124 SLUDGE, 125 BONE CLUB, 126 FIRE BLAST, 127 WATERFALL, 128 CLAMP, 129 SWIFT, 130 SKULL BASH, 131 SPIKE CANNON, 133 AMNESIA, 134 KINESIS, 135 SOFTBOILED, 136 HI JUMP KICK, 137 GLARE, 138 DREAM EATER, 139 POISON GAS, 140 BARRAGE, 141 LEECH LIFE, 142 LOVELY KISS, 143 SKY ATTACK, 144 TRANSFORM, 145 BUBBLE, 146 DIZZY PUNCH, 147 SPORE, 148 FLASH, 149 PSYWAVE, 151 ACID ARMOR, 152 CRABHAMMER, 153 EXPLOSION, 154 FURY SWIPES, 155 BONEMERANG, 157 ROCK SLIDE, 158 HYPER FANG, 159 SHARPEN, 160 CONVERSION, 161 TRI ATTACK, 162 SUPER FANG, 163 SLASH, 164 SUBSTITUTE, 165 STRUGGLE, 166 SKETCH, 167 TRIPLE KICK, 168 THIEF, 169 SPIDER WEB, 170 MIND READER, 171 NIGHTMARE, 172 FLAME WHEEL, 173 SNORE, 174 CURSE, 175 FLAIL, 176 CONVERSION 2, 177 AEROBLAST, 178 COTTON SPORE, 179 REVERSAL, 180 SPITE, 181 POWDER SNOW, 182 PROTECT, 183 MACH PUNCH, 184 SCARY FACE, 185 FAINT ATTACK, 186 SWEET KISS, 187 BELLY DRUM, 188 SLUDGE BOMB, 189 MUD-SLAP, 190 OCTAZOOKA, 191 SPIKES, 192 ZAP CANNON, 194 DESTINY BOND, 196 ICY WIND, 198 BONE RUSH, 199 LOCK-ON, 200 OUTRAGE, 201 SANDSTORM, 202 GIGA DRAIN, 203 ENDURE, 204 CHARM, 205 ROLLOUT, 206 FALSE SWIPE, 207 SWAGGER, 208 MILK DRINK, 209 SPARK, 210 FURY CUTTER, 211 STEEL WING, 212 MEAN LOOK, 213 ATTRACT, 214 SLEEP TALK, 215 HEAL BELL, 216 RETURN, 217 PRESENT, 218 FRUSTRATION, 219 SAFEGUARD, 220 PAIN SPLIT, 221 SACRED FIRE, 222 MAGNITUDE, 223 DYNAMICPUNCH, 224 MEGAHORN, 225 DRAGONBREATH, 226 BATON PASS, 227 ENCORE, 228 PURSUIT, 229 RAPID SPIN, 230 SWEET SCENT, 231 IRON TAIL, 232 METAL CLAW, 233 VITAL THROW, 234 MORNING SUN, 235 SYNTHESIS, 236 MOONLIGHT, 237 HIDDEN POWER, 238 CROSS CHOP, 239 TWISTER, 242 CRUNCH, 243 MIRROR COAT, 244 PSYCH UP, 245 EXTREMESPEED, 246 ANCIENTPOWER, 247 SHADOW BALL, 248 FUTURE SIGHT, 249 ROCK SMASH, 250 WHIRLPOOL, 251 BEAT UP

## unsupported-native-hide-transition

- descriptor bit 1 requires native visibility transition at material end age (84102338); hide state is not implemented

Moves: 226 BATON PASS


## Opcode inventory

- Opcode 0: 395 records
- Opcode 1: 395 records
- Opcode 3: 17 records
- Opcode 4: 308 records
- Opcode 5: 195 records
- Opcode 7: 121 records
- Opcode 8: 715 records
- Opcode 9: 17 records
- Opcode 10: 35 records
- Opcode 11: 35 records
- Opcode 14: 77 records
- Opcode 15: 87 records
- Opcode 16: 17 records
- Opcode 17: 5 records

## Interpretation and source review

The highest coverage gap at audit time was the common constructor's native
model/dispatch scale: 227 moves reference at least one affected descriptor.
The ordinary scale path is now implemented and ROM-tested as described above;
special context scale and missing scene inputs remain diagnosed.
Next broad gaps are shared/model anchors and mode-7 screen-space
particles (34 moves). Counts overlap and must not be added together.

The 360-tick sweep completed all 1,004 scenarios with no execution exceptions.
It was followed by a static pass over every referenced descriptor, including
unselected branches, after adding constructor-scale and hide diagnostics.
Baton Pass was also rerun for 360 ticks on both banks/sides with the new hide
diagnostic. Table contexts include static references where marked.

Source of truth: supported US ROM and local pokestadiumgs commit
`c0e10f23d90cc4f335b654711f13e53c2c07323b`.

- Routing/program execution: 395 programs, all opcode records, 343 referenced
  programs. Opcode 16 (841083B0) needs species and battle-state selection.
  Opcode 12's indirect call (84107D4C) now diagnoses its missing execution,
  but has zero retail records. Native-object modes 4/6 also have zero retail
  records; do not count them as broken retail moves.
- Common construction/motion: 841072BC chooses unit scale under flag 0x80,
  otherwise actor/dispatch-derived scale; that factor is not propagated to
  all constructor inputs. Mode 7 dispatches 841076B8, which initializes a
  screen-space particle. The common draw path still uses world coordinates.
  Material end-age with descriptor bit 1 requests an unimplemented visibility
  transition (Baton Pass), separate from ordinary lifetime termination.
- Materials/native objects: ordinary color tracks and screen/model tint paths
  passed the suite. Whirlwind/Roar still need the separate global alpha gate
  D_841901A4. The lifecycle finish signal D_841901B8 does not resolve that gate.
- Placement: slot-based common anchors omit the native center/battle flags,
  model/saved origin or height adjustment described in their diagnostics.
  Shape-zero Water Gun particles need the dynamic anchor-table write at
  84102750; they are not missing drawable resource exports.
- Lifecycle: all 30 table rows reviewed (including empty rows). Builtin routes
  run in the sweep; ribbon families 23/26/27 still default their native setup
  anchor and scale. Init wrappers 84156F50/84157650/84157740 fetch these inputs
  before calling 8415BBA0.
- Draw/viewer: diagnostics flow through Player into the existing viewer
  ROM_FX log. Missing textures/geometry renderers, rejected callback state,
  and screen-overlay renderer failures now give retained, deduplicated errors.
  Missing material evaluator methods also diagnose rather than freezing silently.

A clean diagnostic log is not proof of ROM parity. Remaining validation covers
animated attachment poses, every species/profile and battle-state branch, arena
transforms/cameras, GPU materials/depth/blending, and transient states between
draw samples. Native pool exhaustion/order and actor animation synchronization
also require dedicated ROM comparisons; this audit does not establish those.

## Reproduce

From the Gen1Recomp repository root:

```sh
luajit mods/STADIUM2_IMPORTER/tools/audit_battle_fx.lua
STADIUM2_AUDIT_STATIC_ONLY=1 luajit mods/STADIUM2_IMPORTER/tools/audit_battle_fx.lua
STADIUM2_AUDIT_MOVE=226 luajit mods/STADIUM2_IMPORTER/tools/audit_battle_fx.lua
STADIUM2_REQUIRE_ROM=1 mods/STADIUM2_IMPORTER/tools/run_battle_fx_worker_checks.sh
```

Set STADIUM2_AUDIT_DRAW_STRIDE=1 for every-frame CPU draw coverage, and
STADIUM2_AUDIT_TICKS for a longer playback window. The tool defaults to 360
ticks, drawing frames 0/1/2, then every 15 ticks and the final frame.
The old battle_FX_bugs.md log is historical and is not this audit's input.
