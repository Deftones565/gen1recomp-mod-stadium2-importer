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
local decalCompare, decalWrite = RenderContract.depthState({
  sourceTextureMissing = false, decal = true }, true)
local bodyCompare, bodyWrite = RenderContract.depthState({
  sourceTextureMissing = false, decal = false }, true)
ok(decalCompare == "lequal" and not decalWrite
  and bodyCompare == "less" and bodyWrite,
  "alpha decals compare equal without writing over ordinary body depth")

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
      tex = 0, cull = 1, blend = "add", texAnim = 0, texMap = { [5] = 1 },
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
ok(Renderer.FORMAT[4] and Renderer.FORMAT[4][1] == "VertexColor",
  "DSM4 mesh format carries source vertex RGBA")
local _, normalDecls = Renderer.SHADER_SOURCE:gsub("varying vec3 vNormal;", "")
local _, sunDecls = Renderer.SHADER_SOURCE:gsub("varying vec3 vSun;", "")
ok(normalDecls == 1 and sunDecls == 1,
  "shared shader varyings are declared once across LÖVE's combined stages")
local _, shadowReads = Renderer.SHADER_SOURCE:gsub("shadowDepth%(p%.xy", "")
ok(shadowReads == 4,
  "softened Pokemon shadows retain the four-fetch PCF cost")
ok(Renderer.SHADER_SOURCE:find("0.30+(stadiumShade-0.30)*shadowVisibility", 1, true) ~= nil,
  "Pokemon self-shadow preserves the authored ambient lighting floor")
ok(Renderer.SHADER_SOURCE:find("vGeneratedUV", 1, true) ~= nil,
  "shared shader implements normal-driven Stadium reflection coordinates")
ok(Renderer.primitiveRenderState({}, { geometryMode = 0x40000 }).textureGenEnabled,
  "G_TEXTURE_GEN enables the shared reflection path")

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
  "dual-texture material builder preserves a detailed authored atlas")
model.textures[2].rgba = string.rep("\255\255\255\255", 4)
ok(rig:currentTexture(model.prims[1]) == 3,
  "dual-texture material builder replaces a uniform body fill")
model.prims[1].decal = false
ok(rig:callbackUsesMaterialFx(model.prims[1]),
  "dual-texture material FX reaches a non-decal body surface")
model.prims[1].decal = true
ok(not rig:callbackUsesMaterialFx(model.prims[1]),
  "dual-texture material FX does not cover an alpha face decal")
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
ok(cameraSquare.near > 0 and cameraSquare.far > cameraSquare.near, "camera clip range valid")
local orient = Renderer.modelMatrix(0, 0, 1, 0, 5, 0, true)
ok(math.abs(orient[6] + 1) < 0.000001 and math.abs(orient[8] - 5) < 0.000001, "Stadium model matrix flips vertical axis around model center")
local shiftedProjection = Renderer.perspective(math.pi / 4, 1, 0.1, 100, 0.25, -0.5)
ok(math.abs(shiftedProjection[3] + 0.25) < 0.000001 and math.abs(shiftedProjection[7] - 0.5) < 0.000001, "projection supports screen-space model panning")

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
  local sh = { code = code }
  function sh:send(...) end
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
  function img:setWrap() end
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
function g.setColor(...) end

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
local sceneCanvas,sceneDraws,sceneDepthContract=false,0,false
for _,call in ipairs(calls) do
  if call[1]=="canvas" then sceneCanvas=true end
  if call[1]=="draw" and type(call[2])=="number" then sceneDraws=sceneDraws+1 end
  if call[1]=="depth" and call[2]==RenderContract.MODEL_DEPTH_COMPARE then
    sceneDepthContract=true
  end
end
ok(not sceneCanvas,"shared scene draw never binds a private actor canvas")
ok(sceneDraws==1,"shared opaque pass excludes additive attached effects")
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
