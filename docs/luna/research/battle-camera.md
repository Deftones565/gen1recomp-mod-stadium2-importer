# Battle camera direction (in progress)

Web session, 2026-09-25. Sources: US assembly for fragment79 (user's pret
split), michiiik/pokestadiumgs `7fc529e5` C. Matches ROM assembly; nothing
here is visually confirmed. This note records the architecture decoded so
far and the plan; the mod still holds the field shot in battle.

## Two layers

1. **Camera programs.** 84111348(owner, program) copies 7 handler pointers
   from D_8418414C + program*0x1C into D_841911E0 +8/+0x10/.../+0x38 and
   stores the owner actor in +4/+0xC/.../+0x34; 841113F8 does the same for
   D_841911E4. There are 32 programs (0-31); most use slot 0 (eye path) and
   slot 1 (look/zoom), a few a third slot; unused slots hold the no-op
   8411123C. 52 distinct handlers, almost all GLOBAL_ASM. Reachable closure:
   129 functions, ~7,100 instructions (13 in main code, e.g. 800371B4).
2. **Shots.** D_841911E0+0x98 is the shot index into D_8418455C (39 rows,
   now all in `lib/battle_camera.lua`). 8410C934 / 8410CAE4 (C) set up a
   shot: 8410B974 computes the target from the actor (yaw from +0x20, or
   8411E140 for the eight species in D_8418393C), then pitch/yaw from the
   row (yaw relative to the actor's facing), distance = camera+0x74 * row
   distance, field of view 45 (80 for shot 0x24 and rows 37/38), and
   800371B4 places the eye. 841203B4 (C) eases values per frame
   (v += (goal - v) * rate). 8410B884 is the B-variant setup.
   The shot index 0x27 (written by 84113E7C) reads past row 38; unresolved.

## Who selects shots (writes to +0x98)

| Writer | Shot |
| --- | --- |
| 8411F94C (event 0x5A, turn start) | random of 5 from D_84183C60, program 10 |
| 841168A0 / 84116BC0 (attack) | random of 6 from D_84183BDC, or fixed 3 / 0x16, or per-move via D_841849BA + move*8 -> 841119CC |
| 8411A3D4 (faint) | random of 3 from D_84183C74 |
| 8411ABAC | random of 4 from D_84183C7C, 0x11 for event 0x20 |
| 84113E7C (codes 0x5C-0x69) | D_84183C44 / D_84183C54 / 0x27 |
| 8411BB04 (send-out family) | D_84183AA8 |
| 8411A19C | 0x24 / 0 |
| 841157D8 / 84115940 / 84115D4C / 84119CF0 | 8 / 0x10 / 0xE / 0x25 |
| many states | 0 on entry or exit |

84116BC0 also copies per-species, per-move dispatch row bytes +0x10..+0x13
to actor +0x628/+0x62A/+0x62C/+0x661, special-cases moves 0x17 (Stomp),
0x22 (Body Slam), 0xCD (Rollout), 0x12 (Whirlwind), 0x2E (Roar) and the
species list D_84183A0C via actor +0x61F, and branches on the event code.

Programs per state family (from the event-code chain in
battle-event-effects.md): 0, 1, 2, 3, 4, 6, 7, 8, 9, 10, 11, 12, 13, 14,
15, 21, 24, 25, 26, 27, 28, 29 are selected.

## Plan

1. (web) Decode the shot/program choice per event and per move into a
   director table: which program and shot each presented event selects,
   with the random tables and the per-move rows. Pure decoding, unit tested.
2. (local) Camera math with the ROM: run the program handlers in the FX
   MIPS VM (as lifecycle families already do), or port them and compare
   against the VM. Needs the ROM and the fragment image, so it belongs to
   the local session.
3. (web) Drive `battle_camera.lua` from battle events through the director,
   using step 2's evaluator.
Random choices must use an injected presentation RNG, never the battle RNG.


## Local session findings and Lua port (2026-09-29)

Sources: US assembly in pret/pokestadiumgs `c0e10f2`, C in michiiik
`15201a6`. User direction: the camera is **ported to Lua** (no VM at
runtime); every port is checked bit for bit against the ROM routine run in
the MIPS VM. Camera option: STADIUM (this port) or FREE (the current camera).

### Structure (decoded)

- Two **GeoCameras** (`D_84190428`, `D_841910E0`; split screen uses both).
  `8410AE8C` applies one: viewport, perspective with FOV `+0x2C`, near 20,
  far 6400, and look-at from eye `+0xA8..B0` to target `+0xB4..BC`
  (`80038E14`; up vector at `+0xC0`).
- Two **controllers** (`D_841911E0`, `D_841911E4`, 0xA4 bytes, `8410B27C`),
  each pointing to its GeoCamera at `+0`: seven handler slots `+0x8..+0x38`
  with owners `+0x4..+0x34`, target `+0x50`, `+0x5C`, eye `+0x68`,
  distance `+0x74`, height `+0x7C`, FOV `+0x88`, jolt `+0x8C` (set by the
  defender hit, `8410B578`), pitch `+0x90`, yaw `+0x92`, shot `+0x98`,
  viewport `+0x9A..+0xA0`.
- **Per tick:** `84111774(gc0, gc1)` calls controller E0's seven handlers
  (`handler(gc0, owner)`), then E4's, then `841114A8`, which only sets 3D
  sound panning from the Pokemon's positions (`80037120`, `8002421C`); it
  does not move the camera. The handlers write the GeoCamera directly.
- **Programs:** `84111348(owner, program)` / `841113F8` copy seven handler
  pointers from `D_8418414C + program*0x1C`. 32 programs, 51 distinct
  handlers (2,244 instructions of their own) plus shared helpers
  (`8410B974` 267, `841119CC` 136, `8410C934`/`8410CAE4` ~108 each, ...).
  `8411123C` is the no-op; `841112C8` / `84111248` clear a controller's
  slots to it.

### Ported and verified (tests/stadium2_battle_fx_camera_math_rom_test.lua)

| ROM | Lua (`lib/stadium2_battle_camera_native.lua`) |
| --- | --- |
| `8000B350` / `8000B3B0` | `atanLookup`, `atan2` (table `D_8008CE50`) |
| `80037120` | `angleTo` (distance, pitch = atan2(flat, dy), yaw = atan2(dz, dx)) |
| `800371B4` | `placeEye` (tables `D_80087E50` / `D_80088E50` = sine +0x400) |
| `841203B4` | `ease` (snap to 0 inside +/-0.001) |
| `8003570C` | `nextRandom` (LCG; the port draws from a presentation RNG) |

### Next

1. Shot setup: `8410B974` (actor anchor and distance), `8410C934`,
   `8410CAE4`, `8410B884`, `841119CC` (per-move shots), with the shot rows
   read from `D_8418455C`. Needs the actor fields they read (`+0x20` yaw,
   `+0x61F`, `+0x634..+0x654`, markers through `8003C9B8`), traced in the VM.
2. The 51 handlers, programs used in ordinary battles first.
3. The director: which program and shot each battle event selects.
4. The STADIUM / FREE option and battle integration.

### Actor inputs of the shot setup (decoded)

`8410B974` (anchor and distance for a shot) reads actor `+0x1A`, position
`+0x24`/`+0x2C`, `+0x7EA`, `+0x7F4`, the battle record `D_84193DD0`, and the
camera fields `+0x634..+0x654`. Those come from a **per-species camera
record** (`84112704` copies it from actor `+0x664`):

| Record | Actor | Use (from `8410B974` / 84110xxx) |
| --- | --- | --- |
| +0x04 | +0x64C | shot distance (controller +0x74) |
| +0x08 | +0x650 | |
| +0x0C | +0x654 | height (controller +0x7C) |
| +0x10..+0x18 | +0x634..+0x63C | anchor offset (rotated by facing, `8410B8FC`) |
| +0x14 | +0x648 | copy of the anchor Y |
| +0x1C | +0x640 | controller +0x80 |
| +0x20 | +0x644 | controller +0x84 |

`84113014` sets `+0x664` to `D_84193E38 + side*0x30`, DMA'd from ROM
archive `D_49B780 + D_22E0 + (species-1)*0x30` (species = actor `+0x658`).
So the camera's per-Pokemon distances and heights are ROM data the Lua port
reads directly; the scene supplies only positions, facing and markers.

### Shot setup ported (tests/stadium2_battle_fx_camera_shot_rom_test.lua)

`8410C934` / `8410CAE4` (`Native:shot` / `shotB`), `8410B974` (`anchor`),
`8410B8FC` (`rotateOffset`), `8411DC80` (`inList`), `8411E1F8` (`side`),
`8411E140` (`sideFacing`), `8411E0A4` (`markerPoint`; `8411DD8C` is the
scene's `markerPosition`), `8410B884` (`secondaryPose`). 300 randomised
scenarios (actors, records, shots 0..40) match the ROM byte for byte over
both controllers, both GeoCameras and `D_841911E8`, including 75 runs of the
marker branch. The Lua work on `lib/stadium2_native_memory.lua`, a byte
memory with the ROM's addresses (no execution).

### Program 0 (the most used; handlers shared by programs 1, 5, 12, 13, 16, 17, 20, 30, 31)

- Slot 0 `84110394` (one-shot): `84120BB4` reset (actor `+0x7EA` = 0, up
  vector (0,1,0), `8411EF2C` status visibility, `84120700` on both actors,
  jolt off via `8410B578(0)`), `8410C934` with the controller's shot
  `+0x98`, then the slot becomes the no-op (`D_84184148`).
- Slot 1 `84110718` (every tick): FOV eased to controller `+0x88` at 0.05;
  `8410DFC4` (follow/reframe, see below) unless the actor kind is in
  `D_8418393C`; `8410E688` for shots in `D_84183944` (14 entries) else
  `8410E73C` (both: `8410B884` then `8410B704`); then `84110B2C` (hit jolt).
- `84110B2C` (controller 0 only): jolt phase `+0x96` += 0x38E0 per tick,
  amplitude `+0x8C` eased to 0 at 0.16; eye/target y += cos(phase)*amp/3,
  and x/z moved sideways (camera yaw + 0x4000) by the same amount.
- `8410B704`: goal eye around the centre from the secondary pose
  (`+0x3C/+0x3E/+0x40`); shots in `D_84183930` jump to it, others ease a
  fraction `+0x44` toward `+0x4C` at `+0x48` and move that fraction of the
  way; eye height clamped to at least 10.
- `8410DFC4` (~440 instructions): when the actor's marker point
  (`8411E0A4`) is farther than slack `+0x80` from the look point it
  reframes, with species cases 0xE8, 0x24, 0x57, 0x9C, 0x49, 0xE2, 0x9B,
  0x71 through `8410D9B8`, `8410DAC8`, `8410DEB4`, `8410D5CC`. Skipped while
  record flag 4, actor `+0x7F4` bit 0x10, record `+0x10` = 0x20, or actor
  scale `+0x34` <= D_84188F48.
- **Scene side effects:** `84120700` resets actor scale `+0x30` to 1, lifts
  `+0x28` for flying/underground states, clears `+0x1C`, and calls the status
  particle routines `84108F88` / `84108E00` and `84112290`; `8411EE74` also
  calls `84108E00`. These become callbacks into the battle scene and the FX
  runtime (the status-shape operations are still unported: audit gap 6).

### Program 0, runner and loaders ported (2026-09-30)

`tests/stadium2_battle_fx_camera_program0_rom_test.lua`: 84110394 and
84110718 (with 8410DFC4, the four band tables 8410D5CC / 8410DAC8 /
8410D9B8 / 8410DEB4, 8410E688 / 8410E73C, 8410B704, 84110B2C, 84120BB4,
8410B578) match the ROM byte for byte over 150 scenarios and 1,500 ticks
(every band table exercised, 286 jolts); 84111348 / 841113F8 and the runner
84111774 match over 480 ticks. The reset's scene side effects (8411EF2C,
84120700) are callbacks; 841114A8 (sound panning) is left out.

### In battle (CAMERA option, default FREE)

`lib/stadium2_battle_camera.lua` fills Stadium's actor structs from the
scene (layout position and facing, species, the ROM camera record, HP),
supplies 8411DD8C from the model's height marker (Endpoints.heightPoint;
without markers the anchor point stands in, reported once), and steps the
port at 30 Hz. Random choices use the game's LCG (8003570C) on a private
seed, never the battle RNG. The director is below.

