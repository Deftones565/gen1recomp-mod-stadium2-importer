local Fragment=require("mods.STADIUM2_IMPORTER.lib.fragment")
local Build=require("mods.STADIUM2_IMPORTER.lib.build")
local Pack=require("mods.STADIUM2_IMPORTER.lib.pack")
local Renderer=require("mods.STADIUM2_IMPORTER.lib.renderer")
local Adapter=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_battle_adapter")
local Layout=require("mods.STADIUM2_IMPORTER.lib.layout")
local Rom=require("mods.STADIUM2_IMPORTER.lib.rom")
local Extract=require("mods.STADIUM2_IMPORTER.lib.extract")
local Dispatch=require("mods.STADIUM2_IMPORTER.lib.animation_dispatch")
local Endpoints=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_endpoints")
local function b16(v)return string.char(math.floor(v/256)%256,v%256)end
local function b32(v)return b16(math.floor(v/65536))..b16(v%65536)end
local profileBytes=b32(0)..b32(0)..b32(0x42820000)..b32(0)..b32(0)
  ..b32(0x42890000)..string.rep("\0",24) -- native Koffing +08=65, +14=68.5
local profile=assert(Dispatch.battleProfile(profileBytes))
assert(profile.targetHeight==3.5 and profile.centerY==68.5)
assert(not Dispatch.battleProfile(profileBytes:sub(2)))
local native={position={10,20,30},marker={40,999,60},centerY=68.5,
  targetHeight=3.5,offset={-3,4,5},rotation={0,0,1,0,1,0,-1,0,0}}
local p=Endpoints.resolve(native,true)
assert(p[1]==45 and p[2]==27.5 and p[3]==63,"target ignores marker Y; all offsets apply")
native.marker=nil
p=Endpoints.resolve(native,false)
assert(p[1]==15 and p[2]==72.5 and p[3]==33,"missing markers still receive offsets")
native.flags=2
assert(Endpoints.resolve(native,false)[2]==272.5,"source flag 2 is not target-clamped")
native.flags=4
p=Endpoints.resolve(native,true)
assert(p[3]==0 and p[2]==27.5)
native.position[2]=500
assert(Endpoints.resolve(native,true)[2]==30)
native.flags=0
assert(Endpoints.resolve(native,true)[2]==200)
native.position[2]=-500
assert(Endpoints.resolve(native,true)[2]==0)
native.flags=4
assert(Endpoints.resolve(native,false)[2]==4)
native.flags=6
assert(Endpoints.resolve(native,false)[2]==272.5,"flag 2 precedes flag 4")
local bone=string.char(0x1d,99,0,255)..b16(10)..b16(20)..b16(30)
  ..string.rep("\0",6)..b32(65536)..b32(65536)..b32(65536)
-- A graph push after the bone node makes that bone the current transform for
-- following leaf commands.  The decoder deliberately keeps the graph's
-- parent/current stack distinction; placing 0x24 immediately after 0x1d
-- would correctly resolve to the parent transform (-1), not the new bone.
local bytes=string.rep("\0",8).."FRAGMENT"..string.rep("\0",48)
  ..string.char(5,0,0,0)..bone..string.char(5,0,0,0)
  ..string.char(0x24,0)..b16(7)..string.char(1,0,0,0)
