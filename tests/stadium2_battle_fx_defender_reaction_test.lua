-- Defender hit clip (context 254) at the impact: the adapter's onImpact hook
-- and Actor:hit. Needs no ROM. Run from the Gen1Recomp repository root.
package.path = "./?.lua;./?/init.lua;" .. package.path
local prefix = "mods.STADIUM2_IMPORTER.lib."
local Adapter = require(prefix .. "stadium2_battle_fx_battle_adapter")
local Actor = require(prefix .. "battle_actor")

local checks = 0
local function ok(value, message)
  assert(value, message)
  checks = checks + 1
end

-- Stub player: records triggers; no ROM catalog needed.
local triggered = {}
local player = {runtime = {frame = 0, effects = {}},
  trigger = function(_, context) triggered[#triggered + 1] = context; return #triggered end,
  abortAll = function() end}
local warnings = {}
local adapter = assert(Adapter.new({
  betaBattleFxEnabled = function() return true end,
  newBattleFxPlayer = function() return player end,
}, {warn = function(message) warnings[#warnings + 1] = message end}))

local reactions = {}
adapter.onImpact = function(target, source, moveId)
  reactions[#reactions + 1] = {target = target, source = source, moveId = moveId}
  return true
end

ok(adapter:impact(1, "player") == "impact", "ordinary result plays the impact")
ok(#reactions == 1 and reactions[1].target == "enemy" and reactions[1].source == "player"
  and reactions[1].moveId == 1, "the defender (opposite side) reacts to a player move")
adapter:impact(1, "enemy")
ok(reactions[2].target == "player", "the player reacts to an enemy move")
local timing = false
for _, message in ipairs(warnings) do
  if message:find("starts with the impact", 1, true) then timing = true end
end
ok(timing, "the approximate reaction timing is reported")

ok(adapter:impact(1, "player", 6) == "none" and #reactions == 2,
  "result 6 (no hit-frame call) plays no reaction")
ok(adapter:impact(33, "player", 1) == "fail" and #reactions == 2,
  "the result-1 failure path plays no reaction")
ok(adapter:impact(0x39, "player", 1) == "owner" and #reactions == 2,
  "Surf's owner-only path dispatches nothing new and plays no reaction")

adapter.onImpact = function() return false, "species 999 has no hit clip" end
adapter:impact(1, "player")
local unresolved = false
for _, message in ipairs(warnings) do
  if message:find("species 999 has no hit clip", 1, true) then unresolved = true end
end
ok(unresolved, "a missing hit clip is reported, not replaced")
adapter.onImpact = function() error("boom") end
ok(adapter:impact(1, "player") == "impact", "a failing host hook does not stop the impact")

-- Actor:hit plays only the species hit clip.
local calls = {}
local function rig(hasHit)
  return {finished = true, setContext = function(_, name, loop)
    calls[#calls + 1] = {name, loop}
    return name ~= "hit" or hasHit
  end}
end
local actor = Actor.new and Actor.new() or setmetatable({context = "idle"}, {__index = Actor})
actor.renderer, actor.dex, actor.context = rig(true), 25, "idle"
ok(actor:hit() == true and actor.context == "hit", "Actor:hit plays context 'hit'")
ok(calls[#calls][1] == "hit" and calls[#calls][2] == false, "the hit clip is not looped")
ok(actor.renderer.finished == false, "the clip restarts")
actor.context = "faint"
ok(actor:hit() == false, "a fainting actor does not react")
actor.renderer, actor.context = rig(false), "idle"
local played, reason = actor:hit()
ok(played == false and reason:find("no hit clip", 1, true) and actor.context == "idle",
  "a species without a hit clip stays as it is (no fallback clip)")

-- battle.damage_dealt facts -> result byte (Gen 1 and Gen 2 payload shapes).
Adapter.clearHits()
ok(Adapter.recordHit({user = {isPlayer = true}, move = {index = 33}, crit = true, typeMult = 10}),
  "Gen 1 payload is recorded for the attacker")
Adapter.recordHit({user = {isPlayer = true}, move = {index = 33}, crit = false, typeMult = 10})
ok(Adapter.takeHitResult("player", 33) == 4, "the first hit of the move sets the byte (critical)")
ok(Adapter.takeHitResult("player", 33) == nil, "facts are consumed once")
Adapter.recordHit({side = "player", moveId = 55, crit = false, effectiveness = 20})
ok(Adapter.takeHitResult("enemy", 55) == 3, "Gen 2 names the defender; the enemy attacked")
Adapter.recordHit({side = "enemy", moveId = 10, effectiveness = 10})
Adapter.recordHit({side = "enemy", moveId = 20, effectiveness = 5})
ok(Adapter.takeHitResult("player", 20) == 5, "Bind is 5 and a stale older move is dropped")
ok(Adapter.takeHitResult("player", 10) == nil, "the dropped entry is gone")
ok(Adapter.recordHit({side = "enemy"}) == false, "payloads without a move are ignored")
for i = 1, 20 do Adapter.recordHit({side = "enemy", moveId = i, effectiveness = 10}) end
ok(Adapter.takeHitResult("player", 15) == 0 and Adapter.takeHitResult("player", 1) == nil,
  "unpresented entries are capped")
Adapter.clearHits()

-- playMoveAndImpact consumes the facts for the attacker.
local scheduled
adapter.playMove = function() return 1 end
adapter.scheduleImpact = function(_, moveId, source, ticks, result) scheduled = result end
Adapter.recordHit({user = {isPlayer = false}, move = {number = 1}, crit = false, typeMult = 20})
adapter:playMoveAndImpact(1, "enemy", nil)
ok(scheduled == 3, "the impact is scheduled with the built result byte")
adapter:playMoveAndImpact(1, "enemy", nil)
ok(scheduled == nil, "without facts the impact keeps the ordinary (nil) result")

print(("%d checks passed (battle FX defender reaction)"):format(checks))
