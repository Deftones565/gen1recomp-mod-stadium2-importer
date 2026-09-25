-- US fragment 79 shared twenty-six-slot controller (families 3 and 15).
local VM=require('mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_mips')
local bit=require('bit')
local Stochastic={}
local POOL,DL,VERT=0x8419F070,0x85200000,0x85300000
local function signed(v)return v>=32768 and v-65536 or v end
local function mux(a,b)
  local x=function(w,shift,mask)return bit.band(bit.rshift(w,shift),mask)end
  return {x(a,20,15),x(b,28,15),x(a,15,31),x(b,15,7),
    x(a,12,7),x(b,12,7),x(a,9,7),x(b,9,7)},
    {x(a,5,15),x(b,24,15),x(a,0,31),x(b,6,7),
      x(b,21,7),x(b,3,7),x(b,18,7),x(b,0,7)}
end
local function drawSpec(texture,wordA,wordB)
  local c0,c1=mux(wordA,wordB)
  -- 84166A64 loads the sprite export as 32x32 RGBA16 (G_SETTIMG FD100000).
  return {textures=texture and {texture} or {},textureFormat=texture and {0,2} or nil,
    cycles=1,cycle0=c0,cycle1=c1,
    primary={255,255,255,255},environment={0,0,0,0},lodFraction=0,
    alpha=1,uv={0,0,0,0},scrollAndShift={0,0,0,0,0,0,0,0}}
end
local function matrix(vm,pointer)
  local m={}
  for j=0,15 do
    local value=vm:read(pointer+j*2,2)*65536+vm:read(pointer+32+j*2,2)
    m[j]=((value>=2147483648 and value-4294967296 or value)/65536)
  end
  return m
end
local function layer(draw,textureScale)
  return {pos={},uv={},color={},idx={},draw=draw,geometryMode=0x200005,
    textureScale=textureScale}
