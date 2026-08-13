-- Shared translation of Stadium/N64 texture sampler state into the normalized
-- UV and wrap controls used by the standalone renderer.
local Sampler = {}

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
