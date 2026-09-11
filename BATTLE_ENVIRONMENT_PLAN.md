# Battle environment plan

A proposed scene checklist for Gen 1 and Gen 2. Grass/woodland is implemented;
the remaining entries are planned, with variants sharing assets where possible.
Trainer battles should use their actual surroundings rather than a separate
universal trainer arena.

| Environment | Status | Scene and useful variants |
|---|---|---|
| Grass / woodland | Implemented | Current forest clearing. Later add open meadow and park/Safari-style variants. |
| Cave / tunnel | Next | Rock floor, uneven walls, boulders and layered passages. Dark cave and mine variants. |
| Freshwater | Planned | Lakes, ponds and rivers, with reeds, rocks and wooded banks. Surfing and fishing compositions. |
| Ocean / coast | Planned | Open sea, beaches and rocky shores. Share the water system with freshwater. |
| Mountain / rocky route | Planned | Exposed rock, gravel, cliffs and sparse vegetation. Summit and volcanic-rock variants. |
| Ice cave | Planned | Ice floor, frozen rock and restrained blue lighting. Reuse cave layouts with different materials. |
| Town / city / road | Planned | Paths, fences, buildings and roadside plants for outdoor trainer encounters. Rural and urban variants. |
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
