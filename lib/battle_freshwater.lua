-- A cached woodland lake: one scenery mesh, one animated water surface.
local Nature=require('mods.STADIUM2_IMPORTER.lib.battle_nature')
local Mat=require('mods.STADIUM2_IMPORTER.lib.renderer')
local Lake={}
local mesh,water,shader,waterShader,paint,modRef,shadowShader
local FORMAT={{'VertexPosition','float',3},{'SurfaceNormal','float',3},{'SurfaceColor','float',3},{'SurfaceMaterial','float',1}}
local COMMON=[[
varying vec3 world;varying vec3 normal;varying vec3 pigment;varying float material;varying vec3 sunPosition;
#ifdef VERTEX
uniform mat4 vp;uniform mat4 sunVP;
attribute vec3 SurfaceNormal;attribute vec3 SurfaceColor;attribute float SurfaceMaterial;
vec4 position(mat4 tp,vec4 p){world=p.xyz;normal=SurfaceNormal;pigment=SurfaceColor;material=SurfaceMaterial;sunPosition=(sunVP*p).xyz;return vp*p;}
#endif
#ifdef PIXEL
uniform Image sunMap;uniform float sunEnabled;uniform vec3 tint;uniform vec3 eye;uniform vec3 lightDir;
float shadow(){
 if(sunEnabled<.5 || sunPosition.x<0. || sunPosition.x>1. || sunPosition.y<0. || sunPosition.y>1.)return 1.;
 vec4 d=Texel(sunMap,sunPosition.xy);return .64+.36*step(sunPosition.z-.003,d.r+d.g/255.);
}
]]
local LAND=COMMON..[[
uniform Image paint;
vec3 tile(vec2 p,vec2 quadrant){return Texel(paint,quadrant*.5+vec2(.008)+abs(fract(p*.5)*2.-1.)*.484).rgb;}
vec4 effect(vec4 c,Image t,vec2 uv,vec2 px){
 vec3 n=normalize(normal);vec3 w=pow(abs(n),vec3(4.));w/=max(.001,w.x+w.y+w.z);
 vec2 q=material<1.5?vec2(0.):material<2.5?vec2(1.,0.):vec2(0.,1.);
 vec3 surface=vec3(0.);
 if(w.x>.001)surface+=tile(world.zy*.08,q)*w.x;
 if(w.y>.001)surface+=tile(world.xz*.08,q)*w.y;
 if(w.z>.001)surface+=tile(world.xy*.08,q)*w.z;
 surface=mix(surface,pigment,.55);
 vec3 rgb=surface*(.57+.24*max(n.y,0.)+.30*max(0.,dot(n,normalize(-lightDir))))*shadow();
 rgb=mix(rgb,vec3(.34,.44,.39),smoothstep(150.,450.,length(world-eye)))*tint;
 return vec4(rgb,1.);
}
#endif
]]
local WATER=COMMON..[[
uniform float time;
vec4 effect(vec4 c,Image t,vec2 uv,vec2 px){
 vec2 p=world.xz;
 float wave=sin(p.x*.18+p.y*.11+time*.65)+sin(p.y*.27-p.x*.07-time*.43);
 vec3 n=normalize(vec3(-.035*cos(p.x*.18+p.y*.11+time*.65),1.,-.045*cos(p.y*.27-p.x*.07-time*.43)));
 vec3 view=normalize(eye-world);float fresnel=pow(1.-max(dot(n,view),0.),3.);
 float angle=atan(p.y,p.x);float edge=102.+4.*sin(angle*3.)+2.*cos(angle*7.);
 float radius=length(p);float shore=smoothstep(edge-16.,edge,radius);
 vec3 deep=vec3(.12,.36,.40);vec3 shallow=vec3(.36,.53,.43);
 vec3 rgb=mix(deep,shallow,shore)+wave*.012;
 rgb=mix(rgb,vec3(.49,.65,.70),fresnel*.6);
 float strokes=smoothstep(.92,1.,sin(p.x*.24+sin(p.y*.21)+time*.35));
 rgb+=vec3(.13,.18,.17)*strokes*.23;
 float foam=(1.-smoothstep(.0,2.0,abs(radius-edge+wave*.35)))*.20;
 rgb+=vec3(.58,.61,.49)*foam;
 rgb*=shadow();rgb*=tint;
 return vec4(rgb,1.);
}
#endif
]]
Lake.sources={LAND,WATER}
function Lake.bind(mod) if modRef and modRef~=mod then Lake.release() end;modRef=mod end
function Lake.matches(ctx,env)
 ctx=ctx or {};local e=ctx.environment or (env and env.environment)
 if e~='ROUTE' and e~='TOWN' and e~='FOREST' then return false end
 -- Explicit coastal classifications are reserved for the later ocean scene.
 if ctx.waterType=='ocean' or ctx.waterType=='sea' then return false end
 local t=tostring(ctx.terrain or ''):lower();local b=tostring(ctx.battleType or ''):lower()
 return (ctx.kind=='wild' or ctx.kind=='trainer') and (t=='water' or t=='surf' or b=='fish' or b=='fishing')
