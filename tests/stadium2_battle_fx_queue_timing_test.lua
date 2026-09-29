package.path="./?.lua;./?/init.lua;"..package.path
-- Delayed battle FX work (timing audit T01/T02,
-- docs/luna/research/timing-lifetimes-2026-09-28.md):
--   T01  work is serviced after every FX tick (Runtime.afterTick), so it
--        fires on its own tick in chronological order however many ticks
--        one presentation update advances;
--   T02  a newer move drops an older move's queued work, and a replaced
--        model drops work aimed at or owned by it.
local checks=0
local function ok(v,m) checks=checks+1 if not v then error("FAIL "..m,0) end end
local Runtime=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_runtime")
local Adapter=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_battle_adapter")

-- the real runtime calls afterTick once per tick, in order
local runtime=Runtime.new({catalog={programs={},moves={}}})
local ticks={}
runtime.afterTick=function(frame) ticks[#ticks+1]=frame end
runtime:update(3/30)
ok(#ticks==3 and ticks[1]==1 and ticks[2]==2 and ticks[3]==3,"Runtime.afterTick runs after each of three batched ticks")

-- a recording player over the real Runtime
local function fixture()
  local p={runtime=Runtime.new({catalog={programs={},moves={}}}),events={},n=0}
  function p:update(dt) return self.runtime:update(dt) end
  function p:trigger(ctx)
    self.n=self.n+1
    self.events[#self.events+1]={at=self.runtime.frame,move=ctx.moveId,
      kind=ctx.alternate and "impact" or ctx.variant and "variant" or "route"}
    return self.n
  end
  function p:finish() return true end
  function p:setRouteSignal(v) self.signal=v end
  function p:playEntry(id,ctx) ctx.moveId=id;return self:trigger(ctx) end
  function p:signalContext() end
  function p:resetModel() return true end
  local a=assert(Adapter.new({betaBattleFxEnabled=function() return true end,
    newBattleFxPlayer=function() return p end}))
  return a,p
end
local function log(p)
  local out={}
  for _,e in ipairs(p.events) do out[#out+1]=("%s:%d@%d"):format(e.kind,e.move,e.at) end
  return table.concat(out," ")
end

-- T01: route due at tick 2, impact at tick 1
local function batch(sizes)
  local a,p=fixture()
  a:scheduleRoute(55,"player",2);a:scheduleImpact(55,"player",1,0,true)
  for _,n in ipairs(sizes) do a:update(n/30) end
  return p
end
local single,batched=batch({1,1,1}),batch({3})
ok(log(single)=="impact:55@1 route:55@2","one tick per update: impact@1, route@2 ("..log(single)..")")
ok(log(batched)==log(single),"three ticks in one update: the same order and ticks ("..log(batched)..")")
ok(single.signal==batched.signal,"and the same final route signal")

-- T02: a newer move drops the older move's queued impact
do
  local a,p=fixture()
  local model={renderer={model={fxDispatch=string.rep("\0",33*20)}}}
  a:playMoveAndImpact(55,"player",model,0)
  a:scheduleImpact(55,"player",10,0,true)
  a:update(1/30)
  a:playMoveAndImpact(33,"enemy",model,0)
  for _=1,12 do a:update(1/30) end
  local stale=false
  for _,e in ipairs(p.events) do if e.move==55 and e.kind=="impact" then stale=true end end
  ok(not stale,"a newer move drops the older move's queued impact ("..log(p)..")")
end

-- T02: a replaced target model drops the impact aimed at it
do
  local a,p=fixture()
  a:playMove(55,"player");a:scheduleImpact(55,"player",8,0,true)
  a:modelChanged("enemy")
  for _=1,9 do a:update(1/30) end
  ok(log(p)=="route:55@0","the impact aimed at a replaced model is dropped ("..log(p)..")")
end

-- T02: an owner's replaced model drops its queued event effects; the other
-- side's are kept
do
  local a,p=fixture()
  a:scheduleSignal(0x101,"enemy",3);a:scheduleSignal(0x102,"player",3)
  a:modelChanged("enemy")
  for _=1,4 do a:update(1/30) end
  ok(log(p)=="route:258@3","only the unaffected owner's event plays ("..log(p)..")")
end

-- T02: a replaced attacker drops its pending route
do
  local a,p=fixture()
  a:scheduleRoute(55,"player",4)
  a:modelChanged("player")
  for _=1,5 do a:update(1/30) end
  ok(log(p)=="","the pending route of a replaced attacker is dropped ("..log(p)..")")
end

-- work for the current move and model still plays
do
  local a,p=fixture()
  a:scheduleImpact(55,"player",2,0,true)
  a:modelChanged("player") -- the attacker's change does not affect the target
  for _=1,3 do a:update(1/30) end
  ok(log(p)=="impact:55@2","an impact whose target is unchanged still plays ("..log(p)..")")
end

print(checks.." checks passed (battle FX queued work timing)")
