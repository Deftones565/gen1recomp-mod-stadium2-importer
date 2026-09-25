Move bug list

Battle follow-up (2026-09-25, weather):
- Gen 2 battles now play Stadium's weather effects: each turn rain, sun or
  sandstorm continues (entries 0x107/0x106/0x113), when it ends
  (0x11F/0x121/0x120), and the sandstorm hit on each battler it hurts
  (0x125). Decoded from the game's own weather handler. Needs your retest
  (Rain Dance, Sunny Day, Sandstorm).
- "Fully paralyzed" is entry 0x10C, but it isn't wired yet: the battle
  message doesn't say which side is paralyzed.

Implementation follow-up (2026-09-25, particle pool):
- The 300-particle pool is now modelled. Once 300 particles are alive, the
  rest of an emission is not created, as in the ROM, and the log reports
  it. This caps runaway particle counts.
- Water Gun (55), Barrage (140), Sludge Bomb (188) and Octazooka (190) now
  spawn their follow-up particles at the earlier particle's position
  (8410668C) instead of reporting "not implemented". Needs your retest.
- Battle result byte: decoded from the Gen 2 battle engine inside the ROM
  and fed from the battle's hit results (crit/effectiveness). No visible
  change yet; it is groundwork for result-dependent effects.

Battle follow-up (2026-09-25, defender hit reaction):
- In Gen 1 and Gen 2 battles the defender now plays its own hit clip
  (context 254) when the impact bank starts, as the viewer's SEQ mode
  already did. A species without a hit clip is reported and keeps its
  current clip. Timing is approximate: the ROM starts the clip when the
  defender's hit state begins, slightly before the impact.
- Not applied: the ROM withholds the reaction for some results (84117948);
  the battles don't pass the result byte yet (see
  docs/luna/research/sequencing-render-emission.md).
- Found while auditing: the per-move table's "84107998 not implemented"
  rows are out of date; secondary/all-marker emission is implemented
  (see the 2026-09-25 implementation follow-up below). Retest 54, 73, 108,
  114, 123, 139, 207, 223, 234, 235, 236.
- Needs your retest in battle.

Viewer follow-up (2026-09-25, full move sequence):
- The viewer's new default mode, SEQ, plays the source battler's own clip
  for the move, the move bank at once, and the impact bank at the dispatch
  hit frame. The defender then plays its hit clip (context 254). A missing
  clip or hit frame is reported on screen and in the log, and the FX keep
  playing. There is no generic fallback clip. O cycles SEQ/PRI/ALT/VAR.
- Fix: impact particles were anchored on the attacker. 8410874C makes the
  battler running the hit-frame state the owner (D_84190194). Those states
  (84116EB4/841170A0/84117948/84118138/841182E0) select context 254 on that
  battler, so it is the defender. Common particles now follow
  Adapter.ownerSide; lifecycle geometry keeps its own source frame.
- Approximate: the defender's hit clip starts with the impact. In the ROM
  it starts when the defender's state begins, and the impact follows at
  that battler's +0x619.
- Next: status and reaction animations (sleep and the other statuses).
  841193E0/84119630 choose FX entries 0x106/0x107/0x10C/0x113/0x11F/0x120/
  0x121 by status branch; contexts 255-270 still need their selecting
  states decoded.

Implementation follow-up (2026-09-25, sequencing, entries and placement):
- Move then impact: battles now play the move bank at move start and the
  impact bank at the attacker's dispatch hit frame (row byte 0x0B), with the
  841087B8 result rules. Gen 2 skips missed events; Gen 1 skips the
  animation on a miss. The hit count starts at the move start, while the
  ROM restarts it after the attack state's approach phase, so the timing is
  approximate and the adapter reports this once.
- Physical moves whose move bank is empty (for example 1, 2, 3, 4, 6, 21,
  23, 24, 26, 27, 29, 33, 39) now show their impact effect in battle.
- Non-move FX entries 252..301 are in the catalog. Adapter:signalEffect(id,
  side) plays them the way 8410890C does. Which battle events trigger each ID
  is not decoded yet, so hosts don't call it yet. The viewer's J/L now
  reaches 301.
- Two-turn moves (13 Razor Wind, 19 Fly, 76 SolarBeam, 91 Dig,
  130 Skull Bash, 143 Sky Attack) have a route-mode-1 "variant" route (the
  second half of the side-variant table). It was never reachable before.
  Adapter:playVariant plays it; the viewer's O key now cycles
  primary/alternate/variant. Hosts don't call it yet.
- The failed-move path (841089D8) is implemented: it cancels pending
  emissions, kills non-held particles, resets model and background colors,
  and clears lifecycles. The Dig special signal is included.
- The wave-grid finish signal (D_841901B8) is set by the impact, so Growl,
  Sing, Supersonic, Hypnosis, Screech, Snore and Perish Song no longer run
  the 1800-tick default once their impact plays.
- Held-particle release (84108A10) is implemented. The status-shape
  variants are still open.
- Camera-ray anchor (84105930): 48 descriptors (37 moves) now anchor at the
  point in front of the camera instead of a fallback position.
- Emission markers (84107998): emissions now spawn at the primary and
  secondary markers, at every model marker, or at the context marker, as
  the ROM selects (for example Mist 11 -> 21 particles, Leech Seed impact
  1 -> 13).
- The "dynamic anchor" diagnostics in the earlier audit were an artifact of
  the audit's stub renderer. The real renderer implements them.
- Research notes: docs/luna/research/sequencing-render-emission.md. New
  tests: sequence (120), camera ray (55), emission markers (26). The full
  worker check passes with the ROM.
- Still open: particle-pool origin 8410668C (55, 140, 188, 190) together
  with the 300-slot pool cap, the second draw pass 84103394, the meaning of
  the 252..301 entries and the host events that trigger them, and exact
  attack-state hit timing.

Implementation follow-up (2026-09-25, shape transforms and render modes):
- Direct FX shapes now use the native 84102B3C geometry-mode transform:
  mode 0 = 84103A3C (Y/X/Z angles from the ROM sin/cos tables, scalar
  +0x18); mode 2 = 84103BCC (same, Y row scaled only); modes 1/3/4 =
  camera-facing billboards 84104528/84104668/84104590 built from the scene
  camera. Compiled-layout (kind-3) shapes keep the model-system transform.
  A missing camera or missing trig tables is diagnosed and the shape is not
  drawn.
- The per-entry 84102E84 render mode is applied: translucent/cutout/opaque
  blending plus depth compare and write. Most retail entries (for example
  low 6 with no flags) draw with no depth test, so they are no longer hidden
  inside the Pokemon model. Cutouts discard texels whose alpha gives no
  3-bit coverage (below 32/255). The anti-aliasing bits are ignored.
- Files: new lib/stadium2_battle_fx_render_mode.lua; edits to
  stadium2_battle_fx_draw_packets.lua, stadium2_battle_fx_player.lua,
  stadium2_battle_fx_resources.lua and renderer.lua; new test
  tests/stadium2_battle_fx_shape_transform_test.lua (84 checks). The
  model-material ROM test fixture now supplies trig tables and a camera.
  The full worker check passes with the ROM.
- Visual retest needed, especially moves marked "nothing is drawing",
  "untextured" or "unfinished": billboards and depth-free drawing change
  what is visible.

Decomp implementation audit (2026-09-25; everything below this section is retained):

This audit compares the decomp with our code. It does not look at rendered
output. Sources: pret/pokestadiumgs c0e10f2 assembly for all 1,785
fragment-79 functions, and decompiled C from michiiik/pokestadiumgs 7fc529e.
I built a call graph starting from the FX entry points (8410580C, the
trigger functions 84108728/8410874C/841087B8/841088CC/8410890C, the 18 opcode
handlers and the 30 lifecycle rows). That reaches 528 functions. I checked
them against lib/ and docs/luna/research/ and read the ones our code doesn't
cite. Out of scope: fragment79_393CA0 (battle mechanics: the move-effect
handler table at 84185F10 and stat-stage ratios) and 379450/379E90 (overlay
scene setup and main loop).

Missing, affects many moves:

