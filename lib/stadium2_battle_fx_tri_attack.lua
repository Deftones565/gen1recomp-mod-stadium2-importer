-- Family 20 / US 84158840: persistent Radial20 mode-5 kernel and native
-- generated display-list capture. Draw-side RNG/spawns run once per 30 Hz
-- tick; host redraws only consume the captured geometry.
local VM=require('mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_mips')
local f=require('mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_float')
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
  local vm=s.vm
  s.allocation=VERT
  local finish=vm:call(0x8415DBBC,{DL})%4294967296
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
  -- 8416A050 billboards the ROM quad using inverse camera rotation.
  -- Simulation and random spark births above execute the original kernel.
  local camera=assert(s.camera,'Tri Attack requires live camera inputs')
  local z=normalize({camera.eye[1]-camera.focus[1],camera.eye[2]-camera.focus[2],camera.eye[3]-camera.focus[3]})
  local x=normalize(cross(camera.up or {0,1,0},z));local y=cross(z,x)
  local dst=g.layers[4]
  s.sparkCount=0
  for i=0,19 do
    local at=AUX+4+i*24;local active=vm:read(at,2)==1
    if active then s.sparkCount=s.sparkCount+1 end
    local age=vm:read(at+4,2)
    local scale=active and f(vm:float(at+8)*f(math.sin(f(f(age*vm:float(0x8418C940))/10)))) or 0
    scale=math.floor(scale*65536)/65536
    local p=vm:vector(at+12)
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
  s.vm=VM.new({{base=0x84100000,bytes=fragment}},{
    [0x841569E0]=function(v)
      for k=1,3 do v:putFloat(v.r[k+3],s.origin[k])end
      v:putFloat(v.r[7],s.direction[1]);v:putFloat(v:read(v.r[29]+16,4),s.direction[2]);v:putFloat(v:read(v.r[29]+20,4),s.direction[3])
    end,
    [0x84109780]=function(v)v:putVector(v.r[4],s.origin)end,
    [0x8007AFA0]=function(v)v.r[2]=rng:next()end,
    [0x80006DEC]=function(v)v.r[2]=s.allocation;s.allocation=s.allocation+v.r[4]end,
    [0x8415D430]=function(v)
      v:write(0x85700000,v.f[12],4);local angle=v:float(0x85700000)
      v:write(0x85700000,v.r[7],4);local radius=v:float(0x85700000)
      local radians=f(f(angle*360/6.2831854820251465)*f(3.1415926/180))
      v:putVector(v.r[6],{0,f(-f(math.sin(radians))*radius),f(f(math.cos(radians))*radius)})
    end,
    -- Billboard submission is captured from the same persistent child pool.
    [0x8416A050]=function(v)v.r[2]=v.r[5]end,
  })
  local ok,err=pcall(function()
    s.vm:write(0x84187530,POOL-0x3C8,4);s.vm:write(0x84187E40,AUX,4)
    s.vm:call(0x84169B80);s.vm:call(0x8415C530);s.vm:call(0x84158768)
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
    if s.age>=181 then return -1 end
    local result=s.vm:call(0x8415DAE4)
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
