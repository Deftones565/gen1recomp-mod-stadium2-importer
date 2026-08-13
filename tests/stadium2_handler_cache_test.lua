package.path = "./?.lua;./?/init.lua;" .. package.path

local Handlers = require("mods.STADIUM2_IMPORTER.lib.model_handlers")
local Build = require("mods.STADIUM2_IMPORTER.lib.build")
local Pack = require("mods.STADIUM2_IMPORTER.lib.pack")
local Registry = require("mods.STADIUM2_IMPORTER.lib.handler_registry")

local checks = 0
local function ok(value, message)
  checks = checks + 1
  if not value then error("FAIL " .. message, 0) end
end

for descriptor, row in pairs(Registry.BY_DESCRIPTOR) do
  ok(row.ownership and row.geometry and row.texturePolicy and row.argumentDecoder,
    ("callback %08X has a complete family contract"):format(descriptor))
end
ok(Registry.BY_DESCRIPTOR[0x81000140].ownership == "following"
  and Registry.BY_DESCRIPTOR[0x81000140].geometry == "state-only",
  "phase-5 contract owns following source geometry without generated scans")

local function be16(value)
  return string.char(math.floor(value / 256) % 256, value % 256)
end

local function be32(value)
  return string.char(math.floor(value / 0x1000000) % 256,
    math.floor(value / 0x10000) % 256,
    math.floor(value / 0x100) % 256, value % 256)
end

local fragment = string.rep("\0", 0x40)
  .. be16(4) .. be16(41) .. be16(2000)
  .. be32(0x8FF00100) .. be32(0x8FF00200)
  .. string.rep("\xA5", 0x80)

local nodes = {
  { handler = 0x81000058, bone = 3, boneId = 12, arg = 0x40, commandOffset = 0x88 },
  { handler = 0x81000060, bone = 4, boneId = 11, arg = 0x40, commandOffset = 0x98 },
  { handler = 0x81000030, bone = 5, boneId = 10, arg = 0x46, commandOffset = 0xA8 },
  { handler = 0x81000080, bone = 0, boneId = 1, arg = nil, commandOffset = 0xB8 },
}

