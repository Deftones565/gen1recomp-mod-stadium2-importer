local Beam=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_beam")
local f=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_float")
local p={origin={1,2,3},velocity={2,-3,4},velocityScale=2,
  initialRadius=1,maxRadius=8,rotationIncrement=.25,radiusIncrement=2,
  growthDuration=5}
local s=Beam.new()
assert(#s.slots==4 and #s.slots[1].rings==10)
for i=1,4 do assert(Beam.spawn(s,p)==i) end
assert(Beam.spawn(s,p)==nil)
assert(s.slots[1].rings[1].velocity[2]==-6)
local a,b={0,0,0},{90,400,0}
assert(Beam.step(s,a,b,0)==0)
local rings=s.slots[1].rings
assert(rings[10].position[1]==22.5 and rings[10].position[2]==50)
assert(b[2]==400) -- endpoint clamping must not modify the caller's model data
assert(rings[1].radius==1 and rings[2].radius==3 and rings[10].radius==1)
for _=2,5 do Beam.step(s,a,b,0) end
assert(rings[10].position[1]==90 and rings[10].position[2]==200)
assert(rings[2].radius==4 and rings[3].radius==6 and rings[4].radius==8)
assert(rings[10].radius==1.5 and rings[4].angle==1.25)
-- Endpoints are sampled every tick; previous positions do not accumulate.
Beam.step(s,{10,0,0},{100,-20,0},0)
assert(rings[1].position[1]==10 and rings[10].position[2]==-20)
local snapshot=Beam.snapshot(s)
snapshot.slots[1].rings[1].position[1]=999
assert(rings[1].position[1]==10 and snapshot.drawReady==false)
-- A held finish signal starts the window once, not on every update.
local finish=Beam.new();Beam.spawn(finish,p)
for tick=1,32 do
  assert(Beam.step(finish,a,b,1)==0)
  assert(finish.slots[1].finishThreshold==31)
  assert(finish.slots[1].phase==(tick<16 and 1 or 2))
end
assert(finish.slots[1].rings[4].radius==f(.1))
assert(Beam.step(finish,a,b,1)==-1 and finish.slots[1].age==32)
-- No implicit timeout: the ROM waits for its controller signal.
local waiting=Beam.new();Beam.spawn(waiting,p)
for _=1,100 do assert(Beam.step(waiting,a,b,0)==0) end
assert(waiting.slots[1].phase==0)
-- The manager uses signed 16-bit ages, as the native sh/lh pair does.
waiting.slots[1].age=32767
Beam.step(waiting,a,b,0)
assert(waiting.slots[1].age==-32768)
print("beam simulation: pool, interpolation, radius profile, live endpoints, finish timing passed")
local Lifecycle=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_lifecycle")
for _,family in ipairs({0,5,18}) do
  local target={90,20,0}
  local manager=Lifecycle.new({resolveBeam=function()
    return {origin={0,0,0},direction={1,0,0},endpointA={0,0,0},endpointB=target}
  end})
  manager:spawn(family)
  manager:step(20)
  local state=manager:snapshot().instances[1].nativeState
  assert(state.slots[1].rings[10].position[1]==90)
  assert(state.slots[1].rings[1].velocity[1]==12)
  assert(state.slots[2].active==(family~=18))
  assert(state.slots[1].growthDuration==20 and state.slots[1].radiusIncrement==5)
  assert(#manager:diagnosticSnapshot()==0,"init/update have native implementations")
  target={180,40,0};manager:step(1)
  assert(manager:snapshot().instances[1].nativeState.slots[1].rings[10].position[1]==180)
  manager:draw()
  local diagnostics=manager:diagnosticSnapshot()
  assert(#diagnostics==1 and diagnostics[1].code=="unresolved-beam-camera",
    "missing glow camera remains explicit")
  manager:setNativeSignal(1);manager:step(33)
  assert(#manager:snapshot().packets==0)
end
local missing=Lifecycle.new();missing:spawn(0);missing:step(1)
assert(missing:diagnosticSnapshot()[1].code=="unresolved-beam-endpoints")
assert(not missing:snapshot().instances[1].nativeState,"missing model anchors cannot invent a beam")
local one=Beam.forFamily(0,{0,0,0},{1,0,0})
one.slots[1].draw.primary[1]=0
assert(Beam.forFamily(0,{0,0,0},{1,0,0}).slots[1].draw.primary[1]==200)
print("beam lifecycle: three setup/update routes, live resolver, diagnostics and expiry passed")
local scoped=Lifecycle.new({resolveBeam=function()
  return {origin={0,0,0},direction={1,0,0},endpointA={0,0,0},endpointB={90,0,0}}
end})
scoped:spawn(18,{effectId=11});scoped:spawn(18,{effectId=12})
assert(scoped:finishEffect(11))
scoped:step(33)
local live=scoped:snapshot()
assert(#live.packets==1 and live.packets[1].context.effectId==12,
  "finishing one move must not finish an overlapping move")
assert(scoped:finishEffect(13))
scoped:spawn(9,{effectId=13});scoped:step(27)
assert(#scoped:snapshot().packets==1,"delayed lifecycle inherits its move completion")
scoped:release();assert(next(scoped.finishedEffects)==nil)

local Rom=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_rom")
local Resources=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_resources")
local file=io.open(os.getenv("STADIUM2_ROM") or "mods/STADIUM2_IMPORTER/baseroms/stadium2.z64","rb")
if not file then
  assert(os.getenv("STADIUM2_REQUIRE_ROM")~="1","required ROM unavailable")
  print("SKIP: beam ROM unavailable");return
end
local rom=file:read("*a");file:close()
local catalog=assert(Rom.catalog(rom))
local Dispatch=require("mods.STADIUM2_IMPORTER.lib.animation_dispatch")
for _,species in ipairs({1,109,159,251}) do
  local rows=assert(Dispatch.forSpecies(rom,species))
  for _,index in ipairs({59,61,75,254}) do
    assert(#rows[index].raw==20 and rows[index].fxJoint==rows[index].raw:byte(3))
  end
end
local addresses={[0]={0x84187130,0x84187170},[5]={0x84187070,0x841870B0},[18]={0x84187230}}
for move,family in pairs({[60]=0,[62]=5,[76]=18}) do
  local state=Beam.forFamily(family,{0,0,0},{1,0,0})
  local resolved=assert(Resources.resolve(rom,catalog.moves[move].resources))
  for i,address in ipairs(addresses[family]) do
    local draw=state.slots[i].draw
    for word=1,8 do
      assert(draw.cycle0[word]==Rom.read32(rom,address+(word-1)*4))
      assert(draw.cycle1[word]==Rom.read32(rom,address+32+(word-1)*4))
    end
    for _,symbol in ipairs(draw.textures) do
      local texture=assert(Resources.beamTexture(resolved,symbol))
      assert(texture.format==4 and texture.size==0 and #texture.rgba==4096)
      local binding=resolved.shapes[symbol]
      local offset=binding.export.pointer-Resources.VRAM_BASE
      for pixel=0,1023 do
        local byte=binding.module:byte(offset+math.floor(pixel/2)+1)
        local intensity=(pixel%2==0 and math.floor(byte/16) or byte%16)*17
        assert(texture.rgba:byte(pixel*4+1)==intensity)
        assert(texture.rgba:byte(pixel*4+4)==255)
      end
    end
  end
end
assert(not Resources.beamTexture({shapes={}},19))
print("beam ROM: five layer combiners and all texture pixels match their resource exports")
local meshState=Beam.forFamily(18,{0,0,0},{1,0,0})
meshState.cameraEye={0,0,100}
for _=1,20 do Beam.step(meshState,{0,0,0},{90,0,0},0) end
local geometry=Beam.geometry(meshState)
assert(#geometry.layers==2 and geometry.layers[1].glow)
local strip,tube=geometry.layers[1],geometry.layers[2]
assert(strip.pos[13]==0 and strip.pos[16]==90,"glow center vertices stay on the endpoints")
assert(strip.pos[2]==40 and strip.pos[26]==-40,"glow outer vertices use twice the native width20")
assert(tube.pos[1]==0 and tube.pos[2]==0 and tube.pos[3]==1)
assert(tube.pos[244]==90,"last tube ring reaches endpointB")
assert(tube.uv[1]==0 and tube.uv[17]==1,"tube seam closes at raw S1024")
for i=1,6 do assert(tube.idx[i]==({1,10,2,10,11,2})[i]) end
local glowTexture=catalog.lifecycleAssets.beamGlow
for pixel=0,1023 do
  local value=rom:byte(Rom.romOffset(0x84188738)+pixel+1)
  assert(glowTexture.rgba:byte(pixel*4+1)==math.floor(value/16)*17)
  assert(glowTexture.rgba:byte(pixel*4+4)==value%16*17)
end
local Player=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_player")
local Renderer=require("mods.STADIUM2_IMPORTER.lib.renderer")
local Adapter=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_battle_adapter")
local finished,nextId={},0
local bridge=setmetatable({player={trigger=function()
  nextId=nextId+1;return nextId
end,finish=function(_,id) finished[#finished+1]=id;return true end}},Adapter)
assert(bridge:trigger(60,"player")==1 and #finished==0)
assert(bridge:trigger(62,"enemy")==2 and finished[1]==1)
assert(bridge:finish() and finished[2]==2)
assert(not bridge:finish() and #finished==2,"completion is sent once per triggered move")
local scene={world={actorSlots={player={-3,0,0},enemy={3,0,0}}},
  camera={eye={0,3,10}}}
for _,move in ipairs({60,62,76}) do
  local allocations,uploads,draws,releases=0,0,0,0
  local player=Player.new({catalog=catalog,resolveBeam=Adapter.beamInputs,
    contextForParticle=Adapter.placementContext,
    loadBeamTexture=function(id,symbol)
      return Resources.beamTexture(assert(Resources.resolve(rom,catalog.moves[id].resources)),symbol)
    end,
    createGeometryRenderer=function(model)
      allocations=allocations+1
      assert(#model.prims==(move==76 and 2 or 3))
      assert(model.prims[1].nverts==10 and model.prims[1].battleFxNoDepth)
      assert(model.prims[2].nverts==90 and #model.prims[2].idx==432)
      local renderer=assert(Renderer.new(model,{flipY=false}))
      local update=renderer.updatePose
      renderer.updatePose=function(self,force)uploads=uploads+1;return update(self,force)end
      renderer.drawScene=function(self,pass,matrix)
        assert(matrix[1]==.05 and matrix[4]==-3)
        local state=self:battleFxMaterialState(model.prims[2])
        assert(state.textures[2] and state.material.combiner.cycles==2)
        local gstate=self:battleFxMaterialState(model.prims[1])
        assert(not gstate.textures[2] and gstate.material.combiner.cycles==1)
        assert(#self.parts[2].rows==90)
        draws=draws+1;return true
      end
      return renderer
    end,
    releaseRenderer=function(r)releases=releases+1;r:release()end})
  player:draw(scene) -- supplies the host endpoint provider before triggering
  assert(player:trigger({moveId=move,sourceSide="player",targetSide="enemy"}))
  player.runtime:step(20)
  local built=player:draw(scene)
  -- One drawScene call: all parts share a blend class, and the player skips
  -- the pass with no parts.
  assert(built.drawn>=1 and draws==1 and allocations==1)
  local before=uploads;player:draw(scene)
  assert(uploads==before and allocations==1,"same frame reuses all beam meshes")
  player.runtime:step(1);player:draw(scene)
  assert(uploads>before and allocations==1)
  player.runtime.lifecycle:setNativeSignal(1);player.runtime:step(33);player:draw(scene)
  assert(releases==1);player:release();assert(releases==1)
end
print("beam renderer: three moves, tube/glow materials, persistent meshes and disposal passed")
