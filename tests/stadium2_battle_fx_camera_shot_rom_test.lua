package.path="./?.lua;./?/init.lua;"..package.path
-- Shot setup ported to Lua against the ROM run in the MIPS VM on identical
-- memory: 8410C934 / 8410CAE4 (with 8410B974, 8410B8FC, 8411DC80,
-- 8411E0A4) and 8410B884. Every byte of both controllers, both GeoCameras
-- and D_841911E8 must match. 8411DD8C (the actor's marker point, supplied
-- by the battle scene) is the same stand-in on both sides.
local file=io.open(os.getenv("STADIUM2_ROM") or "mods/STADIUM2_IMPORTER/baseroms/stadium2.z64","rb")
if not file then assert(os.getenv("STADIUM2_REQUIRE_ROM")~="1","ROM required");print("SKIP battle camera shots ROM");return end
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

-- the stand-in marker point (8411DD8C writes it to its second argument)
local function marker(read,actor)
  return {f32(read(actor+0x24)+3),f32(read(actor+0x638)+11),f32(read(actor+0x2C)-7)}
end

-- deterministic (LuaJIT's generator with a fixed seed)
math.randomseed(777)
local function rnd(n) return math.random(0,n-1) end
local function rf(scale) return f32((rnd(200001)/100000-1)*scale) end

local function scenario()
  local w={} -- address -> {size, value} (float values marked)
  local function set(a,n,v) w[#w+1]={a,n,v} end
  local function setF(a,v) w[#w+1]={a,"f",v} end
  set(0x841911E0,4,C0);set(0x841911E4,4,C1);set(C0,4,GC0);set(C1,4,GC1)
  set(0x84191208,4,A0);set(0x8419120C,4,A1);set(0x84193DD0,4,REC)
  local species={0x5F,0xA3,0x54,0x55,1,25,150,249}
  for _,a in ipairs({A0,A1}) do
    set(a+0x1A,2,species[rnd(#species)+1])
    set(a+0x20,2,rnd(65536))
    setF(a+0x24,rf(400));setF(a+0x2C,rf(400))
    set(a+0x61F,1,rnd(3)==0 and 0x0 or rnd(40))
    for off=0x634,0x654,4 do setF(a+off,rf(off==0x64C and 600 or 150)) end
    set(a+0x7EA,2,rnd(2)==0 and 0 or 1+rnd(5))
    set(a+0x7F4,2,rnd(64))
  end
  local codes={4,8,0x5A,0x22,1}
  set(REC+4,2,codes[rnd(#codes)+1])
  for s=0,1 do
    set(REC+s*16+0xE,2,rnd(3)==0 and 0 or rnd(300))
    set(REC+s*16+0x10,2,rnd(4)==0 and 0x20 or rnd(8))
    set(REC+s*16+0x12,2,rnd(16))
  end
  return w
end

local function apply(w,write,writeF)
  for _,e in ipairs(w) do
    if e[2]=="f" then writeF(e[1],e[3]) else write(e[1],e[3],e[2]) end
  end
end

luaMarkers,vmMarkers=0,0
local regions={{C0,0xA4},{C1,0xA4},{GC0,0xD0},{GC1,0xD0},{0x841911E8,4}}
local cases=0
for round=1,300 do
  local w=scenario()
  local vm=VM.new({{base=0x80000400,bytes=rom:sub(0x1001,0xA8000)},{base=0x84100000,bytes=fragment}},{
    [0x8411DD8C]=function(v) vmMarkers=vmMarkers+1;v:putVector(v.r[5],marker(function(a) return v:float(a) end,v.r[4]%4294967296)) end})
  apply(w,function(a,v,n) vm:write(a,v,n) end,function(a,v) vm:putFloat(a,v) end)
  local cam
  cam=assert(Native.load(rom,fragment,{markerPosition=function(actor)
    luaMarkers=luaMarkers+1
    return marker(function(a) return cam.mem:f32(a) end,actor) end}))
  apply(w,function(a,v,n) cam.mem:write(a,v,n) end,function(a,v) cam.mem:setF32(a,v) end)
  local gc=rnd(2)==0 and GC0 or GC1
  local actor=rnd(2)==0 and A0 or A1
  local shot=rnd(41)
  local which=rnd(3)
  if which==0 then vm:call(0x8410C934,{gc,actor,shot});cam:shot(gc,actor,shot)
  elseif which==1 then vm:call(0x8410CAE4,{gc,actor,shot});cam:shotB(gc,actor,shot)
  else
    local ctrl=cam:controllerFor(gc)
    local yaw=rnd(65536)-32768
    vm:write(ctrl+0x98,shot,2);cam.mem:write(ctrl+0x98,shot,2)
    vm:call(0x8410B884,{gc,actor,ctrl,yaw%65536});cam:secondaryPose(actor,ctrl,yaw)
  end
  for _,r in ipairs(regions) do
    for a=r[1],r[1]+r[2]-1 do
      local native,lua=vm:byte(a),cam.mem:u8(a)
      if native~=lua then
        error(("FAIL round %d (%s shot %d) byte %08X ROM %02X Lua %02X"):format(round,
          ({"8410C934","8410CAE4","8410B884"})[which+1],shot,a,native,lua),0)
      end
    end
  end
  cases=cases+1
end
print("marker branch runs: ROM "..vmMarkers.." Lua "..luaMarkers)
ok(vmMarkers>20 and vmMarkers==luaMarkers,"the marker branch (8411E0A4) runs in both, as often")
ok(cases==300,"8410C934, 8410CAE4 and 8410B884 match the ROM byte for byte in 300 scenarios")
print(checks.." checks passed (battle camera shot setup vs ROM)")
