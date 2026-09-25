local prefix='mods.STADIUM2_IMPORTER.lib.'
local Anchor=require(prefix..'stadium2_battle_fx_common_anchor')
local Motion=require(prefix..'stadium2_battle_fx_motion')
local VM=require(prefix..'stadium2_battle_fx_mips')
local Rom=require(prefix..'stadium2_battle_fx_rom')
local f=io.open(os.getenv('STADIUM2_ROM') or 'mods/STADIUM2_IMPORTER/baseroms/stadium2.z64','rb')
if not f then assert(os.getenv('STADIUM2_REQUIRE_ROM')~='1');print('SKIP common anchor ROM');return end
local rom=f:read('*a');f:close()
local catalog=assert(Rom.catalog(rom))
local vm=VM.new({{base=0x84100000,bytes=catalog.lifecycleAssets.fragment79},
  {base=0x80000400,bytes=rom:sub(0x1001,0xA8000)},
  {base=0x81100054,bytes=rom:sub(0x165CA5,0x165CE4)}},
  {[0x8411E1F8]=function(v)v.r[2]=0 end,
   [0x8411E1D4]=function(v)v.r[2]=-1 end})
local p,actor,desc,tableAddress=0x85000000,0x85001000,0x85002000,0x85003000
vm:write(p+8,actor,4);vm:write(p+0x10,desc,4)
vm:write(0x84193DD0,tableAddress,4)
vm:putVector(actor+0x24,{120,7,-60});vm:putFloat(actor+0x638,45)
vm:putFloat(actor+0x648,37);vm:putFloat(actor+0x650,5)
vm:write(actor+0x1A,109,2);vm:putFloat(actor+0x64C,10)
vm:write(actor+0xA7,2,1)
vm:write(actor+0xA8,3,2);vm:putVector(actor+0xAC,{123,55,-66})
vm:write(actor+0xB8,100,2);vm:putVector(actor+0xBC,{100,20,30})
local saved={-17,22,39};vm:putVector(0x84190020,saved)
local count=0
for _,flags in ipairs({0,0x20,0x80,0x100,0x400,0x100000,0x200000,
    0x1000000,0x4000000,0x40000,0x140000,0x240000,
    0x80000,0x180000,0x280000}) do
  for _,flags2 in ipairs({0,8,0x20,0x28}) do
    for _,actorFlags in ipairs({0,2,4,6}) do
      for _,label in ipairs({3,99}) do
        vm:write(desc+4,flags,4);vm:write(desc+8,flags2,4)
        vm:write(tableAddress+0x12,actorFlags,2);vm:write(p+0x7E,label,1)
        vm:putVector(p+0x2C,{9,8,7})
        vm:call(0x84104A00,{p})
        local result=Anchor.resolve({flags=flags,flags2=flags2},{position={120,7,-60},
          centerY=45,targetHeight=32,anchorY=15,flags=actorFlags,lane=-1,markerLabel=label,
          markers={[3]={123,55,-66},[100]={100,20,30}}},saved)
        local expected=vm:vector(p+0x38)
        for k=1,3 do assert(result.anchor[k]==expected[k],
          ('flags %X/%X actor %X label %d axis %d'):format(flags,flags2,actorFlags,label,k)) end
        assert(result.clearCommonOffset==(vm:float(p+0x2C)==0))
        assert(#result.diagnostics==0)
        count=count+1
      end
    end
  end
end
local anchor={1,2,3}
local options={resolveNativeAnchor=function()return {anchor=anchor}end}
for _,flags in ipairs({0,0x20000}) do
  anchor={1,2,3}
  local state=Motion.init({event={mode=0,flags=flags},nativeSpawnScale=1},options)
  anchor={9,8,7}
  state=Motion.step(state,1,options)
  assert(state.nativeAnchor[1]==(flags==0 and 1 or 9),'frozen/follow anchor')
end
print(('Common anchors ROM: %d flag/marker/actor-state cases and frozen/follow stepping passed'):format(count))

local Player=require(prefix..'stadium2_battle_fx_player')
local Adapter=require(prefix..'stadium2_battle_fx_battle_adapter')
local actorModel={renderer={model={fxDispatch=string.char(0,0,3,255)..string.rep('\0',16)},
  attachmentPositions={[3]={2,4,6}}}}
local scene={world={actorSlots={player={10,1,0}}},scene={host={
  visualActor=function()return actorModel end,
  modelMatrix=function()return {0,0,.05,10,0,.05,0,1,-.05,0,0,0,0,0,0,1}end}}}
local inputs=Adapter.commonAnchorInputs({event={context={moveId=1,sourceSide='player'}}},scene)
assert(inputs.markerLabel==3 and inputs.secondaryMarker==255)
assert(math.abs(inputs.markers[3][1]-206)<1e-6
  and math.abs(inputs.markers[3][2]-24)<1e-6
  and math.abs(inputs.markers[3][3]+2)<1e-6,'posed marker transformed to native world units')
local function emitter(start,flags2)
  return {mode=0,descriptorKind='particle',start=start,repeats=1,particleCount=1,
    flags=0x80,flags2=flags2,attachment={flags=0x80,flags2=flags2},
    geometry={nativeGeometry=true,velocityEntries={{0,9,0}}},
    material={shapeId=47},transform={}}
end
local input={position={10,20,30},centerY=40,markers={[3]={11,22,33}},markerLabel=3}
local player=Player.new({catalog={programs={[1]={id=1,records={
  {opcode=4,emitter=emitter(0,0x10)},{opcode=4,emitter=emitter(1,0x20)},{opcode=0}}}},
  moves={[1]={primaryDispatch={{kind='program',programId=1}},alternateDispatch={}}}},
  commonAnchorInputs=function()return input end,
  contextForParticle=Adapter.placementContext,resolvePlacement=Adapter.resolvePlacement})
assert(player:trigger({moveId=1,sourceSide='player'}))
input.markers[3]={100,200,300}
player.runtime:step(1)
local snapshot=player:snapshot()
assert(#snapshot.particles==2)
local writer,reader=snapshot.particles[1],snapshot.particles[2]
assert(writer.nativeAnchor[2]==22,'spawn anchor remains frozen')
assert(reader.nativeAnchor[2]==31 and reader.position[2]==0,'saved anchor includes only common offset, consumed once')
local ctx=Adapter.placementContext(reader,{})
local placed=Adapter.resolvePlacement(reader.attachment,ctx)
assert(placed.position[2]==31*.05,'viewer uses persistent native anchor')
assert(#ctx.diagnostics==0,'resolved anchors no longer report source-slot approximation')
player:release()
print('Common anchors player: saved-origin writer/reader, frozen model marker and viewer placement passed')
