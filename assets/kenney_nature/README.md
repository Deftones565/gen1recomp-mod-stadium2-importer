# Woodland battle assets

The mesh subset comes from **Kenney Nature Kit 2.1**, included in the user's
Kenney Game Assets All-in-1 3.7.0 download. The kit offers complementary trees,
plants, flowers, rocks, terrain and water props for later environment work.
`License.txt` is Kenney's original CC0 notice and applies to the converted meshes.

Rebuild the compact mesh library from the installed pack:

```sh
python3 tools/build_kenney_grass.py '/path/to/3D assets/Nature Kit'
```

The converter triangulates OBJ faces, preserves normals on plants, and adjusts foliage,
bark and rock colours. Tree foliage receives two offline Loop subdivision
steps followed by an irregular ellipsoid reshape per connected crown. Smooth
normals are rebuilt for tree crowns and trunks; branches and tree placement
remain authored by Kenney. This removes the cuboid canopy silhouettes. It does not bundle the entire asset collection.

## Painted textures

`meadow-grass.png` and `summer-sky.png` were generated using the built-in
image-generation tool for this presentation. They are supplemental artwork,
not assets from Kenney and not covered by Kenney's license notice.

Grass prompt:

> Use case: stylized-concept. Asset type: seamless tiling game ground ALBEDO texture, square 1024x1024. Create a beautiful hand-painted lush short meadow grass ground texture for a colorful Pokemon-like 3D woodland battle clearing. Strict straight top-down orthographic surface, no horizon, no perspective, no scene, no characters. Countless small painterly tapered grass blades and tiny clover leaves, soft mossy undergrowth, subtle scattered dry golden blades, occasional tiny glimpses of warm olive earth. Rich fresh spring greens, lime tips, deeper cool green roots, medium-light values. Organic irregular fine detail distributed evenly across entire image; avoid large clumps, obvious focal points, flowers, stones, shadows from objects, outlines, gridded patches. Crisp professional stylized game texture art, gentle painted ambient shading, beautiful varied green hues, diffuse even illumination. Seamless edges all four sides, tileable. This is an actual ground material texture, not a scene concept. No text, border, labels or watermark.

Sky prompt:

> Use case: stylized-concept. Asset type: wide 3:2 sky background texture for a cheerful colorful 3D creature-battle game. Only a beautiful blue summer sky and softly sculpted white cumulus clouds, no land, no horizon objects, no sun disk, no trees, no characters. Professional painted anime game background, reminiscent of lush adventure RPG skies, crisp clean cloud silhouettes with delicate painterly internal shading, warm white sunlit tops and very pale cool blue undersides. Azure blue upper sky transitioning gradually to pale turquoise towards bottom. A few wispy small clouds in upper quarter, medium fluffy cloud clusters across middle left and middle right, gently billowing larger cumulus banks near lower edge, lots of clear blue space between. Rich but tasteful color, optimistic airy atmosphere, sophisticated illustration not photorealistic, not blurry airbrush, no outlines. Full bleed landscape image, no text, no watermark.


## Watercolor material pass

`watercolor-materials.png` is supplemental artwork made with the built-in
image-generation tool. Its four quadrants contain leaf, bark, stone, and neutral
paper-wash textures. It is not a Kenney asset. Geometry carries explicit material
IDs (ground, foliage, bark, stone, petals). The renderer blends three projection
planes to avoid stretching along tree sides and keeps atlas samples inside each
quadrant. Flowers retain their individual colours with paper-wash detail.
The ground, sky, fog and materials share softer saturation and warm paper tones.
All scenery stays in the same static mesh; this pass adds one material atlas.


## Trail shelter

`structure-roof` comes from the **Survival Kit** in the same Kenney All-in-1
collection. `Survival-Kit-License.txt` is its original CC0 notice. The converter
loads it from the sibling Survival Kit directory and applies the shared painted
wood material. It is a roofed open timber shelter, placed beyond the camera orbit.
