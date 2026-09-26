2026-09-26 follow-up (cache S2IMP62; awaiting the user's retest):

#088 Grimer / #089 Muk missing eyes and lower surfaces: corrected callback
ownership and generated-texture transparency. A null 0x22 display-list node
did not clear the previous draw, so its following 0x08 callback incorrectly
captured Muk's eye draw and other local details. The lower body also inherited
the mouth atlas's transparent texels instead of the callback's opaque slime
tile: this affected 13 Grimer and 41 Muk base triangles. Fresh bind/idle
renders now show Muk's eyes, clean body textures, and the restored lower
surfaces. Both models retain their original 700/701 triangles. The earlier
FIXED claim below established data coverage, not correct rendering, and is
superseded by this finding. Normal/shiny ROM regression and the 251-model
render audit pass; visual parity still awaits the user's retest. Older caches
rebuild on the next importer startup. Evidence and validation limitations:
`docs/luna/research/slime-model-callback-ownership.md`.

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

2026-09-26 follow-ups (cache format S2IMP61; each awaits the user's retest):

AWAITING RETEST: #186 Politoed / #217 Ursaring detached torso and legs | geometry
command 0x1E (named-joint draw) can name a joint that the layout defines later
with 0x1D. The importer resolved only joints already seen and fell back to the
current bone, so those display lists were posed with the wrong matrix.
`Model:prescanBones` (lib/fragment.lua) now walks the layout's control flow
first and assigns every joint id before drawing. Rest-pose open edges fell from
36 to 16 (Politoed) and 73 to 57 (Ursaring); the hip ring and belly swirl now
join in viewer renders. The same forward references occur in species 170, 171,
194, 203, 225, 236 and 247, which change too.

AWAITING RETEST: #088 #089 Grimer/Muk bottom and tongue | the rips show that
every non-decal triangle drawn while the 0x81000048 dual-texture builder is
active takes the generated slime material, while blocked tongue/eye atlases
keep their own texture. The renderer previously kept authored textures on some
callback triangles (the black lips/ring at the bottom) and treated 32x64
atlases as slime inputs (the missing tongue colour). Now only a 4x4 tile is a
slime input (lib/fragment.lua), and 0x48 ownership follows
`DualTexture.ownsPrimitive` (lib/renderer.lua). Open: 10 triangles in Muk's
primitive 22 still show body where the rip shows tongue.

AWAITING RETEST: #079 #080 Slowpoke/Slowbro hit reaction (plus #101, #144,
#178, #198) | every species' model fragment carries a selector table tagged
(species<<16)|1: a u8 count at +4 and a pointer at +0xC to 4-byte entries whose
u16 at +2 is the pose clip. 84111D64 -> 8003F2C4 indexes it by the dispatch
row's selector byte and leaves the animation unchanged when selector >= count
(pret asm; michiiik 204b7d8). `Semantics.readSelectorTable` now reads this table
instead of the old selector-base heuristic; for Slowpoke, selectors 0-2 map to
clip 0 and 3-6 to clips 1-4, so the hit selector 6 is in range.

AWAITING RETEST: #204 Pineco eyes | with body culling disabled, the eye decals
are now two-sided like the other detail decals, and depth hides the rear ones.

AWAITING RETEST: #144 Articuno animation 11 (2026-09-26) | pose file 10 is a
valid 2-frame static pose. The raw pose decoder rejected any multi-frame clip
with no changing channel, then accepted a guessed pointer base (-0x20) that
decoded garbage (scales 0 and 4.095). The footer's header is now read with file
offsets first, static clips allowed (lib/fragment.lua, cache S2IMP63). After
the change all 1,616 species clips decode with file offsets.

AWAITING RETEST: #051 Dugtrio animations 4 and 7 (Dig attack and dig-down;
also #050 Diglett) | the ROM clips scale the heads to -1 and 0 to hide them
underground. The renderer's safeScale/safeTranslation clamped scales <=0 or >4
and translations beyond 4096 to the bind pose, so hidden heads drew at full
size. The ROM sampler (ModelAnim_EvaluateTranslationChannel, michiiik 204b7d8)
divides by 1000 without clamping; the clamps are removed (lib/renderer.lua).
This also changes 91 clips in about 45 species that carried such values, e.g.
Hoppip's petals (x5.5) and Jynx clip 7 (a bone at x20); the matrix code that
consumes these values is still GLOBAL_ASM and was not checked.
