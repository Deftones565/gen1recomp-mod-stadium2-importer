package.path="./?.lua;./?/init.lua;"..package.path
-- Ocean scene: selected for coastal water encounters, builds its scenery,
-- keeps both battle slots on log rafts above the sea, out in open water.
local E=require("mods.STADIUM2_IMPORTER.lib.battle_environment")
local Ocean=require("mods.STADIUM2_IMPORTER.lib.battle_ocean")
local checks=0
local function ok(v,m) checks=checks+1 if not v then error("FAIL "..m,0) end end
local sel=E.select({kind='wild',mapId='ROUTE_20',terrain='WATER'},'kenney')
ok(sel.mode=='environment' and sel.id=='ocean' and sel.scene==Ocean,"sea routes use the ocean scene")
local rows,ground=Ocean.vertices()
ok(#rows%3==0 and ground>0 and #rows>ground,"scenery builds with a ground range")
for _,z in ipairs({24,-24}) do
  ok((Ocean.coast(0,z))<-150,"battle slot z="..z.." is out in open water")
  local top=-math.huge
  for _,r in ipairs(rows) do
    if math.abs(r[1])<15 and math.abs(r[3]-z)<8 and r[10]==2 then top=math.max(top,r[2]) end
  end
  ok(top>-.95 and top<1,"raft at z="..z.." floats with its deck near the battler's feet")
end
print(("%d checks passed (Stadium 2 ocean scene)"):format(checks))
