-- 84107998 emission marker selection, 8411E244 context markers and the
-- global D_84190178 (opcode 17) state. Run from the Gen1Recomp repository root.
package.path = "./?.lua;./?/init.lua;" .. package.path
local prefix = "mods.STADIUM2_IMPORTER.lib."
local Markers = require(prefix .. "stadium2_battle_fx_emission_markers")
local Dispatch = require(prefix .. "animation_dispatch")
local Native = require(prefix .. "stadium2_battle_fx_native")

local checks = 0
local function ok(value, message)
  assert(value, message)
  checks = checks + 1
end
local function labels(list)
  local out = {}
  for _, m in ipairs(list or {}) do out[#out + 1] = m.label .. (m.secondary and "s" or "") end
  return table.concat(out, ",")
end

local inputs = {primary = 3, secondary = 7, context = 9, attachments = {1, 100, 4, 0xFF, 6}}
ok(labels(Markers.select({flags = 0, flags2 = 0}, 0, inputs)) == "3,7s",
  "D_84190178 == 0 emits at the primary and the secondary marker")
ok(labels(Markers.select({flags = 0, flags2 = 0}, 1, inputs)) == "3",
  "opcode 17 restricts emission to the primary marker")
ok(labels(Markers.select({flags = 0x2000000, flags2 = 0}, 1, inputs)) == "7s",
  "flag 0x2000000 selects only the secondary marker")
ok(labels(Markers.select({flags = 8, flags2 = 0}, 0, inputs)) == "9",
  "flag 0x8 uses the 8411E244 context marker")
ok(labels(Markers.select({flags = 8, flags2 = 1}, 0, inputs)) == "1,4,6",
  "flags2 0x1 emits at every owner marker except 100 and 0xFF")
ok(labels(Markers.select({flags = 0, flags2 = 0}, 0, {primary = 3, secondary = 0xFF})) == "3",
  "absent (0xFF) markers are skipped")
ok(Markers.select({flags = 0, flags2 = 0}, 0, {}) == nil, "missing dispatch bytes are unresolved")
ok(Markers.select({flags = 0, flags2 = 1}, 0, {}) == nil, "missing marker list is unresolved")

local table80 = {}
for i = 0, 0x4F do table80[i + 1] = string.char(i) end
table80 = table.concat(table80)
local dispatch = string.rep("\0", 0x13C6) .. string.char(0x21, 0x22) .. string.rep("\0", 0x12)
  .. string.char(0x33) .. string.rep("\0", 0x40)
ok(Dispatch.contextMarker(252, table80, dispatch) == 0x04, "context 252 reads species +0x04")
ok(Dispatch.contextMarker(274, table80, dispatch) == 0x4A, "context 274 reads species +0x4A")
ok(Dispatch.contextMarker(291, table80, dispatch) == 0x4F, "context 291 reads species +0x4F")
ok(Dispatch.contextMarker(255, table80, dispatch) == 0x33, "context 255 reads dispatch +0x13DA")
ok(Dispatch.contextMarker(281, table80, dispatch) == 0x22, "context 281 reads dispatch +0x13C7")
ok(Dispatch.contextMarker(282, table80, dispatch) == 0x21, "context 282 reads dispatch +0x13C6")
ok(Dispatch.contextMarker(262, table80, dispatch) == 0 and Dispatch.contextMarker(7, table80, dispatch) == 0,
  "unlisted contexts return zero")
ok(Dispatch.contextMarker(252, nil, nil) == nil, "missing species table stays unresolved")

-- D_84190178 over executed records only.
local function program(ops)
  local records = {}
  for i, op in ipairs(ops) do records[i] = {opcode = op, address = i} end
  return {id = 1, records = records}
end
ok(Native.execute(program({1, 17, 0}), {}).nativeMarkerSelect == 1, "opcode 17 sets D_84190178")
ok(Native.execute(program({1, 17, 3, 0}), {}).nativeMarkerSelect == 0, "opcode 3 clears D_84190178")
ok(Native.execute(program({1, 0}), {}).nativeMarkerSelect == 0, "opcode 1 clears D_84190178")
ok(Native.execute(program({0}), {}).nativeMarkerSelect == nil, "programs without 1/3/17 leave it unchanged")

local path = os.getenv("STADIUM2_ROM") or "mods/STADIUM2_IMPORTER/baseroms/stadium2.z64"
local file = io.open(path, "rb")
if not file then
  assert(os.getenv("STADIUM2_REQUIRE_ROM") ~= "1", "required ROM unavailable")
  print(checks .. " checks passed (battle FX emission markers; ROM SKIP)")
  return
end
local rom = file:read("*a"); file:close()
local FxRom = require(prefix .. "stadium2_battle_fx_rom")
local Runtime = require(prefix .. "stadium2_battle_fx_runtime")
local catalog = assert(FxRom.catalog(rom))

-- Runtime: every emission is duplicated per selected marker, in order.
local function run(moveId, markers)
  local calls = 0
  local runtime = Runtime.new({catalog = catalog, emissionMarkers = function(event, context, select)
    calls = calls + 1
    return markers(event, context, select)
  end})
  local effect = assert(runtime:trigger({moveId = moveId, alternate = false,
    sourceSide = "player", targetSide = "enemy"}))
  runtime:step(10)
  return runtime, runtime.effects[effect], calls
end
-- 84107B68 routes only modes 0/1 through 84107998; Mist also has a mode-7
-- screen particle, which is never duplicated.
local function common(effect)
  local n = 0
  for _, p in ipairs(effect.particles) do
    if p.event.mode == 0 or p.event.mode == 1 then n = n + 1 end
  end
  return n
end
local single = select(2, run(54, function() return {{label = 3}} end))
local double = select(2, run(54, function() return {{label = 3}, {label = 7, secondary = true}} end))
ok(common(double) == 2 * common(single) and common(single) > 0,
  "Mist common emissions are duplicated for the secondary marker")
ok(#double.particles - common(double) == #single.particles - common(single),
  "screen particles are not duplicated")
local firstLabel, secondaries
for _, p in ipairs(double.particles) do
  if p.event.mode == 0 or p.event.mode == 1 then
    firstLabel = firstLabel or p.nativeMarkerLabel
    if p.nativeSecondaryEmission then secondaries = (secondaries or 0) + 1 end
  end
end
ok(firstLabel == 3 and secondaries == common(single),
  "primary copies precede secondary copies and carry their labels")
local none = select(2, run(54, function() return {} end))
ok(common(none) == 0, "an emission with no valid marker creates no particles")
local unresolved = select(2, run(54, function() return nil, "test reason" end))
ok(common(unresolved) == common(single), "unresolved markers keep one set")
local r = run(54, function() return nil, "test reason" end)
local diagnosed = false
for _, d in ipairs(r:snapshot().diagnostics or {}) do
  if d.code == "unresolved-emission-markers" then diagnosed = true end
end
ok(diagnosed, "unresolved markers are diagnosed")
print(checks .. " checks passed (battle FX emission markers)")
