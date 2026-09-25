# Stadium 2 arena parity audit

This is a ROM-to-renderer audit of all 30 battle-field records in the supported
US Stadium 2 ROM. It describes what is actually present in the archive, what
the importer currently reproduces, and what still prevents the arena renderer
from matching the intended game result.

Run the repeatable inventory from the `gen1recomp` root:

```sh
lua mods/STADIUM2_IMPORTER/tools/audit_stadium2_arena_parity.lua \
  "Pokemon Stadium 2 (USA).z64"
```

The audit is deliberately ROM-only. Independently dumped OBJs were used only
as a geometry cross-check; they were not treated as rendering instructions.

## Executive result

The arena geometry is not broadly missing. Across the archive the importer
finds 537 primitive batches, 22,033 vertices, 15,136 triangles, 482 ordinary
textures, and 167 callback-owned texture registrations without extraction
warnings. Every available independent arena dump compared so far has the same
triangle count. Classroom (arena 27) contains two deliberately repositioned
vertices in the independent OBJ; the ROM display list and all four source
triangles are now proven intact.

The principal material/state blockers are now implemented: all 36 animated
phase-5 controllers are evaluated, the 25 primitive-LOD combiners have exact
shader inputs, opaque RDP submissions no longer disappear when their unused
combiner alpha is zero, and the renderer has an explicit modern surface policy
for all 537 batches. The ROM's graph root profiles, submission layers, and
post-draw state resets are now decoded as well. The remaining source-parity
question is the exact parent-renderer light for 30 normal-bearing batches.

## What is verified

### Archive and geometry

- All 30 field modules are found in the ROM archive.
- All field roots use the same FRAGMENT geo-layout language as the models.
- The current traversal produces 537 primitive batches and 15,136 triangles.
- There are no geometry animations stored in these field models.
- Available independent dumps match exactly for arenas 00-13 and 28.
- Arena 27 matches 414 of 416 reference triangles exactly. The other two use
  the same topology, but the independent OBJ raises two ROM-authored vertices
  by two units to separate an overlapping floor surface.
- The phase-5 callback descriptor is present at 533 sites.
- The stage transform/colour callback is present at 122 nodes.

### Textures and materials

- 482 ordinary textures and 167 callback texture registrations are decoded,
  including every frame referenced by a phase-5 texture controller.
- The phase-5 callback ABI contains two independent item pointers: `arg[0]`
  supplies TEXEL0 and `arg[1]` supplies TEXEL1. There are 91 valid two-texture
  sites. `item + 0x10` is a dynamic environment-colour track, not TEXEL1.
- The ROM contains 141 unique phase-5 combiner selector sets. Combiner-only
  material records are valid even when primitive/environment colour pointers
  are absent.
- Five phase-5 state sites enable generated texture coordinates; no site uses
  linear texture generation.
- 220 opaque/cutout batches intentionally end in a zero combiner-alpha
  equation. Stadium's opaque RDP blender writes their RGB regardless; this is
  now represented explicitly rather than treating those batches as invisible.
- The 440 local material display lists set tiles and load images, but do not
  establish the final framebuffer render mode. That state is inherited.

### Lighting and effects

- 507 primitive batches carry prelit RGBA vertex values. These must not receive
  a second directional-light calculation.
- 30 primitive batches carry normals and need Stadium's global light state.
- No arena model contains a separate particle callback family, geometry
  animation, `G_FOG`, or local `G_ZBUFFER` enable in its extracted primitive
  state.
- Arena animation/FX in this archive is primarily changing material colours
  and textures through the phase-5 controller.

## Implemented visual-correctness work

### Phase-5 controllers

The runtime now decodes the controller at `item + 4`: period/mode, direct,
linear and polynomial RGBA tracks, primitive LOD fraction, and ROM texture
selection tables. It evaluates those values from Stadium's display/material
frame and feeds the same result to game and viewer rendering. Regression
fixtures cover metadata, intermediate interpolation, LOD, dynamic texture
retention, and selected texture pointers.

Affected arenas: 02-04, 06-07, 13-22, and 26-29.

### Modern blend, alpha, depth, shadow, and decal composition

