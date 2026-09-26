-- Shared construction kit for the painted Kenney battle environments.
--
-- A scene module is `Kit.scene(spec)`: one cached static mesh painted with
-- the woodland watercolor atlas (so every level reads as one painted world),
-- an optional painted water surface, an optional painted sky with night stars
-- and moon, soft warm light pools for lamps and torches, and fog. Scenes
-- describe only their layout in `spec.build(k)` using the builders below.
--
-- Material IDs: 1 foliage, 2 wood, 3 stone, 4 plaster/sand, 5 cloth,
-- 6 painted, 7 light (emissive), 8 ice, 9 metal, 10 floor tiles, 11 snow.
local Chunks=require('mods.STADIUM2_IMPORTER.lib.scenery_chunks')
local Nature=require('mods.STADIUM2_IMPORTER.lib.battle_nature')
local Kit={}
local modRef
local paint,sky,skyMesh
local FORMAT={{'VertexPosition','float',3},{'SurfaceNormal','float',3},{'SurfaceColor','float',3},{'SurfaceMaterial','float',1}}
Kit.FORMAT=FORMAT
local scenes={}

function Kit.bind(mod)
 if modRef and modRef~=mod then Kit.releaseAll() end
 modRef=mod
end

local function image(g,path,name)
 local data=modRef and love.filesystem.newFileData(assert(modRef:read(path)),name) or 'mods/STADIUM2_IMPORTER/'..path
 return g.newImage(data,{mipmaps=true})
end
local function ensurePaint(g)
 if not paint then
  paint=image(g,'assets/kenney_nature/watercolor-materials.png','watercolor-materials.png')
  paint:setFilter('linear','linear',4);paint:setMipmapFilter('linear')
 end
 return paint
end

