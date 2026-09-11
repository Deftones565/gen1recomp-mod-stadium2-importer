-- Textured Kenney Nature Kit woodland clearing.
local Torches=require("mods.STADIUM2_IMPORTER.lib.battle_torches")
local TorchShadows=require("mods.STADIUM2_IMPORTER.lib.battle_torch_shadows")
local Nature={}
local Perch=require('mods.STADIUM2_IMPORTER.lib.woodland_perch')
local shadowVertices
local mesh,shader,grassTexture,shadowShader,skyTexture,watercolorTexture,skyShader
local skyMesh
local modRef
function Nature.bind(mod)
 if modRef and modRef~=mod then Nature.release() end
 modRef=mod
end
local function imageAsset(g,name)
  local path="assets/kenney_nature/"..name
  local source="mods/STADIUM2_IMPORTER/"..path
  if modRef then
    local bytes=assert(modRef:read(path),"Missing Nature asset: "..path)
    source=love.filesystem.newFileData(bytes,name)
  end
  return g.newImage(source,{mipmaps=true})
end
local FORMAT={{"VertexPosition","float",3},{"SurfaceNormal","float",3},{"SurfaceColor","float",3},{"SurfaceMaterial","float",1}}
local SHADER=[[
varying float material; varying vec3 normal; varying vec3 albedo; varying vec3 sunPosition; varying vec3 worldPosition;
#ifdef VERTEX
attribute float SurfaceMaterial; attribute vec3 SurfaceNormal; attribute vec3 SurfaceColor;
uniform mat4 vp; uniform mat4 sunVP;
vec4 position(mat4 transform_projection,vec4 p){
 material=SurfaceMaterial; worldPosition=p.xyz; normal=SurfaceNormal; albedo=SurfaceColor; sunPosition=(sunVP*p).xyz; return vp*p;
}
#endif
#ifdef PIXEL
uniform float torchStrength; uniform float flicker; uniform vec3 torch1; uniform vec3 torch2; uniform Image torchMap1; uniform Image torchMap2;  uniform float torchShadows;
uniform vec3 lightDir; uniform vec3 tint; uniform vec3 eye;
uniform Image paintMap; uniform Image grassMap; uniform Image sunMap; uniform vec2 sunTexel; uniform float sunEnabled; uniform float sunBias; uniform float sunDark;
vec3 paint(vec2 uv,vec2 quadrant){
 vec2 mirrorUV=abs(fract(uv*.5)*2.-1.);
 // Stay inside the material tile, including at mipmapped grazing angles.
 return Texel(paintMap,quadrant*.5+vec2(.008)+mirrorUV*.484).rgb;
}
vec3 materialPaint(vec3 p,vec3 n,vec2 quadrant,vec2 scale){
 vec3 weights=pow(abs(n),vec3(4.));weights/=max(.0001,weights.x+weights.y+weights.z);
 vec3 result=vec3(0.);
 if(weights.x>.001)result+=paint(p.zy*scale,quadrant)*weights.x;
 if(weights.y>.001)result+=paint(p.xz*scale,quadrant)*weights.y;
 if(weights.z>.001)result+=paint(p.xy*scale,quadrant)*weights.z;
 return result;
}
]]..require("mods.STADIUM2_IMPORTER.lib.torch_projection").source..[[
float visibility(Image map,vec3 light,vec3 p,vec3 n){
 if(torchShadows<.5)return 1.;
 return torchVisibility(map,light,p,n);
}
float torchLight(vec3 light,vec3 n){
 vec3 delta=light-worldPosition;float d=length(delta);
 float falloff=max(0.,1.-d/100.);falloff*=falloff;
 return falloff*(.30+.70*max(0.,dot(n,normalize(delta))));
}
vec4 effect(vec4 color,Image tex,vec2 uv,vec2 screen){
 float sun=max(0.,dot(normalize(normal),normalize(-lightDir)));
 float hemisphere=normalize(normal).y*.5+.5;
 vec3 illumination=mix(vec3(.45,.52,.46),vec3(.64,.73,.83),hemisphere)
   +vec3(.48,.39,.24)*sun;
 float shade=1.;
 if(worldPosition.y<-.05 && sunEnabled>.5 && sunPosition.x>0. && sunPosition.x<1. && sunPosition.y>0. && sunPosition.y<1. && sunPosition.z<1.){
  float lit=0.;
  for(int x=-1;x<=1;x++){for(int y=-1;y<=1;y++){
    vec4 d=Texel(sunMap,sunPosition.xy+vec2(float(x),float(y))*sunTexel*1.5);
    lit+=step(sunPosition.z-sunBias,d.r+d.g/255.);
  }}
  shade=1.-sunDark*(1.-lit/9.);
 }
 float mist=smoothstep(140.,460.,length(worldPosition-eye));
 vec3 surface=albedo;
 if(worldPosition.y<-.05){
   vec2 tile=worldPosition.xz/38.;
   vec2 uvA=abs(fract(tile*.5)*2.-1.);
   vec2 uvB=abs(fract(vec2(-tile.y,tile.x)*.685+.27)*2.-1.);
   vec3 grass=mix(Texel(grassMap,uvA).rgb,Texel(grassMap,uvB).rgb,.28);
   surface=mix(grass,vec3(.43,.55,.29),.36)*(.80+.30*albedo.g);
 }
 vec3 n=normalize(normal);
 vec3 wash=materialPaint(worldPosition,n,vec2(1.,1.),vec2(.095));
 if(material>.5 && material<1.5){
   vec3 leaves=materialPaint(worldPosition,n,vec2(0.,0.),vec2(.075));
      vec3 leafBase=mix(vec3(.43,.56,.30),albedo,.25);
   surface=mix(leaves,leafBase,.44);
   surface*=.90+.10*smoothstep(0.,18.,worldPosition.y);
 }else if(material<2.5 && material>1.5){
   vec3 bark=materialPaint(worldPosition,n,vec2(1.,0.),vec2(.19,.07));
   surface=mix(bark,albedo,.40);
 }else if(material<3.5 && material>2.5){
   surface=mix(materialPaint(worldPosition,n,vec2(0.,1.),vec2(.14)),albedo,.18);
 }else if(material>3.5){
   surface=mix(albedo,vec3(.77,.73,.65),.16)*(wash*.38+.68);
 }
 if(material<.5){
   float luma=dot(surface,vec3(.25,.6,.15));
   surface=mix(surface,vec3(luma)*vec3(.98,1.04,.88),.30);
 }
 surface=surface*(wash*.23+.81);
 vec3 rgb=surface*illumination*shade;
 rgb=mix(rgb,vec3(.87,.85,.73),.025);

 vec3 lit=mix(rgb,vec3(.27,.35,.28),mist)*tint;
 float pool=torchLight(torch1,n)*visibility(torchMap1,torch1,worldPosition,n)+torchLight(torch2,n)*visibility(torchMap2,torch2,worldPosition,n);
 lit+=surface*vec3(1.65,.75,.22)*pool*torchStrength*flicker;
 return vec4(lit,1.);
}
#endif
]]

