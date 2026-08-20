# Pokemon Stadium 2 Importer

`STADIUM2_IMPORTER` brings Pokemon Stadium 2 models and a complete 3D battle presentation to Gen 1 and Gen 2 games in Gen1Recomp. It includes normal and shiny models, skeletal and texture animation, model effects, shadows, battle stages, a perspective camera, and a Stadium-style HUD.

The mod supports the US Pokemon Stadium 2 ROM with MD5:

```text
1561c75d11cedf356a8ddb1a4a5f9d5d
```

## ROM setup

The release does not include a Pokemon Stadium 2 ROM. Use your own legally dumped US copy.

Install and enable the unmodified release through the Mod Manager. The launcher
will show the required **Pokemon Stadium 2 (USA) ROM** import. Select your ROM
there; `.z64`, `.v64`, and `.n64` byte orders are accepted. The launcher
normalizes the selected file, validates its size and MD5, and privately copies
the canonical result to this mod's scoped `baseroms/stadium2.z64` location.

Do **not** add a ROM to the release ZIP or distribute a modified ZIP containing
one. Mod archives are not allowed to contain files beneath `baseroms/`; ROMs
must go through the launcher's required-import flow.

## First import

Start the game after completing the required ROM import. If its model cache is missing or outdated, the importer starts automatically and shows progress for scanning, models, animations, and normal and shiny packs. Gameplay remains paused until the import finishes.

The number of models is selected automatically. A standard Gen 1 game imports 151 species; Gold or a compatible 251-species setup imports all 251. All 26 Unown forms are included in normal and shiny variants.

If import does not start, confirm that:

- The Mod Manager shows the required Stadium 2 ROM import as complete.
- Its MD5 is `1561c75d11cedf356a8ddb1a4a5f9d5d`.
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
createModel(species, variant)
createSpecialModel(name)
releaseModel(model)
newRenderer(species, variant, options)
newRendererFromModel(model, options)
releaseModels()
readHandlers(species, variant)
handlerInfo(address)
evaluateHandler(record, phase, runtime)
runHandlers(records, phase, runtime, state)
runModelHandlers(species, variant, phase, runtime, state)
resolveHandlerPointer(extension, pointer, length)
shinyPalettesFromTransformSource(source)
scene
models
getActiveBattleScene()
registerBattleSceneExtension(mod, phase, callback, priority)
```

`presentation` is a generation-neutral rendering layer with `newActor`, `newScene`, `setBattler`, `removeBattler`, `sendOut`, `useMove`, `hit`, `faint`, and `update`, plus the `Actor`, `Scene`, and `Camera` types. Callers remain responsible for battle logic.

### Choosing an integration

The current API separates model ownership from scene ownership. A consuming mod
can use only the part it needs:

| Goal | API to use | Who owns the surrounding scene? |
| --- | --- | --- |
| Put Stadium Pokemon into a voxel arena, model viewer, or custom renderer | `exports.models` API v2 | The consuming mod |
| Build a completely separate battle presentation from Stadium actors and cameras | `exports.presentation` | The consuming mod |
| Add to or replace parts of the importer's active battle scene | `exports.scene` | Stadium, with registered extension phases |
| Inspect or mutate raw DSM data with independent ownership | `models.create`, `models.parsePack`, or `models.createSpecial` | The consuming mod |

Declare the importer in the consumer's manifest so its exports are initialized
first. Use `optional_dependencies` when the consumer has a fallback, or
`dependencies` when it cannot run without Stadium assets:

```json
{
  "optional_dependencies": ["STADIUM2_IMPORTER"]
}
```

Feature-detect the API at runtime rather than assuming that every installed
version has the newest capabilities:

```lua
local handle = mod.find("STADIUM2_IMPORTER")
local stadium = handle and handle.exports
local models = stadium and stadium.models

if models and models.apiVersion >= 2 then
  local capabilities = models.capabilities()
  if capabilities.sceneNeutralDraw then
    -- Safe to create independently owned instances for this mod's scene.
  end