The field-local lists contain ordinary one-cycle texture loads and inherit
framebuffer policy from the parent battle renderer. The modern backend now
makes that policy explicit: opaque and cutout surfaces establish depth,
translucent and shadow cards never write it, and ROM graph layers are submitted
in ascending order while retaining display-list order inside each layer. A
small depth rank derived from those layers resolves equal-depth surfaces.
Camera-depth sorting and geometric overlap detection are now legacy fallbacks
only for arena packs without graph-layer metadata. Animated phase-5 texture
coverage and material alpha refresh these queues each frame.

The opaque queue also restores source coverage when a phase-5 combiner ends in
the ROM's `(0 - 0) * 0 + 0` alpha equation. This is not generic forced opacity:
it applies only to structurally proven zero-alpha equations in opaque/cutout
arena submissions. Translucent and shadow layers retain their authored alpha.
This affects 220 batches across all 30 arenas.

Tests separately cover opaque floors, cutouts, translucent layers, shadow
cards, live animated texture coverage, and nested coplanar decals.

### Arena 01 ROM audit

Arena 01 is the Azalea Gym field. Its fragment is geometrically complete: four
roots submit 20 primitive batches containing 628 extracted vertices and 423
triangles. Those 423 triangles match the independent field dump exactly. The
apparent missing centre was instead a phase-5 tile-state error.

The main floor at callback `0xD6A4` combines two 32x32 RGBA16 inputs. TEXEL0
(`0x8FF07050`) is one quadrant of the central log-ring mask and uses mirrored
addressing with S/T shift 2, producing one 64x64 mirrored log across the field.
TEXEL1 (`0x8FF07850`) is the fine gravel detail and uses S/T shift 15, repeating
at eight times TEXEL0's coordinate rate. Texture registrations share a callback
site and had been reduced by retaining the final registration, so TEXEL1's
shift was incorrectly baked into the mesh for both inputs. That produced the
grid of many logs shown by the viewer.

Extraction now retains the first phase-5 registration (TEXEL0) as the mesh's
authored tile. Rendering converts each callback input from that coordinate
space using its own ROM sampler, leaving TEXEL0 at scale 1 and TEXEL1 at scale
8. The gravel Poké Ball batches at `0xDA14` and `0xDA3C` remain layer-6 overlays
above the layer-5 log floor and receive the existing coplanar depth separation.
The arena-specific audit locks the complete inventory, pointers, dimensions,
sampler shifts, callback sites, submission layers, and both centre overlays.

The same dual-texture centre contract is used by arenas 02, 04, 09, 10, 11,
12, and 13. Their primary centre images are 32x32 RGBA16 gravel/ground
carriers; their secondary images are 64x64 I4 Poké Ball masks. Each texture
unit owns an independent tile sampler and coordinate rate. Arena 12 happened
to remain visually plausible under the old shared-sampler reduction, but it
does not use a different material system. The ROM audit now identifies every
affected primitive and callback site (including both transformed battle-area
copies in arena 11), verifies both formats and dimensions, and requires the
mesh sampler to match TEXEL0 rather than the final TEXEL1 registration.

The secondary GPU image must also receive that sampler on every draw. The
renderer previously sent TEXEL1's wrap modes to the shader but only configured
the image when the legacy `set.wrap` field existed. Phase-5 uses per-axis
`set.samplers[2]` instead, leaving the host image clamped. On desktop, where
ordinary repeat/mirror addressing uses the GPU sampler, arena 01's quarter-mask
stretched into long strips instead of forming a complete Poké Ball. Both shared
scene and private-canvas rendering now apply the resolved S/T modes to TEXEL1,
including the clamped physical sampler required by shader-emulated mirror-clamp.
Before/after GPU captures reproduce and resolve arena 01's broken centre; the
other seven dual-texture centre arenas were also rendered and inspected.
Submission-time regression checks cover both draw paths and sampler reuse.

