# Stadium 2 battle UI — reference capture (2026-09-27)

Local session. Sources: the supported US ROM run in mupen64plus 2.6
(glide64mk2 and rice video plugins), seven save states taken by the user in a
Free Battle, headless `--testshots` captures from those states, and 13
screenshots the user took with held buttons (CHECK and the D-pad info need a
button held, so a loaded state does not show them). Matches ROM execution;
nothing is decoded from code yet.

## Screens

- **Status panel** (one per side, 1P top-left, opponent bottom-right):
  gradient card (blue for the player, green for the opponent) with bracket
  corners; name; `L40`, status tag (`Nm` normal, `Pz` paralysed, `Ft`
  fainted, ...) and gender; `HP:` label, green bar; `cur/max` numbers. A tab
  under it carries the trainer name (`1P`, `CAL`). Party balls sit beside
  it (`×` marks a fainted member). A 32x32 box beside each panel holds a
  live 3D portrait (see "Portraits" below); both video plugins draw it as
  noise because they lack framebuffer emulation.
- **Command bar** (top): slanted tabs coloured like the N64 buttons:
  A (blue) BATTLE, B (green) POKéMON, Start (red) RUN.
- **Move menu**: tab bar `L CANCEL` / `R CHECK`; holding a button shows the
  four moves in a diamond around the C-button icons (C-up, C-left, C-right,
  C-down). Each tab is tinted by move type and shows the move name, the
  type name in its colour, and `PP cur/max`. Hint: D-pad `MOVE`.
- **Move info** (D-pad): one move with its C icon, type, PP, `POWER`,
  `ACCURACY` and a three-line description.
- **Switch screen**: tab bar `L CANCEL` / `R CHECK`; a row of party cards
  (name, level, status, gender, HP bar, HP numbers) each with a C-button
  icon. Hint: D-pad `STATUS`.
- **Message box** (bottom): long gradient panel with bracket corners and the
  Stadium bitmap font. Green while the opponent's Pokemon acts, blue-grey
  for the player's. Trainer tags and the portrait boxes hide during
  messages.

## Text

The battle message table is plain Latin-1 at ROM `0x1D8CDA4` (in RAM at
`0x8029B904` during battle), preceded by a u32 offset table. It starts with
the menu labels `BATTLE CANCEL CHECK RUN POKéMON NO YES QUIT? ABILITIES
ATTACK EVASION DEFENSE ACCURACY SPEED SPCL. ATK SPCL. DEF`, then battle
messages with placeholders (`#26` = own Pokemon name, `#28` = target,
`#29`/`#30` = move, `#01` = number, `#42` = item). Move names follow in RAM.

Fragment 79's data holds the battle engine's state/thread names (ROM
`0x3FA540`, vaddr `0x8418AB70..`): `waza_select`, `torikae`, `kuridashi`,
`call_kougeki`, `fight_main`, `CreateFightThread` and others. These are the
engine states that request the UI; fragment 79 does not draw it.

## Loaded fragments in battle

A save state's RDRAM (mupen64plus `.st`: gzip, `M64+SAVE`, 8 MB RDRAM at
+0x2C, little-endian words) holds 14 `FRAGMENT` images. By header size
fields: 27 (bit/random helpers), 79 (battle), 26 (model callbacks); the other
eleven are not in the pret split list (compressed archive fragments:
models, arena, effects and, presumably, the UI). Which one draws the UI is
not identified yet.

## Decomp and ROM data (2026-09-27)

Decomp: michiiik/pokestadiumgs `0ed78d46e9cd11432f217203675a839efcb1cc1c`;
still-ASM routines are pret `c0e10f23` US assembly.

- **Code.** The battle UI is `fragment79_3ADCA0` (functions
  `0x8413E4xx..0x841483xx`), mostly C in the fork (108 C, 55 ASM). It is the
  only part of fragment 79 that calls the 2D texture draw `func_80044270`
  (`src/4AC10.c`) and the UI texture lookup `func_8004C990(file, entry)`
  (`src/4CC20.c`). The battle engine (`fragment79_393CA0`) fills message
  parameters with `func_8004C54C(index, value)` (index 0x0A..0x7F), which is
  why messages use `#NN` placeholders.
