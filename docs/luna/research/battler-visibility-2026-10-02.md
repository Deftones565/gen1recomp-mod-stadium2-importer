# Battler visibility (2026-10-02)

Sources: US asm (pret `c0e10f2`) and fork C (michiiik/pokestadiumgs
`15201a6`), the supported US ROM (state table D_84183D50, program table
D_8418414C). "Matches the assembly by reading" unless a test is named;
nothing here is visually confirmed in game.

## The rule

A battler is drawn only while its display object's +1 bit 0 is set: the
graph walk 8003A2C8 skips every node whose +1 bit 0 is clear before calling
its type's draw (8003BCB4 for a display object). 8411EF08 sets the bit,
8411EE74 clears it, 8411EF2C(actor) sets it on `actor` and clears it on the
other battler.

So in every shot whose reset is 84120BB4 (the plain new-shot reset, used by
programs 0, 2 and others) the shot's battler is shown and the other one is
hidden; 84120CA4 / 84120AC4 / 84120D34 show both, 84120A50 shows both and
re-poses only the other, 84120C20 (program 11, the faint) shows the actor
and hides the other, 84120E14 shows the other and hides the actor.

## Port

With the camera director running, both hosts' `visualState` (wrapping the
renamed `hostVisualState`) take the battler's visibility from the camera's
+1 bit (`StadiumCamera:actorShown`); the host still decides an empty slot,
a trainer, and a fainting battler (its clip). Without the director the host
decides, with Stadium's own Fly / Dig visibility on top
(`Scene:nativeChargeVisibility`). Tests: camera controller (the override
for both hosts, the send-out), special moves (Fly / Dig).

Every writer of the bit in fragment 79 (every caller of 8411EF08 /
8411EE74 / 8411EF2C, US asm and fork C), and its port:

| Writer | What | Port |
|---|---|---|
| 84120BB4, 84120CA4, 84120AC4, 84120D34, 84120A50, 84120C20, 84120E14 | shot resets (above) | camera port; 8411EF2C now written (`StadiumCamera:statusVisibility`) |
| 84120700 | hidden: record flags bit 2 (not Diglett / Dugtrio), +0x7F4 bit 2, record HP 0 | `StadiumCamera:actorReset` |
| 84115988 | Dig sunk: hidden | camera port (digHoleFrame) with the actor's sink |
| 8411BB04, 8411BC28 (family 12) | send-out start: hidden | `StadiumCamera:sendOut` |
| 8411BCC8 (family 12) | shown once the state runs (84113430), alpha 0 | the send-out's first frame |
| 8411C310, 8411C418 (family 24) | the opening's split screen | camera port (openingSetup / openingFrame) |
| 8411C8A0 (family 26) | the arena intro hides both | camera port (arenaIntroSetup) |
| 8411D2E4 (family 30) | the winner shown | camera port (victoryState) |
| 841139D0 (idle, family 27) | hidden: record flags bit 2 (not Diglett / Dugtrio), record HP 0 | not ported as such: every ported show is followed in the same reset by 84120700 with the same tests, except 84120A50 (program 15: the Fly user, neither underground nor at 0 HP), the shows of the send-out, opening and victory (never underground or at 0 HP), and 84120C20 (program 11, the faint shot), which shows the fainting battler at HP 0; the idle state hides it once its faint ends, which the hosts already do (an empty slot after the faint clip) |
| 8411A620 (faint, family 5) | hidden at frame +0x61A + 0x19 only with +0x7EC bit 0 | +0x7EC bit 0 is set only by 841242D8 / 8411DAE0 (a mode switch, D_84193FA0 + 0x80), never in normal play: not reached |
| 8411A76C (Dispatch_226, family 32) | event 0x37 (a fainted Pokemon's recall): hidden | already hidden (record HP 0 in 84120700) |
| 841109FC / 84110A98 (ModelDispatch_113 / 141) | programs 16 / 20: shown on controller 0 | no selection of programs 16 or 20 found (literal program numbers in fragment 79); the camera port reports a missing handler if one loads |
| 84119F24 (family 17, code 7) | the other battler shown from frame 0x23 | the event is not produced by the port (see below) |
| 8411CC2C, 8411CD38 (family 34) | the opening in arena 5 | the port has no family 34 (see below) |

The record HP that 84120700 tests is 84134A6C's displayed HP (the battle
mon's HP less the bar's pending change, +0x38); the camera's record now
takes the hosts' shown HP bar (`Scene:stadiumRecordHp`) instead of the live
HP, so a knocked-out Pokemon is not hidden during its own last hit.

