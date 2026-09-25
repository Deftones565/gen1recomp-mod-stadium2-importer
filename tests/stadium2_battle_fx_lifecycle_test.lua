package.path = "./?.lua;./?/init.lua;" .. package.path

local Lifecycle = require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_lifecycle")

local checks = 0
local function ok(value, message)
  checks = checks + 1
  if not value then error("FAIL " .. message, 0) end
end

local families = Lifecycle.metadata()
local familyCount = 0
for id = 0, 29 do if families[id] then familyCount = familyCount + 1 end end
ok(Lifecycle.COUNT == 30 and familyCount == 30, "metadata has 30 rows")
local empty = {1, 14, 22, 24, 25, 28}
for _, id in ipairs(empty) do ok(families[id].empty, "empty row " .. id) end
ok(not families[19].empty and families[19].init == 0x841594E0,
  "unreachable family 19 remains non-empty")
ok(not families[29].empty and families[29].init == 0x8415703C,
  "family 29 callback row is retained")
local immutable = pcall(function() families[4].group = "invented" end)
ok(not immutable, "metadata rows are immutable")

local events = {}
local manager = Lifecycle.new({callback = function(phase, address, instance,
    context)
  events[#events + 1] = {phase = phase, address = address,
    id = instance.id, counter = instance.counter, context = context}
end})
local source = {sourceSide = "player", targetSide = "enemy", nested = {x = 1}}
local first = assert(manager:spawn(4, source))
source.nested.x = 99
local second = assert(manager:spawn(6, {sourceSide = "enemy"}))
ok(first == 1 and second == 2, "lifecycle IDs are monotonic")
ok(events[1].phase == "init" and events[1].address == families[4].init
  and events[2].id == second, "spawn invokes init in stable ID order")
manager:step(1)
ok(events[3].id == first and events[3].phase == "update"
  and events[4].id == second, "updates are stable ID ordered")
ok(manager:snapshot().instances[1].context.nested.x == 1,
  "spawn context is copied")

-- Spawn every seven ticks below 120; drain through 180 and stop at 181.
manager:step(118)
local snap119 = manager:snapshot()
ok(snap119.frame == 119 and snap119.instances[1].counter == 119
  and snap119.instances[1].gateEligible, "family 4 frame 119 gate")
manager:step(1)
ok(not manager:snapshot().instances[1].gateEligible,
  "family 4 frame 120 gate")
manager:step(6)
ok(not manager:snapshot().instances[1].gateEligible,
  "family 4 frame 126 gate")
manager:step(54)
ok(manager:snapshot().instances[1].counter == 180
  and manager:snapshot().instances[1].active, "family 4 frame 180 alive")
local packets = manager:draw()
ok(#packets == 2 and packets[1].command == 0xDA380003
  and packets[1].pointer == 0x841A4D08
  and packets[1].drawHelper == families[4].drawHelper
  and packets[1].requiresDrawHelper and packets[1].instanceId == first,
  "draw packet preserves exact command evidence")
packets[1].context.sourceSide = "mutated"
ok(manager:draw()[1].context.sourceSide == "player",
  "draw packet context is caller-owned")
manager:step(1)
ok(not manager:snapshot().instances[1].active and #manager:draw()==0,
  "families 4 and 6 terminate at 181")

for _,family in ipairs({2,4,6,21}) do
  local ticks={}
  local m=Lifecycle.new({callback=function(phase,_,instance)
    if phase=="update" and instance.gateEligible then ticks[#ticks+1]=instance.counter end
  end})
  m:spawn(family)
  local stop=family==2 and 1801 or 181
  m:step(stop)
  ok(#ticks==(family==2 and 589 or 17),"native spawn cadence family "..family)
  ok(ticks[#ticks]==(family==2 and 1767 or 119),"last spawn family "..family)
  ok(not m:snapshot().instances[1].active,"native termination family "..family)
end

local wrapping=Lifecycle.new({callback=function()end})
local wid=wrapping:spawn(3)
wrapping.instances[wid].counter=32767
wrapping:step(1)
ok(wrapping:snapshot().instances[1].counter==-32768,"native signed counter wraps")

-- Family 12's emission window and direct termination are distinct from its draw
-- gate: frame 2 draws, frame 50 is terminated before resolver work.
local twelve = Lifecycle.new({callback = function() end})
local tid = assert(twelve:spawn(12, {sourceSide = "player"}))
twelve:step(1)
ok(#twelve:draw() == 0, "family 12 draw gate below counter 2")
twelve:step(1)
ok(#twelve:draw() == 1, "family 12 draws at counter 2")
twelve:step(47)
ok(twelve:snapshot().instances[1].counter == 49
  and twelve:snapshot().instances[1].active, "family 12 frame 49 alive")
twelve:step(1)
ok(not twelve:snapshot().instances[1].active and #twelve:draw() == 0
  and twelve:snapshot().instances[1].lastResult == -1,
  "family 12 direct termination at frame 50")
ok(tid == 1, "family 12 ID is independent and monotonic")

local seventeen = Lifecycle.new({callback = function() end})
assert(seventeen:spawn(17))
seventeen:step(49)
ok(seventeen:snapshot().instances[1].active, "family 17 alive at 49")
seventeen:step(1)
ok(not seventeen:snapshot().instances[1].active,
  "family 17 direct termination at 50")

local twenty = Lifecycle.new({callback = function() end})
assert(twenty:spawn(20))
twenty:step(180)
ok(twenty:snapshot().instances[1].active, "family 20 alive at 180")
twenty:step(1)
ok(not twenty:snapshot().instances[1].active,
  "family 20 direct termination at 181")

-- Missing ROM asset diagnostics are frozen-schema and deduplicated, while the
-- instance and its evidence packet remain available.
local unsupported = Lifecycle.new()
assert(unsupported:spawn(16, {targetSide = "enemy"}))
unsupported:step(1)
unsupported:step(1)
unsupported:draw()
unsupported:draw()
local diagnostics = unsupported:diagnosticSnapshot()
ok(#diagnostics == 1 and diagnostics[1].code == "unresolved-spike-cannon-model",
  "missing Spike Cannon model diagnostic is deduplicated")
for _, item in ipairs(diagnostics) do
  ok(item.code and item.severity and (item.effectId == nil
    or type(item.effectId) == "number")
    and item.programId == nil and item.address ~= nil and item.kind
    and item.message, "diagnostic uses frozen schema")
end
ok(#unsupported:draw() == 1, "unsupported family remains alive")

local copied = unsupported:snapshot()
copied.instances[1].context.targetSide = "mutated"
ok(unsupported:snapshot().instances[1].context.targetSide == "enemy",
  "snapshot is deeply copied")
local beforeSnapshot = unsupported:snapshot().instances[1].lastPhase
unsupported:snapshot()
ok(unsupported:snapshot().instances[1].lastPhase == beforeSnapshot,
  "snapshot does not mutate draw phase")
unsupported:release()
ok(#unsupported:snapshot().instances == 0, "release removes instances")

local identity = Lifecycle.new()
assert(identity:spawn(7, {effectId = 77, programId = 259,
  sourceSide = "player"}))
local identityDiagnostic = identity:diagnosticSnapshot()[1]
ok(identityDiagnostic.effectId == 77 and identityDiagnostic.instanceId == 1
  and identityDiagnostic.programId == 259
  and identityDiagnostic.context.programId == 259,
  "diagnostic preserves context effect identity and instance metadata")

print(("stadium2 battle FX lifecycle: %d checks passed"):format(checks))
