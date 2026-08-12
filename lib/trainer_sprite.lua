-- Shared native-trainer portrait compositor for Stadium battle scenes.
--
-- Gen 1 and Gen 2 trainer portraits are cartridge BG-tile pictures. Their
-- colour-zero "paper" is intentionally opaque because the original battle
-- fields are solid paper. When those same portraits are composited over the
-- Stadium 3D scene, that paper becomes a rectangular box. This helper removes
-- only the edge-connected paper region, preserving enclosed light details.
local TrainerSprite = {}

local masks = setmetatable({}, { __mode = "k" })
local keyed = setmetatable({}, { __mode = "k" })
local keyedPaths = setmetatable({}, { __mode = "k" })

local function imageDataOf(image)
  local g = love and love.graphics
  if not (g and g.newCanvas and g.draw and image and image.getDimensions) then
    return nil
  end
  local w, h = image:getDimensions()
  if not (w and h and w > 0 and h > 0) then return nil end
  local ok, canvas = pcall(g.newCanvas, w, h,
    { format = "rgba8", readable = true, dpiscale = 1 })
  if not ok or not canvas then return nil end

  local previous = g.getCanvas and { g.getCanvas() } or nil
  local oldShader = g.getShader and g.getShader() or nil
  local oldBlend, oldAlpha = g.getBlendMode()
  local success, data = pcall(function()
    g.setCanvas(canvas)
    g.clear(0, 0, 0, 0)
    g.setBlendMode("replace", "premultiplied")
    if g.setShader then g.setShader() end
    g.setColor(1, 1, 1, 1)
    g.draw(image, 0, 0)
    return canvas:newImageData()
  end)

  if previous and #previous > 0 then
    g.setCanvas((table.unpack or unpack)(previous))
  else
    g.setCanvas()
  end
  if g.setShader then g.setShader(oldShader) end
  g.setBlendMode(oldBlend or "alpha", oldAlpha)
  g.setColor(1, 1, 1, 1)
  if canvas.release then pcall(canvas.release, canvas) end
  return success and data or nil
end