Arenas 01, 02, and 04 additionally use the phase-5 combiner family that adds
the submitted vertex `SHADE` in its first cycle. LOVE multiplies mesh vertex
colour by its process-global draw colour, so a colour left behind by viewer or
HUD drawing altered that ROM input and washed the material out while the mask
still remained visible. Stadium has no equivalent global tint at this point:
the callback submits the authored vertex colour unchanged. Both shared-scene
and private-canvas rendering now reset LOVE's draw colour to neutral white
before consuming `VaryingColor`, preserving the ROM combiner inputs. Arenas
09--13 use a different second-cycle equation, which is why that leak was much
less apparent there.

### Arena 03 ROM audit

Arena 03's mode-0 entrypoint returns geo layout `0xBF40`; mode 1 returns field
identifier `1`. Its five graph roots contain 16 primitive batches, 479
vertices, 338 triangles, 14 textures, seven callback textures, 16 phase-5
materials, and five stage transform/colour callbacks.

The animated ground glow is split into primitives 7 and 8. Each is a six-vertex
half-card at exactly `Y=0`, using a separate 64x64 I8 image as both TEXEL0 and
TEXEL1. Both cards use mirrored-repeat addressing and share colour controller
`0xBA58`: over 60 frames it pulses from `(200,230,255,100)` to
`(250,250,255,255)` and back. Their I8 coverage is now restored through the
phase-5 intensity path.

The geometry was complete; its modern depth relationship was not. The base
floor is primitive 3 on ROM submission layer 5, while both glow halves are on
layer 6 and occupy the same plane. The old geometric classifier rejected the
callback-owned surfaces, so the glow used strict depth comparison against the
floor and broke into horizontal strips. The renderer now follows the ROM
directly: layer 5 is submitted first, then both layer-6 halves in their original
display-list order. They receive depth rank 1, accept equal depth, and retain
their animated alpha without writing translucent depth.

The ROM audit locks the entrypoint, field identifier, geometry counts,
floor/glow callback sites, layer 5/6 relationship, exact I8 pointers and
samplers, shared controller, pulse endpoints, and both resolved depth ranks.

### Arena 13 ROM audit

Arena 13's mode-0 entrypoint returns geo layout `0xD940`; mode 1 returns field
identifier `0x45`. The fragment contains five graph roots, 25 primitive
batches, 1,264 vertices, 846 triangles, 19 decoded textures, ten callback
texture registrations, 25 phase-5 callbacks, and five stage transform/colour
callbacks. Twenty-three batches are ROM-prelit and two carry normals. Its root
state is one profile-0 batch and 24 profile-2 batches, divided into eight
class-1, nine class-4, and eight class-6 submissions. Extraction emits no
warnings or unresolved geometry.

Three ordinary, non-callback textures are N64 I4 masks: a 32x32 radial glow, a
64x16 grid/shadow marking, and a 16x16 gradient. The cache deliberately stores
I4 intensity in RGB with opaque host alpha for Pokemon-specific effects. The
phase-5 arena shader was consulting callback format metadata only, so these
ordinary masks became solid quads. It now also consults the active model
texture format and restores `alpha = intensity` only for a phase-5 N64
combiner. This fixes the shaped glow and both masked overlays without changing
Pokemon effects or the shared texture cache.

Callback `0xD660` is the field's sole animated material. It combines two
16x32 RGBA32 flame images, applies the ROM tint `(40,80,120,255)`, and scrolls
only TEXEL1 vertically using tile descriptor `(0,0,0,8,16,32)`. At source
frame 30 that is normalized UV offset `(0,-1.875)`. The generic tile-controller
implementation now reproduces the animation and preserves repeat addressing
for both layers.

The audit also exposed two host queue errors. Primitives 6 and 15 have an
intentionally zero final combiner-alpha equation under an RDP profile which
does not consume that value. Partial vertex alpha had incorrectly placed them
into host blending, where the structural zero discarded every pixel. Zero-alpha
phase-5 submissions now derive only real image coverage and use the
opaque/cutout path. Conversely, primitive 14 is an authored translucent layer;
an opaque callback image no longer overrides that explicit layer and turns it
into a depth-writing opaque draw. Live phase-5 alpha also correctly moves the
large radial glow and two masked callback surfaces into the translucent queue.