local compiled = Handlers.compile(nodes, fragment, 0x8FF00000, 0x40)
ok(#compiled == 4, "compiled handler count")
ok(compiled[1].family == "visibility-range-enable", "enable gate family")
ok(compiled[1].gate.selector == 4, "enable gate selector")
ok(compiled[1].gate.minimum == 41, "enable gate minimum")
ok(compiled[1].gate.maximum == 2000, "enable gate maximum")
ok(compiled[1].argAddress == 0x8FF00040, "argument address")
ok(compiled[3].sourcePointers[1] == 0x8FF00100, "wrapper source pointer 1")
ok(compiled[3].sourcePointers[2] == 0x8FF00200, "wrapper source pointer 2")
ok(compiled[4].noRender == true, "registration is non-rendering")

local enabled = Handlers.evaluate(compiled[1], 2, { selector = 4, rangeValue = 100 })
ok(enabled and enabled.bit0 == true, "enable gate matched")
local disabled = Handlers.evaluate(compiled[1], 2, { selector = 4, rangeValue = 3000 })
ok(disabled and disabled.bit0 == false, "enable gate outside range")
local inverseMatched = Handlers.evaluate(compiled[2], 2, { selector = 4, rangeValue = 100 })
ok(inverseMatched and inverseMatched.bit0 == false, "inverse gate matched")
local inverseOutside = Handlers.evaluate(compiled[2], 2, { selector = 9, rangeValue = 100 })
ok(inverseOutside and inverseOutside.bit0 == true, "inverse gate mismatch")
ok(Handlers.evaluate(compiled[1], 0, { selector = 4, rangeValue = 100 }) == nil, "phase filtering")
local registration = Handlers.evaluate(compiled[4], 0, {})
ok(registration and registration.operation == "register-model-context", "registration operation")
ok(registration.ifEmpty == true and registration.noRender == true, "registration semantics")

local pack = "DSM4synthetic" .. Handlers.packExtension(compiled, 0x8FF00000, fragment)
local decoded = Handlers.readExtension(pack)
ok(decoded ~= nil, "handler extension decoded")
ok(decoded.version == 4, "handler extension version")
ok(decoded.sourceBase == 0x8FF00000, "handler extension source base")
ok(#decoded.records == 4, "handler extension record count")
ok(decoded.fragment == fragment, "handler extension retains model fragment")
ok(decoded.records[1].family == "visibility-range-enable", "roundtrip family")
ok(decoded.records[1].gate.selector == 4, "roundtrip gate selector")
ok(decoded.records[1].gate.minimum == 41 and decoded.records[1].gate.maximum == 2000, "roundtrip gate range")
ok(decoded.records[2].gate.invert == true, "roundtrip inverse gate")
ok(decoded.records[3].sourcePointers[1] == 0x8FF00100, "roundtrip wrapper pointer")
ok(decoded.records[4].noRender == true, "roundtrip no-render flag")
ok(decoded.records[1].boneId == 12 and decoded.records[1].commandOffset == 0x88,
  "v4 preserves physical callback identity")
local resolvedBytes, resolvedOffset = Handlers.resolvePointer(decoded, 0x8FF00040, 6)
ok(resolvedBytes == fragment:sub(0x41, 0x46), "cached fragment pointer resolution")
ok(resolvedOffset == 0x40, "cached fragment pointer offset")
ok(Handlers.resolvePointer(decoded, 0x8FEFFFFF, 1) == nil, "cached fragment rejects low pointer")
ok(Handlers.readExtension("DSM3old-pack") == nil, "old pack has no handler extension")

local moveRows = {}
for i = 1, 165 do moveRows[i] = { 0, -1 } end
local contexts = {}
for i = 1, #Build.CONTEXTS do contexts[i] = 0xFFFF end
local packed = Build.pack({
  rootScale = { 1, 1, 1 },
  bones = { { parent = -1, t = { 0, 0, 0 }, r = { 0, 0, 0 }, s = { 1, 1, 1 } } },
  prims = { { tex = 0, cull = 0, blend = "alpha", texAnim = -1,
    materialOffset = 0x40, callbackOffset = 0xA8,
    pos = { 0, 0, 0, 1, 0, 0, 0, 1, 0 },
    uv = { 0, 0, 1, 0, 0, 1 },
    nrm = { 0, 0, 1, 0, 0, 1, 0, 0, 1 },
    skin = { 0, 0, 0 }, nverts = 3, idx = { 0, 1, 2 }, nidx = 3 } },
  textures = { { w = 1, h = 1, rgba = "\255\255\255\255" } },
  anims = {},
  auxAnims = {},
  handlerOps = compiled,
  handlerSourceBase = 0x8FF00000,
  handlerFragment = fragment,
}, 25, moveRows, contexts)
ok(packed:sub(1, 4) == "DSM4", "handler-aware pack uses DSM4 magic")
local packedHandlers = Handlers.readExtension(packed)
ok(packedHandlers and #packedHandlers.records == 4, "real pack carries handler extension")
ok(packedHandlers.fragment == fragment, "real pack carries handler fragment")
ok(packedHandlers.records[1].bone == 3, "real pack preserves handler bone")
local parsed = assert(Pack.parse(packed))
ok(parsed.prims[1].geometryMode == 0 and parsed.prims[1].vertexSemantics == "normal",
  "DSM4 primitive semantics roundtrip")

local state, deferred = Handlers.run(compiled, 0, { modelContext = "model-25" }, {})
ok(state.modelContext == "model-25", "phase zero model registration")
ok(#deferred == 0, "registration does not create render work")
state, deferred = Handlers.run(compiled, 2, { selector = 4, rangeValue = 100 }, state)
ok(state.bit0ByBone[3] == true, "phase two enable gate state")
local extensionState, extensionDeferred = Handlers.runExtension(decoded, 2, { selector = 4, rangeValue = 100 }, {})
ok(extensionState.bit0ByBone[3] == true, "extension runtime applies gate")
ok(#extensionDeferred == 0 and extensionState.operations[0xA8]
  and extensionState.operations[0xA8].extension == decoded,
  "executed runtime operation carries fragment extension")
ok(state.bit0ByBone[4] == false, "phase two inverse gate state")
ok(#deferred == 0, "all known handlers execute without deferred placeholders")
ok(state.operations[0xA8] and state.operations[0xA8].record.family == "display-list-wrapper",
  "compiled handler operation retained by command site")

local effectRecords = Handlers.compile({
  { handler = 0x81000068, bone = 2, boneId = 7, arg = 0x40, commandOffset = 0xCC },
  { handler = 0x81000070, bone = 3, boneId = 8, arg = 0x40, commandOffset = 0xDC },
  { handler = 0x81000078, bone = 4, boneId = 9, arg = 0x40, commandOffset = 0xEC },
}, fragment, 0x8FF00000)
local effectPack = "DSM4effects" .. Handlers.packExtension(effectRecords, 0x8FF00000, fragment, {
  prims = { { materialOffset = 0x40, callbackOffset = 0xCC } }, handlerTextures = {
    { commandOffset = 0xCC, pointer = 0x8FF00040, slot = 5, w = 64, h = 32, format = 0, size = 2 },
    { commandOffset = 0xDC, pointer = 0x8FF00040, slot = 6, w = 64, h = 64, format = 0, size = 2 },
  },
})
local effectExtension = assert(Handlers.readExtension(effectPack))
ok(effectExtension.render.primitiveCallbacks[1] == 0xCC,
  "v4 render metadata preserves primitive callback site")
ok(#effectExtension.records[1].program.textures == 1, "dynamic callback texture compiled")
local effectState, effectDeferred = Handlers.runExtension(effectExtension, 2,
  { sourceFrame = 3, attributeColorsBySite = { [0xEC] = { 1, 0.5, 0.25, 1 } } }, {})
ok(#effectDeferred == 0 and effectState.textureBySite[0xCC] == 6,
  "dynamic callback texture selected by command site")
ok(effectState.operations[0xDC].result.transform == nil,
  "dynamic object callback does not invent a random transform")
ok(effectState.attributesBySite[0xEC].color[2] == 0.5,
  "source-provided attribute colour is retained by command site")

local slimeRecords = Handlers.compile({
  { handler = 0x81000048, bone = 2, arg = 0x40, commandOffset = 0xF0 },
}, fragment, 0x8FF00000)
local slimePack = "DSM4slime" .. Handlers.packExtension(slimeRecords,
  0x8FF00000, fragment, { handlerTextures = {
    -- A deduplicated texture cache can represent two source tiles with one
    -- image slot when their complete source payload is identical.
    { commandOffset = 0xF0, pointer = 0x8FF00040, slot = 9,
      w = 32, h = 32, format = 0, size = 2 },
  } })
local slimeExtension = assert(Handlers.readExtension(slimePack))
local slimeState = select(1, Handlers.runExtension(slimeExtension, 2,
  { species = 88, sourceFrame = 0 }, {}))
ok(slimeState.textureBySite[0xF0] == 10,
  "deduplicated slime texture remains the primary material layer")
ok(slimeState.textureSetBySite[0xF0]
    and slimeState.textureSetBySite[0xF0][1] == 10
    and slimeState.textureSetBySite[0xF0][2] == 10,
  "deduplicated slime texture still resolves both scrolling material tiles")
ok(slimeState.textureSetBySite[0xF0].tileOrigins[1][1] == 0
    and slimeState.textureSetBySite[0xF0].tileOrigins[2][2] == 0
    and slimeState.textureSetBySite[0xF0].wrap == "repeat"
    and slimeState.textureSetBySite[0xF0].combineMode == "lerp-then-shade",
  "dual-texture runtime retains ROM tile, sampler, and combiner state")
ok(slimeState.materialBySite[0xF0]
    and slimeState.materialBySite[0xF0].primitiveColor[1] == 1
    and slimeState.materialBySite[0xF0].environmentColor[4] == 1
    and slimeState.materialBySite[0xF0].combine[1] == 0,
  "dual-texture callback replaces inherited primitive/environment material")

local grimer = Handlers.compile({
  { handler = 0x81000050, bone = 2, arg = 0x40, commandOffset = 0xFC },
}, fragment, 0x8FF00000)[1]
ok(Handlers.evaluate(grimer, 2, {
  species = 88, selector = 2, rangeValue = 70, textureFrame = 1,
}).textureFrame == 4, "Grimer callback follows its source animation-frame override")

print(("%d checks passed (Stadium 2 handler cache)"):format(checks))
