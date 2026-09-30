# STADIUM camera: status and remaining work (2026-09-30)

Update 2026-10-01: the camera port is complete (everything reachable in
this game is ported); see the items marked Done below. Nothing is
visually confirmed by the user yet.

Local session. Details and ROM evidence for every item are in
`battle-camera.md`; the per-change user-facing notes are in
`battle_FX_bugs.md`. Nothing here is committed yet (last commit: importer
0.21.0). Nothing listed as done has been visually confirmed by the user
unless it says so.

## Done (ported to Lua and checked against the ROM in the VM)

- Director: shot choice (841119CC), attack (family 2), hit (family 4's
  second state), dodge, turn start (program 10), faint (program 11),
  send-out (family 12), recall (family 18), status / residual (family 9),
  weather (family 28, program 29), full paralysis, the turn check (family
  17), woke up (family 19, program 7), confused (family 20), charge turns
  (families 6 / 7 / 8, programs 2 / 15), confusion self-hit (family 16),
  Substitute (families 11 / 21, the doll swap and swap back), Dig (family
  15, program 6), Transform (family 13), Beat Up (family 22), dragged out
  (family 25), the victory (family 30, program 24).
- Battle start: the split-screen arena intro (family 26, the per-arena
  keyframed paths) and the opening send-out wipe (family 24, programs 21 /
  22), with a two-view renderer (`StadiumCamera:views()`,
  `Camera.sceneFrame` viewports, one scissored pass per view in
  `Scene:render`).
- The command menu's idle camera (family 31, programs 4 / 8 / 9 / 12 / 14),
  run while the host waits for a command.
- The dispatcher's per-event jolt reset; the event timer (record +6).
- Animation-timed follow-ups with host signals (clip ended, Fly / Dig
  departure finished, Transform model shown) and the ROM motion records.
- Programs ported: 0-15, 17, 18, 21, 22, 24, 25 (its target needs the FX layer), 26, 27, 29. Programs 16, 19, 20,
  23, 30 and 31 are never loaded by the ROM (unreachable).

## Fixed after the user's test (2026-09-30)

1. The send-out throw. Stadium's split-screen parts signal their own FX
   entries: 0x112 when the arena intro starts (Dispatch_184) and 0x124 on
   the foe when the opening's wipe is 30 px in (8411C418). The controller now
   signals both through the battle FX adapter (the POKE BALL option covers
   them, like 0x122). The ball opening (0x122) was already played by the
   hosts. Not yet seen in game.
2. Wild battles (USER-REQUESTED EXTENSION, not native; Stadium 2 has no
   wild battles): no split-screen intro; the wild Pokemon's own Stadium
   close-up (species shot row 0x27 via 84113658 and program 12) for 60
   ticks, then Stadium's arena orbit (program 4) until the player's send-out,
   which runs the native opening; no foe throw (0x124) for a wild foe.
   `StadiumCamera:wildEncounter`, `Scene:stadiumWildBattle` (Gen 1: no
   `battle.trainer`; Gen 2: `battle.wild`).
3. Gen 2's split screen went away fast: the player's first send-out cut the
   arena intro. The opening now waits for the intro to finish (Stadium's
   engine waits for it); a turn start still closes a running split
   (host-timing fallback).
4. Idle camera "two frames at once": the over-the-shoulder idle shot
   (program 14) puts the eye at the Pokemon it looks over, and Stadium hides
   that Pokemon (84120E14 -> 8411EE74). The mod drew it, so the camera sat
   inside the model. `StadiumCamera:hiddenSide()` now reports it and
   `Scene:render` skips drawing it for that shot. The pure camera simulation
   showed no pose flip-flop and no second view during idle, so this is the
   best-supported cause; needs the user's retest.

5. Entrance animations missing (after fix 3): the host started them at its
   send-outs, during the arena intro. The camera now holds each host
   entrance until Stadium's opening plays it (player: 8411C310's 0xFC at the
   opening's setup; foe: 8411C418 substate 4 at player +0x7E8 == 0x28) via
   `StadiumCamera:holdEntrance` and `Scene:stadiumEntrance` /
   `Scene:stadiumReleaseEntrance`; released on cut, camera off or a failed
   step. Controller-tested only.

## CAMERA STADIUM on custom scenes (user request, 2026-09-30)