local COMMON=[[
varying vec3 world;varying vec3 normal;varying vec3 pigment;varying float material;varying vec3 sunPosition;
#ifdef VERTEX
uniform mat4 vp;uniform mat4 sunVP;
attribute vec3 SurfaceNormal;attribute vec3 SurfaceColor;attribute float SurfaceMaterial;
vec4 position(mat4 tp,vec4 p){world=p.xyz;normal=SurfaceNormal;pigment=SurfaceColor;material=SurfaceMaterial;sunPosition=(sunVP*p).xyz;return vp*p;}
#endif
#ifdef PIXEL
uniform Image sunMap;uniform float sunEnabled;uniform vec3 tint;uniform vec3 eye;uniform vec3 lightDir;uniform Image paint;
uniform vec3 fogColor;uniform vec2 fogRange;uniform float time;uniform float night;
uniform vec4 glowPos[6];uniform vec3 glowColor[6];
float shadow(){
 if(sunEnabled<.5 || sunPosition.x<0. || sunPosition.x>1. || sunPosition.y<0. || sunPosition.y>1.)return 1.;
 vec4 d=Texel(sunMap,sunPosition.xy);return .64+.36*step(sunPosition.z-.003,d.r+d.g/255.);
}
vec3 tile(vec2 p,vec2 quadrant){return Texel(paint,quadrant*.5+vec2(.008)+abs(fract(p*.5)*2.-1.)*.484).rgb;}
vec3 planar(vec3 n,vec2 quadrant,float scale){
 vec3 w=pow(abs(n),vec3(4.));w/=max(.001,w.x+w.y+w.z);vec3 s=vec3(0.);
 if(w.x>.001)s+=tile(world.zy*scale,quadrant)*w.x;
 if(w.y>.001)s+=tile(world.xz*scale,quadrant)*w.y;
 if(w.z>.001)s+=tile(world.xy*scale,quadrant)*w.z;
 return s;
}
vec3 glows(vec3 n){
 vec3 sum=vec3(0.);
 for(int i=0;i<6;i++){
  vec4 g=glowPos[i];
  if(g.w>0.){
   vec3 ray=g.xyz-world;float d=length(ray);float f=max(0.,1.-d/g.w);
   sum+=glowColor[i]*f*f*(.35+.65*max(0.,dot(n,ray/max(d,.001))));
  }
 }
 return sum;
}
vec3 fogged(vec3 rgb){return mix(rgb,fogColor,smoothstep(fogRange.x,fogRange.y,length(world-eye)));}
]]
local LAND=COMMON..[[
vec4 effect(vec4 c,Image t,vec2 uv,vec2 px){
 vec3 n=normalize(normal);vec3 surface;vec3 view=normalize(eye-world);
 float rim=pow(1.-max(dot(n,view),0.),3.);
 float emissive=0.;
 if(material<1.5){surface=mix(planar(n,vec2(0.,0.),.08),pigment,.55);}
 else if(material<2.5){surface=mix(planar(n,vec2(1.,0.),.09),pigment,.50);}
 else if(material<3.5){surface=mix(planar(n,vec2(0.,1.),.07),pigment,.60);}
 else if(material<4.5){float w=dot(planar(n,vec2(1.,1.),.05),vec3(.3,.6,.1));surface=pigment*(.72+w*.34);}
 else if(material<5.5){float w=dot(planar(n,vec2(1.,1.),.09),vec3(.3,.6,.1));surface=pigment*(.80+w*.30);}
 else if(material<6.5){float w=dot(planar(n,vec2(1.,1.),.07),vec3(.3,.6,.1));surface=pigment*(.84+w*.22);}
 else if(material<7.5){float w=dot(planar(n,vec2(1.,1.),.12),vec3(.3,.6,.1));surface=pigment*(1.05+w*.2);emissive=1.;}
 else if(material<8.5){
  float w=dot(planar(n,vec2(1.,1.),.06),vec3(.3,.6,.1));
  surface=pigment*(.78+w*.30);
  surface=mix(surface,vec3(.88,.97,1.),rim*.55);
  float sparkle=smoothstep(.86,.9,dot(planar(n,vec2(1.,1.),.9),vec3(.3,.6,.1)))*(.5+.5*sin(time*3.+world.x*.7+world.z));
  surface+=vec3(.5,.6,.7)*sparkle*.5;
 }
 else if(material<9.5){
  vec3 s=planar(n,vec2(0.,1.),.10);float l=dot(s,vec3(.3,.6,.1));
  surface=mix(vec3(l),pigment,.62);surface+=vec3(.28,.30,.32)*rim;
 }
 else if(material<10.5){
  float w=dot(planar(n,vec2(1.,1.),.05),vec3(.3,.6,.1));
  vec2 tiles=fract(world.xz/12.);float grout=step(.035,tiles.x)*step(.035,tiles.y);
  float check=mod(floor(world.x/12.)+floor(world.z/12.),2.);
  surface=pigment*(.80+w*.26)*(.93+.07*check)*(.84+.16*grout);
  surface=mix(surface,vec3(.9,.92,.95),rim*.18);
 }
 else{
  float w=dot(planar(n,vec2(1.,1.),.05),vec3(.3,.6,.1));
  surface=vec3(.90,.93,.98)*(.84+w*.22);
  surface=mix(surface,vec3(.72,.80,.92),(1.-max(n.y,0.))*.45);
  float sparkle=smoothstep(.88,.91,dot(planar(n,vec2(1.,1.),1.1),vec3(.3,.6,.1)));
  surface+=vec3(.6)*sparkle*(1.-night*.3);
 }
 vec3 rgb=surface*(.57+.24*max(n.y,0.)+.30*max(0.,dot(n,normalize(-lightDir))))*shadow();
 rgb=rgb*tint+surface*glows(n);
 rgb=mix(rgb,surface*1.1,emissive);
 return vec4(fogged(rgb),1.);
}
#endif
]]
local WATER=COMMON..[[
uniform vec3 deepColor;uniform vec3 midColor;uniform vec3 shallowColor;
uniform vec3 shore;uniform vec4 rafts[2];uniform vec3 foams[8];uniform vec3 moonDir;uniform float calm;
float rectDistance(vec2 p,vec4 r){vec2 q=abs(p-r.xy)-r.zw;return length(max(q,0.))+min(max(q.x,q.y),0.);}
vec4 effect(vec4 c,Image t,vec2 uv,vec2 px){
 vec2 p=world.xz;float s=1.-calm*.6;
 float a1=p.x*.050+p.y*.034+time*.55*s,a2=p.y*.071-p.x*.029-time*.41*s,a3=(p.x+p.y)*.013+time*.23*s;
 vec3 n=normalize(vec3((-.05*cos(a1)-.02*cos(a3))*s,1.,(-.06*cos(a2)-.02*cos(a3))*s));
 vec3 view=normalize(eye-world);float fresnel=pow(1.-max(dot(n,view),0.),3.);
 // Shore: signed distance to the rim of a round basin (negative inside).
 float rim=shore.z>0.?length(p-shore.xy)-shore.z:-1e4;
 float shallow=shore.z>0.?smoothstep(-70.,-4.,rim):0.;
 vec3 rgb=mix(midColor,deepColor,smoothstep(0.,1.,length(p)/900.));
 rgb=mix(rgb,shallowColor,shallow*shallow);
 float w1=dot(tile(p*.0042+vec2(time*.0015,.2),vec2(1.,1.)),vec3(.3,.6,.1));
 float w2=dot(tile(p*.013+vec2(.37,time*.003),vec2(1.,1.)),vec3(.3,.6,.1));
 float w3=dot(tile(p*.045+vec2(time*.006,.61),vec2(1.,1.)),vec3(.3,.6,.1));
 rgb=mix(rgb,rgb*vec3(.84,.92,1.08),smoothstep(.30,.90,w1)*.7);
 rgb=mix(rgb,rgb*vec3(1.02,1.08,.95),smoothstep(.40,.95,w2)*.45);
 rgb*=.80+.34*(w1*.5+w2*.35+w3*.15);
 float rd=min(rectDistance(p,rafts[0]),rectDistance(p,rafts[1]));
 rgb*=1.-.25*(1.-smoothstep(0.,6.,rd));
 float crest=sin(length(p)*.30-time*1.1*s+sin(p.x*.05+p.y*.04)*2.);
 float dash=smoothstep(.45,.9,sin(atan(p.y,p.x)*length(p)*.32+w2*9.)*.5+.5);
 float strokes=smoothstep(.90,.99,crest)*dash*smoothstep(.45,.70,w3*.7+w2*.5);
 rgb=mix(rgb,vec3(.80,.88,.88),strokes*.35*s);
 rgb=mix(rgb,deepColor*.85,smoothstep(.94,1.,sin(p.x*.23+p.y*.09-time*.4*s))*smoothstep(.62,.78,w2)*smoothstep(.5,.7,w3)*.25*s);
 rgb=mix(rgb,vec3(.60,.72,.78),fresnel*.22*(.7+.6*w2));
 vec3 h=normalize(view+normalize(-lightDir));
 float fleck=smoothstep(.80,.88,w3+.15*sin(p.x*.8+time*2.)*sin(p.y*.9-time*1.7));
 rgb=mix(rgb,vec3(.98,.97,.90),fleck*pow(max(dot(n,h),0.),24.)*.9*(1.-night)*(1.-calm));
 // Foam: the basin rim, round objects and the rafts.
 float lap=shore.z>0.?1.-smoothstep(0.,2.4,abs(rim+2.5+2.*sin(time*.8+atan(p.y-shore.y,p.x-shore.x)*12.))):0.;
 float wake=1.-smoothstep(0.,1.6,abs(rd-1.4-.9*sin(time*1.3+p.x*.35+p.y*.2)));
 for(int i=0;i<8;i++){
  if(foams[i].z>0.){
   float d=length(p-foams[i].xy)-foams[i].z;
   wake=max(wake,(1.-smoothstep(0.,2.5,abs(d-2.+1.5*sin(time*.9+atan(p.y-foams[i].y,p.x-foams[i].x)*6.))))*.8);
  }
 }
 rgb=mix(rgb,vec3(.93,.94,.90),clamp(lap*.8+wake*.55,0.,1.));
 rgb*=shadow();
 vec3 lit=rgb*tint+rgb*glows(n);
 if(night>.5 && moonDir.y>0.){
  vec3 hm=normalize(view+moonDir);float cm=max(dot(n,hm),0.);
  float shimmer=dot(tile(p*vec2(.018,.11)+vec2(time*.012,time*.03),vec2(1.,1.)),vec3(.3,.6,.1));
  float glitter=smoothstep(.58,.82,shimmer+.22*sin(p.y*.55-time*1.6+p.x*.05));
  lit+=vec3(.62,.68,.86)*(pow(cm,90.)*.9+pow(cm,14.)*.10)*(.55+.9*glitter);
 }
 return vec4(fogged(lit),1.);
}
#endif
]]
local SKY=[[
varying vec3 dir;
#ifdef VERTEX
uniform mat4 skyVP;vec4 position(mat4 tp,vec4 p){dir=p.xyz;return skyVP*p;}
#endif
#ifdef PIXEL
uniform Image paper;uniform float nightSky;uniform float weatherFlash;uniform float time;
uniform vec3 haze;uniform vec3 moonDir;uniform vec3 skyTint;
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
vec3 nightSkyColor(vec2 uv){
 vec3 d=normalize(dir);float up=max(d.y,0.);
 vec3 s=mix(vec3(.13,.19,.33),vec3(.03,.05,.13),pow(up,.55));
 float wash=dot(Texel(paper,vec2(.51)+abs(fract(uv*2.3)*2.-1.)*.48).rgb,vec3(.3,.6,.1));
 s*=.85+.3*wash;
 float band=exp(-pow(dot(d,normalize(vec3(.5,.35,.8)))*4.5,2.));
 float dust=dot(Texel(paper,vec2(.51)+abs(fract(d.xz*1.7+d.y)*2.-1.)*.48).rgb,vec3(.3,.6,.1));
 s+=vec3(.10,.10,.16)*band*(.4+.8*dust)*smoothstep(.02,.25,up);
 vec2 sp=vec2(atan(d.z,d.x)*38.,asin(clamp(d.y,-1.,1.))*38.);
 vec2 cell=floor(sp);float r=hash(cell);
 if(r>.94){
  vec2 at=cell+.2+.6*vec2(hash(cell+3.1),hash(cell+7.7));
  float size=.09+.13*hash(cell+1.3);
  float star=1.-smoothstep(0.,size,length(sp-at));
  float tw=.7+.3*sin(time*(1.5+3.*hash(cell+9.))+r*40.);
  s+=vec3(.95,.93,1.)*star*tw*(.7+1.3*(r-.94)/.06)*smoothstep(.02,.12,up);
 }
 float cm=dot(d,moonDir);
 float disc=smoothstep(.99935,.99955,cm);
 float maria=dot(Texel(paper,vec2(.3,.7)+d.xy*6.).rgb,vec3(.3,.6,.1));
 s=mix(s,vec3(1.,.97,.86)*(.86+.2*maria),disc);
 s+=vec3(.55,.62,.80)*(pow(max(cm,0.),900.)*.55+pow(max(cm,0.),40.)*.18);
 return mix(s,haze*vec3(.22,.26,.40),smoothstep(.485,.50,uv.y));
}
vec4 effect(vec4 color,Image tex,vec2 uv,vec2 screen){
 if(nightSky>.5)return vec4(nightSkyColor(uv)+vec3(.22,.27,.36)*weatherFlash,1.);
 vec2 skyUV=vec2(abs(fract(uv.x*2.)*2.-1.),clamp((uv.y-.5)*3.2+.82,.01,.99));
 vec3 s=Texel(tex,skyUV).rgb;float l=dot(s,vec3(.25,.6,.15));s=mix(s,vec3(l),.22);
 vec3 wash=Texel(paper,vec2(.51)+abs(fract(uv*1.5)*2.-1.)*.48).rgb;
 s=mix(s,vec3(.92,.91,.83),.15)*(wash*.12+.90)*skyTint;
 s=mix(s,haze,smoothstep(.40,.50,uv.y));
 return vec4(s*color.rgb+vec3(.22,.27,.36)*weatherFlash,1.);
}
#endif
]]
Kit.sources={LAND=LAND,WATER=WATER,SKY=SKY}