1. [IMPLEMENTED 2026-09-25, see follow-up above] Camera-facing particle matrices. 84102B3C switches on the shape's
   geometry mode (jump table 84188BD4): mode 0 -> 841043AC/84103A3C
   (XYZ rotation), 1 -> 84104528 billboard, 2 -> 84104428/84103BCC (second
   rotation form, still asm), 3 -> 84104668 rotated Y-scaled billboard,
   4 -> 84104590 rotated billboard, 5/6 -> screen (already implemented).
   The billboards are the transpose of the camera rotation times a uniform
   scale (ParticleGfx_BuildBillboard* in the fork). stadium2_battle_fx_draw_packets.lua
   builds every world particle with the mode-0 matrix, so billboards are
   drawn as fixed 3D quads that can turn edge-on to the camera. Affected:
   259 banks use modes 1/3/4 (240 of them in moves 1-251, including most
   impact banks, e.g. program 138); 12 banks use mode 2: 9m 9i 63i 84m 84i
   85m 85i 87m 87i 192i 209m 209i.

2. [IMPLEMENTED 2026-09-25 for blend/depth; owner-texture mode 0x3F is unused by retail shapes and not implemented] Per-draw-entry render mode. 84102E84 reads the shape entry halfword +6
   and writes G_SETOTHERMODE_L after the material and before the display
   list. Low bits 6/4/1 select alpha blend, alpha-test cutout or opaque;
   flag 0x40 adds anti-aliasing or depth compare; flag 0x80 adds depth
   compare/update (for example 6/0 = 0x0C184240, blend with no depth test;
   6/0xC0 = 0x0C1849D8; 4/0 = 0x0F0A7008). Mode 0x3F (84102D38) binds the
   owner Pokemon's own texture. stadium2_battle_fx_resources.lua decodes
   this as entry.renderState and fragment.lua stores
   prim.battleFxRenderState, but nothing reads it. So FX blending and depth
   come from renderer defaults. 281 banks draw direct shapes that carry this
   state. The 243 banks drawn from compiled layouts don't decode it at all.
   No retail shape for entries 1-301 uses mode 0x3F.

3. Non-move FX entries 252-301 (50 entries). The FX table at 84182A5C is
   indexed by effect ID, not only by move. The battle actor code calls
   8410890C(id), and on the next frame 8410545C plays entry `id`, first
   loading its resources through 84113560 -> 84103694. FxRom.MOVE_COUNT = 251,
   so our catalog, viewer and audits never load these entries.
   Player:signalContext only latches the alpha gate for 300 and never plays
   entry 300. Only entry 261 uses a lifecycle (family 29); the others are
   bytecode programs. The meaning of each ID is not decoded yet: callers
   are listed below, and most IDs come from 84118DD4/841189EC (a large
   result/status switch in the actor code).

4. Move/impact sequencing. None of this is wired into battle playback.
   - Move bank: 84108728 at move start.
   - Impact bank: 841087B8 -> 8410874C when actor+0x7E8 == actor+0x619.
     The hit frame comes from byte 0x0B of the per-move 20-byte dispatch
     row, copied by 841146D4. animation_dispatch keeps the raw row, but no
     FX code uses it. The impact is skipped when (D_84193DD0+9)&7 == 6.
   - When that value is 1: only Growl, Sing, Supersonic, Hypnosis, Screech,
     Snore and Perish Song play their impact; Surf goes through 8410878C.
     Any other move takes the failure path 841089D8: 84105E3C; 841003AC
     (abort: kills flag-0x1 particles and resets both models' colors and
     the background); 84109460(1) -> 841093E8 (lifecycle stop); and
     84108974, which signals entry 301.
   - Mode 1 (841088CC, called from 84115B34/841156D0/84116248) plays the
     move bank's other-side variant. Its battle meaning is still unknown.

5. Battle-actor control of running particles. None of these are
   implemented; all scan the 300-slot pool for the owner actor:
   - 84108A10: 12 callers, including the hit frame. Releases held particles:
     clears 0x10080, and for flag 0x8000 ends the particle (+0x92 = 0) and
     hides its model.
   - 84108AF8, 84108CE8: the same release, but spare status shapes
     0x12/0xD3/0x13D.
   - 84108E00(owner, mode): hides shape 0xD3 or 0x13D, or sets flag 0x100000
     on shape 0x12.
   - 84108F88, 84109118: related releases; 84109118 also signals entry 0x11F.
   Constructor 84107170 maps descriptor flags to runtime flags:
   0x10->0x1, 0x400->0x40, 0x8->0x200, 0x4->0x100, 0x100->0x400,
   0x20000000->0x10000 (held), 0x10000000->0x20000 (Y termination),
   0x08000000->0x8000 (killed on release), 0x80000000->0x40000,
   flags2 0x4->0x80000. The held bit only occurs in entries 254, 256 and
   301, so this matters once item 3 is done.

6. Wave-grid finish signal (families 9-11). The 841094EC signal is not
   supplied by battle, so the effects run the native 1800-tick default
   (docs/luna/research/lifecycle-wave-grid-implemented.md). Affects 45, 47,
   48, 95, 103, 134, 173 and 195.

7. Second draw pass. 84103394 draws only particles with runtime flag 0x1000,
   and only when D_80094910+0x18 matches (8410A284 sets it to 3). Not
   implemented, and not yet known whether any retail FX sets 0x1000.

Missing placement paths. These are in the previous audit section (runtime
diagnostics): emitter line 84105930 (37 moves), secondary markers 84107998
(10), all markers (1), particle-pool origin 8410668C (4), context marker
8411E244 (1), dynamic anchor table (11).

Implemented or out of scope (checked):
- Opcode-16 branch 841083B0: stadium2_battle_fx_battle_state.lua (needs
  host species, status and result inputs).
- Flag-0x20000 Y termination: resolved through Player resolveNativeFinalY.
- All 30 lifecycle rows. Their uncited helpers sit inside family
  implementations that produce no runtime diagnostics; they were not
  checked one by one.
- Opcodes 2, 6, 12 and 13: no retail program uses them.
- Display-list, matrix-push and resource-DMA plumbing, which the renderer
  replaces.

Non-move FX entries (route = what 8410545C plays; callers = functions that
signal this ID via 8410890C or preload it via 84113560):

| Entry | ID | Route | Signaled by |
|---:|---|---|---|
| 252 | 0x0FC | `P235` | 84114BF4 84118DD4 841189EC |
| 253 | 0x0FD | `P236` | 841176E0 84118DD4 841189EC |
| 254 | 0x0FE | `P147` | 84118138 841182E0 8411B898 8411BCC8 |
| 255 | 0x0FF | `P177` | 84118DD4 841189EC |
| 256 | 0x100 | `P148` | 841153DC 8411862C 8411AA3C 8411B898 8411BCC8 |
| 257 | 0x101 | `P149` | 84118DD4 |
| 258 | 0x102 | `P150` | 84118DD4 |
| 259 | 0x103 | `P151` | 84118DD4 |
| 260 | 0x104 | `P155` | 8411A258 |
| 261 | 0x105 | `L29` | 84118DD4 |
| 262 | 0x106 | `P185` | 84119630 841193E0 |
| 263 | 0x107 | `P188` | 84119630 841193E0 |
| 264 | 0x108 | `P189` | 841189EC |
| 265 | 0x109 | `P173` | 84118DD4 841189EC |
| 266 | 0x10A | `P200` | 84118DD4 841189EC |
| 267 | 0x10B | `P201` | 84118DD4 841189EC |
| 268 | 0x10C | `P203` | 84119630 841193E0 |
| 269 | 0x10D | `P225` | 84118DD4 841189EC |
| 270 | 0x10E | `P226` | 84118DD4 841189EC |
| 271 | 0x10F | `P233` | 84118DD4 841189EC |
| 272 | 0x110 | `P237` | 84118DD4 841189EC |
| 273 | 0x111 | `P238` | 84118DD4 841189EC |
| 274 | 0x112 | `P247` | 8411C97C 8411C8A0 |
| 275 | 0x113 | `P302` | 84119630 |
| 276 | 0x114 | `P250` | 84118DD4 841189EC |
| 277 | 0x115 | `P251` | 84118DD4 841189EC |
| 278 | 0x116 | `P252` | 84118DD4 841189EC |
| 279 | 0x117 | `P253` | 84118DD4 841189EC |
| 280 | 0x118 | `P255` | 84118DD4 841189EC |
| 281 | 0x119 | `P298` | 8411A620 |
| 282 | 0x11A | `P299` | 8411A620 8411A4AC |
| 283 | 0x11B | `P300` | (none found with an immediate ID) |
| 284 | 0x11C | `P301` | 84113E7C 84113D7C |
| 285 | 0x11D | `P302` | 84113E7C 84113D7C |
| 286 | 0x11E | `P303` | 84113E7C 84113D7C |
| 287 | 0x11F | `P304` | 84109118 84119630 841193E0 |
| 288 | 0x120 | `P305` | 84119630 841193E0 |
| 289 | 0x121 | `P306` | 84119630 841193E0 |
| 290 | 0x122 | `P311` | 8411BCC8 8411BC28 |
| 291 | 0x123 | `P246` | 84118DD4 841189EC |
| 292 | 0x124 | `P340` | 8411C418 |
| 293 | 0x125 | `P350` | 84118DD4 841189EC |
| 294 | 0x126 | `P379` | 8411ABAC 8411AB5C |
| 295 | 0x127 | `P387` | 841189EC |
| 296 | 0x128 | `P388` | 84118DD4 841189EC |
| 297 | 0x129 | `P389` | 84118DD4 841189EC |
| 298 | 0x12A | `P390` | 8411D1A8 8411D0A0 |
| 299 | 0x12B | `P391` | 8411CD38 |
| 300 | 0x12C | `P392` | 8411B808 (also latches the alpha gate) |
| 301 | 0x12D | `P393` | 84108974 (status-move failure path) |

