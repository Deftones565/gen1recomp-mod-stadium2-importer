-- Controller button icons for the Stadium UI (port extension, requested by
-- the user; Stadium 2 only has N64 icons). The ROM's N64 textures stay in
-- use for the N64 choice, for keyboard play under AUTO, and whenever this
-- returns false.
local Controller = require("mods.STADIUM2_IMPORTER.lib.stadium_controller")
local Atlas = require("mods.STADIUM2_IMPORTER.lib.stadium_button_atlas")
local Glyphs = {}
local cached, reported = {}, {}
local input, enabled, warn, modRef
local iconStyle = "auto"
local ROOT = "assets/controller_buttons/"
local LABELS = {
  a="A", b="B", x="X", y="Y", start="MENU", dpad="+",
  leftshoulder="LB", rightshoulder="RB",
  r_up="R^", r_right="R>", r_down="Rv", r_left="<R",
}
-- PlayStation faces are symbols, written as text only in the placeholder.
local PS_LABELS = { a="X", b="O", x="[]", y="/\\", start="OPT" }

function Glyphs.bindWarning(fn) warn = fn end
function Glyphs.bindMod(mod) modRef = mod end
function Glyphs.setStyle(style) iconStyle = style or "auto" end

-- device: "pad" / "keyboard" (stadium_menu); style: the BUTTON ICONS option.
-- AUTO shows controller icons only while a controller is in use; an
-- explicit family shows them always; N64 never does.
function Glyphs.setContext(game, device, style)
  input = game and game.input
  style = style or iconStyle
  if style == "native" then enabled = false
  elseif style == nil or style == "auto" then enabled = device == "pad"
  else enabled = true end
end

local function imageSource(file)
  local path = ROOT .. file
  if modRef and modRef.assets and type(modRef.assets.path) == "function" then
    return modRef.assets:path(path)
  end
  return "mods/STADIUM2_IMPORTER/" .. path
end

local function load(g, family)
  if cached[family] then return cached[family] end
  local spec = Atlas[family]
  if not spec then return nil end
  local image, quads
  local ok, err = pcall(function()
    -- Own this image. mod.assets:image() is shared by the loader and cannot
    -- be released here; assets:path() also works inside the sealed mod.
    image = g.newImage(imageSource(spec.file), {mipmaps=true})
    image:setFilter("linear", "linear")
    if image.setMipmapFilter then image:setMipmapFilter("linear") end
    quads = {}
    local iw, ih = image:getDimensions()
    for key, r in pairs(spec.rects) do
      quads[key] = {quad=g.newQuad(r[1],r[2],r[3],r[4],iw,ih),w=r[3],h=r[4]}
    end
  end)
  if not ok then
    if image and image.release then image:release() end
    for _, r in pairs(quads or {}) do if r.quad.release then r.quad:release() end end
    if not reported[family] then
      reported[family] = true
      if warn then pcall(warn, "Controller icons unavailable (" .. family .. "): " .. tostring(err)) end
    end
    -- Do not retry a failed upload for every button in every frame.
    cached[family] = {failed=true}
    return cached[family]
  end
  cached[family] = {image=image,quads=quads}
  return cached[family]
end

-- Readable fallback if an asset cannot load or a custom binding has no
-- corresponding picture in the atlas.
local function placeholder(g, text, x, y, w, h, wide)
  local r = math.min(w, h) / 2
  g.setColor(0.16, 0.16, 0.18, 1)
  if wide then g.rectangle("fill", x, y + h * 0.15, w, h * 0.7, h * 0.3)
  else g.circle("fill", x + w / 2, y + h / 2, r) end
  g.setColor(0.82, 0.84, 0.88, 1)
  g.setLineWidth(math.max(0.5, r * 0.12))
  if wide then g.rectangle("line", x, y + h * 0.15, w, h * 0.7, h * 0.3)
  else g.circle("line", x + w / 2, y + h / 2, r) end
  g.setLineWidth(1)
  local font = g.getFont()
  local tw, th = math.max(1, font:getWidth(text)), math.max(1, font:getHeight())
  local scale = math.min(w * (wide and 0.8 or 0.7) / tw, h * 0.6 / th)
  g.setColor(1, 1, 1, 1)
  g.print(text, x + (w - tw * scale) / 2, y + (h - th * scale) / 2, 0, scale, scale)
end

-- Returns false only when the ROM icon should be used. A missing texture or
-- an unusual binding gets a labelled placeholder, never a different button.
function Glyphs.draw(g, logical, x, y, w, h)
  if not enabled then return false end
  local family, key, fallbackText = Controller.glyph(logical, input)
  if not family or family == "native" then return false end
  local previous = g.getColor and {g.getColor()} or {1,1,1,1}
  g.setColor(1,1,1,1)
  local atlas = key and load(g, family)
  local cell = atlas and atlas.quads and atlas.quads[key]
  if cell then
    local scale = math.min(w/cell.w, h/cell.h)
    g.draw(atlas.image,cell.quad,x+(w-cell.w*scale)/2,y+(h-cell.h*scale)/2,0,scale,scale)
  else
    local label = fallbackText or (family == "playstation" and PS_LABELS[key]) or LABELS[key] or "?"
    if family == "playstation" or family == "ayn_thor" or family == "steamdeck" then
      if key == "leftshoulder" then label="L1"
      elseif key == "rightshoulder" then label="R1" end
    end
    if family == "ayn_thor" and key == "start" then label = "START" end
    placeholder(g, label, x, y, w, h, key == "leftshoulder" or key == "rightshoulder" or key == "start")
  end
  g.setColor(unpack(previous))
  return true
end

function Glyphs.release()
  for _, atlas in pairs(cached) do
    for _, cell in pairs(atlas.quads or {}) do
      if cell.quad.release then cell.quad:release() end
    end
    if atlas.image and atlas.image.release then atlas.image:release() end
  end
  cached,reported,input,enabled,warn,modRef,iconStyle = {},{},nil,false,nil,nil,"auto"
end

return Glyphs
