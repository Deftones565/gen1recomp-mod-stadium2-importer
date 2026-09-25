local prefix='mods.STADIUM2_IMPORTER.lib.'
local Rom=require(prefix..'stadium2_battle_fx_rom')
local VM=require(prefix..'stadium2_battle_fx_mips')
local Native=require(prefix..'stadium2_battle_fx_native')
local Motion=require(prefix..'stadium2_battle_fx_motion')
local Packets=require(prefix..'stadium2_battle_fx_draw_packets')
local f=io.open(os.getenv('STADIUM2_ROM') or 'mods/STADIUM2_IMPORTER/baseroms/stadium2.z64','rb')
if not f then assert(os.getenv('STADIUM2_REQUIRE_ROM')~='1');print('SKIP screen ROM');return end
local rom=f:read('*a');f:close()
local catalog=assert(Rom.catalog(rom))
local particle,scheduler,owner=0x85000000,0x85001000,0x85002000
local images={{base=0x84100000,bytes=catalog.lifecycleAssets.fragment79},
  {base=0x80000400,bytes=rom:sub(0x1001,0xA8000)},
  {base=0x81100000,bytes=rom:sub(0x165C51,0x166500)}}
local seen,count={},0
for _,program in pairs(catalog.programs) do for _,record in ipairs(program.records) do
  local event=record.emitter
  if event and event.mode==7 and not seen[event.descriptor] then
    seen[event.descriptor]=true
    local vm=VM.new(images,{
      [0x84100328]=function(v)
        for i=0,0x9B do v:write(particle+i,0,1) end
        v:putFloat(particle+0x1C,1);v.r[2]=particle
      end,
      [0x84107170]=function(v)
        v:write(particle+8,owner,4);v:write(particle+0x10,event.descriptor,4)
        v:write(particle+0x7C,7,1)
      end,
      [0x84106F34]=function()end, -- material is tested independently
      [0x81100120]=function(v)v.r[2]=0 end,
      [0x81100144]=function(v)v.r[2]=0 end})
    vm:write(0x84190194,owner,4)
    vm:write(scheduler,event.descriptor,4);vm:write(scheduler+9,7,1)
    vm:write(event.descriptor+3,1,1)
    vm:call(0x841076B8,{scheduler})
    local e={};for k,v in pairs(event)do e[k]=v end;e.start=0;e.particleCount=1
    local row=assert(Native.particles({scheduled={e}},-1,0)[1])
    local state=Motion.init(row,{trigTables=catalog.trigTables,nativeSourceYaw=0,
      randomScalar=function()return 0 end})
    assert(state.position[1]==vm:float(particle+0x20),('screen X %X'):format(event.descriptor))
    assert(state.position[2]==vm:float(particle+0x24),('screen Y %X'):format(event.descriptor))
    assert(state.scale[1]==vm:float(particle+0x18),'screen unit scalar')
    vm.hooks[0x84102750]=function()end
    for tick=1,3 do
      vm:write(particle+0x7F,tick,1)
      vm:call(0x841027B4,{particle})
      state=Motion.step(state,1)
      assert(state.position[1]==vm:float(particle+0x20),'screen tick X')
      assert(state.position[2]==vm:float(particle+0x24),'screen tick Y')
      assert(state.scale[1]==vm:float(particle+0x18),'screen tick size')
    end
    count=count+1
  end
end end
local vm=VM.new(images)
local function trunc(x)return x<0 and math.ceil(x) or math.floor(x)end
for _,mode in ipairs({5,6}) do for _,angle in ipairs({0,0x1234,0x4000,0xFEDC}) do
  for _,scale in ipairs({.25,1,1.7}) do
    local p={event={mode=7},shapeId=97,position={171.9,-23.6,500},rotation={123,456,angle},scale={scale,scale,scale}}
    local result=Packets.build({particles={p}},{trigTables=catalog.trigTables,
      contextForParticle=function()error('screen particles must bypass world placement')end})
    assert(#result.packets==0 and #result.screenPackets==1 and #result.diagnostics==0)
    vm:putFloat(0x857FF010,scale)
    vm:call(mode==5 and 0x8410383C or 0x841038F4,{particle,trunc(p.position[1]),trunc(p.position[2]),angle})
    local matrix=mode==5 and result.screenPackets[1].matrix or result.screenPackets[1].matrixYScale
    for i=0,3 do for j=0,3 do
      assert(matrix[i*4+j+1]==vm:float(particle+(j*4+i)*4),'screen matrix ROM')
    end end
  end
end end
print(('Screen ROM: %d retail descriptors, both 2D matrix modes, pixel truncation and placement isolation passed'):format(count))

local Preview=require('mods.STADIUM2_IMPORTER.tests.stadium2_koffing_croconaw_visual.battle_fx')
for _,case in ipairs({{10,35,6},{54,8,5}}) do
  for _,side in ipairs({'player','enemy'}) do
    local calls,loads,releases=0,0,0
    local preview=Preview.new({rom=rom,releaseModel=function()end,
      importer={newRendererFromModel=function(model)
        loads=loads+1
        return {model=model,release=function()releases=releases+1 end,
          drawScene=function(_,pass,matrix,options)
            if options.screenSpace then
              calls=calls+1
              assert(options.viewProjection[1]==1/160 and options.viewProjection[6]==-1/120)
              assert(options.viewMatrix[1]==1 and options.viewMatrix[4]==0)
              if model.battleFxGeometryMode==6 then assert(math.abs(matrix[1]^2+matrix[5]^2-1)<1e-6,'fixed screen X scale') end
            end
            return true
          end}
      end}})
    local scene={world={actorSlots={player={-5,0,0},enemy={5,0,0}}},camera={viewProjection={999}}}
    assert(preview:start(case[1],side,false,scene))
    for _=1,case[2] do preview:step() end
    local world=preview:draw(scene)
    for _,p in ipairs(world.packets)do assert(p.kind~='screen-particle')end
    local before=preview.player:snapshot()
    local drawn=scene.nativeOverlayDraw()
    assert(drawn>0 and calls==drawn*2,('overlay move %d drawn %d calls %d particles %d'):format(case[1],drawn,calls,#before.particles))
    local allocated=loads
    scene.camera.viewProjection={-999}
    assert(scene.nativeOverlayDraw()==drawn and loads==allocated,'persistent screen renderers')
    assert(preview.player:snapshot().frame==before.frame,'overlay must not simulate')
    for _,d in ipairs(preview.diagnostics)do assert(d.code~='unsupported-common-screen-space' and d.code~='native-screen-renderer')end
    preview:release();assert(releases==loads,'screen renderer disposal')
  end
end
print('Screen viewer: Scratch/Mist, both sides, overlay routing, camera isolation, reuse and disposal passed')
