# Pokemon Stadium 2 Importer

`STADIUM2_IMPORTER` is a standalone Pokemon Stadium 2 model extractor and renderer for Gen 1 and Gen 2 games in gen1recomp, with owned 3D battle presentation on both generations.

It does not depend on another model importer or renderer. The mod owns ROM discovery, ROM validation, Stadium 2 archive parsing, PERS-SZP/Yay0 decompression, FRAGMENT model parsing, model-handler decoding, DSM4 cache generation and loading, skeletal animation, texture animation, texture upload, skinning, render state, and model drawing.

The supported ROM is the US Pokemon Stadium 2 ROM with MD5 `1561c75d11cedf356a8ddb1a4a5f9d5d`.

## Options

`STADIUM 2 MODELS` defaults to `ON`. Turning it `OFF` keeps the imported model cache intact but disables creation and use of Stadium 2 renderers. Turning it back `ON` restores Stadium 2 rendering without rebuilding the cache.

`STADIUM 2 BATTLE` defaults to `ON`. Gen 1 and Gen 2 now use the importer-owned Stadium presentation. The host battle engines remain authoritative for turn order, damage, move effects, capture odds, switching, faint results, text, menus, party state and RNG. Generation adapters read that state and replace presentation only: a full-window environment, solved perspective camera, footprint-sized 3D platforms, model shadows, frosted edge-aligned HUD, projected native battle effects, normal/shiny DSM4 actors, callback runtime, materials, animated textures, additive FX, presented-frame timing, and send-out/attack/faint states. Turning it `OFF` leaves the engine's normal battle presentation in control.

Gen 1 is implemented by `lib/gen1_battle.lua` as a draw-only adapter over the host `src.battle.BattleState`. Gen 2 is implemented by `lib/gen2_battle.lua` over `src.ui.gen2.BattleState`. Shared model and stage behavior lives in `lib/battle_actor.lua` and `lib/battle_scene.lua`; neither adapter owns battle simulation.

`BATTLE AA` applies to the owned Stadium arena in either generation. It defaults to `OFF`; `2X` and `4X` supersample the 3D scene before the native pixel-art UI and battle objects are composited, and automatically clamp to the GPU texture limit.

In a Stadium battle, ordinary mouse movement controls orbit and pitch, the mouse wheel or `Q`/`E` controls zoom, the controller right stick controls the camera, and `0` resets the shot. One free touch drags and two free touches pinch on both Gen 1 and Gen 2; touches that begin on virtual controls remain owned by the touch pad.


At game ready the importer inspects the merged Pokemon data and expands its own cache target automatically. A normal Gen I game requests 151 models; Gold or a loaded 251-species overhaul requests all 251 without requiring a separate Stadium renderer adapter.

When extraction is required, an opaque in-game import screen shows the real
scan, index, model, animation, normal-pack, and shiny-pack progress. Gameplay
remains paused behind it. Completion closes the screen automatically; a failed
import displays the failing stage and offers retry or close controls.

On Android, **OPTIONS -> STADIUM 2 ROM** uses Gen1Recomp's native system
document picker through the native no-argument `love.system.pickFile()` ROM path. The selected document is
handed back as `picked_rom.gb`, validated as the supported Stadium 2 US ROM,
loaded into the normal importer, and the temporary handoff file is removed.
Desktop Linux, Windows, and macOS keep their existing ROM discovery and file
dialog paths.

The generated cache is stored under:

```text
stadium2_importer/normal/%03d.dsm
stadium2_importer/shiny/%03d.dsm
stadium2_importer/battle/unown_b.dsm ... unown_z.dsm
stadium2_importer/battle/unown_b_shiny.dsm ... unown_z_shiny.dsm
stadium2_importer/pack.info
```

Unown A is species 201 in the ordinary normal/shiny directories. Stadium 2
model and pose records 254 through 278 supply Unown B through Z, so the cache
contains all 26 forms in both normal and shiny variants.

The cache marker format is `S2IMP28`. Shiny packs use Stadium 2's per-species
HSL metadata, while Clefairy, Clefable, Jigglypuff, Wigglytuff, Gyarados,
Noctowl, Cleffa, and Igglybuff use the ROM's dedicated native-format rare-texture
archive, preserving each source texture's N64 bit depth. Translucent model-local FX are kept out of the HSL pass. Model packs use the `DSM4` magic and
carry the importer-owned `S2HX` v4 render extension. Version 4 associates
materials and callbacks with the exact primitive-emitting command site,
splits primitives at callback boundaries, embeds callback textures, and
includes the ROM-textured fire geometry constructed by fragment 26. Older
caches are rebuilt automatically.

DSM4 preserves full per-primitive geometry mode, vertex normal versus RGBA
interpretation, source alpha, callback texture eligibility, and N64 sampler
and texture-scale state. It also distinguishes authored textures from the
neutral sampler input used by source display lists that intentionally disable
texturing. Callback programs remain modular in `S2HX`; core mesh
meaning no longer depends on that extension.

The standalone renderer and both generation battle adapters read those packs
directly. They use rigid bone bindings, source 30 Hz animation frames,
per-animation and callback texture streams, parsed material state, primitive
culling, additive second-pass rendering, embedded RGBA textures, and the
verified Stadium 2 model-handler state implemented by the importer.

For standalone visual inspection, run:

```sh
love mods/STADIUM2_IMPORTER/tests/stadium2_model_viewer_visual
```

`Tab` selects the enemy or player model, left/right cycle one species, and
up/down jump ten species. `Q`/`E` cycle animations, number keys isolate a
primitive, and `G`, `[`/`]`, and `X` force, age, or suppress dynamic callback
FX for the selected model.

