# Ocean assets

Palms, rocks, the row boat, barrels, crates and grass tufts come from Kenney
**Pirate Kit**; the sailing and fishing boats come from Kenney **Watercraft
Pack**. Both are from Game Assets All-in-1 3.7.0 (CC0); their license notices
are included alongside this file.

`models.lua` is generated. Each triangle keeps its palette color, sampled from
the OBJ UVs, and gets a material ID (foliage, wood, stone, sand, sailcloth or
painted trim). At runtime the scene repaints each material with one pigment
and the shared woodland watercolor atlas (`../kenney_nature/`), so the props
match the other Kenney scenes. The sky reuses the woodland's painted summer
sky with a sea-haze horizon.

The battlers' log rafts, the palm island's beach and dunes, the horizon
islets, the sea stacks and the plank pier are built in code
(`lib/battle_ocean.lua`); trees and bushes on the island reuse the Nature Kit
meshes documented in `../kenney_nature/README.md`.

Rebuild with Pillow installed:

```sh
python3 tools/build_kenney_ocean.py '/path/to/Kenney Game Assets All-in-1 3.7.0/3D assets'
```
