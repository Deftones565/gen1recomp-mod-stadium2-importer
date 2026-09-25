# Town assets

Kenney **City Kit - Suburban**, from Game Assets All-in-1 3.7.0 (CC0).
The license is included alongside this file. Houses, fences and planters retain
the source palette, sampled from their OBJ UVs during conversion. Runtime paint
uses the town atlas below alongside the existing woodland watercolor atlas. Trees and flowers reuse the
CC0 Nature Kit assets, documented in `../kenney_nature/README.md`.

Rebuild with Pillow installed:

```sh
python3 tools/build_kenney_town.py '/path/to/3D assets/City Kit - Suburban'
```

## Watercolor material atlas

`watercolor-town.png` was generated with the built-in image generation tool on
2026-09-11 specifically for this project. It is a four-quadrant atlas: ivory
watercolor plaster (upper left), neutral roof shingles (upper right), vertical
wood grain (lower left), and sage leaves (lower right). Prompt requested flat,
evenly lit albedo panels, paper fibers, pigment granulation and watercolor washes,
with no text or borders. This generated image is separate from the Kenney CC0
source assets; the Kenney license does not describe its provenance.

The shader mirrors each quadrant with inset sampling to avoid atlas bleeding.
Plaster, shingles, wood, foliage and trim have explicit per-triangle material IDs.
Colors and light/shadow modulation remain in the runtime material pass, ahead of
the shared whole-scene watercolor finish. The atlas is mipmapped and cached.

Roof classification includes low extensions and eaves: in the four selected
source houses, garden foliage stays below y=0.20 and roofs begin above y=0.32.
The converter separates these at y=0.25; roof undersides keep the roof material
instead of blending into the surrounding plants. Geometry is unchanged.

## Street lamps

The lantern street fixture is from Kenney **Fantasy Town Kit** (CC0); see
`Fantasy-Town-License.txt`. The converter expects that pack beside City Kit -
Suburban in the All-in-1 collection. Two fixtures stand on opposite pavement
corners, clear of the central battle space. Their glass has a separate material
ID (7): opaque and unlit by day, emissive at night, excluded from point-shadow
casters so the glass does not trap the light inside the lantern.

Warm omnidirectional lighting and shadows use an isolated instance of the shared
point-light system for scenery and Pokémon. Daytime skips point-shadow updates;
nighttime reuses cached static shadows and updates moving battlers at 20 Hz.
The lights are steady, without flame flicker. Fixtures are part of the cached
scenery mesh and add 632 triangles total.
