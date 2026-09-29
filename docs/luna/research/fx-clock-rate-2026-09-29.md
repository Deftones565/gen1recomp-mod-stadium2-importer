# Battle FX clock: logic 30 Hz, rendering 60 fps

**Correction (same day, after the user's retest): the conclusion below was
wrong and the 60 Hz change was reverted.** With FX and clips at 60 Hz the user
saw everything at double speed, while 30 Hz had matched the real game. The
retail game renders 60 frames a second (what the frame comparison below
measured: the camera and drawing update every video frame), but battle logic,
FX ticks and clip frames advance at **30 Hz**. The save-state facts still
hold, read in logic ticks: animation speed 1.0 is one clip frame per logic
tick; hit frame 50 + jaw age 6 = clip frame 56 shows the attack counter, clip
and FX share one 30 Hz clock. Which call in the battle loop waits for the
second retrace was not found (`80064D28` → `80005EE0` / `80005F0C` are
controller reads); the chain under `80008648` / `800088DC` remains to be read.
"Every consecutive video frame differs" is **not** evidence of the logic rate.

What the replay does explain: the jaws of Guillotine are world particles
placed just in front of the attack camera (save-state position
(-85.8, 25.6, -0.5)); they are still visible at video frame 10 (age ~11) and
out of view from frame 13, when Stadium cuts the camera to the defender, while
the particle lives to age 35. They leave the screen because of the camera
cut, not because they retire. The port has no Stadium camera shots, so they
stay in view. See the bug log (2026-09-29).

The original (superseded) text follows.

Date: 2026-09-29. **Implemented the same day** (see "Change made" below). Supersedes the
unsourced "30 Hz" assumption repeated across the research notes and
AGENTS.md ("Preserve deterministic 30 Hz stepping").

## Evidence

1. **Real game, measured.** A mupen64plus 2.6.0 save state taken by the user
   during Guillotine (Krabby vs Yanma, `~/.local/share/mupen64plus/save/
   Pokemon Stadium 2 (U) [!]-1561C75D.st0`, 2026-09-29 14:29) was replayed
   with `--testshots` at every video frame 20–40. Every consecutive pair of
   frames differs (1,700–11,200 changed pixels, `compare -metric AE`); none
   is identical. A 30 fps game shows each rendered image for two video
   frames, so pairs would be identical. **The battle renders at 60 fps.**
2. **Code.** The battle frame `8413D37C` calls the FX update
   (`8410A608` → `8410580C` command 2 → `841055D8` → `841029DC`, one
   particle update per call) at `8413D530`, gated only by `*s3 != 0` (FX
   active) and a state byte (`*s1 != s2`), not by frame parity; the FX draw
   (`8410A884`) follows at `8413D578` in the same iteration. One iteration
   per rendered frame means **one FX tick per video frame: 60 Hz (NTSC)**.
   The VI event is installed with retrace count 1 (`800053D4`,
   `osViSetEvent(q, 0x66, 1)`).
3. **Consistent with the save state.** At the save point the jaw particle
   (pool slot 233, mode 0, shape 252, object flag 1) is age 6; the port
   retires it at age 35 (animation finish, `8410291C`). At 60 Hz that is
   about 0.5 s on screen; the port shows it for about 1.2 s.

Not yet checked: the exact frame wait inside the battle loop (the chain
under `80008648` / `800088DC`), and PAL (50 Hz). The measurement above does
not depend on it.

## Consequence

Every FX duration and motion in the port is twice as long and half as fast
as in Stadium: particle ages, colour and scale tracks, alpha ramps, the
age-255 cutoff (8.5 s in the port, 4.25 s in Stadium), lifecycle timers,
schedulers. This matches the user's reports that effects (jaws, slashes)
stay on screen too long.

## Before changing it

- AGENTS.md fixes "deterministic 30 Hz stepping"; changing it is the user's
  decision (architecture rule).
- FX timing is tied to battle timing: the attack timeline converts the
  species' animation rows (hit frame, release) into FX ticks. Those
  conversions must be re-checked so effects still line up with the Pokémon
  (their clips' own playback rate included).
- Several tests hard-code tick counts at 30 Hz.

## Reproducing

`mupen64plus --noosd --windowed --savestate <copy of the .st0> --testshots
20,21,...,40 baseroms/stadium2.z64`, then diff consecutive screenshots in
`~/.local/share/mupen64plus/screenshot/`. RAM from the state: gunzip, find
`M64+SAVE`, RDRAM is stored as byte-swapped 32-bit words; fragment 79 was at
physical `0x147EE0` for virtual `0x84100030` in this state, pool pointer
`D_8418C950` = `0x8027D680`.

## Pokémon clips run on the same clock (added after the change decision)

The same save state holds the live animation states (the `8003E6DC` layout:
`+4` header, `+8` 16.16 position, `+0xC` 16.16 speed; header `+0xA` frame
count):

| state | header | frames | position | speed |
|---|---|---|---|---|
| `0x801D5190` | `0x806D0A60` (jaw animation, shape 253) | 35, once | 6.0 | 1.0 |
| `0x802724F0` | `0x80743274` (Krabby's Guillotine clip) | 107, once | 56.0 | 1.0 |
| `0x802738F0` | `0x806F7118` (a 120-frame loop, likely Yanma's idle) | 120, loop | 0.0 | 1.0 |

Krabby's Guillotine dispatch row: clip start 0, hit frame 50. The route
starts at counter 50 and the jaw is age 6, and the clip is at frame 56: the
attack counter, the clip frame and the FX age advance together, one per
60 Hz battle frame. The jaw animation's 35 frames match the port retiring
the jaw at age 35 (0.58 s at 60 Hz).

## Change made

- `lib/pack.lua` `Pack.FPS` 30 → 60 (Pokémon clip playback).
- `lib/stadium2_battle_fx_runtime.lua`, `lib/stadium2_battle_fx_lifecycle.lua`
  default `clockHz` 30 → 60.
- `lib/battle_actor.lua` pre-roll, special-routine and callback clocks
  `dt*30` → `dt*60` (web-owned file per WORK_SPLIT; timing constants only).
- `lib/renderer.lua` NOISE seed rate 60; comments in the adapter, sequence,
  special moves and renderer updated. `fragment.lua`'s keyframe `/ 30.0` is
  curve math, not a clock, and is unchanged.
- Tests that hard-coded 30 Hz steps now use 60 Hz steps.

Not checked: other game timing the host drives (faint, send-out waits),
which now sees clips finish in half the time, as in Stadium; the viewer's
own playback controls; PAL.
