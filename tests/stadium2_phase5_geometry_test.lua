package.path = "./?.lua;./?/init.lua;" .. package.path

local Phase5 = require("mods.STADIUM2_IMPORTER.lib.render_callbacks.phase5_geometry")
local Registry = require("mods.STADIUM2_IMPORTER.lib.handler_registry")
local Handlers = require("mods.STADIUM2_IMPORTER.lib.model_handlers")

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
fragment = write(fragment, 0x14, be32(base + 0xD8)) -- callback argument -> TEXEL1 item
fragment = write(fragment, 0x30, be32(base + 0x50)) -- item -> image config
fragment = write(fragment, 0x38, be32(base + 0x70)) -- item -> colors
fragment = write(fragment, 0x3C, be32(base + 0x88)) -- item -> geometry/texture state
fragment = write(fragment, 0x40, be32(base + 0xA0)) -- item -> dynamic environment track
fragment = write(fragment, 0x50, be32(base + 0x90)) -- image config -> texels
fragment = write(fragment, 0x58, be32(base + 0x60)) -- image config -> descriptor
fragment = write(fragment, 0x60, string.char(0, 3, 5, 5, 1, 1, 1, 1)
  .. be16(32) .. be16(32))
fragment = write(fragment, 0xA0, be32(base + 0xD0) .. be32(0) .. be32(base + 0xB0))
fragment = write(fragment, 0xD8, be32(base + 0xA0)) -- TEXEL1 item -> image config
fragment = write(fragment, 0xB0, string.char(4, 0, 0, 0, 5, 5, 0, 0)
  .. be16(32) .. be16(32))
fragment = write(fragment, 0x70, be32(base + 0xC0))
fragment = write(fragment, 0x74, be32(base + 0x80))
fragment = write(fragment, 0x78, be32(base + 0x84))
fragment = write(fragment, 0x80, string.char(1, 31, 3, 31, 255, 255, 255, 255))
fragment = write(fragment, 0x88, be32(0x00040000) .. be16(4500) .. be16(4500))
fragment = write(fragment, 0xC0, string.char(
  2,3,4,5, 7,7,7,1, 31,31,31,0, 7,7,7,0))

local specs = Phase5.textureSpecs(fragment, base, 0x10)
ok(#specs == 2 and specs[1].pointer == base + 0x90
  and specs[2].pointer == base + 0xD0, "phase-5 two-texture pointers decoded")
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
ok(material and material.combiner and material.combiner.cycles == 2
  and material.combiner.color0[1] == 2 and material.combiner.color0[2] == 3
  and material.combiner.color1[1] == 31 and material.combiner.color1[4] == 0,
  "phase-5 ROM combiner selectors decoded")
ok(material and material.combiner.alphaOutputZero == false,
  "phase-5 combined-alpha passthrough is not mistaken for constant zero")
local zeroAlphaMaterial = Phase5.materialSpec(
  write(fragment, 0xCC, string.char(7, 7, 7, 7)), base, 0x10)
ok(zeroAlphaMaterial and zeroAlphaMaterial.combiner.alphaOutputZero == true,
  "phase-5 records structurally identify an unused zero alpha equation")
fragment = write(fragment, 0x83, string.char(0x40))
local stageMaterial = Phase5.materialSpec(fragment, base, 0x10, 2)
ok(stageMaterial and math.abs(stageMaterial.primitiveColor[4] - 0x40 / 255) < 0.0001
  and stageMaterial.submissionMode == 2,
  "phase-5 Stadium field mode preserves authored alpha")
local combinerOnly = write(fragment, 0x74, be32(0) .. be32(0))
local combinerOnlyMaterial = Phase5.materialSpec(combinerOnly, base, 0x10, 2)
ok(combinerOnlyMaterial and combinerOnlyMaterial.combiner
  and combinerOnlyMaterial.primitiveColor[1] == 1
  and combinerOnlyMaterial.environmentColor[1] == 1,
  "phase-5 combiner remains valid without authored color pointers")
local renderState = Phase5.stateSpec(fragment, base, 0x10)
ok(renderState and renderState.geometryMode == 0x00040000
  and math.abs(renderState.textureScale[1] - 4500 / 65536) < 0.000001,
  "phase-5 reflection geometry mode and gSPTexture scale decoded")

local animated = string.rep("\0", 0x200)
animated = write(animated, 0x10, be32(base + 0x30))
animated = write(animated, 0x30, be32(base + 0x50) .. be32(base + 0xA0))
animated = write(animated, 0x50, be32(base + 0x90))
animated = write(animated, 0x58, be32(base + 0x60))
animated = write(animated, 0x60, string.char(0, 3, 0, 0, 0, 0, 0, 0)
  .. be16(32) .. be16(32))
animated = write(animated, 0xA0, be16(1) .. be16(0) .. be32(base + 0x180)
  .. be32(base + 0xB0) .. be32(base + 0xD0))
animated = write(animated, 0xB0, be16(1) .. be16(60) .. be16(3) .. be16(0)
  .. be32(base + 0xE0) .. be32(base + 0xF0) .. be32(base + 0x110))
