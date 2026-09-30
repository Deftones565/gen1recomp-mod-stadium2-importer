-- US shared six-slot / twenty-node stream kernel: Ice Beam and Hyper Beam.
-- The kernel is the Lua port in stadium2_battle_fx_textured_stream_native.lua
-- on Stadium's own memory layout; Hyper Beam's core beams are
-- stadium2_battle_fx_beam. This module steps them at 30 Hz and reads the
-- stream vertices back into renderer geometry.
local Native=require('mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_textured_stream_native')
local Memory=require('mods.STADIUM2_IMPORTER.lib.stadium2_native_memory')
local Beam=require('mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_beam')
local Stream={}
local POOL,DL,VERT=0x85000000,0x85200000,0x85300000
local function signed(v)return v>=32768 and v-65536 or v end
local function copy(v)if type(v)~='table'then return v end local o={} for k,x in pairs(v)do o[k]=copy(x)end return o end
local function capture(s)
  local vm=s.mem;s.allocation=VERT
  Native.draw(vm,s.callbacks,DL)
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
      d.alpha=vm:f32(at+0x18)
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
  local mem=Memory.new({{base=0x84100000,bytes=fragment}})
  s.mem=mem
  local function floatWord(w)return Memory.wordFloat(w%4294967296)end
  s.callbacks={
    anchor=function()return s.origin,s.direction end,
    origin=function()return s.origin end,
    signal=function()return s.signal end,
    random=function()return rng:next()end,
    alloc=function(n)local a=s.allocation;s.allocation=s.allocation+n;return a end,
    coreInit=function()
      s.beam=Beam.new();s.beam.family=8;s.beam.cameraEye={}
      for k=1,3 do s.beam.cameraEye[k]=inputs.cameraEye[k]+s.frameOrigin[k]end
    end,
    -- 841670A8's arguments, decoded as its ABI lays them out; no move-name
    -- presets.
    coreSpawn=function(c)
      local function word(offset)return (c.stack[offset] or 0)%4294967296 end
      local d={textures={word(0x30),word(0x34)},scrollAndShift={},cycle0={},cycle1={},
        primary={},environment={},overlay={},uv={0,0,0,0},alpha=1,overlayAlpha=1,lodFraction=word(0x70)%256}
      for i=0,7 do
        d.scrollAndShift[i+1]=signed(word(0x38+i*4)%65536)
        d.cycle0[i+1]=mem:u32(word(0x58)+i*4);d.cycle1[i+1]=mem:u32(word(0x5C)+i*4)
      end
      -- The first native draw advances scroll before any update has run.
      for i,k in ipairs({1,2,5,6})do d.uv[i]=d.scrollAndShift[k]end
      for i=0,3 do d.primary[i+1]=word(0x60+i*4)%256;d.environment[i+1]=word(0x74+i*4)%256;d.overlay[i+1]=word(0x84+i*4)%256 end
      return Beam.spawn(s.beam,{origin={c.fa0,c.fa1,c.a2},
        velocity={c.a3,floatWord(word(0x10)),floatWord(word(0x14))},
        rotationIncrement=floatWord(word(0x18)),radiusIncrement=floatWord(word(0x1C)),velocityScale=floatWord(word(0x20)),
        initialRadius=floatWord(word(0x24)),maxRadius=floatWord(word(0x28)),growthDuration=word(0x2C),draw=d}) or 0
    end,
    coreStep=function()
      local p=s.inputs
      local function world(a)local o={} for k=1,3 do o[k]=a[k]+s.frameOrigin[k]end return o end
      s.beam.cameraEye=p.cameraEye and world(p.cameraEye)
      return Beam.step(s.beam,world(p.endpointA),world(p.endpointB),s.signal)
    end,
    -- Native material words are decoded from the slot below, and all strip
    -- triangles are submitted by the renderer from the captured 40 vertices.
    combine=function()end,
    material=function(dl)return dl end,
    strip=function(dl)return dl end,
  }
  local ok,err=pcall(function()
    local vm=s.mem
    vm:write(Native.POOL_POINTER,POOL-0x900,4);Native.init(vm,s.callbacks,family)
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
    local result=Native.update(s.mem,s.callbacks,s.family)
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
    slots[i+1]={active=s.mem:read(at,2)==1,age=s.mem:read(at+4,2),alpha=s.mem:f32(at+0x18)}
  end
  return {kind='rom-textured-stream-state',family=s.family,age=s.age,active=s.active,slots=slots,
    core=s.beam and Beam.snapshot(s.beam) or nil,
    drawReady=not s.error,error=s.error}
end
return Stream