### Director: which state picks the shot (2026-09-30)

Sources: US assembly (pret/pokestadiumgs `c0e10f23`) for functions still
under GLOBAL_ASM, michiiik/pokestadiumgs `1b6dc17c` (origin/master) C for
84114A04, the fork's BattleAnim_ModelDispatch_* handlers and the Gen 2
engine's 84124604 / 841246AC. Matches ROM execution where a VM test is
named; otherwise it matches the decomp C.

Event records reach 8411FF1C, which switches on the code (jtbl_84189A80) and
gives the side's actor a state family through 841125F4 (7 states from
D_84183D54 + family x 0x1C):

- Event 0 (a move) goes to family 2 for moves 1..0xFA, except 0x5B (15), 0xA4 (11),
  0x90 (13) and 0xFB (22). Family 2 is 841149A0, 84114A04, 841154F8.
  **84114A04 is the attack state**: 84114804 sets the shot to
  841119CC(D_841849B6[move * 8]) and the attacker's kind (+0x61F) by move.
  Then, unless the shot is 0x21, it loads program 0 on the attacker (Fly 0x13: shot 14 and
  program 5; Surf 0x39: 13; Waterfall 0x7F: 3; Rapid Spin 0xE5: 17).
- Event 1 goes to family 16 (84116918, 84116980 = BattleAnim_Dispatch_114,
  84116AC4). 841168A0's random shot of D_84183BDC belongs to this family,
  not to an ordinary move. The first wiring used it for every attack; that
  was wrong and is replaced.
- Events 0x0A-0x15, 0x3B and 0x4B go to family 4 (84116F7C, 841170A0,
  841187E4) on the side named by the record. **841170A0 is the defender's
  hit state**: 84116BC0 sets the defender's kind by move and the shot by
  event code. Codes 0x10 / 0x14 / 0x4B use 841119CC(0x28). 0x11 uses a
  random pick of D_84183BDC. 0x12 and 0x15 use shot 3, and 0x13 uses shot
  0x16. Every other code uses 841119CC(D_841849B6[move * 8 + 4]). Then,
  unless the shot is 0x21, it loads program 1 on the defender (8411744C).
- The Gen 2 engine queues the defender's code in 84124604 for a landed hit:
  0x0B when asleep (status & 7), 0x0D when frozen (& 0x20), else 0x0A.
  841246AC queues 0x13 / 0x12 / 0x11 the same way on a miss (84130EA8,
  D_841951D2 set). So an ordinary hit is 0x0A and a dodge is 0x11.
- 841119CC(ctrl, selector): selectors 0x28..0x32 draw from 11 lists
  (jtbl_84188FC0, D_84183BDC..D_84183C34). Any other value is the shot.
- Other users of D_841849B6 +0 (not wired yet): 8411B070 and
  BattleAnim_Dispatch_079 / _156 (multi-turn and repeat states).

Ported and verified against the ROM in the VM
(`tests/stadium2_battle_fx_camera_director_rom_test.lua`, same seed at
D_80124D50 on both sides):

- 841119CC: 400 cases, every list.
- 84114804's and 84116BC0's camera parts: 600 cases, all branch codes.
  Their dispatch-row copies (841146D4, and 84116BC0's first block) belong
  to the model animation layer and are not ported.
- 84114A04 with its non-camera calls stubbed: 300 cases.
- Programs 1 (84110F64 with 8410E7D0), 3 (84111048, 841110C4, 8410D040),
  5 (841105CC with 84120CA4 and 8410CC90), 13 (84110980) and 17 (8410CF80):
  1,600 runner ticks through 84111348 / 84111774.
  84120CA4's 841125F4(other actor, 0) and 84111048's 8411EFE4 (home pose)
  are battle flow and scene work, so they are not ported (8411EFE4 is an
  `onActorHome` callback, and `sync` already sets the home pose).

In battle: the host calls `attack(side, move)` when a move is presented and
`hit(side, move, condition)` from the adapter's impact hook. The event code
comes from the presented sleep and freeze. Timing is approximate: the ROM
enters 841170A0 when the defender's record is read, and the host uses the
impact. Without battle FX the adapter has no impact hook, so there is no
hit camera.

### Turn start and faint (2026-09-30)

Same sources and fork commit as above.

- Event 0x5A is queued once a turn by the battle loop 841347A0 (fork C),
  after both sides chose and before the turn runs. 8411FF98 then calls
  8411F94C(0, code), which puts both actors in family 0, sets the event
  timer (8411FEE8(0x64)), picks a random shot of D_84183C60 (5) and loads
  program 10 on the player. The host's `battle.turn_started` fires at the
  same point in both engines. Stadium holds the turn's later records until
  program 10 releases the timer; the host does not wait.
- Program 10: 841111D8 (84120AC4 reset, 8410EA58: the eye on the shot's
  D_841844D0 orbit pose around (0, 40, 0)) and 8410ED30 (8410EB50 eases
  the eye to the row's second pose; within 1.75 the handler calls
  8411FEE8(0) and empties its slot). 8410EB50 scales its rates only when
  80001FF0 returns 50 (PAL, osTvType 0); the US ROM on NTSC takes the
  unscaled branch, the only one ported.
- Faint: event 0x1C, family 5, state 8411A544 (fork C). It sets +0x7F4 = 0.
  8411A3D4 then picks a random shot of D_84183C74 (3) unless +0x7EC bit 0
  is set. Unless the shot is 0x21, program 11 is loaded on the fainting
  actor, and +0x7EA = 0. Program 11: 84110408 (84120C20 reset, 8410CAE4)
  and 841107D8 (FOV ease, 8410D174 banded reframe with the species list
  D_84183988 exempt and a +2 bonus for 0xA1, 8410B884 at the actor's
  facing, 8410B60C). The host calls it when the faint clip starts.

Verified against the ROM in the VM (director test): 8411F94C in 200
cases, 8411A544 in 200, and programs 10 and 11 through the runner. Program
10 reached its end in most of its 60-tick rounds. The event timer calls
are counted on both sides.

### Send-out (2026-09-30)

Same sources. Actor states work like camera programs: 84112648 runs the
actor's seven state slots every frame, then advances its frame counter
+0x7E8. Family 12 is 8411BB04, 8411BC28 and 8411BCC8.

- 8411BB04 (entry, once): unless the shot is 0x21, it clears controller 0
  (84111248), picks a random shot of D_84183AA8 (0 or 6), and places the
  opening shot with 8410C544. That runs 84120BB4 and the shot's anchor, then
  puts the eye 50 from (+-150, 20, 0) on the actor's side at the shot's
  pitch and turned yaw, with FOV 45.
- 8411BC28 waits for the model (800427B8) and signals entry 0x122.
  8411BCC8's substate 1 waits for 84113430, then starts substate 2 with the
  counter at 0, so substate 2's first frame sees 1.
- 8411BCC8 substate 2, each frame:
  - The shot is swapped (0 <-> 6) for the frame's work.
  - On frame 1, the secondary pose runs at the actor's facing.
  - On frame 0x3E, +0x44 is set to 0.
  - Before frame 0x3E it calls 8410C720(50, 70, 0, 0); from then on
    8410C720(75, 30, 0.5, 0x1C71). 8410C720 steps the pitch toward -0xE38
    with 84120310 (BattleAnim_StepToS16), eases the target height, and
    closes the eye on the pose.
  - From frame 0x61 the swap stays, program 26 is loaded (unless the shot is
    0x21), and +0x7F4 is set to 0.
- Program 26: 84110264 (the shot, the secondary pose, the eye at half the
  distance level with the look point) and 84110910 (FOV ease, follow, and
  8410C840, which steps the pitch toward 0xAAA and eases +0x44 to 0.2 at
  0.06, keeping the eye at height 5 or more).

Verified against the ROM in the VM (director test): 60 whole send-outs,
frame by frame with the camera runner through the hand-over, and program 26
through the runner.

In battle: the host calls it when it starts the send-out (Gen 1: the grow
starts; Gen 2: the send event). Stadium first waits for the ball's throw and
the Pokemon's appearance before counting frames; the host starts counting at
once. A later event for that actor ends the send-out, as 841125F4 does when
it gives the actor a new family: turn start for both actors, and attack,
hit and faint for their own actor.

### Miss (dodge) (2026-09-30)

On a miss the engine queues no move event for the attacker (8412E420's
missed branch). It queues only the defender's event through 841246AC:
0x13 when asleep (status & 7), 0x12 when frozen (& 0x20), otherwise 0x11,
after the miss text (0x66, or 0xB5 in 84126BA8). That is family 4's hit
state 841170A0, already ported:

- 84116BC0 gives 0x11 a random shot of D_84183BDC, 0x12 shot 3 and 0x13
  shot 0x16.
- Program 1's 8410E7D0 holds the look pose on 0x11.

In battle:

- Gen 2 calls it on a presented move event marked `missed`.
- Gen 1 calls it when the miss line is presented. That line is
  EffectRegistry's `_AttackMissedText` with its `displayName`, rebuilt with
  the engine's own RomText so only that line matches. The move is the
  user's `lastMove`, which is set before the accuracy roll.

### Status and residual events (family 9) (2026-09-30)

Events 0x06 and 0x3C-0x59 (poison, burn, Leech Seed, Nightmare, Curse,
Spikes, trapping ticks, stat rises and falls, healing, drain, love...) give
the actor family 9: 84118990, 841189EC, 84118C08 and 84118DD4.

- 84118990 sets +0x7F6 = 1.
- 841189EC sets +0x7F6 = 2 on frame 2 as it signals the FX entry.
- 84118C08 (skipped while +0x7F6 is 1) then picks the shot by event code:
  - Event 6, 0x3C, 0x3D, 0x49, 0x55 and 0x57-0x59 set shot 0.
  - 0x47 and 0x4B keep the shot.
  - The rest of 0x3E-0x56 draw selector 0x28 until the shot differs from
    the current one.
  - Then it loads program 0 on the actor.

Verified against the ROM in the VM: 300 cases over every code it handles
(director test).

In battle: the hosts call it when they signal the event's FX entry (Gen 1:
poison, burn and Leech Seed rows; Gen 2: `signalEventFx`, now also when
battle FX is off). The code comes from the entry through the mapping
already recorded in `stadium2_battle_fx_sequence.lua`
(`StadiumCamera.ENTRY_EVENT`). A trapping tick's code comes from the
trapping move (84132778): Fire Spin 0x4C, Clamp 0x58, Whirlpool 0x50,
otherwise 0x45.

