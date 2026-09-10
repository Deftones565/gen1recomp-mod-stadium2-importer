package.path="./?.lua;./?/init.lua;"..package.path
local Nature=require("mods.STADIUM2_IMPORTER.lib.battle_nature")
assert(Nature.matches({environment="ROUTE",kind="wild",terrain="grass"}))
assert(Nature.matches({environment="TOWN",kind="trainer"}))
for _,ctx in ipairs({
 {environment="ROUTE",kind="wild",terrain="water"},
 {environment="ROUTE",kind="wild",battleType="fish",terrain="grass"},
 {environment="CAVE",kind="wild",terrain="grass"},
 {environment="INDOOR",kind="trainer"}, {},
}) do assert(not Nature.matches(ctx)) end
local seed=12345
math.randomseed(seed);local expected=math.random();math.randomseed(seed)
local vertices=Nature.vertices()
assert(math.random()==expected,"scenery must not consume game RNG")
assert(#vertices%3==0 and #vertices/3<350000,"bounded authored geometry")
local materials={}
for _,v in ipairs(vertices) do
 assert(#v==10)
 assert(v[10]>=0 and v[10]<=4)
 materials[v[10]]=true
 for _,n in ipairs(v) do assert(n==n and math.abs(n)<10000) end
end
for id=0,4 do assert(materials[id],"missing material class "..id) end
for i=1,#vertices,3 do
 assert(vertices[i][10]==vertices[i+1][10] and vertices[i][10]==vertices[i+2][10],
  "material must stay constant across a triangle")
end
local Importer=require("mods.STADIUM2_IMPORTER.lib.importer")
local value
Importer.bind({options={get=function(_,key) if key=="stadium2_environment" then return value end end}})
assert(Importer.environmentStyle()=="classic")
value="kenney";assert(Importer.environmentStyle()=="kenney")
value="invalid";assert(Importer.environmentStyle()=="classic")
print("Nature routing, RNG isolation, options and geometry budget passed: "..(#vertices/3).." triangles")

local Camera=require("mods.STADIUM2_IMPORTER.lib.battle_camera")
for _,size in ipairs({{1280,720},{720,1280},{2560,1080}}) do
 local original=Camera.frame(size[1],size[2])
 local frame=Nature.frame(original)
 assert(frame.eye~=original.eye and frame.letterbox==original.letterbox)
 for _,side in ipairs({"player","enemy"}) do
  local x,y=Camera.project(frame,size[1],size[2],Camera.positions[side])
  assert(x>0 and x<size[1] and y>0 and y<size[2],"Nature camera clips battler")
 end
end

-- Sky must ignore translation but retain rotation.
local Mat=require("mods.STADIUM2_IMPORTER.lib.renderer")
local base=Camera.frame(1280,720)
local shifted={projection=base.projection,view={}}
for i,v in ipairs(base.view) do shifted.view[i]=v end
shifted.view[4]=shifted.view[4]+90
shifted.view[8]=shifted.view[8]-30
shifted.view[12]=shifted.view[12]+12
local a,b=Nature.skyVP(base),Nature.skyVP(shifted)
for i=1,16 do assert(a[i]==b[i],"sky translated with camera") end
shifted.view=Mat.lookAt(-60,25,10,0,0,0)
local rotated=Nature.skyVP(shifted)
assert(rotated[1]~=a[1],"sky lost camera rotation")
