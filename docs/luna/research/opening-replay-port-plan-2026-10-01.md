# Battle opening second record: findings (2026-10-01)

Status: **not ported, and the replay result below is unreliable.** The port
plays the battle opening (family 24, event 0x22) once, and should keep doing
so unless better evidence appears.

Why it is unreliable: in the VM harness the text-box gate (8413573C:
D_8419A004 / D_84199FFC, driven by 84137778) never engaged during the whole
opening, although the real game shows text there ("Go! <MON>!"). The
message strings were stubbed (only line counts), so the text system did not
run as in the game, and the gate that would hold the second record back was
never exercised. The resulting sequence (the whole opening playing twice)
would look like a glitch to a player, which also argues that the harness is
missing something. Solid: two 0x22 records are queued in a trainer battle,
and both are routed to the player's actor (8411FC94). Not solid: that the
second one restarts the opening.

To settle it: run the text system with real message data in the harness
(the message tables 8004C874 reads, the text layout 8004C8A0, and what sets
the record's +1 text bits early enough), or watch a trainer battle's opening
once in an emulator. If it is ever ported, the user wants it for trainer
battles only (wild battles keep the single opening).

Wording: "the wipe" below is the split-screen transition in the opening,
where the foe's view slides in from the right edge (controller 1's width
grows 30 px a frame) until it fills the screen; "the wipe's end" is the
frame it reaches full width.

Sources: pret/pokestadiumgs `c0e10f2` US asm (8413425C, 84133714,
84134CBC, 84136CA8, 84135A2C, 84135B00, 8413677C, 84136D9C, 84137778,
8413573C, 84135778, 84135700, 841358B0, 8411FF1C, 8411DA4C, 8411DAE0,
8411C310, 8411C418, 8410AA18, 8413E2EC, 8413D37C); michiiik/pokestadiumgs
`1b6dc17` C (8411FC94, Dispatch_169, 841347A0).

## What the ROM code shows (static reading)

1. 8413425C sets the battle-start flag D_841951F0 + 0x9C7, then for each
   battler calls 84136A9C(side, -1, level, 4) (the HP bar fill) and
   84133714(side). While the flag is set, 84133714 queues event 0x22 for
   that side (84134CBC), text 0x16 (84135B00) and commits the record
   (84136CA8). So a trainer battle queues **two** 0x22 records: side 0,
   then side 1. 841347A0 clears the flag when the turn loop starts.
2. 8411FC94 (the dispatcher's 0x22 handler) ignores the record's side:
   both records give **battler 0's actor (the player's)** family 24 (34 in
   arena 5).
3. Records play in order. 841358B0 copies the next queued record into
   D_84199D80, which is also D_84193DD0, the record whose +6 is the camera's
   event timer (8410AA18 stores it from 8413E2EC). 84135778 loads the next
   record only when: the current record's timer (+6) is 0, its new-event
   flag (+2) is 0, its HP-bar animation frames (+0x36 side 0, +0x4E side 1;
   8413677C writes them, 84136D9C counts them down) are 0, and the text gate
   8413573C is clear (D_8419A004 / D_84199FFC, from 84137778).
4. Per frame (8413D37C): 8410A608 -> 8411DBF4 -> 8411DA4C (8411FF1C
   dispatch, then the actor states, then 8411FEFC timer countdown), then the
   record loop 841359D0, then text 84137778, then HP bars 84136D9C. So a
   record loaded in frame N is dispatched at the start of frame N+1, before
   any actor state runs.
5. Family 24's timer writes: Dispatch_169 0x320; 8411C418 substate 2's
   end (the wipe reaching 320 px, 8411C65C) **0**; substate 3 0x320
   (8411C67C); substate 4 -> 5 0x320 (8411C73C); substate 5's end
   (8411C784) 0.
6. Result: the first run reaches the wipe's end, sets the timer 0, the
   record loop loads the side-1 0x22 record in that same frame, and the
   next frame's dispatch restarts family 24 on the player. The first run
   never runs substate 3 (no foe close-up, no foe entrance). The second run
   goes through substates 1-6 normally.
7. Nothing skips a repeated 0x22: 8411FF1C only checks the new-event flag,
   8411FC94 always reloads family 24, and Dispatch_169 / 8411C310 /
   8411C418 have no early exit. 8411C310 does **not** reset the view
   rectangles, so after the first wipe (8410B1CC left only the foe's view,
   controller 1, drawn) that view stays on screen through the second run's
   substate 1, until substate 1 finishes and sets controller 0 full screen
   and controller 1 to zero width again.
8. The text gate stays open at the wipe's end because the records' text is
   started by the actor states' 84112564 / 84112580 (record +1 bits), which
   family 24 only calls late (8411C734, substate 4 -> 5). The HP fill of
   the side-0 record is long done by then.

Visible sequence the harness predicts (unreliable, see the status above): the player's Pokemon's entrance on the
player's full view -> the wipe to the foe's view (0x124 throw signal at
width 30) -> the foe's view held while the player's entrance animation
plays **again** (8411C310 plays 0xFC on the player) -> cut to the player's
full view -> the wipe again (0x124 again) -> the foe's close-up
(8411C1D4, 0x28 frames) -> the foe's entrance (0xFC) -> end.

## VM check (text gate not exercised, see above)

