1 With all of these bugs, its most likely that a lot of these pokemon share code or functions that do the same thing, so one fix may fix many.

2 when I say matching I do not mean byte for byte, I mean the outcome should be the same as the stadium 2 models in stadium 2

FIXED: Charmander family tail flame callback parity | the shared flame
now uses the ROM's literal ten-vertex order and triangle diagonals, clamp/clamp
tile, two-cycle combiner, eight images, and colour pulse on the same uninterrupted
display counter. Its IA16 load is correctly reinterpreted through the ROM's
32x64 IA8 render tile instead of becoming two detached 32x32 flames. Desktop,
mobile, and fallback shaders all use TEXEL0 alpha for
coverage instead of the I4 smoke-intensity rule. Existing caches are normalized
when loaded and do not require re-exporting.

FIXED: Wartortle and Blastoise black body / apparently missing Blastoise cannon | supplied rips match the ROM geometry, bones, textures, normals, and triangle winding. The cannon is ROM primitives 22-23 (64+8 triangles); preserving each material's ROM clamp/mirror tile state prevents the body/cannon textures from repeating incorrectly.

FIXED: #077 Ponyta smoke callback parity | corrected fragment 26's 0.005 growth
rate (previously 20x too large) and preserved its #FF2000C8 environment colour
so the eight I4 frames blend from ROM orange toward the fading white primitive.

FIXED: #088 #089 Grimer/Muk parity | the supplied rips match all 48/47 bones and 700/701 triangles, including mouth cutouts, Grimer's four eye expressions, Muk's eye/pupil and tongue atlases, and the bottom geometry. Their ROM 0x81000048 dual-texture body routes remain complete (16/20 callbacks with both generated tiles).

FIXED: #092 Gastly gas parity | all eight ROM frames, pool/spawn/update timing,
fade and both palettes match fragment 26; its species-specific camera matrix is
now reproduced so the gas remains camera-facing, including shiny palette and
owning-model alpha state.

FIXED: #124 Jynx white face | geometry command 0x23's ROM-authored RGBA field
was being ignored, and primitive merging folded the 25-triangle purple face
draw into the neutral head. The face now remains a distinct primitive and uses
the game's exact #563860FF tint over its white intensity carrier.

FIXED: #146 the flame is incorrect

FIXED: #190 Aipom has no face | the supplied rip contains the same 700 ROM triangles and the face is not separate geometry. It is primitive 7's four-frame 32x64 texture animation; preserving that material's mirrored-S/clamped-T tile state keeps the facial atlas on the head.

FIXED: #192 it has no eyes

FIXED: #198 its eyes clip through its face model

BUGGED: #204 eye appearance/placement still needs matching | eye occlusion is
fixed independently: the battle scene's broad body-culling override no longer
disables the ROM culling bit on Pineco's one-sided eye decals, and their former
0.01 clip-space pull is reduced to the ordinary 4/65535 decal stabilization so
rear and side eyes remain behind the opaque shell.

BUGGED: #186 Politoed torso separation / incomplete rear body

What we found:

- The ROM model contains 37 bones, 787 exported vertices and 722 triangle
  commands (22 TRI1 plus 350 TRI2). No ROM triangle command is currently being
  skipped by the display-list decoder.
- The geometry graph makes 100 top-level display-list calls, 61 of which emit
  triangles. The RSP vertex cache is deliberately reused between named rigid
  assemblies: 299 triangles reference vertices loaded under more than one bone
  matrix. Clearing the cache per list drops those triangles and leaves only 423.
- Keeping the vertex cache produces all 722 triangles, but does not fix the
  visible rear separation. Keeping all 61 draw-bearing submissions unmerged also
  did not visibly fix it. Therefore triangle count and material batching alone
  are not the cause.
- Stadium's named-node renderer selects a matrix, submits the display list, and
  leaves the transformed vertex cache alive. The decoded Euler rotation order,
  hierarchy composition, scale propagation and normal submission were checked
  against the ROM routines; alternate rotation orders and conventional local
  TRS composition made the model worse.
- The two 64x32 belly textures do have a colour boundary. Stitching that boundary
  can hide the small tummy texture seam, but it is unrelated to the detached
  rear torso geometry and must not be described as the model fix.

Potential fixes / next checks:

- Capture Stadium's actual matrix, VTX and TRI command stream for the same
  Politoed animation frame and compare every transformed cache slot with the
  importer. Static ROM data is no longer enough to distinguish the mismatch.
- Verify runtime geometry-graph traversal order, rather than assuming layout
  construction order is the final draw order. A missed preload or reordered
  named node would retain all 722 triangle commands while joining the wrong
  cached vertices.
- Compare the explicit named-node matrix slot and animation channel used by the
  two torso assemblies at the failing frame, including whether Stadium steps or
  interpolates that pose.
- Once transformed vertex positions match, audit per-submission culling, depth
  compare/write and clipping state. These can make present bridge triangles fail
  to cover the gap, but they should be treated as secondary until the cache-slot
  positions match the game.

#217 its lets and body don't look attached on the sides, also its legs are clipping its tummy

FIXED: #110 Weezing's small head repeats its face on both sides | the small
head's ROM face primitive uses CMS=3 (G_TX_MIRROR | G_TX_CLAMP) across
U=-0.48..2.51. The host sampler previously treated that as endless mirrored
repeat, producing a centre face and copies on both sides; treating it as plain
clamp then removed the mirrored eye. The combined N64 mode now mirrors the
half-face once across U=0..2 and clamps beyond that span, matching both Koffing
and Weezing without side copies.
