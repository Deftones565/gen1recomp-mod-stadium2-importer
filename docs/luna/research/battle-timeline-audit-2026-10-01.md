# Battle FX audit: timing, spawn positions, animations, camera needs (2026-10-01)

Sources: US asm (pret `c0e10f2`) for 84135778, 84112564, 84112580, 84114BF4,
84118138, 84137778, 84136D9C; fork C `1b6dc17` where noted; the supported US
ROM. Generated data: `tools/audit_battle_timeline.lua` (table:
battle-timeline-audit-2026-10-01-table.md) and `tools/audit_battle_fx.lua`
(full 251-move sweep, 150 ticks, both banks and sides). "Matches the
assembly by reading" unless a test is named; nothing here is visually
confirmed.

## 1. When the hit happens (the main finding)

Native chain for one move (30 Hz ticks):

1. Attack record (event 0, family 2, attacker). 84114A04 rebases the row;
   84114BF4 starts the body clip at row byte 6, plays the move bank at the
   hit frame (byte 0x0B), and ends the attack at byte 0x0A (or at the clip
   end when that is 0), clearing the record timer.
2. 84112564 (the "release" frame) only sets record +1 bit 0. Its readers
   are the text system (84137778) and the HP bars (84136D9C): it starts the
   record's text and HP bars. It does **not** load the next record.
3. 84135778 loads the next record (the defender's hit, event 0x0A) only
   when the timer (+6) is 0, the new-event flag (+2) is 0, the HP bars
   (84135700) and the text gate (8413573C) are clear. It is dispatched the
   next frame.
4. Defender (family 4): 84118138 plays its hit clip (context 254) at
   counter 0, and the impact bank (841087B8) at counter = its own row's
   byte 7.

So: native impact >= attack end + 1 + defender byte 7.

Port: `Sequence.attackTiming` treats 84112564 as "releases the next event
record" and schedules the impact at release + byte 7 from the move start
(`Adapter:playMoveAndImpact` -> `scheduleImpact`). That is early by
(attack end + 1 - release) for every move: median 60 ticks (2.0 s) across
the 251 moves; largest Dream Eater (121), smallest Selfdestruct (26). The
STADIUM camera (correctly) holds on the attacker until the attack end and
the hosts now wait for it (the record gate), so the impact effect plays on
the defender while the camera is still on the attacker, and the defender's
hit clip (started with the impact) plays off-camera too.

Fixed (same day, after v0.24.1): `Adapter:playMoveAndImpact` arms the
impact; the defender's hit record starts with the camera's hit state
(`StadiumCamera:hit`/`dodge` -> `Scene:stadiumDefenderStarted`, which the
STADIUM camera holds until the attack has ended), or at the host's hit
without the director (`Scene:stadiumDefenderHit`, Gen 1 applyHitFx / Gen 2
damage events, with or without battle FX). It plays the hit clip at the
state's start and `Adapter:defenderStarted` schedules the impact at the
defender's byte 7; each hit of a multi-hit move does this. A move the host
reports no hit for falls back to the native estimate (attack end + 1 +
byte 7, plus `Adapter.HIT_GRACE` = 6 ticks), which also plays the hit clip
through onImpact. `Sequence.attackTiming` now returns `attackEnd` and that
estimate as `impact`. Tests: attack_timing, sequence, defender_reaction,
move_record, gen1_battle_fx. Not seen in game yet.

Fix direction (original): start the impact bank and the defender's hit clip from the
defender's hit record, i.e. when the camera's hit state starts (the held
hit released at the attack end): hit clip at its counter 0, impact at its
counter = defender byte 7. The 84112564 "release" stays what it is: the
attack record's text/HP start. (Corrects sequencing-render-emission.md's
"84112564 releases the next event record" and its open latency note.)

## 2. Spawn positions

The full sweep reports no `approximate-common-*` anchor diagnostics: every
common-particle anchor rule (camera ray, model markers, slots, saved
origin, heights) resolves natively with the Koffing/Croconaw ROM markers.
Remaining:
- Dynamic anchors (`dynamic-anchor-write`, `unresolved-dynamic-anchor-read`)
  for Barrier, Light Screen, Reflect, Barrage, Sky Attack, Protect, Lock-On,
  Rollout, Heal Bell, Safeguard, Hidden Power: they read a posed FX-model
  marker; the sweep's CPU renderer has no posing, so these need an in-game
  check.
  Viewer playback (2026-10-02; LOVE viewer, arena 0, FIELD camera, Koffing
  source, Croconaw target, SEQ route, captures at six to twelve moments
  via STADIUM2_VISUAL_AUTOCAPTURE_FRAMES): all 11 resolve with no
  diagnostics once the move starts after the first draw (an auto key
  before it started the effect without a scene context: an artifact of
  the capture, not of the game). Seen: Barrier / Light Screen / Reflect
  panels in front of the source, following it; Protect, Safeguard, Heal
  Bell particles around the source; Lock-On's reticle closing, then
  particles on the source; Hidden Power's rings, then its burst on the
  target; Rollout's boulder rolling into the target; Barrage's ball leaving
  the source (tick 17) and its impact on the target (about tick 109; the
  flight is outside the FIELD view); Sky Attack's fire bird. Not visually
  confirmed against the game; the FIELD camera is not Stadium's.
  Found: Sky Attack and Rollout fade the source to opacity 0 (84100C68 ->
  8003F4DC; one write, held as in the ROM) and nothing in the port brought
  it back before the turn's end. Natively 841149A0 (the attack state's
  first function, Dispatch_015) runs 84111C44 -> 841089D8(1) at every
  move's start, and 841003AC there restores both battlers' opacity and fog.
  Fixed: `Scene:stadiumCameraAttack` clears first (attack_timing test).
