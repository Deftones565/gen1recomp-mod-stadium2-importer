package.path="./?.lua;./?/init.lua;"..package.path
-- The move's battle record (D_84193DD0) as the FX dispatcher reads it:
-- result flags (Thief 0x20, Present 0x40, Curse 0x80; fragment79_393CA0
-- handlers 8412DC20/8412EC70/8412DE98) and the user's status byte reach
-- this move's route and impact, and nothing else.
local checks=0
local function ok(v,m) checks=checks+1 if not v then error("FAIL "..m,0) end end
local Runtime=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_runtime")
local Adapter=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_battle_adapter")
local Sequence=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_sequence")
local State=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_battle_state")

local function fixture()
  local p={runtime=Runtime.new({catalog={programs={},moves={}}}),events={},n=0}
  function p:update(dt) return self.runtime:update(dt) end
  function p:trigger(ctx)
    self.n=self.n+1
    self.events[#self.events+1]={move=ctx.moveId,impact=ctx.alternate==true,
      state=Adapter.battleState(ctx,{})}
    return self.n
  end
  function p:finish() return true end
  function p:setRouteSignal() end
  function p:playEntry(id,ctx) ctx.moveId=id;return self:trigger(ctx) end
  function p:signalContext() end
  function p:resetModel() return true end
  local a=assert(Adapter.new({betaBattleFxEnabled=function() return true end,
    newBattleFxPlayer=function() return p end}))
  return a,p
end
-- Zeroed dispatch rows: route and impact at tick 0.
local actor={renderer={model={fxDispatch=string.rep("\0",260*20)}}}
local function run(a,n) for _=1,n or 3 do a:update(1/30) end end

-- Snore: a damaging hit (low bits 0) by a sleeping user -> condition 2
Adapter.clearHits()
Adapter.recordHit({side="enemy",moveId=173,effectiveness=10})
local a,p=fixture()
a:playMoveAndImpact(173,"player",actor,nil,actor,{sourceStatus=3})
a:defenderStarted("enemy") -- the host's hit: the defender's hit state starts
run(a)
ok(#p.events==2,"Snore plays its route and impact ("..#p.events..")")
for _,e in ipairs(p.events) do
  ok(e.state.resultFlags==0 and e.state.sourceStatus==3,"both carry the move's record")
  ok(State.condition(173,e.state,9)==2,"asleep and not missed: Snore's branch 2")
end

-- Thief: the hit's record without 0x20 (Gold never steals) -> branch 0
Adapter.recordHit({side="enemy",moveId=168,effectiveness=10})
a,p=fixture()
a:playMoveAndImpact(168,"player",actor,nil,actor,{})
run(a)
ok(State.condition(168,p.events[1].state,9)==0,"Thief without a steal takes branch 0")
a,p=fixture()
a:playMoveAndImpact(168,"player",actor,0,actor,{resultBits=Sequence.RESULT_THIEF_STOLE})
run(a)
ok(State.condition(168,p.events[1].state,9)==1,"a reported steal (0x20) takes branch 1")

-- Curse: the route needs 0x80 (84114BF4); the impact plays either way
a,p=fixture()
a:playMoveAndImpact(174,"player",actor,nil,actor,{})
a:defenderStarted("enemy") -- (in battle: the fallback, with no host hit)
run(a)
ok(#p.events==1 and p.events[1].impact,"the stat Curse plays no route, only the impact")
a,p=fixture()
a:playMoveAndImpact(174,"player",actor,nil,actor,{resultBits=Sequence.RESULT_CURSE_GHOST})
a:defenderStarted("enemy")
run(a)
ok(#p.events==2 and not p.events[1].impact and p.events[1].state.resultFlags==0x80,
  "a Ghost Curse (0x80) plays its route")

-- no facts, no hit: the record stays unknown (diagnosed, as before)
a,p=fixture()
a:playMoveAndImpact(173,"player",actor,nil,actor)
run(a)
ok(p.events[1].state.resultFlags==nil and p.events[1].state.sourceStatus==nil,
  "without facts nothing is invented")
ok(State.condition(173,p.events[1].state,9)==nil,"and Snore stays unresolved")

-- another move, or an event effect, does not see the record
a,p=fixture()
a:playMoveAndImpact(173,"player",actor,0,actor,{sourceStatus=2})
run(a)
a:signalEffect(0x122,"player")
local signal=p.events[#p.events]
ok(signal.state.sourceStatus==nil,"an event effect does not inherit the move's record")
a:playMove(33,"enemy")
ok(p.events[#p.events].state.resultFlags==nil,"nor does another move")

print(checks.." checks passed (battle FX move record)")
