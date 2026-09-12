package.path='./?.lua;./?/init.lua;'..package.path
local N=require('mods.STADIUM2_IMPORTER.lib.visitor_navigation')
local B=require('mods.STADIUM2_IMPORTER.lib.visitor_behaviour')
local C=require('mods.STADIUM2_IMPORTER.lib.visitor_catalog')
local map=N.build('test',{{0,0,-10},{0,20,-10},{0,20,10}})
assert(not N.sweep(map,-20,1,0,20,1,0,2,5),'tunnelled through thin wall')
assert(N.sweep(map,-20,30,0,20,30,0,2,5),'clear flight above wall rejected')
assert(not N.free(nil,0,0,0,1,1),'unbuilt map must not permit unsafe visitors')
local seed=431
local function random() seed=seed*16807%2147483647;return seed/2147483647 end
for _,pair in ipairs({{'grass','nature'},{'town','town'},{'cave','cave'},{'freshwater','freshwater'}}) do
 local id,module=pair[1],pair[2]
 require('mods.STADIUM2_IMPORTER.lib.battle_'..module).vertices()
 local spawned=0
 for _,name in ipairs(C.pools[id]) do
  local gestures=0
  local actor={context='idle',play=function() end,renderer={
   worldMetrics=function() return {height=10,floor=0} end,
   bindBounds={minX=-3,maxX=3,minZ=-3,maxZ=3},
   setMove=function() gestures=gestures+1;return true end,
   setContext=function() gestures=gestures+1;return true end}}
  local v={name=name,actor=actor,age=0}
  local started=B.start(v,id,random)
  if started then
   spawned=spawned+1
   for i=1,900 do
    local x,y,z=v.x,v.y,v.z
    v.age=v.age+.1;B.update(v,.1,id,{v})
    assert(N.sweep(N.maps[id],x,y,z,v.x,v.y,v.z,v.radius,v.bodyHeight),id..' '..name..' clipped scenery')
   end
   assert(gestures>0,'visitor never used its authored animation')
  end
 end
 assert(spawned>=3,id..' insufficient safe visitor placements')
 print(id..': '..spawned..' species navigated actual scenery for 90 seconds each without collision')
end
N.clear('test');assert(not N.maps.test)
print('Swept collision, real scene occupancy, safe spawning and behaviour dispatch passed')
-- A gesture expanding into a wall must restore the last safe animation frame.
local occupancy=N.build('pose',{{8,0,-8},{8,20,-8},{8,20,8}})
local expanded=false;local restored=false
local r={animIndex=1,frame=3,
 poseBounds=function(_,out)
  out.minX,out.maxX,out.minY,out.maxY,out.minZ,out.maxZ=-1,expanded and 12 or 1,0,3,-1,1
  return out
 end,
 setAnimation=function(_,index) assert(index==1);restored=true end,
 seekFrame=function(_,frame) assert(frame==3);expanded=false end}
local v={motion='ground',x=0,y=0,z=0,modelScale=1,modelFloor=0,radius=2,bodyHeight=4,actor={renderer=r,context='idle'}}
assert(B.validate(v,'pose'));expanded=true;r.animIndex=2;r.frame=7
assert(not B.validate(v,'pose') and restored and not expanded,'unsafe animation was rendered through obstacle')
print('Animation envelope validation and safe-frame restoration passed')
