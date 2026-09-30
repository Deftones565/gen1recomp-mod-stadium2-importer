Move bug list

FX fix (2026-10-01, slashes staying on screen, local session):
- Cause: Stadium 2 clears leftover move effects from the battle side when
  the battle returns to the command menu after a turn (and at send-outs),
  a routine the effect code itself never calls. The mod did not do that,
  so the Scratch / Cut / Fury Swipes / Slash mark stayed for about 8
  seconds.
- Fix: the same clear now runs when the command menu comes back after a
  turn, and at every send-out after the first turn. It works with every
  camera setting. Held effects (such as ones a Pokemon keeps) survive it,
  as in Stadium.
- The same lingering screen mark exists in 13 strike moves: Scratch, Cut,
  Wing Attack, Vine Whip, Fury Swipes, Slash, False Swipe, Fury Cutter,
  Steel Wing, Rapid Spin, Iron Tail, Metal Claw and Cross Chop; all are
  covered by the same clear (a sweep of all 251 moves found 34 move banks
  with a lingering screen particle, the rest being clouds and overlays such
  as Mist, the powders, Smokescreen and Sandstorm, which Stadium also keeps
  until that clear).
- Checked with the real ROM data in a test (all 13 strike marks are gone
  after the clear). Needs your retest: use Scratch, Vine Whip or Slash and
  wait for the menu.

Camera trigger fixes (2026-10-01, local session):
- Roar / Whirlwind in Gen 2: the camera always used Stadium's "dragged-out
  Pokemon is asleep" variant. It now picks by the Pokemon's real status,
  as Stadium 2 does.
- Gen 1 trainer switches ("... withdrew ...!"): the foe's recall camera now
  plays, as Stadium 2 does before the next send-out.
- Not possible yet: the player's own switch in Gen 2 has no withdraw step
  in the game, so there is no recall camera for it.

Camera addition (2026-10-01, STADIUM camera, local session):
- Waking up: the camera now holds on the Pokemon until its wake animation
  ends, then 30 frames more, as Stadium 2 does, before moving on.
- Lock-On: the camera now aims at the Lock-On effect, as in Stadium 2, when
  MOVE EFFECTS is on (with it off there is no effect to aim at, so the
  camera holds).
- Multi-hit moves (Fury Attack, Twineedle, Triple Kick, Beat Up and the
  like): the hold after each hit but the last is shorter, as in Stadium 2.
  Gen 2 with MOVE EFFECTS off only; Gen 1 and MOVE EFFECTS on show one
  impact per move, so this does not change there.
- Fixed: the wake-up close-up aimed far off the arena for many Pokemon (for
  example Blastoise, Gengar, Lugia). The camera read the wrong ROM table
  for that shot.
- Matches the ROM in the VM tests; not seen in game yet.

Robustness fix (2026-10-01, local session):
- The move-effect code for Surf, Ice Beam / Hyper Beam, Tri Attack and the
  leaf / petal moves, and the camera's memory, no longer need LuaJIT's ffi
  library, which the game refuses to mods once it is running (the cause of
  the earlier idle-camera flicker). They worked because they loaded at the
  mod's start; now they cannot fail that way. Their ROM tests all pass.

Camera addition (2026-10-01, STADIUM camera, the hit, local session):
- New: after a hit the camera shakes one frame after the impact, harder
  for stronger results (not very effective 10, normal 15, super effective
  20, critical 25), as in Stadium 2. The camera then holds on the hit
  Pokemon until its hit animation ends, or 50 frames after the HP bar stops
  (whichever is sooner), before the idle camera can start. Foresight
  re-aims every 12 frames; Lock-On cuts to its own shot (its final aim
  point needs the effect's position, which is not wired yet, so that part
  is skipped and logged). Matches the ROM in the VM test; not seen in game.
- The hit camera (the cut to the hit Pokemon, the shake and the hold) now
  also works with MOVE EFFECTS (BETA) off, which is the default. Before,
  it only ran with MOVE EFFECTS on. The shake's strength comes from the
  battle's own hit result either way.

Camera addition (2026-10-01, STADIUM camera, local session):
- New: after the turn-start orbit, the camera now turns to the Pokemon
  that acts first, as Stadium 2 does before that Pokemon's move (event
  0x5B, program 18). A newer camera moment, such as the attack itself,
  replaces it. Matches the ROM in the VM test; not seen in game yet.

Camera fix (2026-09-30, "Pokemon no longer do their entrance animation", local session):
- Cause: the opening send-out now waits for the split-screen arena intro
  (the Gen 2 fix), but the game still started each entrance at its own
  send-out, so the entrances played during the intro while the camera filmed
  the arena.
- Fix (Stadium-native timing): in Stadium the opening starts the entrance
  animations itself: the player's as the opening begins (8411C310 plays
  animation 0xFC), the foe's 0x28 frames into its close-up (8411C418
  substate 4). While the STADIUM camera's opening is pending, the game's
  entrance for that side is held and released at those points. Anything
  still held is released if the opening is cut, the camera is switched off,
  or a camera step fails. Wild battles are not held. Checked in the
  controller test only (not in a real game run); needs your retest.

Camera fix (2026-09-30, "two cameras at once" during the idle camera, local session):
- Cause, found in a real headless battle (POKEPORT_DRIVER run on the
  s2evo-test identity): two idle-camera programs (the over-the-shoulder
  shot and one arena orbit) read a double-precision constant through LuaJIT's
  ffi, which the game's mod sandbox refuses once the game is running ("ffi is
  not available to mods"). The camera step then failed and the scene fell
  back to the FREE camera, but only on the frames where the camera ticked (30
  Hz against 60 fps drawing), so the two cameras alternated every frame. It
  started partway into the shoulder shot, when its timer check first read the
  constant.
- Fix: the camera decodes those doubles in plain Lua (exact; checked against
  ffi on 2000 random values in the tests), the camera files no longer use ffi
  (a test enforces it), and a failed camera step now keeps the Stadium
  camera's last pose instead of swapping cameras per frame (the error is
  still logged once).
- Checked in the real game run: no camera error, the camera active every
  frame through the idle shots, and consecutive frames only change at real
  shot cuts. Needs your retest.

Camera follow-up (2026-09-30, STADIUM camera on custom scenes, local session):
- New: CAMERA STADIUM now works on the custom scenes (the painted Kenney
  levels), not only in the Stadium arenas. Stadium's battle layout is fitted
  onto each scene's two battle spots, and while the Stadium camera is on,
  the Pokemon use Stadium's proportions there (so they are somewhat smaller
  than the scenes' usual size). The scene's own camera framing is off then.
