-- Stadium's status particles: the material endpoint's age hold (84102320 /
local bit = require("bit")
-- 841054D4), the status-shape operations 84108AF8 / 84108CE8 / 84108E00 /
-- 84108F88, and the camera states that drive them (841136E8, 8411EE74,
-- 84120700, the wake-up). Run from the Gen1Recomp repository root.
package.path = "./?.lua;./?/init.lua;" .. package.path

local checks = 0
local function ok(value, message)
  checks = checks + 1
  if not value then error("FAIL " .. message, 0) end
end

local path = os.getenv("STADIUM2_ROM") or "mods/STADIUM2_IMPORTER/baseroms/stadium2.z64"
local file = io.open(path, "rb")
if not file then
  assert(os.getenv("STADIUM2_REQUIRE_ROM") ~= "1", "ROM required")
  print("SKIP status particles (ROM unavailable)"); return
end
local rom = file:read("*a"); file:close()

local Preview = require("mods.STADIUM2_IMPORTER.tests.stadium2_koffing_croconaw_visual.battle_fx")
local preview = Preview.new({rom = rom, releaseModel = function() end, warn = function() end,
  importer = {newRendererFromModel = function()
    return {drawScene = function() return true end, release = function() end} end}})
local context = {world = {groundY = 0, actorSlots = {enemy = {x = 10, y = 0, z = 0}, player = {x = -10, y = 0, z = 0}}}}

