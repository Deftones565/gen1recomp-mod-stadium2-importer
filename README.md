# Pokemon Stadium 2 Importer

`STADIUM2_IMPORTER` brings Pokemon Stadium 2 models and a complete 3D battle presentation to Gen 1 and Gen 2 games in Gen1Recomp. It includes normal and shiny models, skeletal and texture animation, model effects, shadows, battle stages, a perspective camera, and a Stadium-style HUD.

The mod supports the US Pokemon Stadium 2 ROM with MD5:

```text
1561c75d11cedf356a8ddb1a4a5f9d5d
```

## ROM setup

The release does not include a Pokemon Stadium 2 ROM. Use your own legally dumped US copy.

The recommended setup is to place the ROM at this exact path inside the mod:

```text
baseroms/stadium2.z64
```

For a downloaded release ZIP:

1. Open the downloaded `STADIUM2_IMPORTER` release ZIP with an archive manager.
2. Open the empty `baseroms` folder included in the archive.
3. Add your ROM as `stadium2.z64`.
4. Install the modified ZIP through the game's mod manager.

Do not add an extra folder around the release contents. The archive should look like this:

```text
STADIUM2_IMPORTER-<version>.zip
├── manifest.json
├── main.lua
├── lib/
└── baseroms/
    └── stadium2.z64
```

If the mod is already extracted, use the same location relative to the mod folder:

```text
STADIUM2_IMPORTER/baseroms/stadium2.z64
```

The following filenames are recognized at either the mod root or inside `baseroms/`:

```text
Pokemon Stadium 2 (USA).z64
Pokemon Stadium 2 (USA).n64
Pokemon Stadium 2 (USA).v64
pokemon_stadium_2.z64
pokemonstadium2.z64
stadium2.z64
```

Use one of these filenames exactly, including capitalization. The filename only helps the mod locate the file; the ROM is validated by content, so renaming an unsupported revision will not make it compatible.

## First import

Start the game with the mod enabled after placing the ROM. If its model cache is missing or outdated, the importer starts automatically and shows progress for scanning, models, animations, and normal and shiny packs. Gameplay remains paused until the import finishes.

The number of models is selected automatically. A standard Gen 1 game imports 151 species; Gold or a compatible 251-species setup imports all 251. All 26 Unown forms are included in normal and shiny variants.

If import does not start, confirm that:

- The ROM is inside the installed mod, preferably at `baseroms/stadium2.z64`.
- Its MD5 is `1561c75d11cedf356a8ddb1a4a5f9d5d`.
- The ZIP has `manifest.json` at its root and is not wrapped in another directory.
- The mod is installed and enabled for the current game.

## Options

- `STADIUM 2 MODELS` enables imported Stadium models. Disabling it preserves the generated model cache.
- `STADIUM 2 BATTLE` enables the complete Stadium battle presentation. The underlying game still controls battle rules, damage, turn order, switching, capture results, menus, and RNG.
- `MODEL SHADER` selects the original `STADIUM` lighting or the `WATERCOLOR MANGA` style. Changes apply to existing battle models immediately.
- `BATTLE AA` selects `OFF`, `2X`, or `4X` supersampling for the 3D arena while keeping the native interface crisp. The selected level is limited automatically by the device's texture support.
- `DRAW HUD PANELS` enables or hides the frosted panels behind the Stadium status cards.

## Battle camera controls

- Move the mouse to orbit and pitch the camera.
- Use the mouse wheel or `Q` and `E` to zoom.
- Use the controller right stick to control the camera.
- Press `0` to reset the view.
- On touchscreens, drag with one free finger and pinch with two. Touches that begin on virtual controls remain assigned to those controls.

## Rendering and compatibility

Desktop uses the full Stadium and Watercolor Manga shaders. Android uses the
simpler Stadium lighting path for stable model detail on GLES hardware. Both
paths support animated textures, per-model effects, normal and shiny palettes,
alpha materials, additive effects, and adaptive graphics fallbacks.

Battle animations advance from presentation time, so fast-forward does not alter their intended speed. Changing shader style or enabling models does not require rebuilding the imported packs.