Fragment 26 handler metadata lives in `lib/handler_registry.lua`. Shared
dynamic-object behavior is composed from audited ASM lifecycle routes under
`lib/effects/`, while `lib/effect_renderer.lua` owns the generic billboard
render description. Phase-5 model rendering callbacks live under
`lib/render_callbacks/`; this keeps shared callback-owned texture and material
logic out of species-specific code. `model_handlers.lua` and `renderer.lua`
retain the public compatibility entry points used by packs, battles, and older
audits.

The semantic model-completeness audit is separate from the callback coverage
audit. It compares source model meaning with what DSM and the renderer can
represent, including topology, callback ownership and targeting, N64 geometry
mode, vertex RGBA versus normals, texture sampler state, and pose/auxiliary
alignment. It audits all 251 species by default or a focused shared-code list:

```sh
STADIUM2_ROM=/path/to/stadium2.z64 lua tests/stadium2_model_parity_audit.lua --report
STADIUM2_ROM=/path/to/stadium2.z64 lua tests/stadium2_model_parity_audit.lua --species=181,200,238,245 --report
STADIUM2_ROM=/path/to/stadium2.z64 lua tests/stadium2_dsm4_roundtrip_audit.lua
STADIUM2_ROM=/path/to/stadium2.z64 lua tests/stadium2_dual_texture_material_audit.lua
love tests/stadium2_shader_audit
```

The dual-texture material audit disassembles the `0x81000048` ROM family
contract and compares its allocation, texture pointers, tile scroll math,
repeat sampler, two-cycle combiner, callback ownership, and complete source
payloads against every family consumer. A valid route with substituted or
truncated pixels is a parity failure.

Omit `--report` in CI to return a failing status while semantic losses remain.
Misdreavus additionally locks its ASM-derived reference topology and six
phase-5 routes so broad pointer scans or reversed callback ownership cannot
silently return.

Battle models advance from the real presentation clock rather than the
speed-scaled game-logic clock. Fast-forward therefore does not change the
authored animation, texture, or callback speed.

Exports include:

```text
configure(options)
status()
available(count)
modelsEnabled()
battleEnabled()
battleStatus(battle)
configureGame(game)
presentation
newBattleActor(side, options)
newBattleScene(options)
autoImport()
beginFrom(bytes, label)
beginPath(path)
request()
modelPath(species, variant)
readPack(species, variant)
parsePack(bytes)
loadModel(species, variant)
newRenderer(species, variant, options)
releaseModels()
readHandlers(species, variant)
handlerInfo(address)
evaluateHandler(record, phase, runtime)
runHandlers(records, phase, runtime, state)
runModelHandlers(species, variant, phase, runtime, state)
resolveHandlerPointer(extension, pointer, length)
shinyPalettesFromTransformSource(source)
```

A renderer instance supports:

```text
setAnimation(indexOrName, loop)
setMove(moveNumber, loop)
setContext(name, loop)
setHandlerRuntime(runtime)
seekFrame(frame)
step(dt)
worldMetrics()
drawScene(pass, modelMatrix, options)
drawShadowMap(modelMatrix, lightViewProjection)
renderToCanvas(width, height, options)
draw(x, y, width, height, options)
release()
```

The standalone model renderer and battle presentation are available in both generations. The project contains no bundled third-party runtime tree: Gen 1 and Gen 2 presentation are implemented by this mod and share the same owned actor/scene renderer.

## Battle presentation API

`mod.exports.presentation` is the generation-neutral rendering layer used by the adapters. It exposes `newActor`, `newScene`, `setBattler`, `removeBattler`, `sendOut`, `useMove`, `hit`, `faint`, and `update`, plus the `Actor`, `Scene`, and `Camera` types. A separate battle mod can therefore use imported Stadium models without depending on either built-in generation adapter. The caller remains responsible for battle meaning; the presentation API never resolves gameplay.

## Interactive model viewer

Run from the Gen1Recomp repository root after installing/importing the Stadium 2 models:

```bash
POKEPORT_DRIVER=mods/STADIUM2_IMPORTER/tests/stadium2_model_viewer_driver.lua \
POKEPORT_TOUCH=0 \
love .
```

The viewer contains 502 entries in paired order: species normal, species shiny, then the next species. Left and Right move one entry at a time and wrap around. S, Up, or Down toggles normal/shiny. Q/E, PageUp/PageDown, or [/] browse every extracted animation for the current model. Space pauses animation. The mouse wheel zooms, left-drag moves the model in screen space, right-drag orbits it manually, and R restores automatic framing. Home and End jump to the first and last entries. Escape closes the viewer. The selected model slowly rotates when it is not being manually orbited. The viewer temporarily raises Gen1Recomp's tool-state surface limit so the model is rendered at the actual framebuffer resolution instead of the normal low-resolution Game Boy UI surface. Model rendering uses corrected Stadium vertical orientation, visible-triangle bounds, linear texture filtering, anisotropic filtering, multisampling, and adaptive supersampling. If a complete 251-species cache is not present, the viewer requests the normal importer flow and displays its progress.
## Battle viewer test

Run from the Gen1Recomp repository root:

```bash
POKEPORT_DRIVER=mods/STADIUM2_IMPORTER/tests/stadium2_battle_viewer_driver.lua \
POKEPORT_TOUCH=0 \
love .
```

The battle viewer draws two imported Stadium 2 models at fixed near-player and far-opponent battle positions with no free camera controls. Both sides play their extracted animations. Tab, Up, or Down changes the selected side; Left/Right changes that side's species; S toggles normal/shiny; Q/E, PageUp/PageDown, or [/] cycles that side's extracted animations; Space pauses both models; 1/2 select player/foe directly; Home/End jump to species 1/251; Escape closes the test.
