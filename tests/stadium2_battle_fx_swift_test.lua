local Swift=require('mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_swift')
local Random=require('mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_random')
local Lifecycle=require('mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_lifecycle')
local Beam=require('mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_beam')
local state=Swift.new();local rng=Random.new(123)
Swift.spawn(state,{-80,25,5},{1,.2,0},1,rng)
local initial=Swift.geometry(state)
assert(#initial.layers==28 and #initial.layers[1].pos==12)
local before=state.slots[1].nodes[1].position[1]
for _=1,11 do assert(Swift.step(state,0)==0) end
assert(state.slots[1].phase==1 and state.slots[1].nodes[1].position[1]==before)
Swift.step(state,0)
assert(state.slots[1].nodes[1].position[1]==before+20)
local geometry=Swift.geometry(state)
assert(geometry.layers[2].color[4]==54 and geometry.layers[2].color[80]==0)
local vertex=geometry.layers[2].pos[1]
Swift.geometry(state);Swift.geometry(state)
assert(Swift.geometry(state).layers[2].pos[1]==vertex,'redraw must not advance history')
local model=Beam.model(initial,{[39]={width=32,height=32,pixels=string.rep('\255',4096)}})
Beam.updateModel(model,geometry)
assert(model.prims[2].color[4]==54 and model.prims[1].pos==geometry.layers[1].pos)
for _=13,40 do assert(Swift.step(state,0)==0) end
assert(Swift.step(state,0)==-1)
local manager=Lifecycle.new({resolveBeam=function()return {origin={-80,20,0},swiftDirection={1,0,0},modelScale=1}end})
manager:spawn(2,{effectId=1});manager:step(39)
assert(#manager:snapshot().instances[1].nativeState.slots==14)
assert(manager:draw()[1].geometry.family==2)
assert(#manager:diagnosticSnapshot()==0)
manager:finishEffect(1);manager:step(75)
assert(#manager:draw()==0,'finished Swift releases its geometry')
print('Swift: motion, phase, trail history, mesh updates, 14-slot pool and cleanup passed')

-- Execute the actual US constructor/update instructions as an independent
-- oracle. Only actor inputs, model scale, signal and guRandom are hooked.
local file=io.open(os.getenv('STADIUM2_ROM') or 'mods/STADIUM2_IMPORTER/baseroms/stadium2.z64','rb')
if not file then assert(os.getenv('STADIUM2_REQUIRE_ROM')~='1');print('SKIP Swift ROM oracle');return end
local rom=file:read('*a');file:close()
local VM=require('mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_mips')
for _,scale in ipairs({.5,1,1.75}) do
  local nativeRandom=Random.new(432);local luaRandom=Random.new(432)
  local signal=0;local origin={-90,20,5};local direction={.8,.25,-.15}
  local vm=VM.new({{base=0x84100000,bytes=rom:sub(0x36F890+1,0x419480)}},{
    [0x84109544]=function(v)v.f[0]=VM.floatWord(scale)end,
    [0x8007AFA0]=function(v)v.r[2]=nativeRandom:next()end,
    [0x841094EC]=function(v)v.r[2]=signal end,
    [0x84156AB4]=function(v)
      for k=1,3 do v:putFloat(v.r[k+3],origin[k])end
      v:putFloat(v.r[7],direction[1]);v:putFloat(v:read(v.r[29]+16,4),direction[2]);v:putFloat(v:read(v.r[29]+20,4),direction[3])
    end})
  local pool=0x85000000;vm:write(0x84187840,pool,4)
  vm:call(0x84162660)
  local s=Swift.new()
  local function compare(tick)
    for i=1,14 do
      local at=pool+(i-1)*0x358;local slot=s.slots[i]
      assert(vm:read(at,2)==(slot and slot.active and 1 or 0),'active '..tick..'/'..i)
      if slot and slot.active then
        assert(vm:read(at+2,2)==slot.phase and vm:read(at+4,2)==slot.age,'phase/age')
        assert(vm:float(at+16)==slot.scale,'scale')
        for j,n in ipairs(slot.nodes) do
          local node=at+0x38+(j-1)*0x50
          assert(vm:float(node+8)==n.angle,'angle '..tick..'/'..j..' native '..vm:float(node+8)..' lua '..n.angle)
          assert(vm:read(node+4,1)==n.alpha,'alpha')
          for k=1,3 do
            assert(vm:float(node+12+(k-1)*4)==n.position[k],'position '..tick..'/'..i..'/'..k)
            assert(vm:float(node+24+(k-1)*4)==n.velocity[k],'velocity')
          end
        end
      end
    end
  end
  vm:call(0x84157128);Swift.spawn(s,origin,direction,scale,luaRandom);compare(0)
  for tick=1,170 do
    if tick==85 then signal=1 end
    if tick%3==0 then
      origin[1]=-origin[1]
      vm:call(0x84157128);Swift.spawn(s,origin,direction,scale,luaRandom)
    end
    local native=vm:call(0x84162C88);local actual=Swift.step(s,signal)
    assert(native==actual,'completion '..tick)
    compare(tick)
    if actual==-1 then break end
  end
end
print('Swift ROM oracle: constructor, RNG, all live nodes and completion match across three scales')
local Rom=require('mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_rom')
local Resources=require('mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_resources')
local Player=require('mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_player')
local Renderer=require('mods.STADIUM2_IMPORTER.lib.renderer')
local Adapter=require('mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_battle_adapter')
local Dispatch=require('mods.STADIUM2_IMPORTER.lib.animation_dispatch')
local catalog=assert(Rom.catalog(rom))
assert(Rom.read32(rom,0x84187918)==0xFB000000 and Rom.read32(rom,0x8418791C)==0xFFFF4014)
assert(Rom.read32(rom,0x84187850)==0x07C00000)
assert(Rom.read32(rom,0x84187910)==0xFC5098A1 and Rom.read32(rom,0x84187914)==0x44327F3F)
local resource=assert(Resources.resolve(rom,catalog.moves[129].resources))
local texture=assert(Resources.beamTexture(resource,39))
assert(#texture.rgba==4096)
local scene={world={actorSlots={player={-3,0,0},enemy={3,0,0}}},camera={eye={0,3,10}},scene={actors={}}}
local rows=assert(Dispatch.forSpecies(rom,109));local raw={}
for i=0,270 do raw[#raw+1]=rows[i].raw end
scene.scene.actors.player={renderer={model={fxDispatch=table.concat(raw)}}}
local inputs=assert(Adapter.beamInputs({moveId=129},scene))
local f=require('mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_float')
assert(inputs.modelScale==f(rows[128].raw:byte(16)*f(.01)))
assert(inputs.swiftOrigin[1]==-60 and inputs.swiftFrameOrigin[1]==-60)
local worldState=Swift.new(inputs.swiftFrameOrigin)
Swift.spawn(worldState,inputs.swiftOrigin,inputs.swiftDirection,inputs.modelScale,Random.new(2))
assert(worldState.slots[1].sign==1,'native world X, not source-relative X, controls acceleration')
local allocations,uploads,releases,draws=0,0,0,0
local player=Player.new({catalog=catalog,resolveBeam=Adapter.beamInputs,contextForParticle=Adapter.placementContext,
  loadBeamTexture=function(move,symbol)assert(move==129 and symbol==39);return texture end,
  createGeometryRenderer=function(model)
    allocations=allocations+1;assert(#model.prims==28)
    local renderer=assert(Renderer.new(model,{flipY=false}))
    local update=renderer.updatePose
    renderer.updatePose=function(self,force)uploads=uploads+1;return update(self,force)end
    renderer.drawScene=function(self)
      draws=draws+1
      assert(self:battleFxMaterialState(model.prims[1]).textures[1])
      return true
    end
    return renderer
  end,releaseRenderer=function(r)releases=releases+1;r:release()end})
player:draw(scene);assert(player:trigger({moveId=129,sourceSide='player',targetSide='enemy'}))
player.runtime:step(20);assert(player:draw(scene).drawn>=1 and allocations==1 and draws>0)
local before=uploads;player:draw(scene);assert(uploads==before)
player.runtime:step(1);player:draw(scene);assert(uploads>before and allocations==1)
player.runtime.lifecycle:setNativeSignal(1);player.runtime:step(75);player:draw(scene)
assert(releases==1);player:release();assert(releases==1)
print('Swift viewer path: ROM star texture, dispatch scale, persistent rendering and disposal passed')
-- The visual scene uses named coordinates, unlike the array-only fixture above.
-- Supply its scene before trigger: native init immediately resolves anchors.
local Preview=require('mods.STADIUM2_IMPORTER.tests.stadium2_koffing_croconaw_visual.battle_fx')
scene.world.actorSlots={player={x=-3,y=0,z=0},enemy={x=3,y=0,z=0}}
scene.camera.eye={x=0,y=3,z=10}
local named=assert(Adapter.beamInputs({moveId=129},scene))
assert(named.swiftOrigin[1]==-60 and named.cameraEye[3]==200)
local viewer=Preview.new({rom=rom,releaseModel=function()end,
  importer={newRendererFromModel=function(model)return Renderer.new(model,{flipY=false})end}})
for _,side in ipairs({'player','enemy'}) do
  assert(viewer:start(129,side,false,scene))
  viewer:step()
  local snapshot=viewer.player:snapshot()
  local live=snapshot.lifecycles.instances[1]
  assert(live and live.nativeState and live.nativeState.kind=='rom-swift-state')
  -- No graphics context is needed for renderer allocation/mesh upload.
  viewer:draw(scene)
  for _,d in ipairs(viewer.diagnostics) do
    assert(d.code~='unresolved-swift-endpoints' and d.code~='lifecycle-swift-input-error',d.message)
  end
  assert(next(viewer.player.renderers),'viewer creates the Swift renderer')
end
viewer:release()
print('Swift viewer regression: named coordinates and scene supplied before initialization passed')
