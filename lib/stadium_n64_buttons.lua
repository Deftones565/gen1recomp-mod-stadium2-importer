-- HD N64 button icons (port extension, requested by the user 2026-09-28;
-- not ROM data). UI DETAIL = HD redraws the UI archive file 30 icons as
-- vector art at 16x, following the ROM icons' design: a greyscale cap
-- (round for A, B, Start and the C buttons, a rounded key for L and R)
-- with a dark rim, a face lit from the upper left, a bold italic letter or
-- an arrow, and a drop shadow to the lower right. They stay greyscale so
-- the game's own tints (A blue, B green, Start red, C yellow) still apply.
-- File 30 entries: 0 A, 1 B, 2 C-down, 3 C-left, 4 C-right, 5 C-up, 6 L,
-- 7 R, 8 Start; round icons are 16x18, L/R 24x17 (the ROM sizes).
local Buttons = {}
Buttons.SCALE = 16

local LETTER = { [0] = "A", [1] = "B", [6] = "L", [7] = "R", [8] = "S" }
local ARROW = { [2] = "down", [3] = "left", [4] = "right", [5] = "up" }

local fonts = {}
local function font(g, px)
  px = math.floor(px + 0.5)
  if not fonts[px] then fonts[px] = g.newFont(px) end
  return fonts[px]
end

-- Face lit from the upper left: concentric steps from the rim tone to
-- white around a highlight offset toward the light.
local function litDisc(g, cx, cy, r, s)
  local steps = 28
  for i = 0, steps - 1 do
    local t = i / (steps - 1)
    local rr = r * (1 - t * 0.9)
    local v = 0.66 + 0.34 * t
    local ox, oy = -r * 0.28 * t, -r * 0.32 * t
    g.setColor(v, v, v, 1)
    g.circle("fill", (cx + ox) * s, (cy + oy) * s, rr * s, 96)
  end
end

local function litKey(g, x, y, w, h, radius, s)
  local steps = 24
  for i = 0, steps - 1 do
    local t = i / (steps - 1)
    local inset = t * math.min(w, h) * 0.32
    local v = 0.66 + 0.34 * t
    g.setColor(v, v, v, 1)
    g.rectangle("fill", (x + inset - t * 0.6) * s, (y + inset - t * 0.8) * s,
      (w - 2 * inset) * s, (h - 2 * inset) * s, math.max(0, radius - inset * 0.5) * s)
  end
end

-- Bold italic glyph: the text stamped around a small circle (weight) under
-- a shear (slant), centred on cx, cy.
local function letter(g, text, cx, cy, size, s)
  local f = font(g, size * s)
  g.setFont(f)
  local tw, th = f:getWidth(text), f:getHeight()
  g.push()
  g.translate(cx * s, cy * s)
  g.shear(-0.22, 0)
  local weight = size * s * 0.045
  for a = 0, 7 do
    local dx, dy = math.cos(a * math.pi / 4) * weight, math.sin(a * math.pi / 4) * weight
    g.print(text, -tw / 2 + dx, -th / 2 + dy)
  end
  g.print(text, -tw / 2, -th / 2)
  g.pop()
end

local function arrow(g, dir, cx, cy, size, s)
  local r = size / 2
  local pts
  if dir == "up" then pts = { 0, -r, r, r * 0.7, -r, r * 0.7 }
  elseif dir == "down" then pts = { 0, r, r, -r * 0.7, -r, -r * 0.7 }
  elseif dir == "left" then pts = { -r, 0, r * 0.7, -r, r * 0.7, r }
  else pts = { r, 0, -r * 0.7, -r, -r * 0.7, r } end
  for i = 1, #pts, 2 do pts[i], pts[i + 1] = (cx + pts[i]) * s, (cy + pts[i + 1]) * s end
  g.polygon("fill", pts)
  g.setLineWidth(size * s * 0.08)
  g.setLineJoin("bevel")
  g.polygon("line", pts)
end

-- Paint entry `e` into the current canvas (w x h Stadium pixels at scale s).
local function paint(g, e, w, h, s)
  local ink = 0.07
  if e == 6 or e == 7 then
    local x, y, kw, kh, rad = 1, 1, w - 4, h - 4, 3
    g.setColor(0, 0, 0, 0.42)
    g.rectangle("fill", (x + 1.4) * s, (y + 1.8) * s, kw * s, kh * s, rad * s)
    g.setColor(0.13, 0.13, 0.13, 1)
    g.rectangle("fill", x * s, y * s, kw * s, kh * s, rad * s)
    litKey(g, x + 0.85, y + 0.85, kw - 1.7, kh - 1.7, rad - 0.4, s)
    g.setColor(ink, ink, ink, 1)
    letter(g, LETTER[e], x + kw / 2 - 0.2, y + kh / 2 - 0.1, 9, s)
  else
    local cx, cy, r = 7.6, 7.8, 7
    g.setColor(0, 0, 0, 0.42)
    g.circle("fill", (cx + 1.3) * s, (cy + 1.8) * s, r * s, 96)
    g.setColor(0.13, 0.13, 0.13, 1)
    g.circle("fill", cx * s, cy * s, r * s, 96)
    litDisc(g, cx, cy, r - 0.85, s)
    g.setColor(ink, ink, ink, 1)
    if ARROW[e] then arrow(g, ARROW[e], cx, cy + 0.1, 6.2, s)
    else letter(g, LETTER[e], cx - 0.1, cy, 9, s) end
  end
end

-- Build the HD image for file 30 entry `e` (ROM size w x h); returns a LOVE
-- image with mipmaps holding Buttons.SCALE texels per Stadium pixel.
function Buttons.image(e, w, h)
  local g = love and love.graphics
  if not (g and (LETTER[e] or ARROW[e])) then return nil end
  local s = Buttons.SCALE
  local canvas = g.newCanvas(w * s, h * s, { format = "rgba8", dpiscale = 1 })
  g.push("all")
  local ok, err = pcall(function()
    g.setCanvas(canvas)
    g.origin()
    g.setScissor()
    g.clear(0, 0, 0, 0)
    g.setBlendMode("alpha", "alphamultiply")
    paint(g, e, w, h, s)
  end)
  g.pop()
  if not ok then canvas:release(); return nil, err end
  local data = canvas:newImageData()
  canvas:release()
  -- blending onto a transparent canvas leaves colour premultiplied by
  -- alpha; undo that so antialiased edges keep their colour
  data:mapPixel(function(_, _, r, gg, b, a)
    if a > 0 and a < 1 then return math.min(1, r / a), math.min(1, gg / a), math.min(1, b / a), a end
    return r, gg, b, a
  end)
  local image = g.newImage(data, { mipmaps = true })
  data:release()
  image:setFilter("linear", "linear")
  if image.setMipmapFilter then image:setMipmapFilter("linear") end
  return image
end

function Buttons.release()
  for _, f in pairs(fonts) do if f.release then f:release() end end
  fonts = {}
end

return Buttons
