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

return DualTexture
