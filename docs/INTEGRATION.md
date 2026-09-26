# Stadium 2 Importer: developer reference

Technical notes moved out of the README: rendering and UI compatibility, the
integration API for other mods, the custom battle presentations, tests and
tools.

## Rendering and compatibility

Battle motion follows the host's presentation boundaries: actual move-script
starts select the species' Stadium move row, direct impacts select the hit
context, and fainting cannot be interrupted by either. Repeated and called
moves use the same playback path rather than menu-selection detection.

The Pokédoll is ROM record 252; record 253 is the Egg. Cache format S2IMP54
invalidates the previously misidentified asset, so existing installations must
reimport their Stadium 2 ROM after updating.
Substitute uses the imported doll model. Creation waits for the native swap;
Gen 2's drop/raise commands temporarily expose the Pokemon for its move. Doll
damage and break transitions follow queued presentation state, without parsing
localized battle messages. Transform changes only the presented model, while
Minimize and Fly/Dig respect the native visual state. Native move effects remain
the host engine's responsibility; this does not create new move-effect assets.

Regression coverage includes `stadium2_move_triggers_test.lua`,
`stadium2_substitute_timeline_test.lua`, and `stadium2_model_motion_test.lua`.
Live battle verification is still
required before claiming exhaustive move/species compatibility.

The same renderer is used by the normal and Watercolor Manga styles on desktop and mobile. It supports animated textures, per-model effects, normal and shiny palettes, alpha materials, additive effects, model and ground shadows, and adaptive graphics fallbacks for mobile GPUs.

Battle animations advance from presentation time, so fast-forward does not alter their intended speed. Changing shader style or enabling models does not require rebuilding the imported packs.

Stadium keeps its original widescreen glass-panel UI, but ownership is attached
to Gen1Recomp's official `battle.status_hud_visible` and
`battle.bottom_ui_visible` hooks. Each region is claimed independently: if
another UI provider returns `false`, Stadium omits its corresponding captured
HUD, glass panel, paper-key treatment, or lower panel while leaving the 3D
scene, models, camera, effects, and battle logic untouched. Pixels contributed
through `battle.overlay` remain in the engine-authored centred layer when a
foreign UI owns those regions.

`BATTLE HUD` can also disable Stadium's glass status cards and lower
panel chrome without disabling the 3D arena, models, camera, or effects. The
native game UI (or another provider) remains available underneath.

Modern UI Suite's Battle Info HUD enhances the native status data inside
Stadium's HUD capture, retaining Stadium's detached placement. Its
Typed Move Colors component claims the lower move area through the official
`battle.bottom_ui_visible` hook on Gen 2. Suite 0.1.23's Gen 1 renderer instead
wraps native text drawing directly; Stadium follows that wrapper's live
ownership predicate so its glass backing also yields for replacement commands,
dialogue and move selection, including live option and layout changes.

Gen 2 Suite status labels are added inside the HUD capture, within the detached
card bounds. The Gen 1 Quality of Life instance-draw adapter collects late HUD
ink once, moves status pixels with the cards, and retains other pixels in the
native layer. Replacement status owners suppress those late status pixels.
Gen1 Modern UI receives a `gen1ModernUi.battle.native3d` contract through its
public adapter registration, so its default 3D-bypass setting recognizes Stadium.
Other UI mods are never modified.

For future integrations, `exports.battleUI` describes three hooks:

- `battle.status_hud_visible`: return `false` while replacing the complete status
  HUD; Stadium omits its captured cards and their backing.
- `battle.bottom_ui_visible`: return `false` while replacing command, move or
  dialogue UI; Stadium omits the corresponding glass backing.
- `battle.ui.status_overlay.v1`: draw native-coordinate status enhancements
  inside Stadium's HUD capture. Call `next(state)` to preserve other providers.
  This pass runs only when Stadium owns the status region. Use `battle.overlay`
  for effects that should remain in the battlefield, and `render.hud` for an
  independently positioned replacement UI.

Visibility decisions must be live and specific to the region actually drawn.
Installing a UI mod alone must not suppress native prompts. Arbitrary future
mods that bypass these hooks need their own compatibility adapter.