## Blender GLB export

The importer can convert parsed normal, shiny, Substitute, and Unown models to
glTF 2.0 binary (`.glb`). Each file contains embedded PNG textures, mesh
primitives, vertex colors, UVs, a standard glTF skin, and all named skeletal
animation clips. Stadium material, texture-animation, callback, decal,
billboard, and effect information is retained in `extras.stadium2`; the source
DSM4 pack is also embedded so Stadium-specific data is not discarded.

For repository development, run the dumper from the Gen1Recomp root:

```text
luajit mods/STADIUM2_IMPORTER/tests/dump_glb.lua \
  --rom mods/STADIUM2_IMPORTER/baseroms/stadium2.z64 \
  --output mods/STADIUM2_IMPORTER/build/glb \
  --species 25 --variant normal
```

Omit `--species` to dump the complete bank. Use `--count 251` for Gen 2,
`--variant normal`, `shiny`, or `both`, and `--validate-only` to encode without
writing files. Generated files under `build/` are ignored by Git and never
included in mod releases.

Inside the sandbox, `exportGLB(species, variant, options)` and
`exportSpecialGLB(name, options)` return the GLB bytes and an export summary.
They do not attempt unrestricted filesystem access.

### Using edited GLBs in-game

Export the edited model from Blender as a binary glTF (`.glb`) with textures
embedded, then place it in one of these mod paths:

```text
models/025-normal.glb
models/025-shiny.glb
models/normal/025.glb
models/shiny/025.glb
models/substitute.glb
models/special/substitute.glb
```

The three-digit number is the Pokédex number. A packaged GLB overrides the
matching model extracted from the Stadium 2 ROM. If no matching GLB is
packaged, or no special-model override exists, the importer continues using
its DSM4 cache normally.

The runtime loader supports embedded PNG images, indexed triangle primitives,
vertex colors, UVs, normals, four-joint weighted skins, inverse bind matrices,
and translation, rotation, and scale animation channels. Blender may remove
the exporter-specific `extras.stadium2` metadata when it writes a GLB; in that
case the importer restores Stadium callbacks, material routing, and battle
animation routing from the matching DSM4 cache while keeping the edited GLB's
geometry, skin, textures, and animations. The Stadium 2 ROM is therefore still
required for a normal in-game import.

For quick development testing, place any binary GLB in:

```text
build/glb-drop/
```

The two-Pokémon visual test uses the first GLB in that directory as the enemy
model, regardless of its filename. `STADIUM2_VISUAL_GLB=/path/to/model.glb`
selects a specific file instead. Dropped models can be ordinary static Blender
objects or skinned animated characters; Stadium-specific extras are optional.
Images must be embedded in the GLB and mesh primitives must use triangles.

Run the drop-in viewer from the Gen1Recomp root:

```text
GEN1RECOMP_ROOT=/opt/git/gen1recomp \
love mods/STADIUM2_IMPORTER/tests/stadium2_koffing_croconaw_visual
```

## Integration API

Other mods can access the importer through `mod.find("STADIUM2_IMPORTER").exports`. The public exports include:

```text
version
US_MD5
FORMAT
configure(options)
status()
available(count)
modelsEnabled()
battleEnabled()
shaderStyle()
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
loadGLB(bytes, options)
loadModel(species, variant)
newRenderer(species, variant, options)
exportGLB(species, variant, options)
exportSpecialGLB(name, options)
releaseModels()
readHandlers(species, variant)
handlerInfo(address)
evaluateHandler(record, phase, runtime)
runHandlers(records, phase, runtime, state)
runModelHandlers(species, variant, phase, runtime, state)
resolveHandlerPointer(extension, pointer, length)
shinyPalettesFromTransformSource(source)
```

`presentation` is a generation-neutral rendering layer with `newActor`, `newScene`, `setBattler`, `removeBattler`, `sendOut`, `useMove`, `hit`, `faint`, and `update`, plus the `Actor`, `Scene`, and `Camera` types. Callers remain responsible for battle logic.
