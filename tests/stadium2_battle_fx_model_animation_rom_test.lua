local prefix='mods.STADIUM2_IMPORTER.lib.'
local Rom=require(prefix..'stadium2_battle_fx_rom')
local Resources=require(prefix..'stadium2_battle_fx_resources')
local Animation=require(prefix..'stadium2_battle_fx_model_animation')
local Renderer=require(prefix..'renderer')
local Player=require(prefix..'stadium2_battle_fx_player')
local VM=require(prefix..'stadium2_battle_fx_mips')
local file=io.open(os.getenv('STADIUM2_ROM') or 'mods/STADIUM2_IMPORTER/baseroms/stadium2.z64','rb')
if not file then assert(os.getenv('STADIUM2_REQUIRE_ROM')~='1');print('SKIP model animation ROM');return end
local rom=file:read('*a');file:close()
local catalog=assert(Rom.catalog(rom))
-- Compare forward/reverse, start-at-end, one-shot and loop boundaries against
-- the US animation counter. Redraws never increment the simulated clock.
local vm=VM.new({{base=0x80000400,bytes=rom:sub(0x1001,0xA8000)}})
local state,header=0x85000000,0x85000100
for _,flags in ipairs({0,2}) do for _,reverse in ipairs({false,true}) do
  for _,atEnd in ipairs({false,true}) do
    local anim={flags=flags,frames=31,startFrame=3,loopStart=2}
    vm:write(header,flags,2);vm:write(header+6,2,2);vm:write(header+10,31,2)
    vm:write(state+4,header,4);vm:write(state+12,reverse and -65536 or 65536,4)
    vm:write(state+18,65535,2)
    local start=(reverse or atEnd) and 30 or 3
    vm:write(state+8,(start+(reverse and 1 or -1))*65536,4)
    for tick=0,120 do
      vm:call(0x8003E6DC,{state,tick})
      local fixed=vm.r[2];vm:write(state+8,fixed,4)
      local frame=math.floor(fixed/65536)%65536
      assert(Animation.frame(anim,{reverse=reverse,startAtEnd=atEnd,ticks=tick})==frame,
        'native animation counter mismatch')
    end
  end
end end
local bit=require('bit')
local retired=false
local finishVM=VM.new({{base=0x80000400,bytes=rom:sub(0x1001,0xA8000)},
  {base=0x84100000,bytes=catalog.lifecycleAssets.fragment79}}, {
  [0x81100054]=function(v)v.r[2]=bit.band(v:read(v.r[4],4),v.r[5])~=0 and 1 or 0 end,
  [0x81100074]=function(v)v.r[2]=bit.band(v:read(v.r[4],4),v.r[5])==0 and 1 or 0 end,
  [0x84100094]=function()retired=true end})
local particle,visual,descriptor=0x85000200,0x85000300,0x85000400
finishVM:write(particle+12,visual,4);finishVM:write(particle+16,descriptor,4)
finishVM:write(visual+0x44,header,4)
for _,headerFlags in ipairs({0,2}) do for _,flags in ipairs({0,0x2000,0x4000,0x6000}) do
  for _,age in ipairs({0,15,30,31,90}) do
    local p={age=age,event={mode=0,flags=flags,material={secondaryShapeId=141}}}
    local selection=Animation.packet(p)
    local anim={flags=headerFlags,frames=31,startFrame=0,loopStart=0}
    finishVM:write(header,headerFlags,2);finishVM:write(header+10,31,2)
    finishVM:write(descriptor+4,flags,4)
    finishVM:write(visual+0x48,Animation.frame(anim,selection)*65536,4)
    retired=false;finishVM:call(0x8410291C,{particle})
    assert(retired==(Animation.finishesParticle(p) and Animation.finished(anim,selection)),
      'native animation completion gate mismatch')
  end
