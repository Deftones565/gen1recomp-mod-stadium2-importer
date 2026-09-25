package.path='./?.lua;./?/init.lua;'..package.path
local W=require('mods.STADIUM2_IMPORTER.lib.battle_weather')
local S=require('mods.STADIUM2_IMPORTER.lib.weather_surface')
local R=require('mods.STADIUM2_IMPORTER.lib.renderer')
S.build('test',{{-8,10,-8},{8,10,-8},{8,10,8},{-8,10,-8},{8,10,8},{-8,10,8}})
assert(S.height('test',0,0)==10,'rain missed roof')
local w=W.new('test','storm')
assert(w:surface(0,0)==10)
assert(w.addBody==nil,'weather must not query Pokemon collision volumes')
local types={}
for i=1,100 do
 w:makeBolt();types[w.boltType]=true
 assert(w.boltCount<=32)
 if w.boltType==1 then assert(w.boltCount==12) else assert(w.boltCount>12) end
end
assert(types[1] and types[2] and types[3],'missing lightning variation')
math.randomseed(67);local expected=math.random();math.randomseed(67)
local created,draws=0,0
local resource={release=function() end,send=function() end,setVertices=function(_,rows) assert(#rows==1464) end}
local g={newMesh=function() created=created+1;return resource end,newShader=function() created=created+1;return resource end,
 push=function() end,pop=function() end,setShader=function() end,setColor=function() end,setMeshCullMode=function() end,setBlendMode=function() end,
 setDepthMode=function(_,write) assert(not write) end,draw=function() draws=draws+1 end}
local frame={vp=R.identity(),view=R.identity()}
local flash=false
for i=1,200 do
 w:lighting({modelTint={.2,.2,.2},ambient={.3,.3,.3}},.1)
 w:draw(g,frame,.1,{},{},{})
 if w.flash>0 then flash=true end
end
assert(flash and created==2 and draws==200 and #w.drops==180)
assert(math.random()==expected,'weather consumed gameplay RNG')
-- A falling drop becomes a horizontal ripple at the roof, and its storage
-- is recycled after the short impact lifetime.
local drop=w.drops[1]
drop.x,drop.z,drop.y,drop.splash=0,0,10.01,0
w:draw(g,frame,.01)
assert(drop.splash>0 and drop.y==10.10,'drop missed scenery impact')
for j=1,6 do assert(w.rows[j][2]==10.10 and w.rows[j][5]>=2) end
for i=1,3 do w:draw(g,frame,.1) end
assert(w.drops[1]==drop and drop.splash==0,'impact slot was not reused')
local previous=w.bolts[1][1]
w:makeBolt()
assert(w.bolts[1][1]~=previous,'strike position did not vary')

local rain=W.new('test','rain')
for i=1,200 do rain:lighting({},.1);assert(rain.flash==0) end
w:release();assert(w.mesh==nil)
local I=require('mods.STADIUM2_IMPORTER.lib.importer');local option='storm'
I.bind({options={get=function() return option end}})
assert(I.weatherStyle()=='storm');option='off';assert(I.weatherStyle()=='off');option='invalid';assert(I.weatherStyle()=='off')
print('Scenery-only impacts, three lightning variants, bounded particle resources, RNG isolation, lightning timing and Off option passed')
