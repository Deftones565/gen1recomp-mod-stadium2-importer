package.path="./?.lua;./?/init.lua;"..package.path
-- Camera program 0 ported to Lua against the ROM in the MIPS VM on identical
-- memory: 84110394 (one-shot setup: 84120BB4 reset, 8410C934, empty slot)
-- and 84110718 (every tick: FOV ease, 8410DFC4 follow with the band helpers
-- 8410D5CC / 8410DAC8 / 8410D9B8 / 8410DEB4, 8410E688 / 8410E73C with
-- 8410B704, and the 84110B2C jolt). The scene boundaries (8411DD8C marker
-- point, 8411EF2C and 84120700 actor presentation) are hooked identically.
local file=io.open(os.getenv("STADIUM2_ROM") or "mods/STADIUM2_IMPORTER/baseroms/stadium2.z64","rb")
if not file then assert(os.getenv("STADIUM2_REQUIRE_ROM")~="1","ROM required");print("SKIP battle camera program 0 ROM");return end
local rom=file:read("*a");file:close()
local prefix="mods.STADIUM2_IMPORTER.lib."
local VM=require("mods.STADIUM2_IMPORTER.tests.support.stadium2_battle_fx_mips")
local FxRom=require(prefix.."stadium2_battle_fx_rom")
local Native=require(prefix.."stadium2_battle_camera_native")
local f32=require(prefix.."stadium2_battle_fx_float")
local checks=0
local function ok(v,m) checks=checks+1 if not v then error("FAIL "..m,0) end end

local fragment=assert(FxRom.catalog(rom)).lifecycleAssets.fragment79
local C0,C1,GC0,GC1=0x85000000,0x85000100,0x85000200,0x85000300
local A0,A1,REC=0x85001000,0x85002000,0x85003000
math.randomseed(4242)
local function rnd(n) return math.random(0,n-1) end
local function rf(scale) return f32((math.random()*2-1)*scale) end

local function marker(read,actor)
  return {f32(read(actor+0x24)+3),f32(read(actor+0x638)+11),f32(read(actor+0x2C)-7)}
end

-- coverage of the ported branches
local used={}
local reframe=Native.reframe
Native.reframe=function(self,helper,...) used[helper]=(used[helper] or 0)+1 return reframe(self,helper,...) end
local jolts,follows=0,0

