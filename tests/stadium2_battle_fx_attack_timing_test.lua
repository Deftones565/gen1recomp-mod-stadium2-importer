-- Attack-state timeline (84114A04/84114BF4 attacker, 841170A0/8411845C
-- defender): Sequence.attackTiming and the adapter's schedule. No ROM.
-- Run from the Gen1Recomp repository root.
package.path = "./?.lua;./?/init.lua;" .. package.path
local prefix = "mods.STADIUM2_IMPORTER.lib."
local Sequence = require(prefix .. "stadium2_battle_fx_sequence")
local Adapter = require(prefix .. "stadium2_battle_fx_battle_adapter")
local Actor = require(prefix .. "battle_actor")

local checks = 0
local function ok(value, message)
  checks = checks + 1
  if not value then error("FAIL " .. message, 0) end
end

-- 271 zeroed rows; row(move) sets bytes 6 (start), 7 (defender hit),
-- 0x0A (second frame) and 0x0B (hit).
local function dispatch(rows)
  local out = {}
  for r = 0, 270 do
    local b = {}
    for i = 1, 20 do b[i] = 0 end
    local spec = rows[r + 1]
    if spec then
      b[7], b[8], b[11], b[12] = spec.start or 0, spec.def or 0, spec.second or 0, (spec.hit or 0) % 256
    end
    out[#out + 1] = string.char(unpack(b))
  end
  return table.concat(out)
end

-- Ordinary move 33: start 4, hit 20, second 60 (60-4-30 >= 20-4): released
-- at the hit frame; defender hit byte 7 = 5.
local atk = dispatch({[33] = {start = 4, hit = 20, second = 60}})
local def = dispatch({[33] = {def = 5}})
local t = assert(Sequence.attackTiming(atk, 33, {defenderDispatch = def}))
ok(t.clipStart == 4 and t.preRoll == 0, "clip starts at byte 6, no pre-roll")
ok(t.route == 16, "move route at hit - start (84114BF4 rebases +0x619)")
ok(t.release == 16, "defender released at the hit frame")
ok(t.impact == 21, "impact at release + defender byte 7")

-- Second frame close to the hit: released at counter 0.
t = Sequence.attackTiming(dispatch({[33] = {start = 0, hit = 20, second = 30}}), 33,
  {defenderDispatch = def})
ok(t.release == 0 and t.impact == 5, "second - 30 < hit releases at counter 0")

-- Negative hit frame: counter starts at the hit, idle pre-roll, route at 0.
t = Sequence.attackTiming(dispatch({[33] = {start = 0, hit = -6, second = 0}}), 33)
ok(t.preRoll == 6 and t.route == 0, "negative hit: idle pre-roll, route on the first frame")

-- Hit before the clip start is never reached: reported.
t = Sequence.attackTiming(dispatch({[33] = {start = 10, hit = -2}}), 33)
ok(t.route == nil and t.diagnostics[1].code == "unreached-attack-hit-frame",
  "an unreachable hit frame is reported")

-- Explosion (153): released at hit or hit + 30 by the second frame.
local ex = dispatch({[153] = {start = 0, hit = 10, second = 20}})
ok(Sequence.attackTiming(ex, 153).release == 10, "Explosion: second < hit+30 releases at hit")
ex = dispatch({[153] = {start = 0, hit = 10, second = 50}})
ok(Sequence.attackTiming(ex, 153).release == 40, "Explosion: otherwise at hit + 30")

-- Species that play only the sound; Foresight's defender hit is 0.
local wd = dispatch({[110] = {hit = 8}})
ok(Sequence.attackTiming(wd, 110, {species = 8}).soundOnly, "Wartortle's Withdraw plays only the sound")
ok(not Sequence.attackTiming(wd, 110, {species = 1}).soundOnly, "other species play the route")
local fs = dispatch({[193] = {hit = 8, second = 100}})
ok(Sequence.attackTiming(fs, 193, {defenderDispatch = dispatch({[193] = {def = 9}})}).impact == 8,
  "Foresight's defender hit frame is 0 (84117744)")
ok(Sequence.attackTiming(dispatch({[185] = {start = 0, hit = 12}}), 185).special == 0,
  "Feint Attack starts its routine at counter 0")

-- Adapter: route and impact scheduled on the runtime clock.
local triggered, impacts = {}, {}
local player = {runtime = {frame = 0, effects = {}},
  trigger = function(_, context) triggered[#triggered + 1] = context; return #triggered end,
  playEntry = function() return 1 end, update = function() return 0 end,
  finish = function() return true end, abortAll = function() end}
local adapter = assert(Adapter.new({
  betaBattleFxEnabled = function() return true end,
  newBattleFxPlayer = function() return player end,
}, {warn = function() end}))
local realImpact = adapter.impact
adapter.impact = function(self, moveId, source) impacts[#impacts + 1] = player.runtime.frame end
local attacker = {dex = 1, renderer = {model = {fxDispatch = atk}}}
local defender = {dex = 4, renderer = {model = {fxDispatch = def}}}
adapter:playMoveAndImpact(33, "player", attacker, 0, defender)
ok(#triggered == 0, "the move route waits for the hit frame")
local function stepTo(frame)
  while player.runtime.frame < frame do
    player.runtime.frame = player.runtime.frame + 1
    adapter:update(1 / 30)
  end
end
adapter:finish() -- host animation ended after 0 frames
stepTo(16)
ok(#triggered == 1 and triggered[1].moveId == 33, "route starts at tick 16")
stepTo(21)
ok(#impacts == 1 and impacts[1] == 21, "impact at tick 21")
adapter.impact = realImpact

-- Actor: clip seeks byte 6; a negative hit holds idle first.
local seeks, moves = {}, {}
local contexts = {}
local rig = {model = {fxDispatch = dispatch({[33] = {start = 4, hit = 20},
    [34] = {start = 2, hit = -3}})},
  setMove = function(_, m) moves[#moves + 1] = m; return true end,
  setContext = function(_, name) contexts[#contexts + 1] = name; return true end,
  seekFrame = function(_, f) seeks[#seeks + 1] = f end}
local a = Actor.new("player")
a.renderer = rig
a:attack(33)
ok(seeks[1] == 4, "attack clip starts at byte 6")
a.context = "idle"
a:attack(34)
ok(a.pendingClip and a.pendingClip.ticks == 3 and contexts[#contexts] == "idle",
  "negative hit waits in idle")
a:stepPendingClip(2 / 30)
ok(a.pendingClip ~= nil, "still waiting after 2 of 3 ticks")
a:stepPendingClip(1 / 30)
ok(a.pendingClip == nil and moves[#moves] == 34 and seeks[#seeks] == 2,
  "then the clip starts at byte 6")

print(("stadium2_battle_fx_attack_timing_test: %d checks passed"):format(checks))
