# Battle environment plan

Scene checklist for Gen 1 and Gen 2. Grass, cave, freshwater and town are
implemented; the other categories are registered for future scenes.
Trainer battles should use their actual surroundings rather than a separate
universal trainer arena.

| Environment | Status | Scene and useful variants |
|---|---|---|
| Grass / woodland | Implemented | Current forest clearing. Later add open meadow and park/Safari-style variants. |
| Cave / tunnel | First version implemented | Rock floor, uneven walls, boulders and layered passages. Dark cave and mine variants. |
| Freshwater | Lake version implemented | Lakes, ponds and rivers, with reeds, rocks and wooded banks. Surfing and fishing compositions. |
| Ocean / coast | Planned | Open sea, beaches and rocky shores. Share the water system with freshwater. |
| Mountain / rocky route | Planned | Exposed rock, gravel, cliffs and sparse vegetation. Summit and volcanic-rock variants. |
| Ice cave | Planned | Ice floor, frozen rock and restrained blue lighting. Reuse cave layouts with different materials. |
| Town / city / road | Town square implemented | Paths, fences, buildings and roadside plants for outdoor trainer encounters. Rural and urban variants. |
| Ordinary interior | Planned | Rooms, corridors and simple furnishings. Houses, gatehouses and other indoor encounters. |
| Industrial / villain base | Planned | Concrete, metal, pipes, machinery and artificial lights. Factory, power-station, warehouse and hideout variants. |
| Tower / ruins / sacred site | Planned | Stone or timber halls, pillars and atmospheric lighting. Ancient ruins, burned tower and haunted/memorial variants. |
| Ship / dock | Planned | Wooden or metal decks, railings and water beyond. Cabin variant can reuse ordinary interiors. |
| Gym / dojo | Planned | A shared battle-room base with themed floors, props and lighting for each leader. Existing Stadium arenas remain an optional alternative. |
| League / championship / Battle Tower | Planned | Formal battle chambers with distinct Elite Four and champion treatments; a cleaner competitive-room variant. |

## Recommended build order

1. Cave / tunnel.
2. Freshwater, then ocean / coast using the same water system.
3. Mountain and ice-cave variants.
4. Towns, ordinary interiors and industrial rooms.
5. Towers, ruins, ships and themed gym/League rooms.

## Shared rules

- Keep the watercolor manga style consistent across scenery and Pokémon.
- Build around the movable camera: hide boundaries in every supported view.
- Cache each environment after first use; add a bounded cache as the scene library grows.
- Reuse geometry and materials for variants. Day/night and weather are lighting/effect variations, not separate maps.
- Fishing uses the local bank or shore when appropriate; surfing uses the surrounding water. Indoor water encounters retain their cave/building context.
- Choose scenes from location and encounter context, with specific locations taking precedence over broad terrain labels. Keep Classic as the fallback.

## Automatic selection and fallback

`lib/battle_environment.lua` is the shared catalog and resolver for both games.
With BATTLE ENVIRONMENT set to the Kenney option, supported wild and trainer
battles select woodland, dry cave, freshwater or town. Location-specific rules
precede broad map headers: Ice Path is ice cave, for example, and never the dry
cave scene. Outdoor grass and water encounters override ordinary town terrain;
coastal water is reserved for ocean. Cave water and indoor water are separately
registered and currently unbuilt. Unknown environments also remain unsupported.

Unbuilt categories use Classic when arenas are disabled. When arenas are enabled,
they use the contextual Stadium arena, including wild encounters in automatic
environment mode. A missing/failed arena asset falls back to Classic. Switching
BATTLE ENVIRONMENT back to Classic preserves the previous arena policy (Gen 2
trainer arenas, classic wild battles). Selection is made from encounter terrain,
map header, map ID and battle type; it does not depend on the opponent species.

Map-name rules and the coastal-route list are explicit, conservative heuristics;
new/custom locations should supply their environment and water classification or
extend the resolver. Unrecognized locations are not assigned a made-up scene.