local function scenario()
  local w={}
  local function set(a,n,v) w[#w+1]={a,n,v} end
  local function setF(a,v) w[#w+1]={a,"f",v} end
  set(0x841911E0,4,C0);set(0x841911E4,4,C1);set(C0,4,GC0);set(C1,4,GC1)
  set(0x84191208,4,A0);set(0x8419120C,4,A1);set(0x84193DD0,4,REC)
  local species={0xE8,0x24,0x57,0x9C,0x49,0xE2,0x9B,0x71,0x5F,1,25,150}
  for _,a in ipairs({A0,A1}) do
    set(a+0x1A,2,species[rnd(#species)+1])
    set(a+0x20,2,rnd(65536))
    setF(a+0x24,rf(400));setF(a+0x2C,rf(400))
    setF(a+0x34,rnd(8)==0 and 0.05 or f32(0.5+math.random()))
    set(a+0x61F,1,rnd(4)==0 and 4 or rnd(40))
    for off=0x634,0x654,4 do setF(a+off,rf(off==0x64C and 600 or 150)) end
    setF(a+0x640,f32(math.random()*60)) -- slack
    set(a+0x7EA,2,rnd(3))
    set(a+0x7F4,2,rnd(4)==0 and rnd(64) or 0)
  end
  set(REC+4,2,({4,8,0x5A,0x22,1})[rnd(5)+1])
  for s=0,1 do
    set(REC+s*16+0xE,2,rnd(4)==0 and 0 or 1+rnd(300))
    set(REC+s*16+0x10,2,rnd(6)==0 and 0x20 or rnd(8))
    set(REC+s*16+0x12,2,rnd(4)==0 and rnd(16) or 0)
  end
  for _,c in ipairs({C0,C1}) do
    set(c+0x98,2,rnd(39))
    setF(c+0x8C,0);set(c+0x96,2,0)
  end
  for _,g in ipairs({GC0,GC1}) do
    setF(g+0x2C,f32(20+math.random()*60))
    for off=0xA8,0xBC,4 do setF(g+off,rf(500)) end
  end
  set(0x841911EC,4,0)
  return w
end
local function apply(w,write,writeF)
  for _,e in ipairs(w) do if e[2]=="f" then writeF(e[1],e[3]) else write(e[1],e[3],e[2]) end end
end

local regions={{C0,0xA4},{C1,0xA4},{GC0,0xD0},{GC1,0xD0},{0x841911E8,4},{A0+0x7EA,2},{A1+0x7EA,2}}
local function compare(vm,cam,label)
  for _,r in ipairs(regions) do
    for a=r[1],r[1]+r[2]-1 do
      if vm:byte(a)~=cam.mem:u8(a) then
        error(("FAIL %s byte %08X ROM %02X Lua %02X"):format(label,a,vm:byte(a),cam.mem:u8(a)),0)
      end
    end
  end
end

local ticks=0
for round=1,150 do
  local w=scenario()
  local vm=VM.new({{base=0x80000400,bytes=rom:sub(0x1001,0xA8000)},{base=0x84100000,bytes=fragment}},{
    [0x8411DD8C]=function(v) v:putVector(v.r[5],marker(function(a) return v:float(a) end,v.r[4]%4294967296)) end,
    [0x8411EF2C]=function() end,[0x84120700]=function() end})
  apply(w,function(a,v,n) vm:write(a,v,n) end,function(a,v) vm:putFloat(a,v) end)
  local cam
  cam=assert(Native.load(rom,fragment,{markerPosition=function(actor)
    return marker(function(a) return cam.mem:f32(a) end,actor) end}))
  apply(w,function(a,v,n) cam.mem:write(a,v,n) end,function(a,v) cam.mem:setF32(a,v) end)
  local gc=rnd(2)==0 and GC0 or GC1
  local actor=rnd(2)==0 and A0 or A1
  vm:call(0x84110394,{gc,actor});cam:program0Setup(gc,actor)
  compare(vm,cam,("round %d setup"):format(round))
  for tick=1,10 do
    -- the Pokemon move, and a hit sometimes starts the jolt
    for _,a in ipairs({A0,A1}) do
      for _,off in ipairs({0x24,0x2C,0x638}) do
        local v=f32(cam.mem:f32(a+off)+rf(40))
        vm:putFloat(a+off,v);cam.mem:setF32(a+off,v)
      end
    end
    if rnd(5)==0 then
      local amount=f32(math.random()*25)
      vm.f[12]=VM.floatWord(amount);vm:call(0x8410B578,{});cam:setJolt(amount)
      jolts=jolts+1
    end
    vm:call(0x84110718,{gc,actor});cam:program0Tick(gc,actor)
    compare(vm,cam,("round %d tick %d"):format(round,tick))
    ticks=ticks+1
  end
end
-- The ROM runner 84111774 with program 0 loaded by 84111348 / 841113F8 in
-- both controllers, against Native:setProgram / setProgram1 / tick.
local runnerTicks=0
for round=1,60 do
  local w=scenario()
  local vm=VM.new({{base=0x80000400,bytes=rom:sub(0x1001,0xA8000)},{base=0x84100000,bytes=fragment}},{
    [0x8411DD8C]=function(v) v:putVector(v.r[5],marker(function(a) return v:float(a) end,v.r[4]%4294967296)) end,
    [0x8411EF2C]=function() end,[0x84120700]=function() end,
    [0x841114A8]=function() end}) -- sound panning, not part of the camera
  apply(w,function(a,v,n) vm:write(a,v,n) end,function(a,v) vm:putFloat(a,v) end)
  local cam
  cam=assert(Native.load(rom,fragment,{markerPosition=function(actor)
    return marker(function(a) return cam.mem:f32(a) end,actor) end}))
  apply(w,function(a,v,n) cam.mem:write(a,v,n) end,function(a,v) cam.mem:setF32(a,v) end)
  local owner0,owner1=rnd(2)==0 and A0 or A1,rnd(2)==0 and A0 or A1
  vm:call(0x84111348,{owner0,0});cam:setProgram(owner0,0)
  vm:call(0x841113F8,{owner1,0});cam:setProgram1(owner1,0)
  compare(vm,cam,("round %d load"):format(round))
  for tick=1,8 do
    for _,a in ipairs({A0,A1}) do
      for _,off in ipairs({0x24,0x2C}) do
        local v=f32(cam.mem:f32(a+off)+rf(30))
        vm:putFloat(a+off,v);cam.mem:setF32(a+off,v)
      end
    end
    vm:call(0x84111774,{GC0,GC1});cam:tick(GC0,GC1)
    compare(vm,cam,("round %d runner tick %d"):format(round,tick))
    if vm:read(0x841911EC,4)~=cam.mem:u32(0x841911EC) then error("FAIL slot counter",0) end
    runnerTicks=runnerTicks+1
  end
end
ok(runnerTicks==480,"84111774 with 84111348 / 841113F8 matches the ROM over 480 ticks")

local names={[0x8410D5CC]="8410D5CC",[0x8410DAC8]="8410DAC8",[0x8410D9B8]="8410D9B8",[0x8410DEB4]="8410DEB4"}
local parts={} for k,v in pairs(used) do parts[#parts+1]=names[k].."="..v end
print("band helpers used: "..table.concat(parts," ").." jolts: "..jolts)
ok(ticks==1500,"84110394 and 84110718 match the ROM byte for byte over 150 scenarios, 1500 ticks")
for helper,name in pairs(names) do ok((used[helper] or 0)>0,name.." (a reframe band table) was exercised") end
ok(jolts>50,"the hit jolt ran")
print(checks.." checks passed (battle camera program 0 vs ROM)")
