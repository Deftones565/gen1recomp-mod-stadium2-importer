local prefix='mods.STADIUM2_IMPORTER.lib.'
local Terrain=require(prefix..'stadium2_battle_fx_terrain_grid')
local VM=require(prefix..'stadium2_battle_fx_mips')
local Rom=require(prefix..'stadium2_battle_fx_rom')
local file=io.open(os.getenv('STADIUM2_ROM') or 'mods/STADIUM2_IMPORTER/baseroms/stadium2.z64','rb')
if not file then assert(os.getenv('STADIUM2_REQUIRE_ROM')~='1');print('SKIP Surf ROM');return end
local rom=file:read('*a');file:close()
local catalog=assert(Rom.catalog(rom))
local function signed(n)return n>=32768 and n-65536 or n end
local function equal(a,b,label)assert(a==b,('%s native %.12g lua %.12g'):format(label,a,b))end
for _,side in ipairs({-1,1}) do
  local camera={eye={0,30,200},focus={0,20,0},fov=45,aspect=1.5,near=20}
  local state=assert(Terrain.new(side,catalog.lifecycleAssets.fragment79,camera))
  local signal=0;local allocations={};local allocation=0x85200000
  -- Independent full-ROM draw: real normalize, cross, height query, camera
  -- construction and fixed matrices. Only allocation, signal and sine hooked.
  local vm=VM.new({{base=0x84100000,bytes=catalog.lifecycleAssets.fragment79},
    {base=0x80000400,bytes=rom:sub(0x1001,0xA8000)}},{
    [0x841094EC]=function(v)v.r[2]=signal end,
    [0x80006DEC]=function(v)v.r[2]=allocation;allocations[#allocations+1]=allocation;allocation=allocation+v.r[4]end,
    [0x80073F70]=function(v)v:write(0x85700000,v.f[12],4);v.f[0]=VM.floatWord(math.sin(v:float(0x85700000)))end})
  vm:write(0x80094908,0x85100000,4)
  vm:putVector(0x851000A8,camera.eye);vm:putVector(0x851000B4,camera.focus);vm:putVector(0x851000C0,{0,1,0})
  vm:putFloat(0x8510002C,45);vm:putFloat(0x85100030,1.5);vm:putFloat(0x85100034,20)
  vm:call(0x8415A9E4,{side,0,0x4650})
  local base=vm:read(0x84187330,4)
  local sawCover,sawSurface=false,false
  for tick=0,95 do
    if tick==50 then signal=1 end
    if tick>0 then equal(vm:call(0x8415AD58),Terrain.step(state,signal,camera),'update')end
    allocations={};allocation=0x85200000
    vm:call(0x8415ADE0,{0x85400000},1000000)
    local g=assert(Terrain.geometry(state),state.error)
    equal(state.counter,signed(vm:read(base+4,2)),'counter')
    equal(state.duration,signed(vm:read(base+8,2)),'duration')
    assert(g==Terrain.geometry(state),'redraw reuses capture')
    for i=0,255 do
      local at=allocations[1]+i*16
      for k=0,2 do equal(signed(vm:read(at+k*2,2)),g.pos[i*3+k+1],'surface vertex')end
      for k=0,1 do equal(signed(vm:read(at+8+k*2,2))/1024,g.uv[i*2+k+1],'UV')end
      equal(vm:read(at+15,1),g.color[i*4+4],'alpha lag')
      if g.color[i*4+4]>0 then sawSurface=true end
    end
    equal(#allocations==3 and 1 or 0,g.cover.visible and 1 or 0,'cover visibility')
    if g.cover.visible then
      sawCover=true
      for i=0,3 do for k=0,2 do
        local expected=signed(vm:read(allocations[2]+i*16+k*2,2))*6553/65536
        assert(math.abs(expected-g.cover.pos[i*3+k+1])<.11,'camera cover vertex')
      end end
    end
  end
  assert(sawSurface and sawCover,'both native water layers exercised')
  -- Reach the authored expiry without burning thousands of test ticks.
  vm:write(base+4,vm:read(base+8,2),2)
  state.vm:write(state.base+4,state.vm:read(state.base+8,2),2)
  equal(vm:call(0x8415AD58),Terrain.step(state,signal,camera),'native expiry')
  assert(not state.active)
end
print('Surf ROM: surface vertices, UV, delayed fade, camera cover, completion and redraw stability passed')

local Preview=require('mods.STADIUM2_IMPORTER.tests.stadium2_koffing_croconaw_visual.battle_fx')
local Renderer=require(prefix..'renderer')
local Dispatch=require(prefix..'animation_dispatch')
local rows=assert(Dispatch.forSpecies(rom,109));local bytes={}
for i=0,270 do bytes[#bytes+1]=rows[i].raw end
local model={species=109,fxDispatch=table.concat(bytes)}
local scene={world={actorSlots={player={x=-3,y=0,z=0},enemy={x=3,y=0,z=0}}},
  camera={eye={0,1.5,10},focus={0,1,0},projection=Renderer.perspective(math.rad(45),1.5,1,320)},
  scene={actors={player={renderer={model=model}},enemy={renderer={model=model}}}}}
for _,move in ipairs({49,57}) do for _,side in ipairs({'player','enemy'}) do
  local allocations,updates,releases=0,0,0;local mesh
  local preview=Preview.new({rom=rom,releaseModel=function()end,importer={newRendererFromModel=function(m)
    local renderer=assert(Renderer.new(m,{flipY=false}))
    if m.file=='stadium2-lifecycle-beam' or m.file=='stadium2-lifecycle-terrain-grid' then
      allocations=allocations+1;mesh=m
      if move==49 then assert(#m.prims==8 and m.textures[1].symbol==37)
      else assert(#m.prims==2 and m.textures[1].symbol==31 and m.textures[2].symbol==32)end
      local update=renderer.updatePose
      renderer.updatePose=function(self,force)updates=updates+1;return update(self,force)end
      local release=renderer.release
      renderer.release=function(self)releases=releases+1;return release(self)end
      renderer.drawScene=function(self,pass,matrix)
        if move==57 then assert(matrix[4]==0 and matrix[8]==0 and matrix[12]==0,'arena origin')end
        return true
      end
    else renderer.drawScene=function()return true end end
    return renderer
  end}})
  assert(preview:start(move,side,false,scene))
  for _=1,20 do preview:step()end
  assert(preview:draw(scene).drawn>=1 and allocations==1)
  local before=updates;preview:draw(scene);assert(before==updates,'redraw does not simulate')
  preview:step();preview:draw(scene);assert(updates>before and allocations==1)
  if move==57 then
    -- Surf's four common-particle emitters start after the early wave check.
    for _=22,90 do preview:step() end
    preview:draw(scene)
    local seen={}
    for _,p in ipairs(preview.player:snapshot().particles) do
      if p.age>0 and p.event.programId==330 then seen[p.event.address]=true end
    end
    for address=0x8417F2B8,0x8417F2D0,8 do
      assert(seen[address],'Surf late particle emitter was exercised')
    end
  end
  for _,d in ipairs(preview.diagnostics) do
    assert(d.code~='terrain-grid-native-kernel-error' and d.code~='unsupported-lifecycle-callback'
      and d.code~='unresolved-terrain-grid-camera' and d.code~='unresolved-four-stream-model'
      and d.code~='unsupported-native-motion-mode' and d.code~='unresolved-native-motion-yaw'
      and d.code~='unsupported-native-motion-trig' and d.code~='motion-evaluation',d.message)
    assert(d.code~='unsupported-lifetime' and d.code~='unsupported-color-controller',d.message)
  end
  if move==49 then for _=22,60 do preview:step()end;preview:draw(scene);assert(releases==1)end
  preview:release();assert(releases==1,'mesh disposal')
end end
print('Sonic Boom/Surf viewer: both sides, ROM textures, placement, mesh reuse and disposal passed')