local function floodMask(data, paper, traverseTransparent)
  local w, h = data:getDimensions()
  local mask, seen, queue, head = {}, {}, {}, 1
  local function idx(x, y) return y * w + x + 1 end
  local function visitable(x, y)
    local _, _, _, a = data:getPixel(x, y)
    if a < .5 then return traverseTransparent end
    return paper(x, y)
  end
  local function push(x, y)
    local i = idx(x, y)
    if seen[i] or not visitable(x, y) then return end
    seen[i] = true
    queue[#queue + 1] = { x, y }
  end
  for x = 0, w - 1 do
    push(x, 0)
    if h > 1 then push(x, h - 1) end
  end
  for y = 1, h - 2 do
    push(0, y)
    if w > 1 then push(w - 1, y) end
  end
  while head <= #queue do
    local q = queue[head]
    head = head + 1
    local x, y = q[1], q[2]
    local _, _, _, a = data:getPixel(x, y)
    if a >= .5 and paper(x, y) then mask[idx(x, y)] = true end
    if x > 0 then push(x - 1, y) end
    if x + 1 < w then push(x + 1, y) end
    if y > 0 then push(x, y - 1) end
    if y + 1 < h then push(x, y + 1) end
  end
  local count = 0
  for _ in pairs(mask) do count = count + 1 end
  if count == 0 then return nil end
  return { w = w, h = h, bg = mask }
end

local function paperMaskData(data, mode)
  if not data then return nil end
  mode = mode or "edge"
  local w, h = data:getDimensions()

  -- Gen 2 opponent trainer portraits are currently written by
  -- RomExtractorGen2:extractMenuGfx with write2bpp(..., transparent=nil), so
  -- their shade-0 paper is opaque. Older/newer caches may already contain
  -- some transparent padding. Treat alpha as outside space and flood through
  -- it until we reach edge-connected shade 0.
  if mode == "shade0" then
    local function paper(x, y)
      local r, g, b, a = data:getPixel(x, y)
      return a >= .5 and r >= .94 and g >= .94 and b >= .94
    end
    return floodMask(data, paper, true)
  end

  -- Gen 1's trainer pictures may already be palette-baked by the host. Find
  -- their paper from the dominant opaque edge color and flood only that color.
  local colors = {}
  local function sample(x, y)
    local r, g, b, a = data:getPixel(x, y)
    if a < .5 then return end
    local rr = math.floor(r * 255 + .5)
    local gg = math.floor(g * 255 + .5)
    local bb = math.floor(b * 255 + .5)
    local key = rr * 65536 + gg * 256 + bb
    local row = colors[key]
    if row then row.n = row.n + 1
    else colors[key] = { n = 1, r = r, g = g, b = b } end
  end
  for x = 0, w - 1 do
    sample(x, 0)
    if h > 1 then sample(x, h - 1) end
  end
  for y = 1, h - 2 do
    sample(0, y)
    if w > 1 then sample(w - 1, y) end
  end

  local best
  for _, row in pairs(colors) do
    if not best or row.n > best.n then best = row end
  end
  if not best then return nil end

  local tolerance = 3 / 255
  local function paper(x, y)
    local r, g, b, a = data:getPixel(x, y)
    return a > .5
      and math.abs(r - best.r) <= tolerance
      and math.abs(g - best.g) <= tolerance
      and math.abs(b - best.b) <= tolerance
  end
  return floodMask(data, paper, false)
end

local function paperMask(image, mode)
  mode = mode or "edge"
  local byMode = masks[image]
  if not byMode then
    byMode = {}
    masks[image] = byMode
  elseif byMode[mode] ~= nil then
    return byMode[mode] or nil
  end

  local data = imageDataOf(image)
  if not data then byMode[mode] = false; return nil end
  local result = paperMaskData(data, mode)
  byMode[mode] = result or false
  return result
end

function TrainerSprite.keyed(base, variant, mode)
  if not (base and variant) then return variant end
  mode = mode or "edge"
  local mask = paperMask(base, mode)
  if not mask then return variant end

  local modes = keyed[base]
  if not modes then
    modes = {}
    keyed[base] = modes
  end
  local variants = modes[mode]
  if not variants then
    variants = setmetatable({}, { __mode = "k" })
    modes[mode] = variants
  end
  local cached = variants[variant]
  if cached then return cached end

  local data = imageDataOf(variant)
  if not data then return variant end
  local w, h = data:getDimensions()
  if w ~= mask.w or h ~= mask.h then return variant end

  for y = 0, h - 1 do
    for x = 0, w - 1 do
      if mask.bg[y * w + x + 1] then
        local r, g, b = data:getPixel(x, y)
        data:setPixel(x, y, r, g, b, 0)
      end
    end
  end

  local g = love and love.graphics
  if not (g and g.newImage) then return variant end
  local ok, out = pcall(g.newImage, data)
  if not ok or not out then return variant end
  if variant.getFilter and out.setFilter then
    local min, mag = variant:getFilter()
    out:setFilter(min or "nearest", mag or "nearest")
  end
  variants[variant] = out
  return out
end

local function applyMask(data, mask)
  if not (data and mask) then return data end
  local w, h = data:getDimensions()
  if w ~= mask.w or h ~= mask.h then return data end
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      if mask.bg[y * w + x + 1] then
        local r, g, b = data:getPixel(x, y)
        data:setPixel(x, y, r, g, b, 0)
      end
    end
  end
  return data
end

-- Gen 2 has the original asset path in BattleState. Read the PNG bytes
-- directly through Assets.imageData instead of GPU-readbacking the already
-- loaded Image. This is the authoritative source and avoids any dependency on
-- the active canvas, shader, blend mode, or draw wrapper during the intro.
function TrainerSprite.fromPath(path, fallback, mode)
  if not (path and fallback) then return fallback end
  mode = mode or "shade0"
  local byMode = keyedPaths[fallback]
  if not byMode then
    byMode = {}
    keyedPaths[fallback] = byMode
  elseif byMode[mode] ~= nil then
    return byMode[mode] or fallback
  end

  local okAssets, Assets = pcall(require, "src.render.Assets")
  if not (okAssets and Assets and type(Assets.imageData) == "function") then
    byMode[mode] = false
    return fallback
  end
  local ok, data = pcall(Assets.imageData, path)
  if not ok or not data then
    byMode[mode] = false
    return fallback
  end
  local mask = paperMaskData(data, mode)
  if not mask then
    byMode[mode] = false
    return fallback
  end
  applyMask(data, mask)

  local g = love and love.graphics
  if not (g and g.newImage) then
    byMode[mode] = false
    return fallback
  end
  local made, out = pcall(g.newImage, data)
  if not made or not out then
    byMode[mode] = false
    return fallback
  end
  if fallback.getFilter and out.setFilter then
    local min, mag = fallback:getFilter()
    out:setFilter(min or "nearest", mag or "nearest")
  end
  byMode[mode] = out
  return out
end

-- Test seams.
TrainerSprite._paperMask = paperMask
TrainerSprite._paperMaskData = paperMaskData
TrainerSprite._floodMask = floodMask
TrainerSprite._imageDataOf = imageDataOf
TrainerSprite._applyMask = applyMask

return TrainerSprite
