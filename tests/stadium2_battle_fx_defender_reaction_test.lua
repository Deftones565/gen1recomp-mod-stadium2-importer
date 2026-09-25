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
Adapter.recordHit({side = "enemy", moveId = 12, move = {effect = "EFFECT_OHKO"}, effectiveness = 10})
ok(Adapter.takeHitResult("player", 12) == 4, "a landed OHKO is 4")
Adapter.recordHit({user = {isPlayer = true}, move = {index = 32, effect = "OHKO_EFFECT"}, typeMult = 10})
ok(Adapter.takeHitResult("player", 32) == 4, "Gen 1 OHKO_EFFECT is 4")
Adapter.recordHit({side = "enemy", moveId = 205, move = {effect = "EFFECT_ROLLOUT"}, crit = true, effectiveness = 20})
ok(Adapter.takeHitResult("player", 205) == 5, "Rollout (effect 0x75) is 5")
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

-- Scheduled signals and faint timing.
local signalled = {}
adapter.signalEffect = function(_, id, owner) signalled[#signalled + 1] = {id = id, owner = owner} end
player.runtime.frame = 100
adapter:scheduleSignal(0x122, "enemy", 3)
adapter:_firePendingSignals()
ok(#signalled == 0, "a scheduled signal waits for its frame")
player.runtime.frame = 103
adapter:_firePendingSignals()
ok(#signalled == 1 and signalled[1].id == 0x122 and signalled[1].owner == "enemy",
  "the signal fires at its frame for its owner")
local Dispatch = require(prefix .. "animation_dispatch")
local row = {}
for i = 1, 271 * 20 do row[i] = "\0" end
row[253 * 20 + 0x0B + 1] = string.char(12)
row[253 * 20 + 0x0A + 1] = string.char(30)
local faintActor = {renderer = {model = {fxDispatch = table.concat(row)}}}
local oldMarker = Dispatch.contextMarker
Dispatch.contextMarker = function() return 0x0B end
signalled = {}
player.runtime.frame = 0
ok(adapter:playFaint("player", faintActor), "faint effects are scheduled")
player.runtime.frame = 12; adapter:_firePendingSignals()
player.runtime.frame = 30; adapter:_firePendingSignals()
ok(#signalled == 2 and signalled[1].id == 0x119 and signalled[2].id == 0x11A,
  "0x119 at the row's 0x0B frame, 0x11A at its 0x0A frame")
Dispatch.contextMarker = function() return 0xFF end
signalled = {}
adapter:playFaint("player", faintActor)
player.runtime.frame = 60; adapter:_firePendingSignals()
ok(#signalled == 1 and signalled[1].id == 0x11A, "a 0xFF marker skips 0x119 (8411E244)")
Dispatch.contextMarker = oldMarker
ok(adapter:playFaint("player", {}) == false, "no dispatch rows: faint effects are reported, not guessed")

-- Charge turn: the variant route fires at the charge row's byte 0x0B.
local variants = {}
adapter.playVariant = function(_, moveId, source) variants[#variants + 1] = {moveId, source} end
local chargeRows = {}
for i = 1, 271 * 20 do chargeRows[i] = "\0" end
chargeRows[256 * 20 + 0x0B + 1] = string.char(9)
player.runtime.frame = 200
ok(adapter:playCharge(19, "enemy", {renderer = {model = {fxDispatch = table.concat(chargeRows)}}}),
  "Fly's charge turn is scheduled")
player.runtime.frame = 208; adapter:_firePendingVariants()
ok(#variants == 0, "not before the charge row's frame")
player.runtime.frame = 209; adapter:_firePendingVariants()
ok(#variants == 1 and variants[1][1] == 19 and variants[1][2] == "enemy", "variant route at byte 0x0B")
ok(adapter:playCharge(33, "enemy", {}) == nil, "ordinary moves have no charge turn")

-- Rest (841153DC): entry 0x100 on the user at Rest's hit frame.
local restRows = {}
for i = 1, 271 * 20 do restRows[i] = "\0" end
restRows[155 * 20 + 0x0B + 1] = string.char(7)
signalled = {}
adapter.playMove = function() return 1 end
adapter.scheduleImpact = function() return true end
player.runtime.frame = 300
adapter:playMoveAndImpact(156, "player", {renderer = {model = {fxDispatch = table.concat(restRows)}}})
player.runtime.frame = 307; adapter:_firePendingSignals()
ok(#signalled == 1 and signalled[1].id == 0x100 and signalled[1].owner == "player", "Rest signals 0x100 at its hit frame")

print(("%d checks passed (battle FX defender reaction)"):format(checks))
