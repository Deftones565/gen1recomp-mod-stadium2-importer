local Chunks=require('mods.STADIUM2_IMPORTER.lib.scenery_chunks')
local Instances=require('mods.STADIUM2_IMPORTER.lib.scenery_instances')
-- A cached open-sea battle: both battlers ride log rafts on a painted sea,
-- a palm island lies off to the side with a pier and dunes, and small islets
-- and sea stacks dot the horizon. Materials share the woodland watercolor
-- atlas so every scene reads as one painted world. Kenney Pirate Kit /
-- Watercraft Pack meshes (CC0), see assets/kenney_ocean/README.md.
local Nature=require('mods.STADIUM2_IMPORTER.lib.battle_nature')
local Ocean={}
local mesh,sea,shader,seaShader,paint,sky,skyMesh,skyShader,modRef,shadowShader
local FORMAT={{'VertexPosition','float',3},{'SurfaceNormal','float',3},{'SurfaceColor','float',3},{'SurfaceMaterial','float',1}}

-- The island: a wobbly disc off to the camera's right and ahead. `coast`
-- returns the signed distance inland from its shoreline (negative at sea)
-- and the arc position along the shore. Shared by the mesh and sea shader.
local CX,CZ,R=230,-640,270
local function wobble(a) return 14*math.sin(a*3)+7*math.sin(a*7+1.3) end
local function coast(x,z)
 local dx,dz=x-CX,z-CZ
 local a=math.atan2(dz,dx)
 return R+wobble(a)-math.sqrt(dx*dx+dz*dz),a*R
end
Ocean.coast=coast
local function coastPoint(d,a)
 local r=R+wobble(a)-d
 return CX+math.cos(a)*r,CZ+math.sin(a)*r
end
-- The two battle rafts: logs along X, centred on each battle slot.
local RAFT_X,RAFT_Z=13,7.5
Ocean.RAFTS={24,-24}
local HAZE='vec3(.66,.77,.80)'
-- Night: the moon hangs just left of the default camera's view, low over the
-- sea behind the battle, so its light path runs towards the camera. Shared by the sky and sea shaders.
local MOON='normalize(vec3(-.87,.115,-.47))'
local SHORE=[[
float shoreDistance(vec2 p){
 vec2 q=p-vec2(230.,-640.);float a=atan(q.y,q.x);
 return 270.+14.*sin(a*3.)+7.*sin(a*7.+1.3)-length(q);
}
float raftDistance(vec2 p,float z){
 vec2 q=abs(vec2(p.x,p.y-z))-vec2(13.,7.5);
 return length(max(q,0.))+min(max(q.x,q.y),0.);
}
]]