The installed Gen 3 Inspired UI exposes a live `uiOwnership.ownsBattleUi`
contract as well as the visibility hooks. Stadium respects that contract,
including explicit native-UI hiding and full-frame-provider deferral. Older
versions without the contract retain a narrow, option-aware fallback.

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
battleFxCatalog()
battleFxResource(resourceId)
battleFxResources(moveId)
battleFxShape(moveId, shapeId)
battleFxShapeModel(moveId, shapeId)
battleFxProgram(moveId, alternate, context)
newBattleFxPlayer(options)
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

The battle-FX APIs decode resources from the user's private Stadium 2 cache.
`newBattleFxPlayer` owns a persistent 30 Hz presentation runtime and accepts
injected placement/native/lifecycle resolvers; call `release()` when its scene
ends. The built-in Gen 1 and Gen 2 battle adapters use this API only when the
default-off **MOVE EFFECTS (BETA)** option is enabled.

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

The model API does not require `3D BATTLE SCENE` to be enabled. A custom scene
normally leaves `3D POKEMON MODELS` on and `3D BATTLE SCENE` off so only one mod
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

Stadium 2 does not store human-readable names in its pose records, so the importer does not infer meaning from a clip's position. It reads the battle overlay's per-species dispatch record instead. ROM entry `251` selects idle, `252` entrance, `253` faint, `254` hit/damage, and `268` the looping sleep pose. Other non-move entries remain named `rom_context_ID` until their battle call sites prove a meaning. An otherwise unclassified animation is named `attack` only when at least one ROM move entry routes to it.

`models.contextSelector(model, name)` and `models.moveSelector(model, moveId)` expose the normalized zero-based selector in the exported animation list. `contextIndex` and `moveIndex` return its one-based playable index. The ROM-only TSV audit retains Stadium's original selector values for low-level comparison.

Per-move body-animation routing is read directly from Stadium 2's ROM-authored per-species dispatch records. `playMove(moveId)` supports all 251 Gen II move IDs, and each parsed animation exposes the one-based move IDs routed to it as `animation.moveIds`. No animation names or move relationships are inferred from another mod.

Dispatch record `0` belongs to species `1`, while the model and pose archives retain their record-zero placeholder. Stadium's per-species dispatch records use two authored selector layouts. Some index pose files directly from `0`; others reserve runtime selector `0` for the model's default pose and address external files as `1..N`. The importer derives the layout from each species' complete ROM dispatch domain and pose-file count, then exposes a normalized zero-based selector. It does not assume one global offset or infer faint/hit from clip order.

To export a readable ROM-only report grouped by Pokémon, body clip, auxiliary clip, move ID, and the move name stored in Stadium 2, run this from the Gen1 recomp repository root:

```sh
STADIUM2_ROM=mods/STADIUM2_IMPORTER/baseroms/stadium2.z64 \
STADIUM2_ANIMATION_DISPATCH_OUT=stadium2_animation_dispatch.tsv \
luajit mods/STADIUM2_IMPORTER/tests/stadium2_animation_dispatch_audit.lua
```

The visual model viewer also shows the current clip's compacted `ROM move IDs` in its debug panel.

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

### Kenney woodland battle presentation

Select **BATTLE ENVIRONMENT → KENNEY NATURE** in the mod options. Grass
encounters and outdoor trainer battles use a textured woodland clearing with
Kenney Nature Kit trees, bushes, flowers, and grass. Tree crowns are rounded
into irregular foliage clusters with smooth normals. Classic remains the default;
water, cave and indoor battles retain their existing presentation. Matching
outdoor encounters take precedence over the experimental contextual trainer
arena option when a battle starts.

The clearing includes watercolor leaf, bark, stone and petal materials, painted
grass/clover, layered foliage, tree shadows in the
existing sun map, a painted cloud sky with time-of-day tint, and a lower camera
angle. Camera providers can still override the shot. Environment providers can
still replace the ground. The scene is currently 348,850 triangles batched into
one static mesh, with a second draw for scenery shadows and a separate sky dome, three mipmapped images,
plus one RGBA8 watercolor target. This version prioritizes appearance; mobile
performance has not been benchmarked. Assets load lazily and remain cached between Nature battles. See `assets/kenney_nature/README.md` for sources, license, and rebuild steps.