- Camera-ray particles (descriptor flag 0x1: Absorb, Gust, Whirlwind, Roar,
  Vice Grip, Bite ...) are placed in front of the camera every frame and
  turned with the attacker's facing (841072BC / 84101D54). They look right
  only under Stadium's attack shot; with the FREE camera they sit at an
  angle. This is native placement, not a port error.
- Placement now also depends on timing (section 1): an impact that fires
  under the attack shot is drawn in a camera the ROM never uses for it.

## 3. Which animation plays

- Attacker: row byte 0 is the body clip, byte 1 the aux clip (84111D64 /
  84111E50 at counter 0), mapped through the species' selector table
  (8003F2C4, `AnimationSemantics`). 21,586 species x move rows select a
  clip outside the species' table (e.g. Hidden Power for every species).
  8003F2C4 then leaves the animation unchanged (the battler keeps its pose);
  the port's `Actor:attack` falls back to `play("attack")`, which ends on
  the idle loop and marks the actor idle. Close to native; the actor
  context should stay "attack" for the record's length.
  Fixed (same day): 84114BF4 passes `lb +0x616` (signed) to 84111D64 ->
  8003F2C4: -1 clears the animation (8003EAEC), a selector not below the
  table count (byte +4) returns with it unchanged. No ROM row has 0xFF
  (0 of 63,001 species x move rows), so every missing clip is the
  unchanged case. `Actor:attack` now keeps the playing animation and holds
  the attack (`Actor:stepHeldAttack`): until the row's length (+0x61A,
  byte 0x0A) when set; when 0, until 8003EC34 reports the animation at its
  last frame (frame >= length - 1; on a length, the clip's end plays
  context 0xFB = idle, 84112158, which an idle loop already is). The
  generic clip remains only for a move with no Stadium row (a degraded
  path, not native). Assumption: the pack's NONE also covers a table file
  the import did not decode; not separated (would need the selector
  table's count in the pack). Test: attack_timing (31 checks).
- Defender: context 254 (hit) exists for all 251 species. Natively it
  starts at the defender record's counter 0, not with the impact (see 1).
- Behaviour kinds (84114804, actor +0x61F): all ported (same day, after
  v0.24.1; battle-special-moves.md, kinds ROM test): 6 Agility, 7 Double
  Team, 9 Minimize, 0xD Meditate, 0xA Surf (57, height and tilt),
  4 Submission (66), 8 Seismic Toss (69, camera roll), 0xC Withdraw (110),
  0xE Waterfall (127), 0x19 Faint Attack (185), 0x1A Belly Drum (187),
  0x18 Destiny Bond (194), 0x13 Rapid Spin (229); defender kind 0xF for
  Stomp (23) and Body Slam (34) (84116BC0). Not seen in game yet.

## 4. What else the camera work needs

1. Section 1's fix: the impact and the defender hit clip follow the
   defender's record (the camera's hit start), not a fixed offset.
2. The text/HP gates of 84135778: Stadium's next record also waits for the
   record's text and HP bars. The hosts keep their own text and HP timing;
   the attack record's text starts at the release frame in Stadium but with
   the move event in the hosts. Acceptable unless the user sees overlap.
3. D_8419A005: 84135778 loads the next record at once when it is set (a
   forced load). Relevant to a button-skip feature.
4. Counter == +0x620 (byte 9): entry 0xFC under a result condition in the
   attack state, not wired.
   Resolved (same day): unreachable in the US ROM, so nothing to port.
   84114BF4 (US asm) at counter == +0x620 plays sound 0xF (80023A3C) and
   entry 0xFC (8410890C) only when record +9 has bit 0x08. That bit's only
   writer is 84134E00(8) in 84124DEC's second branch (fork C 15201a6,
   matched): taken when its side argument differs from D_841951BC. Its
   only caller, BattleAnim_Table_84186004_046 (8412FC9C), passes
   D_841951BC itself, so it always queues event 0x41 instead. No other
   jal, no pointer word to 84124DEC in fragment 79, every 84134E00 call
   passes a constant (0x08, 0x10, 0x10, 0x40), and no `ori 0x8` + `sb +9`
   exists. Matches decomp C and asm by reading; static call graph.
5. Multi-hit moves: each hit is its own defender record; with section 1
   each hit's impact must follow its own hit state. Done with section 1
   (each host hit starts its own defender record).
6. Viewer harness bug: `tests/stadium2_koffing_croconaw_visual/battle_fx.lua:73`
   formats nil for native screen renderers (Thundershock, Lovely Kiss,
   Sweet Kiss, Charm, Attract in the sweep).
   Fixed (same day): the model name uses tostring for the move and shape
   IDs. Sweep rerun for moves 84, 142, 186, 204 and 213 (150 ticks, both
   banks and sides): all finish. Viewer tool only; no game change.
6b. Done from this list (same day): 4 is unreachable (see 4); the Transform
   placement question is answered in battle-placement-audit-2026-10-01.md.
   Still open: the 11 dynamic-anchor moves need an in-game check (section
   2), and Gen 2's Fly / Dig pic motion against Stadium's own Fly / Dig
   states (placement audit).
