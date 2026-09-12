package.path='./?.lua;./?/init.lua;'..package.path
local Cache=require('mods.STADIUM2_IMPORTER.lib.environment_cache')
local calls,allocations,pushed,released=0,0,0,0
local g={push=function() pushed=pushed+1 end,pop=function() pushed=pushed-1 end,
 newCanvas=function() allocations=allocations+1;return {release=function() released=released+1 end} end,
 setCanvas=function() end,clear=function() end,origin=function() end,setScissor=function() end}
local scene={lighting=function(e) return e end,sky=function() calls=calls+1 end,
 castShadow=function() calls=calls+1 end,updateTorchShadows=function() calls=calls+1 end,
 draw=function() calls=calls+1 end,drawEffects=function() end,endBattle=function() end}
local selection={mode='environment',scene=scene,id='test'}
assert(Cache.prepare(g,selection));assert(calls==8 and allocations==1 and released==1 and pushed==0)
for i=1,20 do scene.endBattle();assert(Cache.prepare(g,selection)) end
assert(calls==8 and allocations==1,'encounters rebuilt a ready map')
assert(not Cache.prepare(g,{mode='classic'}));assert(allocations==1)
Cache.reset();scene.draw=function() error('simulated driver failure') end
assert(not Cache.prepare(g,selection));assert(Cache.failed.test and pushed==0 and released==2)
assert(not Cache.prepare(g,selection));assert(allocations==2,'failure retried every frame')
Cache.reset();assert(next(Cache.ready)==nil and next(Cache.failed)==nil)
local E=require('mods.STADIUM2_IMPORTER.lib.battle_environment')
local old=E.select
E.select=function(ctx,style,arenas,env,test,arena)
 assert(ctx.kind=='wild' and style=='kenney' and test=='automatic' and arena==false)
 return {mode='environment',scene=scene,id=ctx.terrain}
end
scene.draw=function() end
Cache.location(g,{environment='ROUTE',waterType='freshwater'},'kenney','automatic',false)
assert(Cache.ready.grass and Cache.ready.water,'land and water candidates not prepared')
E.select=old
print('Preparation, encounter reuse, state restoration, failure backoff, reset and land/water routing passed')
