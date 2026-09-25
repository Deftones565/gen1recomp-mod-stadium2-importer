package.path = "./?.lua;./?/init.lua;" .. package.path

local Build = require("mods.STADIUM2_IMPORTER.lib.build")
local Pack = require("mods.STADIUM2_IMPORTER.lib.pack")
local Renderer = require("mods.STADIUM2_IMPORTER.lib.renderer")
local RenderContract = require("mods.STADIUM2_IMPORTER.lib.render_contract")
local Handlers = require("mods.STADIUM2_IMPORTER.lib.model_handlers")

local checks = 0
local function ok(value, message)
  checks = checks + 1
  if not value then error("FAIL " .. message, 0) end
end

ok(RenderContract.supportsCoplanarDecals(),
  "model depth contract preserves later coplanar eye and face layers")
ok(math.abs(Renderer.PINECO_DECAL_DEPTH_BIAS - 4/65535) < 0.000000001,
  "Pineco uses a minimal decal bias that cannot pull eyes through its shell")
ok(Renderer.ARENA_COPLANAR_DEPTH_BIAS == 32/65535,
  "arena floor markings retain a stable top-layer separation")
ok(Renderer.SHADER_SOURCE:find("n64Cycle", 1, true)
  and Renderer.SHADER_SOURCE:find("n64CombinerCycles", 1, true)
  and Renderer.SHADER_SOURCE:find("n64CoveragePassthrough", 1, true)
  and Renderer.SHADER_SOURCE:find("primaryIntensityAlpha", 1, true)
  and Renderer.SHADER_SOURCE:find("texel0.a = texel0.r", 1, true)
  and Renderer.SHADER_SOURCE:find("other.a = other.r", 1, true)
  and Renderer.SHADER_SOURCE:find("texel0,texel1,primitiveColor,color,environmentColor", 1, true),
  "arena shader evaluates ROM two-cycle combiners and I4 coverage")
local opaqueZeroAlpha = { phase5 = true, combiner = { alphaOutputZero = true } }
ok(Renderer.arenaCombinerCoveragePassthrough(
    { staticPose = true, species = 0 }, { arenaAlphaMode = "opaque" },
    opaqueZeroAlpha)
  and Renderer.arenaCombinerCoveragePassthrough(
    { staticPose = true, species = 0 }, { arenaAlphaMode = "cutout" },
    opaqueZeroAlpha)
  and not Renderer.arenaCombinerCoveragePassthrough(
    { staticPose = true, species = 0 }, { arenaAlphaMode = "blend" },
    opaqueZeroAlpha)
  and not Renderer.arenaCombinerCoveragePassthrough(
    { staticPose = false, species = 25 }, { arenaAlphaMode = "opaque" },
    opaqueZeroAlpha),
  "opaque arena combiners retain coverage without changing translucent or Pokemon alpha")
local decalCompare, decalWrite = RenderContract.depthState({
  sourceTextureMissing = false, decal = true, decalDepthWrite = true }, true)
local ordinaryDecalCompare, ordinaryDecalWrite = RenderContract.depthState({
  sourceTextureMissing = false, decal = true }, true)
local bodyCompare, bodyWrite = RenderContract.depthState({
  sourceTextureMissing = false, decal = false }, true)
local cutoutCompare, cutoutWrite = RenderContract.depthState({
  sourceTextureMissing = false, decal = true, arenaAlphaMode = "cutout" }, true)
local blendCompare, blendWrite = RenderContract.depthState({
  sourceTextureMissing = false, decal = true, arenaAlphaMode = "blend" }, true)
local layerCompare, layerWrite = RenderContract.depthState({
  sourceTextureMissing = false, coplanarLayer = 2 }, true)
local arenaLayerCompare, arenaLayerWrite = RenderContract.depthState({
  sourceTextureMissing = false, coplanarLayer = 2,
  arenaAlphaMode = "opaque" }, true)
ok(decalCompare == "lequal" and not decalWrite
  and ordinaryDecalCompare == "lequal" and not ordinaryDecalWrite
  and layerCompare == "lequal" and not layerWrite
  and arenaLayerCompare == "lequal" and arenaLayerWrite
  and cutoutCompare == "less" and cutoutWrite
  and blendCompare == "less" and not blendWrite
  and bodyCompare == "less" and bodyWrite,
  "model decals and modern arena alpha surfaces use their intended depth queues")

local function be16(value)
  return string.char(math.floor(value / 256) % 256, value % 256)
end

local fragment = string.rep("\0", 0x40) .. be16(4) .. be16(41) .. be16(2000) .. string.rep("\0", 0x80)
local handlers = Handlers.compile({
  { handler = 0x81000058, bone = 1, arg = 0x40, commandOffset = 0x80 },
  { handler = 0x81000080, bone = 0, arg = nil, commandOffset = 0x90 },
}, fragment, 0x8FF00000)

local moveRows = {}
for i = 1, 165 do moveRows[i] = { 0, 0 } end
local contexts = {}
for i = 1, #Build.CONTEXTS do contexts[i] = 0xFFFF end
contexts[1] = 0

local bytes = Build.pack({
  rootScale = { 1, 1, 1 },
  bones = {
    { parent = -1, t = { 0, 0, 0 }, r = { 0, 0, 0 }, s = { 1, 1, 1 } },
    { parent = 0, t = { 10, 0, 0 }, r = { 0, 0, 0 }, s = { 1, 1, 1 } },
  },
  prims = {
    {
      tex = 0, cull = 1, blend = "add", effect = "fire",
      texAnim = 0, texMap = { [5] = 1 },
      pos = { 0, 0, 0, 10, 0, 0, 0, 10, 0, 1000, 1000, 1000 },
      uv = { 0, 0, 1, 0, 0, 1, 1, 1 },
      nrm = { 0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 1, 0 },
      skin = { 1, 1, 1, 1 }, nverts = 4, idx = { 0, 1, 2 }, nidx = 3,
    },
  },
  textures = {
    { w = 1, h = 1, rgba = "\255\0\0\255" },
    { w = 1, h = 1, rgba = "\0\255\0\255" },
  },
  anims = {
    {
      name = "idle", frames = 2, loopStart = 0, aux = 0,
      tracks = {
        [2] = {
          t = { { 10, 20 }, 0, 0 },
          r = { 0, 0, 0 },
          s = { 1, 1, 1 },
        },
      },
    },
  },
  auxAnims = {
    { frames = 1, loopStart = 0, channels = { { n = 1, 5 } } },
  },
  handlerOps = handlers,
  handlerSourceBase = 0x8FF00000,
  handlerFragment = fragment,
}, 25, moveRows, contexts)