## Missing native events found

1. Codes 7 / 8 / 9 (84124BA0, family 17): after the first mover's action and
   its after-move damage (84133F10 -> 84131664, 84131AF8), when neither
   side has fainted, 841343FC queues 7 (8 when the second mover is asleep,
   9 when frozen) on the second mover before its action. Family 17's camera
   takes shot 0x24 / 0x25 (code 7, by the side's flying bit) or 0x24 / 0x26;
   84119F24 shows the other battler from frame 0x23 for code 7. The port
   queues none of these: the hosts would have to hold the second mover's
   first event behind this record.
   Ported (same day):
   - Turn body (841343FC, US asm), all five order cases: the side acting
     first (a switch / item first, else the turn order; case 5, both
     switching, picks at random, 84125080: the host's order stands) takes
     its whole action (84133ACC / 84133F10 with 84131664 and the after-move
     damage 84131AF8); 84133F10 returns 1 when either side's HP is 0, and
     then no handoff is queued (cases 1-4; case 5 always queues it).
   - Gold (gen2_battle.lua, restorable patches): `Battle:takeTurn` /
     `takeLinkTurn` open the turn (a player item makes the player first);
     the second side's action start (`switch`, `switchEnemy`,
     `enemyUseItem`, `canAct`) arms the handoff unless `resolveFaints` has
     reported a faint; `Battle:emit` puts it on that action's first event
     (`event.stadiumHandoff = {side, code}`, code 8 for "sleep", 9 for
     "freeze", else 7); the `advanceQueue` gate plays it
     (`Scene:stadiumHandoff`) and holds the event behind its record.
   - Red (gen1_battle.lua): `Scene:stadiumRoundAction`: a round opens at
     command selection; its first action (a move's `executeAction`, a
     switch, an item, a run, a ball, a scared turn) names the first side;
     the other side's `executeAction` gets the handoff when both battlers
     still stand ("SLP" 8, "FRZ" 9) and is deferred behind it (`actNext`,
     the `updateQueue` gate).
   - Family 17 (84119CF0, 84119F24): the record's timer 0x3E and length
     0x3C, codes 7-9 0x25 / 0x23; the state ends at the length (84111BEC:
     timer 0) and code 7 shows the other battler from frame 0x23. This also
     sets the existing turn-check events' length (2-6, 0x2C), which the port
     never set before (their record timer was whatever the previous record
     left).
   Tests: stadium2_turn_handoff_test (Gold's engine with the hooks),
   camera controller (family 17's timing, Gen 1's round). Not seen in
   game.
2. Family 34 (8411FC94: the opening goes to family 34 instead of 24 when
   D_841911F9 is 5). Resolved (same day): D_841911F9 is the intro path
   (84113590's argument), chosen by 8411D65C (US asm) from the game mode
   (8006A3E0: D_8009DF70 +0, high byte): 0x000 / 0x400 / others a random
   path 0-4 (8003570C % 5); 0x200 path 5 unless D_841910D8 is 0x17-0x1C;
   0x300 path 5 when D_841910D8 is 9-12 or 8006AC70 (D_8009DF70 +0x12) is
   0; 0x600 always 5. The modes are copied from setup data
   (8006A3B8's callers pass no constants), so which Stadium mode each
   value is was not traced. Our battles have no Stadium game mode;
   8006A3E0 without a setup returns 0xFFFF, whose high byte takes the
   default branch: a random path 0-4, which the port uses. Family 34 is
   therefore not reached. Mapping some host battles (for example gym
   battles) to a Stadium mode would be a user decision, not ROM
   behaviour.