`tools/opening_records_harness.lua` (run from the gen1recomp root with
`luajit`; env `PLAYER_ANIM`, `FOE_ANIM` (entrance frames), `LINES0`,
`LINES1` (text lines), `FRAMES`, `VERBOSE`, `STEPS`). Real ROM code for the
dispatcher, the actor states, the record ring and its gates, the text system
and the HP bars. Stubbed: model animation (84112158, 8003EC34 answers from
the entrance length), sounds, 841120AC, 84111C1C, 8410890C, 8006456C,
80023A3C, 80024480, 84108A10, 84108E00, draw calls 84147228, the message
system (8004C874 / 800472E0 give only a line count; the record's text time
is 0x1E + 10 * lines, 84135A2C), 8004C8A0, and 84134994 ("MVED"). The ring
and gate globals (D_84195280 .. 0x8419A010) are cleared first because the
fragment image is not zero there.

Output for entrances of 20, 45 and 90 frames: the wipe ends at frame
entrance + 13, the side-1 record loads that frame, the next frame the
player's substate is 1 again with the timer 799, and the second run ends at
substate 6.

## Porting plan, only if the replay is confirmed (controller: lib/stadium2_battle_camera.lua)

Current behaviour to know first:
- `StadiumCamera:sendOut` ignores the foe's send-out during `openingPhase`
  and starts the opening (`openingSendOut`) on the player's; with the arena
  intro running it defers it (`pendingOpening`).
- `openingSendOut` does 8411C310's camera part (`self.cam:openingSetup()`),
  sets `self.opening = { substate = 1 }`, clears `foeEntranceReleased`, and
  releases the player's held entrance (`releaseEntrance(scene, "player")`).
- `update` runs `self.cam:openingFrame(substate, playerReady, foeReady)`
  each tick; it signals 0x124 at width 30 in substate 2, releases the foe's
  entrance on 4 -> 5 and ends at 6.
- `holdEntrance("enemy")` holds the foe's entrance while
  `self.opening ~= nil and not self.foeEntranceReleased` (so it will keep
  holding through a second run if `foeEntranceReleased` is cleared).
- `newFamily` calls `cutIntro`, which clears the opening, calls
  `endSplit` and releases held entrances: **do not** route the replay
  through `newFamily` / `openingSendOut` as they are, because 8411C310
  does not reset the views.

Steps:
1. In `openingSendOut`, remember that a second record is due:
   `self.openingReplay = not self.wildBattle` (only on the first run; clear
   it when the replay starts so it happens once).
2. In `update`'s opening block, record the transition: if `before == 2`
   and `opening.substate == 3` and `self.openingReplay`, set
   `opening.restartNext = true` (the record loads this frame).
3. At the top of the opening block on the next tick, before
   `openingFrame`: if `opening.restartNext`, run the replay and skip
   `openingFrame` for this tick (the ROM's frame N+1 runs the dispatch and
   the new family's first states, not substate 3):
   - 8411FF1C's prologue: `self.cam:setJolt(0)`.
   - record: `m:setU16(RECORD + 4, 0x22)`, `m:setU8(RECORD + 0, 1)` (side 1).
   - Dispatch_169 / 8411C310: `m:setU16(ACTOR.player + 0x7E8, 0)`,
     `self.cam:openingSetup()`, `self.opening = { substate = 1 }`,
     `self.foeEntranceReleased = nil`, `self.openingReplay = nil`.
   - Do not call `endSplit` / `cutIntro`: the views stay as the wipe left
     them.
   - Replay the player's entrance on the host (8411C310's 84112158(player,
     0xFC)): see the host step below.
4. The timer: the port does not model family 24's timer writes (the idle
   cycle already waits on `self.opening`), so nothing to add there.
5. Host: add `Scene:stadiumReplayEntrance(side)` in lib/battle_scene.lua.
   `Scene:stadiumEntrance(side, start)` already receives each side's
   entrance start function; store it always (e.g.
   `self.stadiumEntranceStart[side] = start`) and have the replay call it
   again (Gen 1: `actor:play("entrance", false)`; Gen 2: `actor:entrance()`).
   The controller calls it through a small local like `releaseEntrance`:
   `scene.stadiumReplayEntrance(scene, "player")` under `pcall`.
6. The 0x124 throw signal fires again in the second run's substate 2 (the
   ROM's 8411C418 signals it each run); keep that, it is ROM behaviour.
7. Wild battles: `self.wildBattle` is true, so no replay.

Tests to add (targeted, per the user's rule):
- Controller test (tests/stadium2_battle_fx_camera_controller_test.lua):
  the existing opening block (`open` camera with `oscene`) is a trainer
  battle (no `stadiumWildBattle`), so after the first wipe it must now
  expect: the next tick substate 1 again, a call to
  `stadiumReplayEntrance("player")`, the views unchanged at that tick (only
  view 1 drawn), then the second wipe (0x124 signalled twice in total), the
  foe's entrance released at player frame 0x28 of the second run's
  substate 4, and the end at 6. Update its current expectations (the
  "foe's entrance released at 0x28", "the opening ended") accordingly.
- A wild-battle case: the same run with `stadiumWildBattle` returning true
  ends after one wipe.
- Optionally a VM oracle: `openingFrame` is already ROM-checked; the
  replay's order (dispatch before states, the record loading on the wipe's
  end frame) is what the harness above shows.

Docs to update when ported: battle-camera.md (the opening sections and
"The second opening record"), battle-camera-status-2026-09-30.md (open
questions), battle_FX_bugs.md (a user-facing entry), and say it is "matches
ROM execution, not visually confirmed".
