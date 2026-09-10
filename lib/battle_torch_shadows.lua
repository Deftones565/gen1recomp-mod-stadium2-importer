-- Omnidirectional point shadows: six cached static faces per torch, packed into
-- two GLES2-compatible atlases. Only moving battlers are redrawn at 20Hz.
local Mat=require('mods.STADIUM2_IMPORTER.lib.renderer')
local Torches=require('mods.STADIUM2_IMPORTER.lib.battle_torches')
local P=require('mods.STADIUM2_IMPORTER.lib.torch_projection')
local S={resolution=P.size,interval=1/20}
local maps,shader,scratch,last={},nil,nil,nil
local windowW,windowH
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
local function canvas(g,w,h)
 local c=g.newCanvas(w,h,{format='rgba8',readable=true,dpiscale=1})
 c:setFilter('nearest','nearest');return c
end
local function beginFace(g,target,p,vp)
 g.setCanvas({target,depth=true});g.clear(1,1,1,1,true,true)
 g.origin();g.setScissor();g.setDepthMode('less',true);g.setMeshCullMode('none')
 g.setBlendMode('replace','premultiplied');g.setColor(1,1,1,1);g.setShader(shader)
 shader:send('lightVP','row',vp);shader:send('modelMatrix','row',Mat.identity())
 shader:send('shadowLight',{p[1],p[2]+1,p[3]})
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
 S.power=(S.night and 1.8 or .22)*Torches.flicker(now)
 if last and now-last<S.interval then return maps end
 if not pcall(g.push,'all') then return nil end
 local ok,err=pcall(function()
  shader=shader or g.newShader(SOURCE)
  scratch=scratch or canvas(g,P.size,P.size)
  for i,p in ipairs(Torches.positions) do
   if not maps[i] then maps[i]={map=canvas(g,P.size*3,P.size*2),faces={}} end
   local entry=maps[i]
   if not entry.ready then
    local selected={}
    for j=1,#vertices,3 do
     local near=false
     for k=j,j+2 do local v=vertices[k]
      if v[10]~=0 and (v[1]-p[1])^2+(v[3]-p[3])^2<105^2 then near=true end
     end
     if near then for k=j,j+2 do selected[#selected+1]=vertices[k] end end
    end
    if #selected>0 then entry.mesh=entry.mesh or g.newMesh(format,selected,'triangles','static') end
    for face=1,6 do
     local v=entry.faces[face]
     if not v then v={map=canvas(g,P.size,P.size),vp=S.frame(p,face)};entry.faces[face]=v end
     beginFace(g,v.map,p,v.vp);shader:send('staticDepth',scratch);shader:send('useStaticDepth',0);if entry.mesh then g.draw(entry.mesh) end

    end
    if entry.mesh then entry.mesh:release();entry.mesh=nil end;entry.ready=true
   end
   for face,v in ipairs(entry.faces) do
    beginFace(g,scratch,p,v.vp)
    -- Restore cached static color; static occlusion is compared explicitly in
    -- the actor fragment shader, so no depth-buffer copies are needed.
    g.setShader();g.setDepthMode('always',false);g.draw(v.map)
    g.setShader(shader);g.setDepthMode('less',true)
    shader:send('staticDepth',v.map);shader:send('useStaticDepth',1)
    for _,side in ipairs({'player','enemy'}) do
     local actor,matrix=actors[side],matrices[side]
     if actor and actor.renderer and matrix and modes[side]=='host' then
      local r=actor.renderer;local old=r.shadowShader;r.shadowShader=shader
      local success,drawn,why=pcall(r.drawShadowMap,r,matrix[1],v.vp)
      r.shadowShader=old
      if not success or not drawn then error(why or drawn) end
     end
    end
    g.setCanvas(entry.map);g.setShader();g.setDepthMode('always',false)
    g.draw(scratch,((face-1)%3)*P.size,math.floor((face-1)/3)*P.size)
   end
  end
 end)
 g.pop()
 if not ok then S.error=tostring(err);return nil end
 last=now;S.error=nil;return maps
end
function S.send(shader)
 shader:send('torchShadows',#maps==2 and not S.error and 1 or 0)
 for i=1,2 do if maps[i] then shader:send('torchMap'..i,maps[i].map) end end
end
function S.bindModel(shader)
 if not shader:hasUniform('localTorchEnabled') then return end
 shader:send('localTorchShadows',#maps==2 and not S.error and 1 or 0)
 shader:send('localTorchEnabled',1);shader:send('localTorchPower',S.power or 0)
 for i,p in ipairs(Torches.positions) do
  shader:send('localTorch'..i,{p[1],p[2]+1,p[3]})
  if maps[i] then shader:send('localTorchMap'..i,maps[i].map) end
 end
end
function S.release()
 for _,v in ipairs(maps) do
  v.map:release();if v.mesh then v.mesh:release() end
  for _,f in ipairs(v.faces) do f.map:release() end
 end
 if scratch then scratch:release() end
 if shader then shader:release() end
 maps,shader,scratch,last={},nil,nil,nil;windowW,windowH=nil,nil;S.error=nil
end
return S
