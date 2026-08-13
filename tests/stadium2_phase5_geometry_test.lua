package.path = "./?.lua;./?/init.lua;" .. package.path

local Phase5 = require("mods.STADIUM2_IMPORTER.lib.render_callbacks.phase5_geometry")

local failures = 0
local function ok(value, name)
  if value then print("PASS " .. name) else failures = failures + 1; print("FAIL " .. name) end
end
local function be16(value)
  return string.char(math.floor(value / 256) % 256, value % 256)
end
local function be32(value)
  return string.char(math.floor(value / 0x1000000) % 256,
    math.floor(value / 0x10000) % 256, math.floor(value / 0x100) % 256, value % 256)
end
local function write(bytes, offset, value)
  return bytes:sub(1, offset) .. value .. bytes:sub(offset + #value + 1)
end

local base = 0x8FF00000
local fragment = string.rep("\0", 0x100)
fragment = write(fragment, 0x10, be32(base + 0x30)) -- callback argument -> item
fragment = write(fragment, 0x30, be32(base + 0x50)) -- item -> image config
fragment = write(fragment, 0x38, be32(base + 0x70)) -- item -> colors
fragment = write(fragment, 0x3C, be32(base + 0x88)) -- item -> geometry/texture state
fragment = write(fragment, 0x50, be32(base + 0x90)) -- image config -> texels
fragment = write(fragment, 0x58, be32(base + 0x60)) -- image config -> descriptor
fragment = write(fragment, 0x60, string.char(0, 3, 5, 5, 1, 1, 1, 1)
  .. be16(32) .. be16(32))
fragment = write(fragment, 0x74, be32(base + 0x80))
fragment = write(fragment, 0x78, be32(base + 0x84))
fragment = write(fragment, 0x80, string.char(1, 31, 3, 31, 255, 255, 255, 255))
fragment = write(fragment, 0x88, be32(0x00040000) .. be16(4500) .. be16(4500))

local specs = Phase5.textureSpecs(fragment, base, 0x10)
ok(#specs == 1 and specs[1].pointer == base + 0x90, "phase-5 texture pointer decoded")
ok(specs[1] and specs[1].w == 32 and specs[1].h == 32
  and specs[1].format == 0 and specs[1].size == 3, "phase-5 texture descriptor decoded")
ok(specs[1] and specs[1].sampler.masks == 1 and specs[1].sampler.maskt == 1
  and specs[1].sampler.shifts == 1 and specs[1].sampler.shiftt == 1,
  "phase-5 sampler descriptor decoded")
local material = Phase5.materialSpec(fragment, base, 0x10)
ok(material and math.abs(material.primitiveColor[2] - 31 / 255) < 0.0001,
  "phase-5 primitive color decoded")
ok(material and material.primitiveColor[4] == 1 and material.environmentColor[1] == 1,
  "phase-5 model alpha and environment color decoded")
local renderState = Phase5.stateSpec(fragment, base, 0x10)
ok(renderState and renderState.geometryMode == 0x00040000
  and math.abs(renderState.textureScale[1] - 4500 / 65536) < 0.000001,
  "phase-5 reflection geometry mode and gSPTexture scale decoded")

local state = { textureBySite = {}, materialBySite = {}, renderTimeResolvedBySite = {} }
ok(Phase5.apply(state, 0x1234, { operation = "render-time-geometry-pipeline",
  geometryIndex = 0, program = { textures = {{slot = 10, pointer = base + 0x90}},
    phase5Material = material } }), "phase-5 state applied")
ok(state.textureBySite[0x1234] == 11 and state.materialBySite[0x1234] == material,
  "phase-5 texture and material reach renderer state")
ok(state.renderTimeResolvedBySite[0x1234] ~= nil, "phase-5 queue consumption is auditable")

if failures > 0 then os.exit(1) end