### Recall (family 18) (2026-09-30)

84124C10 queues 0x1E, 0x1F (asleep) or 0x20 (frozen) on a switch-out, and
0x37 without an effect for a fainted mon. That is family 18, whose camera
state is 8411ABAC (fork C): a random recall shot of D_84183C7C (4 entries)
and program 27 on the outgoing actor, with shot 0x11 instead when frozen.

Program 27:

- 84110320: 84120BB4, then 8410CC90 holds the eye; then its slot empties.
- 84110860: FOV ease; the follow while the target height is above 10,
  otherwise the height is held at 10; the secondary pose at the actor's
  facing; 8410B60C.

Verified against the ROM (director test): 120 recalls, and program 27
through the runner. In battle it runs at the hosts' recall points (Gen 1:
the player's retreat; Gen 2: the enemy's withdraw line), with or without
battle FX.

### Turn check (family 17), weather and full paralysis (family 28) (2026-09-30)

Decomp: michiiik/pokestadiumgs fork C where noted, otherwise the US asm
(the same commits as the sections above). jtbl_84189A80 (8411FF1C) sends
codes 2-5, 7-9 and 0x2C to 8412011C (family 17), 6 to 8412010C with
0x3C-0x59 (family 9), 0x30-0x35 to 841201F0 and 0x36 to 84120204 (family 28).
0x1D (woke up) goes to 84120168 and 0x26 (confused) to 84120178; neither is
ported.

- The turn check 84127194 queues each code right after its text
  (84135B00): 0xA8 "is fast asleep!" -> 4, 0x42 "It's frozen solid!" -> 2,
  0x4D "was defrosted!" -> 0x2C, 0x6D "It's fully paralyzed!" -> 0x36, 0x78
  "is ATTRACTED to" -> 6. After 0x54 (must recharge), 0x5A (flinched) and
  0x2A (disabled) it calls 84124594 (fork C): code 4 when the mon's status
  has bits 0-2 (asleep), 2 with bit 5 (frozen), else 3. Stadium text IDs
  are from the message table at ROM 0x1D8CDA4.
- 84119CF0 (family 17's camera part): shot 0, program 0, kind +0x61F = 0xFF;
  code 7 then takes shot 0x25 when the side's flags (record +0x12) have bit
  1, else 0x24; 8 takes 0x24 and 9 takes 0x26. Codes 7-9 come from 84124BA0
  and are not reached by the turn check.
- 841193E0 (weather, from the state's frame 2, codes 0x30-0x35): unless
  the shot is 0x21, program 29 on the actor. Program 29 is one handler,
  8410FB0C: FOV 45, 84120960 (84120AC4's reset with the scales D_84189C4C
  / D_84189C54), pose 0x222 / 0, distance 500, target (0, 180, 0) when either
  side's flags have bit 1 (else (0, 40, 0)), eye (-323, 394, 268).
- 8411957C (fork C, Dispatch_199), code 0x36: shot 0 and program 0 unless
  +0x7F6 is 1.

Ported in `lib/stadium2_battle_camera_native.lua` (turnCheckState,
weatherState, paralysisState, program29Setup) and checked against the ROM
in the VM: 84119CF0 in 200 cases, 841193E0 / 8411957C in 160, program 29
in the runner rounds. Mutation checks (a wrong shot for code 7, a moved
eye, a skipped weather state) all fail the test.

Triggers. Weather, the sandstorm hit (0x48) and full paralysis already
have host entries (Gen 2 weather messages, FxSequence). The other turn-check
lines have no engine event, so, per the user's rule, the hosts match the
exact line the engine prints: Gen 1 rebuilds it with `battle:romText` and
`EffectRegistry.displayName`, Gen 2 with `Strings` and `battle:monName`
(`Scene.TURN_CHECK_LINES` in each host). Gen 2's "thawed out!" maps to
0x2C. The "react" rows use 84124594's rule on the mon's status. Visual
parity is not confirmed by the user yet.

### Woke up (family 19) and confused (family 20) (2026-09-30)

Decomp: michiiik/pokestadiumgs fork `15201a6` (C for Dispatch_141-143,
84111BEC, 841206D0, 84113430, 84113014's setter 84112FFC); US asm for
84119908, 84119AB4, 8410E8E4 and 84113014. The dispatcher sends 0x1D to
8411FC10 (841125F4 family 0x13) and 0x26 to 8411FD78 (family 0x14). In the
turn check, text 0xA9 "woke up!" precedes event 0x1D and text 0x5B "is
confused!" precedes 0x26; 0x5D "confused no more!" queues no event.

- 84119908 (family 19's first state), camera part: when the side's flags
  (record +0x12) have bit 2, shot 0 and program 0; otherwise program 7.
  84119AB4's substates only wait on the model animation and end with
  84111BEC (the kind reset); they are not ported.
- Program 7 is one handler, 8410E8E4, never emptied, so it runs every frame:
  84120BB4, FOV 80, target = actor position + the species offset row turned
  by the actor's yaw (x/z mirrored by 8411E1D4's side sign), eye from the
  row's distance (+0xC), pitch (+0x10) and signed yaw (+0x12) via 800371B4.
  +0x678 points at D_84193DF8 + side * 0x20, which 84113014 fills from
  archive 0x49B780 + 0 (0x20 bytes per species, plain DMA 80003F74).
- Resolved 2026-10-01 (US asm 84113014): the row +0x678 points at is
  DMA'd from the archive's first table, 0x49B780 + 0 + (species - 1) *
  0x20, not + 0x5730 (that table goes to D_84193E98 / +0x668, and + 0x22E0
  to D_84193E38 / +0x664; + 0x8970, 0x50 per species, to D_84193ED8 /
  +0x67C). The earlier note misread the relocations. From table 0 the row
  is clean (x 0, height, z, distance, pitch, yaw: species 1 has 0 / 15 / 0
  / 61 / 1200 / 12640), so the "88 species far outside the arena" came
  from the wrong table. The loader and the oracle scenario now use it; a
  controller test checks species 9, 94, 249 and 25 aim at the Pokemon.
- Dispatch_142 (family 20), once 84113430 allows it (busy flag
  D_84193DDC & 0xC0, assumed clear): shot 0x24 when the side's flags have
  bit 1, else 0, and program 0. Dispatch_143 resets the kind (841206D0,
  +0x61F = 0xFF) when the frame counter Dispatch_142 zeroed reaches 0x1E;
  the controller schedules it 30 ticks later and cancels it on the side's
  next event.

Checked against the ROM in the VM: 84119908, Dispatch_142 and 841206D0 in
240 cases (every branch), program 7 in the runner rounds. Mutation checks
(a moved target, the wrong branch, the wrong confused shot, a missing kind
reset) all fail the test. Triggers: Gen 1 `_WokeUpText` / `_IsConfusedText`,
Gen 2 "woke up!" (status event) and "is confused!". Not visually confirmed.

### Dig, Substitute, Transform and Beat Up (families 15, 11, 13, 22) (2026-09-30)

Decomp: michiiik/pokestadiumgs fork `15201a6` (C for Dispatch_078/079/092/
106/108/156, 8411B070, 8411B1F4, 84116460, 84116808, 84120D34, 8410E73C,
8411AF6C, 841166C4, 84115D98); US asm for 84115E28, 84115D4C, 8411B3B8,
84112B64, 84113014, 84110640, 841111B0, 8411B160, 8411AEA8. 8411FF1C sends
event 0 for move 0x5B to family 15, 0xA4 to 11, 0x90 to 13 and 0xFB to 22.

- Dig: 84115E28, once 84113430 allows it, runs 84115D4C (unless +0x7EC
  bit 0: shot 0x0E, kind 0xFF), then program 6 unless the shot is 0x21.
  Program 6 = 84110640 (84120D34: both actors home and shown, 84120700, the
  up vector, the digger hidden at height 30 unless it is Diglett/Dugtrio,
  jolt 0; then 8410CC90; slot emptied) and 841111B0 (FOV 45, 8410E73C).
- Substitute: Dispatch_079 takes 841119CC(D_841849B6[0xA4 * 8]) (selector
  0 in the US ROM) and program 0 whatever the shot. 8411B3B8 reaches
  substate 2 at frame 0x1E, so on the 31st tick: 84112B64 swaps the actor to
  the doll (+0x658 = 0xFC; camera record row 0xFC and offset row reloaded),
  then its home pose, shot 0, program 0, +0x7EA = 0. The controller keeps
  the doll's records until the scene shows no doll; Stadium's own swap back
  is in a family not ported yet.
- Transform: 8411B070 runs 8411AF6C (unless +0x7EC bit 0: shot 0, kind
  0xFF), then the move's selector and program 0. Beat Up: Dispatch_156, once
  the model is ready, takes the move's selector and program 0.
- Not ported: Transform's 8411B160 (FOV goal 60 on shot 4 at the dispatch
  row's frame +0x619), 8411AEA8 (shot 0 and program 0 once the new model is
  loaded) and the kind reset at frame 0x28; Beat Up's 84116808 per-hit
  substates (841166C4). They wait on model-animation completion or on
  per-species animation rows (+0x2D4) that the host does not expose.

Checked against the ROM in the VM: 84115E28, Dispatch_079 and 8411B3B8
substate 2 in 300 cases, 8411B070 and Dispatch_156 in 200, program 6 in the
runner (Diglett and Dugtrio added to the scenario species). Mutation checks
fail the test (Substitute's selector is 0 in the ROM, so the check uses
another selector). Not visually confirmed.

### Charge turns (families 6, 7, 8) (2026-09-30)

Decomp: fork `15201a6` (C for Dispatch_043/045/050/059, 841155B0,
84115940, 841157D8, 8410E878, 84120A50); US asm for 841155E8, 841156D0,
84115A64, 84115B34, 84115FAC, 84116010, 84116138, 84116248, 8410D088,
8410CD3C, 841110EC, 84111170, 84110558. 8412C47C queues the charge code
right after its text and stores the move in record +8 (84134DD8); it queues
no move event that turn.

- Fly (0x1A, family 6): 841155E8 runs 841155B0 (unless +0x7EC bit 0: kind
  3), then unless the shot is 0x21, shot 0 and program 3. Dispatch_045's
  841156D0 waits until the model is 200 above its home height (+0x28 -
  +0x650), resets the kind and moves on; 841157D8 then takes shot 8 and
  program 15 at its frame 1. Wired later: the host's Fly departure having
  finished (restCondition `flying`) stands in for the height check.
  flyHighShot and program 15 are ported and ROM-checked.
- Dig's first turn (0x1B, family 7): 84115A64 runs 84115940 (unless bit 0:
  shot 0x10, kind 5), then unless the shot is 0x21, shot 0 and program 0.
  84115B34 moves to substate 1 at frame 0x19, then takes shot 0x10 and
  program 2 (the controller's 26th tick). Its substate 3 (kind reset and the
  facing at frame 0x1E) follows the model animation and is not ported.
- 0x16-0x19 (family 8; Razor Wind, Solar Beam, Skull Bash, Sky Attack):
  84116138 runs 84116010 (unless bit 0: 841119CC with D_84185196 /
  D_8418519E / D_841851A6 / D_841851AE, which are 0x2C, 0x2C, 0x28, 0x2C in
  the US ROM; kind 0xFF), then program 0 unless the shot is 0x21.
  84116248's follow-up (FOV goal 60 on shot 4, jolt 0, a jolt of 45 for
  move 0x59, the kind reset) waits on the dispatch row's frame (+0x619) and
  the model animation; not ported.
