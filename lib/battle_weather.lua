-- Bounded world-space rain: one mesh, no textures, readbacks or shadow maps.
local Surface=require('mods.STADIUM2_IMPORTER.lib.weather_surface')
local W={};W.__index=W
local corners={{-1,0},{1,0},{1,1},{-1,0},{1,1},{-1,1}}
local format={{'VertexPosition','float',3},{'VertexTexCoord','float',2},{'VertexColor','float',4}}
W.source=[[
#ifdef VERTEX
uniform mat4 vp;
vec4 position(mat4 tp,vec4 p){return vp*p;}
#endif
#ifdef PIXEL
vec4 effect(vec4 c,Image t,vec2 uv,vec2 px){
 float edge=1.-smoothstep(.25,1.,abs(uv.x*2.-1.));
 if(uv.y>=4.) return vec4(c.rgb,c.a*edge);
 if(uv.y>=2.) {
  vec2 q=vec2(uv.x*2.-1.,(uv.y-2.)*2.-1.);
  float ring=1.-smoothstep(.07,.22,abs(length(q)-.68));
  return vec4(c.rgb,c.a*ring);
 }
 float taper=pow(sin(uv.y*3.14159),.65);
 return vec4(c.rgb,c.a*edge*taper);
}
#endif
]]
local function random(self) self.seed=self.seed*16807%2147483647;return self.seed/2147483647 end
function W.new(id,mode)
 return setmetatable({id=id,mode=mode,seed=8723,time=0,nextStrike=6,flash=0,drops={},rows={},bolts={},boltCount=0,maxSegments=32,count=180},W)
end
function W:lighting(env,dt)
 self.time=self.time+math.min(math.max(dt,0),.1)
 if self.mode=='storm' and self.time>=self.nextStrike then
  self:makeBolt()
  self.strike=self.time;self.nextStrike=self.time+9+random(self)*12
 end
 local t=self.strike and self.time-self.strike or 10
 -- A broad single illumination swell, not rapid repetitive strobing.
 self.flash=self.mode=='storm' and math.max(0,1-t/.65)^2*.85 or 0
 env.weatherFlash=self.flash
 local tint=env.modelTint or {1,1,1}
 env.modelTint={tint[1]*.72+self.flash*.6,tint[2]*.80+self.flash*.67,tint[3]*.91+self.flash*.8}
 local ambient=env.ambient or {.6,.6,.6}
 env.ambient={ambient[1]*.8+self.flash*.5,ambient[2]*.85+self.flash*.55,ambient[3]*.95+self.flash*.65}
 return env
end
-- Paths are generated only on strikes; segment storage is reused.
function W:makeBolt()
 self.boltCount=0
 self.boltType=1+math.floor(random(self)*3) -- single, forked, branching sheet
 local angle=random(self)*math.pi*2
 local x,z=math.cos(angle)*155,math.sin(angle)*155
 local y=125+random(self)*35
 local function segment(ax,ay,az,bx,by,bz,width)
  local n=self.boltCount+1
  if n>self.maxSegments then return end
  local s=self.bolts[n] or {};self.bolts[n]=s;self.boltCount=n
  s[1],s[2],s[3],s[4],s[5],s[6],s[7]=ax,ay,az,bx,by,bz,width
 end
 for i=1,12 do
  local nx=x+(random(self)*2-1)*10
  local ny=y-(self.boltType==3 and 3 or 7)
  local nz=z+(random(self)*2-1)*7
  if self.boltType==3 then nx=nx+8 end
  segment(x,y,z,nx,ny,nz,.28*(1-i/18))
  x,y,z=nx,ny,nz
 end
 local branches=self.boltType==1 and 0 or (self.boltType==2 and 2 or 4)
 for branch=1,branches do
  local parent=self.bolts[3+math.floor(random(self)*7)]
  x,y,z=parent[4],parent[5],parent[6]
  local dx=(branch%2==0 and 1 or -1)*(5+random(self)*6)
  for j=1,5 do
   local nx,ny,nz=x+dx+(random(self)*2-1)*4,y-4-random(self)*4,z+(random(self)*2-1)*5
   segment(x,y,z,nx,ny,nz,.12*(1-j/7));x,y,z=nx,ny,nz
  end
 end
