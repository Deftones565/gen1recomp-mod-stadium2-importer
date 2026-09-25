-- Run from the game root: love mods/STADIUM2_IMPORTER/tests/drivers/environment_cache_visual
package.path=love.filesystem.getWorkingDirectory()..'/?.lua;'..package.path
function love.load()
 local g=love.graphics
 local ok,err=pcall(function()
 local Cache=require('mods.STADIUM2_IMPORTER.lib.environment_cache')
 local Camera=require('mods.STADIUM2_IMPORTER.lib.battle_camera')
 -- ROM-backed flame loading is tested separately; this checks map resources.
 require('mods.STADIUM2_IMPORTER.lib.battle_torches').draw=function() return true end
 local count=0
 for _,name in ipairs({'newMesh','newShader','newImage','newCanvas'}) do
  local original=g[name];g[name]=function(...) count=count+1;return original(...) end
 end
 local frame=Camera.frame(640,360);local target=g.newCanvas(640,360)
 for _,name in ipairs({'nature','cave','town','freshwater'}) do
  local scene=require('mods.STADIUM2_IMPORTER.lib.battle_'..name)
  scene.bind({read=function(_,path) local f=assert(io.open(love.filesystem.getWorkingDirectory()..'/mods/STADIUM2_IMPORTER/'..path,'rb'));local data=f:read('*a');f:close();return data end})
  assert(Cache.prepare(g,{mode='environment',id=name,scene=scene}))
  local before=count
  for battle=1,3 do
   assert(Cache.prepare(g,{mode='environment',id=name,scene=scene}))
   local env=scene.lighting({daytime='NITE',light={-.4,-.8,-.4},modelTint={1,1,1}})
   g.setCanvas({target,depth=true});g.clear(0,0,0,1,true,true)
   scene.sky(g,640,360,env,frame);scene.castShadow(g,frame.vp)
   scene.updateTorchShadows(g,{},{},{},env)
   g.setCanvas({target,depth=true});scene.draw(g,frame,env)
   scene.endBattle()
  end
  assert(count==before,name..' rebuilt GPU resources: '..(count-before))
  print(name..': three encounters, zero new map meshes, shaders, textures or canvases')
  g.setCanvas();g.setShader();scene.release()
 end
 end)
 g.setCanvas();g.setShader();if not ok then print(err) end
 love.event.quit(ok and 0 or 1)
end
