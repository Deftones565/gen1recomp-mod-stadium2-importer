package.path="./?.lua;./?/init.lua;"..package.path
-- Timing audit T04 (docs/luna/research/timing-lifetimes-2026-09-28.md):
-- finished effects are retired so per-tick work and snapshots stay bounded
-- by what is alive; an effect is kept while it has a live particle, a birth
-- still to come, an active lifecycle instance or an active native object.
local checks=0
local function ok(v,m) checks=checks+1 if not v then error("FAIL "..m,0) end end
local Runtime=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_runtime")

-- one emitter: `count` particles born at `start`, repeated
local function program(start,interval,repeats)
  return {start=start,interval=interval,repeats=repeats,mode=0,flags=0,
    programId=1,address=0x8417B624}
end
local lifetime=3
local native={
  execute=function(p) return {scheduled={p.event},diagnostics={}} end,
  particles=function(execution,previous,frame)
    local out={}
    local e=execution.scheduled[1]
    local n=e.repeats==0xFF and math.huge or e.repeats
    for i=0,math.min(n-1,1000) do
      local born=e.start+e.interval*i
      if born>previous and born<=frame then
        out[#out+1]={schedulerIndex=1,generation=i,particleIndex=1,born=born,
          position={0,0,0},velocity={0,0,0},event=e}
      end
      if e.interval==0 then break end
    end
    return out
  end,
}
local motion={
  init=function(s) return {age=0,lifetime=lifetime,alive=true,position=s.position,
    velocity={0,0,0},rotation={0,0,0},scale={1,1,1}} end,
  step=function(s,d) return {age=s.age+d,lifetime=s.lifetime,alive=s.age+d<s.lifetime,
    position=s.position,velocity=s.velocity,rotation=s.rotation,scale=s.scale} end,
}
local function runtime(events,options)
  local programs,moves={},{}
  for id,event in pairs(events) do
    programs[id]={id=id,event=event}
    moves[id]={dispatch={{kind="program",programId=id}}}
  end
  moves[99]={dispatch={}}
  options=options or {}
  options.catalog={programs=programs,moves=moves}
  options.native=native;options.motion=motion
  options.router={resolve=function(move) return move.dispatch end}
  return Runtime.new(options)
end

-- an empty route retires on the next tick
local r=runtime({})
for _=1,1000 do assert(r:trigger({moveId=99})) end
r:step(1)
ok(#r.effectOrder==0 and next(r.effects)==nil,"1000 empty routes are retired after one tick")
ok(#r:snapshot().effects==0,"and leave the snapshot")

-- live particles and later births keep an effect
r=runtime({[1]=program(0,0,1),[2]=program(6,0,1)})
local now=assert(r:trigger({moveId=1}))
local later=assert(r:trigger({moveId=2}))
r:step(1)
ok(r.effects[now] and r.effects[later],"a live particle and a birth at tick 6 keep both effects")
r:step(3)
ok(r.effects[now]==nil,"the effect retires once its last particle ends")
ok(r.effects[later]~=nil,"the effect with a birth still to come is kept")
r:step(2)
ok(r.effects[later] and #r:snapshot().particles==1,"its tick-6 particle is born and drawn")
r:step(3)
ok(r.effects[later]==nil and #r.effectOrder==0,"then it retires too")

-- an endless emitter (repeats 0xFF) stays until cancelled, and its finished
-- particle rows are dropped
r=runtime({[1]=program(0,1,0xFF)})
local endless=assert(r:trigger({moveId=1}))
r:step(60)
ok(r.effects[endless]~=nil,"an endless emitter is kept")
ok(#r.effects[endless].particles<=lifetime+1,"finished particle rows are pruned ("..#r.effects[endless].particles..")")
r:abortAll()
r:step(lifetime+1)
ok(r.effects[endless]==nil,"a cancelled endless emitter retires once its particles end")

-- an active lifecycle instance keeps its effect; retiring releases it
local instances,released={}, {}
local lifecycle={instances=instances,finishedEffects={},
  spawn=function(self,_,ctx) local id=#released+100;instances[id]={active=true};released[#released+1]=false;return id end,
  release=function(self,id) instances[id]=nil;released[#released+1]=id end,
  step=function() end,snapshot=function() return {instances={}} end}
r=Runtime.new({catalog={programs={},moves={[5]={dispatch={{kind="lifecycle",lifecycleId=23}}}},lifecycle={}},
  router={resolve=function(move) return move.dispatch end},lifecycle=lifecycle,native=native,motion=motion})
local ribbon=assert(r:trigger({moveId=5}))
r:step(5)
ok(r.effects[ribbon]~=nil,"an active lifecycle instance keeps its effect")
instances[100].active=false
lifecycle.finishedEffects[ribbon]=true
r:step(1)
ok(r.effects[ribbon]==nil and instances[100]==nil,"then the effect retires and releases the instance")
ok(lifecycle.finishedEffects[ribbon]==nil,"and forgets its finish signal")

print(checks.." checks passed (battle FX effect retirement)")
