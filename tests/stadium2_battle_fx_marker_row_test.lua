package.path="./?.lua;./?/init.lua;"..package.path

-- Owner +61C/+61D (84107998 primary/secondary markers) come from the last
-- dispatch row the owner loaded: a non-move entry keeps that row.
local Adapter=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_battle_adapter")
local Actor=require("mods.STADIUM2_IMPORTER.lib.battle_actor")

local checks=0
local function ok(value,message)
  checks=checks+1
  if not value then error("FAIL "..message,0) end
end

ok(Adapter.markerRow(nil,{moveId=33})==32,"a move effect uses its own row")
ok(Adapter.markerRow({nativeMarkerRow=32},{moveId=0x125})==32,
  "a non-move entry uses the owner's last loaded row")
ok(Adapter.markerRow({},{moveId=0x125})==nil,"no row before the first load")

-- 271 rows; row r bytes 2/3 = r % 200 + 1, r % 200 + 2.
local rows={}
for r=0,270 do
  local b={}
  for i=0,19 do b[i+1]=0 end
  b[3],b[4]=r%200+1,r%200+2
  rows[#rows+1]=string.char(unpack(b))
end
local model={fxDispatch=table.concat(rows),attachments={}}
local actor={renderer={model=model},nativeMarkerRow=254}
local scene={scene={actors={player=actor,enemy=actor}}}
local markers,reason=Adapter.emissionMarkers({flags=0,flags2=0},{moveId=0x125,
  sourceSide="player"},0,scene)
ok(markers and markers[1].label==55 and markers[2].label==56 and markers[2].secondary,
  "0x125 after a hit uses row 254's markers ("..tostring(reason)..")")
actor.nativeMarkerRow=nil
markers,reason=Adapter.emissionMarkers({flags=0,flags2=0},{moveId=0x125,sourceSide="player"},0,scene)
ok(markers==nil and reason:find("dispatch markers",1,true),"no loaded row is still reported")

-- The actor records the rows its loaders would write.
local rig={setMove=function() return true end,setContext=function() return true end,
  seekFrame=function() end}
local a=Actor.new("player")
a.renderer=rig
a:attack(33)
ok(a.nativeMarkerRow==32,"attack loads the move row")
ok(a.nativeScaleSource.row==32 and a.nativeScaleSource.byte==0x0F,"attack takes +661 from byte 0x0F")
a.context="idle"
a:hit(33)
ok(a.nativeMarkerRow==254,"the defender hit loads row 254")
ok(a.nativeScaleSource.row==32 and a.nativeScaleSource.byte==0x13,
  "the defender hit takes +661 from the received move's byte 0x13")
a.context="idle"
a:charge(256,3)
ok(a.nativeMarkerRow==256,"a charge turn loads its charge row")
a:release()
ok(a.nativeMarkerRow==nil,"a released actor has no loaded row")

print(("stadium2_battle_fx_marker_row_test: %d checks passed"):format(checks))