Full move/impact audit (2026-09-25; original visual results below retained):

How the two banks work (decomp: michiiik/pokestadiumgs 7fc529e; the selector
func_841052AC is still asm, read from the US assembly):
- Move bank = `primaryDispatch` (move table +0). Played by func_84108728 when
  the attacker starts the move (BattleAnim_Dispatch_017 -> func_84114600).
- Impact bank = `alternateDispatch` (move table +2). Played by func_8410874C
  via func_841087B8 on the hit frame (func_84117CAC: actor+0x7E8 == actor+0x619)
  and skipped when battle result byte (D_84193DD0+9)&7 == 6. When that value
  is 1, only Growl, Sing, Supersonic, Hypnosis, Screech, Snore, Perish Song and
  Surf still play their impact bank.
- A third mode (func_841088CC) plays the move bank's other-side variant. Its
  battle meaning has not been worked out.
- Program 394 is empty (start/end records only). A bank routed to it is
  supposed to draw nothing.

Method: every move, both banks, both source sides, 360 ticks, draw sampled every
5 ticks, finish at tick 120. Uses the real ROM Koffing/Croconaw skeletons, the
real FX resources, and the same Player/adapter path as the viewer, but a CPU
stub renderer. This shows what the runtime hands to the renderer. It cannot
show textures, on-screen visibility, GPU output or frame rate. Battle condition
was 0 and battle state was the viewer default.

Results:
- 502 banks: 89 are empty in ROM (correct to draw nothing); 413 have content.
  409 of those reach the renderer. Whirlwind, Roar and Smokescreen impacts
  are background/model color only (no geometry). Snore's impact draws nothing
  under condition 0 (it branches on condition). No execution errors.
- 7 moves have both banks empty: 74 Growth, 97 Agility, 104 Double Team,
  107 Minimize, 118 Metronome, 150 Splash, 156 Rest. Their visuals, if any,
  come from outside the FX tables (Rest has its own path, func_841153DC;
  the others are unverified).
- Every native-object packet in this audit is a background-color, model-color
  or screen-overlay type. No 3D native object went unresolved.
- An earlier run reported "native FX skeletal animation is unavailable" on
  183 banks. That was an artifact of the audit's stub renderer (it had no
  seekFrame), not a runtime gap. With the stub fixed, those packets draw.

Your "nothing is drawing" moves, rechecked:
- Move bank is empty in ROM; the effect is in the impact bank (test with O):
  1, 2, 3, 4, 6, 21, 23, 24, 26, 27, 29, 33, 39.
- Move bank has content that reaches the renderer; retest after the
  2026-09-24/25 texture and model-animation fixes: 19 (one model held at the
  attacker), 30 and 31 (animated horn model, shape 444 with animation 445,
  which needed the 09-25 animation hookup), 32, 34 (16 short-lived ground
  particles).

What is still missing (not implemented, found by the audit):
- Battle integration: play the move bank at move start and the impact bank at
  the hit frame, skip the impact on result 6, and apply the result-1 rule.
  The viewer still picks one bank manually.
- Emitter-line anchor 84105930 (falls back to a default position), 37 moves:
  11, 12, 13, 16, 18, 19, 43, 44, 46, 59, 71, 72, 93, 94, 96, 99, 101, 116,
  117, 128, 137, 138, 141, 149, 158, 162, 170, 184, 193, 197, 202, 212, 234,
  235, 236, 241, 242.
- Secondary-marker emission 84107998, 10 moves: 54, 108, 114, 123, 139, 207,
  223, 234, 235, 236.
- Emit from all model markers 84107998, 1 move: 73.
- Spawn from an earlier particle pool 8410668C, 4 moves: 55, 140, 188, 190.
- Context-selected marker 8411E244, 1 move: 240.
- Dynamic anchor table (marker-1 pose write, then later reads), 11 moves: 112,
  113, 115, 140, 143, 182, 199, 205, 215, 219, 237.
- Battle-condition branches (opcode 9/16), only tested with condition 0, 13
  moves: 10, 15, 22, 154, 163, 168, 173, 206, 210, 211, 217, 231, 232.
- Lag: you reported lag on moves with only 21-37 live particles (7, 9, 37,
  52, 53), so the cost is per-particle rendering, not ROM particle counts.
  Moves peaking at 60+ live particles will be hit hardest: 8, 17, 28, 44, 56,
  57, 59, 61, 63, 89, 90, 102, 105, 127, 143, 160, 161, 166, 172, 176, 189,
  200, 205, 211, 221, 222, 229, 237, 238, 239, 250.
- Not checked by this audit: textures and the "untextured" reports, visibility,
  GPU shaders, species other than Koffing/Croconaw, arenas, and moves 57-251 in
  the viewer.

Per-move table. Route codes: Pn = FX program n, Ln = lifecycle family n
(a = alternate-side flag). "Peak" = most live common particles at once.