local model, err = Pack.parse(bytes)
ok(model ~= nil, err or "pack parse")
ok(model.species == 25, "species")
ok(model.boneCount == 2 and #model.bones == 2, "bones")
ok(model.primCount == 1 and #model.prims == 1, "primitives")
ok(model.prims[1].effect == "fire", "generated fire semantics survive DSM packing")
ok(model.texCount == 2 and #model.textures == 2, "textures")
ok(model.animCount == 1 and #model.anims == 1, "animations")
ok(model.handlers and #model.handlers.records == 2, "handler extension")
ok(Pack.contextIndex(model, "idle") == 1, "idle context")
ok(Pack.moveIndex(model, 1) == 1, "move mapping")
ok(Pack.textureIndex(model, model.prims[1], 1, 0) == 2, "texture animation mapping")
ok(model.prims[1].cull == true and model.prims[1].additive == true, "render state")

local carrierPrim = { callbackOffset = 0x1118, cull = true }
local carrierState = Renderer.primitiveRenderState({ species = 109, handlers = { records = {
  { commandOffset = 0x1118, family = "dynamic-object-renderer" },
} } }, carrierPrim, { disableCulling = true })
ok(carrierState.dynamicObjectCarrier and not carrierState.drawStatic,
  "dynamic-object callback geometry is excluded from the static model pass")
ok(carrierState.cullEnabled,
  "dynamic-object carrier retains source culling through scene override")
ok(not carrierState.lightingEnabled,
  "dynamic-object carrier preserves unlit vertex-color interpretation")
ok(not carrierState.castsShadow,
  "dynamic-object carrier cannot enlarge the model shadow silhouette")
local colorState = Renderer.primitiveRenderState({}, { lighting = false, cull = true })
ok(not colorState.lightingEnabled and colorState.cullEnabled,
  "source vertex-colour geometry disables lighting without disabling culling")
-- Combiner colour input A selector 7 is the RDP's NOISE (Sandstorm's
-- grain layer, shape 147 prim 2); it must not read as zero.
local rendererSource = io.open("mods/STADIUM2_IMPORTER/lib/renderer.lua"):read("*a")
ok(rendererSource:find("vec3 rgb=(n64ColorA(selectors.x", 1, true)
    and rendererSource:find("vec3 rgb=(mobileColorA(selectors.x", 1, true)
    and select(2, rendererSource:gsub("return n64Noise;", "")) == 2,
  "both shaders feed NOISE to colour input A")
-- Battle-FX shapes keep the smooth sampling they had as arena models.
ok(Renderer.smoothSampled({ staticPose = true, species = 0, battleFx = true }),
  "static battle-FX shapes are smooth-sampled")
ok(Renderer.smoothSampled({ staticPose = true, species = 0 }),
  "arena fields are smooth-sampled")
ok(not Renderer.smoothSampled({ species = 25 }),
  "Pokemon models keep the 3-point filter")
-- FX combiners without SHADE ignore lighting (sandstorm shape 147).
local lit = { lightingEnabled = true }
local sandstorm = { phase5 = true, combiner = { cycles = 2,
  color0 = { 2, 1, 14, 1 }, color1 = { 3, 5, 0, 5 } } }
ok(not Renderer.surfaceLit(lit, { battleFx = true }, sandstorm),
  "a battle-FX combiner without SHADE is drawn unlit")
local shaded = { phase5 = true, combiner = { cycles = 1,
  color0 = { 1, 0, 4, 0 }, color1 = { 1, 0, 4, 0 } } }
ok(Renderer.surfaceLit(lit, { battleFx = true }, shaded),
  "a battle-FX combiner that reads SHADE stays lit")
ok(Renderer.surfaceLit(lit, { species = 25 }, sandstorm),
  "a Pokemon model without a display-list state keeps its lighting")
ok(not Renderer.surfaceLit({ lightingEnabled = false }, { battleFx = true }, shaded),
  "an unlit primitive stays unlit")
local arenaPrimitive = { lighting = true, cull = true }
local arenaCullState = Renderer.primitiveRenderState(
  { species = 0, staticPose = true }, arenaPrimitive)
ok(arenaCullState.cullEnabled and arenaPrimitive.cull == true,
  "arena panels retain ROM one-sided culling metadata")
ok(Renderer.meshCullMode({}, true, true, true) == "back"
    and Renderer.meshCullMode({ species = 0, staticPose = true },
      true, true, true) == "none",
  "arena graph keeps mixed-facing field assemblies visible")
ok(Renderer.meshCullMode({ species = 0, staticPose = true },
    true, true, false) == "none",
  "arena cull override still supports explicit two-sided rendering")
local alphaModel = { species = 0, staticPose = true, textures = {
  { rgba = "\255\255\255\255" },
  { rgba = "\255\255\255\0\255\255\255\255" },
  { rgba = "\255\255\255\128" },
} }
local alphaParts = {
  { prim = { tex = 1 }, sourcePartIndex = 1 },
  { prim = { tex = 2, decal = true }, sourcePartIndex = 2 },
  { prim = { tex = 3, decal = true, idx = {1,2,3} }, sourcePartIndex = 3,
    rows = {{0,0,-2},{1,0,-2},{0,1,-2}} },
}
local alphaCounts = Renderer.prepareArenaRenderQueues(alphaModel, alphaParts)
local alphaOrder = Renderer.arenaRenderOrder(alphaModel, alphaParts, "opaque")
ok(alphaCounts.opaque == 1 and alphaCounts.cutout == 1
    and alphaCounts.blend == 1
    and alphaParts[1].prim.arenaQueue == "opaque"
    and alphaParts[2].prim.arenaAlphaMode == "cutout"
    and alphaParts[3].prim.arenaQueue == "translucent"
    and alphaOrder[1] == alphaParts[1] and alphaOrder[2] == alphaParts[2]
    and alphaOrder[3] == alphaParts[3],
  "arena pipeline writes opaque/cutout depth before translucent ROM surfaces")
local materialAlphaParts = {
  { prim = { tex = 1 }, sourcePartIndex = 1 },
  { prim = { tex = 1 }, sourcePartIndex = 2 },
}
local materialAlphaCounts = Renderer.prepareArenaRenderQueues(alphaModel,
  materialAlphaParts, function(prim)
    return { primitiveColor = prim == materialAlphaParts[1].prim
      and {1,1,1,0.5} or {0.25,0.25,0.25,0.4} }
  end)
ok(materialAlphaCounts.blend == 1 and materialAlphaCounts.shadow == 1
    and materialAlphaParts[1].prim.arenaQueue == "translucent"
    and materialAlphaParts[2].prim.arenaCompositeMode == "shadow",
  "ROM material alpha separates translucent markings and dark shadow overlays")
local phase5Opaque = { prim = { tex = 1 }, sourcePartIndex = 1 }
local phase5Counts = Renderer.prepareArenaRenderQueues(alphaModel,
  { phase5Opaque }, function()
    return { phase5 = true, primitiveColor = {1,1,1,0.25}, combiner = {
      cycles = 2, coverage = false, alphaUsesPrimitive = false,
    } }
  end)
ok(phase5Counts.opaque == 1,
  "two-cycle phase-5 framebuffer coverage is not misclassified by unused primitive alpha")
local zeroAlphaVertexBlend = {
  prim = { tex = 1, alphaMode = "blend" }, sourcePartIndex = 1,
}
local zeroAlphaVertexCounts = Renderer.prepareArenaRenderQueues(alphaModel,
  { zeroAlphaVertexBlend }, function()
    return { phase5 = true, primitiveColor = {1,1,1,1}, combiner = {
      cycles = 2, alphaOutputZero = true,
    } }
  end)
ok(zeroAlphaVertexCounts.opaque == 1
    and zeroAlphaVertexBlend.prim.arenaAlphaMode == "opaque",
  "unused zero combiner alpha cannot discard an opaque RDP submission")
local phase5Blend = { prim = { tex = 1 }, sourcePartIndex = 1 }
local phase5BlendCounts = Renderer.prepareArenaRenderQueues(alphaModel,
  { phase5Blend }, function()
    return { phase5 = true, primitiveColor = {1,1,1,0.5}, combiner = {
      cycles = 2, alphaUsesPrimitive = true,
    } }
  end)
ok(phase5BlendCounts.blend == 1
    and phase5Blend.prim.arenaQueue == "translucent",
  "phase-5 water surfaces retain ROM primitive-alpha blending")
local liveTexturePart = { prim = { tex = 1 }, sourcePartIndex = 1 }
local liveTextureCounts = Renderer.prepareArenaRenderQueues(alphaModel,
  { liveTexturePart }, nil, function() return 3 end)
ok(liveTextureCounts.blend == 1,
  "arena queues follow the live phase-5 texture-controller selection")
local authoredBlendPart = {
  prim = { tex = 1, alphaMode = "blend" }, sourcePartIndex = 1,
}
local authoredBlendCounts = Renderer.prepareArenaRenderQueues(alphaModel,
  { authoredBlendPart }, nil, function() return 1 end)
ok(authoredBlendCounts.blend == 1
    and authoredBlendPart.prim.arenaAlphaMode == "blend",
  "opaque callback images do not erase authored translucent vertex layers")
local phase5Combiner = { phase5 = true, combiner = { cycles = 2 } }
local staticIntensity, staticSecondary = Renderer.phase5IntensityAlpha(
  phase5Combiner, nil, { textures = {{ format = 4 }} }, 1)
local callbackIntensity, callbackSecondary = Renderer.phase5IntensityAlpha(
  phase5Combiner, { formats = { 0, 4 } },
  { textures = {{ format = 4 }} }, 1)
local pokemonIntensity = Renderer.phase5IntensityAlpha(
  { intensity = true }, nil, { textures = {{ format = 4 }} }, 1)
ok(staticIntensity and not staticSecondary
    and not callbackIntensity and callbackSecondary
    and not pokemonIntensity,
  "phase-5 I4 alpha covers static and callback arena inputs without changing Pokemon effects")
local shadowCompare, shadowWrite = RenderContract.depthState({
  arenaAlphaMode = "blend", arenaCompositeMode = "shadow", coplanarLayer = 1,
}, true)
ok(shadowCompare == "lequal" and shadowWrite == false,
  "coplanar arena shadows compose above the floor without replacing its depth")
local nearBlend = { sourcePartIndex = 4,
  prim = { arenaQueue = "translucent", idx = {1,2,3} },
  rows = {{0,0,-1},{1,0,-1},{0,1,-1}} }
local farBlend = alphaParts[3]
local sortedAlpha = Renderer.arenaRenderOrder(alphaModel,
  { nearBlend, farBlend }, "opaque",
  {1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1},
  {1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1})
ok(sortedAlpha[1] == farBlend and sortedAlpha[2] == nearBlend,
  "genuinely translucent arena surfaces sort back-to-front for the camera")
local arenaOverlay = {
  prim = { idx = {1,2,3}, nidx = 3, sourceTextureMissing = false },
  rows = {{0,0,0},{1,0,0},{0,0,1}},
}
local arenaFloor = {
  prim = { idx = {1,2,3,1,3,4}, nidx = 6, sourceTextureMissing = false },
  rows = {{0,0,0},{1,0,0},{0,0,1},{-1,0,0}},
}
local arenaParts = { arenaOverlay, arenaFloor }
ok(Renderer.resolveArenaCoplanarLayers(
    { species = 0, staticPose = true }, arenaParts) == 1
    and arenaParts[1] == arenaFloor and arenaParts[2] == arenaOverlay
    and arenaOverlay.prim.coplanarLayer == 1,
  "arena coplanar markings are submitted after their shared floor triangles")
local callbackMarking = {
  prim = { idx = {1,2,3}, nidx = 3, sourceTextureMissing = true,
    callbackTextureRequired = true, arenaSubmissionLayer = 6 },
  -- Deliberately does not overlap the floor. ROM order must not depend on a
  -- geometric containment test.
  rows = {{8,0,8},{9,0,8},{8,0,9}},
}
local callbackFloor = {
  prim = { idx = {1,2,3,1,3,4}, nidx = 6,
    sourceTextureMissing = false, arenaSubmissionLayer = 5 },
  rows = {{-2,0,-2},{2,0,-2},{2,0,2},{-2,0,2}},
}
local callbackLayerParts = { callbackMarking, callbackFloor }
ok(Renderer.resolveArenaCoplanarLayers(
    { species = 0, staticPose = true }, callbackLayerParts) == 1
    and callbackLayerParts[1] == callbackFloor
    and callbackLayerParts[2] == callbackMarking
    and callbackMarking.prim.coplanarLayer == 1,
  "ROM layer order preserves callback-owned coplanar arena artwork")
local romLayerLarge = {
  prim = { idx = {1,2,3,1,3,4}, nidx = 6, sourceTextureMissing = false,
    arenaSubmissionLayer = 6 },
  rows = {{0,0,0},{1,0,0},{1,0,1},{0,0,1}},
}
local romLayerSmall = {
  prim = { idx = {1,2,3}, nidx = 3, sourceTextureMissing = false,
    arenaSubmissionLayer = 5 },
  rows = {{0,0,0},{1,0,0},{1,0,1}},
}
local romLayerParts = { romLayerLarge, romLayerSmall }
ok(Renderer.resolveArenaCoplanarLayers(
    { species = 0, staticPose = true }, romLayerParts) == 1
    and romLayerParts[1] == romLayerSmall and romLayerParts[2] == romLayerLarge,
  "ROM graph submission layer overrides the legacy triangle-count heuristic")
local triangulatedMarking = {
  prim = { idx = {1,2,3}, nidx = 3, sourceTextureMissing = false },
  rows = {{-.8,0,-.4},{.8,0,-.4},{0,0,.8}},
}
local differentlyTriangulatedFloor = {
  prim = { idx = {1,2,3,1,3,4}, nidx = 6, sourceTextureMissing = false },
  rows = {{-2,0,-2},{2,0,-2},{2,0,2},{-2,0,2}},
}
local triangulatedParts = { triangulatedMarking, differentlyTriangulatedFloor }
ok(Renderer.resolveArenaCoplanarLayers(
    { species = 0, staticPose = true }, triangulatedParts) == 1
    and triangulatedParts[1] == differentlyTriangulatedFloor
    and triangulatedParts[2] == triangulatedMarking,
  "arena markings remain top layers across different floor triangulation")
local nestedTop = {
  prim = { idx = {1,2,3}, nidx = 3, sourceTextureMissing = false },
  rows = {{-.5,0,-.25},{.5,0,-.25},{0,0,.5}},
}
local nestedMiddle = {
  prim = { idx = {1,2,3,1,3,4}, nidx = 6, sourceTextureMissing = false },
  rows = {{-1,0,-1},{1,0,-1},{1,0,1},{-1,0,1}},
}
local nestedFloor = {
  prim = { idx = {1,2,3,1,3,4}, nidx = 6, sourceTextureMissing = false },
  rows = {{-2,0,-2},{2,0,-2},{2,0,2},{-2,0,2}},
}
local nestedParts = { nestedTop, nestedMiddle, nestedFloor }
ok(Renderer.resolveArenaCoplanarLayers(
    { species = 0, staticPose = true }, nestedParts) == 2
    and nestedParts[1] == nestedFloor and nestedParts[2] == nestedMiddle
    and nestedParts[3] == nestedTop
    and nestedMiddle.prim.coplanarLayer == 1
    and nestedTop.prim.coplanarLayer == 2,
  "nested arena artwork receives a distinct depth rank for every top layer")
local decalCullState = Renderer.primitiveRenderState({},
  { decal = true, cull = true }, { disableCulling = true })
ok(not decalCullState.cullEnabled,
  "rigid face/detail surfaces follow the scene's unified winding override")
local pinecoEyeCullState = Renderer.primitiveRenderState({ species = 204 },
  { decal = true, cull = true, texAnim = 0, nverts = 3, nidx = 3 },
  { disableCulling = true })
ok(pinecoEyeCullState.cullEnabled,
  "Pineco's isolated eye cards remain one-sided through the scene override")
local pikachuHeadFillState = Renderer.primitiveRenderState({ species = 25 },
  { decal = true, cull = true, texAnim = 4 }, { disableCulling = true })
ok(not pikachuHeadFillState.cullEnabled,
  "Pikachu's ROM head-fill triangles survive the scene body-culling override")
ok(Renderer.FORMAT[4] and Renderer.FORMAT[4][1] == "VertexColor",
  "DSM4 mesh format carries source vertex RGBA")
local _, normalDecls = Renderer.SHADER_SOURCE:gsub("varying STADIUM_FLOAT vec3 vNormal;", "")
local _, sunDecls = Renderer.SHADER_SOURCE:gsub("varying STADIUM_FLOAT vec3 vSun;", "")
local _, eyeNormalDecls = Renderer.SHADER_SOURCE:gsub("varying STADIUM_FLOAT vec3 vEyeNormal;", "")
ok(normalDecls == 1 and sunDecls == 1 and eyeNormalDecls == 1,
  "shared shader varyings retain the desktop path with adaptive mobile precision")
ok(Renderer.SHADER_SOURCE:find("shadowDepth(p.xy+sunTexel", 1, true) ~= nil,
  "desktop shadow path retains the four-fetch PCF footprint")
ok(Renderer.SHADER_SOURCE:find("#ifdef GL_ES", 1, true) ~= nil
    and Renderer.SHADER_SOURCE:find("smoothstep%(mapDepth", 1, false) ~= nil,
  "GLES uses a single soft sun shadow compare instead of binary PCF speckle")
ok(Renderer.SHADER_SOURCE:find("0.30+(stadiumShade-0.30)*shadowVisibility", 1, true) ~= nil,
  "Pokemon self-shadow preserves the authored ambient lighting floor")
ok(Renderer.SHADER_SOURCE:find(
    "effectIntensityMode > 1.5 ? texel.a : intensity", 1, true) ~= nil,
  "IA8 flame coverage uses TEXEL0 alpha instead of I4 smoke intensity")
ok(Renderer.SHADER_SOURCE:find(
    "vec4(mix(texel.rgb, other.rgb, secondaryMix), texel.a)", 1, true) ~= nil
  and Renderer.MOBILE_SHADER_SOURCE:find(
    "vec4(mix(texel.rgb,other.rgb,secondaryMix),texel.a)", 1, true) ~= nil,
  "dual-texture slime keeps opaque primary alpha on desktop and mobile")
ok(Renderer.SHADER_SOURCE:find(
    "texture_coords*secondaryCoordinateScale", 1, true) ~= nil
  and Renderer.MOBILE_SHADER_SOURCE:find(
    "VaryingTexCoord.st*secondaryCoordinateScale", 1, true) ~= nil,
  "secondary callback tile preserves raw coordinates independently of authored detail UVs")
ok(Renderer.SHADER_SOURCE:find("uniform float decalDepthBias;",1,true)~=nil
  and Renderer.SHADER_SOURCE:find("clip.z-=decalDepthBias*clip.w",1,true)~=nil,
  "coplanar detail primitives can be stabilized on reduced-depth mobile buffers")
do
  local oldLove=love
  love={graphics={getRendererInfo=function() return "Metal","3.1","Apple","GPU" end}}
  ok(Renderer.shouldReceiveModelSunShadows({})==false,
    "mobile Metal uses the clean cast-shadow-only fallback")
  love=oldLove
end
ok(Renderer.SHADER_SOURCE:find("vGeneratedUV", 1, true) ~= nil,
  "shared shader implements normal-driven Stadium reflection coordinates")
ok(Renderer.SHADER_SOURCE:find("void effect()", 1, true) ~= nil,
  "lit shader reads VaryingTexCoord directly instead of mediump effect() parameters")
ok(Renderer.SHADER_SOURCE:find("VaryingTexCoord.st", 1, true) ~= nil,
  "texture coordinates stay at LOVE's highp varying precision on GLES")
ok(Renderer.SHADER_SOURCE:find("vec4 color=VaryingColor;", 1, true) ~= nil,
  "phase-5 combiners consume the arena's authored vertex SHADE input")
ok(Renderer.SHADER_SOURCE:find("if (mangaAmount > 0.001)", 1, true) ~= nil,
  "watercolor treatment is skipped entirely in Stadium lighting mode")
ok(Renderer.SHADER_SOURCE:find(
    "if (smoothTextureFiltering > 0.5) return Texel(image, uv);", 1, true) ~= nil,
  "arena shader can use bilinear mipmapped sampling without changing Pokemon three-point filtering")

local emitterModel = { species = 109, rootScale = 0.1,
  handlers = { records = {{ commandOffset = 0x1118, family = "dynamic-object-renderer" }} },
  prims = {{ callbackOffset = 0x1118, skin = {} }},
}
local emitterMatrices = {}
for i = 0, 39 do
  emitterMatrices[i + 1] = {{1,0,0,i},{0,1,0,i * 2},{0,0,1,i * 3}}
end
for i = 0, 17 do
  local bone = i * 2 + 5
  for _ = 1, 4 do emitterModel.prims[1].skin[#emitterModel.prims[1].skin + 1] = bone end
end
local emitterRuntime = Renderer.dynamicObjectEmitters(emitterModel, emitterMatrices)
ok(#emitterRuntime == 18 and emitterRuntime[1].bone == 5 and emitterRuntime[18].bone == 39,
  "dynamic carrier expands to 18 ordered emitter bones")
ok(math.abs(emitterRuntime[1].origin[1] - 0.5) < 0.000001
    and math.abs(emitterRuntime[18].origin[1] - 3.9) < 0.000001,
  "emitter origins use each posed callback bone and model root scale")

local rig, rigErr = Renderer.new(model)
ok(rig ~= nil, rigErr or "renderer")
ok(rig.animIndex == 1, "renderer idle")
ok(rig.parts[1].rows[1][1] == 10, "bind animation frame zero skinning")
rig:step(1/60)
ok(rig.frame==0 and math.abs(rig.parts[1].rows[1][1]-15)<0.000001,
  "geometry interpolates while callback and texture state stay on the source frame")
rig:setAnimation("idle",true)
rig:step(1 / 30)
ok(rig.frame == 1, "30Hz source frame")
ok(rig.parts[1].rows[1][1] == 20, "animated skinning")
rig:step(1 / 30)
ok(rig.frame == 0, "loop start")
ok(rig:seekFrame(1) and rig.frame == 1 and rig.parts[1].rows[1][1] == 20,
  "renderer seeks an exact source frame and refreshes its pose")
rig:seekFrame(0)
ok(rig:currentTexture(model.prims[1]) == 2, "renderer texture selection")
rig.handlerState.textureBySite = { [0x44] = 3 }
model.prims[1].callbackOffset = 0x44
model.prims[1].callbackTextureRequired = false
ok(rig:currentTexture(model.prims[1]) == 2, "authored texture survives site callback")
local savedHandlers = model.handlers
model.handlers = { records = {{ commandOffset = 0x44, descriptor = 0x81000048 }} }
model.textures[2].rgba = "\255\0\0\255\0\255\0\255\0\0\255\255\255\255\255\255"
ok(rig:currentTexture(model.prims[1]) == 2,
  "dual-texture material builder preserves authored nonuniform detail inputs")
ok(rig:callbackUsesMaterialFx(model.prims[1]),
  "authored detail retains the ROM two-texture color combiner")
model.handlers.records[1].descriptor = 0x81000148
ok(not rig:callbackUsesMaterialFx(model.prims[1]),
  "phase-5 callbacks preserve a local authored texture at their graph node")
model.prims[1].callbackTextureRequired = true
ok(rig:callbackUsesMaterialFx(model.prims[1]),
  "callback-owned phase-5 surfaces retain their ROM material combiner")
model.prims[1].callbackTextureRequired = false
model.handlers.records[1].descriptor = 0x81000048
local detailPrimaryScroll, detailSecondaryScroll = Renderer.callbackTextureScroll({
  scroll = {{0.25, 0.5}, {0.75, 1}},
}, false)
ok(detailPrimaryScroll == nil and detailSecondaryScroll[1] == 0.75,
  "authored detail stays fixed while the secondary slime tile scrolls")
local detailWrapS, detailWrapT = Renderer.callbackPrimaryWrap({},
  { wrapS = "clamp", wrapT = "clamp" }, { wrap = "repeat" }, false)
ok(detailWrapS == "clamp" and detailWrapT == "clamp",
  "authored detail retains its ROM clamp modes under the slime callback")
model.textures[3] = { w = model.textures[2].w, h = model.textures[2].h,
  rgba = model.textures[2].rgba }
ok(rig:currentTexture(model.prims[1]) == 3
    and rig:callbackUsesMaterialFx(model.prims[1]),
  "an authored copy of the callback primary tile remains a scrolling body input")
local bodyPrimaryScroll = Renderer.callbackTextureScroll({
  scroll = {{0.25, 0.5}, {0.75, 1}},
}, true)
ok(bodyPrimaryScroll[1] == 0.25,
  "callback-owned body primary retains its ROM tile scroll")
local bodyWrapS, bodyWrapT = Renderer.callbackPrimaryWrap({},
  { wrapS = "clamp", wrapT = "clamp" }, { wrap = "repeat" }, true)
ok(bodyWrapS == "repeat" and bodyWrapT == "repeat",
  "callback-owned body primary uses the generated tile repeat mode")
local waterWrapS, waterWrapT = Renderer.callbackPrimaryWrap({}, nil, {
  samplers = {{ cms = 0, cmt = 0 }, { cms = 1, cmt = 1 }},
}, true)
local waterSecondaryS, waterSecondaryT = Renderer.callbackSecondaryWrap({
  samplers = {{ cms = 0, cmt = 0 }, { cms = 1, cmt = 1 }},
})
ok(waterWrapS == "repeat" and waterWrapT == "repeat"
    and waterSecondaryS == "mirroredrepeat"
    and waterSecondaryT == "mirroredrepeat",
  "phase-5 water layers retain their independent ROM tile addressing")
local localEyeMaterial, generatedPhase5Material = {}, {}
local phase5Rig = setmetatable({
  model = { handlers = { records = {{
    descriptor = 0x81000148, commandOffset = 0x1234,
  }} } },
  handlerState = { materialBySite = { [0x1234] = generatedPhase5Material } },
}, Renderer)
local localEye = { callbackOffset = 0x1234, material = localEyeMaterial,
  tex = 1, texAnim = 0, callbackTextureRequired = false }
local callbackSurface = { callbackOffset = 0x1234,
  material = localEyeMaterial, callbackTextureRequired = true }
ok(not phase5Rig:callbackUsesMaterialFx(localEye)
    and phase5Rig:currentMaterial(localEye) == localEyeMaterial,
  "phase-5 mode 2 preserves a locally textured eye atlas at the same callback site")
ok(phase5Rig:callbackUsesMaterialFx(callbackSurface)
    and phase5Rig:currentMaterial(callbackSurface) == generatedPhase5Material,
  "phase-5 mode 2 still supplies its generated callback surface and animated FX")
local arenaPhase5Rig = setmetatable({
  model = { species = 0, staticPose = true, handlers = phase5Rig.model.handlers },
  handlerState = phase5Rig.handlerState,
}, Renderer)
ok(arenaPhase5Rig:callbackUsesMaterialFx(localEye)
    and arenaPhase5Rig:currentMaterial(localEye) == generatedPhase5Material,
  "arena phase-5 combines its locally textured floor carrier with the callback mask")
phase5Rig.model.handlers.records[1].descriptor = 0x81000140
ok(not phase5Rig:callbackUsesMaterialFx(localEye)
    and phase5Rig:currentMaterial(localEye) == localEyeMaterial,
  "phase-5 mode 1 uses the same ROM replace-untextured ownership rule")
ok(not require("mods.STADIUM2_IMPORTER.lib.render_callbacks.dual_texture_material")
    .ownsAuthoredTexture({ callbackDescriptor = 0x81000048,
          pos = { 0, 0, 0, 0, 40, 0 } },
      { w = 32, h = 64, rgba = "\0\0\0\255"
          .. string.rep("\255\255\255\255", 32 * 64 - 1) },
      { w = 32, h = 32, rgba = string.rep("\0\0\0\255", 32 * 32) },
      0x81000048),
  "authored 32x64 tongue atlas remains a local primary detail")
ok(require("mods.STADIUM2_IMPORTER.lib.render_callbacks.dual_texture_material")
    .ownsAuthoredTexture({ callbackDescriptor = 0x81000048,
          pos = { 0, 30, 0, 0, 200, 0 } },
      { w = 32, h = 64, rgba = "\0\0\0\255"
          .. string.rep("\255\255\255\255", 32 * 64 - 1) },
      { w = 32, h = 32, rgba = string.rep("\0\0\0\255", 32 * 32) },
      0x81000048),
  "Muk rear-head geometry replaces the reused tongue atlas with body material")
local DualTexture = require(
  "mods.STADIUM2_IMPORTER.lib.render_callbacks.dual_texture_material")
local sharedEyeAtlas = { w = 64, h = 32,
  rgba = "\0\0\0\255" .. string.rep("\255\255\255\255", 64 * 32 - 1) }
local slimeTile = { w = 32, h = 32,
  rgba = string.rep("\0\0\0\255", 32 * 32) }
ok(DualTexture.ownsAuthoredTexture({ callbackDescriptor = 0x81000048,
      nverts = 97 }, sharedEyeAtlas, slimeTile, 0x81000048),
  "large Grimer arm geometry does not retain the eye atlas inherited before command 0x08")
ok(not DualTexture.ownsAuthoredTexture({ callbackDescriptor = 0x81000048,
      nverts = 53 }, sharedEyeAtlas, slimeTile, 0x81000048),
  "Muk's complete authored eye and pupil mesh retains its local atlas")
ok(DualTexture.ownsAuthoredTexture({ callbackDescriptor = 0x81000048,
      nverts = 28 }, sharedEyeAtlas, slimeTile, 0x81000048),
  "Muk's small inherited head shell uses the generated body material")
model.textures[2].rgba = string.rep("\255\255\255\255", 4)
model.textures[3].rgba = "\0\0\0\255"
ok(rig:currentTexture(model.prims[1]) == 3,
  "dual-texture material builder replaces a uniform body fill")
model.prims[1].decal = false
ok(rig:callbackUsesMaterialFx(model.prims[1]),
  "dual-texture material FX reaches a non-decal body surface")
local uvS,uvT=Renderer.callbackTextureCoordinateScale({textures={
  {w=4,h=8},{w=32,h=32},
}}, {tex=1,sampler={shifts=0,shiftt=1},textureScale={1,1}}, 2)
ok(math.abs(uvS-0.125)<0.000001 and math.abs(uvT-0.5)<0.000001,
  "callback texture replacement preserves raw N64 S/T across texture size and shift changes")
local arenaPrimaryS,arenaPrimaryT=Renderer.callbackTextureCoordinateScale({
  textures={[15]={w=32,h=32},[16]={w=32,h=32}},
},{tex=0x10000,sampler={shifts=2,shiftt=2}},15,
  {shifts=2,shiftt=2})
local arenaDetailS,arenaDetailT=Renderer.callbackTextureCoordinateScale({
  textures={[15]={w=32,h=32},[16]={w=32,h=32}},
},{tex=0x10000,sampler={shifts=2,shiftt=2}},16,
  {shifts=15,shiftt=15})
ok(arenaPrimaryS==1 and arenaPrimaryT==1
    and arenaDetailS==8 and arenaDetailT==8,
  "phase-5 TEXEL0 mesh coordinates preserve independent TEXEL1 tile shifts")
local centrePrimaryS,centrePrimaryT=Renderer.callbackTextureCoordinateScale({
  textures={[20]={w=32,h=32},[21]={w=64,h=64}},
},{tex=0x10000,sampler={shifts=0,shiftt=0}},20,
  {shifts=0,shiftt=0})
local centreMaskS,centreMaskT=Renderer.callbackTextureCoordinateScale({
  textures={[20]={w=32,h=32},[21]={w=64,h=64}},
},{tex=0x10000,sampler={shifts=0,shiftt=0}},21,
  {shifts=1,shiftt=1})
ok(centrePrimaryS==1 and centrePrimaryT==1
    and centreMaskS==0.25 and centreMaskT==0.25,
  "arena centre gravel and Poké Ball mask retain separate ROM coordinate rates")
model.prims[1].decal = true
ok(not rig:callbackUsesMaterialFx(model.prims[1]),
  "dual-texture material FX does not cover an alpha face decal")
ok(rig:currentTexture(model.prims[1]) == 2,
  "dual-texture material builder preserves an alpha face decal texture")
model.prims[1].decal = nil
model.handlers.records[1].descriptor = 0x81000050
ok(rig:currentTexture(model.prims[1]) == 3,
  "animated texture builder replaces its controlled authored input")
model.handlers = savedHandlers
model.prims[1].callbackTextureRequired = true
ok(rig:currentTexture(model.prims[1]) == 3, "callback texture targets eligible primitive")
model.prims[1].callbackOffset = nil
model.prims[1].callbackTextureRequired = nil
rig.handlerState.textureBySite = nil
rig:setHandlerRuntime({ selector = 4, rangeValue = 100 })
rig:updatePose(true)
ok(rig.handlerState.bit0ByBone[1] == true, "visibility gate enabled")
local bounds = rig:poseBounds()
ok(math.abs(bounds.cx - 15) < 0.000001 and math.abs(bounds.cy - 5) < 0.000001, "posed bounds center uses drawn geometry")
ok(bounds.maxX < 30 and bounds.maxY < 30 and bounds.maxZ < 30, "unused decoded vertex cannot drag camera bounds")
ok(bounds.radius > 7 and bounds.radius < 7.2, "posed bounds radius")
local cameraSquare = rig:fitCamera(320, 320, { fitPadding = 1.12 })
local cameraNarrow = rig:fitCamera(160, 320, { fitPadding = 1.12 })
ok(cameraSquare.bounds.cx == bounds.cx and cameraSquare.bounds.cy == bounds.cy, "camera targets posed bounds")
ok(cameraNarrow.distance > cameraSquare.distance, "camera backs up for narrow aspect")
local cameraZoom = rig:fitCamera(320, 320, { fitPadding = 1.12, zoom = 2 })
ok(cameraZoom.distance < cameraSquare.distance, "viewer zoom moves camera closer")
rig:step(1 / 30)
local movedBounds = rig:poseBounds()
local stableCamera = rig:fitCamera(320, 320, { fitPadding = 1.12 })
ok(movedBounds.cx ~= stableCamera.bounds.cx, "animated pose can move independently of framing bounds")
ok(math.abs(stableCamera.bounds.cx - cameraSquare.bounds.cx) < 0.000001,
  "camera framing stays locked to bind pose instead of chasing animation")
rig:setAnimation("idle", true)
rig.displayTime = 1.25
rig.time = .25
ok(rig:handlerValues().materialFrame == 75,
  "shared callback display counter advances independently of animation time")
rig:setAnimation("idle", true)
ok(rig:handlerValues().materialFrame == 75,
  "shared callback display counter does not reset when animations change")
ok(cameraSquare.near > 0 and cameraSquare.far > cameraSquare.near, "camera clip range valid")
local orient = Renderer.modelMatrix(0, 0, 1, 0, 5, 0, true)
ok(math.abs(orient[6] + 1) < 0.000001 and math.abs(orient[8] - 5) < 0.000001, "Stadium model matrix flips vertical axis around model center")
local shiftedProjection = Renderer.perspective(math.pi / 4, 1, 0.1, 100, 0.25, -0.5)
ok(math.abs(shiftedProjection[3] + 0.25) < 0.000001 and math.abs(shiftedProjection[7] - 0.5) < 0.000001, "projection supports screen-space model panning")
local billboardUniforms = {}
local billboardShader = { send = function(_, name, value)
  billboardUniforms[name] = value
end }
local billboardRows = {
  {-50,200,0}, {-50,150,0}, {50,150,0}, {50,200,0},
  {-50,100,0}, {50,100,0}, {-50,50,0}, {50,50,0},
  {-50,0,0}, {50,0,0},
}
Renderer.sendFlameBillboard(billboardShader,
  { prim={effect="fire"}, rows=billboardRows },
  Renderer.identity(), Renderer.identity())
ok(billboardUniforms.billboardEnabled == 1
    and billboardUniforms.billboardSize[1] == 100
    and billboardUniforms.billboardSize[2] == 200,
  "shared flame object retains its ROM size while facing the camera")
ok(billboardUniforms.billboardCenter[1] == 0
    and billboardUniforms.billboardCenter[2] == 0
    and billboardUniforms.billboardRight[1] == 1
    and billboardUniforms.billboardUp[2] == 1,
  "shared flame object derives camera-facing axes from the view transform")

local gastlyModel=Renderer.modelMatrix(math.pi/2,0,2,0,0,0,false)
local gastlyAxes=Renderer.cameraFacingAxes(Renderer.identity(),gastlyModel)
local gastlyGeometry=Renderer.koffingGasGeometryState(
  {absolute=true,x=0,y=0,z=0,sx=20,sy=20,sz=20}, {0,0,0}, nil,32,32,
  gastlyAxes)
local left,right=gastlyGeometry.vertices[1],gastlyGeometry.vertices[2]
ok(math.abs(left[3]-right[3])>199.999 and math.abs(left[1]-right[1])<0.000001,
  "Gastly gas rotates into model-local camera axes instead of turning edge-on")
local normalRuntime=Renderer.dynamicObjectRuntime({species=92,variant="normal"},{})
local shinyRuntime=Renderer.dynamicObjectRuntime({species=92,variant="shiny"},{})
ok(normalRuntime.dynamicObjectGastlyAlternate==false
    and shinyRuntime.dynamicObjectGastlyAlternate==true
    and shinyRuntime.modelAlphaByte==255,
  "Gastly gas inherits the normal/shiny model state and owning model alpha")

rig:setHandlerRuntime({ selector = 4, rangeValue = 3000 })
rig:updatePose(true)
ok(rig.handlerState.bit0ByBone[1] == false, "visibility gate disabled")
ok(rig.parts[1].rows[1][1] == 0 and rig.parts[1].rows[1][2] == 0, "hidden bone suppressed")
ok(rig.handlerState.modelContext == rig, "model context registered")
ok(Renderer.sourceFrame(model.anims[1], 2 / 30, true) == 0, "animation loop sampling")

-- The renderer smooths the source's 30 Hz pose stream to the 60 Hz scene,
-- but Euler triples can be re-expressed discontinuously between two adjacent
-- source frames.  Interpolating such a pair creates a pose neither source
-- frame contains: long articulated limbs visibly turn inside-out for one
-- display frame.  Hold that bone's source rotation whenever any component
-- moves more than a quarter turn in one 30 Hz step.
local snapModel = {
  rootScale = 1, height = 100,
  bones = { { t = { 0, 0, 0 }, r = { 0, 0, 0 }, s = { 1, 1, 1 } } },
  anims = { { frames = 2, loopStart = 0, tracks = {
    [1] = {
      t = { 0, 0, 0 },
      r = { { 0, 0 }, { 20976, -19936 }, { 32736, -5904 } },
      s = { 1, 1, 1 },
    },
  } } },
}
local snapSample = Renderer.samplePoseInterpolated(snapModel, 1, 0, 0.5, true)
local _, snapR = snapSample(1)
ok(snapR[1] == 0 and snapR[2] == 20976 and snapR[3] == 32736,
  "equivalent-Euler snap holds the whole source rotation instead of flipping a limb")

local smoothModel = {
  rootScale = 1, height = 100,
  bones = { { t = { 0, 0, 0 }, r = { 0, 0, 0 }, s = { 1, 1, 1 } } },
  anims = { { frames = 2, loopStart = 0, tracks = {
    [1] = {
      t = { { 0, 40 }, 0, 0 },
      r = { { 1000, 2000 }, { 32700, -32700 }, 0 },
      s = { { 1, 1.2 }, 1, 1 },
    },
  } } },
}
local smoothSample = Renderer.samplePoseInterpolated(smoothModel, 1, 0, 0.5, true)
local smoothT, smoothR, smoothS = smoothSample(1)
ok(math.abs(smoothT[1] - 20) < 0.000001,
  "ordinary limb translation still receives the 60 Hz halfway pose")
ok(math.abs(smoothR[1] - 1500) < 0.000001,
  "ordinary Euler motion still interpolates")
ok(math.abs(smoothR[2] - 32768) < 0.000001,
  "binary-angle seam uses the short arc instead of spinning around")
ok(math.abs(smoothS[1] - 1.1) < 0.000001,
  "scale still interpolates linearly")

local teleportModel = {
  rootScale = 1, height = 100,
  bones = smoothModel.bones,
  anims = { { frames = 2, loopStart = 0, tracks = {
    [1] = { t = { { 0, 60 }, 0, 0 }, r = { 0, 0, 0 }, s = { 1, 1, 1 } },
  } } },
}
local teleportSample = Renderer.samplePoseInterpolated(teleportModel, 1, 0, 0.5, true)
local teleportT = teleportSample(1)
ok(teleportT[1] == 0,
  "one-frame translation teleport holds the source pose rather than inventing a halfway limb")

local bad, badErr = Pack.parse("DSM3bad")
ok(bad == nil and type(badErr) == "string", "truncated pack rejected")

print(("%d checks passed (Stadium 2 standalone renderer)"):format(checks))


local calls = {}
local meshId = 0
_G.love = {
  image = {
    newImageData = function(w, h, format, rgba)
      return { w = w, h = h, format = format, rgba = rgba }
    end,
  },
  graphics = {},
}
local g = love.graphics
function g.newMesh(format, rows, mode, usage)
  meshId = meshId + 1
  local m = { id = meshId, rows = rows }
  function m:setVertexMap(map) self.map = map end
  function m:setVertices(rows2) self.rows = rows2 end
  function m:setTexture(tex) self.texture = tex end
  function m:release() self.released = true end
  return m
end
function g.newShader(code)
  local sh = { code = code, uniforms = {} }
  function sh:send(name, value, ...) self.uniforms[name] = value end
  function sh:release() end
  return sh
end
function g.newCanvas(w, h, options)
  local c = { w = w, h = h, options = options }
  function c:setFilter(min, mag) self.filter = min .. ":" .. mag end
  function c:release() end
  return c
end
function g.newImage(data)
  local img = { data = data }
  function img:setFilter(min, mag, anisotropy) self.filter, self.anisotropy = min, anisotropy end
  function img:setWrap(s, t) self.wrapS, self.wrapT = s, t end
  function img:release() end
  return img
end
function g.getCanvas() return nil end
function g.getShader() return nil end
function g.getBlendMode() return "alpha", "alphamultiply" end
function g.getDepthMode() return nil, false end
function g.getMeshCullMode() return "none" end
function g.setCanvas(v) calls[#calls + 1] = { "canvas", v } end
function g.clear(...) calls[#calls + 1] = { "clear" } end
function g.setDepthMode(...) calls[#calls + 1] = { "depth", ... } end
function g.setShader(v) calls[#calls + 1] = { "shader", v } end
function g.setBlendMode(a, b) calls[#calls + 1] = { "blend", a, b } end
function g.setMeshCullMode(v) calls[#calls + 1] = { "cull", v } end
function g.draw(v, ...) calls[#calls + 1] = { "draw", v and v.id or "canvas", ... } end
function g.setColor(...) calls[#calls + 1] = { "color", ... } end

local gpuModel = assert(Pack.parse(bytes))
local p1 = gpuModel.prims[1]
local p2 = {}
for k, v in pairs(p1) do p2[k] = v end
p1.additive = false
p2.additive = true
gpuModel.prims = { p1, p2 }
local gpuRig = assert(Renderer.new(gpuModel))
ok(gpuRig.shaderTier == "lit" and gpuRig.shaderError == nil,
  "primary Stadium shader compiles instead of silently using compatibility rendering")
local normalColor = gpuRig.parts[1].mesh.rows[1]
ok(normalColor[9] == 1 and normalColor[10] == 1
  and normalColor[11] == 1 and normalColor[12] == 1,
  "lit normal geometry reaches the shader with neutral vertex colour")
local canvas, renderErr = gpuRig:renderToCanvas(64, 64)
ok(canvas ~= nil, renderErr or "GPU canvas")
local canvasNeutralColor, canvasFirstDraw
for index, call in ipairs(calls) do
  if call[1] == "color" and call[2] == 1 and call[3] == 1
      and call[4] == 1 and call[5] == 1 then
    canvasNeutralColor = canvasNeutralColor or index
  end
  if call[1] == "draw" then canvasFirstDraw = canvasFirstDraw or index end
end
ok(canvasNeutralColor and canvasFirstDraw and canvasNeutralColor < canvasFirstDraw,
  "private viewer rendering clears global draw colour before consuming ROM vertex SHADE")
ok(gpuRig.shader.uniforms.effectIntensityMode == 2,
  "shared flame selects the IA8 intensity-and-alpha shader path")
ok(gpuRig.shader.uniforms.celShadingEnabled == 0,
  "Stadium shader style leaves source lighting continuous")
local liveShaderStyle = "cel"
gpuRig.shaderStyleProvider = function() return liveShaderStyle end
local celCanvas, celErr = gpuRig:renderToCanvas(64, 64)
ok(celCanvas ~= nil and gpuRig.shader.uniforms.celShadingEnabled == 1,
  celErr or "cel-shaded option updates an existing renderer")
liveShaderStyle = "stadium"
gpuRig:renderToCanvas(64, 64)
ok(gpuRig.shader.uniforms.celShadingEnabled == 0,
  "renderer returns to Stadium lighting without rebuilding the model")
calls = {}
gpuRig:renderToCanvas(64, 64)
local drawOrder, blendBeforeDraw = {}, {}
local currentBlend
for _, call in ipairs(calls) do
  if call[1] == "blend" then currentBlend = call[2] end
  if call[1] == "draw" and type(call[2]) == "number" then
    drawOrder[#drawOrder + 1] = call[2]
    blendBeforeDraw[#blendBeforeDraw + 1] = currentBlend
  end
end
ok(#drawOrder == 2, "two primitive draw calls")
ok(blendBeforeDraw[1] == "alpha", "opaque pass first")
ok(blendBeforeDraw[2] == "add", "additive pass second")
local viewerDepthContract = false
for _, call in ipairs(calls) do
  if call[1] == "depth" and call[2] == RenderContract.MODEL_DEPTH_COMPARE then
    viewerDepthContract = true
  end
end
ok(viewerDepthContract, "viewer uses the shared authored eye and face depth contract")
ok(gpuRig.parts[1].mesh.texture ~= nil, "texture uploaded")
ok(gpuRig.parts[1].mesh.texture.filter == "nearest", "renderer preserves sharp source texels")
ok(canvas.filter == "linear:linear", "render target uses linear filtering")
ok(gpuRig.parts[1].mesh.map and #gpuRig.parts[1].mesh.map == 3, "index map uploaded")
calls = {}
local ident={1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1}
local sceneOK,sceneErr=gpuRig:drawScene("opaque",ident,{viewProjection=ident})
ok(sceneOK,sceneErr or "shared scene draw")
ok(gpuRig.shader.uniforms.prelitShadowEnabled == 0,
  "Pokemon unlit materials do not inherit arena floor-shadow reception")
local sceneCanvas,sceneDraws,sceneDepthContract=false,0,false
local sceneNeutralColor,sceneFirstDraw
for index,call in ipairs(calls) do
  if call[1]=="canvas" then sceneCanvas=true end
  if call[1]=="color" and call[2]==1 and call[3]==1
      and call[4]==1 and call[5]==1 then sceneNeutralColor=sceneNeutralColor or index end
  if call[1]=="draw" and type(call[2])=="number" then
    sceneDraws=sceneDraws+1
    sceneFirstDraw=sceneFirstDraw or index
  end
  if call[1]=="depth" and call[2]==RenderContract.MODEL_DEPTH_COMPARE then
    sceneDepthContract=true
  end
end
ok(not sceneCanvas,"shared scene draw never binds a private actor canvas")
ok(sceneDraws==1,"shared opaque pass excludes additive attached effects")
ok(sceneNeutralColor and sceneFirstDraw and sceneNeutralColor < sceneFirstDraw,
  "shared arena rendering clears global draw colour before consuming ROM vertex SHADE")
ok(sceneDepthContract,"battle scene uses the shared authored eye and face depth contract")
calls = {}
local drawOk, drawErr = gpuRig:draw(4, 8, 64, 64, { supersample = 2, msaa = 4, zoom = 1.5, panX = 0.2, panY = -0.1 })
ok(drawOk, drawErr or "supersampled draw")
ok(gpuRig.canvasW == 128 and gpuRig.canvasH == 128, "viewer supersampling renders above presentation resolution")
ok(gpuRig.canvasMSAA == 4, "viewer requests multisample render target")
local sawFrontCull = false
for _, call in ipairs(calls) do if call[1] == "cull" and call[2] == "front" then sawFrontCull = true end end
ok(sawFrontCull, "vertical coordinate correction compensates triangle culling")
gpuRig:release()

p1.vertexSemantics, p1.lighting = "color", false
p1.color = {64,128,192,32, 64,128,192,32, 64,128,192,32, 64,128,192,32}
gpuModel.prims = { p1 }
local colorRig = assert(Renderer.new(gpuModel))
local colorRow = colorRig.parts[1].mesh.rows[1]
ok(math.abs(colorRow[9] - 64/255) < 0.0001
  and math.abs(colorRow[12] - 32/255) < 0.0001,
  "source RGBA including alpha reaches the VertexColor mesh attribute")
colorRig:release()

-- The phase-5 Poké Ball is a mirrored TEXEL1 mask, not a full image.
-- Uniforms alone do not configure desktop GPU sampling: verify the actual
-- image state at submission, including reuse after another material.
;(function()
  local arenaModel = assert(Pack.parse(bytes))
  arenaModel.species, arenaModel.staticPose, arenaModel.handlers = 0, true, nil
  local prim = arenaModel.prims[1]
  prim.additive, prim.effect, prim.decal = false, nil, false
  prim.callbackOffset, prim.callbackTextureRequired = 0xDA14, true
  local arenaRig = assert(Renderer.new(arenaModel, { boundedTextureUV = false }))
  arenaModel.handlers = { records = {
    { commandOffset = 0xDA14, descriptor = 0x81000148 },
  } }
  arenaRig.handlerState.textureBySite = { [0xDA14] = 1 }
  local secondary = Pack.image(arenaModel, 2)
  local originalDraw = g.draw
  local cases = {
    { sampler = { cms = 1, cmt = 1 }, s = "mirroredrepeat", t = "mirroredrepeat" },
    { sampler = { cms = 3, cmt = 1 }, s = "clamp", t = "mirroredrepeat" },
    { sampler = { cms = 0, cmt = 2 }, s = "repeat", t = "clamp" },
    { wrap = "repeat", s = "repeat", t = "repeat" },
    { s = "clamp", t = "clamp" },
  }
  for _, path in ipairs({ "scene", "canvas" }) do
    for _, case in ipairs(cases) do
      arenaRig.handlerState.textureSetBySite = { [0xDA14] = {
        1, 2, phase5 = true, samplers = { [2] = case.sampler }, wrap = case.wrap,
      } }
      secondary:setWrap("stale", "stale")
      local submitted = false
      function g.draw(mesh, ...)
        if mesh == arenaRig.parts[1].mesh then
          submitted = true
          ok(secondary.wrapS == case.s and secondary.wrapT == case.t,
            path .. " submits TEXEL1 with its own per-axis physical sampler")
        end
        return originalDraw(mesh, ...)
      end
      if path == "scene" then
        assert(arenaRig:drawScene("opaque", ident, {
          viewProjection = ident, sunMap = {}, sunVP = ident,
        }))
        ok(arenaRig.shader.uniforms.sunEnabled == 1
          and arenaRig.shader.uniforms.prelitShadowEnabled == 1,
          "prelit arena surfaces receive the battlers' shadow map")
      else
        assert(arenaRig:renderToCanvas(64, 64))
        ok(arenaRig.shader.uniforms.sunEnabled == 0
          and arenaRig.shader.uniforms.prelitShadowEnabled == 0,
          "private canvas clears shadow state left by the shared scene")
      end
      ok(submitted, path .. " exercised the secondary-texture draw")
    end
  end
  g.draw = originalDraw
  arenaRig:release()
end)()

local shaderAttempts = 0
function g.newShader(code)
  shaderAttempts = shaderAttempts + 1
  if shaderAttempts == 1 then error("lit shader rejected") end
  local sh = { code = code }
  function sh:send(...) end
  function sh:release() end
  return sh
end
local fallbackRig, fallbackErr = Renderer.new(assert(Pack.parse(bytes)))
ok(fallbackRig ~= nil, fallbackErr or "camera shader fallback")
ok(fallbackRig.shaderTier == "camera" and fallbackRig.shaderError:find("lit shader rejected", 1, true),
  "shader failure keeps projected camera rendering instead of raw top-left geometry")
fallbackRig:release()
_G.love = nil

print(("%d checks passed (Stadium 2 standalone renderer GPU path)"):format(checks))
