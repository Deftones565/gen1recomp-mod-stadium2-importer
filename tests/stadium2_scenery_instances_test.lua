package.path='./?.lua;./?/init.lua;'..package.path
local Instances=require('mods.STADIUM2_IMPORTER.lib.scenery_instances')
local Chunks=require('mods.STADIUM2_IMPORTER.lib.scenery_chunks')
local Camera=require('mods.STADIUM2_IMPORTER.lib.battle_camera')
local enabled,allocated,draws=false,0,0
local shader={send=function(_,name,value) if name=='sceneryInstanced' then enabled=value end end}
local g={getSupported=function() return {instancing=true} end,getShader=function() return shader end,
 newMesh=function(_,rows)
  allocated=allocated+1
  return {rows=rows,attributes={},attachAttribute=function(self,name,buffer,step) assert(step=='perinstance');self.attributes[name]=buffer end,
   setVertex=function(self,i,data) assert(i<=self.rows);self.last=data end,
   setDrawRange=function() end,release=function(self) self.released=true end}
 end,
 draw=function() assert(not enabled) end,
 drawInstanced=function(mesh,count) assert(enabled and count>0);assert(mesh.attributes.InstancePosition);draws=draws+1 end}
for _,name in ipairs({'nature','town','freshwater'}) do
 local scene=require('mods.STADIUM2_IMPORTER.lib.battle_'..name)
 local rows=scene.vertices();assert(#rows.instances>0)
 -- Reconstruct every instanced vertex independently and compare it to the
 -- original baked geometry, including material colours and rotated normals.
 for _,r in ipairs(rows.instances) do
  local d=r.data
  for i,p in ipairs(r.source) do
   local expected=rows[r.first+i-1]
   local lift=r.lift and p[10]==1 and (.8+.2*math.min(1,p[2]*3)) or 1
   local v={d[1]+(p[1]*d[5]+p[3]*d[6])*d[4],d[2]+p[2]*d[4],d[3]+(-p[1]*d[6]+p[3]*d[5])*d[4],
    p[4]*d[5]+p[6]*d[6],p[5],-p[4]*d[6]+p[6]*d[5],
    d[10]==1 and d[7] or p[7]*lift*d[7],d[10]==1 and d[8] or p[8]*lift*d[8],d[10]==1 and d[9] or p[9]*lift*d[9],p[10]}
   for k=1,10 do assert(math.abs(v[k]-expected[k])<1e-9,name..' instance changed vertex attribute '..k) end
  end
 end
 local mesh=Chunks.new(g,{},rows,scene.groundVertices)
 assert(mesh.baseVertices<#rows*.8,'expected substantial base-geometry savings')
 local before=allocated
 mesh:draw(g,Camera.frame(1280,720).vp)
 assert(draws>0 and not enabled)
 local firstDrawn=mesh.drawnTriangles
 mesh:draw(g,nil)
 assert(mesh.drawnTriangles==#rows/3,'unculled instance count differs')
 assert(allocated==before,'drawing allocated another GPU resource')
 print(name..': '..#rows.instances..' placements; '..mesh.baseVertices..' shared/static vertices vs '..#rows..'; view '..firstDrawn..' triangles')
 mesh:release();assert(mesh.static.mesh.released)
 for _,group in ipairs(mesh.groups) do assert(group.mesh.released and group.buffer.released) end
 -- Devices without instancing retain exactly the expanded geometry/culling.
 g.getSupported=function() return {instancing=false} end
 local fallback=Chunks.new(g,{},rows,scene.groundVertices)
 assert(fallback.mesh.rows==rows and fallback.totalTriangles==#rows/3)
 fallback:release();g.getSupported=function() return {instancing=true} end
end
print('Instance transforms, colours, normals, counts, culling, buffer reuse, release and fallback passed')
