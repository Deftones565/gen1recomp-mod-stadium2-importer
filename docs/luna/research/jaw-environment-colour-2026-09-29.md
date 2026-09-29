# White jaws: where the environment colour comes from

Date: 2026-09-29. Research only; no runtime change. Moves: Vice Grip (11),
Guillotine (12), Bite (44). Sources: supported US ROM, pret/pokestadiumgs
`c0e10f23` US assembly (fragments 26 and 79, `GLOBAL_ASM`).

## The shape

Vice Grip's move bank is program 64, one mode-0 particle, shape **252**
(`tools/dump_fx_colors.lua 11`): compiled layout, node layer 6, two prims,
`displayListState=true`, primitive colour white with LOD fraction 1, and
**no environment colour and no colour controller**.

Combiner (both prims):

- cycle 1 colour `(TEXEL1 − TEXEL0) × PRIM_LOD_FRAC + TEXEL0` (texture blend)
- cycle 2 colour `(PRIM − ENV) × COMBINED + ENV`
- alpha: texture blend, then `COMBINED × PRIM alpha`

With PRIM white and the renderer's fallback ENV white
(`lib/renderer.lua` sends `{1,1,1,1}` when `environmentColor` is nil), cycle 2
is `(1 − 1) × tex + 1` = pure white: the texture is lost entirely. Any darker
ENV would let the texture shade the jaws.

## What the ROM sets

Each particle draw entry goes `841031F4` → material callback resolved from
`8100348C` (fragment 26, via `80003240`) → `84102E84` → display list.
`8100348C` calls the FX material builder **`810024E0`** (998 lines).

`810024E0` emits `G_SETENVCOLOR` (`0xFB`) only on the colour-block path
(`810028E0..81002A7C`, and `81003078..810030F0`): when the node's colour
block (`s2+8`) has an environment entry (`+8`). There the value is:

- particle flag `0x8` and `0x20` set: the particle's secondary colour
  `+0x8B..+0x8E` (RGBA);
- flag `0x8` set, `0x20` clear: secondary RGB with the block's alpha;
- flag `0x8` clear, `0x20` set: the block's RGB with the particle's `+0x8E`
  alpha;
- neither: the colour block's own value;
- no particle (`s1 == 0`): the block's value.

A node **without** a colour block takes path `81002A7C` and emits **no**
`0xFB`. Shape 252 is such a node, so on the N64 the jaws draw with whatever
environment colour the RDP holds from the previous submission. The current
fallback (white) is therefore not the native value, and no single constant
is "correct" without knowing that previous submission.

## Where the inherited value comes from

`8413D37C` (the battle frame) calls the FX update `8410A608`, then
`841359D0`, `84137778`, `84136D9C`, `84137CA4`, `800088DC` (most likely the
main 3D scene draw: arena and Pokémon), then the FX draw `8410A884`
(`84105630`: `84103394`, `guOrtho`, `84103478`), then UI functions
(`8413C7C0`, `8410A9B4`, `84145BA0`, `8414605C`, ...). RDP state persists
across submissions and across frames, so the jaws' ENV is the last `0xFB`
issued before them: from the last scene node drawn in `800088DC` that set
one, from an earlier FX particle in the same frame, or, if nothing in the
frame sets ENV, from the previous frame's last `0xFB` (possibly the UI).

Which of these it is has not been established statically. It may differ
per arena, per species, or per frame.

## Options

1. **Ground truth (preferred).** Capture the RDP command stream for a frame
   of Vice Grip in the emulator (the display list at the FX draw) and read
   the last `0xFB` before shape 252's list. That gives the value and its
   source, and tells whether it is constant.
2. **Emulate RDP persistence.** Keep a renderer-wide "current environment
   colour" updated by every submission that sets one, in draw order, and let
   nodes without one use it. This is the native mechanism, but its result is
   only as right as our draw order matches Stadium's (`800088DC` traversal,
   FX slot order, UI), which is unverified; it could produce a different
   colour than the retail game.

Do not substitute a guessed colour (AGENTS.md accuracy rules).

## Related

Other shapes whose nodes have no colour block (compiled layouts, the
`0x81000138` nodes without a colour block noted in `docs/WORK_SPLIT.md`)
share the same inheritance; the same trace answers them.
