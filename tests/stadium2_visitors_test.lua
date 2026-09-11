package.path='./?.lua;./?/init.lua;'..package.path
local released=0
package.loaded['mods.STADIUM2_IMPORTER.lib.battle_actor']={new=function()
 return {load=function() return true end,play=function() end,update=function() end,
 release=function() released=released+1 end,renderer={bindBounds={minX=-1,maxX=1,minY=0,maxY=20,minZ=-1,maxZ=1},worldMetrics=function() return {height=20,floor=0} end}}
end}
local V=require('mods.STADIUM2_IMPORTER.lib.battle_visitors')
local identity={1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1}
local offscreen={vp=identity}
math.randomseed(123);local expected=math.random();math.randomseed(123)
local grass=V.new('grass','natural',123)
for i=1,2500 do grass:update(.1);grass:prune(offscreen);assert(#grass.active<=2) end
assert(math.random()==expected,'visitors changed gameplay RNG')
local resident=false
for _,v in ipairs(grass.active) do if v.name=='caterpie' then resident=true;assert(v.age>200) end end
assert(resident,'resident Caterpie disappeared')
local perch=require('mods.STADIUM2_IMPORTER.lib.woodland_perch')
local px,py,pz=perch.position()
local tx,tz=perch.treePosition(perch.u,perch.d)
assert(px==tx and pz==tz and py>perch.size*.5,'Caterpie must sit on its tree crown')
assert(math.abs(math.sqrt(px*px+pz*pz)-108)<.001,'perch missed the relocated forest perimeter')
for _,t in ipairs({0,1,20,200}) do
 local x,y,z,_,size=V.pose('caterpie',t,'grass')
 assert(x==px and y==py and z==pz and size==1,'resident must not float or grow off its perch')
end
for name in pairs(V.species) do
 for _,t in ipairs({0,1,7,10,14,17,22}) do
  local p={V.pose(name,t,'town')};assert(#p==5)
  for _,n in ipairs(p) do assert(type(n)=='number' and n==n and math.abs(n)<1000,name) end
 end
end
local cave=V.new('cave','preview',7)
local seen={}
for i=1,800 do cave:update(.1);cave:prune(offscreen);for _,v in ipairs(cave.active) do seen[v.name]=true;assert(v.name~='hooh') end end
assert(seen.zubat and seen.mew)
local town=V.new('town','preview',7)
for i=1,1100 do town:update(.1);town:prune(offscreen);for _,v in ipairs(town.active) do seen[v.name]=true end end
assert(seen.meowth and seen.pidgey and seen.hooh)
local count=#town.active;town:release();assert(#town.active==0 and released>=count)
local v=V.new('town','natural',1);v.spawn=function(self,name) self.spawned=name end
local rares=0
for seed=1,10000 do local s=V.new('town','natural',seed);s.spawn=v.spawn;s:update(.1);s.age=3;s:update(0)
 if s.spawned=='hooh' or s.spawned=='mew' then rares=rares+1 end
end
assert(rares>60 and rares<140,'rare appearance rate must be about 1%')
print('Visitor lifecycle, resident, scene pools, preview cycle, bounded actors, paths and independent RNG passed; rare rolls '..rares..'/10000')

local bounds={minX=-.5,maxX=.5,minY=-.5,maxY=.5,minZ=-.5,maxZ=.5}
assert(V.visible(identity,identity,bounds))
local moved={1,0,0,1.5,0,1,0,0,0,0,1,0,0,0,0,1}
assert(V.visible(identity,moved,bounds),'partly visible model at edge must remain')
moved[4]=2;assert(not V.visible(identity,moved,bounds))
local watched=V.new('town','natural',7);watched:spawn('meowth');watched.nextVisit=999
watched.active[1].age=25;watched.matrix=function() return identity end
watched.active[1].actor.renderer.bindBounds=bounds
watched:update(.1);watched:prune({vp=identity})
assert(#watched.active==1,'expired visitor disappeared on camera')
local _,_,_,_,size=V.pose('meowth',25,'town');assert(size==1,'visitor shrank on camera')
watched.matrix=function() return moved end;watched:prune({vp=identity})
assert(#watched.active==0,'expired offscreen visitor was not released')
print('On-camera retention, whole-model edge visibility, no exit shrinking and offscreen cleanup passed')
