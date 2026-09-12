local Instances=require('mods.STADIUM2_IMPORTER.lib.scenery_instances')
local Chunks=require('mods.STADIUM2_IMPORTER.lib.scenery_chunks')
-- Cached town scenery with two shadowed street lamps beside the square.
local Nature=require('mods.STADIUM2_IMPORTER.lib.battle_nature')
local Mat=require('mods.STADIUM2_IMPORTER.lib.renderer')
local Town={}
-- Opposite pavement corners, clear of doorways and the battle space.
-- Shadow positions use the shared +1 light-center convention.
Town.lamps={{-43,1.386*18-1,-51},{43,1.386*18-1,51}}
local LampShadows=require('mods.STADIUM2_IMPORTER.lib.battle_torch_shadows').new({
 positions=Town.lamps,power=function(night) return night and 1.6 or 0 end,
})
local shadowVertices
Town.bindTorchLighting=LampShadows.bindModel
local mesh,shader,paint,townPaint,modRef,shadowShader
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
local LAND=COMMON..require("mods.STADIUM2_IMPORTER.lib.torch_lighting_shader").pixel..[[
uniform Image paint;uniform Image townPaint;
vec3 tile(vec2 p,vec2 quadrant){return Texel(paint,quadrant*.5+vec2(.008)+abs(fract(p*.5)*2.-1.)*.484).rgb;}
vec4 effect(vec4 c,Image t,vec2 uv,vec2 px){
 vec3 n=normalize(normal);vec3 w=pow(abs(n),vec3(4.));w/=max(.001,w.x+w.y+w.z);
 vec3 surface=vec3(0.);
 if(material<.5 || (material>2.5 && material<3.5)){
  if(w.x>.001)surface+=tile(world.zy*.08,vec2(0.,1.))*w.x;
  if(w.y>.001)surface+=tile(world.xz*.08,vec2(0.,1.))*w.y;
  if(w.z>.001)surface+=tile(world.xy*.08,vec2(0.,1.))*w.z;
  surface=mix(surface,pigment,.55);
 }else{
  vec2 quadrant=material<1.5?vec2(1.,1.):material<2.5?vec2(0.,1.):material<4.5?vec2(0.):material<5.5?vec2(1.,0.):vec2(0.);
  vec3 scale=material<1.5?vec3(.065):material<2.5?vec3(.08,.035,.08):material<4.5?vec3(.028):vec3(.035);
  vec3 p=world*scale;
  if(w.x>.001)surface+=Texel(townPaint,quadrant*.5+vec2(.008)+abs(fract(p.zy*.5)*2.-1.)*.484).rgb*w.x;
  if(w.y>.001)surface+=Texel(townPaint,quadrant*.5+vec2(.008)+abs(fract(p.xz*.5)*2.-1.)*.484).rgb*w.y;
  if(w.z>.001)surface+=Texel(townPaint,quadrant*.5+vec2(.008)+abs(fract(p.xy*.5)*2.-1.)*.484).rgb*w.z;
  if(material<1.5){surface=mix(surface,pigment,.28);}
  else if(material<2.5){surface=mix(surface,pigment,.30);}
  else if(material<4.5){surface=mix(surface,pigment,.30);}
  else if(material<5.5){float density=dot(surface,vec3(.3,.6,.1));surface=pigment*(.48+density*.92);}
  else{surface=pigment*(.85+.18*surface);}
 }
 if(material<.5){
  vec2 paving=fract(world.xz*.15);float seam=step(.055,paving.x)*step(.055,paving.y);
  surface*=.90+.10*seam;
 }
 vec3 rgb=surface*(.57+.24*max(n.y,0.)+.30*max(0.,dot(n,normalize(-lightDir))))*shadow();
 rgb=rgb*tint+surface*localTorchLight(world,n);
 if(material>6.5){
  // The lantern panes emit only at night, before the shared watercolor pass.
  rgb=mix(surface*tint*.55,vec3(1.,.76,.36)*1.35,step(.01,localTorchPower));
 }
 rgb=mix(rgb,vec3(.34,.44,.39)*tint,smoothstep(150.,450.,length(world-eye)));
 return vec4(rgb,1.);
}
#endif
]]
Town.source=LAND
function Town.bind(mod) if modRef and modRef~=mod then Town.release() end;modRef=mod end
function Town.matches(ctx,env)
 ctx=ctx or {};local e=ctx.environment or (env and env.environment)
 local t=tostring(ctx.terrain or ''):lower();local b=tostring(ctx.battleType or ''):lower()
 return e=='TOWN' and (ctx.kind=='trainer' or ctx.kind=='wild') and t~='grass'
  and t~='water' and t~='surf' and b~='fish' and b~='fishing'
