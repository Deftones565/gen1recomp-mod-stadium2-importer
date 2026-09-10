-- US fragment79: 84166F60/841670A8/841674C0/841677C4.
-- Family setup, simulation and authored 84168000 tube/84163380 glow meshes.
-- Endpoint lookup and the host renderer remain separate layers.
local f=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_float")
local Beam={families={[0]=true,[5]=true,[18]=true}}
-- 84158F00, 84158914 and 84159584, in constructor call order.
-- The two 8-word records are combiner selectors, not texture descriptors.
local setups={
  [0]={
    {2,10,{23,23},{5,10,15,15,-5,5,15,15},
      {3,5,1,5,6,7,2,3},{31,31,31,0,0,7,5,7},
      {200,200,0,100},{0,0,200,0,255},{0,255,0,90}},
    {3,15,{21,21},{-2,10,15,15,5,15,15,15},
      {3,5,2,5,1,7,3,7},{31,31,31,0,0,7,5,7},
      {255,50,100,200},{0,100,50,255,255},{0,0,0,0}}},
  [5]={
    {2,10,{19,19},{6,10,15,14,-3,5,0,15},
      {2,1,14,1,2,2,3,1},{3,5,0,5,3,7,0,5},
      {255,255,0,150},{100,255,0,200,50},{255,150,255,120}},
    {3,15,{19,20},{2,6,0,15,-4,2,0,0},
      {2,1,14,1,2,1,3,1},{3,5,0,5,0,7,5,7},
      {0,255,100,150},{100,100,0,255,200},{0,0,0,0}}},
  [18]={
    {3,15,{27,24},{0,20,14,15,0,20,15,14},
      {2,1,14,1,2,1,3,1},{3,5,0,5,0,7,5,7},
      {255,255,255,150},{150,255,255,0,255},{255,255,0,150}}},
}
local function copy(v)
  if type(v)~="table" then return v end
  local out={};for k,x in pairs(v) do out[k]=copy(x) end;return out
end
local MIN_RADIUS=0.10000000149011612 -- 8418C914
local function short(v)return (v+32768)%65536-32768 end
local function vector(v)return {f(v[1]),f(v[2]),f(v[3])}end

function Beam.new()
  local s={slots={}}
  for i=1,4 do
    local slot={active=false,age=0,growthDuration=0,rings={}}
    for j=1,10 do
      slot.rings[j]={index=0,alpha=0,radius=1,angle=0,
        position={0,0,0},velocity={0,0,0}}
    end
    s.slots[i]=slot
  end
  return s
end

-- Inputs are decoded constructor parameters, in native units. No family or
-- move-name defaults: callers must supply the values from their ROM setup.
function Beam.spawn(s,p)
  local slot,index
  for i,v in ipairs(s.slots) do if not v.active then slot,index=v,i;break end end
  if not slot then return nil end -- Native full-pool call leaves state alone.
  local origin,velocity=vector(p.origin),vector(p.velocity)
  local velocityScale=f(p.velocityScale)
  slot.active=true;slot.age=0;slot.phase=0
  slot.growthDuration=short(p.growthDuration)
  slot.maxRadius=f(p.maxRadius)
  slot.rotationIncrement=f(p.rotationIncrement)
  slot.radiusIncrement=f(p.radiusIncrement)
  slot.velocityScale=velocityScale
  slot.finishThreshold=65
  slot.draw=copy(p.draw)
  for i,r in ipairs(slot.rings) do
    r.index=i-1;r.alpha=255;r.radius=f(p.initialRadius);r.angle=0
    r.position=vector(origin)
    r.velocity={f(velocity[1]*velocityScale),f(velocity[2]*velocityScale),
      f(velocity[3]*velocityScale)}
  end
  return index
end

-- origin and direction are the outputs of 841569E0 (before the setup's
-- multiply by ten). Endpoint resolution belongs to the battle integration.
function Beam.forFamily(family,origin,direction)
  local records=assert(setups[family],"unsupported beam family")
  local s=Beam.new();s.family=family
  for _,r in ipairs(records) do
    Beam.spawn(s,{origin=origin,velocity={f(direction[1]*10),
      f(direction[2]*10),f(direction[3]*10)},velocityScale=1.2000000476837158,
      initialRadius=r[1],maxRadius=r[2],rotationIncrement=0,
      radiusIncrement=5,growthDuration=20,
      draw={textures=r[3],scrollAndShift=r[4],cycle0=r[5],cycle1=r[6],
        primary=r[7],lodFraction=r[8][1],
        environment={r[8][2],r[8][3],r[8][4],r[8][5]},overlay=r[9],
        uv={0,0,0,0},alpha=1,overlayAlpha=1}})
  end
  return s
end