animated = write(animated, 0xD0, be32(2) .. be32(base + 0xD8))
animated = write(animated, 0xD8, be32(base + 0x140) .. be32(base + 0x150))
animated = write(animated, 0xE0, be16(0) .. be16(30) .. be16(60))
animated = write(animated, 0xF0,
  string.char(0,20,40,60,80, 100,120,140,160,180, 200,220,240,255,255))
animated = write(animated, 0x110,
  string.char(10,30,50,70, 110,130,150,170, 210,230,250,255))
animated = write(animated, 0x180,
  be16(0) .. be16(0) .. be16(1) .. be16(-1) .. be16(32) .. be16(32))
local controller = Phase5.controllerSpec(animated, base, 0x10)
local controlledMaterial, selectedPointers, controlledScroll = Phase5.evaluateController(controller,
  { phase5 = true }, 15)
ok(controller and controller.colorController.colorTrack.kind == 1
  and controller.colorController.colorTrack.keys == 3,
  "phase-5 linear controller metadata decoded")
ok(controlledMaterial and math.abs(controlledMaterial.primitiveColor[1] - 50 / 255) < 0.0001
  and math.abs(controlledMaterial.environmentColor[1] - 60 / 255) < 0.0001
  and math.abs(controlledMaterial.primitiveLodFraction - 130 / 255) < 0.0001,
  "phase-5 primitive, environment, and LOD tracks interpolate")
ok(selectedPointers[1] == base + 0x150,
  "phase-5 controller selects its ROM texture-table frame")
ok(controller.items[1].controller.tileScroll.speedS == 1
  and controller.items[1].controller.tileScroll.speedT == -1
  and math.abs(controlledScroll[1][1] - 15 / 128) < 0.000001
  and math.abs(controlledScroll[1][2] - 15 / 128) < 0.000001,
  "phase-5 RDP tile-origin animation becomes normalized texture scroll")
local animatedSpecs = Phase5.textureSpecs(animated, base, 0x10)
ok(#animatedSpecs == 2 and animatedSpecs[1].pointer == base + 0x140
  and animatedSpecs[2].pointer == base + 0x150,
  "phase-5 controller texture frames are retained for export")

local state = { textureBySite = {}, textureSetBySite = {}, materialBySite = {},
  renderTimeResolvedBySite = {} }
ok(Phase5.apply(state, 0x1234, { operation = "render-time-geometry-pipeline",
  geometryIndex = 0, program = { textures = {
    {slot = 10, pointer = base + 0x90, format = 0, size = 3},
    {slot = 11, pointer = base + 0xD0, format = 4, size = 0}},
    phase5Material = material } }), "phase-5 state applied")
ok(state.textureBySite[0x1234] == 11 and state.materialBySite[0x1234] == material,
  "phase-5 texture and material reach renderer state")
ok(state.textureSetBySite[0x1234][1] == 11
  and state.textureSetBySite[0x1234][2] == 12
  and state.textureSetBySite[0x1234].formats[1] == 0
  and state.textureSetBySite[0x1234].formats[2] == 4,
  "phase-5 TEXEL0/TEXEL1 and their N64 formats reach renderer state")
local animatedState = { textureBySite = {}, textureSetBySite = {},
  materialBySite = {}, renderTimeResolvedBySite = {} }
ok(Phase5.apply(animatedState, 0x5678, {
  operation = "render-time-geometry-pipeline", phase5Frame = 15,
  program = {
    textures = {
      {slot = 20, pointer = base + 0x140, format = 4, size = 0},
      {slot = 21, pointer = base + 0x150, format = 4, size = 0},
    },
    phase5Controller = controller,
    phase5Material = { phase5 = true },
  },
}), "animated phase-5 state applied")
ok(animatedState.textureBySite[0x5678] == 22
  and math.abs(animatedState.textureSetBySite[0x5678].scroll[1][1]
    - 15 / 128) < 0.000001
  and animatedState.textureSetBySite[0x5678].samplers[1].cms == 0
  and animatedState.textureSetBySite[0x5678].samplers[1].cmt == 0,
  "phase-5 selected frame, water scroll, and sampler reach renderer state")
ok(state.renderTimeResolvedBySite[0x1234] ~= nil, "phase-5 queue consumption is auditable")

local arenaSubmit = Registry.info(0x81000148)
ok(arenaSubmit and arenaSubmit.target == 0x8100343C
  and arenaSubmit.submissionMode == 2 and arenaSubmit.ownership == "following",
  "Stadium field phase-5 descriptor is registered")
local arenaGraph = Registry.info(0x81000150)
ok(arenaGraph and arenaGraph.target == 0x81003768
  and arenaGraph.family == "stage-transform-color",
  "Stadium field graph-state descriptor is registered")
local stageState = Handlers.run({{
  descriptor = 0x81000150, family = "stage-transform-color", phases = { 2 },
  commandOffset = 0x44, bone = 0,
}}, 2, { stageScale = 0.75, stageColor = { 0.5, 0.25, 1, 0.4 } })
ok(stageState and stageState.stageScale == 0.75
  and stageState.stageColor[2] == 0.25 and stageState.stageColor[4] == 0.4,
  "Stadium field phase-2 scale and color reach renderer state")

if failures > 0 then os.exit(1) end