end
Town.frame=Nature.frame
function Town.lighting(env)
 local out=Nature.lighting(env)
 if out.daytime=='NITE' then out.modelTint={.28,.32,.44} end
 return out
end
Town.sky=Nature.sky
function Town.vertices()
 local buildings=require('mods.STADIUM2_IMPORTER.assets.kenney_town.models')
 local plants=require('mods.STADIUM2_IMPORTER.assets.kenney_nature.models')
 local rows={}
 local function v(x,y,z,nx,ny,nz,c,m) rows[#rows+1]={x,y,z,nx,ny,nz,c[1],c[2],c[3],m} end
 local function hash(i) return (math.sin(i*127.1+311.7)*43758.5453)%1 end
 local function place(name,x,z,size,yaw,tone,roof)
  local co,si=math.cos(yaw),math.sin(yaw)
  local source=buildings[name] or plants[name]
  if plants[name] and not roof then Instances.record(rows,source,name,x,0,z,size,co,si,tone or {1,1,1},tone~=nil) end
  for index,p in ipairs(source) do
   local color=tone or {p[7],p[8],p[9]}
   if roof and p[10]==5 then color=roof end
   v(x+(p[1]*co+p[3]*si)*size,p[2]*size,z+(-p[1]*si+p[3]*co)*size,
    p[4]*co+p[6]*si,p[5],-p[4]*si+p[6]*co,color,p[10])
  end
 end
 for x=-280,270,10 do for z=-280,270,10 do
  local plaza=math.abs(x+5)<48 and math.abs(z+5)<58
  local road=math.abs(x+5)<18 or math.abs(z+5)<18
  local c=(plaza or road) and {.64,.61,.53} or {.37,.49,.29}
  for _,p in ipairs({{x,z},{x,z+10},{x+10,z+10},{x,z},{x+10,z+10},{x+10,z}}) do
   v(p[1],-.12,p[2],0,1,0,c,(plaza or road) and 0 or 1)
  end
 end end
 -- Homes face the square; gaps form streets, while a second row gives depth.
 local names={'building-type-a','building-type-b','building-type-c','building-type-f'}
 local roofs={{.68,.29,.22},{.28,.45,.58},{.34,.52,.34},{.58,.43,.29}}
 for side=0,3 do
  local angle=side*math.pi/2
  local co,si=math.cos(angle),math.sin(angle)
  for i=-1,1,2 do
   local x,z=i*48,113
   local wx,wz=x*co+z*si,-x*si+z*co
   place(names[(side+(i+1)/2)%4+1],wx,wz,43,angle+math.pi,nil,roofs[side+1])
   for j=-1,1,2 do
    local px,pz=x+j*20,83
    place('plant_bush',px*co+pz*si,-px*si+pz*co,16,angle,{.31,.48,.26})
    place('flower_purpleA',(px+3)*co+(pz-4)*si,-(px+3)*si+(pz-4)*co,9,angle)
   end
   for j=-2,2 do
    local fx,fz=x+j*10,78
    place('fence',fx*co+fz*si,-fx*si+fz*co,20,angle,{.60,.47,.31})
   end
   place('planter',wx*.58,wz*.58,19,angle)
  end
 end
 for i=0,47 do
  local a=i*2.39996;local r=173+hash(i)*65
  place(i%2==0 and 'tree_oak_lod' or 'tree_fat_lod',math.cos(a)*r,math.sin(a)*r,30+hash(i+40)*17,a,{.34,.49,.28})
 end
 for i=0,3 do
  local a=i*math.pi/2+math.pi/4
  place('tree_oak',math.cos(a)*86,math.sin(a)*86,30,a,{.35,.51,.28})
 end
 for _,p in ipairs(Town.lamps) do place('lantern',p[1],p[3],18,0) end
 -- Distant ground never exposes a square edge through the streets.
 for i=0,63 do
  local a,b=i*math.pi/32,(i+1)*math.pi/32
  for _,p in ipairs({{a,270},{b,950},{b,270},{a,270},{a,950},{b,950}}) do
   v(math.cos(p[1])*p[2],-.18,math.sin(p[1])*p[2],0,1,0,{.37,.49,.29},1)
  end
 end
 require("mods.STADIUM2_IMPORTER.lib.visitor_navigation").build("town",rows)
 Town.triangles=#rows/3;return rows
end
local function ensure(g)
 if not mesh then shadowVertices=Town.vertices();mesh=Chunks.new(g,FORMAT,shadowVertices) end
 if not shader then shader=g.newShader(Instances.shader(LAND)) end
 if not townPaint then
  local path='assets/kenney_town/watercolor-town.png'
  local data=modRef and love.filesystem.newFileData(assert(modRef:read(path)),'watercolor-town.png') or 'mods.STADIUM2_IMPORTER/'..path
  townPaint=g.newImage(data,{mipmaps=true});townPaint:setFilter('linear','linear',4);townPaint:setMipmapFilter('linear')
 end
 if not paint then
  local path='assets/kenney_nature/watercolor-materials.png'
  local data=modRef and love.filesystem.newFileData(assert(modRef:read(path)),'watercolor-materials.png') or 'mods.STADIUM2_IMPORTER/'..path
  paint=g.newImage(data,{mipmaps=true});paint:setFilter('linear','linear',4);paint:setMipmapFilter('linear')
 end
end
function Town.castShadow(g,vp)
 ensure(g)
 if not shadowShader then shadowShader=g.newShader(Instances.shader([[
 varying float depth;
 #ifdef VERTEX
 uniform mat4 lightVP;vec4 position(mat4 tp,vec4 p){vec4 v=lightVP*p;depth=v.z*.5+.5;return v;}
 #endif
 #ifdef PIXEL
 vec4 effect(vec4 c,Image t,vec2 uv,vec2 px){float d=clamp(depth,0.,1.)*255.;return vec4(floor(d)/255.,fract(d),0.,1.);}
 #endif
 ]])) end
 g.setShader(shadowShader);shadowShader:send('lightVP','row',vp);g.setDepthMode('less',true);g.setMeshCullMode('none');mesh:draw(g,vp);g.setShader()
end
function Town.updateTorchShadows(g,actors,matrices,modes,env)
 ensure(g)
 LampShadows.night=env.daytime=='NITE'
 if not LampShadows.night then LampShadows.power=0;return end
 local result=LampShadows.update(g,shadowVertices or {},FORMAT,actors,matrices,modes)
 if result then shadowVertices=nil end
 return result
end
function Town.drawEffects() end
function Town.draw(g,frame,env,shadow)
 ensure(g);g.setColor(1,1,1,1);g.setDepthMode('lequal',true);g.setMeshCullMode('none');g.setBlendMode('alpha','alphamultiply');g.setShader(shader)
 shader:send('vp','row',frame.vp);shader:send('sunVP','row',shadow and shadow.sunVP or frame.vp)
 shader:send('sunEnabled',shadow and shadow.map and 1 or 0)
 if shadow and shadow.map then shader:send('sunMap',shadow.map) end
 shader:send('tint',env.modelTint or {1,1,1});shader:send('eye',frame.eye)
 shader:send('paint',paint);shader:send('townPaint',townPaint);shader:send('lightDir',env.light or {-.4,-1,-.3})
 LampShadows.bindModel(shader)
 mesh:draw(g,frame.vp);g.setShader();return true
end
function Town.endBattle() LampShadows.resetDynamic() end
function Town.release()
 require("mods.STADIUM2_IMPORTER.lib.visitor_navigation").clear("town")
 LampShadows.release();shadowVertices=nil
 for _,r in pairs({mesh,shader,paint,townPaint,shadowShader}) do r:release() end
 mesh,shader,paint,townPaint,shadowShader=nil,nil,nil,nil,nil
end
return Town