| # | Move | Move bank (primary) | Impact bank (alternate) | Missing / risks | Your test |
|---:|---|---|---|---|---|
| 1 | POUND | `P394` empty in ROM | `P138` particles (peak 17) | none found | nothing is drawing |
| 2 | KARATE CHOP | `P394` empty in ROM | `P138` particles (peak 17) | none found | nothing is drawing |
| 3 | DOUBLESLAP | `P394` empty in ROM | `P256` particles (peak 23) | none found | nothing is drawing |
| 4 | COMET PUNCH | `P394` empty in ROM | `P138` particles (peak 17) | none found | nothing is drawing |
| 5 | MEGA PUNCH | `P289` particles (peak 1) | `P258` particles, model color (peak 11) | none found | untextured and unfinished |
| 6 | PAY DAY | `P394` empty in ROM | `P32` particles (peak 37) | none found | nothing is drawing |
| 7 | FIRE PUNCH | `P259` background color, particles (peak 21) | `P260` screen overlay, model color, particles, background color (peak 28) | none found | particles cause lag |
| 8 | ICE PUNCH | `P264` background color, particles (peak 64) | `P265` screen overlay, model color, particles, background color (peak 23) | move: peak 64 live particles (lag risk) | particles cause lag |
| 9 | THUNDERPUNCH | `P266` background color, particles (peak 28) | `P267` screen overlay, model color, particles, background color (peak 25) | none found | lag |
| 10 | SCRATCH | `P206` particles, screen overlay, screen particles (peak 9) | `P207` screen overlay, screen particles, particles (peak 47) | move: branches on battle condition (audited with condition 0 only) | good |
| 11 | VICEGRIP | `P64` particles (peak 1) | `P274` particles (peak 46) | move: emitter-line anchor (84105930) missing, uses fallback position | untextured and unfinished |
| 12 | GUILLOTINE | `P65` background color, particles (peak 1) | `P277` particles, model color (peak 41) | move: emitter-line anchor (84105930) missing, uses fallback position | untextured and unfinished |
| 13 | RAZOR WIND | `P7` background color, particles (peak 3) | `P276` particles, model color, background color (peak 4) | move: emitter-line anchor (84105930) missing, uses fallback position | untextured and unfinished |
| 14 | SWORDS DANCE | `P6` particles (peak 14) | `P394` empty in ROM | none found | untextured and unfinished and swords are not dancing |
| 15 | CUT | `P221` particles, screen overlay, screen particles (peak 3) | `P222` screen overlay, screen particles, particles (peak 47) | move: branches on battle condition (audited with condition 0 only) | good |
| 16 | GUST | `P7` background color, particles (peak 3) | `P8` model color, particles, background color (peak 41) | move: emitter-line anchor (84105930) missing, uses fallback position | untextured and unfinished |
| 17 | WING ATTACK | `P292` screen particles, screen overlay (peak 2) | `P293` screen overlay, screen particles, particles (peak 61) | impact: peak 61 live particles (lag risk) | good |
| 18 | WHIRLWIND | `P283` background color, particles (peak 3) | `P284` background color, model color | move: emitter-line anchor (84105930) missing, uses fallback position | untextured and unfinished |
| 19 | FLY | `P285` particles (peak 1) | `P281` screen overlay, particles (peak 48) | move: emitter-line anchor (84105930) missing, uses fallback position | nothing is drawing |
| 20 | BIND | `L4` lifecycle 4 | `L23` lifecycle 23 | none found | good |
| 21 | SLAM | `P394` empty in ROM | `P282` particles (peak 47) | none found | nothing is drawing |
| 22 | VINE WHIP | `P216` particles, screen overlay, screen particles (peak 3) | `P217` screen overlay, screen particles, particles (peak 36) | move: branches on battle condition (audited with condition 0 only) | good |
| 23 | STOMP | `P394` empty in ROM | `P275` particles (peak 47) | none found | nothing is drawing |
| 24 | DOUBLE KICK | `P394` empty in ROM | `P138` particles (peak 17) | none found | nothing is drawing |
| 25 | MEGA KICK | `P289` particles (peak 1) | `P258` particles, model color (peak 11) | none found | untextured and unfinished |
| 26 | JUMP KICK | `P394` empty in ROM | `P138` particles (peak 17) | none found | nothing is drawing |
| 27 | ROLLING KICK | `P394` empty in ROM | `P138` particles (peak 17) | none found | nothing is drawing |
| 28 | SAND-ATTACK | `P268` particles (peak 96) | `P269` particles (peak 95) | move: peak 96 live particles (lag risk); impact: peak 95 live particles (lag risk) | lag and maybe unfinished |
| 29 | HEADBUTT | `P394` empty in ROM | `P138` particles (peak 17) | none found | nothing is drawing |
| 30 | HORN ATTACK | `P73` particles (peak 1) | `P287` particles (peak 18) | none found | nothing is drawing |
| 31 | FURY ATTACK | `P74` particles (peak 3) | `P288` particles (peak 34) | none found | nothing is drawing |
| 32 | HORN DRILL | `P71` background color, particles (peak 1) | `P72` particles, model color (peak 26) | none found | nothing is drawing |
| 33 | TACKLE | `P394` empty in ROM | `P138` particles (peak 17) | none found | nothing is drawing |
| 34 | BODY SLAM | `P294` particles (peak 16) | `P295` particles (peak 47) | none found | nothing is drawing |
| 35 | WRAP | `L4` lifecycle 4 | `L23` lifecycle 23 | none found | good |
| 36 | TAKE DOWN | `P141` background color, particles (peak 20) | `P355` particles, background color (peak 19) | none found | untextured and unfinished |
| 37 | THRASH | `P296` particles, model color (peak 32) | `P138` particles (peak 17) | none found | lag |
| 38 | DOUBLE-EDGE | `P141` background color, particles (peak 20) | `P380` particles, background color (peak 43) | none found | untextured and unfinished |
| 39 | TAIL WHIP | `P394` empty in ROM | `P138` particles (peak 17) | none found | nothing is drawing |
| 40 | POISON STING | `L17,P361` lifecycle 17, particles (peak 2) | `P365` particles (peak 26) | none found | good |
| 41 | TWINEEDLE | `L17,P361` lifecycle 17, particles (peak 2) | `P365` particles (peak 26) | none found | good |
| 42 | PIN MISSILE | `L17,P361` lifecycle 17, particles (peak 2) | `P362` particles (peak 26) | none found | good |
| 43 | LEER | `P75` background color, particles (peak 2) | `P394` empty in ROM | move: emitter-line anchor (84105930) missing, uses fallback position | untextured and unfinished |
| 44 | BITE | `P66` particles (peak 1) | `P364` particles (peak 60) | move: emitter-line anchor (84105930) missing, uses fallback position; impact: peak 60 live particles (lag risk) | untextured and unfinished |
| 45 | GROWL | `L11a` lifecycle 11 | `P394` empty in ROM | none found | this effect is finished but should apply to the whole camera * this might not be intended but it's what I want |
| 46 | ROAR | `P356` background color, particles (peak 1) | `P357` background color, model color | move: emitter-line anchor (84105930) missing, uses fallback position | untextured and unfinished |
| 47 | SING | `L10a` lifecycle 10 | `P394` empty in ROM | none found | whole camera effect needed |
| 48 | SUPERSONIC | `L11a` lifecycle 11 | `P394` empty in ROM | none found | whole camera effect needed |
| 49 | SONICBOOM | `L12a` lifecycle 12 | `P138` particles (peak 17) | none found | good |
| 50 | DISABLE | `L21` lifecycle 21 | `L27` lifecycle 27 | none found | good |
| 51 | ACID | `P78` particles (peak 1) | `P79` model color, particles (peak 10) | none found | unfinished |
| 52 | EMBER | `P272` screen overlay, particles (peak 36) | `P273` screen overlay, model color, particles (peak 33) | none found | lag and maybe unfinished |
| 53 | FLAMETHROWER | `P158` background color, particles (peak 23) | `P159` background color, particles, model color (peak 37) | none found | lag, and the flame is small (check if this is finished) |
| 54 | MIST | `P108` screen particles, background color, model color, particles (peak 11) | `P394` empty in ROM | move: secondary-marker emission (84107998) not implemented | good |
| 55 | WATER GUN | `P183` background color, particles (peak 41) | `P184` particles, background color (peak 32) | move: spawn from earlier particle pool (8410668C) not implemented | lag and unfinished |
| 56 | HYDRO PUMP | `P180` background color, particles (peak 20) | `P181` background color, particles (peak 74) | impact: peak 74 live particles (lag risk) | unfinished |
| 57 | SURF | `L7a,P330` lifecycle 7, particles (peak 80) | `P331` particles (peak 100) | move: peak 80 live particles (lag risk); impact: peak 100 live particles (lag risk) | not tested |
| 58 | ICE BEAM | `L13a,P309` lifecycle 13, background color, screen overlay, particles (peak 10) | `P310` background color, model color, particles (peak 45) | none found | not tested |
| 59 | BLIZZARD | `P24` background color, screen overlay, particles (peak 1) | `P25` background color, particles, model color (peak 67) | move: emitter-line anchor (84105930) missing, uses fallback position; impact: peak 67 live particles (lag risk) | not tested |
| 60 | PSYBEAM | `L0a,P332` lifecycle 0, background color, screen overlay, particles (peak 1) | `P333` particles, model color, background color (peak 31) | none found | not tested |
| 61 | BUBBLEBEAM | `P198` background color, particles (peak 137) | `P335` model color, particles, background color (peak 105) | move: peak 137 live particles (lag risk); impact: peak 105 live particles (lag risk) | not tested |
| 62 | AURORA BEAM | `L5a,P336` lifecycle 5, background color, particles (peak 1) | `P337` model color, particles, background color (peak 28) | none found | not tested |
| 63 | HYPER BEAM | `L8a,P338` lifecycle 8, background color, screen overlay, particles (peak 2) | `P339` background color, model color, particles (peak 66) | impact: peak 66 live particles (lag risk) | not tested |
| 64 | PECK | `P286` particles (peak 1) | `P344` particles (peak 18) | none found | not tested |
| 65 | DRILL PECK | `P278` particles (peak 1) | `P257` particles (peak 26) | none found | not tested |
| 66 | SUBMISSION | `P297` particles (peak 16) | `P358` particles (peak 34) | none found | not tested |
| 67 | LOW KICK | `P394` empty in ROM | `P138` particles (peak 17) | none found | not tested |
| 68 | COUNTER | `P394` empty in ROM | `P359` particles (peak 51) | none found | not tested |
| 69 | SEISMIC TOSS | `P394` empty in ROM | `P275` particles (peak 47) | none found | not tested |
| 70 | STRENGTH | `P40` particles (peak 2) | `P41` particles (peak 41) | none found | not tested |
| 71 | ABSORB | `P56` background color, particles (peak 1) | `P57` particles, background color, model color (peak 1) | move: emitter-line anchor (84105930) missing, uses fallback position | not tested |
| 72 | MEGA DRAIN | `P58` background color, particles (peak 1) | `P59` background color, particles, model color (peak 1) | move: emitter-line anchor (84105930) missing, uses fallback position | not tested |
| 73 | LEECH SEED | `P307` particles (peak 22) | `P308` particles (peak 1) | impact: emit-from-all-markers (84107998) not implemented | not tested |
| 74 | GROWTH | `P394` empty in ROM | `P394` empty in ROM | none found | not tested |
| 75 | RAZOR LEAF | `L3a` lifecycle 3 | `P341` particles (peak 8) | none found | not tested |
| 76 | SOLARBEAM | `L18a,P342` lifecycle 18, background color, screen overlay, particles (peak 1) | `P343` model color, particles, background color (peak 25) | none found | not tested |
| 77 | POISONPOWDER | `P103` screen particles, particles (peak 21) | `P315` particles (peak 14) | none found | not tested |
| 78 | STUN SPORE | `P104` screen particles, particles (peak 21) | `P316` particles (peak 14) | none found | not tested |
| 79 | SLEEP POWDER | `P105` screen particles, particles (peak 21) | `P317` particles (peak 14) | none found | not tested |
| 80 | PETAL DANCE | `L15a` lifecycle 15 | `P360` particles (peak 8) | none found | not tested |
| 81 | STRING SHOT | `L6` lifecycle 6 | `L26` lifecycle 26 | none found | not tested |
| 82 | DRAGON RAGE | `P169` background color, particles (peak 22) | `P170` background color, particles, model color (peak 37) | none found | not tested |
| 83 | FIRE SPIN | `P158` background color, particles (peak 23) | `P176` model color, particles (peak 50) | none found | not tested |
| 84 | THUNDERSHOCK | `P166` background color, screen overlay, particles (peak 24) | `P167` background color, particles, screen overlay (peak 14) | none found | not tested |
| 85 | THUNDERBOLT | `P164` background color, screen overlay, particles (peak 26) | `P165` background color, particles (peak 23) | none found | not tested |
| 86 | THUNDER WAVE | `P270` particles (peak 9) | `P271` particles (peak 2) | none found | not tested |
| 87 | THUNDER | `P162` background color, screen overlay, particles (peak 26) | `P163` background color, screen overlay, particles (peak 23) | none found | not tested |
| 88 | ROCK THROW | `P42` particles (peak 2) | `P43` particles (peak 45) | none found | not tested |
| 89 | EARTHQUAKE | `P30` background color, particles (peak 1) | `P31` particles (peak 74) | impact: peak 74 live particles (lag risk) | not tested |
| 90 | FISSURE | `P261` background color, particles (peak 1) | `P262` particles (peak 74) | impact: peak 74 live particles (lag risk) | not tested |
| 91 | DIG | `P38` particles (peak 1) | `P39` particles (peak 42) | none found | not tested |
| 92 | TOXIC | `P80` particles (peak 1) | `P81` model color, particles (peak 10) | none found | not tested |
| 93 | CONFUSION | `P53` background color, particles, model color, screen overlay (peak 1) | `P54` particles, model color, background color, screen overlay (peak 9) | move: emitter-line anchor (84105930) missing, uses fallback position; impact: emitter-line anchor (84105930) missing, uses fallback position | not tested |
| 94 | PSYCHIC | `P51` particles, model color, background color, screen overlay (peak 1) | `P52` particles, model color, background color, screen overlay (peak 9) | move: emitter-line anchor (84105930) missing, uses fallback position; impact: emitter-line anchor (84105930) missing, uses fallback position | not tested |
| 95 | HYPNOSIS | `L9a` lifecycle 9 | `P394` empty in ROM | none found | not tested |
| 96 | MEDITATE | `P48` particles (peak 1) | `P394` empty in ROM | move: emitter-line anchor (84105930) missing, uses fallback position | not tested |
| 97 | AGILITY | `P394` empty in ROM | `P394` empty in ROM | none found | not tested |
| 98 | QUICK ATTACK | `P83` particles (peak 5) | `P138` particles (peak 17) | none found | not tested |
| 99 | RAGE | `P345` background color, particles, model color (peak 33) | `P363` background color, particles (peak 17) | move: emitter-line anchor (84105930) missing, uses fallback position | not tested |
| 100 | TELEPORT | `P84` model color, background color, particles (peak 1) | `P394` empty in ROM | none found | not tested |
| 101 | NIGHT SHADE | `P44` screen overlay, background color, particles (peak 1) | `P45` particles, screen overlay, model color, background color (peak 9) | move: emitter-line anchor (84105930) missing, uses fallback position; impact: emitter-line anchor (84105930) missing, uses fallback position | not tested |
| 102 | MIMIC | `P194` background color, particles (peak 215) | `P394` empty in ROM | move: peak 215 live particles (lag risk) | not tested |
| 103 | SCREECH | `L9a` lifecycle 9 | `P394` empty in ROM | none found | not tested |
| 104 | DOUBLE TEAM | `P394` empty in ROM | `P394` empty in ROM | none found | not tested |
| 105 | RECOVER | `P195` background color, model color, particles (peak 226) | `P394` empty in ROM | move: peak 226 live particles (lag risk) | not tested |
| 106 | HARDEN | `P368` model color, particles (peak 16) | `P394` empty in ROM | none found | not tested |
| 107 | MINIMIZE | `P394` empty in ROM | `P394` empty in ROM | none found | not tested |
| 108 | SMOKESCREEN | `P120` screen particles, background color, model color, particles (peak 12) | `P383` model color, background color | move: secondary-marker emission (84107998) not implemented | not tested |
| 109 | CONFUSE RAY | `P85` background color, particles, model color, screen overlay (peak 9) | `P86` particles, screen overlay (peak 9) | none found | not tested |
| 110 | WITHDRAW | `P87` particles (peak 1) | `P394` empty in ROM | none found | not tested |
| 111 | DEFENSE CURL | `P88` model color, particles (peak 13) | `P394` empty in ROM | none found | not tested |
| 112 | BARRIER | `P89` background color, particles, model color, screen overlay (peak 21) | `P394` empty in ROM | move: dynamic anchor write (marker-1 pose) unavailable; move: reads a dynamic anchor that was never written | not tested |
| 113 | LIGHT SCREEN | `P90` background color, particles, model color, screen overlay (peak 21) | `P394` empty in ROM | move: dynamic anchor write (marker-1 pose) unavailable; move: reads a dynamic anchor that was never written | not tested |
| 114 | HAZE | `P107` screen particles, background color, model color, particles (peak 11) | `P394` empty in ROM | move: secondary-marker emission (84107998) not implemented | not tested |
| 115 | REFLECT | `P91` particles, background color, model color, screen overlay (peak 21) | `P394` empty in ROM | move: dynamic anchor write (marker-1 pose) unavailable; move: reads a dynamic anchor that was never written | not tested |
| 116 | FOCUS ENERGY | `P55` particles, model color, background color (peak 19) | `P394` empty in ROM | move: emitter-line anchor (84105930) missing, uses fallback position | not tested |
| 117 | BIDE | `P345` background color, particles, model color (peak 33) | `P363` background color, particles (peak 17) | move: emitter-line anchor (84105930) missing, uses fallback position | not tested |
| 118 | METRONOME | `P394` empty in ROM | `P394` empty in ROM | none found | not tested |
| 119 | MIRROR MOVE | `P394` empty in ROM | `P138` particles (peak 17) | none found | not tested |
| 120 | SELFDESTRUCT | `P92` background color, particles, screen overlay, model color (peak 25) | `P112` background color, model color, particles (peak 24) | none found | not tested |
| 121 | EGG BOMB | `P35` particles (peak 1) | `P369` screen overlay, model color, particles (peak 30) | none found | not tested |
| 122 | LICK | `P33` particles (peak 1) | `P113` model color, particles (peak 10) | none found | not tested |
| 123 | SMOG | `P109` screen particles, background color, model color, particles (peak 11) | `P371` particles, background color, model color (peak 33) | move: secondary-marker emission (84107998) not implemented; impact: secondary-marker emission (84107998) not implemented | not tested |
| 124 | SLUDGE | `P76` particles (peak 1) | `P77` model color, particles (peak 10) | none found | not tested |
| 125 | BONE CLUB | `P114` particles, screen overlay (peak 1) | `P138` particles (peak 17) | none found | not tested |
| 126 | FIRE BLAST | `P158` background color, particles (peak 23) | `P171` background color, model color, particles (peak 48) | none found | not tested |
| 127 | WATERFALL | `P116` particles (peak 69) | `P117` particles, model color (peak 43) | move: peak 69 live particles (lag risk) | not tested |
| 128 | CLAMP | `P64` particles (peak 1) | `P274` particles (peak 46) | move: emitter-line anchor (84105930) missing, uses fallback position | not tested |
| 129 | SWIFT | `L2a,P373` lifecycle 2, background color | `P161` particles, background color (peak 54) | none found | not tested |
| 130 | SKULL BASH | `P118` background color, particles (peak 5) | `P370` screen overlay, model color, particles, background color (peak 30) | none found | not tested |
| 131 | SPIKE CANNON | `L16,P374` lifecycle 16, particles (peak 6) | `P375` particles (peak 42) | none found | not tested |
| 132 | CONSTRICT | `L4` lifecycle 4 | `L23` lifecycle 23 | none found | not tested |
| 133 | AMNESIA | `P119` particles (peak 3) | `P394` empty in ROM | none found | not tested |
| 134 | KINESIS | `P34,L11` particles, lifecycle 11 (peak 1) | `P394` empty in ROM | none found | not tested |
| 135 | SOFTBOILED | `P36` particles, model color (peak 19) | `P394` empty in ROM | none found | not tested |
| 136 | HI JUMP KICK | `P83` particles (peak 5) | `P384` particles (peak 41) | none found | not tested |
| 137 | GLARE | `P334` background color, particles (peak 2) | `P376` particles, background color (peak 1) | move: emitter-line anchor (84105930) missing, uses fallback position; impact: emitter-line anchor (84105930) missing, uses fallback position | not tested |
| 138 | DREAM EATER | `P46` background color, particles (peak 7) | `P47` background color, particles (peak 7) | move: emitter-line anchor (84105930) missing, uses fallback position; impact: emitter-line anchor (84105930) missing, uses fallback position | not tested |
| 139 | POISON GAS | `P121` screen particles, background color, model color, particles (peak 11) | `P372` particles, background color, model color (peak 33) | move: secondary-marker emission (84107998) not implemented; impact: secondary-marker emission (84107998) not implemented | not tested |
| 140 | BARRAGE | `P190` particles (peak 12) | `P191` particles (peak 26) | move: dynamic anchor write (marker-1 pose) unavailable; move: spawn from earlier particle pool (8410668C) not implemented; impact: dynamic anchor write (marker-1 pose) unavailable; impact: spawn from earlier particle pool (8410668C) not implemented | not tested |
| 141 | LEECH LIFE | `P60` background color, particles (peak 1) | `P61` particles, background color, model color (peak 1) | move: emitter-line anchor (84105930) missing, uses fallback position | not tested |
| 142 | LOVELY KISS | `P28` particles, screen overlay (peak 1) | `P29` particles, screen overlay (peak 2) | none found | not tested |
| 143 | SKY ATTACK | `P123` model color, background color, particles (peak 93) | `P124` background color, particles, model color (peak 140) | move: dynamic anchor write (marker-1 pose) unavailable; move: reads a dynamic anchor that was never written; move: peak 93 live particles (lag risk); impact: dynamic anchor write (marker-1 pose) unavailable; impact: reads a dynamic anchor that was never written; impact: peak 140 live particles (lag risk) | not tested |
| 144 | TRANSFORM | `P204` model color, particles (peak 24) | `P394` empty in ROM | none found | not tested |
| 145 | BUBBLE | `P197` background color, particles (peak 36) | `P366` background color, particles (peak 48) | none found | not tested |
| 146 | DIZZY PUNCH | `P394` empty in ROM | `P125` particles (peak 13) | none found | not tested |
| 147 | SPORE | `P106` screen particles, particles (peak 21) | `P394` empty in ROM | none found | not tested |
| 148 | FLASH | `P312` background color, screen overlay, model color, particles (peak 8) | `P313` background color, screen overlay, model color, particles (peak 8) | none found | not tested |
| 149 | PSYWAVE | `P49` background color, particles (peak 1) | `P50` particles, background color (peak 9) | move: emitter-line anchor (84105930) missing, uses fallback position; impact: emitter-line anchor (84105930) missing, uses fallback position | not tested |
| 150 | SPLASH | `P394` empty in ROM | `P394` empty in ROM | none found | not tested |
| 151 | ACID ARMOR | `P130` particles, model color (peak 13) | `P394` empty in ROM | none found | not tested |
| 152 | CRABHAMMER | `P23` particles, screen overlay (peak 1) | `P220` screen overlay, screen particles, particles (peak 47) | none found | not tested |
| 153 | EXPLOSION | `P92` background color, particles, screen overlay, model color (peak 25) | `P112` background color, model color, particles (peak 24) | none found | not tested |
| 154 | FURY SWIPES | `P206` particles, screen overlay, screen particles (peak 9) | `P377` screen overlay, screen particles, particles (peak 47) | move: branches on battle condition (audited with condition 0 only) | not tested |
| 155 | BONEMERANG | `P115` particles (peak 1) | `P138` particles (peak 17) | none found | not tested |
| 156 | REST | `P394` empty in ROM | `P394` empty in ROM | none found | not tested |
| 157 | ROCK SLIDE | `P42` particles (peak 2) | `P43` particles (peak 45) | none found | not tested |
| 158 | HYPER FANG | `P67` particles (peak 1) | `P138` particles (peak 17) | move: emitter-line anchor (84105930) missing, uses fallback position | not tested |
| 159 | SHARPEN | `P126` model color, particles (peak 13) | `P394` empty in ROM | none found | not tested |
| 160 | CONVERSION | `P353` background color, particles (peak 215) | `P394` empty in ROM | move: peak 215 live particles (lag risk) | not tested |
| 161 | TRI ATTACK | `L20a` lifecycle 20 | `P378` particles (peak 84) | impact: peak 84 live particles (lag risk) | not tested |
| 162 | SUPER FANG | `P68` particles (peak 1) | `P138` particles (peak 17) | move: emitter-line anchor (84105930) missing, uses fallback position | not tested |
| 163 | SLASH | `P212` particles, screen overlay, screen particles (peak 9) | `P213` screen overlay, screen particles, particles (peak 47) | move: branches on battle condition (audited with condition 0 only) | not tested |
| 164 | SUBSTITUTE | `P205` model color, particles (peak 24) | `P138` particles (peak 17) | none found | not tested |
| 165 | STRUGGLE | `P394` empty in ROM | `P138` particles (peak 17) | none found | not tested |
| 166 | SKETCH | `P321` background color, particles (peak 215) | `P394` empty in ROM | move: peak 215 live particles (lag risk) | not tested |
| 167 | TRIPLE KICK | `P394` empty in ROM | `P138` particles (peak 17) | none found | not tested |
| 168 | THIEF | `P394` empty in ROM | `P329` particles (peak 17) | impact: branches on battle condition (audited with condition 0 only) | not tested |
| 169 | SPIDER WEB | `L6` lifecycle 6 | `P16` background color, particles (peak 3) | none found | not tested |
| 170 | MIND READER | `P127` background color, particles (peak 2) | `P290` background color, screen particles (peak 3) | move: emitter-line anchor (84105930) missing, uses fallback position | not tested |
| 171 | NIGHTMARE | `P178` background color, screen particles, particles (peak 2) | `P182` particles (peak 5) | none found | not tested |
| 172 | FLAME WHEEL | `P134` background color, model color, particles (peak 1) | `P135` background color, particles, model color (peak 74) | impact: peak 74 live particles (lag risk) | not tested |
| 173 | SNORE | `L9a,P196` lifecycle 9, background color | `P291` background color, particles | impact: branches on battle condition (audited with condition 0 only); impact: produced nothing drawable under condition 0 | not tested |
| 174 | CURSE | `P172` particles, screen overlay, background color (peak 11) | `P367` background color, screen particles, particles (peak 6) | none found | not tested |
| 175 | FLAIL | `P394` empty in ROM | `P348` particles (peak 51) | none found | not tested |
| 176 | CONVERSION 2 | `P346` background color, particles (peak 215) | `P394` empty in ROM | move: peak 215 live particles (lag risk) | not tested |
| 177 | AEROBLAST | `P26` background color, particles (peak 1) | `P27` particles, background color (peak 49) | none found | not tested |
| 178 | COTTON SPORE | `P22` particles (peak 17) | `P347` particles (peak 16) | none found | not tested |
| 179 | REVERSAL | `P186` background color, particles (peak 1) | `P381` background color, particles (peak 51) | none found | not tested |
| 180 | SPITE | `P179` background color, screen particles, particles (peak 2) | `P168` particles, background color (peak 5) | none found | not tested |
| 181 | POWDER SNOW | `P12` screen particles (peak 1) | `P349` screen overlay, model color, particles (peak 23) | none found | not tested |
| 182 | PROTECT | `P102` background color, particles (peak 19) | `P394` empty in ROM | move: dynamic anchor write (marker-1 pose) unavailable; move: reads a dynamic anchor that was never written | not tested |
| 183 | MACH PUNCH | `P95` background color, particles (peak 1) | `P98` particles, background color (peak 28) | none found | not tested |
| 184 | SCARY FACE | `P327` background color, particles (peak 2) | `P394` empty in ROM | move: emitter-line anchor (84105930) missing, uses fallback position | not tested |
| 185 | FAINT ATTACK | `P394` empty in ROM | `P138` particles (peak 17) | none found | not tested |
| 186 | SWEET KISS | `P174` particles, screen overlay (peak 1) | `P175` particles, screen overlay (peak 2) | none found | not tested |
| 187 | BELLY DRUM | `P157` particles (peak 7) | `P394` empty in ROM | none found | not tested |
| 188 | SLUDGE BOMB | `P229` particles (peak 30) | `P230` particles, model color (peak 52) | move: spawn from earlier particle pool (8410668C) not implemented; impact: spawn from earlier particle pool (8410668C) not implemented | not tested |
| 189 | MUD-SLAP | `P234` particles (peak 67) | `P328` particles, model color (peak 54) | move: peak 67 live particles (lag risk) | not tested |
| 190 | OCTAZOOKA | `P192` particles (peak 38) | `P193` particles, model color (peak 52) | move: spawn from earlier particle pool (8410668C) not implemented; impact: spawn from earlier particle pool (8410668C) not implemented | not tested |
| 191 | SPIKES | `P17` particles (peak 1) | `P18` particles (peak 1) | none found | not tested |
| 192 | ZAP CANNON | `P9` particles, background color, screen overlay (peak 1) | `P140` particles, screen overlay, background color (peak 21) | none found | not tested |
| 193 | FORESIGHT | `P239` particles, background color (peak 1) | `P240` background color, particles, screen overlay, model color (peak 1) | move: emitter-line anchor (84105930) missing, uses fallback position; impact: emitter-line anchor (84105930) missing, uses fallback position | not tested |
| 194 | DESTINY BOND | `P231` particles, background color, model color (peak 1) | `P394` empty in ROM | none found | not tested |
| 195 | PERISH SONG | `L10a` lifecycle 10 | `P394` empty in ROM | none found | not tested |
| 196 | ICY WIND | `P10` background color, screen particles (peak 1) | `P320` background color, screen overlay, model color, particles (peak 23) | none found | not tested |
| 197 | DETECT | `P199` background color, particles (peak 1) | `P394` empty in ROM | move: emitter-line anchor (84105930) missing, uses fallback position | not tested |
| 198 | BONE RUSH | `P114` particles, screen overlay (peak 1) | `P256` particles (peak 23) | none found | not tested |
| 199 | LOCK-ON | `P254` screen particles (peak 3) | `P156` background color, model color, particles, screen particles (peak 5) | impact: dynamic anchor write (marker-1 pose) unavailable | not tested |
| 200 | OUTRAGE | `P152` background color, particles, screen overlay (peak 1) | `P153` particles, background color, model color (peak 74) | impact: peak 74 live particles (lag risk) | not tested |
| 201 | SANDSTORM | `P11` screen particles (peak 1) | `P350` screen particles, particles (peak 23) | none found | not tested |
| 202 | GIGA DRAIN | `P248` background color, particles (peak 1) | `P249` background color, model color, particles (peak 1) | move: emitter-line anchor (84105930) missing, uses fallback position | not tested |
| 203 | ENDURE | `P146` particles, background color (peak 1) | `P394` empty in ROM | none found | not tested |
| 204 | CHARM | `P241` screen overlay, particles (peak 46) | `P242` screen overlay, particles (peak 1) | none found | not tested |
| 205 | ROLLOUT | `P62` particles, model color (peak 65) | `P63` particles (peak 12) | move: peak 65 live particles (lag risk); impact: dynamic anchor write (marker-1 pose) unavailable; impact: reads a dynamic anchor that was never written | not tested |
| 206 | FALSE SWIPE | `P227` particles, screen overlay, screen particles (peak 3) | `P228` screen overlay, screen particles, particles (peak 31) | move: branches on battle condition (audited with condition 0 only) | not tested |
| 207 | SWAGGER | `P232` particles (peak 11) | `P394` empty in ROM | move: secondary-marker emission (84107998) not implemented | not tested |
| 208 | MILK DRINK | `P3` particles, model color (peak 17) | `P394` empty in ROM | none found | not tested |
| 209 | SPARK | `P143` background color, screen overlay, particles (peak 13) | `P144` particles, screen overlay, background color (peak 19) | none found | not tested |
| 210 | FURY CUTTER | `P208` particles, screen overlay, screen particles (peak 3) | `P209` screen overlay, screen particles, particles (peak 42) | move: branches on battle condition (audited with condition 0 only) | not tested |
| 211 | STEEL WING | `P214` screen overlay, screen particles (peak 1) | `P215` screen particles, screen overlay, particles (peak 67) | move: branches on battle condition (audited with condition 0 only); impact: peak 67 live particles (lag risk) | not tested |
| 212 | MEAN LOOK | `P322` background color, particles (peak 2) | `P323` background color, particles (peak 1) | move: emitter-line anchor (84105930) missing, uses fallback position; impact: emitter-line anchor (84105930) missing, uses fallback position | not tested |
| 213 | ATTRACT | `P243` screen overlay, particles (peak 46) | `P244` particles, screen overlay (peak 1) | none found | not tested |
| 214 | SLEEP TALK | `P394` empty in ROM | `P138` particles (peak 17) | none found | not tested |
| 215 | HEAL BELL | `P5` particles (peak 27) | `P394` empty in ROM | move: dynamic anchor write (marker-1 pose) unavailable; move: reads a dynamic anchor that was never written | not tested |
| 216 | RETURN | `P394` empty in ROM | `P138` particles (peak 17) | none found | not tested |
| 217 | PRESENT | `P13` particles (peak 13) | `P14` particles, screen overlay, model color (peak 26) | impact: branches on battle condition (audited with condition 0 only) | not tested |
| 218 | FRUSTRATION | `P394` empty in ROM | `P138` particles (peak 17) | none found | not tested |
| 219 | SAFEGUARD | `P101` background color, particles (peak 19) | `P394` empty in ROM | move: dynamic anchor write (marker-1 pose) unavailable; move: reads a dynamic anchor that was never written | not tested |
| 220 | PAIN SPLIT | `P314` background color, model color, particles (peak 2) | `P138` particles (peak 17) | none found | not tested |
| 221 | SACRED FIRE | `P131` background color, model color, particles (peak 1) | `P132` model color, particles, screen overlay, background color (peak 74) | impact: peak 74 live particles (lag risk) | not tested |
| 222 | MAGNITUDE | `P110` background color, particles (peak 2) | `P263` particles (peak 74) | impact: peak 74 live particles (lag risk) | not tested |
| 223 | DYNAMICPUNCH | `P245` background color, particles (peak 48) | `P319` screen overlay, model color, particles, background color (peak 40) | move: secondary-marker emission (84107998) not implemented; impact: secondary-marker emission (84107998) not implemented | not tested |
| 224 | MEGAHORN | `P279` particles (peak 1) | `P280` particles (peak 26) | none found | not tested |
| 225 | DRAGONBREATH | `P351` background color, particles (peak 22) | `P352` particles, model color, background color (peak 37) | none found | not tested |
| 226 | BATON PASS | `P4` particles, model color (peak 13) | `P394` empty in ROM | none found | not tested |
| 227 | ENCORE | `P154` particles (peak 1) | `P202` particles (peak 3) | none found | not tested |
| 228 | PURSUIT | `P394` empty in ROM | `P138` particles (peak 17) | none found | not tested |
| 229 | RAPID SPIN | `P97` background color, screen particles, particles (peak 111) | `P382` background color, particles (peak 17) | move: peak 111 live particles (lag risk) | not tested |
| 230 | SWEET SCENT | `P111` background color, particles (peak 1) | `P128` background color, particles, model color (peak 1) | none found | not tested |
| 231 | IRON TAIL | `P223` screen overlay, screen particles (peak 1) | `P224` screen particles, screen overlay, particles (peak 42) | move: branches on battle condition (audited with condition 0 only) | not tested |
| 232 | METAL CLAW | `P210` particles, screen overlay, screen particles (peak 9) | `P211` screen particles, screen overlay, particles (peak 42) | move: branches on battle condition (audited with condition 0 only) | not tested |
| 233 | VITAL THROW | `P394` empty in ROM | `P275` particles (peak 47) | none found | not tested |
| 234 | MORNING SUN | `P99` model color, particles (peak 32) | `P394` empty in ROM | move: emitter-line anchor (84105930) missing, uses fallback position; move: secondary-marker emission (84107998) not implemented | not tested |
| 235 | SYNTHESIS | `P129` particles, model color (peak 32) | `P394` empty in ROM | move: emitter-line anchor (84105930) missing, uses fallback position; move: secondary-marker emission (84107998) not implemented | not tested |
| 236 | MOONLIGHT | `P133` model color, particles (peak 32) | `P394` empty in ROM | move: emitter-line anchor (84105930) missing, uses fallback position; move: secondary-marker emission (84107998) not implemented | not tested |
| 237 | HIDDEN POWER | `P19` background color, model color, screen overlay, particles (peak 1) | `P160` particles, background color (peak 64) | impact: dynamic anchor write (marker-1 pose) unavailable; impact: reads a dynamic anchor that was never written; impact: peak 64 live particles (lag risk) | not tested |
| 238 | CROSS CHOP | `P218` screen particles, screen overlay (peak 2) | `P219` screen overlay, screen particles, particles (peak 91) | impact: peak 91 live particles (lag risk) | not tested |
| 239 | TWISTER | `P1` background color, particles, screen particles (peak 154) | `P385` background color, particles (peak 153) | move: peak 154 live particles (lag risk); impact: peak 153 live particles (lag risk) | not tested |
| 240 | RAIN DANCE | `P187` background color, particles (peak 39) | `P304` background color, particles (peak 18) | impact: context marker (8411E244) not resolved | not tested |
| 241 | SUNNY DAY | `P100` particles, model color (peak 1) | `P306` screen particles (peak 1) | move: emitter-line anchor (84105930) missing, uses fallback position | not tested |
| 242 | CRUNCH | `P325` particles (peak 2) | `P326` particles (peak 31) | move: emitter-line anchor (84105930) missing, uses fallback position | not tested |
| 243 | MIRROR COAT | `P145` particles, background color, model color (peak 1) | `P354` background color, particles (peak 41) | none found | not tested |
| 244 | PSYCH UP | `P15` particles (peak 1) | `P394` empty in ROM | none found | not tested |
| 245 | EXTREMESPEED | `P96` background color, particles (peak 1) | `P324` background color, particles (peak 28) | none found | not tested |
| 246 | ANCIENTPOWER | `P93` background color, particles (peak 3) | `P94` background color, particles (peak 43) | none found | not tested |
| 247 | SHADOW BALL | `P20` particles, background color (peak 1) | `P21` background color, particles (peak 1) | none found | not tested |
| 248 | FUTURE SIGHT | `P142` particles, background color (peak 1) | `P139` particles, background color, model color (peak 1) | none found | not tested |
| 249 | ROCK SMASH | `P136` particles (peak 1) | `P137` particles (peak 18) | none found | not tested |
| 250 | WHIRLPOOL | `P2` particles, screen particles, background color (peak 154) | `P386` background color, particles (peak 153) | move: peak 154 live particles (lag risk); impact: peak 153 live particles (lag risk) | not tested |
| 251 | BEAT UP | `P394` empty in ROM | `P138` particles (peak 17) | none found | not tested |

