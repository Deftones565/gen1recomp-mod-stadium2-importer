-- Restrained lake fireflies. All motion is deterministic and independent of
-- gameplay RNG. One reusable mesh for glows; four modest local light sources.
local F={count=16,lights={{},{},{},{}}}
local mesh,shader,rows
local enabled=false
local positions={}
for i=1,F.count do positions[i]={} end
local anchors={{-11,5,24},{12,7,-24},{-74,7,-74},{72,6,74}}
local corners={{-1,-1},{1,-1},{1,1},{-1,-1},{1,1},{-1,1}}
local format={{'VertexPosition','float',3},{'VertexTexCoord','float',2},{'VertexColor','float',4}}
local SOURCE=[[
#ifdef VERTEX
uniform mat4 vp;
vec4 position(mat4 tp,vec4 p){return vp*p;}
#endif
#ifdef PIXEL
vec4 effect(vec4 c,Image t,vec2 uv,vec2 px){
 float r=length(uv*2.-1.);
 float halo=pow(max(0.,1.-r),3.)*.25;
 float core=1.-smoothstep(.025,.14,r);
 return vec4(mix(vec3(.68,.88,.24),vec3(1.,.94,.58),core),c.a*(halo+core*.8));
}
#endif
]]
F.source=SOURCE
function F.pose(i,t,out)
 out=out or {}
 local x,y,z
 if i<=4 then local p=anchors[i];x,y,z=p[1],p[2],p[3]
 else local angle=i*2.39996;local radius=96+6*math.sin(i*7.1)
  x,y,z=math.cos(angle)*radius,4+(i%4)*1.2,math.sin(angle)*radius
 end
 local phase=i*2.17
 out[1]=x+3.2*math.sin(t*.22+phase)+.7*math.sin(t*.71+phase)
 out[2]=y+1.4*math.sin(t*.37+phase)
 out[3]=z+2.7*math.cos(t*.19+phase)+.6*math.sin(t*.59+phase)
 out[4]=.30+.70*(.5+.5*math.sin(t*(.64+i*.013)+phase))^2
 return out
end
function F.update(environment,time)
 enabled=environment and (environment.daytime=='NITE' or environment.daytime=='EVE') or false
 local strength=enabled and (environment.daytime=='EVE' and .45 or 1) or 0
 local t=(time or (love and love.timer and love.timer.getTime() or 0))
 for i=1,F.count do
  local p=F.pose(i,t,positions[i]);p[4]=p[4]*strength
  if i<=4 then
   local l=F.lights[i];l[1],l[2],l[3],l[4]=p[1],p[2],p[3],p[4]*.18
  end
 end
end
function F.bindLighting(s)
 if not s:hasUniform('fireflyEnabled') then return end
 s:send('fireflyEnabled',enabled and 1 or 0)
 if enabled then for i=1,4 do s:send('firefly'..i,F.lights[i]) end end
end
function F.draw(g,frame)
 -- Prepare even during daytime so dusk does not allocate mid-battle.
 if not mesh then
  rows={}
  for i=1,F.count*6 do rows[i]={0,0,0,0,0,1,1,1,0} end
  mesh=g.newMesh(format,rows,'triangles','stream');shader=g.newShader(SOURCE)
 end
 if not enabled then return end
 local view=frame.view
 for i=1,F.count do
  local p=positions[i];local size=i<=4 and 1.35 or .85
  for j,corner in ipairs(corners) do
   local r=rows[(i-1)*6+j];local x,y=corner[1]*size,corner[2]*size
   r[1]=p[1]+view[1]*x+view[5]*y
   r[2]=p[2]+view[2]*x+view[6]*y
   r[3]=p[3]+view[3]*x+view[7]*y
   r[4],r[5],r[9]=(corner[1]+1)*.5,(corner[2]+1)*.5,p[4]
  end
 end
 mesh:setVertices(rows)
 g.push('all');g.setShader(shader);shader:send('vp','row',frame.vp)
 g.setColor(1,1,1,1);g.setDepthMode('lequal',false);g.setMeshCullMode('none')
 g.setBlendMode('add','alphamultiply');g.draw(mesh);g.pop()
end
function F.reset() enabled=false end
function F.release()
 if mesh then mesh:release() end;if shader then shader:release() end
 mesh,shader,rows=nil,nil,nil;enabled=false
end
return F