- Program 2: 841110EC (84120BB4, 8410C934, the actor's home pose and
  shown, slot emptied) and 84111170 (FOV 45, 8410D088 pulling the target
  toward the marker point, 8410E878 the sideways secondary pose). Program
  15: 84110558 (84120A50, then 8410CD3C: the shot around the marker point
  with FOV 45; slot emptied).

Checked against the ROM in the VM: 400 cases over the five states, and
programs 2 and 15 in the runner. Mutation checks fail the test (the 0x16 /
0x17 selectors are equal in the ROM, so the check uses 0x18's). Triggers:
Gen 1 BattleState's CHARGE_TEXT lines, Gen 2's Effects.lua charge texts and
Battle.lua's Dig line, matched exactly. The host's attack camera fires on
"used ..." first; the charge line then replaces it (a new family), as
Stadium has no move event on the charge turn. Not visually confirmed.

### Confusion self-hit (16), Substitute faded (21), dragged out (25) (2026-09-30)

Decomp: fork `15201a6` (C for Dispatch_113/114/148/149/163/164/177,
841168A0, 84116A3C, 8411B75C); US asm for 84116AC4, 8411B5A8, 84112C98,
8411A964, 8411B898.

- Self-hit (event 1): Dispatch_114, once 84113430 allows it, runs 841168A0
  (unless +0x7EC bit 0: shot D_84183BDC[8003570C % 6], kind 0xFF), then
  program 0. 84116AC4's kind reset (84116A3C) is animation-timed, not ported.
  Neither engine names the battler on "It hurt itself in its confusion!";
  both print it right after that battler's "is confused!" (as Stadium
  queues 0x26 then 1), so the hosts use that line's side.
