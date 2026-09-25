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
| Web | `lib/gen1_battle.lua`, `lib/gen2_battle.lua`, `lib/battle_actor.lua`, `lib/battle_camera.lua`, `lib/battle_presentation.lua`, `lib/animation_dispatch.lua`, `lib/stadium2_battle_fx_sequence.lua`, `lib/stadium2_battle_fx_battle_state.lua`, `main.lua`, new event/reaction/camera modules, `docs/stadium2_presentation_roadmap.md` |
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
- 2026-09-25 `7dddebb` 300-slot particle pool and 8410668C pool origin:
  run the ROM suite (the old `unsupported-common-pool-origin` diagnostic is
  gone); viewer-check 55 Water Gun, 140 Barrage, 188 Sludge Bomb,
  190 Octazooka, and one particle-heavy move for the cap. Note: this commit
  edited `lib/stadium2_battle_fx_runtime.lua` (now local-owned) before the
  split; the pool code is `Runtime:_allocateNativeSlot` /
  `Runtime:nativePoolOrigin`.
- 2026-09-25 `43d5eca` Gen 2 weather entries (0x107/0x106/0x113 ongoing,
  0x11F/0x121/0x120 ended, 0x125 sandstorm hit): battle retest with Rain
  Dance, Sunny Day, Sandstorm.
- 2026-09-25 `ae4b0dd`/`ad71572` result byte from `battle.damage_dealt`:
  no visible change expected; run the ROM suite.

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

## Verified

(none yet)