local COMMON=[[
varying vec3 world;varying vec3 normal;varying vec3 pigment;varying float material;varying vec3 sunPosition;
#ifdef VERTEX
uniform mat4 vp;uniform mat4 sunVP;
attribute vec3 SurfaceNormal;attribute vec3 SurfaceColor;attribute float SurfaceMaterial;
vec4 position(mat4 tp,vec4 p){world=p.xyz;normal=SurfaceNormal;pigment=SurfaceColor;material=SurfaceMaterial;sunPosition=(sunVP*p).xyz;return vp*p;}
#endif
#ifdef PIXEL
uniform Image sunMap;uniform float sunEnabled;uniform vec3 tint;uniform vec3 eye;uniform vec3 lightDir;uniform Image paint;
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
]]
-- Materials: 1 foliage (leaf wash), 2 wood (bark wash), 3 stone (stone
-- wash), 4 sand and 5 sailcloth (paper wash), 6 painted trim (paper wash).
local LAND=COMMON..SHORE..[[
vec4 effect(vec4 c,Image t,vec2 uv,vec2 px){
 vec3 n=normalize(normal);vec3 surface;
 if(material<1.5){surface=mix(planar(n,vec2(0.,0.),.08),pigment,.55);}
 else if(material<2.5){surface=mix(planar(n,vec2(1.,0.),.09),pigment,.50);}
 else if(material<3.5){surface=mix(planar(n,vec2(0.,1.),.07),pigment,.58);}
 else{
  float wash=dot(planar(n,vec2(1.,1.),material<4.5?.05:.09),vec3(.3,.6,.1));
  surface=pigment*((material<4.5?.72:.80)+wash*.34);
  if(material<4.5){
   // Wind ripples on dry sand; a darker wet band follows the tide line.
   float d=shoreDistance(world.xz);
   float ripple=sin(world.x*.9+sin(world.z*.23)*2.)*.5+.5;
   surface*=.95+.06*ripple*smoothstep(8.,20.,d);
   float wet=(1.-smoothstep(1.,7.,d))*smoothstep(-14.,-4.,d);
   surface=mix(surface,surface*vec3(.80,.80,.82),wet);
  }
 }
 vec3 rgb=surface*(.57+.24*max(n.y,0.)+.30*max(0.,dot(n,normalize(-lightDir))))*shadow();
 rgb=mix(rgb,]]..HAZE..[[,smoothstep(300.,1500.,length(world-eye)))*tint;
 return vec4(rgb,1.);
}
#endif
]]
local SEA=COMMON..SHORE..[[
uniform float time;uniform float night;
vec4 effect(vec4 c,Image t,vec2 uv,vec2 px){
 vec2 p=world.xz;
 float d=shoreDistance(p);
 float a1=p.x*.050+p.y*.034+time*.55,a2=p.y*.071-p.x*.029-time*.41,a3=(p.x+p.y)*.013+time*.23;
 vec3 n=normalize(vec3(-.05*cos(a1)-.02*cos(a3),1.,-.06*cos(a2)-.02*cos(a3)));
 vec3 view=normalize(eye-world);float fresnel=pow(1.-max(dot(n,view),0.),3.);
 // Depth from the coast: deep ultramarine, teal, then turquoise shallows.
 float shallow=smoothstep(-90.,-6.,d);
 vec3 deep=vec3(.09,.27,.45),mid=vec3(.14,.43,.58),lagoon=vec3(.36,.66,.64);
 vec3 rgb=mix(deep,mid,smoothstep(-900.,-200.,d));
 rgb=mix(rgb,lagoon,shallow*shallow);
 // Paint, not plastic: blotchy washes at three scales drift slowly, bleeding
 // cobalt, teal and a touch of green into each other.
 float w1=dot(tile(p*.0042+vec2(time*.0015,.2),vec2(1.,1.)),vec3(.3,.6,.1));
 float w2=dot(tile(p*.013+vec2(.37,time*.003),vec2(1.,1.)),vec3(.3,.6,.1));
 float w3=dot(tile(p*.045+vec2(time*.006,.61),vec2(1.,1.)),vec3(.3,.6,.1));
 float blot=w1*.5+w2*.35+w3*.15;
 rgb=mix(rgb,rgb*vec3(.84,.92,1.08),smoothstep(.30,.90,w1)*.7);   // cobalt pools
 rgb=mix(rgb,rgb*vec3(1.02,1.08,.95),smoothstep(.40,.95,w2)*.45); // teal blooms
 rgb*=.80+.34*blot;
 // Soft contact shade where the rafts sit in the water.
 float rafts=min(raftDistance(p,24.),raftDistance(p,-24.));
 rgb*=1.-.25*(1.-smoothstep(0.,6.,rafts));
 // Brush strokes: broken pale crests and darker hatching, tapered by the
 // paper grain so no line is continuous.
 vec2 qq=p-vec2(230.,-640.);float run=atan(qq.y,qq.x)*length(qq);
 float crest=sin(d*.30+time*1.1+sin(p.x*.05+p.y*.04)*2.);
 float dash=smoothstep(.45,.9,sin(run*.32+d*.05+w2*9.)*.5+.5);
 float breakup=smoothstep(.45,.70,w3*.7+w2*.5);
 float strokes=smoothstep(.90,.99,crest)*dash*breakup;
 rgb=mix(rgb,vec3(.80,.88,.88),strokes*(.35+.25*shallow));
 float hatch=smoothstep(.94,1.,sin(p.x*.23+p.y*.09+sin(p.y*.05)*3.-time*.4))*smoothstep(.62,.78,w2)*smoothstep(.5,.7,w3)*(1.-shallow)
  *smoothstep(.55,.9,sin(p.y*.45-p.x*.18+w3*10.)*.5+.5);
 rgb=mix(rgb,deep*.85,hatch*.25);
 // A light paper wash towards the horizon instead of a glossy sheen.
 rgb=mix(rgb,vec3(.60,.72,.78),fresnel*.22*(.7+.6*w2));
 // Sun sparkles by day: sparse painted flecks, not a specular highlight.
 vec3 h=normalize(view+normalize(-lightDir));
 float sun=pow(max(dot(n,h),0.),24.);
 float fleck=smoothstep(.80,.88,w3+.15*sin(p.x*.8+time*2.)*sin(p.y*.9-time*1.7));
 rgb=mix(rgb,vec3(.98,.97,.90),fleck*sun*.9*(1.-night));
 // Foam: a lapping line at the tide mark, a second wash further out, and
 // wake and spray around the rafts.
 vec2 q=p-vec2(230.,-640.);float along=atan(q.y,q.x)*270.;
 float lap=1.-smoothstep(0.,2.4,abs(d+2.5+2.2*sin(time*.8+along*.045)));
 float wash2=1.-smoothstep(0.,1.6,abs(d+9.+3.*sin(time*.55+along*.03+1.7)));
 float wake=1.-smoothstep(0.,1.6,abs(rafts-1.4-.9*sin(time*1.3+p.x*.35+p.y*.2)));
 float stacks=1e4;
 stacks=min(stacks,length(p-vec2(-190.,-280.))-20.);stacks=min(stacks,length(p-vec2(-340.,-60.))-15.);
 stacks=min(stacks,length(p-vec2(-470.,-420.))-28.);stacks=min(stacks,length(p-vec2(-170.,230.))-12.);
 stacks=min(stacks,length(p-vec2(-280.,-560.))-17.);stacks=min(stacks,length(p-vec2(130.,160.))-11.);
 stacks=min(stacks,length(p-vec2(-90.,-420.))-9.);
 float swirl=1.-smoothstep(0.,2.5,abs(stacks-2.+1.5*sin(time*.9+atan(p.y,p.x)*6.)));
 wake=max(wake,swirl*.8);
 float spray=smoothstep(.55,.9,sin(p.x*.9+time*2.1)*sin(p.y*1.1-time*1.7))*(1.-smoothstep(0.,4.,rafts));
 rgb=mix(rgb,vec3(.93,.94,.90),clamp(lap*.85+wash2*.35+wake*.55+spray*.35,0.,1.));
 rgb*=shadow();
 rgb=mix(rgb,]]..HAZE..[[,smoothstep(220.,1300.,length(world-eye)));
 rgb*=tint;
 if(night>.5){
  // Moonlight: a broad silver sheen and a glittering path towards the moon.
  vec3 m=]]..MOON..[[;vec3 hm=normalize(view+m);float c=max(dot(n,hm),0.);
  float shimmer=dot(tile(p*vec2(.018,.11)+vec2(time*.012,time*.03),vec2(1.,1.)),vec3(.3,.6,.1));
  float glitter=smoothstep(.58,.82,shimmer+.22*sin(p.y*.55-time*1.6+p.x*.05));
  rgb+=vec3(.62,.68,.86)*(pow(c,90.)*.9+pow(c,14.)*.10)*(.55+.9*glitter);
  rgb+=vec3(.20,.24,.34)*(lap*.6+wake*.5);
  rgb=mix(rgb,vec3(.10,.15,.26),smoothstep(500.,1500.,length(world-eye))*.8);
 }
 return vec4(rgb,1.);
}
#endif
]]
Ocean.sources={LAND,SEA}

