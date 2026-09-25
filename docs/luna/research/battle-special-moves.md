# Moves with empty FX banks, and per-move actor behaviours

Web session, 2026-09-25. Sources: US assembly for fragment79 (user's pret
split), michiiik/pokestadiumgs `7fc529e5` C (Math_StepToF 8003730C).
Matches ROM assembly; not visually confirmed.

Growth (74), Agility (97), Double Team (104), Minimize (107), Metronome
(118), Splash (150) and Rest (156) have empty move and impact banks. What
Stadium shows for them:

- Every move plays the species' own attack clip from its dispatch row
  (84114804 -> 841146D4). For Growth, Metronome and Splash that clip is the
  whole presentation: 84114804 gives them no behaviour kind (0xFF). The mod
  already plays it (Actor:attack). Metronome's called move is presented by
  the host as its own move.
- 84114804 also sets a behaviour kind at actor+0x61F per move: 0x39 Surf
  0xA, 0x42 4, 0x45 8, 0x60 0xD, 0x61 Agility 6, 0x68 Double Team 7, 0x6E
  0xC (unless the species is in D_841839EC), 0x7F 0xE, 0xB9 0x19, 0xE5
  0x13, 0x6B Minimize 9, 0xBB 0x1A, 0xC2 0x18; others 0xFF.
  8411845C runs the kind's start routine (84123F60, jtbl_84189D40) at the
  hit frame and its update (84124104, jtbl_84189DA0) every later frame of
  the attack state. Agility: 841218EC / 84121920 (108 lines); Double Team:
  84121CAC / 84121DE8 (81 / 349 lines). Not decoded yet.
- Minimize (kind 9): start 84122990 is empty; update 84122998 sets the
  uniform scale (actor +0x30/+0x34/+0x38) to Math_StepToF(scale, 0.8f,
  0.01, 0.01) unless it equals 0.8 as a double (a float 0.8 never does, so
  the step clamps). 84112580 at hit+10 only sets an event flag; the state
  runs until its clip ends. Implemented as an actor size factor, kept until
  the Pokemon is replaced. Assumes the base scale is 1.0 (84123858, kind
  0xF, also computes scale as 1.0 - x): needs ROM confirmation.
- Rest: BattleAnim_Dispatch_017 sends move 0x9C to 841153DC. At the hit
  frame it plays the empty move route, sound 0xC, 841122D4 (sleep context
  261) and signals entry 0x100 on the user. Implemented: entry 0x100 at the
  hit frame; the sleep pose follows from the presented sleep status.
