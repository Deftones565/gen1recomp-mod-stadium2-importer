local prefix='mods.STADIUM2_IMPORTER.lib.'
local VM=require(prefix..'stadium2_battle_fx_mips')
local Rom=require(prefix..'stadium2_battle_fx_rom')
local Endpoints=require(prefix..'stadium2_battle_fx_endpoints')
local Dispatch=require(prefix..'animation_dispatch')
local Adapter=require(prefix..'stadium2_battle_fx_battle_adapter')
local Lifecycle=require(prefix..'stadium2_battle_fx_lifecycle')
local Ribbon=require(prefix..'stadium2_battle_fx_ribbon')
local f=require(prefix..'stadium2_battle_fx_float')
local file=io.open(os.getenv('STADIUM2_ROM') or 'mods/STADIUM2_IMPORTER/baseroms/stadium2.z64','rb')
if not file then assert(os.getenv('STADIUM2_REQUIRE_ROM')~='1');print('SKIP height/ribbon ROM');return end
local rom=file:read('*a');file:close()
local catalog=assert(Rom.catalog(rom))
local images={{base=0x84100000,bytes=catalog.lifecycleAssets.fragment79},
  {base=0x80000400,bytes=rom:sub(0x1001,0xA8000)}}
local vm=VM.new(images)
local actor,other,state=0x85000000,0x85002000,0x85004000
vm:write(0x841911E0,other,4);vm:putVector(other+0x50,{111,63,222})
local cases=0
for _,include100 in ipairs({true,false}) do
  local markers={}
  local count=include100 and 11 or 10
  vm:write(actor+0xA7,count,1)
  for i=1,count do
    local label=i==11 and 100 or i
    markers[label]={label*2,label*3,label*4}
    vm:write(actor+0xA8+(i-1)*16,label,2)
    vm:putVector(actor+0xAC+(i-1)*16,markers[label])
  end
  for species=1,251 do
    local bytes=Dispatch.battleProfileBytes(rom,species)
    local profile=assert(Dispatch.battleProfile(bytes))
    vm:write(actor+0x1A,species,2)
    vm:putFloat(actor+0x64C,profile.bodyHeight)
    vm:call(0x8411EF90,{actor})
    vm:write(other+0x100,vm.f[0],4)
    local actual=Endpoints.anchorHeight({species=species,markers=markers,
      bodyHeight=profile.bodyHeight,specialHeightPoint={111,63,222}})
    assert(actual==vm:float(other+0x100),'native height species '..species)
    cases=cases+1
  end
end
assert(Endpoints.anchorHeight({species=95,markers={},bodyHeight=10})==nil)
assert(Endpoints.anchorHeight({species=51,markers={[100]={1,2,3}},bodyHeight=10})==nil)