local function update(slot,a,b,signal)
  if signal==1 and slot.phase==0 then
    slot.phase=1;slot.finishThreshold=short(slot.age+30)
  elseif slot.phase==1 and slot.age>=slot.finishThreshold-15 then
    slot.phase=2
  end
  for i,r in ipairs(slot.rings) do
    local ring=i-1
    local t=slot.age<slot.growthDuration
      and f(f(f(slot.age*ring)/9)/f(slot.growthDuration-1)) or f(ring/9)
    local inv=f(1-t)
    for axis=1,3 do r.position[axis]=f(f(a[axis]*inv)+f(b[axis]*t)) end
    r.angle=f(r.angle+slot.rotationIncrement)
    if slot.phase==2 then
      r.radius=math.max(MIN_RADIUS,f(r.radius-1))
    elseif ring==0 then
      r.radius=1
    elseif ring==9 then
      r.radius=slot.age<5 and 1 or math.min(slot.maxRadius,f(r.radius+.5))
    else
      local cap=ring==1 and f(slot.maxRadius*.5)
        or ring==2 and f(slot.maxRadius*.75) or slot.maxRadius
      r.radius=math.min(cap,f(r.radius+slot.radiusIncrement))
    end
  end
end

-- One call per 30 Hz simulation tick. Endpoints are the results of native
-- helpers 84109780/841098FC, not velocity-integrated particle positions.
function Beam.step(s,endpointA,endpointB,signal)
  local first=s.slots[1]
  -- Native termination is checked on slot zero BEFORE incrementing any age.
  if first.phase==2 and first.age>first.finishThreshold then return -1 end
  local a,b=vector(endpointA),vector(endpointB)
  b[2]=math.min(200,b[2])
  for _,slot in ipairs(s.slots) do if slot.active then
    slot.age=short(slot.age+1)
    update(slot,a,b,signal)
    if slot.draw then
      local d=slot.draw
      -- Native draw writes these fields. Advance once at the canonical 30 Hz
      -- presentation tick so repeated host draws cannot speed up the texture.
      for i,field in ipairs({1,2,5,6}) do d.uv[i]=short(d.uv[i]+d.scrollAndShift[field]) end
      d.overlayAlpha=d.alpha
      if slot.phase==2 then
        d.alpha=math.max(0,f(1-f((slot.age-slot.finishThreshold+15)*0.07000000029802322)))
      end
    end
  end end
  return 0
end