From the game root, run `luajit mods/STADIUM2_IMPORTER/tests/stadium2_nature_test.lua`
for routing, deterministic layout, options and camera checks. The live Crystal
visual driver is `mods/STADIUM2_IMPORTER/tests/drivers/gen2_nature_visual.lua` and
requires an imported Crystal ROM and ready Stadium model cache.

The woodland now surrounds the clearing, with tall trees outside the camera
orbit and lower plants around the fighting lane. A Kenney Survival Kit wooden
trail shelter sits in the outer foreground area. The ground extends to a distant
apron instead of ending at the old square boundary. The sky dome uses camera
rotation and projection only: it has no positional parallax when orbiting or
moving the camera. Four cardinal views and a high/zoomed-out view are checked
with the isolated renderer; third-party unrestricted camera ranges remain outside
those checks.

Irregular understory patches now surround tree roots throughout the woodland: bushes,
broad-leaf plants, grass, occasional flowers, and small rocks. The shelter approach
and central fighting lane remain open.


The Kenney scene uses warm directional sunlight and cool hemispheric fill. Its
watercolor manga finish runs on the complete rendered image after antialiasing
and before the HUD, including sky, plants, buildings, flames and Pokémon. Shared
pigment bands, edge-aware color washes, colored ink and subtle paper grain unify
the materials. Lighting is resolved first; the finish preserves warm flame colors,
cool shadows and nighttime blacks. The separate model-only manga pass is disabled
for this presentation to avoid applying the style twice to Pokémon.

Desktop uses nine scene texture samples; Android/iOS use five with simpler
softening. Both use GLES 2-compatible syntax and RGBA8 output without depth reads,
float targets or derivatives. Shader or allocation failure preserves the original
scene. GLES validation and the mobile shader path were tested on a desktop GPU;
physical Android/iOS performance remains unmeasured.

Two irregularly placed wooden torches use the Charmander family's animated flame
textures. Each is a 360-degree point source with six 256×256 radial-depth shadow
faces, packed into a 768×512 atlas. Static nearby scenery is captured once and
rebuilt after window resizing; only moving battlers are redrawn at most 20 times
per second. The two atlases, twelve cached static faces and scratch color target
use about 6.25 MiB, plus depth storage. Both scenery and Pokémon use four filtered
shadow samples with world-space slope bias; filter directions cross cube seams.
Light falls off over 100 world units. Allocation failure preserves unshadowed
point lighting on both scenery and Pokémon.

Three outer tree rings and matching horizon fog conceal the extended ground apron.
Run `luajit mods/STADIUM2_IMPORTER/tests/stadium2_torch_shadows_test.lua` from the
game root for cube projection, static-cache reuse, resize and failure checks.
`tests/drivers/torch_cube_visual.lua` exports an isolated LOVE GPU test (call its
returned function after initializing graphics); it needs no model/ROM data and
checks occluder depth and lit/shadowed receivers in all six directions.

Quick forest optimizations keep nearby trees at full detail and use rounded,
lower-detail variants beyond 150 world units. The scene drops from 482,866 to
348,850 triangles (28% fewer). Flat surfaces skip unused triplanar projections,
and pixels beyond torch range skip shadow filtering. Torch shadow faces outside
the current posed Pokémon bounds are culled conservatively; empty atlas faces
stay cached, including correct cleanup when an actor leaves a face.

The forest mesh, textures, sky, flames and local static shadow caster meshes now
remain in memory between battles. Only dynamic battler shadow state resets.
The large temporary Lua scene-vertex array is discarded after GPU upload; resizing
rebuilds static depth from the retained local caster meshes. Assets are loaded on
the first Nature battle, so later battles avoid that construction cost. Switching
to Classic and ending its scene frees the cache; rebinding the mod or calling the
`releaseEnvironment()` export also frees it. The next Nature battle rebuilds it.
A two-battle renderer check verified zero scenery rebuilds or asset reads on the
second battle, alongside six-direction shadow and resize regression checks.