The ROM audit locks all counts, the entrypoint and identifier, root
profile/layer split, I4 formats, exact radial-glow combiner, flame controller,
flame tint and frame-30 scroll, dynamic queue decisions, and the 23/2 lighting
split.

### Arena 28 ROM audit

Arena 28's fragment is complete and self-contained. Its mode-0 entrypoint
returns geo layout `0xE318`; mode 1 returns field identifier `0x6CB5`, not a
second model or skybox. The returned layout has four independent graph roots,
25 primitive batches, 658 vertices, 420 triangles, 22 decoded textures, ten
callback texture registrations, 25 phase-5 material callbacks, and four shared
stage transform/colour callbacks. Six phase-5 sites use both texture units, two
have live material/texture controllers, and all 25 batches carry prelit vertex
colour rather than normals. Its modern alpha reduction is 12 opaque, seven
cutout, and six translucent batches before the live water controller moves its
surface into the translucent queue.

The sky and distant horizon are primitive batches 1 and 2. Together they span
ROM coordinates X/Z `-9939..9939` and Y `0..4410`, use two fully opaque 64x32
RGBA16 pale-sky textures, and are submitted at callback sites `0xDDA0` and
`0xDDD0`. Their two-cycle combiner is
`1,3,4,5 / 7,7,7,7 / 31,31,31,0 / 7,7,7,7`: RGB passes textured vertex shade,
while final alpha is intentionally zero. The old host shader discarded both
giant batches, creating the false impression that the ROM omitted the park
skyline. The opaque-RDP coverage fix restores them and applies to the same
material pattern in other arenas.

The extraction audit now locks the entrypoint, root, counts, horizon extent,
texture format/opacity, callback provenance, exact combiner selectors, and the
host coverage decision. A matching arena-specific clear remains only as an
edge fill for free viewer cameras outside Stadium's fixed shot volume.

The pool and fountain are phase-5 effects, not separate particle assets. Pool
callback `0xDE08` submits the same 32x32 I4 image as TEXEL0 and TEXEL1 and its
two ROM tile controllers scroll in opposing directions: `(1,-1)` and `(1,1)`
in 10.2 fixed-point units per frame. Its colour track sets RGB to `28/255` and
alpha to `130/255`. Fountain callback `0xE0A4` combines a static 32x64 I4 layer
with a 32x32 I4 layer whose T tile origin advances by six fixed-point units per
frame. The renderer now evaluates these controllers from the same unsigned
eight-bit frame counter used by the fragment and converts the tile origins to
normalized host UV offsets.

Two omissions caused the broken rectangle and frozen effects. The I4 cache
correctly retained intensity as RGB for the existing Pokemon effect shaders,
but phase-5 N64 combiners also source texture alpha from that same intensity;
forcing cached alpha to 255 therefore exposed the entire water quad. Arena
phase-5 combiners now reconstruct alpha from red only at those I4 texture
inputs. Separately, controller offset `+4` points to the six-halfword animated
tile descriptor; it was previously ignored while only colour and texture-frame
tables were evaluated. ROM-specific audit assertions now cover both pool
scrolls, the fountain scroll, I4 format propagation, animated water alpha, and
the resulting translucent queue.

### Primitive LOD combiner inputs

Twenty-five phase-5 combiners use primitive-LOD selectors. The importer now
decodes the fifth primitive-colour byte and both desktop and mobile shaders
evaluate those selectors directly; they no longer fall through to constants.

## Missing or approximate behavior

### Resolved source discrepancy

#### Classroom's two repositioned triangles

Arena 27 exports the same 416 triangles as the independent dump. The apparent
two-triangle discrepancy is an edit in that dump: two vertices were lifted by
two units, changing both triangles without changing their topology.

The ROM provenance is exact. Fragment display list `0xB318` loads eight
vertices from `0x9CB0` and its two `G_TRI2` commands at `0xB330` and `0xB338`
submit all four triangles. Source vertices `0x9CC0` and `0x9CD0` have Y `-3`;
the independent OBJ places their converted coordinates at Y `-1.5` rather
than the ROM conversion's `-3.5`. Primitive 17 retains material `0x8168`,
phase-5 callback `0xC0C0`, root profile 2, submission class 6, and its post-draw
reset. The renderer therefore keeps the ROM vertices and uses the authored
submission layer to resolve overlap instead of modifying geometry.

