package.path='./?.lua;./?/init.lua;'..package.path
local L=require('mods.STADIUM2_IMPORTER.lib.visitor_locomotion')
local uploads=0
local r={bindBounds={minY=0,maxY=10,cx=0,cz=0},parts={{rows={{-2,0,0},{2,0,0},{0,8,0}},visible={true,true,true},mesh={setVertices=function() uploads=uploads+1 end}}}}
local v={name='pikachu',motion='ground',spec={25,6},actor={renderer=r}}
L.attach(v);assert(v.gait and r.visitorLocomotion==v.gait)
L.advance(v,.5,.1);L.apply(r)
assert(r.parts[1].rows[1][3]*r.parts[1].rows[2][3]<0,'feet must stride in opposite directions')
assert(r.parts[1].rows[3][3]==0,'upper body must not stride like a foot')
local phase=v.gait.phase
for i=1,60 do L.advance(v,0,.1) end
assert(v.gait.phase==phase and v.gait.amount<.001,'stationary Pokemon still walking')
assert(uploads==1)
local N=require('mods.STADIUM2_IMPORTER.lib.visitor_navigation')
local B=require('mods.STADIUM2_IMPORTER.lib.visitor_behaviour')
N.maps.town={cells={}}
local function make(name,x)
 local actor={renderer={worldMetrics=function() return {height=10,floor=0} end,bindBounds={minX=-1,maxX=1,minZ=-1,maxZ=1},setMove=function() return true end},play=function() end}
 local visitor={name=name,actor=actor,age=6}
 assert(B.start(visitor,'town',function() return .65 end))
 visitor.x,visitor.y,visitor.z=x,0,60;return visitor
end
local a,b=make('meowth',0),make('eevee',16)
B.update(a,.1,'town',{a,b})
assert(a.partner==b and b.partner==a and a.pauseUntil and b.pauseUntil,'nearby visitors did not greet')
local ax,bx=a.x,b.x
B.update(a,.1,'town',{a,b});B.update(b,.1,'town',{a,b})
assert(a.x==ax and b.x==bx,'greeting visitors slid around')
print('Distance-driven feet, stationary gait stop, body isolation and reciprocal stationary greetings passed')
