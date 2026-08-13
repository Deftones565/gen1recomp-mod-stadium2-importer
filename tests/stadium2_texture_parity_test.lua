package.path = "./?.lua;./?/init.lua;" .. package.path

local TextureParity = require("mods.STADIUM2_IMPORTER.lib.texture_parity")

local failures = 0
local function ok(value, name)
  if value then print("PASS " .. name)
  else failures = failures + 1; print("FAIL " .. name) end
end

local rgba = string.rep(string.char(20, 80, 160, 255), 16)
local complete = TextureParity.audit({
  textures = {{ w = 4, h = 4, rgba = rgba }, { w = 1, h = 1, rgba = "\255\255\255\255" }},
  prims = {
    { tex = 1, texMap = { [3] = 1 } },
    { tex = 2, sourceTextureMissing = true },
  },
}, { indexBase = 1 })
ok(#complete.issues == 0, "authored and intentional neutral texture routes resolve")
ok(complete.metrics.texturedPrimitives == 1 and complete.metrics.untexturedPrimitives == 1,
  "intentional untextured surfaces remain distinguishable in DSM")

local broken = TextureParity.audit({
  textures = {{ w = 4, h = 4, rgba = "short" }},
  prims = {{ tex = 1, texMap = { [4] = 2 } }},
}, { indexBase = 1 })
ok(broken.rules.TEXTURE_PAYLOAD_INVALID == 1,
  "truncated RGBA payload is audited")
ok(broken.rules.TEXTURE_REFERENCE_INVALID == 2,
  "invalid base and animation texture routes are audited")

if failures > 0 then os.exit(1) end
