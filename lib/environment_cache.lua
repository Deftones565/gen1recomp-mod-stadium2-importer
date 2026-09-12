-- Prepare location scenery before encounters, retaining the scene modules' GPU
-- caches. No battlers, battle canvases or visitor actors belong to this cache.
local Cache={ready={},failed={}}
local E=require('mods.STADIUM2_IMPORTER.lib.battle_environment')
function Cache.reset() Cache.ready={};Cache.failed={} end
function Cache.prepare(g,selection)
 if not (selection and selection.mode=='environment') then return false end
 local id,scene=selection.id,selection.scene
 if Cache.ready[id] then return true end
 if Cache.failed[id] or not (g and g.newCanvas) then return false end
 local target
 local pushed,pushError=pcall(g.push,'all')
 if not pushed then Cache.failed[id]=tostring(pushError);return false,pushError end
 local ok,err=pcall(function()
  -- Offscreen draws exercise the actual shader variants and GPU uploads.
  target=g.newCanvas(32,32,{format='rgba8',readable=true,dpiscale=1})
  local frame=require('mods.STADIUM2_IMPORTER.lib.battle_camera').frame(32,32)
  if scene.frame then frame=scene.frame(frame) end
  for _,day in ipairs({'DAY','NITE'}) do
   local env=scene.lighting({daytime=day,light={-.4,-.8,-.4},modelTint={1,1,1}})
   g.setCanvas({target,depth=true});g.clear(0,0,0,1,true,true);g.origin();g.setScissor()
   if scene.sky then scene.sky(g,32,32,env,frame) end
   scene.castShadow(g,frame.vp)
   scene.updateTorchShadows(g,{},{},{},env)
   g.setCanvas({target,depth=true});g.clear(0,0,0,1,true,true)
   scene.draw(g,frame,env)
   if scene.drawEffects then scene.drawEffects(g,frame)
   else require('mods.STADIUM2_IMPORTER.lib.battle_torches').draw(g,frame) end
  end
  scene.endBattle()
 end)
 g.pop()
 if target then target:release() end
 if ok then Cache.ready[id]=true else Cache.failed[id]=tostring(err) end
 return ok,err
end
function Cache.location(g,context,style,test,arenaTest)
 local ctx={kind='wild',terrain='grass'}
 for k,v in pairs(context or {}) do ctx[k]=v end
 local selection=E.select(ctx,style,false,nil,test,arenaTest)
 Cache.prepare(g,selection)
 -- A declared water area can lead to a different scene on the same map.
 if ctx.waterType then
  ctx.terrain='water'
  Cache.prepare(g,E.select(ctx,style,false,nil,test,arenaTest))
 end
end
return Cache
