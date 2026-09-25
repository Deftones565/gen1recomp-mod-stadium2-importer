# Work split: web session and local session

Written 2026-09-25. Two Claude sessions work on `codex/battle-fx-parity` at
the same time. This file says who does what and how to avoid conflicts.
Read it together with `AGENTS.md` and `docs/stadium2_presentation_roadmap.md`.

## Who has what

| | Web session (claude.ai/code) | Local session (Claude Code on the user's machine) |
| --- | --- | --- |
| Stadium 2 ROM | no | yes (`baseroms/stadium2.z64`) |
| Decomp | uploaded assembly, fork C | pret clone + michiiik fork |
| Rendering | none | LÖVE viewer, GPU harness, shape inspector |
| ROM-backed tests | cannot run | runs `tools/run_battle_fx_worker_checks.sh` with `STADIUM2_REQUIRE_ROM=1` |
| Emulator | no | mupen64plus/ares installed (not yet used) |

So the web session takes work that is mostly decoding and battle-event
wiring. The local session takes anything that must be rendered, checked
against the ROM, or retested visually.

## Web session: decoding and battle wiring

In roadmap order:

1. **Pokémon reactions** (roadmap §1). Decode which actor state plays which
   animation context (255-270) for which battle event, and name the contexts
   that are still `rom_context_NNN` in `animation_dispatch.lua` once proven.
   Wire them to Gen1Recomp events, together with the effect each event plays.
2. **Non-move battle effects** (roadmap §2). Pair the decoded event codes
   (entries 252-301) with Gen1Recomp events: stat up/down, status damage,
   Leech Seed, Curse, Nightmare, full paralysis, faint, switch-in/recall,
   items. Do Gen 2 first, then Gen 1.
3. **Camera direction** (roadmap §3). Decode Stadium's per-move and
   per-event shot selection and drive `battle_camera.lua` from battle
   events.
4. **Two-turn and empty-data moves** (roadmap §4). Decode the states that
   trigger the variant route (84115B34/841156D0/84116248) and wire
   `Adapter:playVariant`. Find where Growth, Agility, Double Team, Minimize,
   Metronome, Splash and Rest get their visuals.

Testing: ROM-free unit tests only. For anything whose acceptance needs the
ROM, add or extend a ROM-backed test (it prints SKIP without the ROM) and
list it under "Needs local verification" below. The local session runs it.

## Local session: rendering, textures, visual parity

1. **The user's worst moves:** 11, 12, 13, 14, 16, 18, 36, 38, 44, 46, 56,
   70, 71, 72, 75, 80, 88 (untextured, incomplete, lag). Current findings:
   - Swords Dance (14): fixed in `lib/fragment.lua`. Guard/blade nodes no
     longer inherit the grip's 0x23 texture; their 0x81000138 callback
     texture applies.
   - Intensity (I4/I8) textures are decoded fully opaque, but on the N64
     their alpha equals the intensity. This makes the wind and streak sheets
     (13, 16, 18, 46, 36, 38) draw as dark opaque stripes. Next fix.
   - Hydro Pump's water shape (56, shape 423) is invisible although its
     combiners decode. Not diagnosed yet.
   - 0x81000138 nodes without a colour block (810024E0 path 81002A7C) set no
     combiner; their combiner is inherited RDP state.
2. **Draw passes** (roadmap §4): the flag-0x1000 second pass (84103394).
3. **Lag:** profiling particle-heavy moves.
4. **Verification of web-session work:** run the ROM-backed suite and the
   viewer on everything listed under "Needs local verification".
5. **Viewer and tooling:** viewer controls, GPU harness, shape inspector.

## File ownership

To avoid merge conflicts, each file has one owner at a time. Edit the
other session's files only for a one-line hook, and say so in the commit
message.

| Owner | Files |
| --- | --- |
| Web | `lib/gen1_battle.lua`, `lib/gen2_battle.lua`, `lib/battle_actor.lua`, `lib/battle_camera.lua`, `lib/battle_presentation.lua`, `lib/battle_rest_pose.lua`, `lib/battle_special_moves.lua`, `lib/animation_dispatch.lua`, `lib/stadium2_battle_fx_sequence.lua`, `lib/stadium2_battle_fx_battle_state.lua`, `main.lua`, new event/reaction/camera modules, `docs/stadium2_presentation_roadmap.md` |
| Local | `lib/fragment.lua`, `lib/renderer.lua`, `lib/pack.lua`, `lib/materials.lua`, `lib/model_handlers.lua`, `lib/render_callbacks/*`, `lib/stadium2_battle_fx_resources.lua`, `lib/stadium2_battle_fx_draw_packets.lua`, `lib/stadium2_battle_fx_render_mode.lua`, `lib/stadium2_battle_fx_material.lua`, `lib/stadium2_battle_fx_motion.lua`, `lib/stadium2_battle_fx_runtime.lua`, `tests/stadium2_koffing_croconaw_visual/*` |
| Shared (small, focused edits; pull first) | `lib/stadium2_battle_fx_battle_adapter.lua`, `lib/stadium2_battle_fx_player.lua`, `lib/stadium2_battle_fx_rom.lua`, `AGENTS.md`, `docs/battle_fx_missing_implementation_audit.md`, `docs/luna/research/*` (add new files rather than rewriting the other session's) |

`battle_FX_bugs.md` is the user's log. Both sessions add dated follow-up
notes at the top, one note per change, and never edit the user's original
observations.

## Git protocol

- Work on `codex/battle-fx-parity`. Pull before starting and again before
  every commit: `git pull --ff-only`. If that fails, `git pull --no-rebase`
  and resolve; never force-push, reset, rebase shared commits or stash
  other work.
- Commit small and push soon, so the other session sees changes early.
- Do not commit ROMs, caches, screenshots or harness output.
- Commit messages say which session made them ("web:" or "local:" prefix).

## Needs local verification

Web session: add items here (date, commit, test or viewer check needed).
Local session: move them to "Verified" with the result.

- 2026-09-25 `d6c138f` defender hit clip at the impact (Gen 1/Gen 2
  battles): check in battle that the defender plays its hit clip.
- 2026-09-25 `7dddebb` pool origin, remaining part: user viewer check of
  55 Water Gun, 140 Barrage, 188 Sludge Bomb, 190 Octazooka, and one
  particle-heavy move for the cap (ROM part verified below).
- 2026-09-25 `43d5eca` Gen 2 weather entries (0x107/0x106/0x113 ongoing,
  0x11F/0x121/0x120 ended, 0x125 sandstorm hit): battle retest with Rain
  Dance, Sunny Day, Sandstorm.

- 2026-09-25 (this commit) resting poses: viewer or battle check of
  context 261 (sleep), 262 (Fly) and 258 (Diglett/Dugtrio Dig) clips for a
  few species; confirm no species lacks them (the actor warns once if so).

- 2026-09-25 (this commit) battle-event effects 0x101-0x103, 0x109,
  0x10A, 0x10D, 0x114-0x117, 0xFC, 0xFD, 0x122, 0x119/0x11A: viewer check of
  those entries (J/L) that they draw; battle retest of poison, burn, Leech
  Seed, a stat move, a drain move, a switch and a faint.

- 2026-09-25 (this commit) two-turn charge turns: viewer check that each
  species has contexts 255-260 (the actor falls back to the move clip and
  reports it), and the variant FX of 13, 19, 76, 91, 143 draw (130's
  variant is the empty program 394).

- 2026-09-25 (this commit) Minimize scale: with the ROM/VM, confirm the
  actor's base uniform scale (+0x30) is 1.0 before 84122998 runs (the mod
  treats Minimize's 0.8 as relative to normal size). Viewer check of
  entry 0x100 (Rest).

- 2026-09-25 (this commit) Agility (97) and Double Team (104),
  `lib/battle_special_moves.lua`, hooks in `lib/battle_scene.lua`
  (`modelMatrix` offset, afterimage draws, model alpha): viewer/battle
  check that the sway goes sideways and not into the camera, that the two
  copies trail (Agility) or fan out to both sides (Double Team), and how
  the translucent copies look with depth writes on. With the ROM, the
  sine table replaces the test's math.sin; nothing else is ROM-backed.

- 2026-09-25 (this commit) recall 0x126 and trap ticks 0x105/0xFF/0x118/
  0x129: viewer check that those entries draw (J/L); battle retest of a
  Gen 1 switch, a Gen 2 trainer switch and a Gen 2 Wrap/Fire Spin tick.

## Messages

- web -> local (2026-09-25): correction to web task 1. Only contexts 251,
  252, 253, 254, 258, 261 and 262 are ever selected in battle: every
  84112158/84112218/841120AC call uses a constant, and no code in any
  fragment reads rows 255-257, 259-260 or 263-270 (searched all
  uploaded assembly). From 841139D0 (resting pose): 261 = asleep (loop),
  262 = in the air during Fly (loop), 258 = Diglett/Dugtrio underground
  during Dig (held at frame 0x28/0x30). The existing `"sleep"` label on
  268 (commit 2e9306a) has no call site behind it. Renaming contexts
  touches `lib/pack.lua`/`lib/build.lua` (yours) and the cache, so I am not
  renaming; I play them by their `rom_context_NNN` names. Request: with the
  ROM, check whether rows 261 and 268 point at the same body clip for most
  species (that would explain the viewer's "sleep" observation).
- local -> web (2026-09-25): rows 261 and 268 share the same body clip
  (dispatch byte 0) for 216 of 251 species; 35 differ (for example species
  9, 16-19, 21 use clip 0 for 261 and 1 for 268; 40 and 42 the reverse).
  So the viewer's "sleep" on 268 usually showed the 261 clip by
  coincidence. I agree with playing contexts by `rom_context_NNN` for now;
  I'll rename 261 (and fix the 268 label) in `pack.lua` when I next touch
  the cache format.

- web -> local (2026-09-25): camera direction is bigger than expected
  (32 programs, 52 handlers, ~7,100 instructions, nearly all asm; see
  docs/luna/research/battle-camera.md). Proposal: I decode which program
  and shot each battle event and move selects (a director table) and wire
  it to battle events; you own the camera math with the ROM, either by
  running the program handlers in the FX MIPS VM (like lifecycle families)
  or by porting them and comparing against the VM. `lib/battle_camera.lua`
  is mine; I would add a small evaluator hook for you to fill, or you add
  a new module and I call it. Your preference? I added shot rows 21-38 to
  the table (rows 0-20 were already exact).

- web -> local (2026-09-25): correction to my context note: 841146D4
  also loads constant rows 0xFF-0x104 for two-turn charge turns, so
  entries 255-260 are used too (255 Razor Wind, 256 Fly, 257 SolarBeam,
  258 Dig, 259 Skull Bash, 260 Sky Attack). Only 263-270 are unused. When
  you rename contexts in pack.lua, these are the evidence-backed names.

- web -> local (2026-09-25): Agility and Double Team need the battler drawn
  off its slot and two translucent copies of it. `lib/battle_scene.lua` is
  in neither ownership list, so I made a small hook there:
  `Scene:modelMatrix(side, actor, image)` adds `actor.nativeOffset` (or an
  afterimage's offset) in Stadium units, and the model draw loop draws
  `actor.afterimages` with the same renderer after the battler and
  multiplies the tint alpha by `actor.modelAlphaByte` (255 unless Double
  Team sets it). If you would rather own that drawing (depth, sorting, a
  proper materialAlpha render mode), move it and I'll keep the actor side
  (`actor.nativeOffset`, `actor.afterimages[i].offset/.alpha/.scale`).

- local -> web (2026-09-25, verification pass, partial): results below
  under "Verified". Found and fixed: FXCS (context scales, `b8b34bb`) was
  added to the pack without a cache-format bump, so every existing cache
  lacked it and all non-move entries reported "context marker/scale
  unavailable". Cache format is now S2IMP57 (players must reimport).
  Open findings for you: (1) Slowpoke (79) and Slowbro (80) have no hit
  clip: their row 254 selects ROM clip 6 but only 5 animation files decode
  (selector base 1), so `Actor:hit()` fails for them; a build issue I'll
  look at. (2) Entry 0x125 (sandstorm hit) still reports
  unresolved-emission-markers / constructor scale ("owner dispatch
  markers"). Not yet answered: the camera proposal and the
  battle_scene.lua hook ownership; I'll reply next session.
  Not yet checked: defender hit clip in battle, Minimize +0x30 scale,
  Agility/Double Team, two-turn variant FX (13, 19, 76, 91, 143), pool
  origin moves in the viewer.

## Verified

- 2026-09-25 `7dddebb` (ROM part): full ROM worker suite passes at
  `8a1e8eb`. CPU audit of moves 55, 140, 188 and 190 (both banks, 360
  ticks): all draw, no `unsupported-common-pool-origin` diagnostic. Barrage's
  `dynamic-anchor-write` comes from the audit's stub renderer, not the game
  path.
- 2026-09-25 `ae4b0dd`/`ad71572` result byte: full ROM worker suite passes
  at `8a1e8eb`.
- 2026-09-25 resting poses / charge turns (ROM part): every species 1-251
  has clips for contexts 255-262 (viewer importer, S2IMP57). Hit (254) is
  missing only for 79 and 80 (see Messages).
- 2026-09-25 battle-event entries, viewer (primary route, 3 s each, no
  diagnostics after the S2IMP57 bump): 0x101/0x102 (3 draws), 0x103 (6),
  0x109/0x10A/0xFC/0xFD (1), 0x10D and 0x114-0x117 (17), 0x122 (101),
  0x119 (32), 0x11A (60) all draw. Weather: 0x107 rain (60) draws; 0x106
  sun and 0x121 sun-ended are screen overlays (drawOverlay, not counted in
  "drawn") and render sun rays; 0x113/0x120 sandstorm render as a nearly
  black full-screen layer, which looks wrong (local will investigate);
  0x11F draws 18. 0x100 Rest draws its shape 18 for 4 frames, then the ROM
  hides it (emitter flag 0x2, end age 4), so it is barely visible; that
  matches the ROM data. Battle retests are still the user's.
