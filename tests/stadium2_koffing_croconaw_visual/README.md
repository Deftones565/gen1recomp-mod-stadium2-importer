# Stadium 2 model, arena, and battle FX viewer

From the Gen1Recomp root:

```sh
love mods/STADIUM2_IMPORTER/tests/stadium2_koffing_croconaw_visual
```

Battle FX uses the same persistent player, ROM routing, 30 Hz runtime, and
placement adapter as the battle integration. The supported local US ROM at
`baseroms/stadium2.z64` supplies resources directly; `STADIUM2_VISUAL_ROM`
overrides its path. Without that ROM, the viewer uses the imported cache.

Model cache format S2IMP55 preserves ROM attachment markers and move attachment
selectors. Reimport older model caches to let beams follow those animated markers.
The diagnostic identifies remaining target-height/special-case approximations.

| Control | Action |
| --- | --- |
| J / L | Select and play previous / next FX entry (1–251 moves, 252–301 non-move battle effects) |
| K / FX button | Replay selected move |
| O | Cycle SEQ (default: the source plays its move animation, then move bank, then impact bank at the dispatch hit frame) / PRI / ALT / VAR (two-turn moves only) and replay. A missing species animation or hit frame is reported and the FX still plays. |
| Tab | Select source actor for the next playback |
| Space | Pause / resume the viewer |
| N while paused | Advance FX by exactly one 30 Hz tick |
| M | Stop and release FX |

Replay resets the presentation RNG; changing the selected actor does not
retarget a running effect. `STADIUM2_VISUAL_MOVE_FX` sets the initial move ID,
and `STADIUM2_VISUAL_FX_ALTERNATE=1` selects its alternate route. The ROM now
supplies both directional trig tables and the age-gated common size ramp.
Common particles now use ROM direction modes 4/5/7/8, all three speed
initialization modes, signed vertical ramps, and authored rotation matrices.
Age-gated particle opacity ramps now fade and retire particles according
to ROM flags. For example, Fire Punch's first particles begin fading at
tick 8 and disappear at tick 15. This shared ramp occurs on 179 move routes.
These direction controllers occur in 159 primary/alternate move routes;
that is coverage of this controller, not a claim of complete move parity.
Mode 2 native color tracks are decoded on 104 routes and drive the native
background fill color. Arenas with a fully drawn backdrop can cover that
fill, just as other scene geometry covers the clear color. The panel exposes
the current native RGBA so its timing can also be checked directly.
For in-game playback from an older cache, reimport once to add the
`battle_fx_trig` data block; the direct-ROM viewer needs no reimport. Existing
model, shader, and arena controls remain available.

The FX panel displays frame, submitted packet count, diagnostic count, and
the latest diagnostic. Set `STADIUM2_VISUAL_FX_TRACE=1` to log particle
positions, scales, and loaded mesh rows. A submitted packet count is not a visual parity
measurement. Unresolved native callbacks, motion controllers, trig inputs,
and lifecycle geometry still prevent full ROM parity. There is no guessed
preview lifetime or invented fallback geometry; use M to stop unresolved or
looping effects. Detailed diagnostics are also printed to the console.

ROM-backed viewer integration regression, from the repository root:

```sh
STADIUM2_REQUIRE_ROM=1 luajit mods/STADIUM2_IMPORTER/tests/stadium2_battle_fx_viewer_test.lua
```
# Beam lifecycle effects

Moves 60 (Psybeam), 62 (Aurora Beam), and 76 (SolarBeam), primary route,
now use the shared persistent beam renderer: ROM tube layers, two scrolling
textures, and camera-facing glow. Host model centers approximate native joints;
the diagnostic reports this limitation. In battles they finish automatically
when the host move animation ends. The standalone viewer has no battle animation
controller, so use its stop/restart controls when testing.
