-- US fragment79 8415F0D0/8415F9A0 and 841614E0/84161DAC.
-- Persistent simulation, authored grid geometry and camera-facing placement.
local f=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_float")
local Grid={families={[9]=true,[10]=true,[11]=true}}
local normals=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_grid_normals")
local Random=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_random")
local function disturb(s,x,y)
  for row=0,15 do for col=0,15 do
    local dx,dy=x-col,y-row
    local distance=f(math.sqrt(f(f(dx*dx)+f(dy*dy))))
    local v=s.vertices[row*16+col+1]
    v[4]=f(v[4]+(distance==0 and 1.5707963705062866 or 1.5707963705062866/distance))
  end end
end
function Grid.new(family,random)
  assert(Grid.families[family],"unsupported wave-grid family")
  local s={family=family,counter=0,duration=1800,alpha=0,
    amplitude=family~=11 and f(.01) or 0,finishing=false,active=true,
    vertices={}}
  for row=0,15 do for col=0,15 do
    s.vertices[#s.vertices+1]={f(row*6.75-54),1,f(col*5.25-42),0}
  end end
  if family==10 then
    random=random or Random.new(0)
    disturb(s,8,8)
    for _=1,10 do
      local x,y=random:next(),random:next()
      -- Native signed remainder; the built-in ROM RNG returns 30-bit values.
      x=x<0 and -((-x)%16) or x%16
      y=y<0 and -((-y)%16) or y%16
      disturb(s,x,y)
    end
    for _,v in ipairs(s.vertices) do v[2]=f(f(math.sin(v[4]))*.5+1) end
  end
  return s
end
function Grid.step(s,signal)
  if not s.active then return -1 end
  s.counter=s.counter+1
  -- 841094EC returns a host-controlled global, not elapsed time. The first
  -- value 1 resets the timer and selects the native 25-tick finish window.
  if signal==1 and not s.finishing then
    s.finishing=true;s.counter=0;s.duration=25
  end
  if s.counter>s.duration then s.active=false;return -1 end
  if not s.finishing then
    s.alpha=math.min(s.family~=11 and 128 or 80,s.alpha+10)
  elseif s.counter>=16 then
    s.alpha=math.max(0,s.alpha-(s.family~=11 and 12 or 8))
  end
  if s.amplitude<(s.family==9 and 1 or s.family==10 and .5 or .25) then
    s.amplitude=f(s.amplitude+.05)
  end
  for _,v in ipairs(s.vertices) do
    if s.family==10 then
      -- 84160E58 uses constant .5, not the amplitude state at +8.
      v[2]=f(f(math.sin(v[4]))*.5+1)
      v[4]=f(v[4]+.1)
    else
    local radius=f(math.sqrt(f(f(v[1]*v[1])+f(v[3]*v[3]))))
    local weight=f(1-f(radius/76.3667984008789))
    local angle=f((s.counter%20/20+3*weight)*6.2831854820251465)
    v[2]=f(f(math.sin(angle))*(s.amplitude*weight))
    end
  end
  return 0
end
function Grid.snapshot(s)
  local positions,phases={},{}
  for _,v in ipairs(s.vertices) do
    for i=1,3 do positions[#positions+1]=v[i] end
    if s.family==10 then phases[#phases+1]=v[4] end
  end
  return {kind="rom-wave-grid-state",counter=s.counter,duration=s.duration,
    alpha=s.alpha,amplitude=s.amplitude,finishing=s.finishing,
    active=s.active,positions=positions,phases=s.family==10 and phases or nil,rows=16,columns=16,
    drawReady=true}
end
local function trunc(v)return v<0 and math.ceil(v) or math.floor(v)end
function Grid.geometry(s)
  local g={kind="rom-wave-grid",family=s.family,pos={},idx={},nrm=normals(s.vertices),
    colors={{255,255,255,s.alpha},{0,0,0,0}}}
  for _,v in ipairs(s.vertices) do for j=1,3 do g.pos[#g.pos+1]=trunc(v[j]) end end
  -- Native normal components are truncated to signed bytes after *120.
  for i,v in ipairs(g.nrm) do g.nrm[i]=trunc(v*120)/127 end
  for row=0,14 do for col=0,14 do
    local a=row*16+col+1
    local indices=(row*15+col)%2==0 and {a+1,a+16,a,a+1,a+17,a+16}
      or {a+17,a+16,a,a+1,a+17,a}
    for _,i in ipairs(indices) do g.idx[#g.idx+1]=i end
  end end
  return g
end
function Grid.model(texture,g)
  assert(texture and texture.rgba,"wave-grid ROM texture unavailable")
  local p={pos=g.pos,nrm=g.nrm,idx=g.idx,nverts=256,nidx=#g.idx,
    uv={},skin={},color={},tex=1,texAnim=-1,additive=false,cull=false,
    lighting=false,vertexSemantics="color",alphaMode="blend",
    geometryMode=g.family==10 and 0x260005 or 0x260004,textureScale={.5,.5},sampler={cms=0,cmt=0},
    material={phase5=true,primitiveColor={1,1,1,1},environmentColor={0,0,0,0},
      combiner={cycles=2,color0={1,15,4,7},alpha0={1,7,4,7},
        color1={0,15,4,7},alpha1={0,7,4,7}}}}
  -- Ambient light in 84187638/84187798 is white, so native lit shade RGB
  -- saturates white; normals still drive G_TEXTURE_GEN independently.
  for i=1,256 do
    p.skin[i]=0;p.uv[i*2-1]=math.floor((i-1)/16)/2;p.uv[i*2]=(i-1)%16/2
    for j=1,3 do p.color[(i-1)*4+j]=255 end
    p.color[i*4]=g.colors[1][4]
  end
  return {file="stadium2-lifecycle-wave-grid",species=0,rootScale=1,staticPose=true,
    bones={{parent=-1,boneId=0,chan=-1,t={0,0,0},r={0,0,0},s={1,1,1}}},
    anims={},auxAnims={},fx={},moveAnim={},contextAnim={},prims={p},textures={texture}}
end

-- Camera-relative transform from 8415FC60: focus + normalized(focus-eye)
-- *105/(FOV/30), then orient the grid's local Y axis toward the camera.
function Grid.matrix(camera,units)
  camera=camera or {};local eye,focus=camera.eye,camera.focus
  if not eye or not focus then return nil end
  local dx,dy,dz=focus[1]-eye[1],focus[2]-eye[2],focus[3]-eye[3]
  local length=math.sqrt(dx*dx+dy*dy+dz*dz)
  if length==0 then return nil end
  dx,dy,dz=dx/length,dy/length,dz/length
  local horizontal=math.sqrt(dx*dx+dz*dz)
  if horizontal==0 then return nil end
  local fov=camera.fovDegrees
  if not fov and camera.projection then fov=2*math.atan(1/math.abs(camera.projection[6]))*180/math.pi end
  if not fov or fov<=0 then return nil end
  local scale=units or .05;local distance=105/(fov/30)*scale
  local rx,rz=-dz/horizontal,dx/horizontal
  return {rx*scale,-dx*scale,-dy*rz*scale,focus[1]+dx*distance,
    0,-dy*scale,horizontal*scale,focus[2]+dy*distance,
    rz*scale,-dz*scale,dy*rx*scale,focus[3]+dz*distance,
    0,0,0,1}
end
return Grid
