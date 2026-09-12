-- Run from the game root. Writes /tmp/stadium2-weather-storm.png.
package.path=love.filesystem.getWorkingDirectory()..'/?.lua;'..package.path
function love.load()
 local g=love.graphics
 local ok,err=pcall(function()
 local Lake=require('mods.STADIUM2_IMPORTER.lib.battle_freshwater')
 local Weather=require('mods.STADIUM2_IMPORTER.lib.battle_weather')
 local weather=Weather.new('freshwater','storm')
 local Camera=require('mods.STADIUM2_IMPORTER.lib.battle_camera')
 local W=require('mods.STADIUM2_IMPORTER.lib.battle_watercolor')
 local R=require('mods.STADIUM2_IMPORTER.lib.renderer')
 assert(R.compileMobileShaderAudit())
 if g.validateShader then assert(g.validateShader(true,Weather.source));assert(g.validateShader(true,R.MOBILE_SHADER_SOURCE)) end
 local assetMod={read=function(_,path) local f=assert(io.open(love.filesystem.getWorkingDirectory()..'/mods/STADIUM2_IMPORTER/'..path,'rb'));local s=f:read('*a');f:close();return s end}
 Lake.bind(assetMod);require('mods.STADIUM2_IMPORTER.lib.battle_nature').bind(assetMod)
 local frame=Lake.frame(Camera.frame(960,540));local target=g.newCanvas(960,540)
 for i=1,60 do weather:lighting({},.1) end
 local env=weather:lighting(Lake.lighting({daytime='NITE',light={-.4,-.8,-.4},modelTint={1,1,1}}),.05)
 g.setCanvas({target,depth=true});g.clear(.025,.035,.055,1,true,true)
 Lake.sky(g,960,540,env,frame);Lake.updateTorchShadows(g,{},{},{},env);Lake.draw(g,frame,env);Lake.drawEffects(g,frame)
 weather:draw(g,frame,.05,{},{},{})
 g.setCanvas();g.setShader()
 local result=W.resolve(target,'cel');local data=result:newImageData();local bytes=data:encode('png')
 local file=assert(io.open('/tmp/stadium2-weather-storm.png','wb'));file:write(bytes:getString());file:close()
 weather:release();Lake.endBattle()
 print('GLES weather shader validation and lake storm render passed')
 end)
 g.setCanvas();g.setShader();if not ok then print(err) end
 love.event.quit(ok and 0 or 1)
end
