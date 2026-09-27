-- Stadium 2 battle UI: status panels and the message box, drawn from the
-- ROM's own textures and font (stadium_ui_assets.lua) in Stadium's 320x240
-- screen space. The caller sets the transform onto its canvas.
--
-- Evidence (docs/luna/research/stadium2-battle-ui.md):
-- * decomp, fragment79_3ADCA0 (michiiik 0ed78d4): HP bar func_8413F858 /
--   func_8413F988 / func_80064590, digits func_8413F498, status tags
--   func_8413F5F4, texture lookup func_8004C990(file, entry);
-- * ROM data: colours D_84186F7C..F88, tag tints and card tints read from
--   the game's display list;
-- * ROM execution (the game's display list from save states): positions,
--   frame piece geometry, text origin and advances.
-- Anything not covered there is marked below.
local Assets = require("mods.STADIUM2_IMPORTER.lib.stadium_ui_assets")

local UI = {}

-- Card tints from the display list (prim colour of each card body).
UI.TINT = {
  player = { tag = { 90, 150, 255 }, card = { 170, 210, 255 } },
  enemy = { tag = { 0, 255, 150 }, card = { 150, 255, 200 } },
}
-- HP tiers: D_84186F7C (green), F80 (yellow), F84 (red); empty part F88.
UI.HP_COLORS = { [0] = { 130, 255, 0 }, [1] = { 255, 255, 0 }, [2] = { 255, 120, 0 } }
UI.HP_EMPTY = { 100, 100, 100 }
UI.HP_LENGTH = 43

-- Panel origins (card body top-left) in 320x240, from the display list.
UI.PANEL = {
  player = { x = 25, y = 34, w = 63, h = 42, tagY = 19, tagH = 12 },
  enemy = { x = 232, y = 164, w = 63, h = 42, tagY = 209, tagH = 12 },
}
UI.MESSAGE = { x = 34, y = 174, w = 252, h = 44, textX = 36, textY = 177 }
-- Line spacing of the message box: not in the captured frames (one line);
-- 12 px matches the glyph height. TODO: confirm from a two-line message.
UI.MESSAGE_LINE = 12

-- func_80064590: tier from hp*48/max; 0 HP draws no fill (tier 3).
function UI.hpTier(hp, maxHp)
  hp, maxHp = math.max(0, math.floor(hp or 0)), math.max(1, math.floor(maxHp or 1))
  if hp == 0 then return 3 end
  local value = math.floor(hp * 0x30 / maxHp) % 0x10000
  if value >= 0x18 then return 0 end
  if value >= 0xA then return 1 end
  return 2
end

-- Filled pixels of the 43 px bar (both captured panels: 49/94 -> 22,
-- 87/87 -> 43, i.e. floor(hp*43/max)).
function UI.hpFill(hp, maxHp)
  hp, maxHp = math.max(0, hp or 0), math.max(1, maxHp or 1)
  return math.min(UI.HP_LENGTH, math.floor(hp * UI.HP_LENGTH / maxHp))
end

-- Status labels in file 35, by the text drawn on each (entries 0..6).
UI.STATUS_ENTRY = { BRN = 0, FNT = 1, FRZ = 2, OK = 3, PAR = 4, PSN = 5, SLP = 6 }

local g
local function setColor(c, a)
  g.setColor((c[1] or 255) / 255, (c[2] or 255) / 255, (c[3] or 255) / 255, (a or 255) / 255)
end

local function tex(file, entry)
  local images = Assets.images()
  local set = images and images.sets[file]
  return set and set[entry]
end

-- Draw a sub-rectangle of a texture, stretched to w x h.
local function blit(t, sx, sy, sw, sh, x, y, w, h)
  if not t then return end
  local q = g.newQuad(sx, sy, sw, sh, t.w, t.h)
  g.draw(t.image, q, x, y, 0, w / sw, h / sh)
  if q.release then q:release() end
end

-- A card: the 64x1 gradient strip (file 31) stretched over the body and the
-- 16x4 frame pieces (file 33 #3), all tinted by the card colour. Piece
-- geometry is the display list's: s0 left, s4 top, s8/s12 lower corners,
-- s11 bottom, s12 right; edges stretch one column or row.
function UI.card(x, y, w, h, tint)
  local strip = tex(31, 0)
  setColor(tint)
  if strip then blit(strip, 0, 0, strip.w, 1, x, y, w, h) end
  UI.frame(x, y, w, h, tint)
end

-- The bracket frame alone (file 33 #3), as drawn around the portraits.
function UI.frame(x, y, w, h, tint)
  local frame = tex(33, 3)
  setColor(tint)
  if frame then
    -- left edge incl. top-left corner: columns 0..3; the tile is clamped
    -- (cms/cmt 2), so rows 0..3 draw once and row 3 stretches down
    blit(frame, 0, 0, 4, 4, x - 4, y - 4, 4, 4)
    blit(frame, 0, 3, 4, 1, x - 4, y, 4, h)
    blit(frame, 8, 0, 4, 4, x - 3, y + h, 4, 4)          -- bottom-left
    blit(frame, 11, 0, 1, 4, x + 1, y + h, w - 1, 4)     -- bottom
    blit(frame, 12, 0, 4, 4, x + w, y + h, 4, 4)         -- bottom-right
    blit(frame, 12, 0, 4, 1, x + w, y, 4, h)             -- right
    blit(frame, 4, 0, 4, 4, x + w - 1, y - 4, 4, 4)      -- top-right
    blit(frame, 4, 0, 1, 4, x, y - 4, w - 1, 4)          -- top
  end
end

-- Text in the Stadium font. Glyph quads are drawn from texture column 1, so
-- a glyph's origin is one pixel left of the pen (display list: s=1).
function UI.textWidth(text)
  local images = Assets.images()
  if not images then return 0 end
  local w = 0
  for i = 1, #text do
    local glyph = Assets.glyphFor(images.font, text:byte(i))
    if glyph then w = w + Assets.advance(images.font, glyph) end
  end
  return w
end

function UI.text(text, x, y, color)
  local images = Assets.images()
  if not images then return 0 end
  setColor(color or { 255, 255, 255 })
  local pen = x
  for i = 1, #text do
    local glyph = Assets.glyphFor(images.font, text:byte(i))
    if glyph then
      local img = images.glyphs[glyph]
      if img then g.draw(img, pen - 1, y) end
      pen = pen + Assets.advance(images.font, glyph)
    end
  end
  return pen - x
end

-- Font glyphs without a character-map code (font file indices).
UI.GLYPH_MALE, UI.GLYPH_FEMALE = 2, 65

function UI.glyph(index, x, y, color)
  local images = Assets.images()
  local img = images and images.glyphs[index]
  if not img then return end
  setColor(color or { 255, 255, 255 })
  g.draw(img, x - 1, y)
end

-- Digits from the file 32 #7 strip (8x9 cells: 0-9, '/', 'L', '-').
local DIGIT_CELL = { ["/"] = 10, L = 11, ["-"] = 12 }
local function digitCell(cell, x, y)
  local strip = tex(32, 7)
  if strip then blit(strip, cell * 8, 0, 8, 9, x, y, 8, 9) end
end

-- func_8413F498: right-aligned from x, 6 px per digit, at least minDigits.
function UI.number(value, x, y, minDigits)
  value = math.max(0, math.floor(value or 0))
  minDigits = minDigits or 1
  setColor({ 255, 255, 255 })
  repeat
    x = x - 6
    digitCell(value % 10, x, y)
    value = math.floor(value / 10)
    minDigits = minDigits - 1
  until value <= 0 and minDigits <= 0
end

-- func_8413F858 / func_8413F988: filled part tinted by tier, then the empty
-- part and a 1 px end cap in grey (file 32 #5, 16x6).
function UI.hpBar(x, y, hp, maxHp)
  local bar = tex(32, 5)
  if not bar then return end
  local fill = UI.hpFill(hp, maxHp)
  local tier = UI.hpTier(hp, maxHp)
  local len = UI.HP_LENGTH
  setColor(UI.HP_EMPTY)
  if fill < len then blit(bar, 1, 0, 1, 6, x + fill + 1, y, len - fill, 6) end
  blit(bar, 0, 0, 1, 6, x + len + 1, y, 1, 6)
  if tier ~= 3 then
    -- one texrect of width fill+1 from s=0 with a clamped tile: columns
    -- 0..15, then column 15 repeats
    setColor(UI.HP_COLORS[tier])
    local width = fill + 1
    local head = math.min(bar.w, width)
    blit(bar, 0, 0, head, 6, x, y, head, 6)
    if width > bar.w then blit(bar, bar.w - 1, 0, 1, 6, x + bar.w, y, width - bar.w, 6) end
  end
end

-- One status panel. data = {name, level, status, gender ("M"/"F"/nil),
-- hp, maxHp, tag (trainer label), balls = {"ok"|"fainted"|..., ...}}.
-- While a battle message shows, both cards sit on the top row (y19) with no
-- trainer tags, portraits or balls (message frame's display list; user
-- screenshots). The captured frame tints the acting opponent's card white;
-- the player-acting case is not captured, so tints stay unchanged here.
UI.MESSAGE_PANEL_Y = 19

function UI.statusPanel(side, data, messageLayout)
  local p, tint = UI.PANEL[side], UI.TINT[side]
  if not (p and tint) then return end
  if messageLayout then
    p = { x = p.x, y = UI.MESSAGE_PANEL_Y, w = p.w, h = p.h }
  end
  -- Party balls alone (the host's intro / send-out ball rows, before a
  -- Pokemon is out), at the panel's ball position.
  if data.ballsOnly then
    UI.panelBalls(side, p, data.balls)
    return
  end
  -- trainer tag bar
  if data.tag and not messageLayout then
    UI.card(p.x, p.tagY, p.w, p.tagH, tint.tag)
    local tw = UI.textWidth(data.tag)
    UI.text(data.tag, p.x + math.floor((p.w - tw) / 2), p.tagY)
  end
  UI.card(p.x, p.y, p.w, p.h, tint.card)
  -- name, centred on the card
  local name = tostring(data.name or "")
  local nw = UI.textWidth(name)
  UI.text(name, p.x + math.floor((p.w - nw) / 2) + 1, p.y)
  -- level: 'L' cell then digits, left-aligned (display list: L at +2, then +8)
  setColor({ 255, 255, 255 })
  digitCell(DIGIT_CELL.L, p.x + 2, p.y + 13)
  local level = tostring(math.floor(data.level or 0))
  for i = 1, #level do digitCell(tonumber(level:sub(i, i)), p.x + 2 + 6 * i, p.y + 13) end
  -- status tag (file 35)
  local entry = UI.STATUS_ENTRY[data.status or "OK"] or UI.STATUS_ENTRY.OK
  local label = tex(35, entry)
  if label then setColor({ 255, 255, 255 }); blit(label, 0, 0, label.w, label.h, p.x + 29, p.y + 13, label.w, label.h) end
  -- gender symbol (font glyph), right of the status tag
  if data.gender == "F" or data.gender == "M" then
    UI.glyph(data.gender == "F" and UI.GLYPH_FEMALE or UI.GLYPH_MALE, p.x + 53, p.y + 10)
  end
  -- HP label, bar and numbers
  local hpLabel = tex(32, 6)
  if hpLabel then setColor({ 255, 255, 255 }); blit(hpLabel, 0, 0, hpLabel.w, hpLabel.h, p.x + 2, p.y + 24, hpLabel.w, hpLabel.h) end
  UI.hpBar(p.x + 16, p.y + 24, data.hp, data.maxHp)
  UI.number(data.hp, p.x + 35, p.y + 31, 1)
  setColor({ 255, 255, 255 })
  digitCell(DIGIT_CELL["/"], p.x + 35, p.y + 31)
  -- max HP is left-aligned after the slash (104/104 capture: 67,73,79;
  -- 94 and 87 start at the same column)
  local maxText = tostring(math.max(0, math.floor(data.maxHp or 0)))
  setColor({ 255, 255, 255 })
  for i = 1, #maxText do digitCell(tonumber(maxText:sub(i, i)), p.x + 42 + 6 * (i - 1), p.y + 31) end
  -- Portrait (func_8413FBC4): the 32x32 live render, under the player's
  -- card at (x, y+45) and above the opponent's at (x+31, y-35), framed in
  -- the card tint. Hidden in the message layout.
  if data.portrait and not messageLayout then
    local px, py = p.x, p.y + 45
    if side ~= "player" then px, py = p.x + 31, p.y - 35 end
    -- the box's size in screen pixels, for sharp portraits (port extension)
    if g.transformPoint then
      local x0, y0 = g.transformPoint(px, py)
      local x1, y1 = g.transformPoint(px + 32, py)
      UI.portraitPixels = math.sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2)
    end
    setColor({ 255, 255, 255 })
    local cw, ch = data.portrait:getDimensions()
    g.draw(data.portrait, px, py, 0, 32 / cw, 32 / ch)
    UI.frame(px, py, 32, 32, tint.card)
  end
  -- Party balls at the display list's positions: under the player's
  -- portrait box (x23 y115) and right-aligned above the opponent's (ending
  -- x299, y119). Stadium parties are 3; Gen 1/2 parties show up to 6.
  if not messageLayout then UI.panelBalls(side, p, data.balls) end
end

function UI.panelBalls(side, p, balls)
  if not (balls and #balls > 0) then return end
  if side == "player" then
    UI.partyBalls(p.x - 2, p.y + 81, balls)
  else
    UI.partyBalls(p.x + 59 - 7 * (#balls - 1), p.y - 45, balls)
  end
end

-- A Stadium card behind host UI that stays native with STADIUM UI on
-- (Yes/No prompts, learn-move text, Crystal's move info): replaces the glass
-- plate. rect is in screen pixels; k = screen pixels per Stadium pixel.
function UI.backing(rect, k, side)
  if not (rect and k and k > 0) then return false end
  g.push("all")
  local ok = pcall(function()
    g.translate(rect[1], rect[2])
    g.scale(k, k)
    UI.card(0, 0, rect[3] / k, rect[4] / k, (UI.TINT[side or "player"] or UI.TINT.player).card)
  end)
  g.pop()
  return ok
end

-- Party balls (file 34: #0 ball, #1 fainted), 7 px apart. The captured
-- frame tints a statused member's ball (140,140,140) (paralysed Cyndaquil).
UI.BALL_STATUS_TINT = { 140, 140, 140 }

function UI.ballState(mon)
  if type(mon) ~= "table" then return nil end
  if (mon.hp or 0) <= 0 then return "fainted" end
  local status = mon.status
  if status and status ~= "" and status ~= false and UI.statusKey(status) ~= "OK" then return "status" end
  return "ok"
end

function UI.partyBallStates(party)
  local out = {}
  for _, mon in ipairs(party or {}) do
    local state = UI.ballState(mon)
    if state then out[#out + 1] = state end
  end
  return out
end

function UI.partyBalls(x, y, balls)
  for i, state in ipairs(balls or {}) do
    local t = tex(34, state == "fainted" and 1 or 0)
    if t then
      setColor(state == "status" and UI.BALL_STATUS_TINT or { 255, 255, 255 })
      blit(t, 0, 0, t.w, t.h, x + (i - 1) * 7, y, t.w, t.h)
    end
  end
end

-- The message box, tinted with the acting side's card colour (green while
-- the opponent acts, blue-grey for the player: user screenshots; the tint
-- values themselves are the cards').
function UI.messageBox(lines, side)
  local m = UI.MESSAGE
  local tint = (UI.TINT[side] or UI.TINT.player).card
  UI.card(m.x, m.y, m.w, m.h, tint)
  for i, line in ipairs(lines or {}) do
    UI.text(line, m.textX, m.textY + (i - 1) * UI.MESSAGE_LINE)
  end
end

-- Host status spellings (Gen 1 "PSN", Gen 2 "poison", "TOX", ...) to the
-- file-35 labels.
function UI.statusKey(status, fainted)
  if fainted then return "FNT" end
  local s = tostring(status or ""):upper()
  if s == "" or s == "OK" or s == "NONE" then return "OK" end
  if s:find("^PSN") or s:find("^TOX") or s:find("^POIS") then return "PSN" end
  if s:find("^BRN") or s:find("^BURN") then return "BRN" end
  if s:find("^FRZ") or s:find("^FREEZ") or s:find("^FROZ") then return "FRZ" end
  if s:find("^PAR") then return "PAR" end
  if s:find("^SLP") or s:find("^SLEEP") then return "SLP" end
  if s:find("^FNT") or s:find("^FAINT") then return "FNT" end
  return "OK"
end

-- Stadium's layout is 320x240. Scale it to the battle view: by height in
-- landscape, with the player's panel on the left edge and the opponent's on
-- the right edge of a wider screen (widescreen adaptation, not in the ROM);
-- by width inside `area` in portrait.
function UI.placement(area)
  local s
  if area.w >= area.h then s = area.h / 240 else s = area.w / 320 end
  return {
    scale = s,
    left = area.x,
    right = area.x + area.w - 320 * s,
    top = area.y,
  }
end

-- Safe entry for the battle compositors: false (and the error, reported
-- once) lets the caller fall back to its glass HUD.
local reported
function UI.tryDrawPanels(area, panels, warn, messageLayout)
  g.push("all")
  local ok, err = pcall(UI.drawPanels, area, panels, messageLayout)
  g.pop()
  if not ok and not reported then
    reported = true
    if type(warn) == "function" then pcall(warn, "Stadium UI draw failed: " .. tostring(err)) end
  end
  return ok
end

function UI.drawPanels(area, panels, messageLayout)
  local place = UI.placement(area)
  for _, side in ipairs({ "player", "enemy" }) do
    local data = panels and panels[side]
    if data then
      g.push()
      g.translate(side == "player" and place.left or place.right, place.top)
      g.scale(place.scale, place.scale)
      UI.statusPanel(side, data, messageLayout)
      g.pop()
    end
  end
end

-- Host text is UTF-8; the ROM font's character map is Latin-1 (e.g. the
-- "é" in POKéMON is 0xE9). Two-byte sequences U+0080..U+00FF convert; other
-- characters are dropped rather than drawn as the wrong glyph.
function UI.toLatin1(text)
  text = tostring(text or "")
  local out, i = {}, 1
  while i <= #text do
    local b = text:byte(i)
    if b < 0x80 then out[#out + 1] = string.char(b); i = i + 1
    elseif b == 0xC2 or b == 0xC3 then
      local c = text:byte(i + 1) or 0x80
      out[#out + 1] = string.char((b - 0xC2) * 0x40 + c); i = i + 2
    elseif b >= 0xE0 and b < 0xF0 then i = i + 3
    elseif b >= 0xF0 then i = i + 4
    else i = i + 2 end
  end
  return table.concat(out)
end

-- The message box, centred horizontally in the battle view (Stadium's box
-- spans x34..286 of 320).
function UI.drawMessage(area, lines, side)
  local place = UI.placement(area)
  local converted = {}
  for i, line in ipairs(lines or {}) do converted[i] = UI.toLatin1(line) end
  g.push()
  g.translate(area.x + (area.w - 320 * place.scale) / 2, place.top)
  g.scale(place.scale, place.scale)
  UI.messageBox(converted, side)
  g.pop()
end

function UI.tryDrawMessage(area, lines, side, warn)
  g.push("all")
  local ok, err = pcall(UI.drawMessage, area, lines, side)
  g.pop()
  if not ok and not reported then
    reported = true
    if type(warn) == "function" then pcall(warn, "Stadium UI message draw failed: " .. tostring(err)) end
  end
  return ok
end

------------------------------------------------------------------------
-- Menus (Phase 2). Positions are the game's own display lists (command
-- menu, move menu with CHECK held, switch screen); per-slot offsets are
-- copied from the capture rather than derived.

-- Button icons (file 30) and tab tints from the command-menu frame.
UI.BUTTON = {
  A = { entry = 0, tint = { 170, 170, 255 } },
  B = { entry = 1, tint = { 170, 255, 170 } },
  S = { entry = 8, tint = { 255, 170, 170 } },
  L = { entry = 6, tint = { 220, 230, 220 }, wide = true },
  R = { entry = 7, tint = { 220, 230, 220 }, wide = true },
  CUP = { entry = 5 }, CRIGHT = { entry = 4 }, CDOWN = { entry = 2 }, CLEFT = { entry = 3 },
}
UI.C_TINT = { 255, 255, 60 }
UI.PP_TINT = { 150, 255, 0 }
UI.SUB_TINT = { 220, 230, 220 }

-- Stadium type order (label map D_84186FE8, colours D_84186F98): index ->
-- colour; type 0x12 = none (grey, no label).
UI.TYPE_INDEX = { NORMAL = 0, FIGHTING = 1, FLYING = 2, POISON = 3, GROUND = 4,
  ROCK = 5, BUG = 6, GHOST = 7, STEEL = 8, ["???"] = 9, CURSE = 9, FIRE = 10,
  WATER = 11, GRASS = 12, ELECTRIC = 13, PSYCHIC = 14, ICE = 15, DRAGON = 16,
  DARK = 17 }
UI.TYPE_COLOR = {
  [0] = { 220, 240, 220 }, { 220, 170, 70 }, { 110, 140, 255 }, { 240, 150, 240 },
  { 210, 150, 80 }, { 180, 180, 110 }, { 120, 170, 190 }, { 170, 110, 230 },
  { 120, 170, 190 }, { 190, 200, 170 }, { 240, 120, 30 }, { 110, 190, 255 },
  { 150, 220, 90 }, { 255, 240, 80 }, { 210, 130, 160 }, { 110, 210, 210 },
  { 70, 220, 100 }, { 200, 130, 200 }, { 150, 150, 150 } }
UI.TYPE_LABEL = { [0] = 12, 5, 7, 13, 10, 15, 0, 8, 16, 3, 6, 17, 9, 2, 14, 11, 1, 4 }

function UI.typeIndex(name)
  if name == nil then return 0x12 end
  local key = tostring(name):upper():gsub("[^A-Z?]", "")
  if key == "PSYCHICTYPE" then key = "PSYCHIC" end
  return UI.TYPE_INDEX[key] or 0x12
end

-- Touch targets recorded during the last draw, in the caller's coordinates.
UI.hits = {}
local hitTransform = { x = 0, y = 0, s = 1 }
local function hit(id, x, y, w, h)
  local t = hitTransform
  UI.hits[#UI.hits + 1] = { id = id, x = t.x + x * t.s, y = t.y + y * t.s, w = w * t.s, h = h * t.s }
end
function UI.clearHits() UI.hits = {} end
function UI.hitAt(x, y)
  for i = #UI.hits, 1, -1 do
    local r = UI.hits[i]
    if x >= r.x and y >= r.y and x < r.x + r.w and y < r.y + r.h then return r.id end
  end
  return nil
end

local function mix(c, t)
  return { c[1] + (255 - c[1]) * t, c[2] + (255 - c[2]) * t, c[3] + (255 - c[3]) * t }
end

-- Cursor mark for the CURSOR control style (port addition: Stadium's menus
-- have no cursor). A pulsing yellow 2 px frame around the selected item.
UI.CURSOR_COLOR = { 255, 220, 40 }
function UI.cursorFrame(x, y, w, h)
  local t = love and love.timer and love.timer.getTime and love.timer.getTime() or 0
  local alpha = 190 + 65 * math.sin(t * 6)
  setColor({ 0, 0, 0 }, alpha * 0.6)
  g.setLineWidth(1)
  g.rectangle("line", x - 3.5, y - 3.5, w + 7, h + 7)
  setColor(UI.CURSOR_COLOR, alpha)
  g.setLineWidth(2)
  g.rectangle("line", x - 2, y - 2, w + 4, h + 4)
  g.setLineWidth(1)
end

local function buttonIcon(name, x, y, tint)
  local b = UI.BUTTON[name]
  local icon = b and tex(30, b.entry)
  if not icon then return end
  setColor(tint or b.tint or { 255, 255, 255 })
  blit(icon, 0, 0, icon.w, icon.h, x, y, icon.w, icon.h)
end

-- One command/sub tab: the 64x14 tab (file 33 #0) tinted by its button, the
-- icon at (x-1, y+3) (16x18) or (x-2, y+4) (24x17 for L/R), label at x+15.
-- `selected` brightens the tab toward white: the cursor highlight is an
-- addition for cursor/touch control (Stadium has no cursor here).
function UI.tab(x, y, button, label, tint, selected, id)
  local strip = tex(33, 0)
  local b = UI.BUTTON[button] or {}
  tint = tint or b.tint or UI.SUB_TINT
  if selected then tint = mix(tint, 0.55) end
  if strip then setColor(tint); blit(strip, 0, 0, strip.w, strip.h, x, y, strip.w, strip.h) end
  if b.wide then buttonIcon(button, x - 2, y + 4, tint) else buttonIcon(button, x - 1, y + 3, tint) end
  UI.text(label, x + 15, y + 2)
  if selected then UI.cursorFrame(x - 2, y, 66, strip and strip.h or 14) end
  if id then hit(id, x - 2, y, 66, 21) end
end

-- Command bar: BATTLE / POKeMON / RUN at x94 + 58*i, y17. PACK (Gen 1/2's
-- bag) is an addition in the same style on R; not in Stadium 2.
function UI.commandBar(tabs, selected)
  for i, t in ipairs(tabs) do
    UI.tab(94 + 58 * (i - 1), 17, t.button, t.label, nil, selected == i, "command:" .. i)
  end
end

-- Move/switch sub bar: L CANCEL, R CHECK (tint 220,230,220).
function UI.subBar(cancelSelected)
  UI.tab(94, 17, "L", "CANCEL", UI.SUB_TINT, cancelSelected, "cancel")
  UI.tab(152, 17, "R", "CHECK", UI.SUB_TINT, false, "check")
end

-- Move diamond (func_84141BE0: tab i is move i). Per slot: tab (94x17, file
-- 33 #1) position, its C icon, and the name/type/PP offsets, from the CHECK
-- frame.
UI.MOVE_SLOTS = {
  { tab = { 106, 17 }, icon = { 188, 21 }, button = "CUP", type = { 3, 14 }, slash = 50 },
  { tab = { 204, 24 }, icon = { 200, 33 }, button = "CRIGHT", type = { 12, 14 }, slash = 59 },
  { tab = { 192, 50 }, icon = { 188, 45 }, button = "CDOWN", type = { 12, 14 }, slash = 59 },
  { tab = { 94, 43 }, icon = { 176, 33 }, button = "CLEFT", type = { 11, 14 }, slash = 58 },
}

-- moves = { {name=, type=, pp=, maxPp=}, ... } (up to 4); selected = cursor.
function UI.moveDiamond(moves, selected)
  local wide = tex(33, 1)
  for i, slot in ipairs(UI.MOVE_SLOTS) do
    local move = moves[i]
    local tx, ty = slot.tab[1], slot.tab[2]
    local typeIndex = move and UI.typeIndex(move.type) or 0x12
    local color = UI.TYPE_COLOR[typeIndex] or UI.TYPE_COLOR[0x12]
    local tint = selected == i and mix(color, 0.5) or color
    if wide then setColor(tint); blit(wide, 0, 0, 94, 17, tx, ty, 94, 17) end
    if move then
      local name = UI.toLatin1(move.name or "")
      local w = UI.textWidth(name)
      UI.text(name, tx + 45 - math.floor(w / 2), ty + 1)
      local label = UI.TYPE_LABEL[typeIndex]
      local img = label and tex(36, label)
      if img then setColor(color); blit(img, 0, 0, img.w, img.h, tx + slot.type[1], ty + slot.type[2], img.w, img.h) end
      -- PP: current right-aligned before the slash, max left-aligned after
      local sx, py = tx + slot.slash, ty + 14
      setColor(UI.PP_TINT)
      local cur = tostring(math.max(0, math.floor(move.pp or 0)))
      for k = #cur, 1, -1 do digitCell(tonumber(cur:sub(k, k)), sx - 6 * (#cur - k + 1), py) end
      digitCell(DIGIT_CELL["/"], sx, py)
      local mx = tostring(math.max(0, math.floor(move.maxPp or 0)))
      for k = 1, #mx do digitCell(tonumber(mx:sub(k, k)), sx + 7 + 6 * (k - 1), py) end
      hit("move:" .. i, tx, ty, 94, 24)
    end
    buttonIcon(slot.button, slot.icon[1], slot.icon[2], UI.C_TINT)
  end
  local slot = selected and UI.MOVE_SLOTS[selected]
  if slot and moves[selected] then UI.cursorFrame(slot.tab[1], slot.tab[2], 94, 23) end
end

-- YES/NO window (UI element type 14/15; michiiik 0ed78d4 / US asm, values
-- read from the ROM): init func_84146748 places it at D_84186DD8/DDC
-- (player (92,17), opponent (26,175)), 204x50 (D_84186DE0/DE4), drawn as a
-- card (func_8413F060 strip + func_8413EDF8 frame). func_8414491C centres
-- the question at (+101, +10) (D_84186DF0/DF4) and draws NO then YES at
-- y+26 (D_84186DF8); func_8413FC34 lays them out: total = 20 + 5 + w(NO) +
-- w(YES), x0 = 102 - total/2, x1 = x0 + w(NO) + 5 + 20.
-- Port adaptations: host questions longer than one line wrap to two lines
-- at +3/+13, and the selected answer gets the port's cursor frame over its
-- 20 px slot and label (the game's own marker is not decoded).
UI.YESNO = { x = 92, y = 17, w = 204, h = 50, questionX = 101, questionY = 10,
  optionY = 26, gap = 5, slot = 20 }

-- lines: the host question; selected: 1 = YES, 2 = NO (host order).
function UI.yesNo(lines, selected)
  local w = UI.YESNO
  UI.card(w.x, w.y, w.w, w.h, UI.TINT.player.card)
  lines = lines or {}
  local joined = table.concat(lines, " ")
  local rows
  if #lines <= 1 or UI.textWidth(joined) <= w.w - 8 then
    rows = { { joined, w.questionY } }
  else
    rows = { { lines[1], 3 }, { lines[2] or "", 13 } }
  end
  for _, row in ipairs(rows) do
    local tw = UI.textWidth(row[1])
    UI.text(row[1], w.x + w.questionX - math.floor(tw / 2), w.y + row[2])
  end
  local first, second = UI.textWidth("NO"), UI.textWidth("YES")
  local total = w.slot + w.gap + first + second
  local x0 = math.floor(w.w / 2) - math.floor(total / 2)
  local x1 = x0 + first + w.gap + w.slot
  local options = { { "NO", x0, first, 2 }, { "YES", x1, second, 1 } }
  for _, o in ipairs(options) do
    UI.text(o[1], w.x + o[2], w.y + w.optionY)
    local sx = w.x + o[2] - w.slot
    if selected == o[4] then UI.cursorFrame(sx + 4, w.y + w.optionY - 1, o[3] + w.slot - 2, 13) end
    hit("yesno:" .. o[4], sx, w.y + w.optionY - 4, o[3] + w.slot + 4, 20)
  end
end

-- D-pad hint card (small white card, cross icon, label: file 32 #3 MOVE,
-- #4 STATUS), from the move and switch frames.
function UI.hint(labelEntry, x, y, w)
  x, y = x or 96, y or 71
  UI.card(x, y, w or 42, 5, { 255, 255, 255 })
  local cross, label = tex(32, 2), tex(32, labelEntry)
  setColor({ 255, 255, 255 })
  if cross then blit(cross, 0, 0, cross.w, cross.h, x + 1, y, cross.w, cross.h) end
  if label then blit(label, 0, 0, label.w, label.h, x + 14, y + 1, label.w, label.h) end
end

-- Switch screen (switch frame's display list): one 201x46 card at x94 y19
-- in the player tint, three columns 67 px apart. Column buttons, by the icon
-- textures the game loaded: C-left, C-up, C-right. Members 4..6 (Gen 1/2
-- parties; Stadium's are 3) get a second card below: an adaptation. The C
-- icons sit on the row they address (cRow; C-down moves them).
UI.SWITCH_BUTTONS = { "CLEFT", "CUP", "CRIGHT" }

function UI.switchCards(members, selected, cRow)
  cRow = cRow or 1
  local rows = math.max(1, math.ceil(#members / 3))
  for row = 0, rows - 1 do
    local y = 19 + row * 53
    UI.card(94, y, 201, 46, UI.TINT.player.card)
    -- column dividers (1 px fills at x160/161, x227/228, y+3..y+42): black,
    -- then the card tint (measured on the captured frame)
    for c = 1, 2 do
      local x = 94 + 67 * c - 1
      setColor({ 0, 0, 0 }); g.rectangle("fill", x, y + 3, 1, 39)
      setColor({ 173, 214, 255 }); g.rectangle("fill", x + 1, y + 3, 1, 39)
    end
    for c = 0, 2 do
      local i = row * 3 + c + 1
      local m = members[i]
      if m then
        local x0 = 94 + 67 * c
        if selected == i then
          setColor({ 255, 255, 255 }, 70)
          g.rectangle("fill", x0 + 1, y, 65, 46)
        end
        local name = UI.toLatin1(m.name or "")
        UI.text(name, x0 + 33 - math.floor(UI.textWidth(name) / 2), y + 3)
        setColor({ 255, 255, 255 })
        digitCell(DIGIT_CELL.L, x0 + 5, y + 16)
        local level = tostring(math.floor(m.level or 0))
        for k = 1, #level do digitCell(tonumber(level:sub(k, k)), x0 + 5 + 6 * k, y + 16) end
        local entry = UI.STATUS_ENTRY[m.status or "OK"] or UI.STATUS_ENTRY.OK
        local label = tex(35, entry)
        if label then setColor({ 255, 255, 255 }); blit(label, 0, 0, label.w, label.h, x0 + 32, y + 16, label.w, label.h) end
        if m.gender == "F" or m.gender == "M" then
          UI.glyph(m.gender == "F" and UI.GLYPH_FEMALE or UI.GLYPH_MALE, x0 + 54, y + 13)
        end
        if row + 1 == cRow then buttonIcon(UI.SWITCH_BUTTONS[c + 1], x0 + 3, y + 27, UI.C_TINT) end
        UI.hpBar(x0 + 19, y + 27, m.hp, m.maxHp)
        UI.number(m.hp, x0 + 38, y + 34, 1)
        setColor({ 255, 255, 255 })
        digitCell(DIGIT_CELL["/"], x0 + 38, y + 34)
        local mx = tostring(math.max(0, math.floor(m.maxHp or 0)))
        for k = 1, #mx do digitCell(tonumber(mx:sub(k, k)), x0 + 45 + 6 * (k - 1), y + 34) end
        if selected == i then UI.cursorFrame(x0 + 1, y, 65, 46) end
        hit("switch:" .. i, x0, y, 67, 46)
      end
    end
  end
  UI.hint(4, 94, 19 + rows * 53 - 4, 40)
end

-- Small font with its 1 px shadow (move-info frame: the shadow pass at
-- (+1,+1) with env (20,20,20), then the text in white).
UI.SHADOW = { 20, 20, 20 }

function UI.smallText(text, x, y)
  local images = Assets.images()
  local font = images and images.small
  if not font then return 0 end
  -- `text` is Latin-1 already (ROM descriptions); host text converts first
  for pass = 1, 2 do
    setColor(pass == 1 and UI.SHADOW or { 255, 255, 255 })
    local pen = x + (pass == 1 and 1 or 0)
    for i = 1, #text do
      local glyph = Assets.glyphFor(font, text:byte(i))
      if glyph then
        local img = images.smallGlyphs[glyph]
        if img then g.draw(img, pen - 1, y + (pass == 1 and 1 or 0)) end
        pen = pen + math.max(1, (font.widths[glyph] or 7) - 1)
      end
    end
  end
end

function UI.description(moveNumber)
  local images = Assets.images()
  local list = images and images.descriptions
  return list and list[tonumber(moveNumber) or 0] or nil
end

-- Move info (move-info frame): card x96 y19 169x60 in the player tint, the
-- move's C icon, name, type label and PP; POWER / ACCURACY labels (file 32
-- #8, #0) with their values right-aligned to x261; three description lines.
-- move = {name, type, pp, maxPp, power, accuracy, number}, button = slot icon.
local function rightDigits(value, xRight, y)
  if value == nil then
    digitCell(DIGIT_CELL["-"], xRight - 6, y); digitCell(DIGIT_CELL["-"], xRight - 12, y)
    return
  end
  local text = tostring(math.max(0, math.floor(value)))
  for k = #text, 1, -1 do digitCell(tonumber(text:sub(k, k)), xRight - 6 * (#text - k + 1), y) end
end

function UI.moveInfo(move, button)
  if not move then return end
  UI.card(96, 19, 169, 60, UI.TINT.player.card)
  buttonIcon(button, 99, 20, UI.C_TINT)
  UI.text(UI.toLatin1(move.name or ""), 114, 19)
  local typeIndex = UI.typeIndex(move.type)
  local color = UI.TYPE_COLOR[typeIndex] or UI.TYPE_COLOR[0x12]
  local label = UI.TYPE_LABEL[typeIndex]
  local img = label and tex(36, label)
  if img then setColor(color); blit(img, 0, 0, img.w, img.h, 115, 32, img.w, img.h) end
  setColor(UI.PP_TINT)
  rightDigits(move.pp or 0, 163, 32)
  digitCell(DIGIT_CELL["/"], 163, 32)
  local mx = tostring(math.max(0, math.floor(move.maxPp or 0)))
  for k = 1, #mx do digitCell(tonumber(mx:sub(k, k)), 170 + 6 * (k - 1), 32) end
  local power, accuracy = tex(32, 8), tex(32, 0)
  setColor({ 255, 255, 255 })
  if power then blit(power, 0, 0, power.w, power.h, 195, 20, power.w, power.h) end
  if accuracy then blit(accuracy, 0, 0, accuracy.w, accuracy.h, 195, 31, accuracy.w, accuracy.h) end
  local p = tonumber(move.power)
  rightDigits((p and p > 1) and p or nil, 261, 21)
  local a = tonumber(move.accuracy)
  rightDigits(a and a > 0 and a or nil, 261, 32)
  local desc = UI.description(move.number)
  if desc then
    local i = 0
    for line in desc:gmatch("[^\n]+") do
      UI.smallText(line, 98, 43 + 12 * i)
      i = i + 1
      if i >= 3 then break end
    end
  end
end

-- Draw a menu layer in the battle view: `fn` draws in 320x240 space. The
-- bar and diamond sit in Stadium's centre column; on a wide screen that
-- column is centred between the pinned status panels.
function UI.drawMenu(area, fn)
  local place = UI.placement(area)
  local ox = area.x + (area.w - 320 * place.scale) / 2
  hitTransform = { x = ox, y = place.top, s = place.scale }
  g.push()
  g.translate(ox, place.top)
  g.scale(place.scale, place.scale)
  fn()
  g.pop()
  hitTransform = { x = 0, y = 0, s = 1 }
end

function UI.tryDrawMenu(area, fn, warn)
  UI.clearHits()
  g.push("all")
  local ok, err = pcall(UI.drawMenu, area, fn)
  g.pop()
  if not ok and not reported then
    reported = true
    if type(warn) == "function" then pcall(warn, "Stadium UI menu draw failed: " .. tostring(err)) end
  end
  return ok
end

-- Draw with an explicit graphics module (tests may pass a recorder).
function UI.bind(graphics) g = graphics end

function UI.available()
  local images, err = Assets.images()
  return images ~= nil, err
end

UI.bind(love and love.graphics)
return UI