local PIGMENT={{.31,.50,.29},{.55,.42,.30},{.53,.53,.49},{.82,.78,.66}}
local function pigmentFor(p,variation,keep)
 local base=not keep and PIGMENT[p[10]]
 if not base then
  local grey=(p[7]+p[8]+p[9])/3
  return {(p[7]*.66+grey*.34)*.94*variation,(p[8]*.66+grey*.34)*.94*variation,(p[9]*.66+grey*.34)*.94*variation}
 end
 return {base[1]*variation,base[2]*variation,base[3]*variation}
end

local libraries
local function model(name)
 if not libraries then
  libraries={require('mods.STADIUM2_IMPORTER.assets.kenney_kit.models'),
   require('mods.STADIUM2_IMPORTER.assets.kenney_ocean.models'),
   require('mods.STADIUM2_IMPORTER.assets.kenney_nature.models'),
   require('mods.STADIUM2_IMPORTER.assets.kenney_town.models')}
 end
 for _,lib in ipairs(libraries) do if lib[name] then return lib[name] end end
 error('scene kit: unknown model '..tostring(name))
end
Kit.model=model
local centres={}
local function centre(name,source)
 local c=centres[name]
 if not c then
  local x0,x1,z0,z1=math.huge,-math.huge,math.huge,-math.huge
  for _,p in ipairs(source) do x0=math.min(x0,p[1]);x1=math.max(x1,p[1]);z0=math.min(z0,p[3]);z1=math.max(z1,p[3]) end
  c={(x0+x1)/2,(z0+z1)/2};centres[name]=c
 end
 return c