Implementation follow-up (2026-09-24; original visual results below retained):
- Direct FX model loading now retains compiled FRAGMENT material callbacks and texture bindings. CPU renderer regression verifies textured primitives for moves 5, 14, 16, 43 and 46; visual retest still required.
- Cached FX renderers now receive the material frame from the runtime packet instead of leaving their material clock at zero.
- Follow-up: common and screen particles now pass live age separately from the fixed spawn-hold value. ROM texture sequences for 7, 8, 9, 53 and 55 advance through the actual Player/renderer path and remain stable on repeated draws.
- Compiled mode-0 FX callbacks now apply their full material state (including secondary textures/scrolling), and both compiled and direct FX materials preserve mode-0 authored alpha rather than the Pokemon mode-1 alpha override. Visual retesting remains pending.
- Common-particle placement no longer copies the entire particle snapshot and scene for every particle; public snapshot creation also skips private controller state before copying. Synthetic 150-particle packet preparation: 0.586s to 0.019s over 15 builds (not a viewer FPS measurement).
- Primary/alternate selection remains manual. Blank moves, unfinished motion and camera-wide requests remain open pending further fixes and visual checks.

Model motion follow-up (2026-09-25):
- Connected mode-0 material+2 animation exports to their skeletons in both battle and visual-viewer loading. The supported ROM contains 180 bindings across 131 moves; all decode successfully. This counts animation bindings, not visually complete moves.
- Playback follows native forward/reverse, start-at-end, looping and terminal-frame rules at 30 Hz. Cached model poses are selected per particle; redraws do not advance them. Animated marker writes now use that same pose.
- Swords Dance's 37-bone model plays all 100 authored poses and retires after the final pose in the viewer-path test on both sides. Native counter and completion rules were checked against US ROM execution. Visual retesting is still needed; original observations below are retained.

