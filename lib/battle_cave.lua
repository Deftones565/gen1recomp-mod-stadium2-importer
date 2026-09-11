-- Cached, fully enclosed cavern built from Kenney's Modular Cave Kit.
local Mat=require('mods.STADIUM2_IMPORTER.lib.renderer')
local Nature=require('mods.STADIUM2_IMPORTER.lib.battle_nature')
local Torches=require('mods.STADIUM2_IMPORTER.lib.battle_torches')
local Shadows=require('mods.STADIUM2_IMPORTER.lib.battle_torch_shadows').new()
local Cave={}
local mesh,shader,texture,vertices,modRef
local FORMAT={{'VertexPosition','float',3},{'SurfaceNormal','float',3},{'SurfaceColor','float',3},{'SurfaceMaterial','float',1}}
local SOURCE=[[
varying vec3 world;varying vec3 normal;varying vec3 pigment;varying float material;varying vec3 sunPosition;
#ifdef VERTEX
uniform mat4 vp;uniform mat4 sunVP;
attribute vec3 SurfaceNormal;attribute vec3 SurfaceColor;attribute float SurfaceMaterial;
vec4 position(mat4 tp,vec4 p){world=p.xyz;normal=SurfaceNormal;pigment=SurfaceColor;material=SurfaceMaterial;sunPosition=(sunVP*p).xyz;return vp*p;}
#endif
#ifdef PIXEL
uniform Image stone;uniform vec3 eye;uniform Image torchMap1;uniform Image torchMap2;
uniform vec3 torch1;uniform vec3 torch2;uniform float torchShadows;uniform float power;
uniform Image sunMap;uniform float sunEnabled;uniform vec2 sunTexel;
]]..require('mods.STADIUM2_IMPORTER.lib.torch_projection').source..[[
vec3 paperStone(vec2 uv,float bark){
 vec2 tile=abs(fract(uv*.5)*2.-1.);
 return Texel(stone,mix(vec2(.008,.508),vec2(.508,.008),bark)+tile*.484).rgb;
}
vec3 stoneColor(vec3 p,vec3 n){
 vec3 w=pow(abs(n),vec3(4.));w/=max(.001,w.x+w.y+w.z);
 vec3 rgb=vec3(0.);float bark=step(1.5,material)*step(material,2.5);
 if(w.x>.001)rgb+=paperStone(p.zy*.10,bark)*w.x;
 if(w.y>.001)rgb+=paperStone(p.xz*.10,bark)*w.y;
 if(w.z>.001)rgb+=paperStone(p.xy*.10,bark)*w.z;
 return mix(rgb,pigment,.62);
}
float pointLight(Image map,vec3 light,vec3 n){
 vec3 ray=light-world;float d=length(ray);float f=max(0.,1.-d/100.);
 if(f<=0.)return 0.;
 float vis=torchShadows>.5?torchVisibility(map,light,world,n):1.;
 return f*f*(.15+.85*max(0.,dot(n,ray/max(d,.001))))*vis;
}
vec4 effect(vec4 color,Image tex,vec2 uv,vec2 px){
 vec3 n=normalize(normal);vec3 surface=stoneColor(world,n);
 if(material<.5){
  vec3 broad=paperStone(vec2(world.x-world.z,world.x+world.z)*.023,0.);
  surface=mix(surface,broad*vec3(.80,.76,.72),.32);
 }
 float strata=.94+.06*sin(world.y*.65+sin(world.x*.11)+sin(world.z*.12));
 float floorShade=1.;
 if(material<.5 && sunEnabled>.5 && sunPosition.x>0. && sunPosition.x<1. && sunPosition.y>0. && sunPosition.y<1.){
  float lit=0.;
  for(int x=0;x<2;x++){for(int y=0;y<2;y++){
   vec4 d=Texel(sunMap,sunPosition.xy+(vec2(float(x),float(y))-.5)*sunTexel*2.);
   lit+=step(sunPosition.z-.003,d.r+d.g/255.);
  }}floorShade=.72+.28*lit*.25;
 }
 // Cool bounced light reveals rock relief; torches supply warm direct light.
 vec3 fill=vec3(.34,.38,.47)+vec3(.12,.12,.13)*max(n.y,0.);
 float heightFade=1.-smoothstep(65.,155.,world.y)*.65;
 vec3 rgb=surface*fill*strata*floorShade*heightFade;
 float warm=pointLight(torchMap1,torch1,n)+pointLight(torchMap2,torch2,n);
 rgb+=surface*vec3(1.65,.75,.22)*warm*power;
 float fog=smoothstep(125.,270.,length(world-eye));
 rgb=mix(rgb,vec3(.035,.046,.066),fog);
 return vec4(rgb,1.);
}
#endif
]]
Cave.source=SOURCE
function Cave.bind(mod)
 if modRef and modRef~=mod then Cave.release() end
 modRef=mod