### Cave presentation

KENNEY NATURE now selects a Modular Cave Kit cavern for dry cave wild and trainer
battles. The scene includes enclosed rock walls, a vaulted ceiling, formations,
rubble, a framed passage and textured stone under the shared watercolor manga
finish. Cool fill and two warm omnidirectional torches keep battlers readable.
Cave geometry is 60,640 triangles and stays cached between battles. Cave and
forest own separate torch-shadow caches, preventing scenery from one leaking
into the other's lighting. Cave-water encounters remain on the existing fallback.

The isolated renderer checks cover portrait, four orbit directions, a raised
camera, a second cached battle and GLES shader validation. Full gameplay and
physical mobile performance still need playtesting. Run
`luajit mods/STADIUM2_IMPORTER/tests/stadium2_cave_test.lua` from the game root
for routing, geometry and cache-state isolation checks.

### Freshwater presentation

Outdoor water/surf/fishing encounters now select a wooded freshwater lake under
KENNEY NATURE. The cached scene uses Nature Kit trees and stones, procedural
cattails, irregular shallows and two low sandbars to support terrestrial battlers.
Its animated watercolor water uses directional ripples and a sky-colored grazing
reflection approximation; there is no additional reflection render target.
Geometry is 57,768 land triangles plus 128 water triangles. The complete scene
receives the existing watercolor finish and day/night tint. Lake scenes do not
render the forest's torches or use its local-light shadow cache.

This is the initial lake composition, shared by surfing and fishing. Dedicated
river layouts, bank-based fishing staging and ocean scenes are future variants.
Indoor/cave water and explicitly classified ocean/sea water retain the existing
fallback. Where no water-body classification is supplied, outdoor water uses the
lake as the initial generic presentation.

Verified with portrait, four orbit views, a raised camera, day/night renders,
GLES validation and a second battle with zero scenery rebuilds or asset reads.
Run `luajit mods/STADIUM2_IMPORTER/tests/stadium2_freshwater_test.lua` from the
game root for routing and geometry checks. Physical mobile performance and full
gameplay still need playtesting.

### Town presentation

KENNEY NATURE selects a suburban town square for dry town encounters outside
explicit grass terrain. Eight City Kit - Suburban homes surround a paved battle
space, with fences, garden planters, flowers, trees and connecting streets. House
palette colors are baked from the source OBJ UVs; shared watercolor textures and
the whole-scene finish unify them with the battlers. The 59,384-triangle mesh is
cached between battles. It uses day/night lighting; street lamps and interiors
are not part of this initial town version. Water and grass encounters in town
retain their lake and woodland selections.

The isolated renderer passed day/night, portrait, four orbit views, raised camera,
GLES shaders and second-battle cache reuse. Full-game and physical mobile testing
remain outstanding. Run `luajit mods/STADIUM2_IMPORTER/tests/stadium2_town_test.lua`
from the game root for routing and geometry checks. Asset sources and conversion
steps are in `assets/kenney_town/README.md`.

Town materials now use a dedicated generated watercolor atlas for plaster,
roof shingles, wood and foliage. Explicit per-triangle classes keep these
materials separate from window/door trim; the original palette still controls
roof colors. The additional atlas is mipmapped and retained with the town cache.

### Testing battle presentations

Use **TEST ENVIRONMENT** to force grass/woodland, cave, freshwater or town on
the next encounter in either game, regardless of the real location or the
BATTLE ENVIRONMENT setting. Entries marked **FALLBACK** are unbuilt and exercise
the Classic/context-arena fallback instead.

**TEST ARENA** selects any of the 30 Stadium arena slots on the next encounter,
including wild encounters, even when context arenas are off. Arena tests take
priority over environment tests. Set both to **AUTOMATIC** to restore normal
selection. Changes take effect on the next encounter; they do not change battle
rules or encounter data. If an arena cannot be loaded, the battle uses Classic.

### Ambient Pokémon visitors