end end
local count,moves=0,0
for move=1,251 do
  local seen,res,found={},nil,false
  for _,bank in ipairs({'primaryDispatch','alternateDispatch'}) do
    for _,route in ipairs(catalog.moves[move][bank]) do
      for _,record in ipairs(route.programId and catalog.programs[route.programId].records or {}) do
        local event=record.emitter
        local selection=event and Animation.packet({event=event,age=0})
        if selection then
          local shapeId=event.material.shapeId
          local key=shapeId..':'..selection.id
          if not seen[key] then
            seen[key]=true;found=true
            res=res or assert(Resources.resolve(rom:sub(Resources.ROM_START+1,Resources.ROM_END),catalog.moves[move].resources))
            local model=assert(Resources.modelFromShape(assert(Resources.shapeFromResolved(res,shapeId,selection.id))))
            assert(not model.staticPose and model.anims[1] and model.battleFxAnimationId==selection.id)
            count=count+1
          end
        end
      end
    end
  end
  if found then moves=moves+1 end
end
assert(count==180 and moves==131,'retail animated model route coverage')
local resources=assert(Resources.resolve(rom:sub(Resources.ROM_START+1,Resources.ROM_END),catalog.moves[14].resources))
local particles={}
for i=1,2 do particles[i]={id=i,effectId=1,born=(i-1)*5,age=10,shapeId=140,
  scale={1,1,1},event={mode=0,flags=0x20000,material={shapeId=140,secondaryShapeId=141}},
  material={shapeId=140,secondaryShapeId=141}} end
local snapshot={frame=20,effects={{id=1,moveId=14}},particles=particles}
local frames,positions,loads={},{},0
local player=Player.new({runtime={snapshot=function()return snapshot end},
  resolvePlacement=function()return {resolved=true,position={0,0,0},scale=1}end,
  loadRenderer=function(_,shapeId,animationId)
    loads=loads+1
    local model=assert(Resources.modelFromShape(assert(Resources.shapeFromResolved(resources,shapeId,animationId))))
    local renderer=assert(Renderer.new(model,{flipY=false}))
    renderer.drawScene=function(self,pass)
      if pass=='opaque' then
        frames[#frames+1]=self.frame
        local vertices={}
        for _,part in ipairs(self.parts) do for _,row in ipairs(part.rows) do
          for axis=1,3 do vertices[#vertices+1]=string.format('%.5f',row[axis]) end
        end end
        positions[#positions+1]=table.concat(vertices,',')
      end
      return true
    end
    return renderer
  end})
assert(player:draw({}).drawn==2)
assert(frames[1]==20 and frames[2]==15 and positions[1]~=positions[2],
  'Swords Dance mesh must deform independently for each particle')
assert(player:draw({}).drawn==2 and loads==1)
assert(positions[1]==positions[3] and positions[2]==positions[4],
  'cached renderer must seek back without advancing on redraw')
assert(not Resources.shapeFromResolved(resources,140,9999),'missing animation fails explicitly')
local Preview=require('mods.STADIUM2_IMPORTER.tests.stadium2_koffing_croconaw_visual.battle_fx')
for _,side in ipairs({'player','enemy'}) do
  local seen={}
  local preview=Preview.new({rom=rom,releaseModel=function()end,
    importer={newRendererFromModel=function(model)
      local renderer=assert(Renderer.new(model,{flipY=false}))
      renderer.drawScene=function(self)
        if model.battleFxAnimationId==141 then seen[self.frame]=true end
        return true
      end
      return renderer
    end}})
  local context={world={groundY=0,actorSlots={player={x=-10,y=0,z=0},enemy={x=10,y=0,z=0}}}}
  assert(preview:start(14,side,false,context))
  for tick=0,110 do preview:draw(context);preview:step() end
  for frame=0,99 do assert(seen[frame],'viewer must display every Swords Dance frame, including last') end
  for _,p in ipairs(preview.player:snapshot().particles) do
    assert(p.shapeId~=140,'completed Swords Dance model must retire')
  end
  preview:release()
end
print(('Model animation ROM: native counter, %d bindings across %d moves; Swords Dance skinning and cached poses passed'):format(count,moves))
