# Scene-kit assets

Props for the painted environments built with `lib/scene_kit.lua`: mountain,
ice cave, cave water, indoor water, interior, industrial, ruins, ship, gym
and league. They come from these Kenney kits in Game Assets All-in-1 3.7.0,
all CC0 (each kit's license notice is included alongside this file):

- Nature Kit: pines, rocks, bushes, grass, logs, stumps, mushrooms
- Furniture Kit: bookcases, desk, chairs, sofa, tables, lamps, rugs, plants
- Factory Kit, City Kit - Industrial, Space Station Kit: conveyors,
  hoppers, crane, boxes, tanks, control panels
- Graveyard Kit, Castle Kit, Mini Arena: columns, walls, arches, urns,
  lanterns, braziers, banners, statues, trophies
- Pirate Kit: masts, flags, cannons, crates, barrels, boats

`models.lua` is generated. Palette kits are sampled from their OBJ UVs; kits
without a palette use each material's diffuse colour. Every triangle gets a
material ID (foliage, wood, stone, plaster, cloth, painted, light, metal);
the converter lists per-model fixes where colour alone misleads. At runtime
the scene kit repaints the materials with the shared woodland watercolor
atlas (`../kenney_nature/`) so these levels match the other painted scenes.

Floors, walls, halls, terrain, rafts, rock pillars, icicles, crystals, the
ship's hull and deck, the gym court and the League carpet are built in code.

Rebuild with Pillow installed:

```sh
python3 tools/build_kenney_kit.py '/path/to/Kenney Game Assets All-in-1 3.7.0/3D assets'
```