end
```

The model API does not require `STADIUM 2 BATTLE` to be enabled. A custom scene
normally leaves `STADIUM 2 MODELS` on and `STADIUM 2 BATTLE` off so only one mod
owns the complete battle presentation. The live `exports.scene` extension API,
on the other hand, applies while Stadium owns and draws its battle scene.

### Model API

`exports.models` is the stable model namespace. A model created with `create` is an independent DSM model instance. The consuming mod may inspect or modify its bones, primitives, materials, textures, animations, and handler data. It owns that instance and must release it when finished:

```lua
local stadium = assert(mod.find("STADIUM2_IMPORTER"), "Stadium 2 Importer required").exports

local model, err = stadium.models.create(25, "shiny")
assert(model, err)

-- The model is this mod's private instance and may be changed in place.
for _, primitive in ipairs(model.prims) do
  primitive.decal = true
end

local renderer, renderErr = stadium.models.newRendererFromModel(model, {
  textureFilter = "nearest",
  anchorTravel = true,
})
assert(renderer, renderErr)

-- Later, after the last renderer using the model is gone:
renderer:release()
stadium.models.release(model)
```

`models.load` is the older fast path. It returns a borrowed, importer-cached model and should be treated as read-only. Do not release or retain that value across `releaseModels()`. `models.create` is the correct API whenever a mod needs unrestricted ownership or mutation. Releasing a renderer does not release its model.

`models.readPack` returns the original DSM bytes, and `models.parsePack` parses caller-supplied DSM bytes. A model returned by `parsePack` is also caller-owned and can be released with `models.release`.

`models.createSpecial(name)` provides the same independent ownership for special battle packs such as `substitute`, `unown_b`, and `unown_b_shiny`. A borrowed model from `models.load` is deliberately rejected by `models.release`, preventing one mod from invalidating the importer's shared textures.

#### Scene-neutral model instances

`models.apiVersion == 2` adds the recommended integration path for voxel stages, custom battle scenes, model viewers, and other 3D mods. `newInstance` owns an independent mutable model and its renderer as one object. It does not depend on Stadium's battle scene, camera, stage, or HUD:

```lua
local stadium = assert(mod.find("STADIUM2_IMPORTER"), "Stadium 2 Importer required").exports
local models = stadium.models
assert(models.apiVersion >= 2, "Stadium model instance API v2 required")

local pikachu, err = models.newInstance(25, "normal", {
  textureFilter = "nearest",
  anchorTravel = true,
})
assert(pikachu, err)

-- These helpers understand DSM animation contexts, move IDs, and authored
-- 30 Hz animation timing. A numeric animation index also works with :play().
assert(pikachu:play("idle", true))

function update(dt)
  pikachu:update(dt, {weather="clear"})
end

function drawVoxelScene(camera, sunShadow)
  local modelMatrix = models.matrix.transform({
    position = {12, 0, -8},
    rotation = {0, math.rad(35), 0},
    scale = 0.01,
  })

  -- The voxel mod binds its own color/depth target first. Stadium draws both
  -- opaque and additive model materials into that existing 3D scene.
  assert(pikachu:draw({
    modelMatrix = modelMatrix,
    camera = {
      view = camera.view,
      viewProjection = camera.viewProjection,
    },
    light = {
      direction = {-0.4, 0.8, 0.25},
      ambient = {0.38, 0.40, 0.48},
      diffuse = {0.95, 0.90, 0.82},
    },
    shadow = sunShadow and {
      map = sunShadow.map,
      viewProjection = sunShadow.viewProjection,
      texel = sunShadow.texel,
    } or nil,
  }))
end

function unload()
  pikachu:release() -- releases both renderer and independently owned model
