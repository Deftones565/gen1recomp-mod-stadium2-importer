-- Omnidirectional point shadows: six cached static faces per torch, packed into
-- two GLES2-compatible atlases. Only moving battlers are redrawn at 20Hz.
local Mat=require('mods.STADIUM2_IMPORTER.lib.renderer')
local Torches=require('mods.STADIUM2_IMPORTER.lib.battle_torches')
local P=require('mods.STADIUM2_IMPORTER.lib.torch_projection')
-- EXTRA EFFECTS (user option): one switch shared by every torch/lamp set.
local switch={enabled=true}
local function new(options)
options=options or {}
local positions=options.positions or Torches.positions
local S={resolution=P.size,interval=1/20}
local maps,shader,scratch,last={},nil,nil,nil
local windowW,windowH
local actorBounds,boundsStorage={},{}
local faceTarget={depth=true}
local identity=Mat.identity()
local lightVectors={}
local function lightVector(i,p)
 local v=lightVectors[i]
 if not v then v={};lightVectors[i]=v end
 v[1],v[2],v[3]=p[1],p[2]+1,p[3]
 return v
end
local SOURCE=[[
varying vec3 shadowWorld;varying vec4 shadowClip;
#ifdef VERTEX
uniform mat4 lightVP;uniform mat4 modelMatrix;
vec4 position(mat4 tp,vec4 p){shadowWorld=(modelMatrix*p).xyz;shadowClip=lightVP*vec4(shadowWorld,1.);return shadowClip;}
#endif
#ifdef PIXEL
uniform vec3 shadowLight;uniform Image staticDepth;uniform float useStaticDepth;
vec4 effect(vec4 c,Image t,vec2 uv,vec2 px){
 if(Texel(t,uv).a<.5)discard;
 float depth=length(shadowWorld-shadowLight)/100.;
 if(depth>=1.)discard;
 if(useStaticDepth>.5){
  vec4 d=Texel(staticDepth,shadowClip.xy/shadowClip.w*.5+.5);
  if(depth>d.r+d.g/255.+.00002)discard;
 }
 float encodedDepth=clamp(depth,0.,1.)*255.;
 return vec4(floor(encodedDepth)/255.,fract(encodedDepth),0.,1.);
}
#endif
]]
S.source=SOURCE
function S.frame(p,face)
 return Mat.matMul(Mat.perspective(math.rad(90),1,.1,P.range),P.view(p,face or 1))
end
-- Conservative clip test of the current posed bounds. A face is skipped only
-- when all eight corners lie beyond one clip plane, including seam crossings.
function S.visibleInFace(vp,model,bounds,margin)
 if not bounds then return true end
 margin=margin or 1
 -- Transform each clip plane into model space, then test its furthest AABB
 -- point. This is the same six-plane test without matrices/corner tables.
 for row=0,2 do
  local i=row*4;local scale=row<2 and 1/margin or 1
  for sign=-1,1,2 do
   local x,y,z,w=vp[13]+sign*vp[i+1]*scale,vp[14]+sign*vp[i+2]*scale,
    vp[15]+sign*vp[i+3]*scale,vp[16]+sign*vp[i+4]*scale
   local a=x*model[1]+y*model[5]+z*model[9]+w*model[13]
   local b=x*model[2]+y*model[6]+z*model[10]+w*model[14]
   local c=x*model[3]+y*model[7]+z*model[11]+w*model[15]
   local d=x*model[4]+y*model[8]+z*model[12]+w*model[16]
   if a*(a>=0 and bounds.maxX or bounds.minX)+b*(b>=0 and bounds.maxY or bounds.minY)
    +c*(c>=0 and bounds.maxZ or bounds.minZ)+d < -1e-7 then return false end
  end
 end
 return true
end
local function canvas(g,w,h)
 local c=g.newCanvas(w,h,{format='rgba8',readable=true,dpiscale=1})
 c:setFilter('nearest','nearest');return c
end
local function beginFace(g,target,p,vp,lightIndex)
 faceTarget[1]=target;g.setCanvas(faceTarget);g.clear(1,1,1,1,true,true)
 g.origin();g.setScissor();g.setDepthMode('less',true);g.setMeshCullMode('none')
 g.setBlendMode('replace','premultiplied');g.setColor(1,1,1,1);g.setShader(shader)
 shader:send('lightVP','row',vp);shader:send('modelMatrix','row',identity)
 shader:send('shadowLight',lightVector(lightIndex,p))