The full archive audit asserts these commands and coordinates so this resolved
reference-rip workaround cannot regress into an importer “fix.”

### P1: parity work

#### Recover exact global lighting

`lib/arena_lighting.lua` correctly separates prelit and normal-bearing batches,
but its directional vector and ambient values are a visual approximation. The
field modules contain no local light objects, so the source must be traced from
the parent battle overlay. Three static two-light display lists at fragment-79
VRAM `0x84187660`, `0x84187710`, and `0x841877C0` were audited and rejected as
the answer: their call sites (`0x8415FD8C`, `0x84161018`, and the adjacent third
generator) build procedural 16-by-16 textures rather than submit a field.
Modern shadow mapping is also an enhancement rather than an extraction of
Stadium's stage-shadow state.

Affected arenas with normal-bearing geometry: 02, 04, 06, 12-15, 17-20,
23, and 25-27.

Completion gate: recover ambient/diffuse colours and directions at field draw
time, preserve authored prelighting, and compare representative indoor,
outdoor, and reflective surfaces.

#### Decoded geo-layout render state

The ROM handlers are now identified and implemented. Command `0x09` creates a
plain base graph node. Command `0x0F` creates graph-node type 6 and selects the
root RDP profile through its low three bits: the arena layouts contain 115
profile-2 roots, five profile-0 roots, and two profile-4 roots. Command `0x22`'s
byte 1 selects the child submission class, which Stadium maps to render layers
5-8. Command `0x25` sets graph flag `0x04`; the display-list renderer passes it
to `func_8003DA20`, which calls `func_8003CD84` to reset material/RDP state after
the node.

All three values are retained per exported primitive. Material parsing starts
from the exact `profile x layer` other-mode-low word at ROM table `0x955A4`.
Modern arena submission now uses that ROM layer directly; geometric ordering
is consulted only when older cached data has no layer metadata. The 187 base
nodes, 122 profiles, and 534 post-draw resets are covered by the full archive
audit.

#### Source culling policy

The ROM marks 524 of 537 batches as culled. Arena rendering deliberately keeps
the source bit as metadata but draws fields two-sided: applying source culling
to a free/orbit camera removes assemblies that Stadium's fixed shots never
viewed from behind. This is an intentional modern viewer policy, not missing
extraction.

Optional future fidelity mode: restore per-batch culling only for verified fixed
Stadium shots while retaining the two-sided orbit fallback.

#### Finish the battle camera state machine

Camera presets and arena-scale Pokémon placement are available, but preset
cycling is not the same as Stadium's shot selector. Follow/pan behavior,
transition timing, target selection, and the conditions which choose each shot
still need to be traced. The 122 stage transform/colour callbacks also read
global scale/RGBA state used by the parent scene; current callers default these
to scale 1 and white unless explicitly supplied.

Completion gate: reproduce field shot selection and interpolation from battle
events, including the scale/colour transition state, while leaving classic
battle-scene mode unchanged.

### P2: intentional modern presentation choices

- Arena textures currently use linear filtering and mipmaps instead of N64
  three-point reconstruction. This improves distant floors but should remain a
  named arena option so fidelity and modern quality can both be tested.
- Enclosed arenas clear to their arena colour. The Academy park renders its
  own ROM sky/horizon cyclorama; its matching metadata clear is only an edge
  fill outside fixed-camera coverage and never reuses the classic battle sky.
- Modern antialiasing, anisotropic filtering, and shadow-map quality should be
  renderer quality settings, not hidden changes to extracted material state.

## Per-arena ROM feature inventory

`O/C/B` is the explicit modern opaque/cutout/blend reduction used by the
renderer.

