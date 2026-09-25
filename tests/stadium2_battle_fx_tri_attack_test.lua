local prefix='mods.STADIUM2_IMPORTER.lib.'
local Tri=require(prefix..'stadium2_battle_fx_tri_attack')
local VM=require(prefix..'stadium2_battle_fx_mips')
local Random=require(prefix..'stadium2_battle_fx_random')
local Rom=require(prefix..'stadium2_battle_fx_rom')
local f=io.open(os.getenv('STADIUM2_ROM') or 'mods/STADIUM2_IMPORTER/baseroms/stadium2.z64','rb')
if not f then assert(os.getenv('STADIUM2_REQUIRE_ROM')~='1');print('SKIP Tri Attack ROM');return end
local rom=f:read('*a');f:close()
local catalog=assert(Rom.catalog(rom))
local Renderer=require(prefix..'renderer')
local function signed(v)return v>=32768 and v-65536 or v end
for _,side in ipairs({-1,1}) do
  local inputs={origin={-90*side,20,5},direction={.8*side,.25,-.15},
    terrainCamera={eye={0,30,200},focus={0,20,0}}}
  local random,oracleRandom=Random.new(432),Random.new(432)
  local s=assert(Tri.new(catalog.lifecycleAssets.fragment79,inputs,random))
  local allocation,vertices=0x85300000
  local vm=VM.new({{base=0x84100000,bytes=catalog.lifecycleAssets.fragment79},
    {base=0x80000400,bytes=rom:sub(0x1001,0xA8000)}},{
    [0x84156BA0]=function()end, -- shared camera/model setup belongs to adapter
    [0x841569E0]=function(v)
      for k=1,3 do v:putFloat(v.r[k+3],inputs.origin[k])end
      v:putFloat(v.r[7],inputs.direction[1]);v:putFloat(v:read(v.r[29]+16,4),inputs.direction[2]);v:putFloat(v:read(v.r[29]+20,4),inputs.direction[3])
    end,
    [0x84109780]=function(v)v:putVector(v.r[4],inputs.origin)end,
    [0x8007AFA0]=function(v)v.r[2]=oracleRandom:next()end,
    [0x80006DEC]=function(v)v.r[2]=allocation;vertices=allocation;allocation=allocation+v.r[4]end,
    [0x80073F70]=function(v)v:write(0x85700000,v.f[12],4);v.f[0]=VM.floatWord(math.sin(v:float(0x85700000)))end,
    [0x8416A050]=function(v)v.r[2]=v.r[5]end,
  })
  vm:write(0x84187530,0x85000000-0x3C8,4);vm:write(0x84187E40,0x85010000,4)
  vm:call(0x84169B80);vm:call(0x84158840)
  local sawSpark=false
  for tick=0,60 do
    if tick>0 then
      assert(vm:call(0x84158874)==Tri.step(s,inputs),s.error)
    end
    allocation=0x85300000
    vm:call(0x8415DBBC,{0x85200000})
    assert(random:next()==oracleRandom:next(),'same isolated RNG consumption')
    -- Compare every native node, including the mode-5 radius growth and
    -- delay semantics (delayed nodes do not follow the moving anchor).
    for j=0,19 do
      local at=0x85000048+j*0x48
      for k=0,36,4 do
        if k==4 then assert(vm:read(at+k,1)==s.vm:read(at+k,1),'node alpha')
        else assert(vm:float(at+k)==s.vm:float(at+k),'persistent native node') end
      end
    end
    for i=0,179 do
      for k=0,2 do
        local a=signed(vm:read(vertices+i*16+k*2,2))
        local b=signed(s.vm:read(0x85300000+i*16+k*2,2))
        assert(math.abs(a-b)<=1,'ROM rotate/vertex quantization')
      end
      for k=12,15 do assert(vm:read(vertices+i*16+k,1)==s.vm:read(0x85300000+i*16+k,1),'native gradient')end
    end
    for i=0,19 do
      local at=0x85010004+i*24
      assert(vm:read(at,2)==s.vm:read(at,2),'spark pool active')
      assert(vm:read(at+4,2)==s.vm:read(at+4,2),'spark age')
      for k=8,20,4 do assert(math.abs(vm:float(at+k)-s.vm:float(at+k))<.001,'spark scale/position')end
    end
    local g=Tri.geometry(s)
    assert(g==Tri.geometry(s),'redraw keeps captured geometry')
    assert(#g.layers==4 and #g.layers[1].idx==1026 and #g.layers[2].idx==1026 and #g.layers[3].idx==9)
    if s.sparkCount>0 then sawSpark=true end
    -- Independent native billboard and fixed-point scale/translation.
    local view=Renderer.lookAt(0,30,200,0,20,0)
    for r=0,3 do for c=0,3 do vm:putFloat(0x85500000+(r*4+c)*4,view[c*4+r+1])end end
    vm:call(0x80070DEC,{0x85500100,0x85500000})
    vm:call(0x80084780,{0x85500100,0x85500200}) -- guMtxF2L
    for i=0,19 do
      local at=0x85010004+i*24
      if vm:read(at,2)==1 then
        vm:call(0x84169F18,{0x85400000,at,0x85500200})
        local matrix={}
        for k=0,15 do
          local n=vm:read(vertices+k*2,2)*65536+vm:read(vertices+32+k*2,2)
          matrix[k]= (n>=2147483648 and n-4294967296 or n)/65536
        end
        for j=0,3 do for k=0,2 do
          local p=0x84187E48+j*16
          local expected=signed(vm:read(p,2))*matrix[k]+signed(vm:read(p+2,2))*matrix[4+k]
            +signed(vm:read(p+4,2))*matrix[8+k]+matrix[12+k]
          assert(math.abs(expected-g.layers[4].pos[(i*4+j)*3+k+1])<.005,'native spark billboard')
        end end
      end
    end
  end
  assert(sawSpark,'native random spark births exercised')
  assert(vm:call(0x84158874)==-1 and Tri.step(s,inputs)==-1 and not s.active,'native pool completes at tick 61')
end
print('Tri Attack ROM: both directions, nodes, colors, vertices, RNG, sparks and expiry passed')

local Dispatch=require(prefix..'animation_dispatch')
local Preview=require('mods.STADIUM2_IMPORTER.tests.stadium2_koffing_croconaw_visual.battle_fx')
local rows=assert(Dispatch.forSpecies(rom,109));local raw={}
for i=0,270 do raw[#raw+1]=rows[i].raw end
local model={species=109,fxDispatch=table.concat(raw)}
local scene={world={actorSlots={player={x=-3,y=0,z=0},enemy={x=3,y=0,z=0}}},
  camera={eye={0,1.5,10},focus={0,1,0},projection=Renderer.perspective(math.rad(45),1.5,1,320)},
  scene={actors={player={renderer={model=model}},enemy={renderer={model=model}}}}}
for _,side in ipairs({'player','enemy'})do
  local allocations,updates,releases=0,0,0
  local preview=Preview.new({rom=rom,releaseModel=function()end,importer={newRendererFromModel=function(m)
    local renderer=assert(Renderer.new(m,{flipY=false}))
    if m.file=='stadium2-lifecycle-beam' then
      allocations=allocations+1
      assert(#m.prims==4 and #m.textures==1 and m.textures[1].rgba==catalog.lifecycleAssets.radialSpark.rgba)
      local update=renderer.updatePose
      renderer.updatePose=function(self,force)updates=updates+1;return update(self,force)end
      local release=renderer.release
      renderer.release=function(self)releases=releases+1;return release(self)end
      renderer.drawScene=function(self,pass,matrix,options)
        assert(options.disableCulling==false,'native front/back passes retain culling')
        assert(matrix[4]==(side=='player' and -3 or 3),'source-relative placement')
        return true
      end
    else renderer.drawScene=function()return true end end
    return renderer
  end}})
  assert(preview:start(161,side,false,scene))
  for _=1,25 do preview:step()end
  assert(preview:draw(scene).drawn>=1 and allocations==1)
  local before=updates;preview:draw(scene);assert(before==updates)
  preview:step();preview:draw(scene);assert(updates>before and allocations==1)
  for _=27,62 do preview:step()end
  preview:draw(scene);assert(releases==1)
  for _,d in ipairs(preview.diagnostics)do
    assert(d.code~='unsupported-lifecycle-callback' and d.code~='tri-attack-native-kernel-error'
      and d.code~='unresolved-tri-attack-inputs' and d.code~='draw-renderer',d.message)
  end
  preview:release();assert(releases==1)
end
print('Tri Attack viewer: both sides, native texture, culling, mesh reuse and disposal passed')