end
function W:surface(x,z)
 return Surface.height(self.id,x,z)
end
function W:respawn(p,initial)
 -- Concentrate part of the rainfall near the clearing, with a broad outer
 -- layer for orbiting cameras. Never target or query Pokemon bodies.
 local radius=random(self)<.55 and 65 or 145
 p.x=(random(self)*2-1)*radius;p.z=(random(self)*2-1)*radius
 local floor=self:surface(p.x,p.z)
 p.y=floor+8+random(self)*(initial and 70 or 30)
 p.splash=0;p.speed=46+random(self)*22;p.alpha=.22+random(self)*.22
 p.width=.045+random(self)*.035;p.length=1.5+random(self)*1.8
end
function W:draw(g,frame,dt)
 if not self.mesh then
  for i=1,self.count do local p={};self.drops[i]=p;self:respawn(p,true) end
  for i=1,(self.count+self.maxSegments*2)*6 do self.rows[i]={0,0,0,0,0,.62,.75,.86,0} end
  self.mesh=g.newMesh(format,self.rows,'triangles','stream');self.shader=g.newShader(W.source)
 end
 dt=math.min(math.max(dt,0),.1)
 for i,p in ipairs(self.drops) do
  local hit=self:surface(p.x,p.z)
  if p.splash>0 then
   p.splash=p.splash+dt
   if p.splash>.28 then self:respawn(p,false) end
  else
   p.x=p.x+6*dt;p.z=p.z+2*dt
   p.y=p.y-p.speed*dt
   hit=self:surface(p.x,p.z)
   if p.y<=hit then p.y=hit+.10;p.splash=.001 end
  end
  local splash=p.splash>0
  local width=splash and (.16+p.splash*2.6) or p.width
  local length=splash and width*2 or p.length
  local alpha=splash and (.45*(1-p.splash/.28)) or p.alpha
  for j,c in ipairs(corners) do
   local r=self.rows[(i-1)*6+j];local x=c[1]*width;local y=c[2]*length
   if splash then
    -- A small expanding surface ring, lying on the sampled impact plane.
    r[1]=p.x+x;r[2]=p.y;r[3]=p.z+(c[2]*2-1)*width
   else
    r[1]=p.x+frame.view[1]*x-y*6/p.speed
    r[2]=p.y+frame.view[2]*x+y
    r[3]=p.z+frame.view[3]*x-y*2/p.speed
   end
   r[4],r[5],r[9]=(c[1]+1)*.5,c[2]+(splash and 2 or 0),alpha
  end
 end
 -- Soft halo and pale core share the rain draw. Unused segments stay
 -- transparent, keeping both upload size and GPU resources bounded.
 for segment=1,self.maxSegments do
  local bolt=self.bolts[segment]
  local active=segment<=self.boltCount and self.flash>0
  for layer=1,2 do for j,c in ipairs(corners) do
   local r=self.rows[self.count*6+((layer-1)*self.maxSegments+segment-1)*6+j]
   if active then
    local t=c[2];local width=bolt[7]*(layer==1 and 5 or 1)
    r[1]=bolt[1]+(bolt[4]-bolt[1])*t+frame.view[1]*c[1]*width
    r[2]=bolt[2]+(bolt[5]-bolt[2])*t+frame.view[2]*c[1]*width
    r[3]=bolt[3]+(bolt[6]-bolt[3])*t+frame.view[3]*c[1]*width
   end
   r[4],r[5],r[6],r[7],r[8],r[9]=(c[1]+1)*.5,c[2]+4,.82,.9,1,active and self.flash*(layer==1 and .16 or 1) or 0
  end end
 end
 self.mesh:setVertices(self.rows)
 g.push('all');g.setShader(self.shader);self.shader:send('vp','row',frame.vp)
 g.setDepthMode('lequal',false);g.setMeshCullMode('none');g.setBlendMode('alpha','alphamultiply');g.setColor(1,1,1,1)
 g.draw(self.mesh);g.pop()
end
function W:release()
 if self.mesh then self.mesh:release();self.shader:release() end
 self.mesh,self.shader=nil,nil
end
return W
