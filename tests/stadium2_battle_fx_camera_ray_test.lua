-- Descriptor flag 0x1 anchors (84104D28 -> 84105930): a point along the
-- camera ray, eye + (f32)(s16)material+6 * normalize(focus - eye).
-- Run from the Gen1Recomp repository root.
package.path = "./?.lua;./?/init.lua;" .. package.path
local prefix = "mods.STADIUM2_IMPORTER.lib."
local Adapter = require(prefix .. "stadium2_battle_fx_battle_adapter")
local CommonAnchor = require(prefix .. "stadium2_battle_fx_common_anchor")

local checks = 0
local function ok(value, message)
  assert(value, message)
  checks = checks + 1
end
local function near(a, b) return math.abs(a - b) < 1e-3 end

local camera = {eye = {0, 5, 10}, focus = {0, 5, 0}}
local p = assert(Adapter.cameraRayPoint(camera, 40, .05))
ok(near(p[1], 0) and near(p[2], 100) and near(p[3], 160),
  "point is eye + t * direction in native units")
local back = assert(Adapter.cameraRayPoint(camera, -40, .05))
ok(near(back[3], 240), "negative distances move behind the eye")
local degenerate = assert(Adapter.cameraRayPoint({eye = {1, 2, 3}, focus = {1, 2, 3}}, 10, 1))
ok(near(degenerate[1], 1) and near(degenerate[2], 2) and near(degenerate[3], 13),
  "84105880 uses (0,0,1) for coincident eye and focus")
ok(Adapter.cameraRayPoint(nil, 10, 1) == nil, "missing camera stays unresolved")
ok(Adapter.cameraRayPoint(camera, nil, 1) == nil, "missing distance stays unresolved")

local event = {mode = 0, flags = 1, flags2 = 0}
local result = CommonAnchor.resolve(event, {position = {0, 0, 0}, centerY = 0,
  preparedAnchor = p}, nil)
ok(near(result.anchor[1], p[1]) and near(result.anchor[3], p[3]),
  "flag-0x1 particles use the camera-ray point")
for _, d in ipairs(result.diagnostics or {}) do
  ok(d.code ~= "unresolved-common-prepared-anchor", "resolved camera ray is not diagnosed")
end

local path = os.getenv("STADIUM2_ROM") or "mods/STADIUM2_IMPORTER/baseroms/stadium2.z64"
local file = io.open(path, "rb")
if not file then
  assert(os.getenv("STADIUM2_REQUIRE_ROM") ~= "1", "required ROM unavailable")
  print(checks .. " checks passed (battle FX camera ray; ROM SKIP)")
  return
end
local rom = file:read("*a"); file:close()
local FxRom = require(prefix .. "stadium2_battle_fx_rom")
local catalog = assert(FxRom.catalog(rom))
local descriptors = 0
for id = 0, FxRom.PROGRAM_COUNT - 1 do
  for _, record in ipairs(catalog.programs[id].records) do
    local e = record.emitter
    if e and e.descriptorKind == "particle" and e.flags and e.flags % 2 == 1 then
      descriptors = descriptors + 1
      ok(e.material and type(e.material.nativeCameraRayDistance) == "number",
        ("program %d flag-0x1 descriptor decodes material +6"):format(id))
    end
  end
end
ok(descriptors > 0, "retail programs contain camera-ray descriptors")
print(("%d checks passed (battle FX camera ray; %d retail descriptors)"):format(checks, descriptors))