1 nothing is drawing
2 nothing is drawing
3 nothing is drawing
4 nothing is drawing
5 untextured and unfinished
6 nothing is drawing
7 particles cause lag
8 particles cause lag
9 lag
10 good
11 untextured and unfinished
12 untextured and unfinished
13 untextured and unfinished
14 untextured and unfinished and swords are not dancing
15 good
16 untextured and unfinished
17 good
18 untextured and unfinished
19 nothing is drawing
20 good
21 nothing is drawing
22 good
23 nothing is drawing
24 nothing is drawing
25 untextured and unfinished
26 nothing is drawing
27 nothing is drawing
28 lag and maybe unfinished
29 nothing is drawing
30 nothing is drawing
31 nothing is drawing
32 nothing is drawing
33 nothing is drawing
34 nothing is drawing
35 good
36 untextured and unfinished
37 lag
38 untextured and unfinished
39 nothing is drawing
40 good
41 good
42 good
43 untextured and unfinished
44 untextured and unfinished
45 this effect is finished but should apply to the whole camera * this might not be intended but it's what I want
46 untextured and unfinished
47 whole camera effect needed
48 whole camera effect needed
49 good
50 good
51 unfinished
52 lag and maybe unfinished
53 lag, and the flame is small (check if this is finished)
54 good
55 lag and unfinished
56 unfinished