| Arena | Prims | Textures | Callback textures | Dynamic controllers | TEXEL0+1 sites | Normal batches | Cull batches | Special mux | O/C/B |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|:---|
| 00 | 17 | 18 | 2 | 0 | 1 | 0 | 17 | 0 | 12/5/0 |
| 01 | 20 | 23 | 11 | 0 | 6 | 0 | 20 | 1 | 17/3/0 |
| 02 | 18 | 17 | 11 | 1 | 7 | 1 | 18 | 1 | 10/2/6 |
| 03 | 16 | 14 | 7 | 4 | 5 | 0 | 16 | 0 | 3/1/12 |
| 04 | 19 | 19 | 9 | 2 | 5 | 2 | 19 | 0 | 7/5/7 |
| 05 | 17 | 18 | 9 | 0 | 5 | 0 | 17 | 0 | 11/3/3 |
| 06 | 16 | 14 | 5 | 1 | 2 | 4 | 15 | 1 | 3/3/10 |
| 07 | 23 | 21 | 4 | 2 | 2 | 0 | 23 | 2 | 7/0/16 |
| 08 | 19 | 17 | 0 | 0 | 0 | 0 | 19 | 0 | 6/4/9 |
| 09 | 21 | 21 | 4 | 0 | 2 | 0 | 19 | 1 | 14/4/3 |
| 10 | 29 | 20 | 8 | 0 | 4 | 0 | 29 | 2 | 15/10/4 |
| 11 | 31 | 19 | 8 | 0 | 4 | 0 | 30 | 2 | 14/13/4 |
| 12 | 26 | 19 | 8 | 0 | 4 | 1 | 25 | 2 | 12/10/4 |
| 13 | 25 | 19 | 10 | 1 | 5 | 2 | 25 | 2 | 8/3/14 |
| 14 | 14 | 13 | 1 | 1 | 0 | 1 | 14 | 0 | 11/2/1 |
| 15 | 13 | 13 | 4 | 3 | 3 | 2 | 13 | 1 | 8/5/0 |
| 16 | 13 | 12 | 2 | 1 | 1 | 0 | 13 | 1 | 11/2/0 |
| 17 | 13 | 13 | 3 | 2 | 2 | 2 | 13 | 1 | 11/2/0 |
| 18 | 19 | 13 | 3 | 2 | 1 | 2 | 19 | 1 | 11/6/2 |
| 19 | 13 | 11 | 1 | 1 | 0 | 5 | 13 | 0 | 10/3/0 |
| 20 | 14 | 15 | 7 | 5 | 5 | 2 | 14 | 2 | 13/1/0 |
| 21 | 13 | 13 | 2 | 1 | 1 | 0 | 13 | 1 | 11/2/0 |
| 22 | 10 | 7 | 15 | 3 | 8 | 0 | 10 | 0 | 1/2/7 |
| 23 | 15 | 14 | 4 | 0 | 2 | 1 | 12 | 2 | 10/3/2 |
| 24 | 7 | 8 | 2 | 0 | 1 | 0 | 7 | 1 | 3/0/4 |
| 25 | 21 | 17 | 0 | 0 | 0 | 3 | 19 | 0 | 11/6/4 |
| 26 | 15 | 15 | 3 | 1 | 2 | 1 | 14 | 0 | 10/5/0 |
| 27 | 19 | 17 | 2 | 1 | 2 | 1 | 19 | 1 | 15/1/3 |
| 28 | 25 | 22 | 10 | 2 | 6 | 0 | 25 | 0 | 12/7/6 |
| 29 | 16 | 17 | 9 | 2 | 5 | 0 | 14 | 0 | 8/5/3 |

## Definition of complete

An arena is not marked complete merely because it looks acceptable from one
viewer angle. Completion requires:

1. Exact triangle and transform inventory, or a documented intentional change.
2. Every ROM combiner selector represented by the modern material shader.
3. Explicit render class, blend function, alpha rule, depth test/write rule,
   culling rule, and coplanar order for every primitive batch.
4. Phase-5 material output verified at multiple controller frames.
5. Authored prelighting preserved and normal-bearing geometry lit from recovered
   battle state.
6. Pokémon placement, scale, and camera shots verified in arena mode, with no
   behavioral change to classic mode.
7. Automated extraction/state tests plus visual captures for at least one
   indoor, outdoor, reflective, translucent, shadow-heavy, and animated arena.

This order matters: controller and render-state work should be completed before
more arena-specific offsets or texture-layer exceptions are added.
