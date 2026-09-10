package.path="./?.lua;./?/init.lua;"..package.path
local Rom=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_rom")
local Runtime=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_runtime")
local Random=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_random")
local Motion=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_motion")
local Material=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_material")
local Native=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_native")
local single=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_float")
local file=io.open(os.getenv("STADIUM2_ROM") or
  "mods/STADIUM2_IMPORTER/baseroms/stadium2.z64","rb")
if not file then
  assert(os.getenv("STADIUM2_REQUIRE_ROM")~="1","required ROM unavailable")
  print("SKIP: common motion ROM fixtures (ROM unavailable)");return
end
local rom=file:read("*a");file:close()
local checks=0
local function check(v,m)checks=checks+1;assert(v,m)end
-- Guard the signed address and ramp branch that earlier audits transcribed
-- incorrectly. Fixtures below are tied to these actual US instructions.
check(Rom.read32(rom,0x841060C8)==0x3C078009 and
  Rom.read32(rom,0x841060D4)==0x24E78E50,"TB uses signed addiu")
check(Rom.read32(rom,0x84101E14)==0x14200025,"age<start skips the ramp")
check(Rom.read32(rom,0x841060EC)==0x3C014F80,"unsigned float correction is 2^32")
local catalog=assert(Rom.catalog(rom))
local movementMoves,colorMoves,particleColorMoves=0,0,0
local firstParticleTrack
for id=1,251 do
  local move=catalog.moves[id]
  local movement,color,particleColor=false,false,false
  for _,pid in ipairs({move.primary,move.alternate}) do
    local program=catalog.programs[pid]
    for _,record in ipairs(program and program.records or {}) do
      local emitter=record.emitter
      local native=emitter and emitter.transform and emitter.transform.nativeMotion
      local direction=native and native.direction
      if direction and (direction.mode==4 or direction.mode==5 or direction.mode==7 or direction.mode==8) then movement=true end
      if emitter and emitter.mode==2 and emitter.nativeColorTrack then color=true end
      local material=emitter and emitter.material
      if material and (material.nativePrimaryTrack or material.nativeSecondaryTrack) then
        particleColor=true
        firstParticleTrack=firstParticleTrack or material
      end
    end
  end
  if movement then movementMoves=movementMoves+1 end
  if color then colorMoves=colorMoves+1 end
  if particleColor then particleColorMoves=particleColorMoves+1 end
end
check(movementMoves==159,"shared movement covers 159 primary/alternate move routes")
check(colorMoves==104,"native color controllers decode for 104 move routes")
check(particleColorMoves==112,"particle color tracks decode for 112 move routes")
local track=firstParticleTrack.nativePrimaryTrack
check(track.mode==1 and track.period==16 and track.colors[2].age==4
  and track.colors[3].age==15,"Pound uses the ROM's age-keyed particle color track")
local materialState=Material.init(firstParticleTrack,{})
materialState=Material.step(materialState,{age=9})
check(materialState.primaryColor[1]==255 and materialState.primaryColor[4]==69,
  "Pound particle alpha interpolates ROM keys with native truncation")
materialState=Material.step(materialState,{age=40})
check(materialState.primaryColor[4]==32,"Pound holds its final particle color sample")
local geometryOnly=Native.particles({scheduled={{descriptorKind="particle",start=0,
  particleCount=1,geometry={nativeGeometry=true,selectors={position=1},
    positionEntries={{0x4000,0,0}}}}}},-1,0)[1]
check(geometryOnly.position==nil and geometryOnly.rotation[1]==0x4000,
  "an angle-only geometry record never leaks into position")
