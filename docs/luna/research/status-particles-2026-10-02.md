# Status particles (2026-10-02)

Sources: US asm (pret `c0e10f2`) for 84108AF8, 84108CE8, 84108E00,
84108F88, 841054D4, 84101D54, 84107170, 84119AB4, 84119F24, 84118138,
841182E0, 8411862C; fork C (michiiik/pokestadiumgs `15201a6`) for 841136E8,
84112464, Dispatch_113 / 177. Matches the assembly by reading; ROM-backed
test stadium2_status_particles_test.lua; not seen in game.

## Native

- The sleep (entry 0x100, shape 0x12) and frozen (0xFE, shape 0x13D)
  visuals and Dig's failure dust (0x12D, shape 0xD3) are held particles
  (object flag 0x10000) whose material endpoint freezes their age (object
  flag 0x80, see timing-lifetimes T06): they stay until released.
- 84107170 maps descriptor bits to object flags: 0x10 -> 0x1, 0x400 ->
  0x40, 0x8 -> 0x200, 0x20000000 -> 0x10000, 0x4 -> 0x100, 0x100 -> 0x400,
  0x10000000 -> 0x20000, 0x08000000 -> 0x8000, 0x80000000 -> 0x40000,
  descriptor +8 bit 4 -> 0x80000. 841054D4 ages a particle only without
  0x80 (and counts down +0x81 for 0x800, then shows its renderer).
- The states that start a visual mark it on the actor (+0x7F4): 0x40
  asleep (841153DC Rest, 8411862C), 0x20 frozen (84118138, 841182E0), 0x10
  underground (Dig).
- 841136E8 (from 84113BE8 idle, 84113C54 first mover, 84113D38 turn-check
  3 / 5, Dispatch_113 self-hit, Dispatch_177 drag-in, 8411BC28 send-out)
  ends each marked visual whose condition left the record (flags bit 2,
  status 0x20, status & 7) with 84108AF8: the owner's held particles are
  released except shape 0x12 while asleep, 0x13D while frozen, 0xD3 while
  underground (release: flags 0x10080 cleared; with 0x8000 also ended and
  the renderer hidden).
- 84108CE8: every held particle of the owner but 0xD3 released: the
  wake-up (84119908 at its start, 84119AB4 substate 0 at frame 0x14, which
  also clears bits 0 and 0x40) and the defrost (84119F24 code 0x2C when not
  underground, at frame 0x23, clearing bits 1 and 0x20).
- 8411EE74 (any battler hide) hides its status shape (84108E00: mode 2
  0x12 via object flag 0x100000, mode 1 0x13D via the renderer bit) by the
  record status; 84120700 shows them again (84108F88, not on the doll 0xFC)
  and hides them again when the battler stays hidden.

## Port

Runtime: `releaseStatusEnded`, `releaseHeldButDust`, `hideStatusShape`,
`showStatusShape` (`particle.nativeStatusHidden`, skipped by the draw
packets); Player / Adapter pass-throughs; `Adapter.onStatusEntry` (entries
0x100 / 0xFE). Camera: `StadiumCamera:statusEntry` / `statusEnded` /
`statusShapesHidden`, `Native:hideActor` for every hide, the record status
byte (+0x10, `Scene:stadiumRecordStatus`: Gold's presented status byte;
Red's in Gold's layout), and the calls at the native states above.

## Starting the visuals (same day)

- 0x0C, fell asleep: the sleep effect 84128EC0 (US asm) writes the status,
  prints text 0xA7 and queues 84134CBC(target, 0x0C) (move +8; result 5 for
  Lovely Kiss, 0x8E). Family 4 runs 8411862C: no hit clip at the state's
  start; at its hit frame (84117CAC: the target's row byte 7) the move's
  impact, clip 0x105 (context 261), entry 0x100 on the target, +0x7F4 bit
  0x40.
- 0x0E, frozen: 8412955C prints text 0x41 and rewrites the previous record
  (84134D28: write index - 1, 84134A6C) to 0x0E. 84118138: the hit clip
  (0xFE) at counter 0, at the hit frame the impact and +0x7F4 bit 0x20, at
  frame 8 entry 0xFE (the ice), at frame 9 84108E00(1) when the record says
  flying or underground. (0x3B, 841182E0, the same without the impact.)
- 0x0F: 84129374 rewrites the hit on a frozen target to 0x0F (text 0x77);
  8411854C releases the held particles (84108A10) at its hit frame.
- The send-out of an asleep / frozen Pokemon (8411BCC8, US asm): after the
  camera part (substate 2, to frame 0x61), substate 3 zeroes the counter,
  4 moves on at counter 5, 5 signals 0x100 / 0xFE at counter 6 (0x10 for a
  shiny Pokemon, 8006456C) and ends at 0x50.
- Port: `Scene:stadiumDefenderStarted` asks the host
  (`Scene:stadiumHitInflicts`: Gold looks ahead in its queue to the next
  move for the target's sleep / freeze status event, since it resolves the
  turn first; Red compares the target's status with its value at the
  action's start, as Red applies a move's status while it runs; "Fire
  defrosted" is the thaw) and plays 0x0C (`Actor:fallAsleep`, entry 0x100
  at the hit frame) / 0x0E (entry 0xFE at 8, the check at 9) / 0x0F (the
  release at the hit frame). The camera's send-out tail signals the status
  visual (`StadiumCamera.sendOutTail`). Gold's engine has no fire thaw
  (no "defrosted" path), so 0x0F does not occur there.

## Releases (84108A10), same day

Wired: the faint (Dispatch_036 / 8411A544, at the state's start), the
victory (8411D2E4, the winner), the recall of an asleep / frozen Pokemon
(8411ABAC, codes 0x1F / 0x20), Beat Up's start (84116460), Dig's attack
(84115D98, frame 0x19; Diglett / Dugtrio at their clip's end), the
opening's end (8411C418, both battlers), Baton Pass by an asleep user
(84114BF4 at its hit frame), Whirlwind / Roar's target (84116F7C, as its
record starts, not on a dodge), the thaw (8411854C). Not wired: 8411A964
(family 23, event 0x28, Beat Up's end), which the port does not produce.
Tests: stadium2_status_particles_test (35 checks).