local model=assert(Fragment.extract(bytes,"marker-fixture",{directLayoutOffset=64}))
assert(#model.attachments==1 and model.attachments[1].label==7 and model.attachments[1].bone==0)
assert(model.bones[1].boneId==99,"marker label must not be interpreted as bone ID")
local shadowBytes=bytes:sub(1,64)..string.char(0x18,0,0,0,0,0,0,0)..bytes:sub(65)
local shadowModel=assert(Fragment.extract(shadowBytes,"shadow-fixture",{directLayoutOffset=64}))
assert(shadowModel.attachments[1].label==100 and shadowModel.attachments[1].bone==-1)
model.fxDispatch=string.rep(string.char(0,0,7)..string.rep("\0",17),271)
model.fxBattleProfile=profileBytes
model.fxContextScales=string.rep(string.char(17,31,53,79,101),16)
model.prims={{tex=0,cull=0,pos={0,0,0,1,0,0,0,1,0},uv={0,0,1,0,0,1},
  nrm={0,1,0,0,1,0,0,1,0},skin={0,0,0},idx={0,1,2},nidx=3,nverts=3}}
model.textures={{w=1,h=1,rgba="\255\255\255\255"}}
local ctx={};for i=1,#Build.CONTEXTS do ctx[i]=65535 end
local normal,shiny=Build.packPair(model,25,{},ctx,function()return true end)
for _,packed in ipairs({normal,shiny}) do
  local decoded=assert(Pack.parse(packed))
  assert(decoded.attachments[1].label==7 and decoded.fxDispatch==model.fxDispatch)
  assert(decoded.fxBattleProfile==profileBytes,"native profile survives normal/shiny cache")
  assert(decoded.fxContextScales==model.fxContextScales,"context scale bytes survive normal/shiny cache")
  local renderer=assert(Renderer.new(decoded,{flipY=false}))
  local p=assert(renderer:attachmentPosition(7))
  assert(p[1]==10 and p[2]==20 and p[3]==30)
  p[1]=999;assert(renderer:attachmentPosition(7)[1]==10)
  decoded.bones[1].t[1]=40;renderer:updatePose(true)
  assert(renderer:attachmentPosition(7)[1]==40,"marker follows the current pose")
  assert(not renderer:attachmentPosition(99))
  local host={visualActor=function()return {renderer=renderer}end,
    modelMatrix=function(_,side)return {0,0,2,side=="player" and 0 or 200,
      0,2,0,0,-2,0,0,0,0,0,0,1}end}
  local input=assert(Adapter.beamInputs({moveId=60},
    {scene={host=host},world={actorSlots={player={0,0,0},enemy={200,0,0}}},camera={eye={0,20,100}}}))
  assert(input.attachmentCount==2 and input.endpointA[1]==30 and input.endpointA[3]==-40)
  assert(input.endpointB[1]==130 and input.endpointB[3]==-40)
  assert(input.endpointB[2]==3.5 and not input.approximate,"native height replaces mesh half-height")
  -- The target marker stays row 254 while its signed offset follows row 251.
  local row=string.char(0,0,99)..string.rep("\0",9)..string.char(255,2,3)..string.rep("\0",5)
  decoded.fxDispatch=decoded.fxDispatch:sub(1,251*20)..row..decoded.fxDispatch:sub(252*20+1)
  input=assert(Adapter.beamInputs({moveId=60},
    {scene={host=host},world={actorSlots={player={0,0,0},enemy={200,0,0}}}}))
  assert(input.endpointB[1]==133 and input.endpointB[2]==5.5 and input.endpointB[3]==-39,
    "target gets rotated signed current-context offsets on all axes")
  decoded.attachments=shadowModel.attachments
  renderer:updatePose(true)
  local shadow=assert(renderer:attachmentPosition(100))
  assert(shadow[1]==0 and shadow[2]==0 and shadow[3]==0,"root shadow uses the root transform")
  renderer:release()
end
model.attachments=nil;model.fxDispatch=nil;model.fxBattleProfile=nil;model.fxContextScales=nil
assert(not assert(Pack.parse(Build.pack(model,25,{},ctx))).attachments,"legacy metadata remains valid")

-- Validate the two models used by the visual viewer against the real dispatch
-- rows.  Dispatch entries are indexed by their numeric move/context ID; the
-- target context 254 therefore uses rows[254], matching the overlay's
-- `context * 0x14 + 2` lookup. Context 255 carries shadow-node marker 100.
local romPath=os.getenv("STADIUM2_ROM") or "mods/STADIUM2_IMPORTER/baseroms/stadium2.z64"
local romFile=io.open(romPath,"rb")
if not romFile then
  assert(os.getenv("STADIUM2_REQUIRE_ROM")~="1","required ROM unavailable")
  print("attachment markers: synthetic graph/cache/pose checks passed (ROM unavailable)")
  return
end
local rom=assert(Rom.normalise(romFile:read("*a")));romFile:close()
for species=1,Dispatch.ARCHIVE_RECORDS do
  assert(Dispatch.battleProfile(Dispatch.battleProfileBytes(rom,species)))
end
assert(Dispatch.battleProfile(Dispatch.battleProfileBytes(rom,109)).targetHeight==3.5)
assert(Dispatch.battleProfile(Dispatch.battleProfileBytes(rom,159)).targetHeight==26.5)
local archive=assert(Rom.archiveAt(rom,Layout.MODEL_TABLE_START))
local function extractSpecies(species)
  local record=assert(archive.records[species+1])
  local decoded=assert(Rom.decompress(assert(Rom.recordBytes(rom,record))))
  local info=assert(Extract.fragmentInfo(decoded))
  decoded=Extract.runtimeFragmentForSpecies(rom,species,decoded)
  Fragment.setBase(info.sourceBase)
  return assert(Fragment.extract(decoded,"attachment-rom-"..species))
end
local function markerSet(model)
  local set={}
  for _,marker in ipairs(model.attachments or {}) do set[marker.label]=true end
  return set
end
local function checkRomModel(species,targetLabel)
  local extracted=extractSpecies(species)
  local labels=markerSet(extracted)
  local rows=assert(Dispatch.forSpecies(rom,species))
  for _,moveId in ipairs({60,62,76}) do
    local row=assert(rows[moveId-1])
    assert(labels[row.fxJoint],("species %d move %d dispatch label %d missing"):format(
      species,moveId,row.fxJoint))
  end
  local target=assert(rows[254]) -- context 254 (hit)
  assert(target.fxJoint==targetLabel)
  assert(labels[target.fxJoint],("species %d target marker %d missing"):format(
    species,target.fxJoint))
  local special=assert(rows[255])
  assert(special.fxJoint==100 and labels[special.fxJoint],
    ("species %d special context 255 must resolve shadow marker 100"):format(species))
  return extracted, target.fxJoint
end
local _,targetK=checkRomModel(109,9)
local _,targetC=checkRomModel(159,9)
print(("attachment markers: ROM Koffing/Croconaw dispatch plus synthetic pack/cache and pose checks passed; "
  .."context 254 target labels %d/%d and context 255 shadow marker 100 present"):format(targetK,targetC))
