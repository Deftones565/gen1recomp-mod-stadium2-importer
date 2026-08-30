-- Exact render contract for fragment26 descriptor 0x81000048.
-- func_81005DB4 allocates a 0xF0-byte display list and calls func_81005B50,
-- which loads two 32x32 RGBA16 images and the fixed material at 0x810061B0.
local DualTexture = {}

DualTexture.DESCRIPTOR = 0x81000048
DualTexture.TARGET = 0x81005DB4
DualTexture.BUILDER = 0x81005B50
DualTexture.MATERIAL = 0x810061B0
DualTexture.ALLOCATION_BYTES = 0xF0
DualTexture.WIDTH = 32
DualTexture.HEIGHT = 32
DualTexture.COMBINE = { 0x262A04, 0x1F1893FF }
DualTexture.ENVIRONMENT_ALPHA = 100 / 255

local function signed16(value)
  value = value % 0x10000
  return value >= 0x8000 and value - 0x10000 or value
end

local function tile12(value) return value % 0x1000 end

-- Reproduce 0x81005BFC..0x81005D9C. Origins are N64 10.2 values.
-- RDP subtracts the upper-left tile coordinate before applying its mask, so
-- normalized sampling offsets use the negative origin.
function DualTexture.state(frame)
  frame = math.floor(tonumber(frame) or 0) % 0x10000
  local negative16 = signed16(-frame * 16)
  local firstS = math.floor(negative16 / 16)
  local firstT = signed16(0x4000 - firstS)
  local secondS = tile12(firstT)
  local secondT = signed16(0x4000 - math.floor(negative16 / 8))
  local origins = {
    { tile12(firstS), tile12(firstT) },
    { secondS, tile12(secondT) },
  }
  return {
    frame = frame,
    tileOrigins = origins,
    textureScroll = {
      { -origins[1][1] / (4 * DualTexture.WIDTH),
        -origins[1][2] / (4 * DualTexture.HEIGHT) },
      { -origins[2][1] / (4 * DualTexture.WIDTH),
        -origins[2][2] / (4 * DualTexture.HEIGHT) },
    },
    wrap = "repeat",
    mix = DualTexture.ENVIRONMENT_ALPHA,
    combine = DualTexture.COMBINE,
    combineMode = "lerp-then-shade",
    -- The shader implements the ROM combine equation explicitly through the
    -- secondary layer and ordinary SHADE path. Do not also inherit an
    -- authored primitive/environment combiner from the source draw.
    material = {
      primitiveColor = { 1, 1, 1, 1 },
      environmentColor = { 1, 1, 1, 1 },
      combine = { 0, 0 },
      callbackCombine = DualTexture.COMBINE,
    },
  }
end

function DualTexture.ownsPrimitive(prim, descriptor)
  return type(prim) == "table"
    and (descriptor or prim.callbackDescriptor) == DualTexture.DESCRIPTOR
    and prim.decal ~= true
end

local function uniformTexture(texture)
  local rgba = texture and texture.rgba
  if type(rgba) ~= "string" or #rgba < 4 then return false end
  local first = rgba:sub(1, 4)
  for pixel = 5, #rgba, 4 do
    if rgba:sub(pixel, pixel + 3) ~= first then return false end
  end
  return true
end

local function sameTexture(a, b)
  return a ~= nil and b ~= nil
    and tonumber(a.w) == tonumber(b.w) and tonumber(a.h) == tonumber(b.h)
    and type(a.rgba) == "string" and a.rgba == b.rgba
end

local function generatedCarrierAtlas(prim, authored, callback)
  if not (authored ~= nil and callback ~= nil
      and tonumber(authored.w) == 32 and tonumber(authored.h) == 64
      and tonumber(callback.w) == DualTexture.WIDTH
      and tonumber(callback.h) == DualTexture.HEIGHT) then
    return false
  end
  -- Muk reuses its tongue atlas as the source state for two rear-head shells.
  -- Those shells extend high through model space; the actual Muk tongue and
  -- every Grimer tongue segment remain low around the mouth/base. This is the
  -- stable geometry distinction produced by the ROM display lists.
  local maxY = -math.huge
  for at = 2, #(prim and prim.pos or {}), 3 do
    maxY = math.max(maxY, tonumber(prim.pos[at]) or -math.huge)
  end
  return maxY > 80
end

local function generatedCarrierGeometry(prim, authored, callback)
  -- The current 64x32 eye-texture state also reaches Grimer's large arm
  -- meshes and Muk's two small head shells before command 0x08 replaces it.
  -- Muk's medium-sized 53-vertex eye/pupil mesh is the authored exception.
  local vertices = tonumber(prim and prim.nverts) or 0
  return authored ~= nil and callback ~= nil
    and tonumber(authored.w) == 64 and tonumber(authored.h) == 32
    and tonumber(callback.w) == DualTexture.WIDTH
    and tonumber(callback.h) == DualTexture.HEIGHT
    and (vertices < 32 or vertices > 64)
end

-- A 0x48 callback owns the model's uniform carrier, or an authored image
-- which is byte-identical to its first generated tile. Other authored images
-- are local detail atlases, not either texture argument passed to the ROM
-- builder. Their primary UVs remain authored; the renderer may still apply
-- the callback's secondary tile through the ROM combiner.
function DualTexture.ownsAuthoredTexture(prim, authoredTexture, callbackTexture,
    descriptor)
  return DualTexture.ownsPrimitive(prim, descriptor)
    and (uniformTexture(authoredTexture)
      or sameTexture(authoredTexture, callbackTexture)
      or generatedCarrierAtlas(prim, authoredTexture, callbackTexture)
      or generatedCarrierGeometry(prim, authoredTexture, callbackTexture))
end

return DualTexture