- Checked: the controller test (the mapping lands both Pokemon on the
  scene's spots and round-trips), the full suite and the strict-ROM worker
  checks. Needs your test: CAMERA STADIUM on a custom scene.

Camera follow-up (2026-09-30, STADIUM camera, fixes from the user's test, local session):
- Send-out throw: the split-screen parts now play Stadium's throw effects
  (0x112 when the arena intro starts, 0x124 on the foe during the opening
  wipe); the ball opening already played. The POKE BALL option covers them.
- Wild battles (user-requested, not in Stadium 2): no split screen; the wild
  Pokemon's own Stadium close-up, then Stadium's slow arena orbit until you
  send out, then the normal opening wipe (without a foe throw).
- Gen 2's split screen ending fast: your first send-out cut the arena intro;
  the opening now waits for the intro, as Stadium does.
- Idle camera glitch: the over-the-shoulder idle shot had the camera inside
  your Pokemon's model; that Pokemon is now hidden for the shot, as in
  Stadium. Please retest; if it still flickers, tell me which shot.
- Notes on what is done and what is left:
  docs/luna/research/battle-camera-status-2026-09-30.md.

Camera follow-up (2026-09-30, STADIUM camera, seventeenth part, local session):
- New: the camera steps that wait for a Pokemon's animation now happen.
  The mod reads Stadium's own timing for each move from the ROM and uses
  what the game shows as the signal: Fly's second shot comes once your
  Pokemon has flown out of view; Transform's shot comes when the copied
  model appears; the charge turns, Beat Up, the confusion self-hit and Dig's
  first turn finish their camera moves on Stadium's frames.
- Fixed: Dig's first turn now sets the flag Stadium uses to lower the
  camera for a Pokemon in a hole.
- Checked: the director test (520 more ROM rounds with each species' real
  animation data), the controller test, the full suite and the strict-ROM
  worker checks. Needs your test with CAMERA set to STADIUM.

Camera follow-up (2026-09-30, STADIUM camera, sixteenth part, local session):
- New: Stadium's victory camera. When the battle is won or lost, the camera
  frames the winner (a wide shot easing in), then Stadium's close-up of it.
  Running away or catching has no Stadium victory shot. In Gen 1 the battle
  screen closes at once, so it may not show there.
- Changed: the idle camera now plays while the fight menu or move list is
  open (that is when Stadium plays it), not after the turn starts.
- Checked: the director test (20 ROM victories), the controller test, the
  full suite and the strict-ROM worker checks. Needs your test with CAMERA
  set to STADIUM.

Camera follow-up (2026-09-30, STADIUM camera, fifteenth part, local session):
- New: Stadium's idle camera while you choose a command. While the fight
  menu or move list is open, the camera cycles through Stadium's idle shots
  in its order: over
  each Pokemon's shoulder, slow orbits of the arena, close shots of your
  Pokemon and the foe, each for Stadium's own time, until you act.
- One idle shot (a mode-specific arena view) depends on Stadium game modes
  the recomp does not have; the camera holds its previous shot for that
  step's time and a warning is logged once.
- Checked: the director test (400 ROM idle cases, five more camera
  programs), the controller test, the full suite and the strict-ROM worker
  checks. Needs your test with CAMERA set to STADIUM.

Camera follow-up (2026-09-30, STADIUM camera, fourteenth part, local session):
- New: Stadium's opening send-out. When your first Pokemon comes out, the
  camera watches it until its entrance animation ends, then the foe's camera
  wipes in from the right edge and takes over, closes in on the foe, and
  stays there until the turn begins (as in Stadium, where it returns when
  the command menu opens).
- The foe's own send-out before yours keeps the arena intro running, since
  Stadium films both Pokemon in this one sequence.
- Checked: the director test (10 ROM openings), the controller test, the
  full suite and the strict-ROM worker checks. Needs your test with CAMERA
  set to STADIUM.

Camera follow-up (2026-09-30, STADIUM camera, thirteenth part, local session):
- New: Stadium's split-screen arena intro at battle start. The screen splits
  into two cameras (top on your side, bottom on the foe's), each following
  one of the ROM's five intro camera paths; after two seconds the top view
  grows over the bottom one, and after about five seconds the normal camera
  takes over. The battle is drawn twice only while the screen is split.
- If the game sends out the first Pokemon before the intro ends, the split
  closes at once (Stadium would wait; the recomp does not).
- Also: every new battle event now ends any running camera shake first, as
  Stadium's event dispatcher does.
- Checked: the director test (all six paths, 166 frames each, every byte of
  both cameras), the controller test, the full suite and the strict-ROM
  worker checks. Needs your test with CAMERA set to STADIUM.

Camera follow-up (2026-09-30, STADIUM camera, twelfth part, local session):
- New: "It hurt itself in its confusion!" takes Stadium's self-hit shot
  on the confused Pokemon. "SUBSTITUTE broke!" takes Stadium's shot, and
  about a second later the camera goes back to framing the Pokemon itself
  (Stadium's own timing now, not when the doll disappears). "was dragged
  out!" (Gen 2 Roar / Whirlwind) takes Stadium's dragged-out camera
  instead of the normal send-out camera.
- Checked: the director test (360 more ROM cases), the controller test,
  the full suite and the strict-ROM worker checks. Needs your test with
  CAMERA set to STADIUM.

Camera follow-up (2026-09-30, STADIUM camera, eleventh part, local session):
- New: charge turns. "flew up high!", "dug a hole!", "made a whirlwind!",
  "took in sunlight!", "lowered its head!" and "is glowing!" now take
  Stadium's charge-turn camera. Dig's first turn changes shot again about
  a second later, as in Stadium.
- Not yet: Fly's second shot (Stadium waits until the Pokemon is high
  enough, which the mod cannot see yet) and the charge moves' follow-up
  shots, which wait for the animation.
- Checked: the director test (400 ROM cases plus programs 2 and 15 in the
  runner), the controller test, the full suite and the strict-ROM worker
  checks. Needs your test with CAMERA set to STADIUM.

Camera follow-up (2026-09-30, STADIUM camera, tenth part, local session):
- New: Dig, Substitute, Transform and Beat Up use Stadium's own cameras
  instead of the ordinary attack camera. Dig follows the digger with its
  own camera program. Substitute switches to the doll's framing about a
  second after the move (and back when the doll is gone).
- Not yet: Transform's and Beat Up's later shots, which in Stadium wait for
  the model animation to finish.
- Checked: the director test (500 ROM cases plus program 6 in the runner),
  the controller test, the full suite and the strict-ROM worker checks.
  Needs your test with CAMERA set to STADIUM.

Camera follow-up (2026-09-30, STADIUM camera, ninth part, local session):
- New: "woke up!" gives Stadium's wake-up close-up (its own camera program
  from per-species data in the ROM), and "is confused!" gives Stadium's
  confusion shot.
- Open: for 88 species the ROM's wake-up data looks unusable (the camera
  target would land far outside the arena). The port does what the ROM
  does; if that happens, the camera keeps its last good view and a warning
  is logged once. Please tell me what the wake-up shot looks like.
- Checked: the director test (240 ROM cases plus program 7 in the runner),
  the controller test, the full suite and the strict-ROM worker checks.
  Needs your test with CAMERA set to STADIUM.

Camera follow-up (2026-09-30, STADIUM camera, eighth part, local session):
- New: weather. When rain, sun or a sandstorm continues or ends (Gen 2), the
  camera takes Stadium's wide arena shot (program 29). The sandstorm hurting
  a Pokemon uses Stadium's residual shot, as in part six.
- New: the turn check. "is fast asleep!", "is frozen solid!", "fully
  paralyzed!", "flinched!", "must recharge!" and (Gen 2) "thawed out!" put
  the camera on that Pokemon as Stadium does. The engine has no event for
  these, so the mod recognises the exact line it prints.
- Checked: the director test (200 ROM turn checks, 160 weather and
  paralysis cases, program 29 in the runner), the controller test, the full
  suite and the strict-ROM worker checks. Needs your test with CAMERA set to
  STADIUM.

Camera follow-up (2026-09-30, STADIUM camera, seventh part, local session):
- New: recall. When a Pokemon is called back, the camera takes one of
  Stadium's four recall shots on it (a special one when it is frozen).
- Checked: the director test (120 ROM recalls and the recall camera
  program), the controller test, the full suite and the strict-ROM worker
  checks. Needs your test with CAMERA set to STADIUM.

Camera follow-up (2026-09-30, STADIUM camera, sixth part, local session):
- New: status and residual events (poison, burn, Leech Seed, trapping,
  stat changes, healing, love, and in Gen 2 Nightmare, Curse and Spikes).
  The camera takes Stadium's shot for that event on the Pokemon it happens
  to, as the effect plays. This also works with battle FX off.
- Checked: the director test (300 ROM cases), the controller test, the
  full suite and the strict-ROM worker checks. Needs your test with CAMERA
  set to STADIUM.

Camera follow-up (2026-09-30, STADIUM camera, fifth part, local session):
- New: misses. When a move misses, the camera cuts to Stadium's dodge shot
  on the defender (as in Stadium, the attacker gets no attack camera). In
  Gen 1 it follows the "attack missed!" line.
- Checked: the controller test (the dodge's three event codes and the Gen 1
  miss line), the director test (already covers the ROM side), the full
  suite and the strict-ROM worker checks. Needs your test with CAMERA set
  to STADIUM.

Camera follow-up (2026-09-30, STADIUM camera, fourth part, local session):
- New: send-out. When a Pokemon comes out, the camera takes one of
  Stadium's two send-out shots on it, rises with it for about two seconds,
  pulls back, then settles into Stadium's follow-up shot (program 26).
  Stadium waits for the ball's throw before it starts; here it starts with
  the send-out.
- Checked: the whole send-out against the ROM byte for byte, frame by frame
  (the director test, 469 checks), the controller test, the full suite and
  the strict-ROM worker checks. Needs your test with CAMERA set to STADIUM.

Runtime follow-up (2026-09-30, no more VM, local session):
- Razor Leaf (75), Petal Dance (80), Surf (57), Ice Beam (58), Hyper Beam
  (63) and Tri Attack (161) no longer run Stadium's code in the built-in
  emulator (the VM). Their effects are Lua ports of that code now, and
  nothing in the game uses the VM; it only checks the ports in tests.
- They are 2-7 times faster (Razor Leaf 12.4 -> 1.9 ms per frame).
- They are also slightly closer to the N64: the old path swapped in the
  PC's own sine and cosine for Stadium's, and a few helpers were
  approximations.
- Checked: every ported routine against the ROM byte for byte over whole
  effects, the full suite and the strict-ROM worker checks. Needs your
  test: those six moves should look the same as before.

Camera follow-up (2026-09-30, STADIUM camera, third part, local session):
- New: turn start. Once both sides have chosen, the camera swings round on
  one of Stadium's five turn-start orbits before the moves play. The game
  waits for that swing to finish; here the first move can cut in early.
- New: faint. When a Pokemon's faint starts, the camera cuts to one of
  Stadium's three faint shots on it and follows it down.
- Checked: both against the ROM byte for byte (the director test, 308
  checks), the controller test, the full suite and the strict-ROM worker
  checks. Needs your test with CAMERA set to STADIUM.
- Not yet: send-out, which keeps the last shot.

Camera follow-up (2026-09-30, STADIUM camera, second part, local session):
- The attack camera now follows Stadium's own attack state. Each move uses
  its own shot, taken from Stadium's per-move camera table; the first part
  wrongly used one random attack shot for every move. Fly, Surf, Waterfall
  and Rapid Spin get their own camera programs.
- New: when the defender is hit, the camera cuts to Stadium's hit shot for
  that move on the defender. Sleep and freeze pick Stadium's variants. The
  cut happens at the impact.
- Checked: every new routine against the ROM byte for byte (the director
  test, 225 checks), the controller test, the full suite and the strict-ROM
  worker checks. Needs your test: moves with CAMERA set to STADIUM, including
  Fly or Surf.

Camera follow-up (2026-09-30, STADIUM camera, first part, local session):
- New option CAMERA: FREE (the field camera, default) or STADIUM (Stadium 2's
  own battle camera, ported from the ROM to Lua, no VM).
- STADIUM so far: when a move starts, Stadium's attack camera on the
  attacker (one of its six attack shots, chosen at random as in Stadium),
  following the Pokemon and with the hit jolt. Other moments (turn start,
  faints, send-outs, the per-move shots) keep the last shot until they are
  ported.
- Checked: every ported camera routine against the ROM byte for byte (maths,
  shot setup, program 0 over 1,500 ticks, the runner), a controller test, the
  full suite and the strict-ROM worker checks. Needs your test: a battle with
  CAMERA set to STADIUM.

Runtime follow-up (2026-09-29, the white square on hits, local session):
- The hit of Pound (1) and 99 other move/context entries showed a white
  square. Their hit sparks (shape 109: a flat 32-unit white quad, scaled by
  its scale curve to about 0.8 units and spun 45 degrees a tick) were drawn
  for one tick at full size when each spark was born, before their first
  update. Stadium updates a particle before it is ever drawn (841055D8: the
  scheduler 84107B68 runs before the particle pass 841029DC).
- Fixed for every move: particles the scheduler creates in a tick get their
  first update in that tick at age 0; a move route's zero-time births (made
  after the tick's pass) are not drawn until the next tick's update. Model
  animations (e.g. Swords Dance) still start on frame 0 at their first draw.
- Entries using the sparks: 1 2 3 4 6 7 8 9 10 11 12 15 16 17 19 21 23 24 26
  27 29 30 31 32 33 34 36 37 38 39 44 49 52 58 63 64 65 66 67 68 69 70 88 91
  98 99 117 119 121 125 128 130 136 140 143 152 154 155 157 158 162 163 164
  165 167 168 172 173 174 175 179 181 183 185 196 198 200 206 210 211 214 216
  217 218 220 221 223 224 228 229 231 232 233 238 242 243 245 246 249 251.
- Checked: new test `tests/stadium2_battle_fx_birth_update_test.lua`, the
  strict-ROM worker checks (the ROM oracles for Sonic Boom, Needle and the
  radial families still match). Needs your retest: Pound and any other hit.

Runtime follow-up (2026-09-29, move results for Thief, Present, Curse, Snore
and shiny Pokemon, Gen 2, local session):
- These moves pick between versions of their effect from the battle result.
  That result was never passed in, so they could not choose. Now, from the
  Stadium 2 ROM's battle engine:
  - Curse (174): a Ghost-type Curse plays its move effect; the stat-raising
    Curse plays only its hit effect, as in Stadium.
  - Snore (173): plays its "asleep" version.
  - Thief (168) and Present (217): play the version for no item stolen and
    no heal, because Gen1Recomp's engine never steals or heals with them.
  - Shiny Pokemon: the send-out effect (and four related effects) now take
    their shiny branch. Stadium tests the same DVs as the Game Boy games.
    Gen 2 only.
- Checked: ROM assembly for all four (notes in
  `docs/luna/research/move-record-inputs-2026-09-29.md`), new tests, the
  full suite and the strict-ROM worker checks. Not seen in game yet.
- Open: the exact result value Stadium gives a Ghost Curse's hit effect
  (needs an emulator capture).
- Needs your retest: a Ghost Curse (Gengar/Haunter), a stat Curse, Snore
  while asleep, Thief, Present, and sending out a shiny Pokemon in a Gen 2
  battle.

Runtime follow-up (2026-09-29, timing audit T01/T02/T04, local session):
- T01: delayed work (impacts, routes, event effects) now fires on its own
  30 Hz tick, in order, even when one screen update covers several ticks
  (a slow frame). Before, it all fired together on the last tick, out of
  order.
- T02: a newer move drops the older move's queued hit, and a Pokemon that is
  switched out or replaced drops queued effects aimed at it or owned by it.
- T04: finished effects are removed instead of being kept and walked every
  frame for the whole battle (lag in long battles). A synthetic benchmark
  cut late-battle FX work per frame from 0.189 ms to 0.005 ms; not measured
  in game.
- Checked: new tests (queue timing, effect retirement), the full suite, the
  strict-ROM worker checks and `tools/audit_battle_fx_timing.lua`. Needs
  your retest: a long battle, with switches during moves, should show no
  stray late hits and no growing lag.

Runtime follow-up (2026-09-29, Bind/Wrap end-of-turn damage, local session):
- Bind (20) and Wrap (35)'s end-of-turn damage (entry 261) drew nothing: its
  ribbon family (29) was not implemented. It now plays the ribbon that wraps
  the trapped Pokemon, the same effect family as other ribbons, sized per
  species from Stadium's own table (from 0.4 to 2.55, e.g. Onix 2.4).
- From the ROM assembly: same colours and motion as family 23; it follows
  the trapped Pokemon's marker each tick. The exact marker Stadium picks is
  not decoded yet, so the Pokemon's move-row marker stands in (reported).
- Checked: ribbon and lifecycle tests, a new ROM test for entry 261, the full
  suite and the strict-ROM worker checks. Needs your retest: a Gen 2 battle
  where Bind or Wrap traps the opponent (the effect plays at end of turn).

Free-camera addition (2026-09-29, user-requested, NOT Stadium 2 behaviour,
local session):
- Effects placed on the camera's view ray (descriptor bit 0x1; the jaws of
  Vice Grip 11, Guillotine 12, Bite 44, and any other effect placed the same
  way) now turn with the free camera, so they stay square to the view, and
  stop drawing when the move's impact starts. That is where Stadium cuts the
  camera to the defender and takes them off screen. Their native lifetime and
  motion are unchanged; a failed move (no impact) keeps them for their full
  lifetime. Battles only; the viewer stays native.
