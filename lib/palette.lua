local Palette = {}

local function clamp(value, low, high)
  if value < low then return low end
  if value > high then return high end
  return value
end

local function rgbToHsv(r, g, b)
  r, g, b = r / 255, g / 255, b / 255
  local max = math.max(r, g, b)
  local min = math.min(r, g, b)
  local d = max - min
  local h = 0
  if d ~= 0 then
    if max == r then h = ((g - b) / d) % 6
    elseif max == g then h = (b - r) / d + 2
    else h = (r - g) / d + 4 end
    h = h / 6
  end
  local s = max == 0 and 0 or d / max
  return h, s, max
end

local function hsvToRgb(h, s, v)
  h = (h % 1) * 6
  local c = v * s
  local x = c * (1 - math.abs(h % 2 - 1))
  local m = v - c
  local r, g, b
  if h < 1 then r, g, b = c, x, 0
  elseif h < 2 then r, g, b = x, c, 0
  elseif h < 3 then r, g, b = 0, c, x
  elseif h < 4 then r, g, b = 0, x, c
  elseif h < 5 then r, g, b = x, 0, c
  else r, g, b = c, 0, x end
  return clamp(math.floor((r + m) * 255 + 0.5), 0, 255),
    clamp(math.floor((g + m) * 255 + 0.5), 0, 255),
    clamp(math.floor((b + m) * 255 + 0.5), 0, 255)
end

local function colour(palette, index)
  local row = palette and palette[index]
  if type(row) ~= "table" then return nil end
  return tonumber(row[1]), tonumber(row[2]), tonumber(row[3])
end