end
Lake.frame=Nature.frame
Lake.lighting=Nature.lighting
Lake.sky=Nature.sky
function Lake.vertices()
 local models=require('mods.STADIUM2_IMPORTER.assets.kenney_nature.models')
 local rows={}
 local function v(x,y,z,nx,ny,nz,c,m) rows[#rows+1]={x,y,z,nx,ny,nz,c[1],c[2],c[3],m} end
 local function hash(i) return (math.sin(i*127.1+311.7)*43758.5453)%1 end
 local function place(name,x,y,z,size,yaw,c)
  local co,si=math.cos(yaw),math.sin(yaw)
  for _,p in ipairs(models[name]) do
   v(x+(p[1]*co+p[3]*si)*size,y+p[2]*size,z+(-p[1]*si+p[3]*co)*size,
    p[4]*co+p[6]*si,p[5],-p[4]*si+p[6]*co,c,p[10])
  end
 end
 -- Circular banks continue beneath outer trees and disappear into atmospheric fog.
 for ring=0,5 do for i=0,127 do
  local a,b=i*math.pi/64,(i+1)*math.pi/64
  local r0=102+ring*43;local r1=ring==5 and 950 or r0+43
  local function point(angle,r)
   local y=math.min(5,(r-102)*.20)-.8
   local offset=4*math.sin(angle*3)+2*math.cos(angle*7)
   return {math.cos(angle)*(r+offset),y,math.sin(angle)*(r+offset)}
  end
  local p,q,r,s=point(a,r0),point(b,r0),point(b,r1),point(a,r1)
  for _,t in ipairs({p,r,q,p,s,r}) do v(t[1],t[2],t[3],0,1,0,ring==0 and {.58,.55,.39} or {.33,.48,.27},ring==0 and 3 or 1) end
 end end
 for ring=0,2 do for i=0,47 do
  local a=i*math.pi/24+ring*.17;local r=139+ring*70+hash(i+ring*89)*18
  place(i%2==0 and 'tree_oak_lod' or 'tree_fat_lod',math.cos(a)*r,4,math.sin(a)*r,28+hash(i+77)*20,a,{.35,.52,.29})
 end end
 for i=0,179 do
  local a=i*2.39996;local r=105+hash(i+21)*25+4*math.sin(a*3)+2*math.cos(a*7)
  place(i%4==0 and 'rock_smallA' or i%3==0 and 'plant_bush' or 'grass',math.cos(a)*r,math.min(5,(r-102)*.2)-.8,math.sin(a)*r,5+hash(i)*12,a,i%4==0 and {.48,.48,.41} or {.34,.48,.25})
 end
 -- Cattail clusters grow in the shallows, with crossed leaves visible in orbit.
 for i=0,71 do
  local a=i*2.39996;local radius=100+hash(i+380)*8+4*math.sin(a*3)+2*math.cos(a*7)
  for j=1,4 do
   local x,z=math.cos(a)*radius+hash(i*9+j)*3,math.sin(a)*radius+hash(i*5+j)*3
   local h=3+hash(i*11+j)*5
   for _,yaw in ipairs({a,a+math.pi/2}) do
    local dx,dz=math.cos(yaw)*.32,math.sin(yaw)*.32
    for _,p in ipairs({{x-dx,-.8,z-dz},{x+dx,-.8,z+dz},{x+.5*dx,h,z+.5*dz}}) do
     v(p[1],p[2],p[3],0,1,0,{.29,.42,.20},1)
    end
    local c={.32,.26,.16}
    for _,p in ipairs({{x-dx*.7,h*.74,z-dz*.7},{x+dx*.7,h*.74,z+dz*.7},{x+dx*.7,h,z+dz*.7},
      {x-dx*.7,h*.74,z-dz*.7},{x+dx*.7,h,z+dz*.7},{x-dx*.7,h,z-dz*.7}}) do
     v(p[1],p[2],p[3],0,1,0,c,2)
    end
   end
  end
 end
 -- Low sandbars support terrestrial battlers without submerging their feet.
 for _,z in ipairs({24,-24}) do for i=0,47 do
  local a,b=i*math.pi/24,(i+1)*math.pi/24
  local function p(angle) local f=1+.09*math.sin(angle*3+z)+.06*math.cos(angle*5);return {math.cos(angle)*18*f,-.18,z+math.sin(angle)*13*f} end
  local q,r=p(a),p(b)
  for _,t in ipairs({{0,-.12,z},r,q}) do v(t[1],t[2],t[3],0,1,0,{.60,.57,.43},3) end
  local s,t={q[1]*1.12,-1.3,z+(q[3]-z)*1.12},{r[1]*1.12,-1.3,z+(r[3]-z)*1.12}
  for _,point in ipairs({q,r,t,q,t,s}) do v(point[1],point[2],point[3],0,1,0,{.48,.47,.34},3) end
 end end
 Lake.triangles=#rows/3;return rows
end
local function ensure(g)
 if not mesh then mesh=g.newMesh(FORMAT,Lake.vertices(),'triangles','static') end
 if not shader then shader=g.newShader(LAND);waterShader=g.newShader(WATER) end
 if not water then
  local rows={}
  for i=0,127 do
   local a,b=i*math.pi/64,(i+1)*math.pi/64
   for _,p in ipairs({{0,0},{math.cos(b)*110,math.sin(b)*110},{math.cos(a)*110,math.sin(a)*110}}) do rows[#rows+1]={p[1],-.95,p[2],0,1,0,1,1,1,0} end
  end
  water=g.newMesh(FORMAT,rows,'triangles','static')
 end
 if not paint then
  local path='assets/kenney_nature/watercolor-materials.png'
  local data=modRef and love.filesystem.newFileData(assert(modRef:read(path)),'watercolor-materials.png') or 'mods.STADIUM2_IMPORTER/'..path
  paint=g.newImage(data,{mipmaps=true});paint:setFilter('linear','linear',4);paint:setMipmapFilter('linear')
 end
end
function Lake.castShadow(g,vp)
 ensure(g)
 if not shadowShader then shadowShader=g.newShader([[
 varying float depth;
 #ifdef VERTEX
 uniform mat4 lightVP;vec4 position(mat4 tp,vec4 p){vec4 v=lightVP*p;depth=v.z*.5+.5;return v;}
 #endif
 #ifdef PIXEL
 vec4 effect(vec4 c,Image t,vec2 uv,vec2 px){float d=clamp(depth,0.,1.)*255.;return vec4(floor(d)/255.,fract(d),0.,1.);}
 #endif
 ]]) end
 g.setShader(shadowShader);shadowShader:send('lightVP','row',vp);g.setDepthMode('less',true);g.setMeshCullMode('none');g.draw(mesh);g.setShader()
end
function Lake.updateTorchShadows() end
function Lake.drawEffects() end
function Lake.draw(g,frame,env,shadow)
 ensure(g);g.setColor(1,1,1,1);g.setDepthMode('lequal',true);g.setMeshCullMode('none');g.setBlendMode('alpha','alphamultiply')
 for _,entry in ipairs({{shader,mesh},{waterShader,water}}) do
  local s,m=entry[1],entry[2];g.setShader(s)
  s:send('vp','row',frame.vp);s:send('sunVP','row',shadow and shadow.sunVP or frame.vp)
  s:send('sunEnabled',shadow and shadow.map and 1 or 0)
  if shadow and shadow.map then s:send('sunMap',shadow.map) end
  s:send('tint',env.modelTint or {1,1,1});s:send('eye',frame.eye)
  if s==shader then s:send('paint',paint);s:send('lightDir',env.light or {-.4,-1,-.3})
  else s:send('time',love.timer.getTime()) end
  g.draw(m)
 end
 g.setShader();return true
end
function Lake.endBattle() end
function Lake.release()
 for _,r in pairs({mesh,water,shader,waterShader,paint,shadowShader}) do r:release() end
 mesh,water,shader,waterShader,paint,shadowShader=nil,nil,nil,nil,nil,nil
end
return Lake
