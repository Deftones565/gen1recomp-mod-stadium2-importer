local prefix='mods.STADIUM2_IMPORTER.lib.'
local Rom=require(prefix..'stadium2_battle_fx_rom')
local VM=require(prefix..'stadium2_battle_fx_mips')
local Player=require(prefix..'stadium2_battle_fx_player')
local Resources=require(prefix..'stadium2_battle_fx_resources')
local Renderer=require(prefix..'renderer')
local file=io.open(os.getenv('STADIUM2_ROM') or 'mods/STADIUM2_IMPORTER/baseroms/stadium2.z64','rb')
if not file then assert(os.getenv('STADIUM2_REQUIRE_ROM')~='1');print('SKIP dynamic anchor ROM');return end
local rom=file:read('*a');file:close()
local catalog=assert(Rom.catalog(rom))
local vm=VM.new({{base=0x84100000,bytes=catalog.lifecycleAssets.fragment79},
  {base=0x80000400,bytes=rom:sub(0x1001,0xA8000)}})
local actor,desc,transform,rule=0x85000000,0x85001000,0x85002000,0x85003000
vm:write(desc+16,transform,4);vm:write(transform+16,rule,4)
vm:write(actor+0xA7,1,1);vm:write(actor+0xA8,1,2)
for index=0,1 do
  vm:write(rule,0,2);vm:write(rule+2,index,2)
  vm:putVector(actor+0xAC,{17+index,31,43})
  vm:call(0x84102750,{actor,desc})
  local p=vm:vector(0x8418C958+index*12)
  assert(p[1]==17+index and p[2]==31 and p[3]==43)
  vm:write(rule,1,2);vm:putVector(actor+0xAC,{99,99,99})
  vm:call(0x84102750,{actor,desc})
  assert(vm:vector(0x8418C958+index*12)[1]==17+index,'reader must not overwrite')
end
local function emitter(start,mode)
  return {descriptorKind='particle',mode=mode,start=start,particleCount=1,repeats=1,
    flags=0x20080,flags2=0,geometry={nativeGeometry=true},
    transform={nativeAnchorTable={mode=mode,index=0}},
    material={shapeId=47,nativeEndAge=10}}
end
local point={7,11,13}
local loads,poses=0,0
local player=Player.new({catalog={programs={[1]={id=1,records={
  {opcode=4,emitter=emitter(0,0)},{opcode=4,emitter=emitter(1,1)},{opcode=0}}}},
  moves={[1]={primaryDispatch={{kind='program',programId=1}},alternateDispatch={}}}},
  commonAnchorInputs=function()return {position={10,20,30},centerY=20,
    markers={[1]={10,20,30}},markerLabel=1}end,
  loadRenderer=function()
    loads=loads+1
    return {updatePose=function()poses=poses+1 end,attachmentPosition=function()return point end}
  end})
assert(player:trigger({moveId=1,sourceSide='player'}))
assert(player:dynamicAnchor(0)==nil,'no write during construction/draw')
player.runtime:step(1)
assert(player:dynamicAnchor(0)[1]==17)
local particles=player:snapshot().particles
assert(#particles==2 and particles[2].nativeAnchor[1]==17,'reader spawned after writer update')
point={27,11,13};player.runtime:step(1)
assert(player:snapshot().particles[2].nativeAnchor[1]==37,'reader follows persistent table')
assert(loads==1 and poses==2,'writer reuses renderer and runs once per simulation tick')
player:release()

-- Heal Bell is a retail writer/reader chain with an exported marker-1 model.
local resources=assert(Resources.resolve(rom,catalog.moves[215].resources))
local p=Player.new({catalog=catalog,
  commonAnchorInputs=function()return {position={0,0,0},centerY=0,
    markers={[1]={0,0,0}},markerLabel=1}end,
  loadRenderer=function(_,shape,animation)
    return assert(Renderer.new(assert(Resources.modelFromShape(
      assert(Resources.shapeFromResolved(resources,shape,animation)))),{flipY=false}))
  end,
  releaseRenderer=function(r)r:release()end})
assert(p:trigger({moveId=215,sourceSide='player'}))
p.runtime:step(40)
assert(p:dynamicAnchor(0),'retail model writes dynamic slot')
for _,d in ipairs(p:snapshot().diagnostics) do assert(d.code~='dynamic-anchor-write',d.message) end
p:release()
print('Dynamic anchors ROM: two native slots, writer/reader modes, 30 Hz ordering and retail Heal Bell model passed')