local function particles(runtime, shape)
  local out = {}
  for _, id in ipairs(runtime.effectOrder) do
    local effect = runtime.effects[id]
    for _, p in ipairs(effect and effect.particles or {}) do
      if p.active ~= false and (shape == nil or p.shapeId == shape) then out[#out + 1] = p end
    end
  end
  return out
end
local function run(ticks) for _ = 1, ticks do preview:step() end end

-- the sleep visual (entry 0x100, shape 0x12): held at its endpoint
preview:start(0x100, "enemy", false, context)
local runtime = preview.player.runtime
run(400)
local z = particles(runtime, 0x12)
ok(#z == 1 and z[1]._motionState.nativeAgeFrozen, "the sleep particle holds its age (object flag 0x80)")
local age = z[1].age
run(50)
ok(z[1].age == age and z[1].active ~= false, "and stays, unaged, past its byte-age end")
runtime:abortAll()
ok(#particles(runtime, 0x12) == 1, "841089D8 keeps it (held, flag 0x10000)")

-- 84108E00 / 84108F88
ok(runtime:hideStatusShape("enemy", 2) == 1 and z[1].nativeStatusHidden, "84108E00 mode 2 hides shape 0x12")
ok(runtime:hideStatusShape("player", 2) == 0, "only the owner's")

ok(runtime:showStatusShape("enemy", 2) == 1 and not z[1].nativeStatusHidden, "84108F88 mode 2 shows it")

-- 84108AF8: kept while asleep, released when not
ok(runtime:releaseStatusEnded("enemy", {asleep = true}) == 0, "84108AF8 keeps shape 0x12 while asleep")
ok(runtime:releaseStatusEnded("enemy", {}) == 1 and not z[1]._motionState.nativeAgeFrozen,
  "and releases it once the status has ended (its age runs again)")
run(260)
ok(#particles(runtime, 0x12) == 0, "a released particle ends at byte age 0xFF")

-- 84108CE8 releases all but shape 0xD3 (the Dig dust, entry 0x12D)
preview:start(0x100, "enemy", false, context); runtime = preview.player.runtime; run(10)
preview.player:playEntry(0x12D, {sourceSide = "enemy", targetSide = "player", condition = 0}); run(30)
ok(#particles(runtime, 0xD3) > 0 and #particles(runtime, 0x12) == 1, "dust and the sleep particle held")
ok(runtime:releaseHeldButDust("enemy") == 1, "84108CE8 releases the sleep particle only")
ok(#particles(runtime, 0xD3) > 0, "the dust stays")
local dust = particles(runtime, 0xD3)
runtime:releaseStatusEnded("enemy", {})
ok(dust[1].active == false and dust[1].nativeDropped, "84108AF8 ends a held 0x8000 particle at once")

-- the camera's side: status bits, 841136E8, 8411EE74, 84120700
local Camera = require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_camera")
local catalog = assert(require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_rom").catalog(rom))
local camera = assert(Camera.new({rom = rom, fragment79 = catalog.lifecycleAssets.fragment79}))
local calls = {}
local status = {player = 0, enemy = 3}
local scene = {actors = {player = {dex = 25, mon = {hp = 20}}, enemy = {dex = 16, mon = {hp = 20}}},
  stadiumRecordStatus = function(_, side) return status[side] end,
  stadiumStatusParticles = function(_, side, op, arg)
    calls[#calls + 1] = {side, op, type(arg) == "table" and arg or tonumber(arg)} end}
camera:sync(scene)
local E = 0x85002000
local m = camera.cam.mem
camera:statusEntry("enemy", 0x100)
ok(bit.band(m:u16(E + 0x7F4), 0x40) ~= 0, "entry 0x100 marks the sleep visual (+0x7F4 bit 0x40)")
calls = {}
camera:statusEnded(E)
ok(#calls == 0, "841136E8: still asleep, nothing released")
status.enemy = 0; camera:sync(scene)
camera:statusEnded(E)
ok(#calls == 1 and calls[1][2] == "releaseStatusEnded" and bit.band(m:u16(E + 0x7F4), 0x40) == 0,
  "awake: the bit cleared and 84108AF8 run")
status.enemy = 0x20; camera:sync(scene); calls = {}
camera.cam:hideActor(E)
ok(#calls == 1 and calls[1][2] == "hideStatusShape" and calls[1][3] == 1, "8411EE74 hides the frozen shape (mode 1)")
calls = {}
camera:statusVisibility(E)
camera:actorReset(E)
ok(calls[1] and calls[1][2] == "showStatusShape" and calls[1][3] == 1, "84120700 shows it again (84108F88)")

-- the records that start a visual: 0x0C (fell asleep, 8411862C) and 0x0E
-- (frozen, 84118138) at the defender's record start
do
  local Scene = require("mods.STADIUM2_IMPORTER.lib.battle_scene")
  local scheduled, actions = {}, {}
  local fx = {defenderStarted = function() end,
    scheduleSignal = function(_, entry, side, ticks) scheduled[#scheduled + 1] = {entry, side, ticks} end,
    scheduleCall = function(_, side, ticks, fn) scheduled[#scheduled + 1] = {"call", side, ticks} end}
  local actor = {fallAsleep = function() actions[#actions + 1] = "asleep" end,
    hit = function() actions[#actions + 1] = "hit" end,
    defenderHitFrame = function() return 12 end}
  local inflicts
  local view = setmetatable({battleFx = fx, actors = {enemy = actor},
    stadiumHitActor = function() return actor end,
    stadiumHitInflicts = function() return inflicts end}, {__index = Scene})
  inflicts = "sleep"
  view:stadiumDefenderStarted("enemy", 79, false)
  ok(actions[1] == "asleep" and scheduled[1][1] == 0x100 and scheduled[1][3] == 12,
    "fell asleep (0x0C): the fall-asleep clip and the Z's at the hit frame")
  inflicts = "freeze"; scheduled, actions = {}, {}
  view:stadiumDefenderStarted("enemy", 58, false)
  ok(actions[1] == "hit" and scheduled[1][1] == 0xFE and scheduled[1][3] == 8 and scheduled[2][3] == 9,
    "frozen (0x0E): the hit clip, the ice at frame 8, the flying / underground check at 9")
  inflicts = nil; scheduled, actions = {}, {}
  view:stadiumDefenderStarted("enemy", 33, false)
  ok(actions[1] == "hit" and #scheduled == 0, "an ordinary hit starts no visual")
  -- the hosts: Gold's queue, Red's status before the action
  local Gen2 = require("mods.STADIUM2_IMPORTER.lib.gen2_battle")
  local g2 = setmetatable({screen = {queue = {{kind = "damage", side = "enemy"},
    {kind = "status", side = "enemy", status = "freeze"}, {kind = "move", side = "enemy"}}}}, {__index = Gen2.Scene})
  ok(g2:stadiumHitInflicts("enemy") == "freeze" and g2:stadiumHitInflicts("player") == nil,
    "Gold: the target's status event before the next move")
  g2.screen.queue = {{kind = "damage"}, {kind = "move"}, {kind = "status", side = "enemy", status = "sleep"}}
  ok(g2:stadiumHitInflicts("enemy") == nil, "not one after the next move")
  local Gen1 = require("mods.STADIUM2_IMPORTER.lib.gen1_battle")
  local b = {mon = {status = "SLP"}}
  local g1 = setmetatable({stadiumStatusBefore = {enemy = nil},
    shownBattler = function() return b end}, {__index = Gen1.Scene})
  ok(g1:stadiumHitInflicts("enemy") == "sleep", "Red: asleep now, not before the action")
  g1.stadiumStatusBefore = {enemy = "SLP"}
  ok(g1:stadiumHitInflicts("enemy") == nil, "already asleep: nothing new")
end

-- the send-out of an asleep Pokemon (8411BCC8 substate 5)
do
  local signals = {}
  scene.battleFx = {signalEffect = function(_, entry, side) signals[#signals + 1] = {entry, side} end}
  status.enemy = 2; camera:sync(scene)
  camera.openingPhase = nil
  camera:sendOut(scene, "enemy")
  local ticks = 0
  while camera.sendingOut and ticks < 200 do camera:update(scene, 1/30); ticks = ticks + 1 end
  -- count the camera's own ticks (one update may run several)
  local firedAt, sleepSignal
  for tick = 1, 20 do
    camera.accumulator = 0
    camera:update(scene, Camera.TICK)
    for _, sig in ipairs(signals) do
      if sig[1] == 0x100 and not firedAt then firedAt, sleepSignal = tick, sig end
    end
  end
  ok(firedAt == 7 and sleepSignal[2] == "enemy",
    "the Z's at counter 6: the 7th tick after the camera part (counter 0 on the 1st)")
end

-- the held-particle releases at their states (84108A10)
do
  calls = {}
  camera:faint(scene, "enemy")
  ok(calls[1] and calls[1][1] == "enemy" and calls[1][2] == "releaseHeld", "a faint releases the held particles")
  calls = {}
  camera:recall(scene, "enemy", {asleep = true})
  ok(calls[1] and calls[1][2] == "releaseHeld", "the recall of an asleep Pokemon releases them")
  calls = {}
  camera:recall(scene, "enemy", {})
  ok(#calls == 0, "an ordinary recall does not")
  calls = {}
  camera:battleEnd(scene, "win")
  ok(calls[1] and calls[1][1] == "player" and calls[1][2] == "releaseHeld", "the winner's at the victory")
  local Scene = require("mods.STADIUM2_IMPORTER.lib.battle_scene")
  local ops, scheduled = {}, {}
  local fx = {defenderStarted = function() end,
    scheduleSignal = function() end,
    scheduleCall = function(_, side, ticks, fn) scheduled[#scheduled + 1] = {side, ticks, fn} end}
  local actor = {hit = function() end, defenderHitFrame = function() return 9 end}
  local inflicts
  local view = setmetatable({battleFx = fx, actors = {enemy = actor},
    stadiumHitActor = function() return actor end,
    stadiumHitInflicts = function() return inflicts end,
    stadiumStatusParticles = function(_, side, op) ops[#ops + 1] = {side, op} end}, {__index = Scene})
  view:stadiumDefenderStarted("enemy", 0x12, false)
  ok(ops[1] and ops[1][2] == "releaseHeld", "Whirlwind's target releases them as its record starts")
  ops = {}
  view:stadiumDefenderStarted("enemy", 0x12, true)
  ok(#ops == 0, "not on a dodge")
  inflicts = "thaw"
  view:stadiumDefenderStarted("enemy", 52, false)
  ok(scheduled[1] and scheduled[1][2] == 9, "a thawing hit (0x0F) releases them at its hit frame")
  scheduled[1][3]()
  ok(ops[1] and ops[1][2] == "releaseHeld", "(84108A10 at 8411854C's hit frame)")
  local Gen1 = require("mods.STADIUM2_IMPORTER.lib.gen1_battle")
  local b = {mon = {status = nil}}
  local g1 = setmetatable({stadiumStatusBefore = {enemy = "FRZ"},
    shownBattler = function() return b end}, {__index = Gen1.Scene})
  ok(g1:stadiumHitInflicts("enemy") == "thaw", "Red: \"Fire defrosted\" is the thaw")
end

print(("stadium2_status_particles_test: %d checks passed"):format(checks))
