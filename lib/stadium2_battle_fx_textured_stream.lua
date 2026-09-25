-- US shared six-slot / twenty-node stream kernel: Ice Beam and Hyper Beam.
-- Simulation and generated vertices stay in an isolated persistent ROM VM.
local VM=require('mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_mips')
local f=require('mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_float')
local Beam=require('mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_beam')
local Stream={}
local POOL,DL,VERT=0x85000000,0x85200000,0x85300000
local function signed(v)return v>=32768 and v-65536 or v end
local function copy(v)if type(v)~='table'then return v end local o={} for k,x in pairs(v)do o[k]=copy(x)end return o end
local function capture(s)
  local vm=s.vm;s.allocation=VERT
  vm:call(0x84169618,{DL})
  local g={kind='rom-beam',family=s.family,layers={}}
  if s.beam then
    local core=Beam.geometry(s.beam)
    for _,layer in ipairs(core.layers)do
      for j=1,#layer.pos do layer.pos[j]=layer.pos[j]-s.frameOrigin[(j-1)%3+1]end
      g.layers[#g.layers+1]=layer
    end
  end
  for i=0,5 do
    local at=POOL+i*0x374;local active=vm:read(at,2)==1
    local d=copy(s.template)
    if active then
      d.alpha=vm:float(at+0x18)
      d.uv={signed(vm:read(at+0x68,2)),signed(vm:read(at+0x6A,2)),
        signed(vm:read(at+0x74,2)),signed(vm:read(at+0x76,2))}
    else d.alpha=0 end
    local l={pos={},uv={},color={},idx={},geometryMode=0x200005,draw=d}
    local vertex=active and vm:read(at+0x88,4) or nil
    for j=0,39 do
      for k=0,2 do l.pos[#l.pos+1]=vertex and signed(vm:read(vertex+j*16+k*2,2))-s.frameOrigin[k+1] or 0 end
      -- UVs are immutable in the renderer. Seed inactive slots with the
      -- native strip coordinates so later emissions retain their texture.
      l.uv[#l.uv+1]=j%2
      l.uv[#l.uv+1]=math.floor(math.floor(j/2)*1024/20)/1024
      for k=12,15 do l.color[#l.color+1]=vertex and vm:read(vertex+j*16+k,1) or 0 end
    end
    for j=0,18 do for _,v in ipairs({1,3,2,2,3,4})do l.idx[#l.idx+1]=j*2+v end end
    g.layers[#g.layers+1]=l
  end
  s.geometry=g
end
function Stream.new(fragment,inputs,rng,family)
  if type(fragment)~='string' then return nil,'stream requires fragment 79' end
  family=family or 13
  if family~=8 and family~=13 then return nil,'unsupported textured-stream family' end
  local s={family=family,inputs=inputs,age=0,signal=0,active=true,origin=inputs.swiftOrigin or inputs.origin,
    direction=inputs.direction,frameOrigin=inputs.swiftFrameOrigin or {0,0,0}}
  local function trig(fn)return function(v)
    v:write(0x85700000,v.f[12],4);v.f[0]=VM.floatWord(fn(v:float(0x85700000)))
  end end
  s.vm=VM.new({{base=0x84100000,bytes=fragment}},{
    [0x84166F60]=function()
      s.beam=Beam.new();s.beam.family=8;s.beam.cameraEye={}
      for k=1,3 do s.beam.cameraEye[k]=inputs.cameraEye[k]+s.frameOrigin[k]end
    end,
    [0x841670A8]=function(v)
      -- Decode the original constructor's ABI; no move-name presets.
      local sp=v.r[29]
      local function word(offset)return v:read(sp+offset,4)end
      local function floatWord(w)v:write(0x85700000,w,4);return v:float(0x85700000)end
      local d={textures={word(0x30),word(0x34)},scrollAndShift={},cycle0={},cycle1={},
        primary={},environment={},overlay={},uv={0,0,0,0},alpha=1,overlayAlpha=1,lodFraction=word(0x70)%256}
      for i=0,7 do
        d.scrollAndShift[i+1]=signed(word(0x38+i*4)%65536)
        d.cycle0[i+1]=v:read(word(0x58)+i*4,4);d.cycle1[i+1]=v:read(word(0x5C)+i*4,4)
      end
      -- The first native draw advances scroll before any update has run.
      for i,k in ipairs({1,2,5,6})do d.uv[i]=d.scrollAndShift[k]end
      for i=0,3 do d.primary[i+1]=word(0x60+i*4)%256;d.environment[i+1]=word(0x74+i*4)%256;d.overlay[i+1]=word(0x84+i*4)%256 end
      v.r[2]=Beam.spawn(s.beam,{origin={floatWord(v.f[12]),floatWord(v.f[14]),floatWord(v.r[6])},
        velocity={floatWord(v.r[7]),v:float(sp+0x10),v:float(sp+0x14)},
        rotationIncrement=v:float(sp+0x18),radiusIncrement=v:float(sp+0x1C),velocityScale=v:float(sp+0x20),
        initialRadius=v:float(sp+0x24),maxRadius=v:float(sp+0x28),growthDuration=word(0x2C),draw=d}) or 0
    end,
    [0x841677C4]=function(v)
      local p=s.inputs
      local function world(a)local o={} for k=1,3 do o[k]=a[k]+s.frameOrigin[k]end return o end
      s.beam.cameraEye=p.cameraEye and world(p.cameraEye)
      v.r[2]=Beam.step(s.beam,world(p.endpointA),world(p.endpointB),s.signal)
    end,
    [0x84156BA0]=function()end,
    [0x841569E0]=function(v)
      for k=1,3 do v:putFloat(v.r[k+3],s.origin[k])end
      v:putFloat(v.r[7],s.direction[1]);v:putFloat(v:read(v.r[29]+16,4),s.direction[2]);v:putFloat(v:read(v.r[29]+20,4),s.direction[3])
    end,
    [0x84109780]=function(v)v:putVector(v.r[4],s.origin)end,
    [0x841094EC]=function(v)v.r[2]=s.signal end,
    [0x841094A4]=function(v)v.r[2]=0x85600000 end, -- mode 0 ignores the camera structure
    [0x8007AFA0]=function(v)v.r[2]=rng:next()end,
    [0x80073F70]=trig(math.sin),[0x8007E9C0]=trig(math.cos),
    [0x80006DEC]=function(v)v.r[2]=s.allocation;s.allocation=s.allocation+v.r[4]end,
    [0x84168C18]=function(v)
      v:write(0x85700000,v.f[12],4);local a=v:float(0x85700000)
      v:write(0x85700000,v.r[7],4);local radius=v:float(0x85700000)
      local radians=f(f(f(360*a)/v:float(0x8418C920))*f(3.1415926/180))
      v:putVector(v.r[6],{0,f(-f(math.sin(radians))*radius),f(f(math.cos(radians))*radius)})
    end,
    -- Native material words are decoded from the slot below, and all strip
    -- triangles are submitted by the renderer from the captured 40 vertices.
    [0x800710A8]=function()end,
    [0x84169344]=function(v)v.r[2]=v.r[4]end,
    [0x84169214]=function(v)v.r[2]=v.r[4]end,
  })
  local ok,err=pcall(function()
    local vm=s.vm
    vm:write(0x84187DC0,POOL-0x900,4);vm:call(family==8 and 0x84159C2C or 0x84158E24)
    local d={textures={vm:read(POOL+0x20,4),vm:read(POOL+0x24,4)},
      primary={},environment={},cycle0={},cycle1={},cycles=2,alpha=1,
      lodFraction=vm:read(POOL+12,1),uv={0,0,0,0},scrollAndShift={}}
    for i=0,3 do d.primary[i+1]=vm:read(POOL+8+i,1);d.environment[i+1]=vm:read(POOL+13+i,1)end
    for i=0,7 do d.cycle0[i+1]=vm:read(POOL+0x28+i*4,4);d.cycle1[i+1]=vm:read(POOL+0x48+i*4,4)end
    for _,base in ipairs({0x6C,0x78})do for i=0,3 do d.scrollAndShift[#d.scrollAndShift+1]=signed(vm:read(POOL+base+i*2,2))end end
    s.template=d;capture(s)
  end)
  if not ok then return nil,tostring(err)end
  return s
end
function Stream.step(s,inputs,signal)
  if not s.active then return -1 end
  s.age=s.age+1;s.signal=signal or 0
  s.inputs=inputs
  s.origin=inputs.swiftOrigin or inputs.origin;s.direction=inputs.direction
  local ok,result=pcall(function()
    local result=s.vm:call(s.family==8 and 0x84159C6C or 0x84158E58)
    if result~=-1 then capture(s)end
    return result
  end)
  if not ok then s.error=tostring(result);s.active=false;return -1 end
  if result==-1 then s.active=false end
  return result
end
function Stream.geometry(s)return s.geometry end
function Stream.snapshot(s)
  local slots={}
  for i=0,5 do local at=POOL+i*0x374
    slots[i+1]={active=s.vm:read(at,2)==1,age=s.vm:read(at+4,2),alpha=s.vm:float(at+0x18)}
  end
  return {kind='rom-textured-stream-state',family=s.family,age=s.age,active=s.active,slots=slots,
    core=s.beam and Beam.snapshot(s.beam) or nil,
    drawReady=not s.error,error=s.error}
end
return Stream