-- Use encounter metadata, never species or battle RNG. Unknown/unsupported
-- contexts retain the normal presentation, including water and indoor fights.
-- Copy the resolved environment: keep time-of-day meaning and sun direction,
-- but balance actor lighting against the scene's cool fill and warm sunlight.
function Nature.lighting(environment)
 local out={}
 for k,v in pairs(environment or {}) do out[k]=v end
 local night=out.daytime=="NITE"
 out.modelTint=night and {.19,.24,.36} or out.modelTint
 out.ambient=night and {.22,.27,.38} or {.62,.66,.70}
 out.diffuse=night and {.30,.36,.50} or {.86,.78,.64}
 return out
end

function Nature.matches(ctx,environment)
  ctx=ctx or {}
  local terrain=tostring(ctx.terrain or ""):lower()
  local kind=tostring(ctx.battleType or ""):lower()
  if terrain=="water" or terrain=="surf" or kind=="fish" or kind=="fishing" then return false end
  local env=ctx.environment or (environment and environment.environment)
  if env~="ROUTE" and env~="TOWN" and env~="FOREST" then return false end
  return ctx.kind=="trainer" or terrain=="grass"
end

function Nature.vertices()
  local models=require("mods.STADIUM2_IMPORTER.assets.kenney_nature.models")
  local vertices,trees={},{}
  local function vertex(x,y,z,nx,ny,nz,c,material)
    vertices[#vertices+1]={x,y,z,nx,ny,nz,c[1],c[2],c[3],material or 0}
  end
  -- Composition coordinates: u runs across the default view, d into the woods.
  local function world(u,d) return (u-d)*.70710678,(-u-d)*.70710678 end
  local function hash(i) return (math.sin(i*127.1+311.7)*43758.5453)%1 end
  local function tree(u,d,size,variant,yaw)
    local x,z=Perch.treePosition(u,d)
    local radius=math.sqrt(u*u+d*d)
    if radius<108 then u,d=u*108/radius,d*108/radius end
    if (u+86)^2+(d+72)^2<38^2 then return end
    trees[#trees+1]={x=x,z=z,size=size,variant=variant or 1,yaw=yaw}
  end
  -- Irregular overlapping rows, with a small sunlit opening at centre-right.
  for i=0,17 do tree(-104+i*12,88+hash(i)*14,23+hash(i+3)*10,i%3+1) end
  for i=0,13 do tree(-84+i*13,65+hash(i+20)*10,19+hash(i+2)*9,i%3+1) end
  for _,t in ipairs({{-65,24,27},{-48,39,23},{Perch.u,Perch.d,Perch.size,Perch.yaw},{-11,65,20},
    {22,62,20},{42,44,24},{62,25,26},{-54,-3,25},{57,-2,27}}) do
    tree(t[1],t[2],t[3],1,t[4])
  end
  -- Finish the perimeter beyond the camera orbit, including the old foreground.
  for ring=0,2 do for i=0,43 do
    local angle=i*math.pi*2/44+ring*.23
    local radius=94+ring*33+hash(i+ring*50)*13
    local u,d=math.cos(angle)*radius,math.sin(angle)*radius
    if d<25 or math.abs(u)>100 then
      tree(u,d,23+hash(i+ring*9)*14,2+i%2)
    end
  end end
  for ring=0,2 do for i=0,59 do
    local angle=(i+hash(i+901)*.5)*math.pi*2/60
    local radius=205+ring*65+hash(i+930)*24
    tree(math.cos(angle)*radius,math.sin(angle)*radius,32+hash(i+980)*22,2+i%2)
  end end
  local groundColors={}
  local function ground(x,z)
    local key=x..":"..z
    if groundColors[key] then return groundColors[key] end
    local u=(x-z)*.70710678;local d=-(x+z)*.70710678
    local clearing=math.exp(-((u/35)^2+(d/43)^2))
    local variation=.045*math.sin(x*.21+math.sin(z*.13)*2)*math.cos(z*.24)
    local c={.30+.23*clearing+variation,.52+.20*clearing+variation,.18+.10*clearing+variation*.4}
    local shade=0
    for _,t in ipairs(trees) do
      local dx,dz=(x-t.x)/ (t.size*.34),(z-t.z)/(t.size*.30)
      shade=math.max(shade,.32*math.exp(-(dx*dx+dz*dz)*1.5))
    end
    for j=1,3 do c[j]=c[j]*(1-shade) end
    groundColors[key]=c
    return c
  end
  -- Static vertex colour ground: mottled meadow + broad baked contact shade.
  -- The painted grass material modulates these broad colour and contact shades.
  for x=-180,174,6 do for z=-180,174,6 do
    for _,p in ipairs({{x,z},{x+6,z},{x+6,z+6},{x,z},{x+6,z+6},{x,z+6}}) do
      vertex(p[1],-.12,p[2],0,1,0,ground(p[1],p[2]))
    end
  end end
  -- A distant ground apron removes the finite square edge at high pitch/zoom.
  for i=0,95 do
    local a,b=i*math.pi/48,(i+1)*math.pi/48
    local points={{math.cos(a)*170,math.sin(a)*170}, {math.cos(a)*950,math.sin(a)*950},
      {math.cos(b)*950,math.sin(b)*950}, {math.cos(a)*170,math.sin(a)*170},
      {math.cos(b)*950,math.sin(b)*950}, {math.cos(b)*170,math.sin(b)*170}}
    for _,p in ipairs(points) do vertex(p[1],-.18,p[2],0,1,0,{.35,.49,.27}) end
  end
  Nature.groundVertices=#vertices
  local function place(name,x,z,size,yaw,tone)
    local c,s=math.cos(yaw),math.sin(yaw)
    tone=tone or 1
    for _,v in ipairs(models[name]) do
      local foliage=v[10]==1
      local lift=foliage and (.80+.20*math.min(1,v[2]*3)) or 1
      local color={v[7]*tone*lift,v[8]*tone*lift,v[9]*tone*lift}
      vertex(x+(v[1]*c+v[3]*s)*size,v[2]*size,z+(-v[1]*s+v[3]*c)*size,
        v[4]*c+v[6]*s,v[5],-v[4]*s+v[6]*c,color,v[10])
    end
  end
  for i,t in ipairs(trees) do
    local name=({"tree_detailed","tree_oak","tree_fat"})[t.variant]
    if t.x*t.x+t.z*t.z>150^2 then name=name.."_lod" end
    place(name,t.x,t.z,t.size,t.yaw or i*2.4,.88+hash(i)*.24)
  end
  -- Understory grows in uneven patches around the actual tree positions,
  -- rather than another concentric border around the battle clearing.
  for i,t in ipairs(trees) do
    local patchAngle=hash(i+700)*math.pi*2
    for j=1,(t.x*t.x+t.z*t.z<190^2 and 9 or 0) do
      local seed=i*19+j
      local angle=patchAngle+(hash(seed+301)-.5)*4.8
      local radius=3+hash(seed+411)*14
      local x,z=t.x+math.cos(angle)*radius,t.z+math.sin(angle)*radius
      local u,d=(x-z)*.70710678,-(x+z)*.70710678
      -- Keep the trail shelter's footprint and approach open.
      if (u+86)^2+(d+72)^2>24^2 then
        local name=j<=3 and "plant_bush" or j<=6 and "grass_leafs" or "grass"
        local size=j<=3 and 15+hash(seed+9)*15 or 8+hash(seed+13)*10
        place(name,x,z,size,angle,.86+hash(seed)*.20)
        if j==4 and i%4==0 then
          place("flower_purpleA",x+1.5,z-1,8+hash(seed+5)*4,angle,.90)
        end
        if j==7 and i%5==0 then
          place("rock_smallA",x-2,z,7+hash(seed+17)*5,angle,.92)
        end
      end
    end
  end
  -- Bushes close the gaps beneath the canopy and give the clearing a soft edge.
  for i=0,36 do
    local u=-78+i*4.4;local d=31+9*math.cos(u*.045)+hash(i)*8
    local x,z=world(u,d)
    place("plant_bush",x,z,13+hash(i+8)*12,i*2.4,.88+hash(i)*.24)
  end
  for _,side in ipairs({-1,1}) do for i=0,11 do
    local u=side*(40+hash(i)*12);local d=-32+i*5
    local x,z=world(u,d)
    place("plant_bush",x,z,14+hash(i+4)*10,i*2.4,.94+hash(i)*.15)
  end end
  -- Clusters, not evenly spaced ornaments. The fighting lane stays short grass.
  for i=0,180 do
    local side=i%2==0 and -1 or 1
    local u=side*(29+hash(i)*30);local d=-40+hash(i+41)*87
    local x,z=world(u,d)
    place("grass",x,z,5+hash(i+5)*5,i*2.399,.86+hash(i)*.35)
  end
  -- Independent flower patches: do not tie selection to the alternating
  -- grass-side index (multiples of four previously all landed on one side).
  for i=1,58 do
    local u=(hash(i*7+1201)*2-1)*76
    local d=(hash(i*13+1601)*2-1)*78
    local count=1+math.floor(hash(i+1901)*4)
    for j=1,count do
      local seed=i*23+j
      local angle=hash(seed+2201)*math.pi*2
      local radius=hash(seed+2601)*5
      local px,pd=u+math.cos(angle)*radius,d+math.sin(angle)*radius
      local x,z=world(px,pd)
      if x*x+(z-24)^2>13^2 and x*x+(z+24)^2>13^2
          and (px+86)^2+(pd+72)^2>24^2 then
        local name=hash(seed+3001)<.5 and "flower_yellowA" or "flower_purpleA"
        place(name,x,z,6+hash(seed+3401)*5,angle,.92+hash(seed+3801)*.10)
      end
    end
  end
  -- A few low tufts break up the lawn without covering either actor's footing.
  for i=0,100 do
    local u=-29+hash(i)*58;local d=-34+hash(i+21)*66
    if (u+17)^2+(d+17)^2>120 and (u-17)^2+(d-17)^2>120 then
      local x,z=world(u,d)
      place("grass_leafs",x,z,4+hash(i+3)*3,i*2.4,1.1)
    end
  end
  for i,t in ipairs({{-36,17,14},{35,23,17},{-41,-20,12},{44,-11,10}}) do
    local x,z=world(t[1],t[2]);place("rock_smallA",x,z,t[3],i*2.4)
  end
  -- Wooden trail shelter, off the fighting lane and outside the camera orbit.
  local hx,hz=world(-86,-72)
  place("structure-roof",hx,hz,52,math.rad(35),1)
  for i=0,135 do
    local angle=i*2.39996323
    local radius=48+hash(i+231)*43
    local u,d=math.cos(angle)*radius,math.sin(angle)*radius
    if d<12 and (u+86)^2+(d+72)^2>420 then
      local x,z=world(u,d)
      place(i%4==0 and "plant_bush" or "grass",x,z,
        i%4==0 and 16+hash(i)*10 or 6+hash(i)*5,angle,.98)
      if i%9==0 then place("flower_yellowA",x+2,z,9,angle,1) end
    end
  end
  -- Eight-sided wooden stakes with a wider, charred brazier at the top.
  for _,p in ipairs(Torches.positions) do
    for section=1,2 do
      local bottom,top=section==1 and 0 or p[2]-.8,section==1 and p[2]-.4 or p[2]
      local r=section==1 and .40 or .72
      for k=0,7 do
        local a,b=k*math.pi/4,(k+1)*math.pi/4
        local nx,nz=math.cos((a+b)/2),math.sin((a+b)/2)
        for _,v in ipairs({{a,bottom},{b,bottom},{b,top},{a,bottom},{b,top},{a,top}}) do
          vertex(p[1]+math.cos(v[1])*r,v[2],p[3]+math.sin(v[1])*r,nx,0,nz,
            section==1 and {.39,.25,.12} or {.18,.12,.07},2)
        end
      end
    end
  end
  shadowVertices=vertices
  Nature.triangles=#vertices/3
  return vertices
end

local function ensurePaint(g)
  if not watercolorTexture then
    watercolorTexture=imageAsset(g,"watercolor-materials.png")
    watercolorTexture:setFilter("linear","linear",8)
    watercolorTexture:setMipmapFilter("linear")
  end
end

function Nature.draw(g,frame,environment,shadow)
  ensurePaint(g)
  if not mesh then mesh=g.newMesh(FORMAT,Nature.vertices(),"triangles","static") end
  if not shader then shader=g.newShader(SHADER) end
  if not grassTexture then
    grassTexture=imageAsset(g,"meadow-grass.png")
    grassTexture:setWrap("repeat","repeat");grassTexture:setFilter("linear","linear",8)
    grassTexture:setMipmapFilter("linear")
  end
  g.setDepthMode("lequal",true);g.setMeshCullMode("none")
  g.setBlendMode("alpha","alphamultiply");g.setColor(1,1,1,1);g.setShader(shader)
  shader:send("vp","row",frame.vp)
  shader:send("eye",frame.eye)
  shader:send("grassMap",grassTexture)
  shader:send("paintMap",watercolorTexture)
  shader:send("sunVP","row",shadow and shadow.sunVP or frame.vp)
  shader:send("sunEnabled",shadow and shadow.map and 1 or 0)
  if shadow and shadow.map then shader:send("sunMap",shadow.map) end
  shader:send("sunBias",shadow and shadow.sunBias or .003)
  shader:send("sunDark",shadow and shadow.sunDark*.60 or .4)
  shader:send("sunTexel",shadow and shadow.sunTexel or {1/1024,1/1024})
  shader:send("lightDir",environment.light or {-.4,-.8,-.4})
  shader:send("tint",environment.modelTint or {1,1,1})
  shader:send("torchStrength",environment.daytime=="NITE" and 1.8 or .22)
  shader:send("flicker",Torches.flicker(Torches.time()))
  for i,p in ipairs(Torches.positions) do shader:send("torch"..i,{p[1],p[2]+1,p[3]}) end
  TorchShadows.send(shader)
  g.draw(mesh);g.setShader()
  return true
end

-- Preserve the normal camera's orbit, zoom and UI sizing, but lower the
-- woodland shot so the canopy and sky are part of the battle composition.
function Nature.frame(frame)
  local Mat=require("mods.STADIUM2_IMPORTER.lib.renderer")
  local out={}
  for k,v in pairs(frame) do out[k]=v end
  out.eye={frame.eye[1],frame.eye[2]*.65,frame.eye[3]}
  out.focus={frame.focus[1],frame.focus[2]+6,frame.focus[3]}
  out.view=Mat.lookAt(out.eye[1],out.eye[2],out.eye[3],out.focus[1],out.focus[2],out.focus[3])
  out.vp=Mat.matMul(out.projection,out.view)
  return out
end

function Nature.castShadow(g,lightVP)
  if not mesh then mesh=g.newMesh(FORMAT,Nature.vertices(),"triangles","static") end
  if not shadowShader then shadowShader=g.newShader([[
    varying float depth;
    #ifdef VERTEX
    uniform mat4 lightVP;
    vec4 position(mat4 tp,vec4 p){vec4 v=lightVP*p;depth=v.z*.5+.5;return v;}
    #endif
    #ifdef PIXEL
    vec4 effect(vec4 c,Image t,vec2 uv,vec2 sc){float d=clamp(depth,0.,1.)*255.;return vec4(floor(d)/255.,fract(d),0.,1.);}
    #endif
  ]]) end
  g.setShader(shadowShader);shadowShader:send("lightVP","row",lightVP)
  g.setDepthMode("less",true);g.setMeshCullMode("none")
  g.setBlendMode("replace","premultiplied")
  mesh:setDrawRange(Nature.groundVertices+1,Nature.triangles*3-Nature.groundVertices)
  g.draw(mesh);mesh:setDrawRange();g.setShader()
end

-- A translation-free camera VP: the sky is infinitely distant. Camera
-- rotation/pitch/zoom still change the view naturally, but position cannot.
function Nature.skyVP(frame)
  local Mat=require("mods.STADIUM2_IMPORTER.lib.renderer")
  local view={}
  for i,v in ipairs(frame.view) do view[i]=v end
  view[4],view[8],view[12]=0,0,0
  return Mat.matMul(frame.projection,view)
end

function Nature.sky(g,w,h,environment,frame)
  ensurePaint(g)
  if not skyShader then skyShader=g.newShader([[
    #ifdef VERTEX
    uniform mat4 skyVP;
    vec4 position(mat4 tp,vec4 p){return skyVP*p;}
    #endif
    #ifdef PIXEL
    uniform Image paper;uniform float nightSky;
    vec4 effect(vec4 color,Image tex,vec2 uv,vec2 screen){
      vec2 skyUV=vec2(abs(fract(uv.x*2.)*2.-1.),clamp((uv.y-.5)*3.2+.82,.01,.99));
      vec3 sky=Texel(tex,skyUV).rgb;
      float l=dot(sky,vec3(.25,.6,.15));
      sky=mix(sky,vec3(l),.22);
      vec3 wash=Texel(paper,vec2(.51)+abs(fract(uv*1.5)*2.-1.)*.48).rgb;
      sky=mix(sky,vec3(.92,.91,.83),.15)*(wash*.12+.90);
      sky*=mix(1.,.25,nightSky);
      float horizon=smoothstep(.44,.52,uv.y);
      sky=mix(sky,vec3(.27,.35,.28),horizon);
      return vec4(sky,1.)*color;
    }
    #endif
  ]]) end
  if not skyTexture then
    skyTexture=imageAsset(g,"summer-sky.png")
    skyTexture:setFilter("linear","linear")
  end
  if not skyMesh then
    local vertices={}
    local function v(i,j)
      local yaw=i/96*math.pi*2
      local pitch=(j/48-.5)*math.pi
      vertices[#vertices+1]={math.cos(yaw)*math.cos(pitch)*450,
        math.sin(pitch)*450,math.sin(yaw)*math.cos(pitch)*450,i/96,1-j/48}
    end
    for j=0,47 do for i=0,95 do
      v(i,j);v(i+1,j);v(i+1,j+1);v(i,j);v(i+1,j+1);v(i,j+1)
    end end
    skyMesh=g.newMesh({{"VertexPosition","float",3},{"VertexTexCoord","float",2}},vertices,"triangles","static")
    skyMesh:setTexture(skyTexture)
  end
  g.setShader(skyShader);skyShader:send("paper",watercolorTexture)
  skyShader:send("nightSky",environment.daytime=="NITE" and 1 or 0)
  skyShader:send("skyVP","row",Nature.skyVP(frame))
  g.setDepthMode("always",false);g.setMeshCullMode("none")
  local tint=environment.daytime=="NITE" and {.19,.24,.36} or environment.modelTint or {1,1,1}
  g.setColor(tint[1],tint[2],tint[3],1)
  g.draw(skyMesh)
  g.setColor(1,1,1,1);g.setShader()
end

Nature.bindTorchLighting=TorchShadows.bindModel
function Nature.updateTorchShadows(g,actors,matrices,modes,environment)
 TorchShadows.night=environment.daytime=="NITE"
 -- The render mesh and small local caster meshes live on the GPU. Once the
 -- caster caches exist, release the large temporary Lua vertex array.
 local result=TorchShadows.update(g,shadowVertices or {},FORMAT,actors,matrices,modes)
 if result then shadowVertices=nil end
 return result
end

-- Ending a battle does not unload the forest. No actors or camera state are
-- retained here; force the next shadow update to erase old battler silhouettes.
function Nature.endBattle()
 TorchShadows.resetDynamic()
end

function Nature.release()
  TorchShadows.release();shadowVertices=nil
  Torches.release()
  if skyMesh then skyMesh:release();skyMesh=nil end
  if mesh then mesh:release() end
  if shader then shader:release() end
  if grassTexture then grassTexture:release() end
  if skyTexture then skyTexture:release() end
  if shadowShader then shadowShader:release() end
  if watercolorTexture then watercolorTexture:release() end
  if skyShader then skyShader:release() end
  mesh,shader,grassTexture,shadowShader,skyTexture,watercolorTexture,skyShader=nil,nil,nil,nil,nil,nil,nil
end
return Nature
