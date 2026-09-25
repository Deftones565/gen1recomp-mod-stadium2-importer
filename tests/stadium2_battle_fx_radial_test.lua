local Radial=require('mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_radial')
local Random=require('mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_random')
local f=require('mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_float')
local file=io.open(os.getenv('STADIUM2_ROM') or 'mods/STADIUM2_IMPORTER/baseroms/stadium2.z64','rb')
if not file then assert(os.getenv('STADIUM2_REQUIRE_ROM')~='1');print('SKIP radial ROM');return end
local rom=file:read('*a');file:close()
local VM=require('mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_mips')
local emitters={[4]=0x84156CCC,[6]=0x84157398,[21]=0x8415782C}
for family,address in pairs(emitters) do for _,scale in ipairs({.5,1.75}) do for _,sign in ipairs({-1,1}) do
  local nativeRandom,luaRandom=Random.new(432),Random.new(432)
  local origin={-90*sign,20,5};local direction={f(.8*sign),f(.25),f(-.15)}
  local vm=VM.new({{base=0x84100000,bytes=rom:sub(0x36F890+1,0x419480)}},{
    [0x84109544]=function(v)v.f[0]=VM.floatWord(scale)end,
    [0x8007AFA0]=function(v)v.r[2]=nativeRandom:next()end,
    [0x84169BA8]=function(v)v.r[2]=0 end,
    [0x84169DBC]=function()end, -- no auxiliary children in mode 2
    [0x84109780]=function(v)v:putVector(v.r[4],origin)end,
    [0x80073F70]=function(v)v:write(0x85700000,v.f[12],4);v.f[0]=VM.floatWord(math.sin(v:float(0x85700000)))end,
    [0x841569E0]=function(v)
      for k=1,3 do v:putFloat(v.r[k+3],origin[k])end
      v:putFloat(v.r[7],direction[1]);v:putFloat(v:read(v.r[29]+16,4),direction[2]);v:putFloat(v:read(v.r[29]+20,4),direction[3])
    end})
  local pool=0x85000000;vm:write(0x84187530,pool-0x3C8,4);vm:call(0x8415C530)
  local s=Radial.new(family)
  local function equal(a,b,label)
    assert(a==b,('family %d %s native %.12g lua %.12g'):format(family,label,a,b))
  end
  local function compare(tick)
    for i=1,10 do
      local at=pool+(i-1)*0x5E8;local slot=s.slots[i]
      equal(vm:read(at,2),slot and slot.active and 1 or 0,'active '..tick..'/'..i)
      if slot and slot.active then
        equal(vm:read(at+4,2),slot.age,'age');equal(vm:read(at+8,2),slot.mode,'mode')
        equal(vm:float(at+20),slot.maxRadius,'max radius');equal(vm:float(at+24),slot.rotation,'rotation')
        for c=1,4 do equal(vm:read(at+9+c,1),slot.primary[c],'primary') end
        for c=1,3 do equal(vm:read(at+13+c,1),slot.environment[c],'environment') end
        for j,n in ipairs(slot.nodes) do
          local node=at+0x48+(j-1)*0x48
          equal(vm:float(node),n.delay,'delay');equal(vm:float(node+8),n.radius,'radius')
          equal(vm:float(node+12),n.angle,'angle');equal(vm:read(node+4,1),n.alpha,'alpha')
          for k=1,3 do
            equal(vm:float(node+16+(k-1)*4),n.position[k],'position '..tick..'/'..j..'/'..k)
            equal(vm:float(node+28+(k-1)*4),n.velocity[k],'velocity '..tick..'/'..j..'/'..k)
          end
        end
      end
    end
    equal(nativeRandom.state,luaRandom.state,'RNG')
  end
  vm:call(address);Radial.spawn(s,origin,direction,scale,luaRandom);compare(0)
  for tick=1,180 do
    origin[1]=f(origin[1]+.125)
    if tick<120 and tick%7==0 then vm:call(address);Radial.spawn(s,origin,direction,scale,luaRandom) end
    equal(vm:call(0x8415DAE4),Radial.step(s,origin),'completion '..tick)
    compare(tick)
  end