- Substitute faded (0x27): Dispatch_148 makes sure the actor is the doll
  (84112B64), Dispatch_149 takes shot 0 and program 0. 8411B5A8 reaches
  substate 2 at frame 0x1E (counted from Dispatch_148's zero), then runs
  84112C98 (the swap back: +0x658 = +0x65C, 84113014, 84112704, the home
  pose, +0x7EA = 0) and shot 0 / program 0 again: the controller's 31st
  tick. This replaces the earlier host-driven doll restore. Triggered by
  "SUBSTITUTE broke!" (Gen 1 `_SubstituteBrokeText`, Gen 2) on the doll's
  owner; which battler 84124A14 queues 0x27 for is not re-checked here.
- Dragged out (0x2D-0x2F; 0x2F follows text 0x45 "was dragged out!"):
  8411B75C reloads the model, Dispatch_177 waits for it (800427B8, assumed
  ready at once); 8411B898 substate 1 takes shot 0 / program 0 unless the
  shot is 0x21 (next tick), substate 2 ends at its frame 5, substate 3
  resets the kind at its frame 0x3C (66th tick; 0x2F clears +0x7F4 bit 0,
  0x2E bit 1). Gen 2 emits "was dragged out!" as a send event; the host now
  routes it here instead of the send-out camera. 0x2D / 0x2E's moments
  are not identified.
- 0x28 (family 23): its only camera effect is Dispatch_164's kind reset at
  frame 4 after the model is ready. Correction (2026-10-01, US asm for
  84128664 / 8412A454, fork C for 84128B4C): it is Beat Up's end, not
  Destiny Bond's. All three sites queue it only when the move (D_841951BF)
  is 0xFB: 84128664 after a miss, 8412A454 when the multi-hit counter
  (+0x12, substatus +0xF bit 2) reaches 0, and 84128B4C when the target
  faints (after, and independent of, its Destiny Bond text 0x83). The kind
  reset has no visible effect (the next event's state sets the kind), so it
  is not wired.

Checked against the ROM in the VM: Dispatch_114 in 120 cases (the seed
compared), Dispatch_149 / 8411B5A8 / 8411B898 in 240. Mutation checks fail
the test. Not visually confirmed.

### The opening send-out and the split-screen intro (families 24, 34, 12) (2026-09-30)

Decomp: fork `15201a6` (C for 84124CC4, 8411FC94, 841347A0, Dispatch_169
/ 239, 8410AE50, 8410B08C, 8410B1CC, 841113F8); US asm for 84133714,
84113590, 8411C310, 8411C418, 8411CC2C, 8411CD38.

- 84133714 sends a Pokemon in: it queues the event, then prints the
  send-out line chosen by the foe's HP ratio (text 0x16 "Go! #26!", 0x12 "Do
  it, #26!", 0x10 "Go for it, #26!", 0x27 "Your foe's weak! Get'm, #26!").
  84124CC4 picks the code by the mon's status (asleep / frozen / other):
  0x23 / 0x24 / 0x21, or 0x2A / 0x2B / 0x29 and 0x39 / 0x3A / 0x38 for its
  two flag variants (callers 841339D0 and 84133B14). All of these go to
  family 12, the send-out family already ported.
- While D_841951F0 + 0x9C7 is set it queues 0x22 instead. 841347A0 (the
  battle loop) runs the opening send-outs (8413425C) and then clears
  0x9C7, so 0x22 is the battle's opening. 8411FC94 gives battler 0's actor
  family 34 when D_841911F9 == 5, else family 24. D_841911F9 is the arena
  index 84113590 stores (it loads that arena's data from D_84183A90).
- Families 24 / 34 (8411C310 / 8411CC2C, 8411C418 / 8411CD38) are a
  split-screen intro. Each controller has a viewport rectangle at
  +0x9A..+0xA0 (8410AE50; 8410B08C applies both). Controller 0 films the
  player's actor (program 0x1A, 8410C544) and controller 1 the foe's
  (841113F8 loads a program on controller 1: 0x16, later 0x1A); the edge
  slides 30 px a frame (800372CC) across the 320-px screen, then 8410B1CC
  drops the second view. Later substates run 8411C1D4 / 8411C7B8 (not read
  yet) and wait on model animations. Family 34 also reloads arena 4's data.
- The mod renders one camera. Porting this needs a second view in the
  renderer (two cameras, two viewports), which is a rendering change, not
  only a camera port. Not started.

### The arena intro, ported (family 26) and the two-view renderer (2026-09-30)

Decomp: fork `15201a6` (C for 8411C8A0, Dispatch_184, 8411C9DC, 8410AF1C,
8410B08C, 8410B224, 8410B104, 8410C304, 8411C7B8, 84111248,
GeoCamera_SetViewport 80038D0C, GeoCamera_SetPerspective 80038DC8,
Math_StepToS32 800372CC); US asm for 8410AE8C, 8410BDA0, 8410C400,
84113590, 8411D65C, 80038E14.

- GeoCamera (0xF0 bytes): graph-node flags +1 (bit 0x10 = the view is
  drawn), viewport x / y / w / h +0x1C..+0x22, projection fovy / aspect /
  near / far / scale +0x2C..+0x3C, ortho l / r / b / t / n / f / scale
  +0x44..+0x5C, eye / at / up +0xA8 / +0xB4 / +0xC0. The views are
  D_84190428 and D_841910E0 (84111868 hands them to the camera tick); the
  controller now uses those addresses for GC0 / GC1.
- 8411D65C picks the path D_841911F9: 8003570C % 5 in the plain modes, 5
  in some game modes (and 0x14 / 0x19 adjust 0 / 3 to 1 in 84113590). The
  host has no Stadium game mode, so the controller takes the plain branch
  (a random path 0-4). Assumption, recorded here.
- 84113590 copies the path's curves (1800 bytes for paths 0-4, 2504 for 5)
  from archive 0x49B780 + D_84183A90[path] into D_84190520. 8410BDA0 steps
  six clamped counters through them (see the channel table in the code).
- The controller runs 8411C8A0's camera part at battle start (event 0x65)
  and 8411C9DC once per tick from frame 1 (Dispatch_184 zeroes the counter
  a tick after the setup). If the host's first send-out comes before frame
  0xA0, the split is closed at once with 8410B104: a host-timing fallback,
  not a ROM path (Stadium's engine waits for the intro).
- Renderer: `StadiumCamera:views()` returns each drawn view with its
  controller rectangle; `Camera.sceneFrame` gives a view its rectangle's
  aspect and a clip-space remap into that rectangle (the 320 x 240 layout
  stretched to the canvas, as the full view is); `Scene:render` draws one
  pass per view, scissored (LOVE's clear respects the scissor; checked),
  with visitors, the HUD box and UI anchors from the first view only.

Checked against the ROM in the VM: all six paths, 166 frames each of
8411C9DC plus the camera tick, every byte of both controllers and both
GeoCameras (viewport, projection, ortho, eye, target, up, draw flags) and
the loaded curves. Mutation checks (the up vector's signed zero, the aspect,
a path channel, the blend's pitch goal, the split's step) fail the test.
Not yet seen in the game.

### The opening send-out, ported (family 24) (2026-09-30)

Decomp: fork `15201a6` (C for Dispatch_169, 84111C1C, 8411EE74, 8411EF20,
8410B1CC, 8411F90C, Dispatch_064, Dispatch_120); US asm for 8411C310,
8411C418 (jtbl_841893AC: substates 1-5), 8411C1D4, 8410F6AC / 8410F724
(program 21), 8410F78C / 8410F844 (program 22), 84111774, 8413543C,
84136CA8.

- 8411C310: +0x7EA = 0 on both actors, program 26 on the player
  (controller 0, shot 0), 8410C544 on controller 1 for the foe, the player
  shown, the foe hidden. 8411C418: (1) once the player's model animation
  ends (8003EC34), controller 0 full screen, controller 1 a zero-width
  rectangle at x = 320, program 21 (pan the target around the eye toward
  yaw -0x8000) on the player, program 22 (the same from +0x5555 toward
  0x4000) on controller 1; (2) controller 1's width steps 30 a frame to 320
  as its left edge slides in; at 320, 8410B1CC leaves controller 1 as the only
  drawn view on 8410C544's foe shot; (3 / 4) 8411C1D4 (8410C720 with (50,
  70, 0, 0), then (75, 30, 0.5, 0x1C71) from frame 5) for 0x28 frames, then
  program 26 for the foe on both controllers; (5) once the foe's animation
  ends, done.
- The first view returns with 8410B104, whose callers are 8411F90C (codes
  0x5C-0x64 and 0x68 / 0x69: 8413543C's idle records while the command menu
  waits), Dispatch_064 (family 9) and Dispatch_120 (family 17). The
  controller calls it at the host's turn start (the idle record's part;
  family 31, the idle camera 84113E7C, is not ported) and in families 9 and
  17. 84136CA8 moves to the next of 30 presentation records.
- Host mapping: the opening runs from the player's first send-out; the
  foe's send-out before it keeps the arena intro (family 24 films both).
  8003EC34 is the host actor's entrance clip having ended (the same Stadium
  clip 8411C310 starts, 0xFC). A player event before the opening ends cuts it
  with 8410B104 (host-timing fallback).
- Open question: 8413425C calls 84133714 for both battlers, so 0x22 is
  queued twice; whether the second record replays family 24 is not settled
  from the code. The controller runs it once.

Checked against the ROM in the VM: 10 openings with random animation-end
frames for both actors, every byte of both controllers and GeoCameras each
frame. Mutation checks (the wipe's edge, program 22's tick and setup, the
foe step's turn frame, the view hand-over) fail the test. Not yet seen in
the game.

### The idle camera, ported (family 31) (2026-09-30)

Decomp: fork `15201a6` (C for 8413543C, 84135808, 8411F794 / F7E0 / F82C /
F878 / F8C4, 8411FEE8, 8411FEFC, 84120E14, Dispatch_008 / 009, 84134A10);
US asm for 84113D7C, 84113E7C (jtbl_84188FF0), 84113658, 8410FC28 /
8410FD54 (program 4), 8410FDEC / 8410FF0C (8), 8410FF6C / 84110098 (9),
841104E4 (12), 8411047C / 8410ED98 / 8410F0D0 (14), 84110118 (28),
84136D9C, 84137778.

- The event timer is the current record's +6 (8411FEE8 sets it, 8411FEFC,
  called from the animation loops, counts it down). 8413543C builds the next
  idle record (D_84199D80, its timer D_84199D86) when that timer is 0: step
  D_8419A006 0-11 picks (battler, code): 0x62 x2, 0x5C, 0x5D, 0x60, 0x61,
  0x60 / 0x61 for the foe, 0x5E, 0x64, 0x5F (0x63 when D_8419A007) x2; steps
  0 / 1 skip an asleep or frozen battler (status & 0x27); after 11 it goes to
  2. The step is 0 at the battle's start and after send-out records
  (84135808); D_8419A007 is set by 8413C820 (not identified) and stays 0.
- Each idle record goes through 8411FF1C (jolt 0, timer 100) and 8411F90C
  (8410B104, family 31). 84113E7C, by code: 0x5C / 0x68 / 0x69 program 4
  (timer 0x12C / 0x96), 0x5D program 8, 0x5E program 9 (0x12C), 0x5F a shot
  of D_84183C44 (7) with program 12 on shot 5 else 0 (0x2D, then family 1:
  timer 0x12C until the model animation ends or frame 0x78), 0x60 a shot of
  D_84183C54 (6) and program 0 (0x3D), 0x61 program 7 (0x3D), 0x62 program 14
  (0x64), 0x63 the species' shot row 0x27 (84113658, archive 0xE0A0) and
  program 12 (0x32), 0x64 program 28 (0x50). The skip checks end the timer.
- Programs 4 / 8 / 9: an arena orbit (pitch 0x222 / 0x1C70 / 0x9F4, the
  flag pitch -0x888 / none / -0x9F4, distance 500 / D_84188F90 /
  D_84188F94, around (0, 40, 0) or (0, 180, 0)), the yaw turning 0xE8 a
  frame; 4 keeps the eye at height 10 or more, 9 scales the eye's z by
  D_84188F98. Program 12: 84120960 and 8410C934. Program 14: 84120E14 (the
  actor hidden, the other shown) and 8410ED98's over-the-shoulder pose
  (FOV 35); its tick ends the timer once it is under 0x29 and the height has
  settled.
- Program 28 (0x64) takes its FOV, eye and target from the game-mode table
  D_84185258 by D_841910D8; the host has no Stadium game mode, so it is not
  ported: the handler is reported once and the camera holds that step's
  0x50 frames.
- When: 841347A0 chooses both commands (84134098) before it queues 0x5A,
  and the display loop (8413D37C, 841359D0) builds idle records whenever
  the idle timer is 0 and D_8418615C (841383B4's third argument, 0 in the
  loop) is clear, so the idle cycle plays while the battle waits for a
  command. The host's `battle.turn_started` fires after both sides have
  chosen (like 0x5A), so the controller asks the scene instead:
  `stadiumAwaitingCommand` is Gen 1's `battle.phase` "menu" / "moveSelect"
  and Gen 2's `screen.phase` "menu" / "moves". The cycle runs while that is
  true and the event timer is 0, and stops at the next battle event. The
  turn start still closes a split (host-timing fallback: the host can finish
  choosing before Stadium's opening would have ended). Family 1's end uses
  the ROM's frame-0x78 cap (the host does not play Stadium's idle
  animation).

Checked against the ROM in the VM: 84113E7C in 400 cases (the timer, shot
row 0x27 and the random draws compared) and programs 4, 8, 9, 12 and 14 in
the runner. Mutation checks fail the test. Not yet seen in the game.

### Animation-timed follow-ups, with host signals (2026-09-30)

The follow-ups that wait on Stadium's model animations are now ported and
triggered. The frame numbers they compare against come from the ROM: the
per-species motion record (the animation-dispatch archive, 0x1530 bytes at
the actor's +0x2D4) and 841146D4's row copy (+0x616..+0x661). The
controller keeps each species' compressed record and loads it with the
species. Host signals stand in for the checks the recomp has no data for:

| ROM check | Host signal |
| --- | --- |
| 8003EC34 (the model animation has ended) | the host actor's Stadium clip has ended (`actor.context` back to "idle") |
| 841156D0: Fly 200 above home | the host's Fly departure has finished (`restCondition(side).flying`) |
| 84115988: Dig sunk below -3 x +0x648 | the host's Dig departure has finished (`restCondition(side).underground`) |
| 800427B8 (Transform's new model is loaded) | the host actor shows another species than its own |

- Charge turns (0x16-0x19): 84116138 copies row 0xFF / 0x101 / 0x103 / 0x104
  (84116010), timer 0x258, the frame counter from +0x61B; Dispatch_059 /
  84116248 at frame +0x619 (FOV goal 60 on shot 4, jolt 0 or 45 for move
  0x59), then the kind reset at frame +0x61A. In the US ROM +0x61A is never
  0 for these rows and the charge selectors never give shot 4, so this
  follow-up is exact without any host signal.
- Fly: 841155E8 copies row 0x100 and sets the timer 0x258; 841156D0 ends the
  rise at 200 above home (+0x28 = home + 200, kind reset); 841157D8 takes
  shot 8 / program 15 at frame 1 and ends the timer at frame 0x1E.
- Dig's first turn: 84115B34 substates 0-3 (frame 0x19, shot 0x10 /
  program 2 and +0x7F4 bit 4, which 8410B974 reads for the camera height;
  sunk or, for Diglett / Dugtrio, the clip's end; the kind reset and side
  facing at frame 0x1E). The earlier port missed +0x7F4 bit 4; fixed.
- Transform: 8411B070 copies the row (8411AF6C), timer 500; 8411B1F4: frame
  +0x619 (FOV goal 60 on shot 4), the model swap (8411AE08 changes only the
  display model, +0x65C: the transformer keeps its own camera data, so the
  controller no longer reloads species data when the host shows the copy),
  shot 0 / program 0 once the new model is loaded, the kind reset at frame
  0x28.
- Beat Up: Dispatch_156 copies the row (84116410); 84116808: the record's
  move, timer 0x258, frame +0x619 (FOV / jolt), the kind reset at +0x61A.
- Confusion self-hit: Dispatch_114 copies row 0 and sets the timer 0x258;
  84116AC4 / 84116A3C reset the kind at frame +0x61A.
- Not done: the wake-up's tail (84119AB4 waits on 84111C8C, which reads the
  model's own animation data and D_84183A28) and family 1's idle clip (the
  host does not play Stadium's idle animation; the frame-0x78 cap stays).

Checked against the ROM in the VM with the actors' real motion records: 160
charge / Fly rounds, 60 each of Transform, Beat Up, Dig's first turn and
the self-hit, every camera byte, the timer, the frame counter and the row
copy each frame. Not yet seen in the game.

### The battle's end, ported (family 30) (2026-09-30)

Decomp: fork `15201a6` (C for 8411D388, 8413D2E4, 84112290); US asm for
84133C10, 8411D2E4, 8410F9FC / 8410FABC (program 24), 8413C6AC.

- After a faint, 84133C10 counts each side's remaining Pokemon (84126320):
  8413D2E4(0) when only the player has some (win), (1) when only the foe
  has (loss), (2) when neither (draw; mode D_841951C3 == 7 decides by the
  fainted battler instead). 8413D2E4 stores it (D_841951F0 + 0x9C6) and
  queues 0x67 on that battler (2 -> 0) while either active Pokemon has HP,
  else 0x69. 0x66 goes to family 29, whose states are empty.
- 8411D2E4: timer 0x154, the winner shown and the other hidden, +0x7EA = 0,
  program 24 (shot 0x23 for species 0x5F / 0xF9, else 0x22, FOV 70 easing
  back to 45, 8410E73C). 8411D388: once the eye is within 1.75 of the
  secondary pose around the target and the frame is 6 or more, program 7;
  50 frames later the timer ends.
- Host: `battle.ended` (the mod's main.lua) with result win / lose / draw;
  run, caught and fled have no Stadium event. Gen 1 finishes the battle scene
  at once, so the victory camera may not be seen there; Gen 2 defers its
  teardown.

Checked against the ROM in the VM: 20 victories, every byte of both
controllers and GeoCameras each frame and the timer; program 24 in the
runner. Mutation checks fail the test. Not yet seen in the game.

### The dispatcher's prologue, battle start and end codes (2026-09-30)

- 8411FF1C, for every event whose record has the new-event flag (+2,
  8411FE80 clears it), first ends the camera jolt (8410B578(0)) and restarts
  the event timer (8411FEE8(100)), then gives the family. The controller now
  does the jolt reset in newFamily, which every controller event calls.
- 8413E2EC (the battle's entry) calls 8413D37C, which queues 0x65 at the
  very start (unless D_8419A0A0 is set): the arena intro. 8411FF1C gives
  battler 0's actor family 33 in arena 5 (D_841911F9), else family 26.
  Family 26 (8411C8A0, fork C) sets up both controllers on their own actors
  (8410C304) and both actors hidden; 8411C9DC (fork C) runs 8411C7B8 on both
  every frame and, from frame 0x3C, grows controller 0's viewport height 4
  lines a frame to 240 while controller 1's shrinks: a horizontal split
  screen, ended by 8410B224 / 8410B104 (frame 0xA0). Ported later with the
  two-view renderer (see the opening send-out section).
- 0x5B is queued by 841343FC before the first mover's action (corrected
  2026-10-01, see "The first mover"); 0x66 goes to family
  29 and 0x67 to family 30; 8413D2E4 queues 0x67 when either side still has
  HP, else 0x69; 8413C820 queues 0x68; 0x64, 0x68 and 0x69 go to 8411FF74
  (like 0x5C-0x63). Not identified further yet.
- 0x25 (family 3) is never queued with a constant in fragment 79, and the
  three computed queue sites give 6, 0x4A-0x54 and 0x67-0x69: no queue site
  found.
- 0x37 (the recall of a fainted mon, 84124C10) goes to family 32, whose
  states (Dispatch_225 / 226, 8411A310, 8411EE74) make no camera change.

### Remaining event codes: where the engine queues them (2026-09-30)

From every 84134CBC call in fragment79_393CA0 (US asm) and the text queued
just before it (84135B00; message table at ROM 0x1D8CDA4). 8411FF1C's
targets are from jtbl_84189A80.

| Code | Queued in | Text before it | 8411FF1C target |
| --- | --- | --- | --- |
| 0x01 | 841268A0 | 0x5C "It hurt itself in its confusion!" | 8411FB60 (family 16) |
| 0x16-0x19 | 8412C47C | 0x51 whirlwind, 0xAA sunlight, 0x9E lowered its head, 0x37 glowing | 8411FAA8 |
| 0x1A | 8412C47C | 0x69 "flew up high!" | 8411FAD4 |
| 0x1B | 8412C47C | 0x24 "dug a hole!" | 8411FB00 |
| 0x27 | 84124A14 | 0x7B "SUBSTITUTE faded!" | 8411FE28 |
| 0x28 | 84128664, 84128B4C, 8412A454 | none of its own: Beat Up (0xFB) ended (see above) | 8411FC3C |
| 0x2D-0x2F | 8412A300 | 0x45 "was dragged out!" (0x2F) | 8411FD20 |
| 0x21, 0x23, 0x24, 0x29-0x2B, 0x38-0x3A | 84124CC4 | none | 8411FCF4 (0x29-0x2B, 0x38-0x3A via 84111C1C) |
| 0x22 | 84133714 | none | 8411FC94 |

Remaining camera states by family (event codes from 8411FF1C):

| Family | Events | State |
| --- | --- | --- |
| 23 | 0x28 | 8411A964, 8411AA3C, 8411AAE0 |
| 24 / 34 | 0x22 (battle opening, split screen) | 8411C310, 8411C418 / 8411CC2C, 8411CD38 |
| 3, 14, 26, 30, 31, 33 | 0x25, and others | various |

### The first mover: event 0x5B and program 18 (2026-10-01)

Decomp: michiiik/pokestadiumgs `1b6dc17` (origin/master; C for 8411F9D8,
84112564, Dispatch_190 / Dispatch_002, 841136E8, 841137F8, 841139D0,
84135778, 84135700, 8413573C); US asm (pret `c0e10f2`) for 841343FC,
841347A0, 841320E8, 841358B0, 8410F1A8, 8410F3E8.

- Correction: 0x5B is not the end of the turn. 841347A0 queues 0x5A, calls
  84136CA8, then the turn body 841343FC, then 84133440. 841343FC switches
  on 841320E8 (the turn order: a switch or item first, then Quick Claw
  (item 0x4A), priority and speed; cases 1-5) and queues 0x5B on the side
  acting first, before that side's action (84133F10(side)).
- Records play in order: 841358B0 copies the next queued record (0x280
  bytes) into D_84199D80 (= D_84195280 + 0x4B00), and 84135778 plays the
  next only while D_84195280 + 0x4B06 (the current record's +6 timer) and
  + 0x4B02 are 0. So 0x5B plays once 0x5A's orbit has released its timer.
- 8411F9D8 (family 27 on both actors): timer 0x12C, record +1 bit 0
  (84112564), controller 0's shot 0, program 18 on the side's actor.
  Family 27's states only play the idle animation and hide a Pokemon
  underground or without HP (841139D0): not the camera.
- Program 18 (row 8410F1A8, 8410F3E8, then empty): the setup picks shot
  0x26 when the side's record +0x10 is 0x20, else 0x24; the look point
  and target at the actor's turned +0x634 offset plus its position, at
  +0x638 height (the marker height while the side's flags have bit 1;
  30 when bit 2 or +0x7F4 & 0x10); FOV goal 80. The tick eases the FOV
  (0.02), the fraction +0x44, the target toward the look point and the eye
  toward the shot row's secondary pose (8410B884; distance x D_84188F8C and
  yaw 0x1555 on the facing's side while flag bit 1); within 1.75 it waits
  20 frames, then ends the timer and its slot.
- Checked against the ROM in the VM: 8411F9D8 and program 18 through the
  runner until the timer ends, 120 rounds, every controller / GeoCamera
  byte and the record's timer compared; four mutations (the yaw 0x1555, the
  height 30, the 20-frame wait, the 0x26 shot) each fail it.
- Host signal: the controller runs 0x5B once the event timer is 0 after the
  turn start, on `Scene:stadiumFirstMover()`; a newer camera event drops it,
  and so does the host reaching its command menu first. Gen 2's engine sets
  `battle.firstMover` right after `battle.turn_started`; Gen 1 keeps the
  order only in its queued actions, so the first `BattleState:executeAction`
  after the turn start names the side (a restorable patch in
  `gen1_battle.lua`). `battle.turn_ended` is not used: both engines emit it
  when the turn is computed, before it is shown.

### The hit's follow-up: family 4's third state (2026-10-01)

Decomp: michiiik/pokestadiumgs `1b6dc17` (C for 84116B40, 84116EB4,
841175D4, 84117648, 84117880, 84117A24, 84117C18, 84117CAC, 84118138,
841182E0, 8411845C, 8411854C, 8411862C, 84118704 / 84118754 / 84118794,
84111BEC, 8413D358, 84108940, BattleAnim_ModelDispatch_176); US asm (pret
`c0e10f2`) for 841170A0 (jtbl_84189054), 84116BC0, 841187E4
(jtbl_84189084), 84117744, 84117CEC, 84117DC4, 84117E94, 84117AA0.

- 84116BC0 first copies the defender's own motion row for the received
  move: +0x2D4 + (move - 1) * 0x14, bytes +7 (+0x619, the hit frame), +0xA
  (+0x61A, the state's length), +8 (+0x620), +0x10..+0x13 (+0x628 / +0x62A /
  +0x62C / +0x661), and the record's +0x13DA / +0x13DB (+0x61C / +0x61D).
- 841170A0 zeroes the frame counter and substate, then sets the length
  through 84116B40 by event code: 0x0A: 0x3C while the side's flags have
  bit 1 or 2, else 84116EB4: the hit animation's length (0xFE; model +0x44
  -> +0xA), at least 0x50, or 0x3C for results 2 and 5; 0x0C and 0x0E: the
  hit animation's length; 0x0B, 0x0D, 0x0F, 0x11-0x13, 0x15 and 0x3B: 0x3C;
  all other codes: 0x46. 84116B40 stores it as a byte, adds up to 40
  frames past +0x620 when the result has bit 0x10, starts the counter at
  +0x619 - 1 when +0x619 <= 0, sets the timer 0x258 and clears D_841911F8.
  A hit that is not the last of a multi-hit move (effects 0x1D / 0x4D by
  80062D20, or moves 0xFB / 0xA7, with record +0xB ~= +0xA) ends at 0x28.
  Then program 1 unless the shot is 0x21.
- 841187E4 runs while the substate is 0 and 841133EC is clear, by code:
  0x0A with side flag 4 or 2 (84117CEC / 84117DC4), 0x0C (8411862C), 0x0D
  (8411845C), 0x0E (84118138), 0x0F / 0x15 (8411854C), 0x11-0x13
  (84118704 / 84118754 / 84118794), 0x3B (841182E0), else 84117E94. Their
  camera parts: 84117744 (per-move lengths: Lock-On 0x78, Rollout 0x5A,
  Whirlwind / Roar 0x32, Spite 0x78; Foresight 0x50 with +0x619 = 0 and
  shot D_84183C6C[frame / 12] with program 1 every 12 frames below 0x25),
  84117880 (at +0x619 + 1 the jolt by result & 7: 2 -> 10, 0 -> 15,
  3 -> 20, 4 -> 25), 84117A24 (Lock-On at +0x619 + 2: 84120BB4, 8410C934,
  program 25) and 84117648 (841175D4: once the side's HP bar has nothing
  left to drain, D_8419521C[side * 24] == 0, the end moves to 0x32 frames
  later if sooner; at +0x61A: +0x7F4 bits 0-1 cleared unless the length is
  0xF, 84111BEC: counter 0, timer 0, kind reset; counter 0x12C, substate
  1). 84117CEC / 84117DC4 end at +0x61A with only the kind reset and the
  timer 0. 84117AA0 is sound only.
- Program 25 (8411100C, its slot never empties) sets the target to
  D_8418C958 row 0 (84108940). That table is written while particles are
  placed (8003C9B8 via 84102750 / 84104A00: a model attachment point), so
  the port asks `options.attachmentPoint(0)`; the game's controller does
  not supply it yet, so the step is reported once and skipped.
- Checked against the ROM in the VM: 841170A0 and 841187E4 frame by frame
  with the camera runner, 420 rounds over every code, the special moves,
  results with bit 0x10, the HP bar settling at a random frame and fixed
  boundary rounds; every controller / GeoCamera byte, the row bytes, the
  counter, substate, +0x7F4 bits 0-1 and the timer compared. Eight
  mutations: six fail it, and `over < 41` is equivalent (it adds 0).
- Host signals (controller `startHit`): the hosts call the hit camera at
  the FX impact, which is the defender's frame +0x619 (84117CAC plays the
  hit FX 841087B8 there). The counter starts one frame before it so program
  1's setup (84120BB4 ends any jolt) runs first, as in the ROM, where it
  runs at the state's first tick. A dodge starts at frame 0. Record +9 is
  the FX adapter's result byte for the move (`Scene:stadiumHitResult`);
  unknown, the jolt is skipped and reported. The hit animation's length is
  the defender's "hit" clip (`Scene:stadiumClipFrames`); unknown, the end
  is not scheduled and reported. The HP bar (`Scene:stadiumHpSettled`):
  Gen 1's battler `shownHP` equal to its HP with no drain running; Gen 2's
  screen `shownHp[side]` equal to the battler's HP and no `hpAnim` on that
  side (Gen 2 resolves the whole turn first, so a later drain in the same
  turn keeps it unsettled and the row's end stands). The hosts present one
  impact per move, so the multi-hit index is not supplied (+0xA = +0xB).

Host trigger without MOVE EFFECTS (2026-10-01): the hit camera was reached
only through the FX adapter's `onImpact`, so with MOVE EFFECTS (BETA) off
(the default) no hit state ran at all. `Scene:stadiumHostImpact(side)` now
starts it at the host's own impact while there is no FX adapter: Gen 1's
`applyHitFx` blink and Gen 2's direct "damage" event (where the defender's
hit clip already plays then), for the move the other side last presented.
The result byte then comes from the static `Adapter.takeHitResult` (the
facts `main.lua` records from `battle.damage_dealt`, which nothing else
takes while FX is off). A dodge sets result 1 itself (a miss keeps 1:
841246AC, 84128298 / 84130E04). Seen in a headless Gen 1 trainer battle in
an arena (arena 0, CAMERA STADIUM, MOVE EFFECTS off): events 0x65, 0x22,
0x5A, 0x5B, 0 and 0x0A in order, the jolt of 15 on the tick after each
impact, the hit state ending with the timer 0, and no camera warnings.

### The wake-up's tail, Lock-On's aim point, multi-hit lengths (2026-10-01)

Decomp: US asm (pret `c0e10f2`) for 84119908, 84119AB4, 84111C8C,
84111FA4; michiiik/pokestadiumgs `1b6dc17` C for 80062D20 (src/638E0.c).

- 84119908 also zeroes the counter and substate and sets the timer 0x258;
  with side flag bit 2 it clears +0x7F4 bits 0 and 6, takes substate 4 and
  sets record +1 bits 0 and 2 (the port's `wakeState` now does all of it).
- 84119AB4 (the tail): 0: at frame 0x14 +0x7F4 loses bits 0 and 6 (1);
  1: once the wake animation has finished (8003EC34 when 84111C8C picks a
  wake clip: model +0xC -> +0x2C's byte +5 >= 1 or the species in
  D_84183A28; else 84111FA4: model +0x58 clear or 8003EFBC), frame 0 and
  record +1 bits 0 and 2 (2); 2: at frame 0x1E, 84111BEC (3); 4: at frame
  0x3C, 84111BEC (5). Host signal: the actor's clip has ended. Checked in
  the VM over 160 rounds (substates, counter, +0x7F4, record +1 and +6,
  camera bytes); four mutations fail it.
- Lock-On (program 25): D_8418C958 is the battle FX player's dynamic
  anchor table (its port of 84102750, `Player:dynamicAnchor`), so the
  camera reads row 0 from it; with MOVE EFFECTS off there is none and the
  target is held (reported once).
- 80062D20 is D_8009782A[move * 6] (main segment, ROM data: Fury Attack
  0x1D, Twineedle 0x4D, Double Kick 0x2C, Triple Kick 0x68, Beat Up 0x9A),
  read from the ROM image. A non-final hit of a move with effect 0x1D /
  0x4D or move 0xFB / 0xA7 ends at 0x28 (Double Kick's 0x2C is not in the
  list). Checked in the VM with 80062D20 running on the ROM table; four
  mutations fail it. Host signal (`Scene:stadiumMoreHits`): Gen 2 with
  MOVE EFFECTS off, another damage event on that side before the next move
  event in the screen queue (Gold emits one per hit). Gen 1 and MOVE
  EFFECTS on (one impact per move) count every hit as the last.

### The second opening record (2026-10-01, still open)

8413425C sets D_841951F0 + 0x9C7, then sends out both battlers
(84133714(0), 84133714(1)); each queues 0x22 while the flag is set, and
841347A0 clears it when the turn loop starts. 8411FC94 ignores the record's
side and gives battler 0's actor family 24 (34 in arena 5) both times, and
the family's states (Dispatch_169, 8411C310, 8411C418) run from the start
when reloaded. The records play when the current one's timer is 0: the
wipe's end sets the timer 0 (8411C65C) and substate 3 sets 0x320 one frame
later (8411C67C), so the second record could only start in that gap, and
whether it does depends on the display loop's other gates (84135700:
D_84195280 + 0x4B36 / + 0x4B4E; 8413573C), which are text and UI state
the port does not model. The port plays the opening once. Running the
opening in the emulator would settle it.

### The busy gates 84113430 / 841133EC (2026-10-01, resolved below)

Fork `1b6dc17` C: 841133EC returns D_84193DDC & 0xD0; 84113430 calls
84113400 (8003F904 on D_84193DD8, then D_84193DDC & 0xC0) and, when that is
0, 8410373C(D_84193DD8) and 1. D_84193DD8 is a sequence object: 84103640 /
84103694 / 841036E8 start it with a move or entry ID (841035DC through the
asset table D_8418CA20 that BattleAnim_RegisterAssetTable fills, then
8003F84C / 8003F874), 84113560 with entry IDs such as 0x11C-0x11E, and
8003F904 steps it. So the gates wait for the previous sequence to finish,
most likely the move's own animation script. Nothing in the host matches
it, so the port keeps treating both gates as clear (the camera states run
at once).

### Trigger audit (2026-10-01)

Every controller event has a host caller. Fixed by this audit:

- Dragged out: 8412A300 (US asm) queues, after text 0x45, 0x2F when the
  incoming Pokemon is asleep (status & 7), 0x2E when frozen (& 0x20), else
  0x2D. Gen 2 always sent 0x2F (the asleep variant); it now picks by the
  incoming mon's status (`Scene:stadiumDragCode`, tested).
- Gen 1's trainer AI switch ("<trainer> withdrew <mon>!",
  `_AIBattleWithdrawText`) had no recall trigger; it now recalls the foe,
  with the outgoing mon's sleep / freeze kept at the switch (the engine
  swaps battle.enemy before the text). Tested.

