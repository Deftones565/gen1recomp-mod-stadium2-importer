package.path = "./?.lua;./?/init.lua;" .. package.path

local Parity = require("mods.STADIUM2_IMPORTER.lib.model_parity")

local model = {
  species = 1,
  prims = {{
    tex = 0, cull = true, geometryMode = 0x400, vertexSemantics = "color",
    color = { 20, 40, 60, 128 }, nidx = 3, callbackOffset = 0x20,
    callbackTextureRequired = nil,
  }},
  fx = {{ handler = 0x81000140, commandOffset = 0x20 }},
  handlerTextures = {{ commandOffset = 0x20,
    sampler = { cms = 0, cmt = 0, masks = 5, maskt = 5, shifts = 1, shiftt = 1 } }},
  anims = {{ frames = 80 }, { frames = 100 }},
  auxAnims = {{ frames = 5 }, { frames = 100 }},
}

local report = Parity.auditModel(model, "", 0x8FF00000, { packSupportsVertexColor = false })
local failures = 0
local function ok(value, name)
  if value then print("PASS " .. name) else failures = failures + 1; print("FAIL " .. name) end
end

ok(report.rules.PACK_VERTEX_COLOR_LOSS == 1, "vertex colour loss is semantic, not texture coverage")
ok(report.rules.PACK_SAMPLER_STATE_LOSS == 1, "callback sampler loss detected")
ok(report.rules.CALLBACK_TEXTURE_OVERRIDES_AUTHORED_TEXTURE == 1,
  "site-wide callback override of authored texture detected")
ok(report.metrics.auxAligned == 1, "authored-order auxiliary alignment detected")
ok(report.metrics.primitives == 1 and report.metrics.triangles == 1, "topology metrics retained")

local leak = Parity.auditModel({ species = 208, prims = {{
  tex = 0, nrm = {119/127,0,0}, color = {}, nidx = 3,
  geometryMode = 0x60400, vertexSemantics = "normal", lighting = true,
  callbackDescriptor = 0x81000140, callbackOffset = 0x40,
  callbackTextureRequired = false,
}}, textures = {{w=1,h=1,rgba="\255\255\255\255"}},
  fx = {}, handlerTextures = {}, anims = {}, auxAnims = {} }, "", 0, {})
ok(leak.rules.AUTHORED_TEXTURE_TEXGEN_LEAK == 1,
  "reflection state leaking onto authored eye UVs is detected")

if failures > 0 then os.exit(1) end
