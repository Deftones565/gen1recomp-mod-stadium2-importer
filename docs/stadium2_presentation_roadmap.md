# Stadium 2 battle presentation roadmap

Written 2026-09-25. What is still needed for a complete Stadium 2 battle
presentation on top of Gen1Recomp's Gen 1 and Gen 2 battle engines.

The mod is presentation only (see `AGENTS.md`, Architecture): the recomp
decides what happens, and Stadium 2's battle engine is read only to map
battle events to what Stadium shows. Where the two differ, the recomp wins.

Already in place: Stadium models (normal and shiny, skeletal and texture
animation), arenas, a Stadium-style HUD, the field camera, trainer sprites,
shadows, and most of the move-effect engine. Move-level status is tracked in
`battle_FX_bugs.md`; effect-engine gaps in
`docs/battle_fx_missing_implementation_audit.md`; decoded evidence in
`docs/luna/research/sequencing-render-emission.md`.

## 1. Pokémon reactions and animations

Large; visible every turn.

- Battle uses context entries 251-262 (`docs/luna/research/battle-rest-pose.md`);
  263-270 are never read. Resting poses (261 asleep, 262 Fly, 258
  Diglett/Dugtrio Dig, frozen hit hold) and charge-turn clips (255-260)
  are implemented (2026-09-25).
- The decoded event codes show which clip Stadium plays for which battle
  event. Work: pair each code with the matching Gen1Recomp event, then play
  the clip and its effect together.
- The hit reaction starts at the impact; Stadium starts it slightly earlier,
  when the defender's hit state begins.

## 2. Non-move battle effects

Large.

- The code-to-effect tables for entries 252-301 are decoded. Only weather is
  wired (Gen 2: ongoing, ended and sandstorm hit).
- Still to pair with Gen1Recomp events: stat up/down, poison, burn and
  confusion damage, Leech Seed, Curse, Nightmare, full paralysis, faint,
  switch-in and recall, item use.
- Gen 1 has residual damage, faint, send-out and charge turns wired; its
  stat changes have no host event.
- 2026-09-25: recall (0x126) and trap ticks wired where the host has a cue
  (docs/luna/research/battle-event-effects.md). Stadium has no bag items or
  ball throws, so those keep the Game Boy animations. Gold's player
  switch has no withdraw step in Gen1Recomp; pairing it needs one there.
- Some events lack a detail the presentation needs (for example, Gold's
  "fully paralyzed" message has no side). These need a small addition to
  Gen1Recomp's events, not a guess from the text.

## 3. Camera direction

Large; probably the biggest gap in overall feel.

- In battle the camera holds the standard field shot. The 21 Stadium camera
  shots (`D_8418455C`, `lib/battle_camera.lua`) are only reachable manually
  in the viewer.
- Stadium chooses a shot per move and per event and moves between them.
  Work: decode that selection from fragment 79 and drive it from battle
  events. Self-contained; the needed assembly is available.

## 4. Finishing move effects

Medium; spread across many moves.

- Second turn of two-turn moves: Razor Wind, Fly, SolarBeam, Dig, Skull
  Bash, Sky Attack (variant routes exist; the triggering states
  84115B34/841156D0/84116248 need decoding).
- Moves with no effect data, whose visuals live in Stadium's battle code:
  Growth, Agility, Double Team, Minimize, Metronome, Splash, Rest.
  All seven are now handled (2026-09-25); the other behaviour kinds (Surf,
  Seismic Toss, Meditate, Withdraw, Waterfall, Feint Attack, Rapid Spin,
  Belly Drum, Destiny Bond, move 0x42) are not decoded yet.
- Draw passes: every mode-1 particle carries flag 0x1000 and is drawn in a
  separate Stadium pass the mod does not model. Possibly behind some "not
  visible" reports; untested.
- Swords Dance texture lead: fragment 26's 810024E0 path without a colour
  block (the uploaded assembly includes fragment 26).
- Lag on particle-heavy moves: needs profiling on the target machine.
- User retests of moves 57-251 (never checked in the viewer).

## 5. Polish and optional

- One open model bug: #204's eyes (`model_bugs.md`).
- Remaining arena material items (`ARENA_PARITY_AUDIT.md`).
- Stadium sound and music: the effects reference Stadium sound IDs, but the
  mod plays no Stadium audio, so battles keep the Game Boy sounds. A large,
  separate project; only if requested.

## Suggested order

1. Reactions and non-move effects (sections 1 and 2): same decoding, one
   more pass through the event codes, biggest visible payoff.
2. Camera direction (section 3).
3. Two-turn and empty-data moves (section 4).
4. Draw passes and the Swords Dance lead, which need visual checks.

Steps 1-3 can be decoded from the assembly and Gen1Recomp; anything that
changes how things look still needs a user retest.
