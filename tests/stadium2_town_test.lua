package.path='./?.lua;./?/init.lua;'..package.path
local T=require('mods.STADIUM2_IMPORTER.lib.battle_town')
assert(T.matches({environment='TOWN',kind='trainer'}))
assert(T.matches({environment='TOWN',kind='wild',terrain='road'}))
for _,ctx in ipairs({{environment='TOWN',kind='wild',terrain='grass'},
 {environment='TOWN',kind='wild',terrain='water'},
 {environment='TOWN',kind='wild',battleType='fish'},
 {environment='INDOOR',kind='trainer'},{environment='ROUTE',kind='trainer'}, {}}) do assert(not T.matches(ctx)) end
math.randomseed(21);local expected=math.random();math.randomseed(21)
local rows=T.vertices();assert(math.random()==expected)
assert(#rows%3==0 and #rows/3<65000)
for _,v in ipairs(rows) do assert(#v==10);for _,n in ipairs(v) do assert(n==n and math.abs(n)<2000) end end
T.release();print('Town routing, geometry and RNG isolation passed: '..#rows/3)

local models=require('mods.STADIUM2_IMPORTER.assets.kenney_town.models')
local materials={}
for name,vs in pairs(models) do
 for i=1,#vs,3 do
  local id=vs[i][10]
  assert(id==vs[i+1][10] and id==vs[i+2][10],name..' mixes materials across triangle')
  materials[id]=true
 end
end
for _,id in ipairs({1,2,4,5,6}) do assert(materials[id],'missing town material '..id) end
print('Town plaster, roof, wood, foliage and trim material checks passed')

-- The source houses have garden plants below .20 and roof shells above .32.
-- Low extensions and eaves must use shingles too, even below the former .43 cutoff.
for _,name in ipairs({'building-type-a','building-type-b','building-type-c','building-type-f'}) do
 local roofVertices,lowRoofVertices,plants=0,0,0
 for _,v in ipairs(models[name]) do
  if v[10]==1 then
   assert(v[2]<.20,name..' roof/eaves incorrectly use foliage')
   plants=plants+1
  elseif v[10]==5 then
   assert(v[2]>.32,name..' garden plants incorrectly use shingles')
   roofVertices=roofVertices+1
   if v[2]<.43 then lowRoofVertices=lowRoofVertices+1 end
  end
 end
 assert(roofVertices>0 and lowRoofVertices>0 and plants>0,name..' lost roof or garden surfaces')
end
print('All four house roofs, low extensions and eaves use shingles; garden plants retain foliage')

assert(#T.lamps==2 and #models.lantern==316*3)
local glass=false
for _,v in ipairs(models.lantern) do if v[10]==7 then glass=true end end
assert(glass,'lantern must have separate emissive glass')
local Shadows=require('mods.STADIUM2_IMPORTER.lib.battle_torch_shadows')
local custom=Shadows.new({positions=T.lamps,power=function(night) return night and 1.6 or 0 end})
local uniforms={}
local shader={hasUniform=function() return true end,send=function(_,key,value) uniforms[key]=value end}
local g={getDimensions=function() return 1280,720 end,push=function() error('no GPU in unit test') end}
for _,night in ipairs({false,true,false}) do
 custom.night=night;custom.update(g,{}, {}, {}, {}, {});custom.bindModel(shader)
 assert(uniforms.localTorchPower==(night and 1.6 or 0))
 assert(uniforms.localTorch1[1]==T.lamps[1][1] and uniforms.localTorch1[2]==T.lamps[1][2]+1)
end
assert(require('mods.STADIUM2_IMPORTER.lib.battle_torches').positions[1][1]==-48,'town changed forest torch positions')
print('Street lamp positions, day/night power and forest light isolation passed')
