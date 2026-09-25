-- Run from the game root. Writes /tmp/stadium2-fireflies-night.png.
package.path=love.filesystem.getWorkingDirectory()..'/?.lua;'..package.path
function love.load()
 local g=love.graphics
 local ok,err=pcall(function()
 local Lake=require('mods.STADIUM2_IMPORTER.lib.battle_freshwater')
 local F=require('mods.STADIUM2_IMPORTER.lib.battle_fireflies')
 local Camera=require('mods.STADIUM2_IMPORTER.lib.battle_camera')
 local W=require('mods.STADIUM2_IMPORTER.lib.battle_watercolor')
 local R=require('mods.STADIUM2_IMPORTER.lib.renderer')
 assert(R.compileMobileShaderAudit())
 if g.validateShader then assert(g.validateShader(true,F.source));assert(g.validateShader(true,R.MOBILE_SHADER_SOURCE)) end
 local assetMod={read=function(_,path) local f=assert(io.open(love.filesystem.getWorkingDirectory()..'/mods/STADIUM2_IMPORTER/'..path,'rb'));local s=f:read('*a');f:close();return s end}
 Lake.bind(assetMod);require('mods.STADIUM2_IMPORTER.lib.battle_nature').bind(assetMod)
 local frame=Lake.frame(Camera.frame(960,540));local target=g.newCanvas(960,540)
 local env=Lake.lighting({daytime='NITE',light={-.4,-.8,-.4},modelTint={1,1,1}})
 g.setCanvas({target,depth=true});g.clear(.025,.035,.055,1,true,true)
 Lake.sky(g,960,540,env,frame);F.update(env,8);Lake.draw(g,frame,env);Lake.drawEffects(g,frame)
 g.setCanvas();g.setShader()
 local result=W.resolve(target,'cel');local data=result:newImageData();local bytes=data:encode('png')
 local file=assert(io.open('/tmp/stadium2-fireflies-night.png','wb'));file:write(bytes:getString());file:close()
 Lake.endBattle();local values={}
 F.bindLighting({hasUniform=function() return true end,send=function(_,k,v) values[k]=v end})
 assert(values.fireflyEnabled==0,'lake lighting leaked after battle')
 print('Lake night shaders, billboard rendering, mobile shader compilation and lighting reset passed')
 end)
 g.setCanvas();g.setShader();if not ok then print(err) end
 love.event.quit(ok and 0 or 1)
end
