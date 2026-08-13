-- Shared Stadium 2 flame object used by fragment 26 descriptor 0x81000038.
--
-- The mesh and material below are ROM data/behaviour, not a Pokemon-specific
-- approximation. func_810059D0 installs one of eight 32x32 IA16 images and
-- func_80070974 draws the object display list at 0x8009F2E0. Its vertices are
-- the ten Vtx records at 0x8009F228.
local Flame = {}

Flame.DESCRIPTOR = 0x81000038
Flame.ROM = {
  vertexAddress = 0x8009F228,
  displayListAddress = 0x8009F2E0,
  materialAddress = 0x8009F448,
  textureBuilder = 0x810059D0,
  objectPrepare = 0x8007087C,
  objectDraw = 0x80070974,
}

local rows = {
  -- y, texture t, blue channel. The source Vtx colors are (255,255,b,255).
  { 200,    0,   0 },
  { 150,  512,   0 },
  { 100, 1024,   0 },
  {  50, 1536, 192 },
  {   0, 2048, 128 },
}

function Flame.geometry(bone)
  local pos, uv, nrm, color, skin = {}, {}, {}, {}, {}
  for row, values in ipairs(rows) do
    for side = 0, 1 do
      local i = (row - 1) * 2 + side + 1
      pos[i * 3 - 2] = side == 0 and -50 or 50
      pos[i * 3 - 1] = values[1]
      pos[i * 3] = 0
      -- N64 Vtx s/t are S10.5. The 32x32 tile therefore maps 1024 units to
      -- one image width/height; T=2048 deliberately repeats it twice.
      uv[i * 2 - 1] = side
      uv[i * 2] = values[2] / 1024
      nrm[i * 3 - 2], nrm[i * 3 - 1], nrm[i * 3] = 0, 0, 1
      color[i * 4 - 3], color[i * 4 - 2] = 255, 255
      color[i * 4 - 1], color[i * 4] = values[3], 255
      skin[i] = bone
    end
  end
  return {
    pos = pos, uv = uv, nrm = nrm, color = color, skin = skin, nverts = 10,
    idx = { 1,2,3, 1,3,4, 3,4,5, 3,5,6,
            5,6,7, 5,7,8, 7,8,9, 7,9,10 },
    nidx = 24,
  }
end

-- func_80070A4C has explicit branches for Magmar and Moltres. All other
-- users pulse the red environment channel from 180 down to 110 over 8 ticks.
function Flame.material(species, displayFrame)
  species = math.floor(tonumber(species) or -1)
  local frame = math.floor(tonumber(displayFrame) or 0) % 8
  local primitive, environment
  if species == 126 then
    primitive = { 1, 1, 5 / 255, 1 }
    environment = { 1, 32 / 255, 0, 0 }
  elseif species == 146 then
    primitive = { 1, 1, 1, 200 / 255 }
    environment = { 1, 32 / 255, 0, 0 }
  else
    primitive = { 1, 1, 1, 1 }
    environment = { (180 - frame * 10) / 255, 32 / 255, 0, 0 }
  end
  return {
    primitiveColor = primitive,
    environmentColor = environment,
    combine = { 0xFC309680, 0x5F1AFFFF },
    intensity = true,
  }
end

return Flame