**AMBIENT POKEMON** controls cosmetic visitors in the custom environments:
**NATURAL** (default), **OFF**, or **PREVIEW CAMEOS** for quick testing.
Woodland keeps its resident Caterpie and adds butterflies, bugs, Oddish, Paras,
Pikachu, Eevee and Jigglypuff. Town adds Rattata, Growlithe, Snubbull, Persian
and resting Abra alongside Meowth and birds. Caves have Zubat, Golbat,
Geodude, Clefairy, Gastly and Misdreavus. Lake visitors are flying insects and
birds; land Pokemon are not placed on unsupported open water.

Natural mode rolls once per encounter for a 0.5% Mew cameo and, outdoors,
a separate 0.5% Ho-Oh outcome. Preview cycles the expanded pool every ten
seconds (skipping arrivals while all slots are occupied). Common arrivals are
attempted every 12–22 seconds and may depart after 32–46 seconds, but only
when the entire posed model is off camera. At most three visitors are active;
Caterpie can stay for the encounter.

A conservative collision grid is built from the actual scenery once, with the
cached map. Visitors sweep their full body volume through each movement step,
turn or stop at obstacles, and reserve room for battlers and other visitors.
Animation poses are checked too; an obstructed gesture restores its last safe
frame. Species pause for authored idle, available sleep, entrance or move-dispatch clips
with an idle fallback when unavailable. These are ambient gestures, not attacks
on battlers. The conservative grid can make a visitor wait at a narrow gap.

Visitors use the imported Stadium models and animations, shared watercolor
finish, and scene lighting/shadows. Missing model packs are skipped. They own
no battle state, cannot be caught or targeted, and use an independent RNG.
Their renderers are released when they depart or the battle ends. Test options
can force an environment to preview its visitors on any encounter.

### Scenery visibility optimization

Woodland, cave, town and freshwater scenery retain their original geometry,
materials, resolution and draw order. Static meshes now keep bounded spatial
sections, skipping sections outside each render pass's view. Sun shadows use
the light's view independently, so off-camera scenery still casts visible
shadows. Short gaps are merged to limit draw-call overhead. The sections are
built once with the cached mesh and reused across encounters.

From the game root, run
`luajit mods/STADIUM2_IMPORTER/tests/stadium2_scenery_chunks_test.lua` for
triangle preservation, camera-orbit visibility and submission counts. Run
`love mods/STADIUM2_IMPORTER/tests/drivers/scenery_culling_visual` for 20
pixel comparisons against the original geometry using a flat-colour shader.
These tests verify geometry preservation; sustained Android frame times still
need device profiling with the complete lighting and post-processing enabled.

Repeated woodland trees, grass, bushes and flowers, plus town and freshwater
vegetation, now use shared model meshes and per-instance transforms on hardware
reporting instancing support. Each placement keeps its authored scale, rotation,
colour and material. Camera and sun passes cull each instance independently;
visible placements are batched by model into reusable instance buffers. Cavern
geometry continues to use section culling. Unsupported hardware uses the
original expanded mesh with section culling, with the same visual detail.
Torch static-shadow caches continue to use the baked geometry.

Run `luajit mods/STADIUM2_IMPORTER/tests/stadium2_scenery_instances_test.lua`
from the game root for original-vertex equivalence, capability fallback,
resource reuse and instance counts. The GPU check is
`love mods/STADIUM2_IMPORTER/tests/drivers/scenery_instancing_visual`;
it checks five views per scene and executes the production day/night and
sun-shadow shaders. Instanced GPU transforms and equal-depth overlaps can
produce isolated edge-pixel differences; the separate static-culling test
still requires exact pixels. No texture, resolution or geometry detail is reduced.

### Preparing maps before encounters

Entering a map now warms the selected environment offscreen, including meshes,
instance buffers, textures, scene/shadow shaders, sky and static point-shadow
maps. When the location declares water, the matching water encounter scene is
prepared too. If the importer is still loading, preparation waits until it is
ready; changing the environment-test option also prepares that selection outside
battle. Classic/arena selections do not preload custom scenery.

