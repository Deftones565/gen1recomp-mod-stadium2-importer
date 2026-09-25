local prefix='mods.STADIUM2_IMPORTER.lib.'
local Stream=require(prefix..'stadium2_battle_fx_textured_stream')
local VM=require(prefix..'stadium2_battle_fx_mips')
local Random=require(prefix..'stadium2_battle_fx_random')
local Rom=require(prefix..'stadium2_battle_fx_rom')
local file=io.open(os.getenv('STADIUM2_ROM') or 'mods/STADIUM2_IMPORTER/baseroms/stadium2.z64','rb')
if not file then assert(os.getenv('STADIUM2_REQUIRE_ROM')~='1');print('SKIP Ice Beam ROM');return end
local rom=file:read('*a');file:close()
local catalog=assert(Rom.catalog(rom))
local function signed(v)return v>=32768 and v-65536 or v end
for _,family in ipairs({13,8})do
for _,side in ipairs({-1,1})do
  local inputs={origin={-90*side,20,5},direction={.8*side,.25,-.15},
    endpointA={-90*side,20,5},endpointB={90*side,40,0},cameraEye={0,30,200}}
  local random,oracleRandom=Random.new(432),Random.new(432)
  local s=assert(Stream.new(catalog.lifecycleAssets.fragment79,inputs,random,family))
  local allocation,signal,glowVertices=0x85300000,0
  local function trig(fn)return function(v)
    v:write(0x85700000,v.f[12],4);v.f[0]=VM.floatWord(fn(v:float(0x85700000)))
  end end
  local vm=VM.new({{base=0x84100000,bytes=catalog.lifecycleAssets.fragment79},
    {base=0x80000400,bytes=rom:sub(0x1001,0xA8000)}},{
    [0x84156BA0]=function()end,
    [0x841569E0]=function(v)
      for k=1,3 do v:putFloat(v.r[k+3],inputs.origin[k])end
      v:putFloat(v.r[7],inputs.direction[1]);v:putFloat(v:read(v.r[29]+16,4),inputs.direction[2]);v:putFloat(v:read(v.r[29]+20,4),inputs.direction[3])
    end,
    [0x84109780]=function(v)v:putVector(v.r[4],inputs.origin)end,
    [0x841098FC]=function(v)v:putVector(v.r[4],inputs.endpointB)end,
    [0x841094EC]=function(v)v.r[2]=signal end,
    [0x841094A4]=function(v)v.r[2]=0x85600000;v:putVector(0x856000A8,inputs.cameraEye)end,
    [0x8007AFA0]=function(v)v.r[2]=oracleRandom:next()end,
    [0x80006DEC]=function(v)v.r[2]=allocation;if v.r[4]==160 then glowVertices=allocation end;allocation=allocation+v.r[4]end,
    [0x80073F70]=trig(math.sin),[0x8007E9C0]=trig(math.cos),
  })
  vm:write(0x84187DC0,0x85000000-0x900,4);vm:write(0x84187D40,0x85010000,4)
  vm:call(family==8 and 0x84159C2C or 0x84158E24)
  local peak,fade=0,false
  for tick=0,91 do
    if tick==21 then inputs.origin={-70*side,25,8};inputs.endpointA=inputs.origin;inputs.direction={side,.1,0}end
    if tick>=40 then signal=1 end
    if tick>0 then
      local result=vm:call(family==8 and 0x84159C6C or 0x84158E58)
      assert(result==Stream.step(s,inputs,signal),s.error)
      if result==-1 then assert(tick==(family==8 and 72 or 91) and not s.active);break end
    end
    allocation=0x85300000;vm:call(0x84169618,{0x85200000})
    assert(random:snapshot().state==oracleRandom:snapshot().state,'isolated RNG')
    assert(random:snapshot().offset==oracleRandom:snapshot().offset,'RNG consumption')
    local g=Stream.geometry(s);assert(g==Stream.geometry(s) and #g.layers==(family==8 and 9 or 6))
    if family==8 then
      glowVertices=nil
      vm:call(0x84168000,{0x85400000})
      if glowVertices then
        for j=0,9 do
          for k=0,2 do assert(math.abs(signed(vm:read(glowVertices+j*16+k*2,2))-g.layers[1].pos[j*3+k+1])<=1,
            ('native glow vertex tick=%d j=%d k=%d native=%s actual=%s'):format(tick,j,k,signed(vm:read(glowVertices+j*16+k*2,2)),g.layers[1].pos[j*3+k+1]))end
          for k=0,3 do assert(math.abs(vm:read(glowVertices+j*16+12+k,1)-g.layers[1].color[j*4+k+1])<=(k==3 and 1 or 0),
            ('native glow color tick=%d j=%d k=%d native=%s actual=%s'):format(tick,j,k,vm:read(glowVertices+j*16+12+k,1),g.layers[1].color[j*4+k+1]))end
        end
      end
      for slot=0,1 do
        local at=0x85010000+slot*0x240;local core=s.beam.slots[slot+1]
        assert(core.age==vm:read(at+2,2) and core.phase==vm:read(at+6,2),'native core age/phase')
        for j=0,9 do
          local node=at+0xB0+j*0x28;local ring=core.rings[j+1]
          assert(ring.radius==vm:float(node+8) and ring.angle==vm:float(node+12),'native core profile')
          for k=0,2 do assert(ring.position[k+1]==vm:float(node+16+k*4),'native core endpoint')end
        end
        local vertices=vm:read(at+0x18,4);local layer=g.layers[slot+2]
        for j=0,89 do
          for k=0,2 do assert(math.abs(signed(vm:read(vertices+j*16+k*2,2))-layer.pos[j*3+k+1])<=1,'native core vertex')end
          for k=0,1 do assert(signed(vm:read(vertices+j*16+8+k*2,2))/1024==layer.uv[j*2+k+1],'native core UV')end
        end
        for i,offset in ipairs({0x64,0x66,0x70,0x72})do assert(core.draw.uv[i]==signed(vm:read(at+offset,2)),'native core scroll')end
        assert(core.draw.alpha==vm:float(at+0x90),'native core fade')
        for j=0,3 do
          assert(core.draw.primary[j+1]==vm:read(at+0x7C+j,1),'native primary color')
          assert(core.draw.environment[j+1]==vm:read(at+0x81+j,1),'native environment color')
          assert(core.draw.overlay[j+1]==vm:read(at+0x86+j,1),'native glow palette')
        end
        for j=0,7 do
          assert(core.draw.cycle0[j+1]==vm:read(at+0x24+j*4,4),'native first combiner')
          assert(core.draw.cycle1[j+1]==vm:read(at+0x44+j*4,4),'native second combiner')
        end
      end
    end
    local active=0
    for slot=0,5 do
      local at=0x85000000+slot*0x374;local layer=g.layers[slot+1+(family==8 and 3 or 0)]
      -- Compare complete native simulation/material state, excluding the
      -- scratch vertex pointer populated independently by each draw.
      for offset=0,0x373 do
        if offset<0x88 or offset>=0x8C then
          assert(vm:read(at+offset,1)==s.vm:read(at+offset,1),'native slot state')
        end
      end
      assert(#layer.idx==114 and layer.geometryMode==0x200005)
      for j=0,39 do
        assert(layer.uv[j*2+1]==j%2 and layer.uv[j*2+2]==math.floor(math.floor(j/2)*1024/20)/1024,
          'inactive slots must retain native UVs for future emissions')
      end
      if vm:read(at,2)==1 then
        active=active+1
        assert(layer.draw.textures[1]==25 and layer.draw.textures[2]==25)
        assert(layer.draw.alpha==vm:float(at+0x18),'native material fade')
        if layer.draw.alpha>0 and layer.draw.alpha<1 then fade=true end
        local vertices=vm:read(at+0x88,4)
        for j=0,39 do
          for k=0,2 do assert(math.abs(signed(vm:read(vertices+j*16+k*2,2))-layer.pos[j*3+k+1])<=1,'native rotation/vertex')end
          for k=0,1 do assert(signed(vm:read(vertices+j*16+8+k*2,2))/1024==layer.uv[j*2+k+1],'native UV')end
          for k=0,3 do assert(vm:read(vertices+j*16+12+k,1)==layer.color[j*4+k+1],'native color')end
        end
      else assert(layer.draw.alpha==0)end
    end
    peak=math.max(peak,active)
  end
  assert(peak>1 and (fade or family==8),'repeated emissions and finish fade exercised')
end
end
print('Ice Beam/Hyper Beam ROM: both sides, live anchors, pools, vertices, UV, material, RNG and expiry passed')

local Renderer=require(prefix..'renderer')
local Dispatch=require(prefix..'animation_dispatch')
local Preview=require('mods.STADIUM2_IMPORTER.tests.stadium2_koffing_croconaw_visual.battle_fx')
local rows=assert(Dispatch.forSpecies(rom,109));local raw={}
for i=0,270 do raw[#raw+1]=rows[i].raw end
local model={species=109,fxDispatch=table.concat(raw)}
local scene={world={actorSlots={player={x=-3,y=0,z=0},enemy={x=3,y=0,z=0}}},
  camera={eye={0,1.5,10},focus={0,1,0},projection=Renderer.perspective(math.rad(45),1.5,1,320)},
  scene={actors={player={renderer={model=model}},enemy={renderer={model=model}}}}}
for _,move in ipairs({58,63})do
for _,side in ipairs({'player','enemy'})do
  local allocations,updates,releases=0,0,0
  local preview=Preview.new({rom=rom,releaseModel=function()end,importer={newRendererFromModel=function(m)
    local renderer=assert(Renderer.new(m,{flipY=false}))
    if m.file=='stadium2-lifecycle-beam' then
      allocations=allocations+1
      assert(#m.prims==(move==63 and 9 or 6) and #m.textures==(move==63 and 17 or 12),'persistent core and stream meshes')
      for i,texture in ipairs(m.textures)do
        if move~=63 or i>1 then
          assert(texture.w==32 and texture.h==32 and texture.format==4 and texture.size==0,'ROM I4 beam/stream texture')
        end
      end
      local update=renderer.updatePose
      renderer.updatePose=function(self,force)updates=updates+1;return update(self,force)end
      local release=renderer.release
      renderer.release=function(self)releases=releases+1;return release(self)end
      renderer.drawScene=function(self,pass,matrix)
        assert(matrix[4]==(side=='player' and -3 or 3),'source-relative placement');return true
      end
    else renderer.drawScene=function()return true end end
    return renderer
  end}})
  local effect=assert(preview:start(move,side,false,scene))
  for _=1,25 do preview:step()end
  assert(preview:draw(scene).drawn>=1 and allocations==1)
  local before=updates;preview:draw(scene);assert(before==updates,'redraw does not step simulation')
  preview:step();preview:draw(scene);assert(updates>before and allocations==1)
  assert(preview.player:finish(effect))
  for _=1,60 do preview:step()end
  preview:draw(scene);assert(releases==1,'native finish disposes renderer')
  for _,d in ipairs(preview.diagnostics)do
    assert(d.code~='unsupported-lifecycle-callback' and d.code~='textured-stream-native-kernel-error'
      and d.code~='unresolved-textured-stream-inputs' and d.code~='draw-renderer',d.message)
  end
  preview:release();assert(releases==1)
end
end
print('Ice Beam/Hyper Beam viewer: both sides, ROM textures, mesh reuse, finish and disposal passed')
