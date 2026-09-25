local prefix='mods.STADIUM2_IMPORTER.lib.'
local Stochastic=require(prefix..'stadium2_battle_fx_stochastic')
local VM=require(prefix..'stadium2_battle_fx_mips')
local Random=require(prefix..'stadium2_battle_fx_random')
local Rom=require(prefix..'stadium2_battle_fx_rom')
local file=io.open(os.getenv('STADIUM2_ROM') or 'mods/STADIUM2_IMPORTER/baseroms/stadium2.z64','rb')
if not file then assert(os.getenv('STADIUM2_REQUIRE_ROM')~='1');print('SKIP stochastic ROM');return end
local rom=file:read('*a');file:close()
local catalog=assert(Rom.catalog(rom))
local function signed(v)return v>=32768 and v-65536 or v end
for _,family in ipairs({3,15})do
  local inputs={origin={-90,20,5},endpointB={90,40,0},modelScale=1}
  local random,oracleRandom=Random.new(432),Random.new(432)
  local state=assert(Stochastic.new(catalog.lifecycleAssets.fragment79,catalog.lifecycleAssets.mainKernel,inputs,random,family))
  local signal,allocation=0,0x85300000
  local function trig(fn)return function(v)
    v:write(0x85700000,v.f[12],4);v.f[0]=VM.floatWord(fn(v:float(0x85700000)))
  end end
  local vm=VM.new({{base=0x84100000,bytes=catalog.lifecycleAssets.fragment79},
    {base=0x80000400,bytes=catalog.lifecycleAssets.mainKernel}},{
    [0x84156BA0]=function()end,
    [0x84109780]=function(v)v:putVector(v.r[4],inputs.origin)end,
    [0x841098FC]=function(v)v:putVector(v.r[4],inputs.endpointB)end,
    [0x84109544]=function(v)v.f[0]=VM.floatWord(inputs.modelScale)end,
    [0x841094EC]=function(v)v.r[2]=signal end,
    [0x8007AFA0]=function(v)v.r[2]=oracleRandom:next()end,
    [0x80073F70]=trig(math.sin),[0x8007E9C0]=trig(math.cos),
    [0x80006DEC]=function(v)v.r[2]=allocation;allocation=allocation+v.r[4]end,
  })
  vm:call(family==3 and 0x84157AB0 or 0x84157CB0)
  local peak=0
  for tick=0,111 do
    if tick==21 then inputs.origin={-70,25,8};inputs.endpointB={110,35,0}end
    if tick>=40 then signal=1 end
    if tick>0 then
      local result=vm:call(family==3 and 0x84157ADC or 0x84157CDC)
      assert(result==Stochastic.step(state,inputs,signal),state.error)
      if result==-1 then assert(tick==111);break end
    end
    assert(random:snapshot().state==oracleRandom:snapshot().state,'isolated native RNG')
    if tick==0 or tick==2 or tick==21 or tick==40 or tick==60 or tick==80 or tick==110 then
      allocation=0x85300000
      local finish=vm:call(0x84166A64,{0x85200000,family==3 and 34 or 35})%4294967296
      assert(finish==state.drawEnd,'native draw packet length')
      local geometry=Stochastic.geometry(state)
      assert(geometry==Stochastic.geometry(state) and #geometry.layers==52,'persistent 26-slot geometry')
      local spriteIndex,visible=0,0
      for slot=0,25 do
        local at=0x8419F070+slot*0x360
        local active=vm:read(at,2)==1
        local sprite=active and vm:float(at+0x54)>0
        local spriteLayer,trailLayer=geometry.layers[slot*2+1],geometry.layers[slot*2+2]
        assert(#spriteLayer.idx==6 and #trailLayer.idx==54)
        for offset=0,0x35F do
          if offset<0x20 or offset>=0x24 then
            assert(vm:read(at+offset,1)==state.vm:read(at+offset,1),
              ('native pool state family=%d tick=%d slot=%d offset=%X'):format(family,tick,slot,offset))
          end
        end
        if sprite then
          spriteIndex=spriteIndex+1
          local found
          local seen=0
          for p=0x85200000,finish-1,8 do
            if vm:read(p,4)==0xDA380000 then
              seen=seen+1
              if seen==spriteIndex then found=vm:read(p+4,4);break end
            end
          end
          assert(found,'native sprite transform')
          for j=0,3 do
            local p=0x84187C80+j*16
            for k=0,2 do
              local expected=0
              for n=0,2 do
                local word=vm:read(found+(n*4+k)*2,2)*65536+vm:read(found+32+(n*4+k)*2,2)
                local m=(word>=2147483648 and word-4294967296 or word)/65536
                expected=expected+signed(vm:read(p+n*2,2))*m
              end
              local word=vm:read(found+(12+k)*2,2)*65536+vm:read(found+32+(12+k)*2,2)
              expected=expected+(word>=2147483648 and word-4294967296 or word)/65536
              assert(math.abs(expected-spriteLayer.pos[j*3+k+1])<.001,'ROM sprite matrix')
            end
          end
        end
        if active then
          visible=visible+1
          local vertices=vm:read(at+0x20,4)
          for j=0,19 do
            for k=0,2 do assert(signed(vm:read(vertices+j*16+k*2,2))==trailLayer.pos[j*3+k+1],'native ribbon vertex')end
            for k=0,3 do assert(vm:read(vertices+j*16+12+k,1)==trailLayer.color[j*4+k+1],'native ribbon color')end
          end
        end
      end
      peak=math.max(peak,visible)
    end
  end
  assert(peak==26,'all native slots reached saturation')
end
print('Families 3/15 ROM: RNG, full pool, sprite matrices, ribbons, live anchors and expiry passed')

local Renderer=require(prefix..'renderer')
local Dispatch=require(prefix..'animation_dispatch')
local Preview=require('mods.STADIUM2_IMPORTER.tests.stadium2_koffing_croconaw_visual.battle_fx')
local rows=assert(Dispatch.forSpecies(rom,109));local raw={}
for i=0,270 do raw[#raw+1]=rows[i].raw end
local model={species=109,fxDispatch=table.concat(raw)}
local scene={world={actorSlots={player={x=-3,y=0,z=0},enemy={x=3,y=0,z=0}}},
  camera={eye={0,1.5,10},focus={0,1,0},projection=Renderer.perspective(math.rad(45),1.5,1,320)},
  scene={actors={player={renderer={model=model}},enemy={renderer={model=model}}}}}
for _,move in ipairs({75,80})do for _,side in ipairs({'player','enemy'})do
  local allocations,updates,releases=0,0,0
  local preview=Preview.new({rom=rom,releaseModel=function()end,importer={newRendererFromModel=function(m)
    local renderer=assert(Renderer.new(m,{flipY=false}))
    if m.file=='stadium2-lifecycle-beam' then
      allocations=allocations+1
      assert(#m.prims==52 and #m.textures==26,'native sprites and ribbons')
      for _,texture in ipairs(m.textures)do assert(texture.w==32 and texture.h==32 and texture.format==4 and texture.size==0)end
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
  local before=updates;preview:draw(scene);assert(before==updates,'redraw must preserve native state')
  preview:step();preview:draw(scene);assert(updates>before and allocations==1)
  assert(preview.player:finish(effect))
  for _=1,72 do preview:step()end
  preview:draw(scene);assert(releases==1,'native finish disposes renderer')
  for _,d in ipairs(preview.diagnostics)do
    assert(d.code~='unsupported-lifecycle-callback' and d.code~='stochastic-native-kernel-error'
      and d.code~='unresolved-stochastic-anchor' and d.code~='draw-renderer',d.message)
  end
  preview:release();assert(releases==1)
end end
print('Families 3/15 viewer: moves 75/80 on both sides, ROM textures, mesh reuse and disposal passed')