The one-time preparation cost occurs on location entry instead of the first
battle draw. Built maps remain cached across encounters and presentation-option
changes. Explicit `releaseEnvironment()` or a mod rebind clears them. This is a
cache of the four supported map types, not one copy per encounter or world map.
Battle actors and battle-specific render targets still have their own lifetimes.

`luajit mods/STADIUM2_IMPORTER/tests/stadium2_environment_cache_test.lua`
checks preparation, reuse, failure backoff and routing. The GPU regression is
`love mods/STADIUM2_IMPORTER/tests/drivers/environment_cache_visual`: it verifies
three encounters per scene allocate no new map meshes, shaders, textures or
canvases after preparation. ROM-backed flame loading is stubbed in that test.

### Render scratch storage

Torch-face visibility now tests transformed clip planes directly, without
allocating a matrix or corner tables for each actor/face. Shadow updates reuse
visibility lists, bounds outputs, light vectors and framebuffer descriptors.
Visitors reuse their render matrices, normal matrices, metrics, draw options
and shadow-input lists; those lists are cleared as visitors leave.

Renderer `poseBounds`, `worldMetrics` and `normalMatrix` accept an optional
output table for internal reuse. Calls without an output table still return
independent results, preserving existing consumer ownership.

Run `luajit mods/STADIUM2_IMPORTER/tests/stadium2_render_scratch_test.lua`
from the game root for reference-visibility comparisons and allocation counts.
Its allocation benchmark disables JIT allocation elision; it measures this
visibility function, not whole-game allocation or Android frame times.

### Android Stadium / watercolor manga choice

**SHADER STYLE** offers **STADIUM** and **WATERCOLOR MANGA** on Android
and desktop, using the existing saved `stadium2_shader` choice. Android's model
shader now implements the manga choice with bounded pigment variation and
silhouette ink in the same material pass. Warm local lights and dark shading
feed the treatment; effect alpha and hit flashes retain their existing paths.

For custom battle environments, this choice also enables or bypasses the
whole-scene manga finish, leaving battle UI unchanged. GLES renderer detection
works without `love.system` in the mod sandbox and selects the five-sample mobile
finish. Stadium bypasses that pass and its allocation. Changing the option does
not rebuild the models or maps. Device-specific Android performance and visual
validation remain necessary.

Run `love mods/STADIUM2_IMPORTER/tests/drivers/android_watercolor` from the game
root to validate GLES shader sources, render both mobile model styles, and check
the scene finish and Stadium bypass with sandbox-style Android detection.

### Lake fireflies

At dusk and night, sixteen small green-gold fireflies drift and breathe in
independent rhythms around the lake. Four brighter motes supply very faint,
26-unit local light to banks, water, imported Pokemon and visitors. The other
motes are decorative. Glows are depth-tested and batched into one reusable
96-vertex mesh. These tiny fill lights do not allocate shadow maps. Daytime
hides the fireflies; leaving the lake disables their lighting.

`luajit mods/STADIUM2_IMPORTER/tests/stadium2_fireflies_test.lua` checks motion,
light limits, daylight gating, RNG isolation and resource reuse. Run
`love mods/STADIUM2_IMPORTER/tests/drivers/fireflies_visual` from the game root
for a night render and mobile shader validation.

Visitor collision checks: run
`luajit mods/STADIUM2_IMPORTER/tests/stadium2_visitor_navigation_test.lua`
from the game root. It exercises actual map occupancy for 90 seconds per
spawned species, plus thin-wall sweeps and obstructed animation restoration.
For imported-model animation validation, set `STADIUM2_PACK_DIR` to the normal
model-pack directory and run
`love mods/STADIUM2_IMPORTER/tests/drivers/visitor_navigation_real`.

Visitors are admitted only after the final camera (including overrides) is
known and their whole model is offscreen. Candidate points must have a clear
exit corridor; if none are available, the arrival is skipped. Caterpie follows
the same rule and waits until its perch is outside the view.