function Ocean.bind(mod) if modRef and modRef~=mod then Ocean.release() end;modRef=mod end
function Ocean.matches(ctx,env) return false end -- selected by battle_environment
Ocean.frame=Nature.frame
-- Moonlit nights: a slightly brighter, bluer key than the woodland's.
function Ocean.lighting(env)
 local out=Nature.lighting(env)
 if out.daytime=='NITE' then out.modelTint={.27,.33,.50} end
 return out
end

local function image(g,path,name)
 local data=modRef and love.filesystem.newFileData(assert(modRef:read(path)),name) or 'mods/STADIUM2_IMPORTER/'..path
 return g.newImage(data,{mipmaps=true})
end

-- Same painted summer sky as the woodland, with a sea-haze horizon.
function Ocean.sky(g,w,h,env,frame)
 if not skyShader then skyShader=g.newShader([[
  varying vec3 dir;
  #ifdef VERTEX
  uniform mat4 skyVP;vec4 position(mat4 tp,vec4 p){dir=p.xyz;return skyVP*p;}
  #endif
  #ifdef PIXEL
  uniform Image paper;uniform float nightSky;uniform float weatherFlash;uniform float time;
  float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
  vec3 night(vec2 uv){
   vec3 d=normalize(dir);float up=max(d.y,0.);
   // Painted indigo wash, warmer and paler towards the sea.
   vec3 s=mix(vec3(.13,.19,.33),vec3(.03,.05,.13),pow(up,.55));
   float wash=dot(Texel(paper,vec2(.51)+abs(fract(uv*2.3)*2.-1.)*.48).rgb,vec3(.3,.6,.1));
   s*=.85+.3*wash;
   // A faint Milky Way band across the sky.
   float band=exp(-pow(dot(d,normalize(vec3(.5,.35,.8)))*4.5,2.));
   float dust=dot(Texel(paper,vec2(.51)+abs(fract(d.xz*1.7+d.y)*2.-1.)*.48).rgb,vec3(.3,.6,.1));
   s+=vec3(.10,.10,.16)*band*(.4+.8*dust)*smoothstep(.02,.25,up);
   // Stars on a sphere grid: sparse, varied size, gently twinkling.
   vec2 sp=vec2(atan(d.z,d.x)*38.,asin(clamp(d.y,-1.,1.))*38.);
   vec2 cell=floor(sp);float r=hash(cell);
   if(r>.94){
    vec2 at=cell+.2+.6*vec2(hash(cell+3.1),hash(cell+7.7));
    float size=.09+.13*hash(cell+1.3);
    float star=1.-smoothstep(0.,size,length(sp-at));
    float tw=.7+.3*sin(time*(1.5+3.*hash(cell+9.))+r*40.);
    s+=vec3(.95,.93,1.)*star*tw*(.7+1.3*(r-.94)/.06)*smoothstep(.02,.12,up);
   }
   // The moon: a soft ivory disc with painted maria, a halo and wide glow.
   vec3 m=]]..MOON..[[;float c=dot(d,m);
   float disc=smoothstep(.99935,.99955,c);
   float maria=dot(Texel(paper,vec2(.3,.7)+d.xy*6.).rgb,vec3(.3,.6,.1));
   s=mix(s,vec3(1.,.97,.86)*(.86+.2*maria),disc);
   s+=vec3(.55,.62,.80)*(pow(max(c,0.),900.)*.55+pow(max(c,0.),40.)*.18);
   s=mix(s,vec3(.14,.20,.32),smoothstep(.485,.50,uv.y));
   return s;
  }
  vec4 effect(vec4 color,Image tex,vec2 uv,vec2 screen){
   if(nightSky>.5)return vec4(night(uv)+vec3(.22,.27,.36)*weatherFlash,1.);
   vec2 skyUV=vec2(abs(fract(uv.x*2.)*2.-1.),clamp((uv.y-.5)*3.2+.82,.01,.99));
   vec3 s=Texel(tex,skyUV).rgb;float l=dot(s,vec3(.25,.6,.15));s=mix(s,vec3(l),.22);
   vec3 wash=Texel(paper,vec2(.51)+abs(fract(uv*1.5)*2.-1.)*.48).rgb;
   s=mix(s,vec3(.92,.91,.83),.15)*(wash*.12+.90);
   s=mix(s,]]..HAZE..[[,smoothstep(.40,.50,uv.y));
   return vec4(s*color.rgb+vec3(.22,.27,.36)*weatherFlash,1.);
  }
  #endif
 ]]) end
 if not sky then sky=image(g,'assets/kenney_nature/summer-sky.png','summer-sky.png');sky:setFilter('linear','linear') end
 if not skyMesh then
  local rows={}
  local function v(i,j)
   local yaw,pitch=i/96*math.pi*2,(j/48-.5)*math.pi
   rows[#rows+1]={math.cos(yaw)*math.cos(pitch)*450,math.sin(pitch)*450,math.sin(yaw)*math.cos(pitch)*450,i/96,1-j/48}
  end
  for j=0,47 do for i=0,95 do v(i,j);v(i+1,j);v(i+1,j+1);v(i,j);v(i+1,j+1);v(i,j+1) end end
  skyMesh=g.newMesh({{'VertexPosition','float',3},{'VertexTexCoord','float',2}},rows,'triangles','static')
  skyMesh:setTexture(sky)
 end
 Ocean.ensurePaint(g)
 g.setShader(skyShader);skyShader:send('paper',paint)
 skyShader:send('nightSky',env.daytime=='NITE' and 1 or 0)
 skyShader:send('time',love.timer and love.timer.getTime()%1000 or 0)
 skyShader:send('weatherFlash',env.weatherFlash or 0)
 skyShader:send('skyVP','row',Nature.skyVP(frame))
 g.setDepthMode('always',false);g.setMeshCullMode('none')
 local tint=env.daytime=='NITE' and {1,1,1} or env.modelTint or {1,1,1}
 g.setColor(tint[1],tint[2],tint[3],1);g.draw(skyMesh);g.setColor(1,1,1,1);g.setShader()
end

-- One pigment per material keeps Kenney's bright palette in the painted key.
local PIGMENT={{.31,.50,.29},{.55,.42,.30},{.53,.53,.49},{.79,.72,.55},{.93,.91,.85}}
local function pigmentFor(p,variation)
 local base=PIGMENT[p[10]]
 if not base then
  local grey=(p[7]+p[8]+p[9])/3
  return {(p[7]*.62+grey*.38)*.92,(p[8]*.62+grey*.38)*.92,(p[9]*.62+grey*.38)*.92}
 end
 return {base[1]*variation,base[2]*variation,base[3]*variation}
end

function Ocean.vertices()
 local models=require('mods.STADIUM2_IMPORTER.assets.kenney_ocean.models')
 local plants=require('mods.STADIUM2_IMPORTER.assets.kenney_nature.models')
 local rows={}
 local function v(x,y,z,nx,ny,nz,c,m) rows[#rows+1]={x,y,z,nx,ny,nz,c[1],c[2],c[3],m} end
 local function hash(i) return (math.sin(i*127.1+311.7)*43758.5453)%1 end
 local function height(x,z)
  local d,t=coast(x,z)
  if d<0 then return -.95-5*math.min(1,(-d/40)^1.5) end
  if d<30 then return -.95+d*.10 end
  -- Dunes roll up to a rounded green hill in the island's middle.
  local dune=2.05+(d-30)*.12+1.4*math.sin(t*.05)*math.sin(d*.09)
  local hill=math.max(0,d-110)*.16
  return math.min(dune,11+1.2*math.sin(t*.03))+hill*hill*.012
 end
 Ocean.height=height
 local function place(name,x,z,size,yaw,options)
  options=options or {}
  local source=models[name] or plants[name]
  local co,si=math.cos(yaw),math.sin(yaw)
  local y=options.y or height(x,z)
  local variation=options.variation or 1
  for _,p in ipairs(source) do
   local color=options.tone or pigmentFor(p,variation)
   v(x+(p[1]*co+p[3]*si)*size,y+p[2]*size,z+(-p[1]*si+p[3]*co)*size,
    p[4]*co+p[6]*si,p[5],-p[4]*si+p[6]*co,color,p[10])
  end
 end
 -- Island terrain: a height field over the island and its shallow shelf.
 local function terrain(x0,x1,z0,z1,step,heightAt,distanceAt)
  for x=x0,x1-step,step do for z=z0,z1-step,step do
   local corners={{x,z},{x+step,z},{x+step,z+step},{x,z+step}}
   local deepest=math.huge
   for _,c in ipairs(corners) do deepest=math.min(deepest,distanceAt(c[1],c[2])) end
   if deepest>-40 then
    local function vert(c)
     local y=heightAt(c[1],c[2]);local e=2
     local nx=heightAt(c[1]-e,c[2])-heightAt(c[1]+e,c[2])
     local nz=heightAt(c[1],c[2]-e)-heightAt(c[1],c[2]+e)
     local len=math.sqrt(nx*nx+4*e*e+nz*nz)
     return {c[1],y,c[2],nx/len,2*e/len,nz/len,distanceAt(c[1],c[2])}
    end
    local q={vert(corners[1]),vert(corners[2]),vert(corners[3]),vert(corners[4])}
    for _,tri in ipairs({{q[1],q[3],q[2]},{q[1],q[4],q[3]}}) do
     local d=(tri[1][7]+tri[2][7]+tri[3][7])/3
     local grassy=d>36
     local n=hash(math.floor(tri[1][1]*3+tri[1][3]*7))
     local color=grassy and {.44+n*.05,.54+n*.04,.30} or d<3 and {.68,.63,.50} or {.82,.75,.58}
     for _,p in ipairs(tri) do v(p[1],p[2],p[3],p[4],p[5],p[6],color,grassy and 1 or 4) end
    end
   end
  end end
 end
 terrain(CX-R-60,CX+R+60,CZ-R-60,CZ+R+60,12,height,function(x,z) return (coast(x,z)) end)
 -- Islets on the horizon: small sandy mounds with a few palms.
 local islets={{-640,-700,70,9},{-120,-980,55,7},{-980,120,90,11},{820,420,60,8}}
 for k,it in ipairs(islets) do
  local ix,iz,ir,ih=it[1],it[2],it[3],it[4]
  local function dist(x,z) return ir+6*math.sin(math.atan2(z-iz,x-ix)*3+k)-math.sqrt((x-ix)^2+(z-iz)^2) end
  local function h(x,z)
   local d=dist(x,z)
   if d<0 then return -.95-4*math.min(1,-d/30) end
   return -.95+ih*math.sin(math.min(1,d/(ir*.8))*math.pi*.5)
  end
  terrain(ix-ir-40,ix+ir+40,iz-ir-40,iz+ir+40,14,h,dist)
  for j=0,3 do
   local a=k*1.9+j*1.6;local r=ir*(.25+.35*hash(k*7+j))
   local x,z=ix+math.cos(a)*r,iz+math.sin(a)*r
   place(({'palm-bend','palm-straight','palm-detailed-bend'})[(k+j)%3+1],x,z,7+hash(k+j)*3,a,{y=h(x,z)-.5})
  end
 end
 local ground=#rows
 -- Log rafts: lashed logs along X with two cross beams on top.
 local function cylinder(x0,x1,y,z,r,c)
  local sides=10
  for i=0,sides-1 do
   local a,b=i/sides*math.pi*2,(i+1)/sides*math.pi*2
   local ya,za,yb,zb=math.sin(a),math.cos(a),math.sin(b),math.cos(b)
   local p={{x0,y+ya*r,z+za*r},{x1,y+ya*r,z+za*r},{x1,y+yb*r,z+zb*r},{x0,y+yb*r,z+zb*r}}
   local nm=(ya+yb)*.5;local nz=(za+zb)*.5
   for _,k in ipairs({1,2,3,1,3,4}) do v(p[k][1],p[k][2],p[k][3],0,nm,nz,c,2) end
   -- Pale cut ends.
   for _,e in ipairs({{x0,-1},{x1,1}}) do
    local ends={{e[1],y,z},{e[1],y+ya*r,z+za*r},{e[1],y+yb*r,z+zb*r}}
    for _,q in ipairs(ends) do v(q[1],q[2],q[3],e[2],0,0,{.74,.62,.46},2) end
   end
  end
 end
 local function beam(x,y,z,lx,ly,lz,c)
  local faces={
   {{-1,1,-1},{1,1,-1},{1,1,1},{-1,1,1},{0,1,0}},
   {{1,-1,-1},{1,-1,1},{1,1,1},{1,1,-1},{1,0,0}},
   {{-1,-1,1},{-1,-1,-1},{-1,1,-1},{-1,1,1},{-1,0,0}},
   {{-1,-1,-1},{1,-1,-1},{1,1,-1},{-1,1,-1},{0,0,-1}},
   {{1,-1,1},{-1,-1,1},{-1,1,1},{1,1,1},{0,0,1}},
  }
  for _,f in ipairs(faces) do
   local q={}
   for n=1,4 do q[n]={x+f[n][1]*lx,y+f[n][2]*ly,z+f[n][3]*lz} end
   for _,k in ipairs({1,3,2,1,4,3}) do v(q[k][1],q[k][2],q[k][3],f[5][1],f[5][2],f[5][3],c,2) end
  end
 end
 for index,rz in ipairs(Ocean.RAFTS) do
  local logs=7
  for i=0,logs-1 do
   local z=rz-RAFT_Z+1.07+i*2.14
   local len=RAFT_X-.6+hash(index*20+i)*1.4
   local shade=.9+hash(index*30+i)*.18
   cylinder(-len,len+hash(index*40+i)*.8,-.92,z,1.07,{.56*shade,.43*shade,.30*shade})
  end
  for _,x in ipairs({-8.5,8.5}) do beam(x,.3,rz,1.1,.28,RAFT_Z+.4,{.50,.38,.27}) end
  -- Rope lashings where the beams cross the outer logs.
  for _,x in ipairs({-8.5,8.5}) do for _,side in ipairs({-1,1}) do
   beam(x,.2,rz+side*(RAFT_Z-.9),1.3,.5,.35,{.80,.72,.54})
  end end
 end
 -- Palms line the island beach, thickest on the side facing the battle.
 local palms={'palm-bend','palm-straight','palm-detailed-bend'}
 for i=0,43 do
  local a=math.pi*.45+i*.105+hash(i)*.06
  local x,z=coastPoint(22+hash(i+30)*34,a)
  place(palms[i%3+1],x,z,6.5+hash(i+60)*2.4,a+math.pi+(hash(i+90)-.5)*1.4,{variation=.92+hash(i+5)*.16})
 end
 for i=0,119 do
  local a=i*.0524+hash(i+200)*.04
  local x,z=coastPoint(34+hash(i+210)*90,a)
  if i%3==0 then place('plant_bush',x,z,26+hash(i)*16,hash(i+7)*6.28,{tone={.33,.50,.28}})
  else place('grass-plant',x,z,5+hash(i)*4,hash(i+11)*6.28,{variation=.9+hash(i+3)*.2}) end
 end
 for i=0,41 do
  local a=i*.15+hash(i+300)*.08
  local x,z=coastPoint(120+hash(i+310)*120,a)
  place(i%2==0 and 'tree_oak_lod' or 'tree_fat_lod',x,z,30+hash(i+320)*18,hash(i+330)*6.28,{tone={.34,.50,.28}})
 end
 -- A plank pier runs out from the island beach towards the battle.
 local pa=math.pi*.93
 local ox,oz=coastPoint(12,pa)
 local ux,uz=math.cos(pa),math.sin(pa)   -- along the pier, out to sea
 local wx,wz=-uz,ux                       -- across the pier
 local deck=1.2
 local function box(cx,cy,cz,lx,ly,lz,c)
  local function corner(i,j,k) return {cx+ux*lx*i+wx*lz*k,cy+ly*j,cz+uz*lx*i+wz*lz*k} end
  local faces={
   {{-1,1,-1},{1,1,-1},{1,1,1},{-1,1,1},{0,1,0}},
   {{1,-1,-1},{1,-1,1},{1,1,1},{1,1,-1},{ux,0,uz}},
   {{-1,-1,1},{-1,-1,-1},{-1,1,-1},{-1,1,1},{-ux,0,-uz}},
   {{-1,-1,-1},{1,-1,-1},{1,1,-1},{-1,1,-1},{-wx,0,-wz}},
   {{1,-1,1},{-1,-1,1},{-1,1,1},{1,1,1},{wx,0,wz}},
  }
  for _,f in ipairs(faces) do
   local q={corner(unpack(f[1])),corner(unpack(f[2])),corner(unpack(f[3])),corner(unpack(f[4]))}
   for _,k in ipairs({1,3,2,1,4,3}) do v(q[k][1],q[k][2],q[k][3],f[5][1],f[5][2],f[5][3],c,2) end
  end
 end
 local length=84
 for k=0,length-1,3 do
  local shade=.92+hash(k+500)*.14
  box(ox+ux*(k+1.5),deck,oz+uz*(k+1.5),1.35,.35,6.5,{.58*shade,.45*shade,.32*shade})
 end
 for k=0,length,12 do for _,side in ipairs({-1,1}) do
  box(ox+ux*k+wx*6*side,-2.2,oz+uz*k+wz*6*side,.8,3.6,.8,{.45,.35,.26})
 end end
 local ex,ez=ox+ux*(length-6),oz+uz*(length-6)
 place('barrel',ex+wx*3,ez+wz*3,5,.4,{y=deck+.35});place('barrel',ex+wx*3-ux*4,ez+wz*3-uz*4,5,1.1,{y=deck+.35})
 place('crate',ex-wx*3,ez-wz*3,6,.2,{y=deck+.35})
 local bx,bz=coastPoint(2,pa+.12)
 place('boat-row-small',bx,bz,7,pa+1.2,{y=height(bx,bz)-.4})
 -- Rocks on the island shore, and sea stacks with their own foam.
 for i=0,21 do
  local a=i*.29+hash(i+400)*.1
  if math.abs(a-pa)>.08 then
   local x,z=coastPoint(-2+hash(i+410)*7,a)
   place(({'rocks-a','rocks-b','rocks-c'})[i%3+1],x,z,3+hash(i+420)*3,hash(i+430)*6.28,{y=-1.6})
  end
 end
 -- Sea stacks: tapering painted rock pillars with grassy crowns.
 local function stack(x,z,radius,tall,seed)
  local sides,levels=14,9
  local function point(i,j)
   local a=i/sides*math.pi*2;local f=j/levels
   local bumps=1+.16*math.sin(a*3+seed)+.09*math.sin(a*5+seed*2.3)+.06*math.sin(f*9+a*2+seed)
   local r=radius*(1-.42*f^1.4)*bumps
   return {x+math.cos(a)*r,-3+f*(tall+3),z+math.sin(a)*r}
  end
  for j=0,levels-1 do for i=0,sides-1 do
   local p1,p2,p3,p4=point(i,j),point(i+1,j),point(i+1,j+1),point(i,j+1)
   local a=(i+.5)/sides*math.pi*2
   local crown=j>=levels-2
   local shade=.9+hash(seed*50+j*sides+i)*.16
   local c=crown and {.36*shade,.50*shade,.29*shade} or {.58*shade,.56*shade,.50*shade}
   for _,q in ipairs({p1,p3,p2,p1,p4,p3}) do v(q[1],q[2],q[3],math.cos(a),.25,math.sin(a),c,crown and 1 or 3) end
  end end
  local top=-3+tall+3
  for i=0,sides-1 do
   local p1,p2=point(i,levels),point(i+1,levels)
   for _,q in ipairs({{x,top+radius*.12,z},p2,p1}) do v(q[1],q[2],q[3],0,1,0,{.38,.53,.30},1) end
  end
 end
 for i,st in ipairs({{-190,-280,20,46},{-340,-60,15,34},{-470,-420,28,62},{-170,230,12,26},{-280,-560,17,40},{130,160,11,24},{-90,-420,9,20}}) do
  stack(st[1],st[2],st[3],st[4],i*1.37)
 end
 -- Boats on the horizon.
 place('boat-sail',-330,-560,12,.9,{y=-1.4})
 place('boat-fishing',-600,-150,10,2.2,{y=-1.4})
 require("mods.STADIUM2_IMPORTER.lib.visitor_navigation").build("ocean",rows)
 Ocean.triangles=#rows/3;return rows,ground
end

function Ocean.ensurePaint(g)
 if not paint then
  paint=image(g,'assets/kenney_nature/watercolor-materials.png','watercolor-materials.png')
  paint:setFilter('linear','linear',4);paint:setMipmapFilter('linear')
 end
end
local function ensure(g)
 if not mesh then local rows,ground=Ocean.vertices();mesh=Chunks.new(g,FORMAT,rows,ground) end
 if not shader then shader=g.newShader(Instances.shader(LAND));seaShader=g.newShader(SEA) end
 if not sea then
  -- Rings get denser near the battle so fog and foam stay smooth.
  local rows,radii={},{0,40,90,160,260,420,700,1100,1700}
  for r=1,#radii-1 do for i=0,127 do
   local a,b=i*math.pi/64,(i+1)*math.pi/64
   local r0,r1=radii[r],radii[r+1]
   local p={{math.cos(a)*r0,math.sin(a)*r0},{math.cos(b)*r0,math.sin(b)*r0},{math.cos(b)*r1,math.sin(b)*r1},{math.cos(a)*r1,math.sin(a)*r1}}
   for _,k in ipairs({1,3,2,1,4,3}) do rows[#rows+1]={p[k][1],-.95,p[k][2],0,1,0,1,1,1,0} end
  end end
  sea=g.newMesh(FORMAT,rows,'triangles','static')
 end
 Ocean.ensurePaint(g)
end
function Ocean.castShadow(g,vp)
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
function Ocean.updateTorchShadows() end
function Ocean.drawEffects() end
local function bindCommon(s,frame,env,shadow)
 s:send('vp','row',frame.vp);s:send('sunVP','row',shadow and shadow.sunVP or frame.vp)
 s:send('sunEnabled',shadow and shadow.map and 1 or 0)
 if shadow and shadow.map then s:send('sunMap',shadow.map) end
 s:send('tint',env.modelTint or {1,1,1});s:send('eye',frame.eye)
 s:send('lightDir',env.light or {-.4,-1,-.3});s:send('paint',paint)
end
function Ocean.draw(g,frame,env,shadow)
 ensure(g);g.setColor(1,1,1,1);g.setDepthMode('lequal',true);g.setMeshCullMode('none');g.setBlendMode('alpha','alphamultiply')
 g.setShader(shader);bindCommon(shader,frame,env,shadow);mesh:draw(g,frame.vp)
 g.setShader(seaShader);bindCommon(seaShader,frame,env,shadow)
 seaShader:send('time',love.timer and love.timer.getTime()%1000 or 0)
 seaShader:send('night',env.daytime=='NITE' and 1 or 0)
 g.draw(sea);g.setShader();return true
end
function Ocean.endBattle() end
function Ocean.release()
 require("mods.STADIUM2_IMPORTER.lib.visitor_navigation").clear("ocean")
 for _,r in pairs({mesh,sea,shader,seaShader,paint,sky,skyMesh,skyShader,shadowShader}) do if r and r.release then r:release() end end
 mesh,sea,shader,seaShader,paint,sky,skyMesh,skyShader,shadowShader=nil,nil,nil,nil,nil,nil,nil,nil,nil
end
return Ocean