end end end
print('Radial ROM oracle: three families, 20-node state, live anchors, RNG and expiry match at two scales')

local Rom=require('mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_rom')
local Renderer=require('mods.STADIUM2_IMPORTER.lib.renderer')
local Dispatch=require('mods.STADIUM2_IMPORTER.lib.animation_dispatch')
local Preview=require('mods.STADIUM2_IMPORTER.tests.stadium2_koffing_croconaw_visual.battle_fx')
local catalog=assert(Rom.catalog(rom))
assert(Rom.read32(rom,0x84187554)==0x220005,'native geometry flags')
assert(Rom.read32(rom,0x84187570)==0xFC309661 and Rom.read32(rom,0x84187574)==0x552EFF7F,'native combiner')
assert(Rom.read32(rom,0x84187584)==catalog.lifecycleAssets.ribbon.address,'shared native texture')
assert(Rom.read32(rom,0x841875B4)==0x0001C03C,'native 8x16 tile dimensions')
local rows=assert(Dispatch.forSpecies(rom,109));local raw={}
for i=0,270 do raw[#raw+1]=rows[i].raw end
local model={fxDispatch=table.concat(raw)}
local scene={world={actorSlots={player={x=-3,y=0,z=0},enemy={x=3,y=0,z=0}}},
  camera={eye={0,3,10}},scene={actors={player={renderer={model=model}},enemy={renderer={model=model}}}}}
local moves={[20]=4,[35]=4,[132]=4,[81]=6,[169]=6,[50]=21}
for move,family in pairs(moves) do for _,side in ipairs({'player','enemy'}) do
  local allocations,uploads,releases,draws=0,0,0,0
  local preview=Preview.new({rom=rom,releaseModel=function()end,importer={newRendererFromModel=function(mesh)
    allocations=allocations+1
    assert(#mesh.prims==10,'fixed native ribbon pool')
    for _,texture in ipairs(mesh.textures) do
      assert(texture.w==8 and texture.h==16 and texture.format==3 and texture.size==1)
      assert(texture.rgba==catalog.lifecycleAssets.ribbon.rgba,'native IA8 texture')
    end
    local renderer=assert(Renderer.new(mesh,{flipY=false}))
    local update=renderer.updatePose
    renderer.updatePose=function(self,force)uploads=uploads+1;return update(self,force)end
    renderer.drawScene=function(self,pass,matrix)
      draws=draws+1;assert(matrix[1]==.05 and matrix[4]==(side=='player' and -3 or 3))
      local p=mesh.prims[1];local state=self:battleFxMaterialState(p)
      assert(p.nverts==40 and p.nidx==114 and state.textures[1])
      assert(p.geometryMode==0x220005)
      assert(state.material.combiner.cycles==1)
      return true
    end
    local release=renderer.release
    renderer.release=function(self)releases=releases+1;return release(self)end
    return renderer
  end}})
  assert(preview:start(move,side,false,scene))
  for _=1,25 do preview:step() end
  local state=preview.player:snapshot().lifecycles.instances[1]
  assert(state.familyId==family and state.nativeState.kind=='rom-radial-state')
  -- One drawScene call: all parts share a blend class, and the player skips
  -- the pass with no parts.
  assert(preview:draw(scene).drawn==1 and allocations==1 and draws==1)
  for _,d in ipairs(preview.diagnostics) do
    assert(d.code~='unsupported-lifecycle-callback' and d.code~='unresolved-radial-endpoints',d.message)
  end
  local before=uploads;preview:draw(scene)
  assert(uploads==before and allocations==1,'redraw reuses geometry without advancing')
  local first=state.nativeState.slots[1].nodes[1].position[1]
  preview:step();preview:draw(scene)
  assert(uploads>before and allocations==1,'tick uploads into the persistent mesh')
  assert(preview.player:snapshot().lifecycles.instances[1].nativeState.slots[1].nodes[1].position[1]~=first)
  for _=27,180 do preview:step() end
  preview:draw(scene);assert(releases==1,'native expiry disposes the renderer')
  preview:release();assert(releases==1,'release is idempotent')
end end
print('Radial viewer: six move routes, both sides, texture format, persistent geometry and disposal passed')
