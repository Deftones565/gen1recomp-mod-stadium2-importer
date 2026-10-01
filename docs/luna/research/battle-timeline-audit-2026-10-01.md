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

Fix direction: start the impact bank and the defender's hit clip from the
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
- Defender: context 254 (hit) exists for all 251 species. Natively it
  starts at the defender record's counter 0, not with the impact (see 1).
- Behaviour kinds (84114804, actor +0x61F) still not ported: 0xA Surf (57),
  4 Submission (66), 8 Seismic Toss (69), 0xC Withdraw (110), 0xE Waterfall
  (127), 0x19 Faint Attack (185), 0x1A Belly Drum (187), 0x18 Destiny Bond
  (194), 0x13 Rapid Spin (229); defender kind 0xF for Stomp (23) and Body
  Slam (34) (84116BC0). Ported: 6 Agility, 7 Double Team, 9 Minimize,
  0xD Meditate.

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
5. Multi-hit moves: each hit is its own defender record; with section 1
   each hit's impact must follow its own hit state.
6. Viewer harness bug: `tests/stadium2_koffing_croconaw_visual/battle_fx.lua:73`
   formats nil for native screen renderers (Thundershock, Lovely Kiss,
   Sweet Kiss, Charm, Attract in the sweep).