end
function S.update(g,vertices,format,actors,matrices,modes)
 local w,h=g.getDimensions()
 -- LOVE can discard canvas contents when the window mode changes. Rebuild the
 -- static cache on resize, rather than keeping zeroed depth as permanent shade.
 if w~=windowW or h~=windowH then
  for _,entry in ipairs(maps) do entry.ready=false end
  last=nil;windowW,windowH=w,h
 end
 local now=Torches.time()
 S.power=options.power and options.power(S.night,now) or (S.night and 1.8 or .22)*Torches.flicker(now)
 if not switch.enabled then last=nil;return nil end
 if last and now-last<S.interval then return maps end
 if not pcall(g.push,'all') then return nil end
 local ok,err=pcall(function()
  for side in pairs(actorBounds) do actorBounds[side]=nil end
  for side,actor in pairs(actors) do
   if actor.renderer and actor.renderer.poseBounds then
    boundsStorage[side]=boundsStorage[side] or {}
    actorBounds[side]=actor.renderer:poseBounds(boundsStorage[side])
   end
  end
  shader=shader or g.newShader(SOURCE)
  scratch=scratch or canvas(g,P.size,P.size)
  for i,p in ipairs(positions) do
   if not maps[i] then maps[i]={map=canvas(g,P.size*3,P.size*2),faces={}} end
   local entry=maps[i]
   if not entry.ready then
    if not entry.castersReady then
    local selected={}
    for j=1,#vertices,3 do
     local near=false
     for k=j,j+2 do local v=vertices[k]
      if v[10]~=0 and v[10]~=7 and (v[1]-p[1])^2+(v[3]-p[3])^2<105^2 then near=true end
     end
     if near then for k=j,j+2 do selected[#selected+1]=vertices[k] end end
    end
    if #selected>0 then entry.mesh=g.newMesh(format,selected,'triangles','static') end
    entry.castersReady=true
    end
    for face=1,6 do
     local v=entry.faces[face]
     if not v then v={map=canvas(g,P.size,P.size),vp=S.frame(p,face),visible={}};entry.faces[face]=v end
     v.hadActors=nil
     beginFace(g,v.map,p,v.vp,i);shader:send('staticDepth',scratch);shader:send('useStaticDepth',0);if entry.mesh then g.draw(entry.mesh) end

    end
    entry.ready=true
   end
   for face,v in ipairs(entry.faces) do
    local visible=v.visible
    for j=#visible,1,-1 do visible[j]=nil end
    for side in pairs(actors) do
     local actor,matrix=actors[side],matrices[side]
     if actor and actor.renderer and matrix and modes[side]=='host'
       and S.visibleInFace(v.vp,matrix[1],actorBounds[side]) then visible[#visible+1]=side end
    end
    if #visible>0 then
     beginFace(g,scratch,p,v.vp,i)
     g.setShader();g.setDepthMode('always',false);g.draw(v.map)
     g.setShader(shader);g.setDepthMode('less',true)
     shader:send('staticDepth',v.map);shader:send('useStaticDepth',1)
     for _,side in ipairs(visible) do
      local r=actors[side].renderer;local old=r.shadowShader;r.shadowShader=shader
      local success,drawn,why=pcall(r.drawShadowMap,r,matrices[side][1],v.vp)
      r.shadowShader=old
      if not success or not drawn then error(why or drawn) end
     end
    end
    -- Empty faces remain cached. Restore a face once when an actor leaves it.
    if #visible>0 or v.hadActors~=false then
     g.setCanvas(entry.map);g.setShader();g.origin();g.setScissor()
     g.setDepthMode('always',false);g.setBlendMode('replace','premultiplied');g.setColor(1,1,1,1)
     g.draw(#visible>0 and scratch or v.map,((face-1)%3)*P.size,math.floor((face-1)/3)*P.size)
    end
    v.hadActors=#visible>0
   end
  end
 end)
 g.pop()
 if not ok then S.error=tostring(err);return nil end
 last=now;S.error=nil;return maps
end
function S.send(shader)
 shader:send('torchShadows',#maps==2 and not S.error and switch.enabled and 1 or 0)
 for i=1,2 do if maps[i] then shader:send('torchMap'..i,maps[i].map) end end
end
function S.bindModel(shader)
 if not shader:hasUniform('localTorchEnabled') then return end
 shader:send('localTorchShadows',#maps==2 and not S.error and switch.enabled and 1 or 0)
 shader:send('localTorchEnabled',1);shader:send('localTorchPower',S.power or 0)
 for i,p in ipairs(positions) do
  shader:send('localTorch'..i,lightVector(i,p))
  if maps[i] then shader:send('localTorchMap'..i,maps[i].map) end
 end
end
function S.resetDynamic()
 last=nil;S.power=0
 for side in pairs(actorBounds) do actorBounds[side]=nil end
 for _,entry in ipairs(maps) do for _,face in ipairs(entry.faces) do
  for i=#face.visible,1,-1 do face.visible[i]=nil end
 end end
 -- Preserve hadActors until the next update, so formerly occupied faces get
 -- their clean cached scenery restored before the new battle is drawn.
end
function S.release()
 for _,v in ipairs(maps) do
  v.map:release();if v.mesh then v.mesh:release() end
  for _,f in ipairs(v.faces) do f.map:release() end
 end
 if scratch then scratch:release() end
 if shader then shader:release() end
 faceTarget[1]=nil;actorBounds={};boundsStorage={};lightVectors={}
 maps,shader,scratch,last={},nil,nil,nil;windowW,windowH=nil,nil;S.error=nil
end
return S
end
local default=new()
default.new=new
function default.setEnabled(value) switch.enabled=value~=false end
function default.enabled() return switch.enabled end
return default
