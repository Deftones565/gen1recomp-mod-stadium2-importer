package.path='./?.lua;./?/init.lua;'..package.path
local C=require('mods.STADIUM2_IMPORTER.lib.scenery_chunks')
local Mat=require('mods.STADIUM2_IMPORTER.lib.renderer')
local Shadows=require('mods.STADIUM2_IMPORTER.lib.battle_torch_shadows')
local Camera=require('mods.STADIUM2_IMPORTER.lib.battle_camera')
local identity=Mat.identity()
local calls={}
local g={newMesh=function(_,rows)
 return {rows=rows,setDrawRange=function(self,first,count) self.first,self.count=first,count end,
 release=function(self) self.released=true end}
end,draw=function(mesh) calls[#calls+1]={mesh.first,mesh.count} end}
assert(C.visible({minX=-2,maxX=2,minY=-2,maxY=2,minZ=-2,maxZ=2},identity),'geometry enclosing camera must survive')
assert(not C.visible({minX=2,maxX=3,minY=0,maxY=1,minZ=0,maxZ=1},identity))
for _,name in ipairs({'nature','cave','town','freshwater'}) do
 local scene=require('mods.STADIUM2_IMPORTER.lib.battle_'..name)
 local rows=scene.vertices();local chunks=C.new(g,{},rows,scene.groundVertices)
 assert(#chunks.mesh.rows==#rows,'geometry removed')
 for i,v in ipairs(rows) do assert(chunks.mesh.rows[i]==v,'original draw order changed') end
 local originals={}
 for i=1,#rows,3 do originals[rows[i]]={rows[i+1],rows[i+2]} end
 for i=1,#chunks.mesh.rows,3 do
  local original=assert(originals[chunks.mesh.rows[i]],'triangle added or duplicated')
  assert(original[1]==chunks.mesh.rows[i+1] and original[2]==chunks.mesh.rows[i+2],'triangle attributes or winding changed')
  originals[chunks.mesh.rows[i]]=nil
 end
 assert(next(originals)==nil,'triangle missing')
 local frame=Camera.frame(1280,720)
 if name=='nature' then frame=scene.frame(frame) end
 chunks:draw(g,frame.vp)
 print(string.format('%s default view: %d / %d triangles (%.1f%% skipped), %d submissions',name,
  chunks.drawnTriangles,chunks.totalTriangles,100*(1-chunks.drawnTriangles/chunks.totalTriangles),chunks.drawCalls))
 for i=0,23 do
  local angle=i*math.pi/12
  local vp=Mat.matMul(frame.projection,Mat.lookAt(math.cos(angle)*95,10+i*3,math.sin(angle)*95,0,6,0))
  for _,b in ipairs(chunks.groups) do
   assert(C.visible(b,vp)==Shadows.visibleInFace(vp,identity,b),'culling differs from eight-corner reference')
  end
  calls={};chunks:draw(g,vp)
  for _,b in ipairs(chunks.groups) do
   local included=false
   for _,call in ipairs(calls) do
    if b.first>=call[1] and b.first+b.count<=call[1]+call[2] then included=true end
   end
   assert(included or not C.visible(b,vp),'visible section missing from draw ranges')
  end
 end
 local lightVP=Mat.matMul(Mat.ortho(-58,58,-58,58,1,190),Mat.lookAt(55,90,55,0,4,0))
 chunks:draw(g,lightVP,name=='nature')
 print(string.format('%s sun view: %d / %d triangles, %d submissions',name,chunks.drawnTriangles,chunks.totalTriangles,chunks.drawCalls))
 chunks:draw(g,nil)
 assert(chunks.drawnTriangles==#rows/3 and chunks.drawCalls==1,'unculled ranges should merge')
 assert(chunks.mesh.first==nil,'draw range leaked')
 chunks:release();assert(chunks.mesh.released)
end
print('Exact triangle preservation, 360-degree culling, merged ranges and release passed')