The Stadium camera now runs on the custom (Kenney / painted) scenes too,
not only in the arenas. `Scene:stadiumSpace()` gives where Stadium units sit
in a scene: the arena uses its own scale at its ground; a custom scene fits
Stadium's layout (player at X -150, foe at X +150) onto its two battle
spots (`Stage.positions`, 24 units either side of the centre): scale
24 / 150 = 0.16, a quarter turn about Y (Stadium +X to the player-to-foe
line), origin at the midpoint. While CAMERA is STADIUM there, the Pokemon
take the arena's placement and proportions in that space
(`Scene:modelMatrix`, `Scene:actorPosition`: Stadium slot, facing and
per-species distance, model scale 0.16 x the battler's size), so they stand
on the scene's spots and keep Stadium's relative sizes; they are smaller
than the custom scenes' usual normalized height (about 60% for an
average-size Pokemon), as the user allowed. The camera pose goes through the
same mapping (`Camera.sceneFrame` with `stadiumTheta` / `stadiumOrigin`),
the scene's own framing (`environmentScene.frame`) is not applied then, and
the camera's model markers come back through the inverse
(`Scene:worldToStadium`). Split views and the hidden over-the-shoulder
Pokemon work there as in the arenas. Not yet seen in game.

## The idle flicker, fixed (2026-09-30)

The earlier guess (the camera inside the over-the-shoulder Pokemon) was
real but not the flicker. The flicker was the game's mod sandbox refusing
the ffi library at run time: programs 9 and 14 read a double constant
through it, the camera step raised, and `Scene:updateStadiumCamera` set the
Stadium camera inactive on exactly the frames that ticked, alternating it
with the FREE camera. Found with a headless battle driver logging
`stadiumCameraActive` per frame. The camera now decodes doubles in plain Lua
(`Native.wordsToDouble`), its files do not use ffi (tested), and a failed step
keeps the Stadium camera. Fixed 2026-10-01: the effect ports
(`stadium2_battle_fx_*_native.lua`, `stadium2_libultra.lua`) no longer
require ffi; they and the native memory use exact plain-Lua conversions
(`stadium2_native_memory.lua`: floatWordLua / wordFloatLua /
wordsToDouble, checked against ffi on 6000 values), and the memory loads
and works with ffi refused (tested). ffi stays only as an optional fast path
in the native memory, taken through pcall.

## Remaining camera work

- Done 2026-10-01: the hit follow-up (family 4's third state): the row
  copy, the length, the jolt by result, the per-move lengths, Foresight's
  re-shots, Lock-On's shot and program 25, the end with the HP bar, all
  checked in the VM. Program 25's target (D_8418C958, a particle
  attachment point) now comes from the FX player (see below).
- Done 2026-10-01: event 0x5B is not the turn end but the first mover's
  shot (841343FC queues it before the first action); 8411F9D8 and program
  18 are ported and checked in the VM, triggered after the turn-start orbit
  (see battle-camera.md, "The first mover").
- Program 28 (the idle 0x64 shot;
  needs the game-mode table D_84185258 by D_841910D8, which the host has no
  equivalent for: reported once and skipped).
- Done 2026-10-01: 0x28 (family 23) is Beat Up's end, not Destiny Bond's
  (all three queue sites require move 0xFB); its only camera effect, a kind
  reset, is overwritten by the next event, so it is not wired.
- Done 2026-10-01: the wake-up's tail (84119AB4), Lock-On's aim point
  (the FX player's dynamic anchor 0) and multi-hit lengths (80062D20 from
  the ROM; Gen 2 per-hit signal). Family 1's idle clip stays: the host does
  not play Stadium's idle animation, so the ROM's frame-0x78 cap is used.
- D_8419A007 (8413C820) is never set, so the idle cycle never uses 0x63.
- The arena-5 intro variants (families 33 / 34) belong to Stadium game modes
  the host does not have.
- Resolved 2026-10-01: the "88 species" wake-up offsets came from the
  wrong ROM table (archive + 0x5730 instead of + 0); fixed.
- The second opening record (0x22 for battler 1): two are queued and both
  go to the player's actor, but whether the second restarts the opening is
  unresolved (the VM harness said yes, but its text-box gate never engaged,
  so that result is unreliable). The port keeps the single opening. Details:
  `opening-replay-port-plan-2026-10-01.md`.
- Open questions: 841133EC / 84113430 wait
  for the move's effect assets to finish loading from the cartridge
  (resolved; always clear in the mod, which preloads them).
- Everything above needs the user's in-game test with CAMERA set to
  STADIUM.