end
```

Use `instance:playContext(name, loop)`, `playAnimation(nameOrIndex, loop, auxIndex)`, or `playMove(moveId, loop)` when the animation source should be explicit. `seekFrame(frame)` supports inspection tools; `animationState()` and `isFinished()` expose playback state; and `metrics()`, `bounds()`, or `geometryAnchor()` support placement. To cast the model into a custom shadow map, bind that target and call `instance:drawShadow({modelMatrix=..., lightViewProjection=...})` before the color pass.

Matrices are row-major and multiply column vectors; a clip transform is `projection * view * model`. `models.matrix` provides `identity`, `multiply`, `perspective`, `lookAt`, `orthographic`, translation/rotation/scale constructors, `compose`, `transform`, and `normalFromModel`. `transform` builds `translation * rotationZ * rotationY * rotationX * scale` and accepts angles in radians.

`newInstanceFromModel(model, options)` renders a model already created or parsed by the caller. It leaves that model caller-owned unless `options.takeOwnership == true`; transferring ownership means `instance:release()` also calls `models.release(model)`. Perform structural model edits before calling `newInstanceFromModel`, because renderer meshes are built when the instance is created. `instance:model()` and `instance:renderer()` are explicit escape hatches for creators who need raw DSM data or renderer features beyond the stable facade.

Call `models.capabilities()` (or inspect `exports.modelCapabilities`) instead of guessing which optional features an installed version supports. `draw` accepts `pass="opaque"` or `pass="additive"` when a custom render graph needs separate passes; the default `pass="all"` draws them in that order. The API restores normal graphics state, but deliberately keeps the caller's render target bound.

### Battle scene extension API

`exports.scene` exposes the live owned scene without taking battle mechanics away from the game. `scene.current()` returns the active Gen 1 or Gen 2 Stadium scene, `scene.actor(side)` returns its `player` or `enemy` actor, and `scene.register` installs a phase callback owned by the consuming mod.

Declare `STADIUM2_IMPORTER` in the consuming mod's `optional_dependencies` (or `dependencies` when it cannot operate without these assets). This ensures its exports are initialized before the consumer looks them up.

```lua
local stadium = assert(mod.find("STADIUM2_IMPORTER"), "Stadium 2 Importer required").exports

local unregister = stadium.scene.register(mod, "environment", function(next, ctx)
  local g = ctx.graphics

  -- Draw a complete custom arena into the already-bound color/depth target.
  drawMyEnvironment(g, ctx.camera, ctx.world, ctx.target)

  -- Environment callbacks must return screen-space marks for the two battlers.
  -- Reusing these keeps Stadium's HUD aligned with its standard actor slots.
  return ctx.marks
end, 100)
```

The callback uses the engine hook convention `function(next, context)`. Calling `next(context)` composes with lower-priority providers and eventually runs Stadium's default for phases that have one. Omitting `next` takes complete control of that phase. The returned `unregister` function removes the callback. Hook failures are attributed to the consuming mod and safely fall through to the next provider.

Available phases are:

- `camera`: return a camera frame containing `view`, `projection`, `viewProjection`/`vp`, `eye`, `focus`, and `letterbox`.
- `background`: paint or replace the sky/background.
- `environment`: paint or replace the stage and return `{ player=mark, enemy=mark }` screen-space anchors.
- `geometry`: add arbitrary world-space geometry after the stage.
- `shadow`: during `context.shadowPhase == "cast"`, add geometry to the shared shadow map.
- `battlers`: during `prepare`, return a mode for each side; during `draw`, render provider-owned battlers and report which sides were drawn.
- `overlay`: draw the last in-scene 3D/2D layer before the Stadium HUD is built.

Every context contains `graphics`, `target`, `camera`, `world`, `environment`, `marks`, and `scene`. `context.scene.host` is the concrete live scene, `context.scene.actors` contains its model actors, and `context.scene.game`, `screen`, and `battle` expose the presentation owners. The importer restores the render target, shader, depth, culling, blend mode, and color after every phase, and wraps each callback in a graphics-state push/pop when supported.

To replace only one battler while keeping the other Stadium model:

```lua
stadium.scene.register(mod, "battlers", function(next, ctx)
  if ctx.battlerPhase == "prepare" then
    return { sides={ player="host", enemy="provider" } }
  end

  drawMyEnemy(ctx)
  return { drawn={ player=false, enemy=true } }
end, 100)
```

Battler modes are `host` (Stadium draws its model), `provider` (the extension draws it), and `native` (the game may draw its normal sprite). If a provider requests a side but does not report it drawn, Stadium safely falls back to its model. `battleSceneCapabilities` remains available for feature detection, and contains the exact raw hook names for mods that prefer `mod.hooks:wrap` directly.
