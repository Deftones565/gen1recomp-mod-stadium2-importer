# Pokemon Stadium 2 Importer

3D Pokemon Stadium 2 battles for Gen 1 and Gen 2 games in Gen1Recomp: Stadium
models (normal and shiny, all 251 plus every Unown), animations, battle
arenas, move effects, a free camera and Stadium's glass HUD. The game still
runs the battles; this mod only changes how they look.

| | |
|---|---|
| ![Brock's Stadium arena](docs/images/arena-brock.jpg) | ![Free Battle Park](docs/images/arena-park.jpg) |
| ![Ocean](docs/images/ocean.jpg) | ![Ocean at night](docs/images/ocean-night.jpg) |
| ![Ice cave](docs/images/ice-cave.jpg) | ![Ship at night](docs/images/ship-night.jpg) |
| ![Home interior](docs/images/interior.jpg) | ![Gym](docs/images/gym.jpg) |

## Setup

1. Install and enable the mod in the Mod Manager.
2. When asked, import your own **Pokemon Stadium 2 (USA)** ROM (`.z64`,
   `.v64` or `.n64`). MD5: `1561c75d11cedf356a8ddb1a4a5f9d5d`.
3. Start the game. Models are imported once, with a progress screen; after
   an update that changes the format, they are re-imported automatically.

No ROM is included. Never add one to the mod ZIP.

## Battle scenes

- **Gyms** use the leader's Stadium 2 arena.
- **Elsewhere**, with `BATTLE ENVIRONMENT` set to `KENNEY NATURE`, battles
  use a painted scene matched to where you are: woodland, cave, lake, town,
  ocean, mountain, ice cave, homes, factories, ruins, ships, the League,
  underground lakes and indoor pools.
- `CLASSIC` keeps the simple classic battle stage.

## Evolution in battle

When a Pokemon evolves at the end of a won battle, it evolves in the 3D
battle instead of on the game's evolution screen: the camera closes in, the
Pokemon turns white and its old and new models trade places on the game's
own flash beats, sparkles rise, and the white fades off the new form. The
game's texts show in the Stadium message box. If the Pokemon evolving is not
the one out, it is sent out first. B still cancels. If a model can't load,
the game's own evolution screen is used.

## Options

| Option | What it does |
|---|---|
| 3D POKEMON MODELS | Stadium models on or off. |
| 3D BATTLE SCENE | The 3D battle presentation on or off. |
| BATTLE HUD | Stadium's glass HUD; turn off to use the native or another mod's UI. |
| STADIUM UI | Stadium 2's battle UI (status panels with live portraits, message box, command bar, move diamond and info, switch cards, PACK, YES/NO) in place of the glass HUD. It is the [Stadium 2 UI](https://github.com/Deftones565/Stadium-2-UI) mod, included in this mod. |
| MENU CONTROLS | With a controller the menus use Stadium 2's controls (no cursor, C buttons on the right stick, hold the D-pad for move info). On keyboard, `CURSOR` keeps a moving cursor and `STADIUM` uses the controller scheme. |
| UI DETAIL | `HD` (default) smooths the Stadium UI's art and font for big screens; `N64 PIXELS` shows them as crisp pixels. |
| CONTROLLER ICONS | Button prompts in the Stadium UI: `AUTO` follows the controller you last used; or pick `XBOX`, `PLAYSTATION`, `AYN THOR`, `STEAM DECK`, or `NATIVE N64` for Stadium's own icons. Keyboard play shows the N64 icons under `AUTO`. |
| THOR INPUT MODE | Shown for `AYN THOR`: match the Thor's controller style so A/B and X/Y prompts line up. |
| GRAPHICS | Shows the graphics settings below. |
| SHADER STYLE | `STADIUM` or `WATERCOLOR MANGA`. |
| 3D RESOLUTION | `AUTO`, 100%, 75% or 50%. Lower is faster; the UI stays sharp. |
| BATTLE AA | Anti-aliasing: off, 2x or 4x. |
| EXTRA EFFECTS | `LITE` or `OFF` cuts particles, shadows, weather and visitors for slow phones. |
| POKE BALL | Stadium's send-out and return effects. |
| SCENE WEATHER | Rain or thunderstorms in outdoor scenes. |
| BATTLE ENVIRONMENT | `CLASSIC` or the painted `KENNEY NATURE` scenes. |
| AMBIENT POKEMON | Harmless visitors in the painted scenes. |
| TEST ENVIRONMENT / TEST ARENA | Force a scene or arena for your next battle. |
| TEST ROOM | Opens the test room (below). |
| RAPIDASH CUT PARTICLES | Restores Rapidash's unused flame particles from the ROM. |
| CONTEXT ARENAS (BETA) | Gen 2 trainer battles use their matching Stadium arena. |
| PARK TIME OF DAY (BETA) | Morning, day and night lighting for Free Battle Park. |
| MOVE EFFECTS (BETA) | Stadium 2's own move effects, decoded from your ROM. |

The painted scenes, weather, visitors, Extra Effects, the Poke Ball toggle
and the in-battle evolution are mod additions, not part of Stadium 2. In the Stadium UI, PACK, the
cursor, sharp portraits, the second row of switch cards, the controller
icons and HD detail are additions too.

## Test room

![Test room](docs/images/test-room.jpg)

Play any move or battle effect between any two Pokemon, in any scene or
Stadium arena, day or night. Works with touch, mouse, keyboard and gamepad;
`EXIT` returns to the game.

## Camera

- **Mouse:** move to orbit, wheel (or `Q`/`E`) to zoom, `0` to reset.
- **Controller:** right stick.
- **Touch:** drag with one finger, pinch to zoom.

## Credits

This mod's research into Stadium 2's formats, battle effects and UI builds
on the work of these decompilation projects:

- [pret/pokestadiumgs](https://github.com/pret/pokestadiumgs) — the original
  Pokemon Stadium 2 decompilation and its contributors.
- [michiiik/pokestadiumgs](https://github.com/michiiik/pokestadiumgs) — the
  continued decompilation work, including battle and UI routines used as
  references for this port.

Thank you to the maintainers and contributors of both projects.

## For developers

The Stadium UI is the Stadium-2-UI repository, a git submodule at `ui/`
(one codebase with the standalone Stadium 2 UI mod). Clone with
`git clone --recursive`, or run `git submodule update --init` in an
existing clone. Build a release ZIP with `sh tools/build_release.sh`
(it includes `ui/`, which `git archive` leaves out).

The integration API, UI-mod compatibility, rendering notes, tests and tools
are in [docs/INTEGRATION.md](docs/INTEGRATION.md). Release notes are in
[docs/releases](docs/releases).