end
function Cave.matches(ctx,environment)
 ctx=ctx or {}
 local env=ctx.environment or (environment and environment.environment)
 local terrain=tostring(ctx.terrain or ''):lower()
 local kind=tostring(ctx.battleType or ''):lower()
 -- Cave-water layouts are a later variant; preserve the current water fallback.
 return env=='CAVE' and (ctx.kind=='wild' or ctx.kind=='trainer')
  and terrain~='water' and terrain~='surf' and kind~='fish' and kind~='fishing'
end
function Cave.lighting(env)
 local out={};for k,v in pairs(env or {}) do out[k]=v end
 out.modelTint={.82,.86,.96};out.ambient={.38,.40,.47};out.diffuse={.20,.22,.28}
 out.light={-.3,-1,-.2};out.shadowStrength=.40
 out.bands={{.035,.046,.066},{.035,.046,.066}}
 return out
end
Cave.frame=Nature.frame
function Cave.vertices()
 local models=require('mods.STADIUM2_IMPORTER.assets.kenney_cave.models')
 local out={}
 local function v(p,n,c,material) out[#out+1]={p[1],p[2],p[3],n[1],n[2],n[3],c[1],c[2],c[3],material or 3} end
 local function tri(a,b,c,tone,material)
  local u={b[1]-a[1],b[2]-a[2],b[3]-a[3]};local w={c[1]-a[1],c[2]-a[2],c[3]-a[3]}
  local n={u[2]*w[3]-u[3]*w[2],u[3]*w[1]-u[1]*w[3],u[1]*w[2]-u[2]*w[1]}
  local len=math.sqrt(n[1]^2+n[2]^2+n[3]^2)
  for k=1,3 do n[k]=n[k]/math.max(len,.001) end
  v(a,n,tone,material);v(b,n,tone,material);v(c,n,tone,material)
 end
 local function hash(i) return (math.sin(i*127.1+311.7)*43758.5453)%1 end
 local function place(name,x,y,z,sx,sy,sz,yaw,tone)
  local c,s=math.cos(yaw),math.sin(yaw)
  for _,p in ipairs(models[name]) do
   local nx,ny,nz=p[4]/sx,p[5]/sy,p[6]/sz
   local len=math.sqrt(nx*nx+ny*ny+nz*nz)
   v({x+p[1]*sx*c+p[3]*sz*s,y+p[2]*sy,z-p[1]*sx*s+p[3]*sz*c},
    {(nx*c+nz*s)/len,ny/len,(-nx*s+nz*c)/len},tone,3)
  end
 end
 -- A continuous floor extends beneath all walls and tunnel scenery.
 for x=-300,290,10 do for z=-300,290,10 do
  local function point(a,b) return {a,-.14-math.max(0,math.sqrt(a*a+b*b)-48)*.007,b} end
  local shade=.40+hash(x*19+z)*.06;local tone={shade,shade*.96,shade*.91}
  tri(point(x,z),point(x,z+10),point(x+10,z+10),tone,0)
  tri(point(x,z),point(x+10,z+10),point(x+10,z),tone,0)
 end end
 -- Dense overlapping walls and a continuous vaulted shell close every view.
 for i=0,19 do
  local a=i*math.pi/10;local radius=147+hash(i)*10
  place('template-wall',math.cos(a)*radius,-.4,math.sin(a)*radius,13,22+hash(i+1)*5,15,-a-math.pi/2,{.43,.40,.38})
 end
 local function ceiling(a,r,y) return {math.cos(a)*r,y+math.sin(a*5)*3,math.sin(a)*r} end
 for ring=0,5 do for i=0,63 do
  local a,b=i*math.pi/32,(i+1)*math.pi/32
  local r0,r1=ring*38,(ring+1)*38
  local y0,y1=155-ring*10,145-ring*10
  local p,q,r,s=ceiling(a,r0,y0),ceiling(b,r0,y0),ceiling(b,r1,y1),ceiling(a,r1,y1)
  tri(p,r,q,{.31,.32,.36});tri(p,s,r,{.31,.32,.36})
 end end
 for i=0,31 do
  local a=i*2.39996;local r=108+hash(i+20)*27
  place('template-detail',math.cos(a)*r,0,math.sin(a)*r,3+hash(i)*3,5+hash(i+2)*8,3+hash(i+1)*3,a,{.44,.42,.40})
  if i%2==0 then
   place('template-detail',math.cos(a)*r,115,math.sin(a)*r,3,-7-hash(i+41)*7,3,a,{.33,.34,.38})
  end
 end
 -- Rubble stays mostly at the wall bases; the fighting lane stays open.
 for i=0,159 do
  local a=i*2.39996;local r=55+hash(i+200)*82
  local size=5+hash(i+150)*17
  place('rock_smallA',math.cos(a)*r,-.15,math.sin(a)*r,size,size*(.5+hash(i)),size,a,{.45,.43,.40})
 end
 for i=0,74 do
  local a=i*2.39996;local r=26+hash(i+440)*70
  local x,z=math.cos(a)*r,math.sin(a)*r
  if math.abs(x+z)>18 then
   local size=1+hash(i+441)*3
   place('rock_smallA',x,-.12,z,size,size*.45,size,a,{.40,.39,.38})
  end
 end
 -- A framed passage suggests deeper chambers; the far wall remains dark.
 place('gate-rock',-115,0,-72,12,13,12,math.pi*.4,{.35,.33,.34})
 for _,p in ipairs(Torches.positions) do
  for section=1,2 do
   local bottom,top=section==1 and 0 or p[2]-.8,section==1 and p[2]-.4 or p[2]
   local radius=section==1 and .4 or .72
   for k=0,7 do
    local a,b=k*math.pi/4,(k+1)*math.pi/4
    local q={p[1]+math.cos(a)*radius,bottom,p[3]+math.sin(a)*radius}
    local r={p[1]+math.cos(b)*radius,bottom,p[3]+math.sin(b)*radius}
    local s={r[1],top,r[3]};local t={q[1],top,q[3]}
    tri(q,r,s,{.32,.21,.12},2);tri(q,s,t,{.32,.21,.12},2)
   end
  end
 end
 Cave.triangles=#out/3;vertices=out;return out
end
local function ensure(g)
 if not mesh then mesh=g.newMesh(FORMAT,Cave.vertices(),'triangles','static') end
 if not shader then shader=g.newShader(SOURCE) end
 if not texture then
  local path='assets/kenney_nature/watercolor-materials.png'
  local data=modRef and love.filesystem.newFileData(assert(modRef:read(path)),'watercolor-materials.png') or 'mods/STADIUM2_IMPORTER/'..path
  texture=g.newImage(data,{mipmaps=true});texture:setFilter('linear','linear',4);texture:setMipmapFilter('linear')
 end
end
function Cave.sky() end -- The scene clear and enclosed geometry replace the sky.
function Cave.castShadow(g) ensure(g) end -- Broad bounced fill; torch maps handle walls.
function Cave.updateTorchShadows(g,actors,matrices,modes)
 ensure(g);Shadows.night=true
 local result=Shadows.update(g,vertices or {},FORMAT,actors,matrices,modes)
 if result then vertices=nil end
 return result
end
Cave.bindTorchLighting=Shadows.bindModel
function Cave.draw(g,frame,environment,shadow)
 ensure(g)
 g.setDepthMode('lequal',true);g.setMeshCullMode('none');g.setBlendMode('alpha','alphamultiply')
 g.setColor(1,1,1,1);g.setShader(shader)
 shader:send('vp','row',frame.vp);shader:send('eye',frame.eye);shader:send('stone',texture)
 shader:send('sunVP','row',shadow and shadow.sunVP or frame.vp)
 shader:send('sunEnabled',shadow and shadow.map and 1 or 0)
 if shadow and shadow.map then shader:send('sunMap',shadow.map) end
 shader:send('sunTexel',shadow and shadow.sunTexel or {1/1024,1/1024})
 shader:send('power',1.8*Torches.flicker(Torches.time()))
 for i,p in ipairs(Torches.positions) do shader:send('torch'..i,{p[1],p[2]+1,p[3]}) end
 Shadows.send(shader);g.draw(mesh);g.setShader();return true
end
function Cave.endBattle() Shadows.resetDynamic() end
function Cave.release()
 Shadows.release()
 for _,v in pairs({mesh,shader,texture}) do v:release() end
 mesh,shader,texture,vertices=nil,nil,nil,nil
end
return Cave