- Code: `lib/stadium2_battle_fx_camera_follow.lua` (the addition),
  hooks in `stadium2_battle_fx_player.lua` (draw), `..._battle_adapter.lua`
  (enable, and hide at impact), packet fields in `..._draw_packets.lua`.
  Test: `tests/stadium2_battle_fx_camera_follow_test.lua`.
- To be replaced by Stadium's own camera shots once those are implemented.
- Follow-up after the user's retest (Vice Grip "not attached to the camera"):
  the native ray distance (80 source units for the jaws) is converted with
  the attacker's model scale in classic/Kenney scenes, which put them out
  among the battlers. They are now drawn 4 world units in front of the eye
  (80 units at Stadium's .05 field scale, as arena scenes already have) on
  the same ray, scaled by the same factor, so their on-screen size is the
  native one and nothing covers them.
- The family (descriptor bit 0x1, 37 moves, all in the move's own bank):
  11 12 13 16 18 19 43 44 46 59 71 72 93 94 96 99 101 116 117 128 137 138
  141 149 158 162 170 184 193 197 202 212 234 235 236 241 242.
- Needs your retest: Vice Grip, Guillotine, Bite and a few others from the
  list (e.g. Leer, Psychic, Crunch), including while orbiting.
- User retest (2026-09-29): the camera attachment (turning with the free
  camera and drawing in front of the eye) is removed at the user's request;
  these effects are placed natively again. Kept: they stop drawing when the
  move's impact starts (the user confirmed that part was good).

Research follow-up (2026-09-29, jaw moves stay on screen, local session):
- A 60 Hz clock change made earlier today was reverted after the user's
  retest (everything ran at double speed). Battle logic, effects and clips
  run at 30 Hz in Stadium 2, as the port already did; only the rendering is
  60 fps. [FX clock note](docs/luna/research/fx-clock-rate-2026-09-29.md)
- From the user's Guillotine save state replayed in mupen64plus: the jaws are
  3D objects placed just in front of the attack camera, so they look fixed
  to the screen. They are still visible at video frame 10 and gone from
  frame 13, when Stadium cuts the camera to the defender; the jaw itself
  lives on to age 35 in both games.
- So the jaws (Vice Grip, Guillotine, Bite, and likely other camera-placed
  effects) stay on screen in the port because the port has no Stadium camera
  cuts, not because of their lifetime. Fix: Stadium's per-move camera shots
  (item 9 of the parity audit), at least the cut to the defender at impact.

Runtime follow-up (2026-09-29, T03 fixed, local session):
- Particles now leave at age 255 by the ROM's own rule: only those whose
  descriptor has flag `0x10` stay past it (object flag 1 in `84107170`,
  tested by `8410009C` through `84100074` with mask 1). Before, the port used
  the unrelated "falls to the ground" flag for this, so those particles
  lived on while the `0x10` ones died early.
- Moves whose effects carry one of these flags include Mist (54), the
  powders (77–79), Haze (114), Powder Snow (181), Icy Wind (196), Rapid
  Spin (229), Rain Dance (240) and many impact effects. Most particles end
  earlier by other rules, so a visible change is only expected where a
  particle reached age 255 (~8.5 s).
- Checked: motion test (all four flag combinations), full importer suite,
  strict-ROM worker checks. Needs your retest of long-lasting effects
  (Mist, Haze, Rain Dance, the powders).

User report (2026-09-29): slashing effects stay on screen after they play.
Research follow-up (2026-09-29, local session; research only, no fix yet):
- **S01 — The move-bank slash lives ~8.5 s.** Scratch (10), Cut (15),
  Fury Swipes (154) and Slash (163) each spawn one mode-7 screen particle
  (shape 82; program 206 records 7/10 for Scratch) that stretches to 6.2×
  in ~6 ticks and then stays at full alpha until the age-255 cutoff
  (~tick 285). Their orange screen flash and the impact bank's slash end
  within 16–18 ticks, as they should.
- The decoded ROM data gives that particle no earlier end: material end age
  0, no alpha ramp (the impact slash has one), no colour tracks, not held,
  shape 82 does not fade itself, and Stadium does not clear the particle
  pool between moves (`84100134` only runs at battle setup). All retirement
  paths of `8410009C` were checked in the assembly.
- So the port matches the decoded data, but not what the user sees in
  Stadium 2. Open question: is Stadium's stretched slash placed off-screen
  (our mode-7 screen transform, changed 09-27, may differ), cleared by a
  path not yet found, or on a faster clock? Next step is a real-game
  capture of Scratch (emulator or reference video) to compare with the
  viewer. No fade or timeout will be invented meanwhile.
- Evidence, addresses and reproduction:
  [slash persistence](docs/luna/research/slash-persistence-2026-09-29.md).
  Needs no retest yet (nothing changed).

Timing/lifetime audit (2026-09-28–29; research only, findings added as verified):

- **T01 — Batched updates fire delayed FX late and can reverse their order.**
  `Adapter:update` advances all runtime ticks before servicing the route,
  impact, event and charge queues. A controlled route-at-2 / impact-at-1
  probe produces impact at 1 then route at 2 with single ticks, but route
  then impact at 3 with one three-tick update. The final route-finish signal
  also differs (0 versus 1). Both battle adapters permit three ticks per
  update. This is a demonstrated scheduler defect; the fixture is not a
  claim that Water Gun's retail row has those frame values.
- **T02 — Superseded moves and replaced models retain scheduled work.** A
  newer move replaces `pendingRoute`, but does not clear the prior move's
  queued impact/charge/event callbacks. `modelChanged` only resets model
  color state. Controlled probes show the old impact firing at tick 10
  after a new move starts, and at tick 8 after its target model changes.
  Queued callbacks identify a side, not a particular actor incarnation.
  Exact live-battle frequency still needs captures; this is separate from
  the concurrent fix for already-running recall color controllers.
- **T03 — Common-particle age-255 survival tests the wrong flag.** Executing
  supported-ROM `8410009C` proves object bit 1 exempts the age-255 cutoff;
  descriptor bit `0x10` sets it in `84107170`. Lua instead exempts the
  independent Y-termination bit (`descriptor 0x10000000`). At age 255 and
  positive Y, descriptor `0x10` incorrectly dies; `0x10000000` incorrectly
  survives. Mist/powders/Haze and other catalog entries use the first bit;
  many impact entries use the second. Other termination gates may end them
  earlier, so this does **not** mark every such move visibly broken. The
  older common-particle note and motion test encode the same wrong rule.
- **T04 — Finished-effect history is retained for the whole battle.** After
  1,000 real-ROM empty Pound primary routes and 360 ticks, the runtime still
  snapshots 1,000 effects with zero live particles. `effects`, `effectOrder`
  and ordinary expired particle records are not retired until full release.
  The 300-slot live pool therefore does not bound all per-tick/snapshot work.
  This is a storage/work lifetime issue; no FPS impact is claimed here.
- **T05 — ThunderShock (84) loses a repeating impact emitter.** Its real
  program 167 descriptor `84177B4C` has repeat byte zero. Six executions of
  native scheduler `84107B68` emit on passes 0,1,2,3,4,5; `Native.births`
  emits only on 0. Signed nonpositive counts remain active in the native
  scheduler until release; zero is not a one-shot count.
- **T06 — Native age freeze is being treated as invisibility.** At its
  material endpoint, descriptor bit 2 sets object flag `0x80` (`84102320`),
  which stops byte-age advancement in `841054D4/841055A0`. Lua sets
  `nativeHidden`, removes the draw packet, and continues aging. A ROM
  prepass holds age 3 while Lua reaches age 4 and is hidden. Catalog exposure
  includes Baton Pass (226) and event entries 254/256/275/285/286/288/301;
  exact visible lifetimes need per-entry captures.
- **T07 — Gen 2 Magnitude (222) starts FX on the deferred announcement.**
  The host sets `deferAnim` on the move row, then later starts the animation
  through a message row with `moveAnim`. `Scene:handleEvent` schedules FX
  on the first row and ignores the actual animation row; the model clip
  correctly waits for `animForMove`. The early row can also be marked
  finished because it has no animation runner. Reproduced through the live
  scene adapter using the host's event shapes.
- **T08 — Negative-hit-frame pre-roll advances the new clip by too much.**
  `Actor:stepPendingClip` changes from idle to the move clip at the pre-roll
  boundary, then `Actor:update` gives the new clip the entire update delta.
  With a two-tick pre-roll and three elapsed ticks, three single updates
  leave the clip at frame 2; one three-tick update leaves it at frame 3.
  The pose and FX timeline therefore depend on display/update partitioning.
  This is an isolated actor-clock probe, not a claim about Pound's real row.

Evidence, scope, reproducer and remaining checks:
[timing audit](docs/luna/research/timing-lifetimes-2026-09-28.md).
Primary decomp consulted: merged michiiik/pokestadiumgs
`026460f8a239c720fa38ac8c5a702b51a5bdfc2e`. These are diagnosed gaps,
not fixes or user-confirmed visual results. Earlier observations stay below.

Research completion (2026-09-27; incorporates the newer local follow-ups):
- **New confirmed no-draw path: Bind/Wrap residual damage (20/35), entry
  261 / `0x105`, lifecycle family 29.** The Gen 2 event hook exists, but the
  runtime ribbon implementation only handles families 23/26/27. Family 29
  reports `unsupported-lifecycle-callback` and `lifecycle-model-unresolved`.
  A real-pose CPU probe reproduces both warnings on both owners. Native
  callbacks `8415703C/841570B4/841570D4` establish separate setup inputs and
  `8415BD48(1)`; the implemented family 23 uses mode 0. This corrects the
  earlier blanket claim that trap ticks/all lifecycle families are complete.
  Initial Bind/Wrap move FX are separate and remain implemented.
- The Absorb diagnosis below was addressed by local commit `f3eac59` during
  this audit; user retest is still required. That commit also corrected the
  sequence-test expectation. I reran the strict-ROM worker checks on the
  current checkout (`c029438` plus concurrent UI work): **passed**. The old
  failed gate below is the initial audit result, not the current result.
- Hydro Pump (56) drawing is user-confirmed in the local follow-up below.
  The remaining highest priorities are family 29, Ghost Curse/result/status
  input plumbing, and the unported actor/event paths listed in the audit.
- Runtime frame-phase ordering also differs from `841055D8`; its visible
  consequences need a complete-frame ROM comparison. Native global/table
  bookkeeping and the reviewed lifecycle timeouts are not counted as
  missing effects. See the corrected runtime research note.

User retest (2026-09-27, Hydro Pump):
- Hydro Pump (56) draws; confirmed by the user in game. Remove it from the
  open "invisible water shape" item in docs/WORK_SPLIT.md and older notes.

Battle follow-up (2026-09-27, Gen 1 Absorb vs Leech Seed, local session):
- Fixes item 1 of the parity audit below. In Gen 1, an ordinary Absorb (71)
  could play Leech Seed's drain effect (0x103) instead of its own move FX:
  the recomp sets `pendingHit` only after the animation starts, so the old
  check saw every ABSORB row as the Leech Seed drain.
- Now the move's own row (`moveAnimRow`) decides it: the first ABSORB start
  after that row has left the queue is the move; any other ABSORB start is
  the Leech Seed drain on the seeded side. No host code is wrapped or changed
  (`lib/gen1_battle.lua`, `Scene.isResidualAbsorb`). The Gen 1 FX test now
  follows the host's real ordering (`pendingHit` still nil at start).
- Needs your retest: a Gen 1 battle where one side uses Absorb and the
  other has Leech Seed.

Test follow-up (2026-09-27, ROM acceptance gate, local session):
- `stadium2_battle_fx_sequence_test.lua` expected the old timing (one bank
  at the hit frame). Since the attack-state timeline, the move route starts
  at the attacker's hit frame and, with no defender row, the impact starts
  on the same frame. The test now checks that, plus a defender-row case
  where route and impact are checked at their own frames. The strict ROM
  gate (`STADIUM2_REQUIRE_ROM=1 tools/run_battle_fx_worker_checks.sh`)
  passes again. Test-only change; no visual change.

Parity research follow-up (2026-09-27; current backlog, no runtime fixes):

Checked importer `aede59e9c230b994eeddd5fb527e3b885d0813ab` against current
merged michiiik/pokestadiumgs master
`0ed78d46e9cd11432f217203675a839efcb1cc1c`, with the supported US assembly
for functions still marked GLOBAL_ASM. The original observations and earlier
follow-ups below are retained. This section supersedes older implementation
status claims; **nothing is newly marked visually fixed**.

Confirmed missing/wrong integration, highest priority:

1. **Gen 1 Absorb (71) can take the Leech Seed residual path instead of its
   move FX.** `gen1_battle.lua:presentAnimStart` tests `pendingHit == nil`
   to distinguish them. The real `AnimPlayer:start` hook runs before
   `BattleState` assigns that move's `pendingHit`, so an ordinary Absorb
   meets the residual condition, signals `0x103`, and clears the move route.
   The existing test supplies hit data before the hook and misses this
   ordering. Needs an explicit move/residual discriminator from the host.

2. **Curse (174), and result/status-dependent branches, lack live inputs.**
   The adapter requires native result bit `0x80` to start Curse's primary
   route, but the host bridge only reconstructs damaging-result values
   `0..5`; no Ghost-Curse outcome supplies that bit. Separately, the computed
   damage result is used for impact selection but is not passed into the
   particle evaluator's `nativeBattleState`. Thief (168), Snore (173),
   Present (217), and entries 274/290/292/298/299 still need their result,
   source status, or owner status-pattern inputs for `841083B0`. The viewer's
   neutral zeros hide this integration gap. This corrects the older broad
   claim that the battle result byte is fully fed through.

3. **Some battle-event effects still have no host trigger.** Gen 2:
   full paralysis (`0x10C`), attraction turn state (`0x108`), Spikes
   switch-in damage (`0x10B`), Leftovers recovery (`0x10D`), Destiny Bond's
   event (`0x123`), and player recall (`0x126`). Spikes' move-191 setup FX
   and Attract's move-213 FX are separate from these event entries. Gen 1
   stat-change and full-paralysis presentation also remain open. Do not
   infer a side or outcome from an ambiguous message. Native selectors:
   `84118DD4`, `841189EC`, `84119630`; recall: `8411ABAC`.

4. **The FX banks are only part of several moves.** Actor behavior dispatch
   `84123F60/84124104` still has unported kinds for Surf (57), Submission
   (66), Seismic Toss (69), Meditate (96), Withdraw (110, with native species
   exceptions), Waterfall (127), Faint Attack (185), Belly Drum (187),
   Destiny Bond (194), and Rapid Spin (229). Their particles reaching the
   renderer does not prove their Pokemon movement/visibility is complete.
   Agility (97), Double Team (104), and Minimize (107) have implementations
   now and belong in the retest list, not the "no implementation" list.

Remaining rendering, timing and lifecycle work:

5. **Inherited material state is incomplete.** A model that never sets its
   environment color receives white from our renderer instead of the native
   submission's inherited value. This is consistent with the previously
   reported white jaws (11/12/44). Cross-model combiner/environment state
   still needs tracing; do not prescribe guessed colors. Wind sheets
   (13/16/18/46), Strength (70), and Swords Dance (14) have subsequent
   material fixes and need retests before attributing their current output
   to this remaining gap.

6. **Native layer/pass and pool ordering are not fully represented.**
   `84103394` selects mode-1 draws by the child object's layer; `84103478`
   handles its separate overlay predicates. The player lacks that complete
   native layer selection, and sorts mixed screen packets by birth tick
   instead of native pool-slot order. Slot reuse can therefore change
   overlap order. This is a code-level difference; its visible impact needs
   a targeted capture. See the rendering note for actual mode-1 routes.

7. **Status particles lack their selective release/hide/show operations.**
   `84108AF8/84108CE8/84108E00/84108F88/84109118` operate on status shapes
   `0x12/0xD3/0x13D`, ownership, and descriptor flags. Ordinary held release
   (`84108A10`) is implemented, but does not cover these cases. Wiring a
   weather-end entry alone also does not implement `84109118`'s pool scan.
   These are status/event lifecycle gaps, not evidence that every move
   using the same texture is wrong.

8. **Sequence parity remains partial.** Battle playback has the newer
   attacker/defender-row schedule. Viewer SEQ still starts the move bank
   immediately and uses the attacker's hit frame for impact, so it cannot
   validate the battle timing. The defender clip still begins at impact
   instead of native hit-state entry, and `84117948`'s result-dependent
   reaction suppression is not applied. Other defender handlers, approach
   and release latency, and missed/failed move presentation need caller
   traces; the hosts skip missed move animations before FX dispatch.

9. **The battle camera is still a field/manual-shot camera.** Native
   event-selected camera programs (`84111348/841113F8`, `841119CC`) and
   their evolving actor-relative anchors are absent. Even manual presets
   use estimated model bounds and raw table FOV, where `8410C934/8410CAE4`
   overwrite FOV with 45 or 80 degrees. This affects framing and the camera
   input used by already-implemented camera-ray/wave effects. Onix also has
   no producer for the camera-owned `nativeFxHeightPoint` required by
   `8411EF90`, leaving its height-flagged attachment path unresolved.

Performance, requested behavior, and visual acceptance:

- No new frame-time measurements were made. The historical improvements
  (roughly 8.6–15 ms warmed frames, one roughly 360 ms initial model-load
  frame) are previous measurements, not today's results. First-use loading
  and the reported lag still need target-machine retests. Particle counts
  alone do not identify the bottleneck.
- Growl/Sing/Supersonic (45/47/48): native wave-grid placement is already
  camera-relative. Full viewport coverage has not been established. Keep
  the requested whole-camera behavior open; if it requires going beyond
  native coverage, implement and label it as a separate extension.
- Retest the original no-draw and unfinished-texture reports after the
  09-24/25 changes. Empty primary banks are intentional for many physical
  moves; test their complete sequence. Animation, marker emission,
  camera-ray anchors, 300-slot allocation/pool-origin spawning, billboards,
  render modes, wave finish, and two-turn routing have implementations.
  Old per-move "missing" rows for those paths are historical. The original
  user table still has moves 57–251 marked untested; later developer checks
  are not a substitute for user visual confirmation.

What was checked this time:

- Fresh ROM sweep: **251 moves, 1,004 bank/side scenarios, 360 ticks each,
  zero execution failures**. Repeating it with the real CPU FX pose evaluator
  removes all animation/dynamic-anchor warnings from the stub-renderer run.
  This tests execution and resource/pose availability, not GPU appearance.
- The required strict-ROM worker check **fails** at
  `stadium2_battle_fx_sequence_test.lua:238`: its old expectation counts one
  new bank at tick 14; the new schedule queues both banks there when the
  defender row is absent. The remaining tests were run separately and pass.
  The stale assertion still needs updating; the full gate is not green.
- The old 502-bank peak/draw table and full call-graph census were not
  regenerated. All species, result/status branches, live event sequences,
  GPU pixels, and performance remain outside this sweep.

Detailed evidence, addresses and current-source references:
[integration](docs/luna/research/parity-2026-09-27-integration.md),
[rendering](docs/luna/research/parity-2026-09-27-rendering.md),
[runtime](docs/luna/research/parity-2026-09-27-runtime.md),
[camera and validation](docs/luna/research/parity-2026-09-27-camera-and-validation.md).
Updated diagnostic counts: [implementation audit](docs/battle_fx_missing_implementation_audit.md).

Viewer follow-up (2026-09-25, moves 11, 12, 13, 16, 18, 44, local session):
- The jaw (Vice Grip, Guillotine, Bite) and wind-sheet (Razor Wind, Gust,
  Whirlwind) models now use the combiner and colours their own display
  lists set, plus the per-node table combiner Stadium applies (layout 0x23
  byte 1). Before, they had no combiner and drew black or flat white.
- Static FX shapes were being drawn as arena geometry (opaque "replace"
  blending), which made the wind sheet a black wall. They now blend, and
  follow their node layer's render mode (no depth writes).
- The jaws still draw white: their colour depends on an environment colour
  the model never sets and inherits from earlier draws, which is not
  decoded yet.
- Needs your retest.

Battle follow-up (2026-09-25, moves with no effect data, web session):
- Growth, Metronome and Splash: in Stadium these are just the species'
  own move animation, which the mod already plays. Nothing was missing.
- Minimize now shrinks the Pokemon to 80% over 20 frames from the move's
  hit frame, and it stays small until it's switched out, as in Stadium.
- Rest now plays Stadium's effect 0x100 on the user at its hit frame, then
  the sleep pose.
- Agility and Double Team use their own model routines in Stadium (speed
  blur / clones); decoded where they live, not implemented yet.
- Needs your retest.

Battle follow-up (2026-09-25, move timing, web session):
- Moves now follow Stadium's attack timeline from the species' own rows:
  the attacker's animation starts partway in (row byte 6) as in Stadium;
  the move's effect starts at the attacker's hit frame instead of at the
  start; the defender's impact comes from the defender's own row (byte 7)
  after the attacker releases it. Previously the effect started
  immediately and the impact came at the attacker's hit frame.
- Special cases from the ROM: Explosion, Self-Destruct and the healing
  moves release the defender later; Withdraw/Lick/Rollout play only their
  sound for a few species (Squirtle line, ghosts, Golem...); Curse's effect
  needs the ghost result. Two-turn moves were already timed this way.
- Needs your retest (effects should now line up with the Pokemon's
  motion; tell me any that start late or feel off).

Battle follow-up (2026-09-25, Sandstorm near-black, web session):
- Move 201 is one full-screen particle (program 11, mode 7, shape 147;
  decoded from fragment 79's data, no colour layer). Shape 147 has two
  layers. The second is a grain layer whose colour combiner starts from the
  N64's NOISE input (random grey per pixel): (NOISE*LOD) then
  (PRIM - that) * that. The mod had no NOISE input, so that layer drew as
  solid black wherever its textures were bright. NOISE is now implemented
  in both shaders. Also applies to any other effect using NOISE.
- Needs your retest. If 201 is still too dark, run
  `luajit mods/STADIUM2_IMPORTER/tools/dump_fx_colors.lua 201 > dump.txt`
  from the Gen1Recomp folder and send me dump.txt.

Battle follow-up (2026-09-25, lines through screen effects, second fix):
- The lines were a regression from 3429234: taking effect shapes off the
  arena path also switched their texture filtering from smooth sampling
  to the 3-point shader filter. Effect shapes are smooth-sampled again
  (7895ccb); the blend change from that commit stays. The earlier
  3-point weight fix (795893c) still stands for Pokemon models.
- Needs your retest (201 and the other screen effects).

Battle follow-up (2026-09-25, lines through screen effects, web session):
- The dashed diagonal lines and regular stripes across Sandstorm (201) and
  other screen effects came from a bug in the N64-style 3-point texture
  filter: in half of every texel two weights were swapped, so the image
  jumped along each texel's diagonal. Effect shapes only started using
  that filter in 3429234 (they were smooth-sampled as arena models before),
  which is why it appeared on many effects at once. Fixed; the same filter
  is used on Pokemon models, where the error was small but present.
- The near-black colour in your 201 screenshot is not explained by this.
  If the screenshot was taken before restarting the viewer on 8f05e6e,
  retest; otherwise the local session will dump 201's shader inputs.
- Needs your retest.

Battle follow-up (2026-09-25, sandstorm colour, local session's fix,
finished by the web session):
- Sandstorm (0x113/0x120, shape 147) drew as a near-black screen layer. Its
  N64 colour combiner never reads the vertex shade, so on the N64 the
  scene lighting cannot darken it, but the mod lit it anyway. Battle-FX
  surfaces whose combiner ignores shade are now drawn unlit, so it keeps
  its sand colour. Applies to every such FX surface. Thunderbolt and
  Psychic's white screen flashes are their own authored flashes, not this.
- Needs your retest (Sandstorm, and a few common moves for any colour
  change).

Battle follow-up (2026-09-25, switching and trapping, web session):
- Withdrawing a Pokemon now plays Stadium's recall effect (0x126) on it:
  Gen 1 when your Pokemon starts its retreat, Gen 2 when the opponent's
  "withdrew" line shows. Gen 2's own switch-out skips the withdraw step
  entirely, so your switches there have nothing to attach it to yet.
- Bind, Wrap, Fire Spin, Clamp and Whirlpool's end-of-turn damage (Gen 2)
  now plays Stadium's trap effect for that move on the trapped Pokemon.
- Ball throws and bag items: Stadium 2 has neither (no wild battles, no
  bag in battle), so they keep Gold/Red's own animations.
- Needs your retest (recall effect over the send-out in Gen 1: the host
  swaps the Pokemon 7 frames after the retreat starts).

Battle follow-up (2026-09-25, Agility and Double Team, web session):
- Agility (97): from the hit frame the Pokemon sways sideways, building up
  to 50 Stadium units and settling back home (about 80 frames), trailed by
  two half-transparent copies of itself, as Stadium's 84121920/84120F5C do.
- Double Team (104): two half-transparent copies fade in and swing out to
  each side (a quarter of the species' body height) while the Pokemon
  itself flickers, as Stadium's 84121DE8 does.
- Both end when the move's clip ends. Arena mode only. Ported from the
  assembly; not visually checked. Needs your retest (see the side of the
  sway, and whether the copies look right with depth).

Battle follow-up (2026-09-25, two-turn moves, web session):
- The charge turn of Razor Wind, Fly, SolarBeam, Dig, Skull Bash and Sky
  Attack now plays Stadium's charge clip for the species and the move's
  charge-turn effect (the variant route), timed from the species' charge
  row. The second turn plays the move normally. Gen 1 and Gen 2.
- Gen 1 Fly's charge turn no longer plays Teleport's move effect.
- Needs your retest.

Battle follow-up (2026-09-25, status and battle-event effects, web session):
- Stadium's effects now play for: poison/toxic and burn damage, Leech Seed,
  Curse, stat raises (your own, Rage, Belly Drum) and drops (Sand-Attack,
  Growl, String Shot, Screech, Smokescreen, Flash, Cotton Spore, Charm,
  Sweet Scent, exactly as in Stadium), drain heals (Absorb, Mega Drain,
  Giga Drain, Leech Life, others), berries, send-out, and fainting (timed
  per species). Gen 2 gets all of these; Gen 1 gets poison/burn, Leech Seed,
  send-out and faint. Needs your retest.
- Leech Seed in Gen 1 no longer plays Absorb's move effect for the drain.
- Not yet: Leftovers, Spikes, full paralysis, Attract, and Gen 1 stat
  changes (the recomp's events don't carry enough to identify them).

Battle follow-up (2026-09-25, resting poses, web session):
- Pokemon now hold Stadium's resting poses between actions: asleep loops
  its sleep clip, frozen holds its hit clip, a Pokemon up in the air during
  Fly loops its in-air clip, and Diglett/Dugtrio stay visible underground
  during Dig (other species are hidden underground, as in Stadium). Decoded
  from Stadium's idle state. Needs your retest in Gen 1 and Gen 2 battles.

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

Local follow-up (2026-09-25, Razor Leaf / Petal Dance and lag):
- Razor Leaf (75) and Petal Dance (80): the leaves and petals drew as grey
  noise squares because their RGBA16 sprite texture was decoded as I4.
  Checked in real-time viewer playback: green leaves and pink petals now fly
  to the target (commit 93022dd). Retest.
- Lag and crash: Razor Leaf took 1-1.4 s per frame in real time. Fixed in
  three steps: the MIPS VM no longer allocates a closure per instruction
  (256c22f); each draw reuses one runtime snapshot; lifecycle geometry is no
  longer deep-copied twice (50e77b1). Real-time averages on the local
  machine now: 75/80 about 11 ms; 7, 8, 9, 28, 37, 52, 53, 55 between 8.6 and
  15 ms. The first play of a move still has one ~360 ms frame while its
  models load. Retest for lag.

Local follow-up (2026-09-25, textures on the worst-moves list):
- Swords Dance (14): five of the six swords drew their blades and guards
  with the brown grip texture. They now use the chrome callback texture
  with environment mapping (commit 8a1e8eb). Retest.
- Take Down / Double-Edge (36/38): the speed streaks drew as opaque black
  bars. Intensity (I4/I8) textures now use alpha = intensity as on the N64,
  so they are translucent white streaks. Retest.
- Hydro Pump (56), Strength (70), Absorb/Mega Drain (71/72),
  Earthquake/Fissure rocks (88), Razor Wind leaves (13), Vicegrip (11/12)
  and Bite (44): their shapes render in an isolated close-up only. That
  says nothing about how they look in the viewer (the user found Razor
  Leaf's leaves wrong there), so these still need viewer checks.
- Open: the wind sheet used by Razor Wind, Gust, Whirlwind and Roar
  (13/16/18/46) and Strength's column (70) render as a dark opaque wall.
  Their ROM nodes set no combiner of their own; they inherit the state left
  by Stadium's model-draw setup, which is not decoded yet.

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
