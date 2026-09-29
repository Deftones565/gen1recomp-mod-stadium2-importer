-- Read-only timing audit. Run with luajit from /opt/git/gen1recomp.
-- Reports observations, not passing parity assertions; scheduler rows below
-- are controlled fixtures. The retention and lifetime checks use the US ROM.
package.path='./?.lua;./?/init.lua;'..package.path
local P='mods.STADIUM2_IMPORTER.lib.'
local Adapter=require(P..'stadium2_battle_fx_battle_adapter')
local function fixture()
  local p={runtime={frame=0,accumulator=0},events={},n=0}
  function p:update(dt)
    local r=self.runtime;r.accumulator=r.accumulator+dt*30
    local n=math.floor(r.accumulator+1e-9);r.accumulator=r.accumulator-n;r.frame=r.frame+n
    return r.frame
  end
  function p:trigger(ctx)
    self.n=self.n+1
    self.events[#self.events+1]={at=self.runtime.frame,move=ctx.moveId,kind=ctx.alternate and 'impact' or ctx.variant and 'variant' or 'route'}
    return self.n
  end
  function p:finish(id) self.events[#self.events+1]={at=self.runtime.frame,move=id,kind='finish'};return true end
  function p:setRouteSignal(v) self.signal=v end
  function p:playEntry(id,ctx) ctx.moveId=id;return self:trigger(ctx) end
  function p:signalContext() end
  function p:resetModel() return true end
  local a=assert(Adapter.new({betaBattleFxEnabled=function()return true end,newBattleFxPlayer=function()return p end}))
  return a,p
end
local function report(label,p)
  io.write(label)
  for _,e in ipairs(p.events)do io.write((' %s:%d@%d'):format(e.kind,e.move,e.at))end
  print(' signal='..tostring(p.signal))
end
local function batch(sizes)
  local a,p=fixture();a:scheduleRoute(55,'player',2);a:scheduleImpact(55,'player',1,0,true)
  for _,n in ipairs(sizes)do a:update(n/30)end
  return p
end
report('single-step',batch({1,1,1}))
report('three-tick batch',batch({3}))
do
  local a,p=fixture();a:scheduleRoute(55,'player',8);a:scheduleImpact(55,'player',10,0,true)
  a:update(1/30);a:playMoveAndImpact(33,'enemy',{renderer={model={fxDispatch=string.rep('\0',33*20)}}},0)
  for _=1,12 do a:update(1/30)end
  report('superseded move',p)
end
do
  local a,p=fixture();a:playMove(55,'player');a:scheduleImpact(55,'player',8,0,true)
  a:modelChanged('enemy');for _=1,9 do a:update(1/30)end
  report('model replaced before impact',p)
end
local f=assert(io.open('mods/STADIUM2_IMPORTER/baseroms/stadium2.z64','rb'));local rom=f:read('*a');f:close()
local FxRom=require(P..'stadium2_battle_fx_rom')
local Player=require(P..'stadium2_battle_fx_player')
local catalog=assert(FxRom.catalog(rom))
local player=assert(Player.new({catalog=catalog}))
for _=1,1000 do assert(player:trigger({moveId=1,sourceSide='player',targetSide='enemy'})) end
player:update(12)
local snap=player:snapshot()
print(('1000 empty Pound primary routes + 360 ticks: effects=%d particles=%d'):format(#snap.effects,#snap.particles))
player:release()
local Dispatch=require(P..'animation_dispatch');local Seq=require(P..'stadium2_battle_fx_sequence')
local function rows(species)
  local r=assert(Dispatch.forSpecies(rom,species));local t={}
  for i=0,r.n-1 do t[#t+1]=r[i].raw end
  return table.concat(t)
end
-- Execute native US termination and scheduler code, with only emission and
-- scheduler-release calls observed instead of allocating their draw objects.
local VM=require(P..'stadium2_battle_fx_mips')
local Motion=require(P..'stadium2_battle_fx_motion')
local Native=require(P..'stadium2_battle_fx_native')
local vm=VM.new({{base=0x84100000,bytes=catalog.lifecycleAssets.fragment79}})
local obj=0x85000000
for _,c in ipairs({{0,0},{0x10,1},{0x10000000,0x20000},{0x10000010,0x20001}})do
  vm:write(obj+0x92,1,1);vm:write(obj+0x7f,255,1);vm:write(obj+0x14,c[2],4);vm:putFloat(obj+0x24,1)
  local native=vm:call(0x8410009C,{obj})
  local state=Motion.step(Motion.init({event={flags=c[1]},age=254},
    {resolveNativeFinalY=function()return 1 end}),1)
  print(('age255 descriptor=%08X native_done=%s lua_alive=%s'):format(c[1],native,tostring(state.alive)))
end
local pass,births=0,{}
local scheduler=VM.new({{base=0x84100000,bytes=catalog.lifecycleAssets.fragment79}}, {
  [0x84107998]=function()births[#births+1]=pass end,
  [0x84105E20]=function(v)v:write(v.r[4]+8,0,1)end,
})
scheduler:write(0x84190150,obj,4)
for _,r in ipairs(catalog.programs[167].records)do
  local e=r.emitter
  if e and e.descriptor==0x84177B4C then
    for i=0,64*12-1 do scheduler:write(obj+i,0,1)end
    scheduler:write(obj+4,e.start,1);scheduler:write(obj+5,e.interval,1)
    scheduler:write(obj+7,e.repeats,1);scheduler:write(obj+8,1,1);scheduler:write(obj+9,e.mode,1)
    for i=0,5 do pass=i;scheduler:call(0x84107B68,{})end
    local actual={}
    for _,b in ipairs(Native.births(Native.execute({records={r}},{}),-1,5))do actual[#actual+1]=b.born end
    print('ThunderShock84 zero-repeat emitter native='..table.concat(births,',')..' lua='..table.concat(actual,','))
  end
end
vm:write(0x8418C950,obj,4)
for i=0,300*0x9c-1 do vm:write(obj+i,0,1)end
vm:write(obj+0x98,1,1);vm:write(obj+0x14,0x80,4);vm:write(obj+0x7f,3,1)
vm:call(0x841054D4,{})
local held=Motion.init({event={mode=1,flags=2},material={nativeEndAge=3},age=2})
held=Motion.step(Motion.step(held,1),1)
print(('held age native=%d lua=%d lua_hidden=%s'):format(vm:read(obj+0x7f,1),held.age,tostring(held.nativeHidden)))

-- Isolate the live Gen 2 event adapter, not a copy of its conditionals.
local Gen2=require(P..'gen2_battle')
local scene=Gen2.Scene.new({volatile=function()return{}end})
scene.sync=function()end
scene.screen={game={data={moves={[222]={index=222,effect='EFFECT_MAGNITUDE'}}}}}
local moves={}
scene.battleFx={playMoveAndImpact=function(_,id)moves[#moves+1]=id end}
scene:handleEvent({kind='move',side='player',move=222,deferAnim=true,animDelay=true})
print('Magnitude deferred announcement FX starts='..#moves)
scene:handleEvent({kind='message',side='player',moveAnim=222})
print('Magnitude actual animation row total FX starts='..#moves)
scene.battleFx=nil;scene:release()

local Actor=require(P..'battle_actor')
local function preroll(steps)
  local actor=Actor.new('player')
  actor.renderer={model={fxDispatch=string.rep('\0',11)..string.char(254)..string.rep('\0',8)},frame=0,
    setMove=function(self)self.frame=0;return true end,
    setContext=function(self)self.frame=0;return true end,
    setHandlerRuntime=function()end,step=function(self,dt)self.frame=self.frame+dt*30 end}
  assert(actor:attack(1))
  for _,n in ipairs(steps)do actor:update(n/30)end
  return actor.renderer.frame
end
print(('negative-hit pre-roll: three single ticks clip_frame=%g, one three-tick update clip_frame=%g')
  :format(preroll({1,1,1}),preroll({3})))
local a,d=rows(159),rows(109)
for id=1,251 do
  local t=assert(Seq.attackTiming(a,id,{species=159,defenderDispatch=d}))
  if t.impact and t.route and t.impact<t.route and math.ceil(t.impact/3)==math.ceil(t.route/3) then
    print(('real rows Croconaw159->Koffing109 move%d route%d impact%d batch reverses'):format(id,t.route,t.impact))
  end
end
