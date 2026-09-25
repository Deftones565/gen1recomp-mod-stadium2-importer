-- Static opaque scenery, partitioned once; all triangles and vertex attributes
-- are retained. Each pass culls against its own camera (including shadow views).
local C={};C.__index=C
local floor,min,max=math.floor,math.min,math.max
function C.new(g,format,vertices,groundCount)
 local Instances=require("mods.STADIUM2_IMPORTER.lib.scenery_instances")
 if vertices.instances and Instances.available(g) then return Instances.new(g,format,vertices,groundCount,C) end
 local groups={}
 local group
 for i=1,#vertices,3 do
  local a,b,c=vertices[i],vertices[i+1],vertices[i+2]
  local ground=i<=(groundCount or 0)
  local cellX=floor((a[1]+b[1]+c[1])/192)
  local cellZ=floor((a[3]+b[3]+c[3])/192)
  -- Keep original triangle order, including coplanar overlaps. Small runs
  -- absorb cell-boundary crossings instead of creating tiny draw calls.
  if not group or group.ground~=ground or group.count>=1536
    or (group.count>=192 and (group.cellX~=cellX or group.cellZ~=cellZ)) then
   group={first=i,count=0,cellX=cellX,cellZ=cellZ,ground=ground,
    minX=math.huge,minY=math.huge,minZ=math.huge,
    maxX=-math.huge,maxY=-math.huge,maxZ=-math.huge}
   groups[#groups+1]=group
  end
  group.count=group.count+3
  for j=i,i+2 do
   local v=vertices[j]
   group.minX=min(group.minX,v[1]);group.maxX=max(group.maxX,v[1])
   group.minY=min(group.minY,v[2]);group.maxY=max(group.maxY,v[2])
   group.minZ=min(group.minZ,v[3]);group.maxZ=max(group.maxZ,v[3])
  end
 end
 return setmetatable({mesh=g.newMesh(format,vertices,'triangles','static'),groups=groups,
  totalTriangles=#vertices/3,drawnTriangles=0,drawCalls=0},C)
end
-- Positive AABB support point for each homogeneous clip plane. Bounds include
-- complete triangles, even those crossing cells or the camera's near plane.
function C.visible(b,m)
 if not m then return true end
 for row=0,2 do
  local i=row*4
  for sign=-1,1,2 do
   local x,y,z,w=m[13]+sign*m[i+1],m[14]+sign*m[i+2],m[15]+sign*m[i+3],m[16]+sign*m[i+4]
   if x*(x>=0 and b.maxX or b.minX)+y*(y>=0 and b.maxY or b.minY)
     +z*(z>=0 and b.maxZ or b.minZ)+w < -1e-5 then return false end
  end
 end
 return true
end
function C:draw(g,vp,skipGround)
 local first,last
 self.drawnTriangles=0;self.drawCalls=0
 -- Bridging a short invisible gap is cheaper than another mobile draw call.
 -- Submitted ranges always preserve the original order and vertex data.
 for _,group in ipairs(self.groups) do
  if not (skipGround and group.ground) and C.visible(group,vp) then
   if first and group.first-last>1536 then
    local count=last-first+1
    self.mesh:setDrawRange(first,count);g.draw(self.mesh)
    self.drawnTriangles=self.drawnTriangles+count/3;self.drawCalls=self.drawCalls+1
    first=nil
   end
   first=first or group.first;last=group.first+group.count-1
  end
 end
 if first then
  local count=last-first+1
  self.mesh:setDrawRange(first,count);g.draw(self.mesh)
  self.drawnTriangles=self.drawnTriangles+count/3;self.drawCalls=self.drawCalls+1
 end
 self.mesh:setDrawRange()
end
function C:release() self.mesh:release() end
return C