Movement now selects reachable destinations, pauses on arrival and replans
from rest when blocked. Nearby visitors can approach, face one another and
exchange gestures with a cooldown. Ground visitors use explicitly named walk
clips where present; otherwise a visitor-only procedural walk/trot/crawl layer
animates lower-body strides and subtle body motion. Gait phase follows actual
travel distance and stops at rest. Abra hovers instead of sliding in a seated
pose. Procedural gaits are stylized fallbacks, not newly authored skeletal clips.

`stadium2_visitor_locomotion_test.lua` checks alternating strides, stationary
feet and reciprocal greetings. The real-model driver now simulates 60 seconds
of movement and pose collisions for eight species, including six ground gaits.


Scene weather is selected with **SCENE WEATHER: OFF / RAIN / THUNDERSTORM**
(default OFF). It applies to grass, town and freshwater presentations; caves
and classic/arena presentations remain unaffected. Weather is cosmetic and
does not change battle mechanics. Rain uses cool, tapered strokes and small
impact splashes, followed by the selected scene watercolor finish.
Thunderstorms vary between jagged single bolts, forked bolts and branching
lightning across the sky, with soft halos and a single brief illumination of
the sky, scenery and imported Pokemon; no extra shadow pass is rendered.

The system reuses 180 particle slots and one 1,464-vertex mesh. A four-unit
surface-height grid is built with each cached map; rain samples it rather than raycasting every mesh every frame.
Pokemon and visitors do not receive rain splashes.
These are approximate impacts, especially on thin objects.
The effect uses no particle textures, framebuffer readbacks or dynamic shadow
maps. It does not include thunder audio or wet-material simulation.

Run `luajit mods/STADIUM2_IMPORTER/tests/stadium2_weather_test.lua` from the
game root for impact, resource reuse, option and RNG checks. The
`tests/drivers/weather_visual` LÖVE driver validates the mobile shader and
renders a lake storm. Actual Android frame-time measurements are still needed.


Direct engine patches are now session-owned. Disabling Stadium for the active
game, uninstalling it, rolling back a failed load, or ending/replacing the game
session restores the original Gen 1/Gen 2 battle, animation and control methods
and clears the install sentinels. Official hook/event subscriptions and cached
presentation resources are released too. The next enabled game session installs
fresh wrappers; changing another game's checkbox does not stop the active one.
A wrapper retained by a later mod becomes a pass-through, preserving that mod.

The current host has no general mod-unload callback, so `lib/mod_lifecycle.lua`
observes the existing loader, launcher, runtime and session teardown methods.
Those observers are themselves restored during teardown. `mod.exports.uninstall()`
provides the same idempotent cleanup for tools. Regression coverage lives in
`tests/stadium2_patch_lifecycle_test.lua` and both generations' control/ownership
tests, including repeated install/remove and partial-install failure.

## Exporting the original Stadium battle fields

The ROM contains 30 battle-field models in its archive at `0x01638000`. To
dump all of them as OBJ/MTL models with TGA textures, run this from the
Gen1Recomp repository root after importing the ROM:

```bash
luajit mods/STADIUM2_IMPORTER/tools/dump_stadium2_arenas.lua \
  mods/STADIUM2_IMPORTER/baseroms/stadium2.z64 \
  mods/STADIUM2_IMPORTER/stadium2_arena_dump
```

Each `arena_00` through `arena_29` directory also retains its exact packed
PERS-SZP record and decompressed FRAGMENT for further research. `manifest.json`
and `manifest.tsv` record ROM offsets, geometry counts, texture counts, and
bounds. The dump directory is ignored by Git because it contains assets
derived from the user's ROM and must not be distributed with the mod.

## Context arena visual tests

Run the real Gen 2 encounter visual suite from the mod directory:

```bash
./tests/run_context_arena_visuals.sh
```

It starts separate wild, fishing, outdoor trainer, indoor trainer, and Violet
Gym encounters through the live engine. Each case asserts the active arena
state, index, and resolver reason before writing a clean Stadium scene image
and a `-full-window` integration
image to `/tmp/stadium2-context-arenas`. Set
`STADIUM2_ARENA_VISUAL_DIR` to choose another output directory, or
`POKEPORT_GAME=gold` / `silver` to run against a different Gen 2 game.
