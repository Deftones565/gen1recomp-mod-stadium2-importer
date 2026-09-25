package.path = "./?.lua;./?/init.lua;" .. package.path

local Ribbon = require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_ribbon")
local Lifecycle = require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_lifecycle")

local checks = 0
local function ok(value, message)
  checks = checks + 1
  if not value then error("FAIL " .. message, 0) end
end
local function same(a, b, message)
  ok(type(a) == "table" and type(b) == "table" and #a == #b,
    message .. " (length)")
  for i = 1, #a do ok(a[i] == b[i], message .. " [" .. i .. "]") end
end

ok(Ribbon.families[23] and Ribbon.families[26] and Ribbon.families[27],
  "retail ribbon families are registered")

local expectedColors = {
  [23] = {{100, 200, 255, 200}, {0, 100, 200, 0}},
  [26] = {{255, 255, 255, 200}, {100, 150, 150, 0}},
  [27] = {{255, 255, 100, 200}, {150, 150, 0, 0}},
}
for id, expected in pairs(expectedColors) do
  local state = Ribbon.new(id, {lifecycleScale = 1})
  same(state.colors[1], expected[1], "family " .. id .. " primary color")
  same(state.colors[2], expected[2], "family " .. id .. " environment color")
end

-- The native update grows six records per tick and caps at 200 records.
local state = Ribbon.new(23, {lifecycleScale = 1})
for i = 1, 34 do ok(Ribbon.step(state) == 0, "ribbon remains active at tick " .. i) end
ok(state.count == 200, "ribbon record count caps at 200")
ok(state.counter == 21 and state.cycles == 1,
  "first ROM duration rollover advances from counter 18")

-- Twenty-one ROM cycles terminate on the 291st 30 Hz update.
local lifetime = Ribbon.new(23, {})
for i = 1, 290 do ok(Ribbon.step(lifetime) == 0, "ribbon alive before expiry") end
ok(lifetime.active and lifetime.counter == 30 and lifetime.cycles == 20,
  "ribbon is active on frame 290")
ok(Ribbon.step(lifetime) == -1 and not lifetime.active,
  "ribbon terminates on frame 291")
ok(Ribbon.step(lifetime) == -1, "terminated ribbon stays terminated")

-- Geometry is a draw snapshot: N64 signed truncation, Y ground clamp, and
-- the two triangles per adjacent ribbon segment must remain literal.
local geometryState = Ribbon.new(23, {})
geometryState.count = 2
geometryState.vertices[1] = {-1.75, -4.25, 2.9, 1}
geometryState.vertices[2] = {3.99, 4.99, -5.99, 1}
geometryState.vertices[3] = {7.99, 8.99, 9.99, 1}
geometryState.vertices[4] = {-10.99, 11.99, 12.99, 1}
local geometry = Ribbon.geometry(geometryState)
local prefix = {}
for i = 1, 12 do prefix[i] = geometry.pos[i] end
same(prefix, {-1, 0, 2, 3, 4, -5, 7, 8, 9, -10, 11, 12},
  "ribbon geometry truncates and clamps Y")
ok(#geometry.pos == 1200, "ribbon geometry retains fixed 400 vertex allocation")
same(geometry.idx, {1, 3, 2, 3, 4, 2}, "ribbon geometry uses ROM quad indices")

local first = Ribbon.new(23, {})
local second = Ribbon.new(23, {})
first.colors[1][1] = 17
ok(second.colors[1][1] == 100, "ribbon instances own color state")
Ribbon.step(first, {10, 20, 30})
ok(second.vertices[1][1] == 0 and second.counter == 0,
  "ribbon instances own persistent motion state")

-- A draw snapshot must not advance the authored simulation.
local before = first.counter
local snapshot = Ribbon.geometry(first)
ok(first.counter == before and snapshot.count == first.count,
  "geometry snapshot has no simulation side effects")

-- Lifecycle integration keeps init, update, and draw in stable order and
-- honors a native update callback's -1 termination result.
local phases = {}
local manager = Lifecycle.new({callback = function(phase)
  phases[#phases + 1] = phase
end})
local id = assert(manager:spawn(23, {sourceSide = "player"}))
manager:step(1)
local packets = manager:draw()
ok(id == 1 and phases[1] == "init" and phases[2] == "update"
  and phases[3] == "draw" and #packets == 1,
  "ribbon lifecycle invokes init update and draw")

local terminated = Lifecycle.new({callback = function(phase)
  if phase == "update" then return -1 end
end})
assert(terminated:spawn(23))
terminated:step(1)
local terminatedSnapshot = terminated:snapshot().instances[1]
ok(not terminatedSnapshot.active and terminatedSnapshot.lastResult == -1,
  "lifecycle update callback result -1 terminates instance")

local builtin = Lifecycle.new()
local builtinId = assert(builtin:spawn(23, {sourceSide = "player",
  lifecycleAnchor={0,0,0},lifecycleScale=1}))
builtin:step(1)
local builtinSnapshot = builtin:snapshot()
local builtinInstance = builtinSnapshot.instances[1]
ok(builtinId == 1 and builtinInstance.active and builtinInstance.frame == 1
  and builtinInstance.lastResult == 0 and #builtinSnapshot.diagnostics == 0,
  "default lifecycle manager runs ribbon update")
ok(builtinSnapshot.packets[1].geometry
  and builtinSnapshot.packets[1].geometry.count == 6,
  "default lifecycle snapshot exposes ribbon geometry")
builtin:release(builtinId)
ok(#builtin:snapshot().instances == 0, "lifecycle release removes ribbon")

local builtinLifetime = Lifecycle.new()
assert(builtinLifetime:spawn(23))
builtinLifetime:step(291)
ok(#builtinLifetime:snapshot().instances == 1
  and not builtinLifetime:snapshot().instances[1].active,
  "default lifecycle ribbon expires at frame 291")

print(("stadium2 battle FX ribbon: %d checks passed"):format(checks))
