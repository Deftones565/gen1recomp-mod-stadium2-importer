-- Shared translation of Stadium/N64 texture sampler state into the normalized
-- UV and wrap controls used by the standalone renderer.
local Sampler = {}
local floor = math.floor

local function shiftFactor(value)
  value = math.floor(tonumber(value) or 0) % 16
  if value <= 10 then return 1 / (2 ^ value) end
  return 2 ^ (16 - value)
end

local function wrap(mode)
  mode = math.floor(tonumber(mode) or 0)
  if mode % 2 == 1 then return "mirroredrepeat" end
  if math.floor(mode / 2) % 2 == 1 then return "clamp" end
  return "repeat"
end

function Sampler.wrap(state)
  state = type(state) == "table" and state or {}
  return wrap(state.cms), wrap(state.cmt)
end

-- Shader-side texture folding uses small numeric modes instead of relying on
-- string comparisons in GLSL. Keep these values stable: 0=clamp, 1=repeat,
-- 2=mirrored repeat.
function Sampler.wrapCode(mode)
  if mode == "repeat" then return 1 end
  if mode == "mirroredrepeat" then return 2 end
  return 0
end

-- Scrolling callback materials can accumulate tile origins over time. The
-- visible result is periodic for repeat/mirrored-repeat, so reduce the offset
-- on the CPU before it reaches a mediump mobile fragment shader. Clamp must
-- retain its absolute offset because moving past an edge is semantically
-- meaningful there.
function Sampler.foldOffset(value, mode)
  value = tonumber(value) or 0
  if mode == "repeat" then
    return value - floor(value)
  end
  if mode == "mirroredrepeat" then
    return value - floor(value / 2) * 2
  end
  return value
end

-- Repeated textures are periodic, so a common whole-tile origin may be
-- removed from every vertex in a primitive without changing the image.
-- Doing this before rasterization matters on GLES2: once a large coordinate
-- has been interpolated at mediump precision, fragment-side mod/fract cannot
-- recover the fractional texel detail which was already discarded.
function Sampler.coordinateAnchor(minimum, maximum, mode)
  minimum, maximum = tonumber(minimum) or 0, tonumber(maximum) or 0
  local center = (minimum + maximum) * 0.5
  if mode == "repeat" then return floor(center) end
  if mode == "mirroredrepeat" then return floor(center / 2) * 2 end
  return 0
end

function Sampler.uvScale(state, textureScale)
  state = type(state) == "table" and state or {}
  textureScale = type(textureScale) == "table" and textureScale or { 1, 1 }
  return (tonumber(textureScale[1]) or 1) * shiftFactor(state.shifts),
    (tonumber(textureScale[2]) or 1) * shiftFactor(state.shiftt)
end

-- G_TEXTURE_GEN produces an s/t span from -1..+1 normals. Nintendo's
-- documented gSPTexture scale for a texture coordinate maximum is max<<6.
-- Convert the stored .16 scale and tile shift into normalized shader UVs.
function Sampler.textureGenScale(state, textureScale, width, height)
  local us, vs = Sampler.uvScale(state, textureScale)
  width, height = math.max(1, tonumber(width) or 1), math.max(1, tonumber(height) or 1)
  return us * 1024 / width, vs * 1024 / height
end

return Sampler
