-- Family 20 / US 84158840: Tri Attack. The radial mode-5 kernel and its
-- display-list builder are the Lua port in
-- stadium2_battle_fx_tri_attack_native.lua, run on Stadium's own memory
-- layout; this module steps it at 30 Hz and reads the display list back
-- into renderer geometry. Draw-side RNG/spawns run once per 30 Hz tick;
-- host redraws only consume the captured geometry.
local Native=require('mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_tri_attack_native')
local Memory=require('mods.STADIUM2_IMPORTER.lib.stadium2_native_memory')
local bit=require('bit')
local Tri={}
local POOL,AUX,DL,VERT=0x85000000,0x85010000,0x85200000,0x85300000
local function signed(n)return n>=32768 and n-65536 or n end
local function layer(spark)
  local cycle=spark and {3,5,1,5,1,7,3,7} or {15,15,31,4,7,7,7,4}
  return {pos={},uv={},idx={},color={},geometryMode=spark and 0x220005 or 0x200005,
    draw={textures=spark and {-4} or {},cycles=1,cycle0=cycle,cycle1=cycle,
      primary={255,255,255,spark and 200 or 255},environment={0,64,255,0},
      lodFraction=0,alpha=1,uv={0,0,0,0},scrollAndShift={0,0,0,0,0,0,0,0}}}
end
local function normalize(v)
  local n=math.sqrt(v[1]^2+v[2]^2+v[3]^2)
  assert(n>0,'Tri Attack requires a nondegenerate camera')
  return {v[1]/n,v[2]/n,v[3]/n}
end
local function cross(a,b)return {a[2]*b[3]-a[3]*b[2],a[3]*b[1]-a[1]*b[3],a[1]*b[2]-a[2]*b[1]}end
local function capture(s)
  local vm=s.mem
  s.allocation=VERT
  local finish=Native.draw(vm,s.callbacks,DL)
  local g={kind='rom-beam',family=20,nativeCulling=true,layers={layer(false),layer(false),layer(false),layer(true)}}
  g.layers[1].geometryMode=0x200405;g.layers[1].cull=true
  g.layers[2].geometryMode=0x200205;g.layers[2].cull=true
  local cache,mode={},0x200005
  local function triangle(word)
    local front=bit.band(mode,0x200)~=0
    local dst=g.layers[bit.band(mode,0x400)~=0 and 1 or front and 2 or 3]
    -- The shared renderer culls back faces; reverse the front-cull pass.
    for _,shift in ipairs(front and {16,0,8} or {16,8,0}) do
      local at=assert(cache[math.floor(word/2^shift)%256/2],'unmapped Tri Attack vertex')
      dst.idx[#dst.idx+1]=#dst.pos/3+1
      for k=0,2 do dst.pos[#dst.pos+1]=signed(vm:read(at+k*2,2))-s.frameOrigin[k+1] end
      dst.uv[#dst.uv+1]=0;dst.uv[#dst.uv+1]=0
      for k=12,15 do dst.color[#dst.color+1]=vm:read(at+k,1) end
    end
  end
  for at=DL,finish-1,8 do
    local a,b=vm:read(at,4),vm:read(at+4,4);local op=math.floor(a/2^24)
    if op==0xDE then
      assert(b==0x841875C0,'unexpected Tri Attack material');mode=0x200005
    elseif op==0xD9 then mode=bit.bor(bit.band(mode,bit.band(a,0xFFFFFF)),b)
    elseif op==1 then
      local n=math.floor(a/4096)%256;local first=math.floor(a/2)%128-n
      for i=0,n-1 do cache[first+i]=b+i*16 end
    elseif op==5 then triangle(a)
    elseif op==6 then triangle(a);triangle(b) end
  end
  -- 8416A050 billboards the ROM quad using inverse camera rotation; the
  -- spark's size is 84169F18's (Native.sparkScale). Simulation and random
  -- spark births above are the ported kernel.
  local camera=assert(s.camera,'Tri Attack requires live camera inputs')
  local z=normalize({camera.eye[1]-camera.focus[1],camera.eye[2]-camera.focus[2],camera.eye[3]-camera.focus[3]})
  local x=normalize(cross(camera.up or {0,1,0},z));local y=cross(z,x)
  local dst=g.layers[4]
  s.sparkCount=0
  for i=0,19 do
    local at=AUX+4+i*24;local active=vm:read(at,2)==1
    if active then s.sparkCount=s.sparkCount+1 end
    local scale=active and Native.sparkScale(vm,at) or 0
    scale=math.floor(scale*65536)/65536
    local p=vm:vec(at+12)
    for j=0,3 do
      local v=0x84187E48+j*16
      for k=1,3 do
        local value=p[k]+scale*(signed(vm:read(v,2))*x[k]+signed(vm:read(v+2,2))*y[k]+signed(vm:read(v+4,2))*z[k])
        dst.pos[#dst.pos+1]=value-s.frameOrigin[k]
      end
      dst.uv[#dst.uv+1]=signed(vm:read(v+8,2))/1024
      dst.uv[#dst.uv+1]=signed(vm:read(v+10,2))/1024
      for k=1,4 do dst.color[#dst.color+1]=255 end
    end
    for _,index in ipairs({1,2,3,3,2,4}) do dst.idx[#dst.idx+1]=i*4+index end
  end
  s.geometry=g
end
function Tri.new(fragment,inputs,rng)
  if type(fragment)~='string' then return nil,'Tri Attack requires fragment 79' end
  local s={frameOrigin=inputs.swiftFrameOrigin or {0,0,0},camera=inputs.terrainCamera,
    origin=inputs.swiftOrigin or inputs.origin,direction=inputs.direction,age=0,active=true}
  s.mem=Memory.new({{base=0x84100000,bytes=fragment}})
  s.callbacks={
    anchor=function()return s.origin,s.direction end,
    origin=function()return s.origin end,
    random=function()return rng:next()end,
    alloc=function(n)local a=s.allocation;s.allocation=s.allocation+n;return a end,
    -- the sparks are billboarded from the live camera in capture()
    sparks=function(_,dl)return dl end,
  }
  local ok,err=pcall(function()
    s.mem:write(Native.POOL_POINTER,POOL-0x3C8,4);s.mem:write(Native.SPARK_POINTER,AUX,4)
    Native.init(s.mem,s.callbacks)
    capture(s)
  end)
  if not ok then return nil,tostring(err)end
  return s
end
function Tri.step(s,inputs)
  if not s.active then return -1 end
  s.origin=inputs.swiftOrigin or inputs.origin;s.camera=inputs.terrainCamera
  s.age=s.age+1
  local ok,result=pcall(function()
    local result=Native.update(s.mem,s.callbacks)
    if result~=-1 then capture(s)end
    return result
  end)
  if not ok then s.error=tostring(result);s.active=false;return -1 end
  if result==-1 then s.active=false end
  return result
end
function Tri.geometry(s)return s.geometry end
function Tri.snapshot(s)return {kind='rom-tri-attack-state',age=s.age,active=s.active,
  sparkCount=s.sparkCount,drawReady=not s.error,error=s.error}end
return Tri
