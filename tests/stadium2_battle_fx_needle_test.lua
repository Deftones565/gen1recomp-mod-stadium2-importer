local Needle=require('mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_needle')
local Random=require('mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_random')
local f=require('mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_float')
local file=io.open(os.getenv('STADIUM2_ROM') or 'mods/STADIUM2_IMPORTER/baseroms/stadium2.z64','rb')
if not file then assert(os.getenv('STADIUM2_REQUIRE_ROM')~='1');print('SKIP needle ROM');return end
local rom=file:read('*a');file:close()
local VM=require('mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_mips')
local Rom=require('mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_rom')
local catalog=assert(Rom.catalog(rom));local asset=catalog.lifecycleAssets.needle
assert(#asset.pos==54 and #asset.idx==48 and #asset.texture.rgba==64)
assert(Rom.read32(rom,0x84188A88)==0xD9FFFFFF and Rom.read32(rom,0x84188A8C)==0x220405)
assert(Rom.read32(rom,0x84188AD8)==0xFC5098A1 and Rom.read32(rom,0x84188ADC)==0x44327F3F)
for _,species in ipairs({13,109}) do for _,sign in ipairs({-1,1}) do for _,height in ipairs({-5,25}) do
  local nativeRandom,luaRandom=Random.new(732),Random.new(732)
  local origin={-90*sign,height,5};local direction={f(.8*sign),f(.25),f(-.15)}
  local allocation=0x85200000
  local vm=VM.new({{base=0x84100000,bytes=rom:sub(0x36F890+1,0x419480)},
    {base=0x80000400,bytes=rom:sub(0x1001,0xA8000)}},{
    [0x80006DEC]=function(v)v.r[2]=allocation;allocation=allocation+v.r[4]end,
    [0x84156BA0]=function()end, -- camera matrix only
    [0x841094B0]=function(v)v.r[2]=species end,
    [0x8007AFA0]=function(v)v.r[2]=nativeRandom:next()end,
    [0x841569E0]=function(v)
      for k=1,3 do v:putFloat(v.r[k+3],origin[k])end
      v:putFloat(v.r[7],direction[1]);v:putFloat(v:read(v.r[29]+16,4),direction[2]);v:putFloat(v:read(v.r[29]+20,4),direction[3])
    end})
  local pool=0x85000000;vm:write(0x84187BD0,pool,4)
  vm:call(0x84158588)
  local s=Needle.new(origin,direction,species,luaRandom)
  local function equal(a,b,label)assert(a==b,('%s native %.12g lua %.12g'):format(label,a,b))end
  local function compare(tick)
    local slot=s.slots[1]
    equal(vm:read(pool,2),slot.active and 1 or 0,'active '..tick)
    equal(vm:read(pool+2,2),slot.age,'age')
    equal(vm:float(pool+0x418),slot.scale,'scale')
    equal(vm:float(pool+12),slot.maxRadius,'max radius')
    equal(vm:float(pool+16),slot.rotation,'rotation')
    for j,n in ipairs(slot.nodes) do
      local at=pool+0x1C+(j-1)*0x44
      equal(vm:read(at,1),n.alpha,'alpha');equal(vm:float(at+4),n.radius,'radius')
      equal(vm:float(at+8),n.angle,'angle '..tick..'/'..j)
      for k=1,3 do
        equal(vm:float(at+12+(k-1)*4),n.position[k],'position '..tick..'/'..j..'/'..k)
        equal(vm:float(at+24+(k-1)*4),n.velocity[k],'velocity')
      end
    end
    equal(nativeRandom.state,luaRandom.state,'RNG')
    local g=Needle.geometry(s,asset)
    assert(#g.layers==8 and #g.layers[2].idx==84)
    for i=2,#g.layers[2].pos,3 do assert(g.layers[2].pos[i]>=0,'native trail clamps to ground')end
    if not slot.active or slot.nodes[1].position[2]<=0 then
      assert(g.layers[1].color[4]==0,'hidden needle head')
    end
    if slot.active and (tick<=1 or tick%10==0) then
      allocation=0x85200000
      vm:call(0x84165CC0,{0x85400000},1000000)
      local vertices=vm:read(pool+0x14,4)
      for j=0,29 do
        for k=0,2 do
          local value=vm:read(vertices+j*16+k*2,2)
          if value>=32768 then value=value-65536 end
          equal(value,g.layers[2].pos[j*3+k+1],'draw vertex '..tick..'/'..j..'/'..k)
        end
        for c=0,3 do equal(vm:read(vertices+j*16+12+c,1),g.layers[2].color[j*4+c+1],'draw color')end
      end
      if slot.nodes[1].position[2]>0 then
        local matrix={}
        for j=0,15 do
          local high=vm:read(0x85200000+j*2,2)
          if high>=32768 then high=high-65536 end
          matrix[j+1]=high+vm:read(0x85200020+j*2,2)/65536
        end
        for j=0,17 do for k=1,3 do
          local expected=matrix[12+k]
          for axis=0,2 do expected=expected+asset.pos[j*3+axis+1]*matrix[axis*4+k] end
          assert(math.abs(expected-g.layers[1].pos[j*3+k])<.02,'head transform differs from native fixed matrix')
        end end
      end
    end
  end
  compare(0)
  for tick=1,55 do equal(vm:call(0x84165C2C),Needle.step(s),'update return');compare(tick)end
end end end
print('Needle ROM oracle: 15 nodes, RNG, Weedle scale, both directions, expiry, draw vertices/colors and head transforms match')

local Renderer=require('mods.STADIUM2_IMPORTER.lib.renderer')
local Dispatch=require('mods.STADIUM2_IMPORTER.lib.animation_dispatch')
local Preview=require('mods.STADIUM2_IMPORTER.tests.stadium2_koffing_croconaw_visual.battle_fx')
local rows=assert(Dispatch.forSpecies(rom,109));local raw={}
for i=0,270 do raw[#raw+1]=rows[i].raw end
local model={species=109,fxDispatch=table.concat(raw)}
local scene={world={actorSlots={player={x=-3,y=1,z=0},enemy={x=3,y=1,z=0}}},
  camera={eye={0,3,10}},scene={actors={player={renderer={model=model}},enemy={renderer={model=model}}}}}
for _,move in ipairs({40,41,42}) do for _,side in ipairs({'player','enemy'}) do
  local allocations,uploads,releases=0,0,0
  local meshSeen
  local preview=Preview.new({rom=rom,releaseModel=function()end,importer={newRendererFromModel=function(mesh)
    if mesh.file~='stadium2-lifecycle-beam' then
      local renderer=assert(Renderer.new(mesh,{flipY=false}))
      renderer.drawScene=function()return true end
      return renderer
    end
    allocations=allocations+1;meshSeen=mesh
    assert(#mesh.prims==8 and #mesh.textures==4,'persistent four-slot head/trail pool')
    assert(mesh.textures[1].rgba==asset.texture.rgba)
    assert(mesh.prims[1].lighting and mesh.prims[1].nidx==48)
    assert(mesh.prims[2].nverts==30 and mesh.prims[2].nidx==84)
    assert(mesh.prims[2].tex==-1 and mesh.prims[2].battleFxTextures[1]==nil,'native shade-only trail')
    local renderer=assert(Renderer.new(mesh,{flipY=false}))
    local update=renderer.updatePose
    renderer.updatePose=function(self,force)uploads=uploads+1;return update(self,force)end
    renderer.drawScene=function(self,pass,matrix)
      assert(matrix[1]==.05 and matrix[4]==(side=='player' and -3 or 3));return true
    end
    local release=renderer.release
    renderer.release=function(self)releases=releases+1;return release(self)end
    return renderer
  end}})
  assert(preview:start(move,side,false,scene))
  for _=1,15 do preview:step() end
  local instances=preview.player:snapshot().lifecycles.instances
  assert(instances[1].familyId==17 and instances[1].nativeState.kind=='rom-needle-state')
  local result=preview:draw(scene)
  local messages={}
  for _,d in ipairs(result.diagnostics or {}) do messages[#messages+1]=d.code..': '..d.message end
  assert(result.drawn>=1 and allocations==1,table.concat(messages,'\n'))
  local before=uploads;local x=meshSeen.prims[1].pos[1]
  preview:draw(scene);assert(uploads==before and allocations==1,'redraw does not simulate')
  preview:step();preview:draw(scene)
  assert(uploads>before and allocations==1 and meshSeen.prims[1].pos[1]~=x,'motion uploads into persistent model')
  for _,d in ipairs(preview.diagnostics) do
    assert(d.code~='unsupported-lifecycle-callback' and d.code~='unresolved-needle-endpoints' and d.code~='unresolved-needle-model',d.message)
  end
  for _=17,80 do preview:step()end
  preview:draw(scene);assert(releases==1,'expiry releases mesh')
  preview:release();assert(releases==1)
end end
print('Needle viewer: Poison Sting, Twineedle and Pin Missile, both sides, persistent ROM mesh and disposal passed')