function Palette.recolour(rgba, normal, shiny)
  if type(rgba) ~= "string" or type(normal) ~= "table" or type(shiny) ~= "table" then
    return rgba
  end
  local out = {}
  local last = 1
  for i = 1, #rgba, 4 do
    local r, g, b, a = rgba:byte(i, i + 3)
    if not a then break end
    local best, bestDistance
    for index = 1, math.max(#normal, #shiny) do
      local nr, ng, nb = colour(normal, index)
      local sr, sg, sb = colour(shiny, index)
      if nr and sr then
        local distance = (r - nr) ^ 2 + (g - ng) ^ 2 + (b - nb) ^ 2
        if not bestDistance or distance < bestDistance then
          bestDistance = distance
          best = { nr, ng, nb, sr, sg, sb }
        end
      end
    end
    if best then
      local nh, ns, nv = rgbToHsv(best[1], best[2], best[3])
      local sh, ss, sv = rgbToHsv(best[4], best[5], best[6])
      local h, s, v = rgbToHsv(r, g, b)
      local dh = sh - nh
      if dh > 0.5 then dh = dh - 1 elseif dh < -0.5 then dh = dh + 1 end
      r, g, b = hsvToRgb(h + dh, clamp(s + ss - ns, 0, 1), clamp(v + sv - nv, 0, 1))
    end
    out[last] = string.char(r, g, b, a)
    last = last + 1
  end
  return table.concat(out)
end

local function rgbToHsl(r, g, b)
  r, g, b = r / 255, g / 255, b / 255
  local hi, lo = math.max(r, g, b), math.min(r, g, b)
  local light = (hi + lo) / 2
  if hi == lo then return 0, 0, light end
  local delta = hi - lo
  local saturation = light > 0.5 and delta / (2 - hi - lo)
    or delta / (hi + lo)
  local hue
  if hi == r then hue = ((g - b) / delta + (g < b and 6 or 0)) / 6
  elseif hi == g then hue = ((b - r) / delta + 2) / 6
  else hue = ((r - g) / delta + 4) / 6 end
  return hue, saturation, light
end

local function hueChannel(p, q, t)
  t = t % 1
  if t < 1 / 6 then return p + (q - p) * 6 * t end
  if t < 1 / 2 then return q end
  if t < 2 / 3 then return p + (q - p) * (2 / 3 - t) * 6 end
  return p
end

local function hslToRgb(hue, saturation, light)
  local r, g, b
  if saturation == 0 then
    r, g, b = light, light, light
  else
    local q = light < 0.5 and light * (1 + saturation)
      or light + saturation - light * saturation
    local p = 2 * light - q
    r = hueChannel(p, q, hue + 1 / 3)
    g = hueChannel(p, q, hue)
    b = hueChannel(p, q, hue - 1 / 3)
  end
  return clamp(math.floor(r * 255 + 0.5), 0, 255),
    clamp(math.floor(g * 255 + 0.5), 0, 255),
    clamp(math.floor(b * 255 + 0.5), 0, 255)
end

local function signed8(value)
  return value and (value >= 0x80 and value - 0x100 or value) or nil
end

-- Stadium 2's species metadata stores its rare-colour operation directly:
-- signed 10.6-degree hue followed by signed saturation/lightness steps.
-- FF FF FF FF is the game's dedicated-texture sentinel.
function Palette.decodeRare(data, offset)
  if type(data) ~= "string" then return nil end
  offset = math.floor(tonumber(offset) or 0)
  local hi, lo, saturation, lightness = data:byte(offset + 1, offset + 4)
  if not lightness then return nil end
  if hi == 0xff and lo == 0xff and saturation == 0xff
      and lightness == 0xff then
    return { specialTexture = true }
  end
  local rawHue = hi * 0x100 + lo
  if rawHue >= 0x8000 then rawHue = rawHue - 0x10000 end
  return {
    hue = rawHue / 64,
    saturation = signed8(saturation),
    lightness = signed8(lightness),
  }
end

-- Apply the same whole-model HSL operation used for ordinary Stadium 2 rare
-- colours. The signed S/L bytes are sixteenths of their normalized channels.
-- Pixels with partial alpha are model-local fire, gas, glow or similar FX;
-- Stadium renders those separately and does not pass them through this shift.
function Palette.applyRare(rgba, rare)
  if type(rgba) ~= "string" or type(rare) ~= "table"
      or rare.specialTexture then return rgba end
  local hueShift = (tonumber(rare.hue) or 0) / 360
  local saturationShift = (tonumber(rare.saturation) or 0) / 16
  local lightnessShift = (tonumber(rare.lightness) or 0) / 16
  if hueShift == 0 and saturationShift == 0 and lightnessShift == 0 then
    return rgba
  end
  local out = {}
  for offset = 1, #rgba, 4 do
    local r, g, b, a = rgba:byte(offset, offset + 3)
    if not a then break end
    if a ~= 255 then
      out[#out + 1] = rgba:sub(offset, offset + 3)
    else
      local h, s, l = rgbToHsl(r, g, b)
      r, g, b = hslToRgb(h + hueShift,
        clamp(s + saturationShift, 0, 1),
        clamp(l + lightnessShift, 0, 1))
      out[#out + 1] = string.char(r, g, b, a)
    end
  end
  return table.concat(out)
end

function Palette.decodeRgba5551(bytes, pixelCount)
  if type(bytes) ~= "string" then return nil, "texture record is not bytes" end
  pixelCount = math.floor(tonumber(pixelCount) or -1)
  if pixelCount < 0 or #bytes ~= pixelCount * 2 then
    return nil, ("RGBA5551 record has %d bytes; expected %d")
      :format(#bytes, math.max(0, pixelCount) * 2)
  end
  local out = {}
  for offset = 1, #bytes, 2 do
    local hi, lo = bytes:byte(offset, offset + 1)
    local value = hi * 0x100 + lo
    local r = math.floor(math.floor(value / 0x800) % 0x20 * 255 / 31)
    local g = math.floor(math.floor(value / 0x40) % 0x20 * 255 / 31)
    local b = math.floor(math.floor(value / 2) % 0x20 * 255 / 31)
    local a = value % 2 == 1 and 255 or 0
    out[#out + 1] = string.char(r, g, b, a)
  end
  return table.concat(out)
end

function Palette.nativeTextureBytes(w, h, siz)
  w = math.max(0, math.floor(tonumber(w) or 0))
  h = math.max(0, math.floor(tonumber(h) or 0))
  siz = math.floor(tonumber(siz) or -1)
  local pixels = w * h
  if siz == 0 then return math.floor((pixels + 1) / 2) end
  if siz == 1 then return pixels end
  if siz == 2 then return pixels * 2 end
  if siz == 3 then return pixels * 4 end
  return nil
end

function Palette.decodeNativeTexture(bytes, w, h, fmt, siz)
  if type(bytes) ~= "string" then return nil, "texture record is not bytes" end
  w = math.max(0, math.floor(tonumber(w) or 0))
  h = math.max(0, math.floor(tonumber(h) or 0))
  fmt = math.floor(tonumber(fmt) or -1)
  siz = math.floor(tonumber(siz) or -1)
  local pixels = w * h
  local expected = Palette.nativeTextureBytes(w, h, siz)
  if expected == nil then return nil, ("unsupported N64 texture size %s"):format(tostring(siz)) end
  if #bytes ~= expected then
    return nil, ("native texture has %d bytes; expected %d for %dx%d f%d/s%d")
      :format(#bytes, expected, w, h, fmt, siz)
  end

  local function nibble(i)
    local value = bytes:byte(math.floor(i / 2) + 1)
    if i % 2 == 1 then return value % 16 end
    return math.floor(value / 16)
  end

  if fmt == 0 and siz == 2 then return Palette.decodeRgba5551(bytes, pixels) end
  if fmt == 0 and siz == 3 then return bytes end

  local out = {}
  if fmt == 3 then
    for i = 0, pixels - 1 do
      local l, a
      if siz == 2 then
        l, a = bytes:byte(i * 2 + 1, i * 2 + 2)
      elseif siz == 1 then
        local value = bytes:byte(i + 1)
        l, a = math.floor(value / 16) * 17, value % 16 * 17
      elseif siz == 0 then
        local value = nibble(i)
        l = math.floor(math.floor(value / 2) * 255 / 7)
        a = value % 2 == 1 and 255 or 0
      else
        return nil, ("unsupported IA texture size %d"):format(siz)
      end
      out[#out + 1] = string.char(l, l, l, a)
    end
    return table.concat(out)
  end

  if fmt == 4 then
    if siz ~= 0 and siz ~= 1 then
      return nil, ("unsupported intensity texture size %d"):format(siz)
    end
    for i = 0, pixels - 1 do
      local l = siz == 1 and bytes:byte(i + 1) or nibble(i) * 17
      out[#out + 1] = string.char(l, l, l, 255)
    end
    return table.concat(out)
  end

  if fmt == 2 then return nil, "dedicated CI texture requires its TLUT" end
  return nil, ("unsupported dedicated N64 texture f%d/s%d"):format(fmt, siz)
end

function Palette.fromTransformSource(source)
  if type(source) ~= "string" then return nil end
  local hex = source:match('local%s+COLORS%s*=%s*"([0-9a-fA-F]+)"')
  if not hex or #hex < 151 * 12 then return nil end
  local out = {}
  local function byteAt(offset)
    return tonumber(hex:sub(offset, offset + 1), 16)
  end
  for dex = 1, 151 do
    local offset = (dex - 1) * 12 + 1
    out[dex] = {
      { 248, 248, 248 },
      { byteAt(offset), byteAt(offset + 2), byteAt(offset + 4) },
      { byteAt(offset + 6), byteAt(offset + 8), byteAt(offset + 10) },
      { 0, 0, 0 },
    }
  end
  return out
end

return Palette
