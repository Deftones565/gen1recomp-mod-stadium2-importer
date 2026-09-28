# In-battle evolution (user-requested extension, not native)

Added 2026-09-28 at the user's request (notes: "when we evolve in a match
... the camera should go to the pokemon that is evolving ... white ...
particle effects ... gracefully change into its evolution model").

**This is not Stadium 2 behaviour.** Stadium 2 battles have no levels and no
evolution, so nothing in `lib/battle_evolution.lua` comes from the ROM or the
decomp. It is kept in its own module, separate from the native-parity code.

What is host-driven (unchanged): the evolution's timing, the B cancel, the
species change, the cries and every text are the host's own
(`src/ui/EvolutionState.lua` for Gen 1, `src/ui/gen2/EvolutionAnim.lua` for
Gen 2). The model swap follows the host's flash beats (Gen 1 `evoShowsNew`,
Gen 2 `showNew`).

What is invented presentation: the camera close-up and drift, the white
silhouette (`flashAmount`), the field dim and glow, the sparkles and the
reveal burst, and sending the evolving Pokemon out (with Stadium's send-out
entry 0x122) when it is not the one out.

Fallback: when either model or the Stadium message box art is unavailable,
nothing is hidden and the host's evolution screen plays as before.

Seams: `battle_scene.lua` (step, camera frame, actor override, flash,
backdrop and overlay draws), `main.lua` (`Evolution.install`: render.hud,
screen.render_visible, battle.bottom_ui_visible, battle.status_hud_visible,
the `evolutionPresented` export that STADIUM2_UI reads to stand aside).
Test: `tests/stadium2_battle_evolution_test.lua` (stubbed, ROM-free).
Not yet confirmed visually by the user.