local function trunc(x)return x<0 and math.ceil(x) or math.floor(x)end
local function glow(slot,eye)
  local d=slot.draw
  if not eye or d.overlay[1]+d.overlay[2]+d.overlay[3]+d.overlay[4]==0 then return nil end
  local a,b=slot.rings[1].position,slot.rings[10].position
  local u,v={},{}
  for k=1,3 do u[k]=f(b[k]-a[k]);v[k]=f(a[k]-eye[k]) end
  local n={f(f(u[2]*v[3])-f(u[3]*v[2])),f(f(u[3]*v[1])-f(u[1]*v[3])),
    f(f(u[1]*v[2])-f(u[2]*v[1]))}
  local length=f(math.sqrt(f(f(f(n[1]*n[1])+f(n[2]*n[2]))+f(n[3]*n[3]))))
  -- Keep the fixed mesh allocation when the native helper would skip a
  -- degenerate strip; zero width makes its triangles degenerate too.
  local e,h={},{}
  for k=1,3 do n[k]=length==0 and 0 or f(f(n[k]/length)*20)
    e[k]=f(f(f(1.2)*a[k])-f(f(.2)*b[k]))
    h[k]=f(f(f(1.2)*b[k])-f(f(.2)*a[k]))
  end
  local g={glow=true,pos={},uv={.5,1,.5,1,0,.5,1,.5,.5,.5,.5,.5,0,.5,1,.5,.5,0,.5,0},
    idx={1,5,3,3,5,7,1,2,5,2,6,5,2,4,6,4,8,6,7,5,9,5,6,9,9,6,10,6,8,10},color={},
    draw={textures={-1},primary={255,255,255,255},environment=copy(d.overlay),lodFraction=0,
      cycle0={5,4,1,4,1,7,4,7},cycle1={5,4,1,4,1,7,4,7},alpha=1,
      uv={0,0,0,0},scrollAndShift={0,0,0,0,0,0,0,0}}}
  for i,pair in ipairs({{a,2},{b,2},{e,1},{h,1},{a,0},{b,0},{e,-1},{h,-1},{a,-2},{b,-2}}) do
    for k=1,3 do g.pos[#g.pos+1]=short(trunc(f(pair[1][k]+f(n[k]*pair[2])))) end
    for k=1,4 do g.color[#g.color+1]=(i==5 or i==6)
      and (k==4 and trunc(f(d.overlay[k]*d.overlayAlpha)) or d.overlay[k]) or (k==4 and 0 or 255) end
  end
  return g
end
function Beam.geometry(s)
  local g={kind="rom-beam",family=s.family,layers={}}
  for _,slot in ipairs(s.slots) do if slot.active and slot.draw then
    local strip=glow(slot,s.cameraEye)
    if strip then g.layers[#g.layers+1]=strip end
    local layer={pos={},uv={},idx={},draw=copy(slot.draw)}
    for ring=0,9 do
      local r=slot.rings[ring+1]
      for j=0,8 do
        local angle=f(r.angle+f(f(f((j%8)*2)*3.1415927410125732)/8))
        local offset={0,f(-f(math.sin(angle))*r.radius),f(f(math.cos(angle))*r.radius)}
        for axis=1,3 do layer.pos[#layer.pos+1]=short(trunc(f(r.position[axis]+offset[axis]))) end
        layer.uv[#layer.uv+1]=j*128/1024
        layer.uv[#layer.uv+1]=math.floor(ring*1024/10)/1024
      end
    end
    for ring=0,8 do for j=0,7 do
      local a=ring*9+j+1
      for _,v in ipairs({a,a+9,a+1,a+9,a+10,a+1}) do layer.idx[#layer.idx+1]=v end
    end end
    g.layers[#g.layers+1]=layer
  end end
  return g
end

function Beam.model(g,textures)
  local model={file="stadium2-lifecycle-beam",species=0,rootScale=1,staticPose=true,
    bones={{parent=-1,boneId=0,chan=-1,t={0,0,0},r={0,0,0},s={1,1,1}}},
    anims={},auxAnims={},fx={},moveAnim={},contextAnim={},prims={},textures={}}
  for i,layer in ipairs(g.layers) do
    local d=layer.draw
    local p={pos=layer.pos,uv=layer.uv,idx=layer.idx,nverts=#layer.pos/3,nidx=#layer.idx,
      nrm={},skin={},color={},tex=#model.textures+1,texAnim=-1,additive=false,cull=false,
      lighting=false,vertexSemantics="color",alphaMode="blend",geometryMode=layer.glow and 0x200004 or 0x200005,
      sampler={cms=0,cmt=0},material={phase5=true,primitiveColor={},environmentColor={},
        primitiveLodFraction=d.lodFraction/255,
        combiner={cycles=layer.glow and 1 or 2,color0={unpack(d.cycle0,1,4)},alpha0={unpack(d.cycle0,5,8)},
          color1={unpack(d.cycle1,1,4)},alpha1={unpack(d.cycle1,5,8)}}}}
    for _,symbol in ipairs(d.textures) do
      model.textures[#model.textures+1]=assert(textures[symbol],"beam ROM texture unavailable")
    end
    p.battleFxNoDepth=layer.glow or false
    for v=1,p.nverts do
      p.skin[v]=0;p.nrm[v*3-2],p.nrm[v*3-1],p.nrm[v*3]=0,1,0
      for c=1,4 do p.color[(v-1)*4+c]=layer.color and layer.color[(v-1)*4+c] or 0 end
    end
    model.prims[i]=p
  end
  Beam.updateModel(model,g)
  return model
end

function Beam.updateModel(model,g)
  for i,layer in ipairs(g.layers) do
    local p,d=model.prims[i],layer.draw
    p.pos=layer.pos
    if layer.color then p.color=layer.color end
    for c=1,4 do
      p.material.primitiveColor[c]=(c==4 and trunc(f(d.primary[c]*d.alpha)) or d.primary[c])/255
      p.material.environmentColor[c]=(c==4 and trunc(f(d.environment[c]*d.alpha)) or d.environment[c])/255
    end
    local shift=d.scrollAndShift
    p.battleFxTextures={p.tex,d.textures[2] and p.tex+1 or nil,phase5=true,wrap="repeat",
      samplers={{cms=0,cmt=0,shifts=shift[3],shiftt=shift[4]},
        {cms=0,cmt=0,shifts=shift[7],shiftt=shift[8]}},
      scroll={{-(d.uv[1]%4096)/128,-(d.uv[2]%4096)/128},
        {-(d.uv[3]%4096)/128,-(d.uv[4]%4096)/128}}}
  end
end

function Beam.snapshot(s)
  local out={kind="rom-beam-state",family=s.family,drawReady=s.family~=nil,slots={}}
  for i,v in ipairs(s.slots) do
    local slot={active=v.active,age=v.age,phase=v.phase,
      growthDuration=v.growthDuration,finishThreshold=v.finishThreshold,
      maxRadius=v.maxRadius,rotationIncrement=v.rotationIncrement,
      radiusIncrement=v.radiusIncrement,velocityScale=v.velocityScale,rings={}}
    slot.draw=copy(v.draw)
    for j,r in ipairs(v.rings) do
      slot.rings[j]={index=r.index,alpha=r.alpha,radius=r.radius,angle=r.angle,
        position=vector(r.position),velocity=vector(r.velocity)}
    end
    out.slots[i]=slot
  end
  return out
end
return Beam