end
local function capture(s)
  local v=s.vm;s.allocation=VERT
  local drawResult=v:call(0x84166A64,{DL,s.family==3 and 34 or 35})
  local finish=drawResult%4294967296
  local g={kind='rom-beam',family=s.family,layers={}}
  local spriteDraw=drawSpec(s.family==3 and 34 or 35,0xFCFFFFFF,0xFFFCF279)
  local trailDraw=drawSpec(nil,0xFCFFFFFF,0xFFFE793C)
  local matrices,vertices={},{}
  for at=DL,finish-1,8 do
    local a,b=v:read(at,4),v:read(at+4,4)
    if a==0xDA380000 then matrices[#matrices+1]=b
    elseif a==0x01004008 and b>=VERT and b<VERT+0x100000 then
      if b~=0x84187C80 then vertices[#vertices+1]=b end
    end
  end
  local visible,sprites=0,0
  for i=0,25 do
    local at=POOL+i*0x360
    local active=v:read(at,2)==1
    local spriteActive=active and v:float(at+0x54)>0
    local sprite=layer(drawSpec(spriteDraw.textures[1],0xFCFFFFFF,0xFFFCF279),{.5,.5})
    local trail=layer(drawSpec(nil,0xFCFFFFFF,0xFFFE793C))
    local m=spriteActive and matrix(v,assert(matrices[sprites+1],'missing native sprite matrix')) or nil
    for j=0,3 do
      local p=0x84187C80+j*16
      local xyz={signed(v:read(p,2)),signed(v:read(p+2,2)),signed(v:read(p+4,2))}
      for k=0,2 do
        sprite.pos[#sprite.pos+1]=m and (xyz[1]*m[k]+xyz[2]*m[4+k]+xyz[3]*m[8+k]+m[12+k]-s.frameOrigin[k+1]) or 0
      end
      sprite.uv[#sprite.uv+1]=signed(v:read(p+8,2))/1024
      sprite.uv[#sprite.uv+1]=signed(v:read(p+10,2))/1024
      for k=12,15 do sprite.color[#sprite.color+1]=spriteActive and v:read(p+k,1) or 0 end
    end
    sprite.idx={1,2,3,2,4,3}
    local base=active and v:read(at+0x20,4) or nil
    for j=0,19 do
      local p=base and base+j*16
      for k=0,2 do trail.pos[#trail.pos+1]=p and signed(v:read(p+k*2,2))-s.frameOrigin[k+1] or 0 end
      trail.uv[#trail.uv+1]=p and signed(v:read(p+8,2))/1024 or 0
      trail.uv[#trail.uv+1]=p and signed(v:read(p+10,2))/1024 or 0
      for k=12,15 do trail.color[#trail.color+1]=p and v:read(p+k,1) or 0 end
    end
    for j=0,8 do for _,n in ipairs({1,3,2,3,4,2})do trail.idx[#trail.idx+1]=j*2+n end end
    g.layers[#g.layers+1]=sprite;g.layers[#g.layers+1]=trail
    if spriteActive then sprites=sprites+1 end
    if active then visible=visible+1 end
  end
  assert(#matrices==sprites and #vertices==visible*9,'native stochastic display-list topology changed')
  s.geometry=g;s.visible=visible;s.drawEnd=finish
end
function Stochastic.new(fragment,mainKernel,inputs,rng,family)
  if not fragment or not mainKernel then return nil,'native stochastic controller requires fragment 79 and main kernel' end
  if family~=3 and family~=15 then return nil,'unsupported stochastic family' end
  if not inputs or not (inputs.swiftOrigin or inputs.origin) or not inputs.endpointB then
    return nil,'native stochastic controller requires live source and target anchors'
  end
  local frameOrigin=inputs.swiftFrameOrigin or {0,0,0}
  local target={}
  for k=1,3 do target[k]=inputs.endpointB[k]+frameOrigin[k]end
  local s={family=family,origin=inputs.swiftOrigin or inputs.origin,target=target,
    frameOrigin=frameOrigin,scale=inputs.modelScale or 1,signal=0,
    age=0,active=true}
  local function trig(fn)return function(v)
    v:write(0x85700000,v.f[12],4);v.f[0]=VM.floatWord(fn(v:float(0x85700000)))
  end end
  s.vm=VM.new({{base=0x84100000,bytes=fragment},{base=0x80000400,bytes=mainKernel}},{
    [0x84156BA0]=function()end,
    [0x84109780]=function(v)v:putVector(v.r[4],s.origin)end,
    [0x841098FC]=function(v)v:putVector(v.r[4],s.target)end,
    [0x84109544]=function(v)v.f[0]=VM.floatWord(s.scale)end,
    [0x841094EC]=function(v)v.r[2]=s.signal end,
    [0x8007AFA0]=function(v)v.r[2]=rng:next()end,
    [0x80073F70]=trig(math.sin),[0x8007E9C0]=trig(math.cos),
    [0x80006DEC]=function(v)v.r[2]=s.allocation;s.allocation=s.allocation+v.r[4]end,
  })
  local ok,err=pcall(function()
    s.vm:call(family==3 and 0x84157AB0 or 0x84157CB0)
    capture(s)
  end)
  if not ok then return nil,tostring(err)end
  return s
end
function Stochastic.step(s,inputs,signal)
  if not s.active then return -1 end
  s.age=s.age+1;s.origin=inputs.swiftOrigin or inputs.origin;s.signal=signal or 0
  s.target={}
  for k=1,3 do s.target[k]=inputs.endpointB[k]+s.frameOrigin[k]end
  local ok,result=pcall(function()return s.vm:call(s.family==3 and 0x84157ADC or 0x84157CDC)end)
  if not ok then s.error='update: '..tostring(result);s.active=false;return -1 end
  if result~=-1 then
    local drawOk,drawError=pcall(capture,s)
    if not drawOk then s.error='draw: '..tostring(drawError);s.active=false;return -1 end
  end
  if not ok then s.error=tostring(result);s.active=false;return -1 end
  if result==-1 then s.active=false end
  return result
end
function Stochastic.snapshot(s)
  local active=0
  for i=0,25 do if s.vm:read(POOL+i*0x360,2)==1 then active=active+1 end end
  return {kind='rom-stochastic-state',family=s.family,age=s.age,active=s.active,
    activeSlots=active,drawReady=not s.error,error=s.error}
end
function Stochastic.geometry(s)return s.geometry end
return Stochastic
