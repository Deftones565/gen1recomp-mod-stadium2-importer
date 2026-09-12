-- Run from the game root: love mods/STADIUM2_IMPORTER/tests/drivers/scenery_culling_visual
package.path=love.filesystem.getWorkingDirectory()..'/?.lua;'..package.path
function love.load()
 local ok,err=pcall(function()
 local C=require('mods.STADIUM2_IMPORTER.lib.scenery_chunks')
 local Camera=require('mods.STADIUM2_IMPORTER.lib.battle_camera')
 local Mat=require('mods.STADIUM2_IMPORTER.lib.renderer')
 local g=love.graphics
 -- Exercise the original static culling path independently of instancing.
 require("mods.STADIUM2_IMPORTER.lib.scenery_instances").available=function() return false end
 local fmt={{'VertexPosition','float',3},{'SurfaceNormal','float',3},{'SurfaceColor','float',3},{'SurfaceMaterial','float',1}}
 local shader=g.newShader([[
 varying vec3 shade;
 #ifdef VERTEX
 attribute vec3 SurfaceColor;uniform mat4 vp;
 vec4 position(mat4 tp,vec4 p){shade=SurfaceColor;return vp*p;}
 #endif
 #ifdef PIXEL
 vec4 effect(vec4 c,Image t,vec2 uv,vec2 px){return vec4(shade,1.);}
 #endif
 ]])
 local a=g.newCanvas(640,360);local b=g.newCanvas(640,360)
 for _,name in ipairs({'nature','cave','town','freshwater'}) do
  local scene=require('mods.STADIUM2_IMPORTER.lib.battle_'..name)
  local rows=scene.vertices();local original=g.newMesh(fmt,rows,'triangles','static');local chunks=C.new(g,fmt,rows,scene.groundVertices)
  local frame=Camera.frame(640,360)
  if name=='nature' then frame=scene.frame(frame) end
  for i=0,4 do
   local vp=frame.vp
   if i>0 then local angle=i*math.pi/2;vp=Mat.matMul(frame.projection,Mat.lookAt(math.cos(angle)*95,30,math.sin(angle)*95,0,6,0)) end
   for j,target in ipairs({a,b}) do
    g.setCanvas({target,depth=true});g.clear(0,0,0,1,true,true);g.setShader(shader);shader:send('vp','row',vp)
    g.setDepthMode('lequal',true);g.setMeshCullMode('none');g.setBlendMode('replace')
    if j==1 then g.draw(original) else chunks:draw(g,vp) end
   end
   g.setCanvas();g.setShader()
   local ai,bi=a:newImageData(),b:newImageData();local diff=0
   for y=0,359 do for x=0,639 do
    local ar,ag,ab=ai:getPixel(x,y);local br,bg,bb=bi:getPixel(x,y)
    if math.max(math.abs(ar-br),math.abs(ag-bg),math.abs(ab-bb))>1/255+.00001 then diff=diff+1 end
   end end
   print(name..' view '..i..': '..diff..' differing pixels')
   assert(diff==0,'visible geometry changed')
   ai:release();bi:release()
  end
  chunks:release();original:release();scene.release()
 end
 end)
 if not ok then print(err) end
 love.event.quit(ok and 0 or 1)
end