- **Assets.** ROM table at `0x437620` (RAM `0x80124E90`) lists the asset
  archives; entry 1 is the UI archive at `0x1898000` (456 files). Each file
  is an 0x18-byte header plus a Yay0 texture set: `u32 count`, `count`
  pointers relative to `0x8FF00000`, each entry an 8-byte header
  `u16 w, u16 h, u8 fmt, u8 siz, u16 ?` before its pixels. Odd rows are
  stored with their 32-bit words swapped (TMEM interleave).
  `func_8004C990(file, entry)` selects file `file` entry `entry`:
  file 30 button icons (16x18 / 24x17 IA8), 31 (tab end), 32 small labels
  and the digit strip (#7, 8x9 IA4 per digit), 33 tab strips / bracket
  frame (64x14, 94x17 IA8, 24x26 corners), 34 unknown, 35 status tags,
  36 move-type labels (32x9 IA4, 18 labels), 122 unknown.
- **Font.** `src/47580.c` is the text system (`D_80126F50` state;
  `func_80047524` opens the font archive `D_437750`, ROM `0x437750`, 6 files).
  File 1 (Yay0 at `0x437FA8`) holds 16x12 IA8 glyphs, unswapped, preceded by
  a byte table whose values 6..8 look like per-glyph advances (not yet
  confirmed against the ASM `func_80046980`). `D_437670` / ROM `0x437680`
  looks like the character-to-glyph map. In battle the game copies 128
  glyphs to RAM `0x8028C000`.
- **HP bar** (`func_8413F858`, `func_8413F988`, `func_80064590`): 48 px;
  tier = `hp*48/max`: >= 24 green (130,255,0), >= 10 yellow (255,255,0),
  else red (255,120,0); 0 HP returns tier 3 (no fill). Empty part grey
  (100,100,100). Data `D_84186F7C/80/84/88`.
- **Digits** (`func_8413F498`): right-aligned, 6 px advance, file 32 #7.
- **Move types** (`func_8413F640`): colour `D_84186F98[type*3]` (19
  entries), label `D_84186FE8[type]` from file 36; type 0x12 draws nothing.
- **Status tags** (`func_8413F5F4`): label `D_84186FE0[status]` from file 35.
- **Portraits** (`func_8413FBC4`): 32x32 RGBA16 via `Gfx_DrawTextureRgba16`
  from `D_84190414/18`; the image in the captured state matches ROM
  `0x22682F0` (not in an archive).
- **Layout** (ROM execution, command-menu display list): player panel card
  `x25..88, y19..76` (320x240), opponent `x232..295, y164..221`, tab bar
  `y17..31` from `x94`. Card bodies are 64x1 IA16 gradient strips stretched
  vertically and tinted by prim colour (player (170,210,255)).

## Implementation notes (2026-09-27, `lib/stadium_ui*.lua`)

- **Character map** `D_437670`: 16-byte header, then two ranges: codes
  0x20..0x7F at offset 0x10, codes 0x90..0xFF at offset 0x70 (Latin-1).
  Checked: "A" -> glyph 0x1A, "0" -> 0x10, "é" (0xE9) -> 118.
- **Advance** = width-table value - 2: matches every pen position of
  "PIKACHU's THUNDERBOLT!" in the message frame (ROM execution).
- **HP numbers**: current HP right-aligned ending at card x+35 (6 px
  cells), "/" at x+35, max HP left-aligned from x+42 (104/104 capture:
  42,48,54 / 60 / 67,73,79).
- **Message layout**: while a message shows, both cards move to y19
  (x25 and x232), no trainer tags, portraits or balls; message card
  x34 y174 252x44, text origin x36 y177. The captured frame tints the acting
  opponent's card (255,255,255); the player-acting case is not captured, so
  the port keeps normal tints (open).
- **Balls**: file 34 #0 / #1 (fainted), 7 px apart; player x23 y115,
  opponent right-aligned ending x299 y119; a statused member's ball is
  tinted (140,140,140) (paralysed Cyndaquil in the capture).
- **Widescreen**: the port scales the 320x240 layout by screen height and
  pins the player's column to the left edge and the opponent's to the right;
  the message box stays centred. Not in the ROM.
- **Host wiring**: Gen 1 `BattleState:visibleText()` / `shown`; Gen 2
  `messageLines()` in its message phases. The host skips its own text box
  through the public `battle.bottom_ui_visible` hook while the Stadium box
  owns the text (`battle_ui_ownership.lua` message claim); no engine
  function is patched.

## Menus (2026-09-27, `lib/stadium_ui.lua`, `lib/stadium_menu.lua`)

Positions are the game's display lists from the held-button states
(03 CHECK, 04 D-pad info, 07 switch); ROM execution unless noted.

- **Command bar**: 64x14 tabs (file 33 #0) at x94+58i y17, tints A
  (170,170,255), B (170,255,170), Start (255,170,170); icons file 30
  (A #0, B #1, S #8) at (x-1, y+3); labels at x+15. PACK on R is a port
  addition (Stadium has no bag in battle).
- **Sub bar**: L CANCEL / R CHECK, tint (220,230,220), L/R icons 24x17 at
  (x-2, y+4). Hidden while the move diamond shows, as in the CHECK frame.
- **Move diamond** (`func_84141BE0`, michiiik 0ed78d4: tab i is move i,
  tinted by `D_84186F98[type]`): tabs 94x17 (file 33 #1) at (106,17)
  (204,24) (192,50) (94,43); C icons (tint 255,255,60) at (188,21) C-up,
  (200,33) C-right, (188,45) C-down, (176,33) C-left, so move 1..4 = C-up,
  C-right, C-down, C-left. Type label at tab+(3|12|12|11, 14), PP tint
  (150,255,0) around a slash at tab+(50|59|59|58). Names centred at tab+45.
- **Move info** (D-pad in Stadium; R held in the port): card x96 y19 169x60,
  C icon (99,20), name x114 y19, type label (115,32), PP slash x163 y32,
  POWER / ACCURACY labels (file 32 #8, #0) at x195 y20/31, values
  right-aligned to x261. Three description lines at x98 y43/55/67 in the
  small font with a (+1,+1) shadow (env 20,20,20).
- **Small font**: font archive `D_437750` file 0, same layout as file 1 with
  16x10 IA8 glyphs (160 bytes) from 0xC0; advance = width - 1 (spaces are
  drawn glyphs). Checked on Flame Wheel's line.
- **Descriptions**: ROM `0x1D81710`: u32 count 251, then 251 offsets from
  the table start; move m's text is entry m (Latin-1, `\n` line breaks).
- **Switch screen**: card x94 y19 201x46, columns 67 px apart; per column
  name centred at +33 y+3, L+level at +5 y+16, status tag +32 y+16, gender
  glyph +54 y+13, C icon +3 y+27, HP bar +19 y+27, HP numbers around a
  slash at +38 y+34. Column icons (by the RAM texture addresses of file 30,
  loaded in archive order): C-left, C-up, C-right. Dividers: 1 px black at
  x160/227 and 1 px (173,214,255) at x161/228, y+3..y+42 (colour measured).
  STATUS hint (file 32 #2 cross, #4 label) under the card. Members 4..6
  (Gen 1/2 parties) get a second card row: a port adaptation.
- **Port input** (not ROM behaviour): the engine's `input.step` and
  `input.pointer` hooks; actions go through the host's own menu state and
  `mod.input` taps. The host party menu stays live but is hidden through
  `screen.render_visible` while the switch cards stand in for it; a pick
  selects SWITCH (or STATS on R) in its submenu on the next tick, so the
  host's own switch rules and refusals apply.

## Portraits (2026-09-27, `lib/stadium_portrait.lua`)

From the US assembly and michiiik `0ed78d4` (decomp C, not yet visually
compared with a real console or a framebuffer-emulating plugin):

- `func_8410AA18` allocates two 32x32 16-bit framebuffers (`D_84190414/18`)
  and two cameras (`D_84190230/320`) with `func_80038DC8(fovy 10, near 10,
  far 1280)`.
- `func_8411F400` builds a separate model instance of the battler's species
  at the origin, animation selector 0 (idle), and sets its frame to the
  record's start frame (`func_8003EB84` = `ModelAnim_SetFrame`).
- `func_8411F4F4` aims the camera at `(rec.x, rec.y, 0)`; `func_800371B4`
  places the eye at target + `(sin yaw cos pitch, sin pitch, cos yaw cos
  pitch) * dist`, with 4096-entry sin/cos tables indexed by `angle >> 4`.
- `func_8411F340` clears to `0x4A53` (grey 74,74,74), sets a 32x32 viewport
  and renders; `func_8413FBC4` draws it with `Gfx_DrawTextureRgba16`.
- Records (`func_84113014`, DMA): ROM `0x4A0EB0 + (species-1)*32`
  (table `0x4A0EB0..0x4A40F0`): `s16 pitch, s16 yaw, f32 dist, f32 x,
  f32 y, s16 frame, s16 alt`. For the second battler x and yaw are negated,
  unless `alt != 0x200`, in which case the record at
  `0x4A0EB0 + (alt-2)*32` is loaded as authored (Pikachu: alt 0x188, pitch 100, yaw 5882,
  x -1.2). Species 0xFC (Substitute doll) gets no portrait.
- Position (display list): player `(card x, card y+45)`, opponent
  `(card x+31, card y-35)`; hidden in the message layout.

Port: the portrait is a second renderer of the battler's model drawn into a
32x32 canvas with the record's camera, stepping its idle clip from the
record's frame. The bracket frame around it (file 33 #3 in the card tint) is
taken from the command-menu display list.

Sharp portraits (port extension, requested by the user 2026-09-27, not ROM
behaviour): the native 32x32 buffer looked too pixelated scaled up, so the
port renders the same camera at twice the box's on-screen size (32 px
steps, max 512) and draws it scaled into the 32x32 box. `Portrait.render`
without `pixels` keeps the native buffer.

Gamepad input (port, 2026-09-27): the host binds LB/RB to game speed and
drops them before they become L/R, so a lazily installed `input.gamepad`
wrapper hands shoulder presses to the host's `Input:gamepadpressed` while a
Stadium menu is open. B/Start/R on the command bar work in both MENU
CONTROLS modes (the host command menus ignore them); the mode only decides
whether A follows the cursor or always picks BATTLE.

Menu input from the decomp (michiiik `0ed78d4`, US; matches decomp C):
`func_84139EB0` (command bar) reads pressed A = BATTLE (state 2), B =
POKeMON (state 5), Start = RUN (`func_84139C54`). `func_8413A53C` (move
select) reads held D-pad up/right/down/left = info card of move 1..4
(`func_8413A12C`), held R = CHECK (`func_84139F44`), pressed L = cancel,
pressed C-up/right/down/left = move 1..4; A is not read. The switch
screen's handler is still ASM (`func_8413A6CC..`) and not decoded.

Port (2026-09-27): a controller in use (the host's press sources `pad:`,
`joy:`, `stick`, `hat`) or MENU CONTROLS = STADIUM selects these Stadium
controls: no cursor, the host's A withheld on the move and switch screens,
D-pad held shows the info card. Keyboard with CURSOR keeps the host cursor,
now marked by a pulsing yellow frame (port addition; Stadium has no
cursor), and R held shows the cursor move's info. Switch screen adaptations
for 4..6 members: C-down moves the C icons to the next row; R held while
picking a member opens the host's STATS for it. Open: the lighting the game uses
for the portrait pass is not decoded; the port uses a fixed neutral light.

## Glass HUD suppression (2026-09-27, port)

With STADIUM UI on, neither scene draws the glass HUD or the captured Game
Boy status bands (`gen1_battle.lua` composeWorld, `battle_hud.lua`
Hud.composite for Gen 2). The host's intro / send-out party-ball rows
(Gen 1 `introBalls`/`showEnemyBalls`, Gen 2 `screen.ballRows`) show as
Stadium balls at the panel ball positions. Host UI that has to stay native
(Yes/No prompts, learn-move text, stats box, Crystal's move-info pane) sits
on a Stadium card instead of glass (`UI.backing`). The Stadium message box
now owns the whole message phase (Gen 1 `messages`, Gen 2 `resolving`,
`intro`, ...), keeping the last message through the text-less stretches of
a move animation, where the host's empty box used to show through. Glass
returns only if a Stadium draw fails (reported once) or another UI owns the
status region.

## YES/NO window (2026-09-27)

Decomp michiiik `0ed78d4` plus US asm (`func_8414491C`, `func_8413FD04`
checked); constants read from the ROM (fragment 79 data mapped with the
asm's `0x8413A6D4 <-> ROM 0x3A9F64`, verified on the type colours):

- UI element type 14/15, init `func_84146748`: position
  `D_84186DD8/DDC[index]` = player (92,17), opponent (26,175); size
  `D_84186DE0/DE4` = 204x50. Drawn like every card: strip
  `func_8413F060` + frame `func_8413EDF8` in the element's prim colour.
- `func_8414491C`: question (text table entry 7, `QUIT?`) centred at
  (+101, +10) (`D_84186DF0/DF4`), then NO (entry 5) and YES (entry 6) at
  y+26 (`D_84186DF8`). `func_84144A00` is the variant whose question is a
  message with the Pokemon's name, centred at (+101, +18).
- `func_8413FC34` lays out the answers: total = `DEC` 20 + `DE8` 5 +
  w(NO) + w(YES) (big-font widths, `func_80049148(2, -2, ...)`),
  x0 = 204/2 - total/2, x1 = x0 + w(NO) + 5 + 20; a 20 px slot sits before
  each answer (`+0x12/+0x16`). What the game draws in that slot (the
  selection marker) is not decoded: no A/B icon draw uses those fields.

Port (`UI.yesNo`, `stadium_menu.lua` kind `yesno`): Gen 1's battle
`ChoiceBox` (default YES/NO labels) and Gen 2's YesNoBox phases
(`ask-nickname`, `ask-shift`, `ask-next-mon`, `ask-forget`,
`stop-learning`) draw as this window at the player position, the host
question in the question slot. Adaptations: questions longer than one line
wrap to two lines (+3/+13); the selection is the port's cursor frame over
slot + label; left/right (and taps) pick, since the host toggles with
up/down; A and B stay the host's (B = NO). The host's own box is hidden
(`screen.render_visible` for `ChoiceBox`; the bottom claim for Gen 2).

## Controller icons (2026-09-28, port extension)

Requested by the user; not ROM behaviour. Astra's generated art
(`assets/controller_buttons/*.png`, prompts in `prompts.json`) with
measured glyph rects (`lib/stadium_button_atlas.lua`). `stadium_controller`
identifies the family from the host's normalised gamepad events (Valve
28de:1205 = Steam Deck, Sony vendor/names = PlayStation, "AYN Thor" names,
any other SDL gamepad = Xbox layout) and maps each logical N64 control to
the physical button through the host's `padBindings`; C buttons are the
right stick the Stadium menus read. `stadium_button_glyphs` draws them in
place of the ROM icons (CONTROLLER ICONS option; `NATIVE N64` and keyboard
play under `AUTO` keep the ROM textures). A missing image or an unusual
binding draws a labelled placeholder, never a different button.

## Open

- Locate the UI fragment and its textures (panel gradients, bracket
  corners, button icons, type tabs, font) instead of redrawing them.
- Portrait lighting (see above); visual comparison against a
  framebuffer-emulating plugin (e.g. GLideN64 with FB emulation on).
- Message box line spacing for two-line text (12 px assumed).
- Colours per move type and status abbreviations from data, not screenshots.
