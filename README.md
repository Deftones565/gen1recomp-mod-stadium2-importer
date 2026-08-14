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

The same renderer is used by the normal and Watercolor Manga styles on desktop and mobile. It supports animated textures, per-model effects, normal and shiny palettes, alpha materials, additive effects, model and ground shadows, and adaptive graphics fallbacks for mobile GPUs.

Battle animations advance from presentation time, so fast-forward does not alter their intended speed. Changing shader style or enabling models does not require rebuilding the imported packs.

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

`presentation` is a generation-neutral rendering layer with `newActor`, `newScene`, `setBattler`, `removeBattler`, `sendOut`, `useMove`, `hit`, `faint`, and `update`, plus the `Actor`, `Scene`, and `Camera` types. Callers remain responsible for battle logic.
