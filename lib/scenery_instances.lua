-- Shared source geometry with per-placement transforms; no LOD or detail loss.
local I={};I.__index=I
local attributes={{'InstancePosition','float',4},{'InstanceRotation','float',2},{'InstanceColor','float',4}}
local helper=[[
#ifdef VERTEX
uniform bool sceneryInstanced;
attribute vec4 InstancePosition;
attribute vec2 InstanceRotation;
attribute vec4 InstanceColor;
vec4 sceneryPoint(vec4 p){
 if(!sceneryInstanced)return p;
 return vec4(InstancePosition.xyz+vec3(p.x*InstanceRotation.x+p.z*InstanceRotation.y,p.y,-p.x*InstanceRotation.y+p.z*InstanceRotation.x)*InstancePosition.w,1.);
}
vec3 sceneryNormal(vec3 n){
 if(!sceneryInstanced)return n;
 return vec3(n.x*InstanceRotation.x+n.z*InstanceRotation.y,n.y,-n.x*InstanceRotation.y+n.z*InstanceRotation.x);
}
vec3 sceneryColor(vec3 c){
 if(!sceneryInstanced)return c;
 return mix(c*InstanceColor.rgb,InstanceColor.rgb,InstanceColor.a);
}
#endif
]]
function I.shader(source)
 source=source:gsub('vec4 position%(', 'vec4 sceneryOriginalPosition(')
 -- Attribute declarations stay unchanged; transform only their uses.
 source=source:gsub('=SurfaceNormal', '=sceneryNormal(SurfaceNormal)')
 source=source:gsub('=SurfaceColor', '=sceneryColor(SurfaceColor)')
 return helper..source..[[
#ifdef VERTEX
vec4 position(mat4 tp,vec4 p){return sceneryOriginalPosition(tp,sceneryPoint(p));}
#endif
]]
end
function I.available(g)
 if not (g.drawInstanced and g.getSupported and g.getShader) then return false end
 local ok,supported=pcall(g.getSupported)
 return ok and supported.instancing==true
end
-- Records refer to the original expanded range, also retained by torch caches.
function I.record(rows,source,key,x,y,z,size,co,si,color,override,lift)
 rows.instances=rows.instances or {}
 rows.instances[#rows.instances+1]={first=#rows+1,count=#source,source=source,key=key,
  data={x,y,z,size,co,si,color[1],color[2],color[3],override and 1 or 0},lift=lift}
end
function I.new(g,format,vertices,groundCount,Chunks)
 local self=setmetatable({groups={},Chunks=Chunks,drawnTriangles=0,drawCalls=0,totalTriangles=#vertices/3},I)
 local byKey,residual={},{}
 local recordIndex=1;local i=1;local residualGround=0
 while i<=#vertices do
  local record=vertices.instances[recordIndex]
  if record and record.first==i then
   local group=byKey[record.key]
   if not group then
    local base=record.source
    if record.lift then
     base={}
     for j,v in ipairs(record.source) do
      local lift=v[10]==1 and (.80+.20*math.min(1,v[2]*3)) or 1
      base[j]={v[1],v[2],v[3],v[4],v[5],v[6],v[7]*lift,v[8]*lift,v[9]*lift,v[10]}
     end
    end
    group={mesh=g.newMesh(format,base,'triangles','static'),records={},triangles=#base/3}
    byKey[record.key]=group;self.groups[#self.groups+1]=group
   end
   local b={minX=math.huge,minY=math.huge,minZ=math.huge,maxX=-math.huge,maxY=-math.huge,maxZ=-math.huge}
   for j=i,i+record.count-1 do
    local v=vertices[j]
    b.minX=math.min(b.minX,v[1]);b.maxX=math.max(b.maxX,v[1])
    b.minY=math.min(b.minY,v[2]);b.maxY=math.max(b.maxY,v[2])
    b.minZ=math.min(b.minZ,v[3]);b.maxZ=math.max(b.maxZ,v[3])
   end
   record.bounds=b;group.records[#group.records+1]=record
   i=i+record.count;recordIndex=recordIndex+1
  else
   residual[#residual+1]=vertices[i]
   if i<=(groundCount or 0) then residualGround=residualGround+1 end
   i=i+1
  end
 end
 self.baseVertices=#residual
 for _,group in ipairs(self.groups) do
  group.buffer=g.newMesh(attributes,#group.records,'points','stream')
  for _,attribute in ipairs(attributes) do group.mesh:attachAttribute(attribute[1],group.buffer,'perinstance') end
  self.baseVertices=self.baseVertices+group.triangles*3
 end
 self.static=Chunks.new(g,format,residual,residualGround)
 return self
end
function I:draw(g,vp,skipGround)
 local shader=assert(g.getShader(),'Instanced scenery requires its scene shader')
 shader:send('sceneryInstanced',false)
 self.static:draw(g,vp,skipGround)
 self.drawnTriangles=self.static.drawnTriangles;self.drawCalls=self.static.drawCalls
 shader:send('sceneryInstanced',true)
 for _,group in ipairs(self.groups) do
  local n=0
  for _,record in ipairs(group.records) do
   if self.Chunks.visible(record.bounds,vp) then
    n=n+1;group.buffer:setVertex(n,record.data)
   end
  end
  if n>0 then
   g.drawInstanced(group.mesh,n)
   self.drawnTriangles=self.drawnTriangles+n*group.triangles;self.drawCalls=self.drawCalls+1
  end
 end
 shader:send('sceneryInstanced',false)
end
function I:release()
 self.static:release()
 for _,group in ipairs(self.groups) do group.mesh:release();group.buffer:release() end
end
return I