Known gaps left:

- Gen 2 player switch: the engine prints no withdraw line and has no
  retreat step before the new send-out, so Stadium's recall (family 18) has
  nothing to pair with and is not played for the player in Gen 2.
- Multi-hit per-hit lengths: Gen 2 with MOVE EFFECTS off only.
- The idle animation cap, the second opening record and the busy gates, as
  above.

### Resolved: the busy gates are asset loads (2026-10-01)

Fork `1b6dc17` C for 800421E0 and 8003F84C (src/229E0.c), US asm for
841035DC, 8003F874, 8003F904. 841035DC(id) copies the byte list at
D_84182A60[id * 8] (ended by 0x83; for example move 1: 01, entry 0x55:
52 81, 0x11C: 5C) into D_8418D240; 8003F84C / 8003F874 hand it to
800421E0, which posts a type-2 load request (osSendMesg on D_80126F00,
0x18000-byte buffer at +0x70: the PokeIcon loader's background-load slot)
and marks it pending; 8003F904 polls 80042808 and clears the pending bits.
So D_84193DD8 loads the move's effect resources from the cartridge, and
84113430 / 841133EC make the camera state wait until that load finishes.
The mod has every resource in memory before the battle, so the gates are
always clear: treating them as clear is the exact equivalent, not an
assumption.

### The second opening record: mechanism (2026-10-01)

US asm for 8411DA4C / 8411DAE0 (the per-frame battle-animation update:
8411FF1C, the actor states 8411DA2C, then 8411FEFC), 8410AA18 / 8413E2EC
(D_84193DD0 = D_84199D80), 84136D9C, 8413677C, 84137778, 8413573C.

- D_84193DD0, where 8411FEE8 writes the event timer, is D_84199D80, the
  record 841358B0 copies each queued record into; so the timer is the
  record gate's +0x4B06 field.
- The other gates: +0x36 / +0x4E are the record's per-side HP-bar
  animation frames (8413677C, side blocks of 0x18 from +0x2C; counted down
  by 84136D9C through 84134A10); 8413573C waits for the text box
  (D_8419A004 / D_84199FFC, 84137778). The text system also paces its text
  on the same timer (84134A10(D_84199D86, ...)).
- 84133714 commits each send-out as its own record (84136CA8), so the two
  0x22 records are separate; nothing in 8411FF1C, 8411FC94, Dispatch_169,
  8411C310 or 8411C418 skips a repeated 0x22.
- Each frame the update dispatches a newly loaded record before the actor
  states run, so a record loaded while the timer is 0 replaces family 24
  before 8411C418 raises the timer again. The timer is 0 at the wipe's end
  (8411C65C, one frame) and at the opening's end (8411C784).
- So by the code, the second record restarts family 24 on the player at
  the first of those moments when that record's text and HP-bar gates are
  also clear. Which moment it is (and so what the second run shows) depends
  on the text box's timing against the timer, which only running the
  record loop, text system and actor states together settles; all of it is
  fragment-79 code the MIPS VM can run.

### The second opening record: run in the VM (2026-10-01)

`tools/opening_records_harness.lua` (run from the gen1recomp root) runs the
battle's per-frame order from 8413D37C in the MIPS VM: 8411DA4C (8411FF1C,
the actor states, 8411FEFC), the record loop 841359D0, the text system
84137778 and the HP bars 84136D9C, after building both send-out records
the way 8413425C does (84136A9C mode 4, 84134CBC(side, 0x22),
84135B00(0x16), 84136CA8). Real ROM code throughout except: model
animations (84112158 / 8003EC34, the entrance length is an input), sounds,
the message strings (8004C874 / 800472E0 give only the line count, which
sets the record's text time 0x1E + 10 * lines in 84135A2C), 8004C8A0 and
84134994 ("MVED").

Result, the same for player entrances of 20, 45 and 90 frames: the wipe's
end (8411C418 substate 2 -> 3) sets the timer 0, the record loop loads the
foe's 0x22 record in the same frame (the text gate stays open: the
records' text is started by the states' 84112564 / 84112580, which run
later in the opening), and the next frame's 8411FF1C restarts family 24 on
the player. The first run never reaches the foe's close-up; the second
runs through substates 1-6 (the player's entrance again, the wipe again,
the foe's close-up and entrance). 8411C310 does not reset the views, so
the foe's view would stay on screen until substate 1 of the second run
resets the rectangles. This matches ROM execution with the stubs above; it
is not visually confirmed. Correction (same day): the text-box gate never
engaged in the harness although the game shows text there, so the harness
did not run the text system as the game does; the replay result is
unreliable and a double opening would look like a glitch. The port keeps
the single opening. Details and what would settle it:
`opening-replay-port-plan-2026-10-01.md`.

### The attack state's length: the camera stays on the attacker (2026-10-01)

User report: the camera cut to the defender's hit before the attacker's
animation and effects had played. Cause: the port started the hit camera
when the host reported the impact; in Stadium the defender's hit record
cannot play before the attack record's event timer is 0 (84135778).

US asm for 84114804 (its tail 841146D4(actor, move - 1)), 841154F8,
84114BF4; fork C for 84114A04.

- 84114804 ends by copying the attacker's motion row for the move
  (841146D4): +0x619 (hit frame), +0x61A (length), +0x61B and the rest. The
  port had left the copy out as "not camera"; it now does it.
- 84114A04, after the program: Fly's +0x7F4 bit 3; the counter 0, or the
  hit frame when it is negative; substate 0; +0x61A and +0x619 less +0x61B;
  the timer 600.
- 841154F8 runs 84114BF4 (841153DC for Rest, 0x9C) while the substate is 0
  and 841133EC is clear. Camera parts: the frame after the hit frame, on
  shot 4, FOV goal 60; at the hit frame the jolt stops, then Earthquake /
  Fissure jolt 45 and Magnitude / Flail / Frustration / Return jolt 55; the
  end at frame +0x61A, or when the animation finishes (8003EC34) if +0x61A
  is 0: +0x7F4 loses bits 0 and 3, substate 4, 84111BEC (the timer 0).
- Checked against the ROM in the VM: 84114A04 + 841154F8 frame by frame
  with the real motion records, 300 rounds (every fifth with length 0);
  five mutations fail it. Lengths with the real rows: median about 80
  frames, 23 to about 210.
- Controller: `attack` runs `attackFrame` each tick (the host's clip end is
  8003EC34); a hit or dodge on the other side reported meanwhile is held
  (`holdHit`) and played when the attack ends, starting with its state at
  frame 0 (as the record does), instead of lined up with the host's impact.
  Any other camera event drops the wait. The host still plays the
  defender's hit clip and the HP drain at its own impact, which can fall
  inside the attacker's shot; that is host timing, not the camera.


## The record gate: hosts wait for Stadium's current record (2026-10-01)

Source: 84135778 (US asm, pret `c0e10f2`), the record loop described in
opening-replay-port-plan-2026-10-01.md: the next queued record is copied in
only when the current one's timer (+6) is 0, its new-event flag (+2) is 0,
the HP-bar frames are 0 and the text gate is clear.

Port (`StadiumCamera:busy`, `Scene:stadiumPresentationBusy`):
- busy while the record timer is above 0 (every family that sets it clears
  it at its end), or a family the port tracks without a timer is still
  playing: the attack (`attacking`), the send-out (`sendingOut`), timed
  states (drag-out, substitute) and runs (hit follow-up, wake, ...).
- not busy for the idle cycle's timer (`idleTimer`; a new family resets the
  timer to 0, as a new record starts with its own), the battle's opening and
  arena intro (they wait on the hosts' send-outs themselves), the victory
  camera, or a pending first mover (its side is known only once the host
  runs that action; the 0x5A and first-mover timers cover the turn start).
- The state machine (the "director") now runs with either CAMERA option;
  only the camera pose needs STADIUM (`stadiumDirectorActive` versus
  `stadiumCameraActive`). Without the director, the attacker's clip stands
  in. Every hold ends after 8 s (`Scene.PRESENTATION_HOLD_LIMIT`).
- Gen 2 holds `BattleState:advanceQueue` and resumes it from Scene:update.
  Gen 1 holds `updateQueue` only before a new row; Red's HP drain and wait
  rows pass (a hit waits for its HP bar). The hosts' own HP bars and text
  gates stay theirs.
Matches the assembly's rule by reading; not visually confirmed.