end

-- Builders. Every builder appends triangles to the scene's row list.
local function builder(rows,spec)
 local k={rows=rows}
 local function v(x,y,z,nx,ny,nz,c,m) rows[#rows+1]={x,y,z,nx,ny,nz,c[1],c[2],c[3],m} end
 k.v=v
 function k.hash(i) return (math.sin(i*127.1+311.7)*43758.5453)%1 end
 k.ground=spec.ground or function() return 0 end
 -- A Kenney prop. opts: y, tone, variation, material, keep (keep colours).
 function k.place(name,x,z,size,yaw,opts)
  opts=opts or {}
  local source=model(name)
  local co,si=math.cos(yaw or 0),math.sin(yaw or 0)
  local y=opts.y or k.ground(x,z)
  local variation=opts.variation or 1
  local sx,sy=size,size*(opts.stretch or 1)
  local ox,oz=0,0
  if opts.center then local c=centre(name,source);ox,oz=c[1],c[2] end
  for _,p in ipairs(source) do
   local px,pz=p[1]-ox,p[3]-oz
   local color=opts.tone or pigmentFor(p,variation,opts.keep)
   local material=opts.material or p[10]
   if opts.materials and opts.materials[p[10]] then material=opts.materials[p[10]] end
   v(x+(px*co+pz*si)*sx,y+p[2]*sy,z+(-px*si+pz*co)*sx,
    p[4]*co+p[6]*si,p[5],-p[4]*si+p[6]*co,color,material)
  end
 end
 function k.quad(a,b,c,d,n,col,m)
  for _,q in ipairs({a,c,b,a,d,c}) do v(q[1],q[2],q[3],n[1],n[2],n[3],col,m) end
 end
 -- Oriented box: half extents hx,hy,hz, turned by yaw about its centre.
 function k.box(cx,cy,cz,hx,hy,hz,yaw,c,m,skipBottom)
  local co,si=math.cos(yaw or 0),math.sin(yaw or 0)
  local function P(i,j,l) local x,z=i*hx,l*hz;return {cx+x*co+z*si,cy+j*hy,cz-x*si+z*co} end
  local function N(x,y,z) return {x*co+z*si,y,-x*si+z*co} end
  k.quad(P(-1,1,-1),P(1,1,-1),P(1,1,1),P(-1,1,1),N(0,1,0),c,m)
  if not skipBottom then k.quad(P(-1,-1,1),P(1,-1,1),P(1,-1,-1),P(-1,-1,-1),N(0,-1,0),c,m) end
  k.quad(P(1,-1,-1),P(1,-1,1),P(1,1,1),P(1,1,-1),N(1,0,0),c,m)
  k.quad(P(-1,-1,1),P(-1,-1,-1),P(-1,1,-1),P(-1,1,1),N(-1,0,0),c,m)
  k.quad(P(-1,-1,-1),P(1,-1,-1),P(1,1,-1),P(-1,1,-1),N(0,0,-1),c,m)
  k.quad(P(1,-1,1),P(-1,-1,1),P(-1,1,1),P(1,1,1),N(0,0,1),c,m)
 end
 -- Tapered round column with caps.
 function k.column(x,z,y0,y1,r0,r1,sides,c,m,capColor,capMaterial)
  sides=sides or 12
  for i=0,sides-1 do
   local a,b=i/sides*math.pi*2,(i+1)/sides*math.pi*2
   local ca,sa,cb,sb=math.cos(a),math.sin(a),math.cos(b),math.sin(b)
   k.quad({x+ca*r0,y0,z+sa*r0},{x+cb*r0,y0,z+sb*r0},{x+cb*r1,y1,z+sb*r1},{x+ca*r1,y1,z+sa*r1},
    {math.cos((a+b)/2),(r0-r1)/(y1-y0),math.sin((a+b)/2)},c,m)
   for _,q in ipairs({{x,y1,z},{x+cb*r1,y1,z+sb*r1},{x+ca*r1,y1,z+sa*r1}}) do v(q[1],q[2],q[3],0,1,0,capColor or c,capMaterial or m) end
  end
 end
 -- A log lying along X.
 function k.log(x0,x1,y,z,r,c)
  local sides=10
  for i=0,sides-1 do
   local a,b=i/sides*math.pi*2,(i+1)/sides*math.pi*2
   local ya,za,yb,zb=math.sin(a),math.cos(a),math.sin(b),math.cos(b)
   k.quad({x0,y+ya*r,z+za*r},{x1,y+ya*r,z+za*r},{x1,y+yb*r,z+zb*r},{x0,y+yb*r,z+zb*r},{0,(ya+yb)*.5,(za+zb)*.5},c,2)
   for _,e in ipairs({{x0,-1},{x1,1}}) do
    for _,q in ipairs({{e[1],y,z},{e[1],y+ya*r,z+za*r},{e[1],y+yb*r,z+zb*r}}) do v(q[1],q[2],q[3],e[2],0,0,{.74,.62,.46},2) end
   end
  end
 end
 -- A log raft centred on (0, y, z), logs along X.
 function k.raft(z,y,c)
  y=y or -.92
  for i=0,6 do
   local shade=.9+k.hash(z*3+i)*.18
   local len=12.4+k.hash(z*5+i)*1.4
   k.log(-len,len+k.hash(z*7+i)*.8,y,z-7.5+1.07+i*2.14,1.07,{(c or {.56,.43,.30})[1]*shade,(c or {.56,.43,.30})[2]*shade,(c or {.56,.43,.30})[3]*shade})
  end
  for _,x in ipairs({-8.5,8.5}) do k.box(x,y+1.22,z,1.1,.28,7.9,0,{.50,.38,.27},2) end
  for _,x in ipairs({-8.5,8.5}) do for _,side in ipairs({-1,1}) do k.box(x,y+1.12,z+side*6.6,1.3,.5,.35,0,{.80,.72,.54},5) end end
 end
 -- An irregular rock pillar (sea stack / spire) with an optional crown.
 function k.pillar(x,z,radius,tall,seed,c,crown,crownMaterial,baseY,taper)
  local sides,levels=14,9;baseY=baseY or -3;taper=taper or .42
  local function point(i,j)
   local a=i/sides*math.pi*2;local f=j/levels
   local bumps=1+.16*math.sin(a*3+seed)+.09*math.sin(a*5+seed*2.3)+.06*math.sin(f*9+a*2+seed)
   local r=radius*(1-taper*f^1.4)*bumps
   return {x+math.cos(a)*r,baseY+f*tall,z+math.sin(a)*r}
  end
  for j=0,levels-1 do for i=0,sides-1 do
   local a=(i+.5)/sides*math.pi*2
   local top=crown and j>=levels-2
   local shade=.9+k.hash(seed*50+j*sides+i)*.16
   local col=top and crown or c
   k.quad(point(i,j),point(i+1,j),point(i+1,j+1),point(i,j+1),{math.cos(a),.25,math.sin(a)},{col[1]*shade,col[2]*shade,col[3]*shade},top and (crownMaterial or 1) or 3)
  end end
  for i=0,sides-1 do
   local p1,p2=point(i,levels),point(i+1,levels)
   for _,q in ipairs({{x,baseY+tall+radius*.12,z},p2,p1}) do v(q[1],q[2],q[3],0,1,0,crown or c,crown and (crownMaterial or 1) or 3) end
  end
 end
 -- Height-field terrain. paint(x,y,z,nx,ny,nz) -> colour, material (or nil to skip).
 function k.terrain(x0,x1,z0,z1,step,height,paint)
  for x=x0,x1-step,step do for z=z0,z1-step,step do
   local function vert(px,pz)
    local y=height(px,pz);local e=step*.25
    local nx=height(px-e,pz)-height(px+e,pz)
    local nz=height(px,pz-e)-height(px,pz+e)
    local len=math.sqrt(nx*nx+4*e*e+nz*nz)
    return {px,y,pz,nx/len,2*e/len,nz/len}
   end
   local q={vert(x,z),vert(x+step,z),vert(x+step,z+step),vert(x,z+step)}
   for _,tri in ipairs({{q[1],q[3],q[2]},{q[1],q[4],q[3]}}) do
    local cx=(tri[1][1]+tri[2][1]+tri[3][1])/3;local cz=(tri[1][3]+tri[2][3]+tri[3][3])/3
    local cy=(tri[1][2]+tri[2][2]+tri[3][2])/3;local ny=(tri[1][5]+tri[2][5]+tri[3][5])/3
    local col,m=paint(cx,cy,cz,ny)
    if col then for _,p in ipairs(tri) do v(p[1],p[2],p[3],p[4],p[5],p[6],col,m) end end
   end
  end end
 end
 -- A flat disc (or ring when inner>0) facing up.
 function k.disc(x,y,z,r,sides,c,m,inner)
  sides=sides or 32;inner=inner or 0
  for i=0,sides-1 do
   local a,b=i/sides*math.pi*2,(i+1)/sides*math.pi*2
   local p1,p2={x+math.cos(a)*r,y,z+math.sin(a)*r},{x+math.cos(b)*r,y,z+math.sin(b)*r}
   if inner>0 then
    k.quad({x+math.cos(a)*inner,y,z+math.sin(a)*inner},{x+math.cos(b)*inner,y,z+math.sin(b)*inner},p2,p1,{0,1,0},c,m)
   else
    for _,q in ipairs({{x,y,z},p2,p1}) do v(q[1],q[2],q[3],0,1,0,c,m) end
   end
  end
 end
 -- An enclosing irregular cavern shell (inward facing) around (cx, cz).
 function k.shell(cx,cz,rx,rz,floorY,height,seed,paintFn)
  local sides,levels=40,12
  local function point(i,j)
   local a=i/sides*math.pi*2;local f=j/levels
   local bump=1+.10*math.sin(a*5+seed)+.07*math.sin(a*9+f*6+seed*1.7)+.05*math.sin(f*11+a*3)
   local ring=math.cos(f*math.pi*.5)
   return {cx+math.cos(a)*rx*ring*bump,floorY+math.sin(f*math.pi*.5)*height*(1+.08*math.sin(a*7+seed)),cz+math.sin(a)*rz*ring*bump}
  end
  for j=0,levels-1 do for i=0,sides-1 do
   local a=(i+.5)/sides*math.pi*2;local f=(j+.5)/levels
   local n={-math.cos(a)*math.cos(f*math.pi*.5),-math.sin(f*math.pi*.5),-math.sin(a)*math.cos(f*math.pi*.5)}
   local col,m=paintFn(f,a,k.hash(seed*97+j*sides+i))
   k.quad(point(i,j),point(i,j+1),point(i+1,j+1),point(i+1,j),n,col,m)
  end end
 end
 -- An enclosed hall: four inward walls and a ceiling, centred on the battle.
 function k.hall(hx,hz,height,wall,wallMaterial,ceiling,ceilingMaterial)
  local t=4
  k.box(0,height/2,-hz-t,hx+t,height/2,t,0,wall,wallMaterial)
  k.box(0,height/2,hz+t,hx+t,height/2,t,0,wall,wallMaterial)
  k.box(-hx-t,height/2,0,t,height/2,hz+t,0,wall,wallMaterial)
  k.box(hx+t,height/2,0,t,height/2,hz+t,0,wall,wallMaterial)
  k.box(0,height+t,0,hx+t,t,hz+t,0,ceiling or wall,ceilingMaterial or wallMaterial)
 end
 -- A flat floor slab of tiles or planks.
 function k.floor(hx,hz,y,c,m) k.box(0,y-1,0,hx,1,hz,0,c,m,true) end
 -- Hanging or standing spikes: stalactites (dir -1) or crystals (dir 1).
 function k.spike(x,y,z,radius,length,dir,c,m,sides)
  sides=sides or 6
  for i=0,sides-1 do
   local a,b=i/sides*math.pi*2,(i+1)/sides*math.pi*2
   local p1,p2={x+math.cos(a)*radius,y,z+math.sin(a)*radius},{x+math.cos(b)*radius,y,z+math.sin(b)*radius}
   local tip={x,y+dir*length,z}
   local n={math.cos((a+b)/2),.3*dir,math.sin((a+b)/2)}
   for _,q in ipairs(dir>0 and {p1,p2,tip} or {p2,p1,tip}) do v(q[1],q[2],q[3],n[1],n[2],n[3],c,m) end
  end
 end
 return k
end

-- A scene module from a spec. See the file header for spec fields.
function Kit.scene(spec)
 local S={id=spec.id,outdoor=spec.outdoor==true,visitors=spec.visitors or false}
 local mesh,water,shader,waterShader,shadowShader,skyShader
 function S.bind(mod) Kit.bind(mod) end
 function S.matches() return false end -- selected by battle_environment
 S.frame=spec.frame or Nature.frame
 function S.lighting(env)
  local out=Nature.lighting(env)
  if spec.lighting then out=spec.lighting(out,out.daytime) or out end
  return out
 end
 function S.vertices()
  local rows={}
  local k=builder(rows,spec)
  local ground=spec.build(k) or 0
  require("mods.STADIUM2_IMPORTER.lib.visitor_navigation").build(spec.id,rows)
  S.triangles=#rows/3
  return rows,ground
 end
 local function ensure(g)
  if not mesh then local rows,ground=S.vertices();mesh=Chunks.new(g,FORMAT,rows,ground) end
  if not shader then shader=g.newShader(require('mods.STADIUM2_IMPORTER.lib.scenery_instances').shader(LAND)) end
  if spec.water and not water then
   local w=spec.water;local rows,radii={},w.radii or {0,40,90,160,260,420,700,1100,1700}
   for r=1,#radii-1 do for i=0,127 do
    local a,b=i*math.pi/64,(i+1)*math.pi/64
    local r0,r1=radii[r],radii[r+1]
    local p={{math.cos(a)*r0,math.sin(a)*r0},{math.cos(b)*r0,math.sin(b)*r0},{math.cos(b)*r1,math.sin(b)*r1},{math.cos(a)*r1,math.sin(a)*r1}}
    for _,q in ipairs({1,3,2,1,4,3}) do rows[#rows+1]={p[q][1]+(w.x or 0),w.level or -.95,p[q][2]+(w.z or 0),0,1,0,1,1,1,0} end
   end end
   water=g.newMesh(FORMAT,rows,'triangles','static')
   waterShader=g.newShader(WATER)
  end
  ensurePaint(g)
 end
 local function send(s,name,value) if s:hasUniform(name) then s:send(name,value) end end
 local function sendList(s,name,list,count,width)
  if not s:hasUniform(name) then return end
  local values={}
  for i=1,count do
   local item=list and list[i]
   if width==4 then values[i]=item and {item[1],item[2],item[3],item[4]} or {0,0,0,0}
   else values[i]=item and {item[1],item[2],item[3]} or {0,0,0} end
  end
  s:send(name,unpack(values))
 end
 local function bind(s,frame,env,shadow)
  local night=env.daytime=='NITE' and 1 or 0
  s:send('vp','row',frame.vp);s:send('sunVP','row',shadow and shadow.sunVP or frame.vp)
  send(s,'sunEnabled',shadow and shadow.map and 1 or 0)
  if shadow and shadow.map then send(s,'sunMap',shadow.map) end
  send(s,'tint',env.modelTint or {1,1,1});send(s,'eye',frame.eye)
  send(s,'lightDir',env.light or {-.4,-1,-.3});send(s,'paint',paint)
  local fog=spec.fog or {}
  local fogColor=(night==1 and fog.night) or fog.color or {.66,.77,.80}
  send(s,'fogColor',fogColor);send(s,'fogRange',fog.range or {300,1500})
  send(s,'time',love.timer and love.timer.getTime()%1000 or 0);send(s,'night',night)
  local lights=spec.glows and spec.glows(env) or {}
  local positions,colors={},{}
  for i,l in ipairs(lights) do positions[i]={l[1],l[2],l[3],l[4]};colors[i]={l[5],l[6],l[7]} end
  sendList(s,'glowPos',positions,6,4);sendList(s,'glowColor',colors,6,3)
 end
 function S.castShadow(g,vp)
  ensure(g)
  -- Enclosed rooms: walls and ceiling would shade the whole floor.
  if spec.sceneShadows==false then return end
  if not shadowShader then shadowShader=g.newShader(require('mods.STADIUM2_IMPORTER.lib.scenery_instances').shader([[
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
 function S.updateTorchShadows() end
 function S.drawEffects() end
 function S.draw(g,frame,env,shadow)
  ensure(g);g.setColor(1,1,1,1);g.setDepthMode('lequal',true);g.setMeshCullMode('none');g.setBlendMode('alpha','alphamultiply')
  g.setShader(shader);bind(shader,frame,env,shadow);mesh:draw(g,frame.vp)
  if water then
   local w=spec.water
   g.setShader(waterShader);bind(waterShader,frame,env,shadow)
   send(waterShader,'deepColor',w.deep or {.08,.27,.46});send(waterShader,'midColor',w.mid or {.13,.45,.60})
   send(waterShader,'shallowColor',w.shallow or {.36,.68,.66})
   send(waterShader,'shore',w.shore or {0,0,0});send(waterShader,'calm',w.calm or 0)
   sendList(waterShader,'rafts',w.rafts,2,4);sendList(waterShader,'foams',w.foams,8,3)
   send(waterShader,'moonDir',spec.moon or {0,-1,0})
   g.draw(water)
  end
  g.setShader();return true
 end
 function S.sky(g,w,h,env,frame)
  if not spec.sky then return end
  if not skyShader then skyShader=g.newShader(SKY) end
  if not sky then sky=image(g,'assets/kenney_nature/summer-sky.png','summer-sky.png');sky:setFilter('linear','linear') end
  if not skyMesh then
   local rows={}
   local function vv(i,j)
    local yaw,pitch=i/96*math.pi*2,(j/48-.5)*math.pi
    rows[#rows+1]={math.cos(yaw)*math.cos(pitch)*450,math.sin(pitch)*450,math.sin(yaw)*math.cos(pitch)*450,i/96,1-j/48}
   end
   for j=0,47 do for i=0,95 do vv(i,j);vv(i+1,j);vv(i+1,j+1);vv(i,j);vv(i+1,j+1);vv(i,j+1) end end
   skyMesh=g.newMesh({{'VertexPosition','float',3},{'VertexTexCoord','float',2}},rows,'triangles','static')
   skyMesh:setTexture(sky)
  end
  ensurePaint(g)
  g.setShader(skyShader);skyShader:send('paper',paint)
  skyShader:send('nightSky',env.daytime=='NITE' and 1 or 0)
  send(skyShader,'time',love.timer and love.timer.getTime()%1000 or 0)
  send(skyShader,'haze',spec.sky.haze or {.66,.77,.80})
  send(skyShader,'skyTint',spec.sky.tint or {1,1,1})
  send(skyShader,'moonDir',spec.moon or {0,-1,0})
  send(skyShader,'weatherFlash',env.weatherFlash or 0)
  skyShader:send('skyVP','row',Nature.skyVP(frame))
  g.setDepthMode('always',false);g.setMeshCullMode('none')
  local tint=env.daytime=='NITE' and {1,1,1} or env.modelTint or {1,1,1}
  g.setColor(tint[1],tint[2],tint[3],1);g.draw(skyMesh);g.setColor(1,1,1,1);g.setShader()
 end
 function S.endBattle() end
 function S.release()
  require("mods.STADIUM2_IMPORTER.lib.visitor_navigation").clear(spec.id)
  for _,r in pairs({mesh,water,shader,waterShader,shadowShader,skyShader}) do if r and r.release then r:release() end end
  mesh,water,shader,waterShader,shadowShader,skyShader=nil,nil,nil,nil,nil,nil
 end
 scenes[#scenes+1]=S
 return S
end

function Kit.releaseAll()
 for _,s in ipairs(scenes) do s.release() end
 for _,r in pairs({paint,sky,skyMesh}) do if r and r.release then r:release() end end
 paint,sky,skyMesh=nil,nil,nil
end
return Kit