local tables=assert(catalog.trigTables)
check(#tables.tableA==4096 and #tables.tableB==4096,"both complete trig windows decoded")
check(tables.tableA[1]==0 and tables.tableB[1]==1
  and tables.tableA[1025]==1 and tables.tableB[2049]==-1,"ROM quadrant samples")
check(tables.tableA[2]==0.0015339801320806146
  and tables.tableB[2]==0.9999988079071045,"exact binary32 table samples")
local bytes=rom:sub(Rom.TRIG_ROM_START+1,Rom.TRIG_ROM_END)
local cached=assert(Rom.catalog(rom:sub(Rom.ROM_BASE+1,0x419480),bytes))
check(cached.trigTables.tableB[4096]==tables.tableB[4096],"cache and full ROM tables agree")
local Extract=require("mods.STADIUM2_IMPORTER.lib.extract")
local captured={}
local job=Extract.newJob(rom,function()return true end,function(name,data)
  captured[name]=data;return true
end,{species={}})
for _=1,20000 do
  if captured.battle_fx_trig or not job:step() then break end
end
check(captured.battle_fx_trig==bytes,"public importer job writes exact trig cache bytes")
check(Rom.trigTables(bytes:sub(2))==nil,"truncated table rejected")
check(Rom.trigTables(string.char(0x7f,0x80,0,0)..bytes:sub(5))==nil,
  "non-finite table rejected")
local rng=Random.new({tableA=tables.tableA,tableB=tables.tableB})
for _,mode in ipairs({2,3}) do
  local v=assert(rng:vector(mode,0,5,{0x4000,0,0}))
  check(math.abs(v[1])<1e-6 and v[2]==-5 and math.abs(v[3])<1e-6,
    "directional Y multiplies magnitude once for mode "..mode)
end
local v=assert(rng:vector(5,0,5,{0,0,0}))
check(v[1]==0 and v[2]==5 and v[3]==0,"mode5 uses actual paired ROM table")
local aliased=Runtime.new({catalog=catalog,
  randomOptions={tables={a=function()return 0 end,b=function()return 2 end}}})
local supplied=aliased.motionOptions.randomVector(5,{0,5},{angleContext={0,0,0}})
check(supplied[2]==10,"explicit trig aliases take precedence over catalog tables")
aliased:release()
local runtime=Runtime.new({catalog=catalog})
assert(runtime:trigger({moveId=7,sourceSide="enemy"}))
local first=runtime:snapshot().particles[1]
local ramp=first.material.nativeAlphaRamp
check(ramp and ramp.startAge==8 and ramp.step==32 and ramp.target==0,
  "Fire Punch fade is decoded from the actual ROM alpha record")
check(first.position[1]==0 and first.position[2]==0 and first.position[3]==5
  and first.velocity[3]==0,
  "Fire Punch direction initializes an offset, not a velocity")
local expected={0.30000001192092896,0.32500001788139343,
  0.35000002384185791,0.37500002980232239,0.40000003576278687,
  0.42500004172325134,0.45000004768371582,0.4750000536441803,0.5,0.5}
for frame=0,9 do
  local p=runtime:snapshot().particles[1]
  check(p.id==first.id and p.age==frame and p.scale[1]==expected[frame+1],
    "ROM scalar golden at tick "..frame)
  if frame==3 then
    check(p.position[1]==0 and p.position[2]==3 and p.position[3]==9.5,
      "Fire Punch accumulates ROM speed and vertical motion at tick3")
  end
  runtime:step(1)
end
local native=runtime:snapshot().nativeObjects
check(#native.slots==0 and #native.colorInstances==1,
  "native color visual persists after one-shot scheduler completion")
check(native.nativeColor[1]==0 and native.nativeColor[4]==76,
  "Fire Punch mode2 color interpolation truncates the actual ROM keys")
runtime:step(7)
local firstSurvives=false
for _,particle in ipairs(runtime:snapshot().particles) do
  if particle.id==first.id then firstSurvives=true end
end
check(not firstSurvives,"Fire Punch first particles retire after completing their native fade")
check(runtime:snapshot().nativeObjects.nativeColor[4]==128,
  "native color terminal frame holds the final authored alpha")
for _,d in ipairs(runtime:snapshot().diagnostics) do
  check(d.code~="invalid-random-vector-resolver" and d.code~="unsupported-random-vector-mode",
    "full ROM no longer reports missing directional trig")
end
local row={scale=1,nativeScaleUpdate={initial=1000,target=500,step=300,startAge=3}}
local down=Motion.init({scale=row})
for _=1,2 do down=Motion.step(down,1) end
check(down.scale[1]==1,"descending ramp waits until authored start")
down=Motion.step(down,1)
check(down.scale[1]==single(1-single(300*single(.001))),"descending ramp step")
down=Motion.step(down,1)
check(down.scale[1]==.5 and down.alive,"descending ramp clamps without expiring")
runtime:release()
print(("%d checks passed (Stadium 2 common motion ROM)"):format(checks))
