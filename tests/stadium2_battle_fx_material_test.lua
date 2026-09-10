package.path = "./?.lua;./?/init.lua;" .. package.path

local Material = require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_material")

local checks = 0
local function ok(value, message)
  checks = checks + 1
  if not value then error("FAIL " .. message, 0) end
end

local function hasDiagnostic(state, code)
  for _, item in ipairs(state.diagnostics or {}) do
    if item.code == code then return true end
  end
  return false
end

local material = {
  address = 0x84170000, shapeId = 47, secondaryShapeId = 95,
  colorController = 0x84123400, colors = 0x84123500,
  primaryColor = {1, 2, 3, 255}, secondaryColor = {4, 5, 6, 128},
  constantColor = {7, 8, 9, 64},
}
local state = Material.init(material, {effectId = 2, programId = 259, age = 4})
ok(state.primaryShapeId == 47 and state.secondaryShapeId == 95
  and state.shapeId == 47 and state.selectedShapeId == nil,
  "primary and secondary shapes remain separate without selection")
ok(state.colorController == 0x84123400 and state.colorTable == 0x84123500,
  "material controller and table pointers are retained")
ok(state.primaryColor[1] == 1 and state.primaryColor[4] == 255
  and state.secondaryColor[4] == 128 and state.constantColor[4] == 64,
  "preloaded RGBA bytes remain exact")
ok(hasDiagnostic(state, "unsupported-color-controller")
  and hasDiagnostic(state, "unsupported-secondary-shape"),
  "unresolved controller and secondary shape are explicit")
local snapshot = Material.snapshot(state)
snapshot.primaryColor[1] = 99
ok(state.primaryColor[1] == 1 and snapshot._context == nil,
  "material inputs and snapshots are detached")

local invalid = Material.init({shapeId = 1, primaryColor = {1, 2, 256, 4},
  secondaryColor = {1, 2, 3}}, {effectId = 3})
ok(invalid.primaryColor == nil and invalid.secondaryColor == nil
  and hasDiagnostic(invalid, "invalid-rgba"),
  "invalid RGBA is rejected without normalization")

local colorCalls, shapeCalls = 0, 0
local resolved = Material.init(material, {effectId = 4, programId = 260,
  colorController = function(previous, context)
    colorCalls = colorCalls + 1
    ok(context.effectId == 4 and (previous.age == 0 or previous.age == 2),
      "color resolver receives detached state and context")
    return {primary = {10, 20, 30, 40}, secondary = {50, 60, 70, 80}}
  end,
  selectShape = function(previous, context)
    shapeCalls = shapeCalls + 1
    ok(context.programId == 260 and previous.secondaryShapeId == 95,
      "shape resolver receives persistent material context")
    return {shapeId = 95}
  end})
ok(not hasDiagnostic(resolved, "unsupported-color-controller")
  and not hasDiagnostic(resolved, "unsupported-secondary-shape"),
  "explicit init resolvers suppress unresolved diagnostics")
local resolvedTick = Material.step(resolved, {delta = 2})
ok(resolvedTick.age == 2 and colorCalls == 1 and shapeCalls == 1
  and resolvedTick.primaryColor[1] == 10
  and resolvedTick.selectedShapeId == 95,
  "explicit resolvers update colors and selected shape")
local again = Material.step(resolvedTick, {delta = 1})
ok(colorCalls == 2 and shapeCalls == 2 and #again.diagnostics == #resolvedTick.diagnostics,
  "resolver diagnostics remain deduplicated across steps")

local previous = Material.init({shapeId = 47, secondaryShapeId = 95,
  colorController = 1, primaryColor = {1, 2, 3, 4}}, {effectId = 5})
local bad = Material.step(previous, {
  colorController = function() return {primary = {1, 2}} end,
  selectShape = function() return "bad" end,
})
ok(bad.primaryColor[1] == 1 and bad.selectedShapeId == nil
  and hasDiagnostic(bad, "invalid-color-controller-resolver")
  and hasDiagnostic(bad, "invalid-secondary-shape-resolver"),
  "invalid resolver output preserves the previous material state")
ok(bad.age == 1, "material step advances age")

local schema = bad.diagnostics[1]
for _, field in ipairs({"code", "severity", "effectId", "programId", "address", "kind", "message"}) do
  ok(schema[field] ~= nil or field == "programId" or field == "address",
    "diagnostic schema includes " .. field)
end

local fading=Material.init({nativeAlphaRamp={target=0,step=32,startAge=8}},
  {flags=0x40000004})
for age=1,7 do fading=Material.step(fading,{age=age}) end
ok(fading.nativeAlpha==255,"native fade waits until its ROM start age")
fading=Material.step(fading,{age=8})
ok(fading.nativeAlpha==223,"native fade subtracts one authored byte step")
for age=9,15 do fading=Material.step(fading,{age=age}) end
ok(fading.nativeAlpha==0 and fading.nativeAlphaFinished,
  "native fade saturates and retires particles with the ROM termination flag")
local rising=Material.init({nativeAlphaInitial=10,nativeAlphaRamp={target=100,step=70,startAge=1}},{})
rising=Material.step(rising,{age=1});rising=Material.step(rising,{age=2})
ok(rising.nativeAlpha==100 and not rising.nativeAlphaFinished,"upward alpha ramp clamps without inventing termination")
local gated=Material.init({nativeAlphaRamp={target=0,step=255,startAge=0}},{flags=0x10})
gated=Material.step(gated,{age=1})
ok(gated.nativeAlpha==255 and hasDiagnostic(gated,"unsupported-alpha-gate"),
  "battle-gated fades remain explicitly unresolved")
print(("%d checks passed (Stadium 2 battle FX material)"):format(checks))