-- Execute the real lifecycle setup wrappers: +194 is the current owner,
-- +198 the attacker, +19C the target. Only pose/offset and matrix hooks are
-- injected; actor selection, scale-byte access and ribbon initialization run.
local liveAnchor={90,80,70}
vm=VM.new(images,{
  [0x84156BA0]=function()end,
  [0x8411DCCC]=function(v)
    v:putVector(v.r[5],v:vector(v.r[4]+0x24))
  end,
  [0x84109630]=function()end,
  [0x8410971C]=function(v)v:putVector(v.r[4],liveAnchor)end,
})
vm:write(0x84187498,state,4)
vm:write(0x84190198,actor,4);vm:write(0x8419019C,other,4)
vm:putVector(actor+0x24,{11,22,33});vm:putVector(other+0x24,{44,55,66})
vm:write(actor+0x661,73,1);vm:write(other+0x661,126,1)
for _,owner in ipairs({actor,other}) do
  vm:write(0x84190194,owner,4)
  for id,address in pairs({[23]=0x84156F50,[26]=0x84157650,[27]=0x84157740}) do
    vm:call(address,{})
    local inputs={ribbonAnchor={11,22,33},ribbonOwnerAnchor=owner==actor and {11,22,33} or {44,55,66},
      ribbonOwnerScale=f((owner==actor and 73 or 126)*f(.01)),ribbonTargetScale=f(126*f(.01)),
      ribbonUpdateAnchor={90,80,70}}
    local lifecycle=Lifecycle.new({resolveBeam=function()return inputs end})
    local index=assert(lifecycle:spawn(id))
    local s=lifecycle.instances[index].ribbon
    assert(s.scale==vm:float(state+0x20) and s.radius==vm:float(state+0x14))
    for k=1,3 do assert(s.vertices[1][k]==vm:vector(state+8)[k]) end
    liveAnchor={90,80,70}
    vm:call(0x8415BD48,{0})
    lifecycle:step(1)
    for i=1,12 do for k=1,3 do
      assert(math.abs(s.vertices[i][k]-vm:float(state+0x38+(i-1)*16+(k-1)*4))<.0001,
        'native ribbon moving anchor vertex '..i..' axis '..k)
    end end
    local expected=Ribbon.new(id,{lifecycleScale=s.scale})
    Ribbon.step(expected,{90,80,70})
    for k=1,3 do assert(s.vertices[1][k]==expected.vertices[1][k]) end
    inputs.ribbonUpdateAnchor={190,180,170}
    liveAnchor=inputs.ribbonUpdateAnchor
    vm:call(0x8415BD48,{0})
    lifecycle:step(1);Ribbon.step(expected,inputs.ribbonUpdateAnchor)
    for k=1,3 do assert(s.vertices[1][k]==expected.vertices[1][k]) end
    for i=1,24 do for k=1,3 do
      assert(math.abs(s.vertices[i][k]-vm:float(state+0x38+(i-1)*16+(k-1)*4))<.0001)
    end end
    assert(#lifecycle:snapshot().diagnostics==0)
  end
end

-- Viewer bridge: distinguish source/target scale and owner center/posed marker.
local function model(species,scale)
  local row=string.char(0,0,9,255)..string.rep('\0',11)..string.char(scale)..string.rep('\0',4)
  return {species=species,fxDispatch=string.rep(row,271),
    fxBattleProfile=Dispatch.battleProfileBytes(rom,species)}
end
local actors={player={renderer={model=model(109,73),fxDispatchRow=0}},
  enemy={renderer={model=model(159,126),fxDispatchRow=251}}}
for _,a in pairs(actors) do
  a.renderer.attachmentPositions={[9]={7,80,5},[100]={3,100,4}}
  function a.renderer:attachmentPosition(label)return self.attachmentPositions[label]end
end
local scene={world={actorSlots={player={-7.5,0,0},enemy={7.5,0,0}}},scene={actors=actors}}
scene.scene.host={modelMatrix=function(_,side)
  return {.05,0,0,side=='player' and -7.5 or 7.5,0,.05,0,0,0,0,.05,0,0,0,0,1}
end}
for _,alternate in ipairs({false,true}) do
  local inputs=assert(Adapter.beamInputs({sourceSide='player',moveId=1,alternate=alternate},scene))
  assert(inputs.ribbonOwnerScale==f((alternate and 126 or 73)*f(.01)))
  assert(math.abs(inputs.ribbonUpdateAnchor[1]-(alternate and 307 or 7))<1e-5)
  assert(math.abs(inputs.ribbonUpdateAnchor[2]-80)<1e-5)
end
local input=Adapter.commonAnchorInputs({event={context={sourceSide='player',moveId=1}}},scene)
assert(input.anchorY==f(100-f(input.bodyHeight*.5)))
local Player=require(prefix..'stadium2_battle_fx_player')
for _,move in ipairs({20,35,50,81,132}) do
  for _,side in ipairs({'player','enemy'}) do
    local p=Player.new({catalog=catalog,sceneContext=scene,resolveBeam=Adapter.beamInputs,
      contextForParticle=Adapter.placementContext})
    assert(p:trigger({moveId=move,alternate=true,sourceSide=side}))
    p.runtime:step(2)
    local packets=p:packets(scene)
    assert(#packets.lifecyclePackets==1)
    for _,d in ipairs(packets.diagnostics) do
      assert(d.code~='approximate-ribbon-anchor' and d.code~='approximate-ribbon-scale'
        and d.code~='unresolved-ribbon-update-anchor',d.message)
    end
    p:release()
  end
end
print(('Height/ribbon ROM: %d species/marker cases, six lifecycle setups, live markers and viewer bridge passed'):format(cases))
