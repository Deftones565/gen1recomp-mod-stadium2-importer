-- Shared Stadium 2 flame object used by fragment 26 descriptor 0x81000038.
--
-- The mesh and material below are ROM data/behaviour, not a Pokemon-specific
-- approximation. func_810059D0 loads one of eight IA16 source images, then
-- reinterprets each 0x800-byte payload through its 32x64 IA8 render tile, and
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

-- func_810059D0 loads the source as IA16, then installs an IA8 render tile
-- with G_TX_CLAMP in both axes (F5680800 00080200). Its line and tile-size
-- fields reinterpret the payload as the single 32x64 image used by the card.
Flame.SAMPLER = {
  cms = 2, cmt = 2, masks = 0, maskt = 0, shifts = 0, shiftt = 0,
}

-- Literal order of the ten Vtx records at 0x8009F228. This is deliberately
-- not generated as row pairs: the ROM stores the first four vertices around
-- the top cell, then appends pairs for the remaining rows. Its display list
-- uses that order to choose the interpolation diagonal in each cell.
local vertices = {
  -- x,   y,    s,    t, blue
  { -50, 200,    0,    0,   0 },
  { -50, 150,    0,  512,   0 },
  {  50, 150, 1024,  512,   0 },
  {  50, 200, 1024,    0,   0 },
  { -50, 100,    0, 1024,   0 },
  {  50, 100, 1024, 1024,   0 },
  { -50,  50,    0, 1536, 192 },
  {  50,  50, 1024, 1536, 192 },
  { -50,   0,    0, 2048, 128 },
  {  50,   0, 1024, 2048, 128 },
}

function Flame.geometry(bone)
  local pos, uv, nrm, color, skin = {}, {}, {}, {}, {}
  for i, values in ipairs(vertices) do
    pos[i * 3 - 2], pos[i * 3 - 1], pos[i * 3] = values[1], values[2], 0
    -- N64 Vtx s/t are S10.5. The callback renders a 32x64 IA8 tile, so its
    -- S span is 1024 coordinate units and its T span is 2048.
    uv[i * 2 - 1], uv[i * 2] = values[3] / 1024, values[4] / 2048
    nrm[i * 3 - 2], nrm[i * 3 - 1], nrm[i * 3] = 0, 0, 1
    color[i * 4 - 3], color[i * 4 - 2] = 255, 255
    color[i * 4 - 1], color[i * 4] = values[5], 255
    skin[i] = bone
  end
  return {
    pos = pos, uv = uv, nrm = nrm, color = color, skin = skin, nverts = 10,
    idx = { 1,2,3, 1,3,4, 2,5,6, 2,6,3,
            5,7,8, 5,8,6, 7,9,10, 7,10,8 },
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
