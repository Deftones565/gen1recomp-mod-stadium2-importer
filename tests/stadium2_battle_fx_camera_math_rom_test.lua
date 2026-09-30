package.path="./?.lua;./?/init.lua;"..package.path
-- The Lua camera maths against the ROM's own routines run in the MIPS VM,
-- bit for bit: 8000B3B0 (atan2), 80037120 (distance/pitch/yaw), 800371B4
-- (eye placement), 841203B4 (easing), 8003570C (the game's LCG).
local file=io.open(os.getenv("STADIUM2_ROM") or "mods/STADIUM2_IMPORTER/baseroms/stadium2.z64","rb")
if not file then assert(os.getenv("STADIUM2_REQUIRE_ROM")~="1","ROM required");print("SKIP battle camera maths ROM");return end
local rom=file:read("*a");file:close()
local prefix="mods.STADIUM2_IMPORTER.lib."
local VM=require("mods.STADIUM2_IMPORTER.tests.support.stadium2_battle_fx_mips")
local FxRom=require(prefix.."stadium2_battle_fx_rom")
local Native=require(prefix.."stadium2_battle_camera_native")
local f32=require(prefix.."stadium2_battle_fx_float")
local checks=0
local function ok(v,m) checks=checks+1 if not v then error("FAIL "..m,0) end end

local cam=assert(Native.load(rom))
local catalog=assert(FxRom.catalog(rom))
local vm=VM.new({{base=0x80000400,bytes=rom:sub(0x1001,0xA8000)},
  {base=0x84100000,bytes=catalog.lifecycleAssets.fragment79}})
local W=VM.floatWord
local function s16(v) v=v%65536 return v>=32768 and v-65536 or v end

-- deterministic spread of inputs, plus the edge cases
-- deterministic (LuaJIT's generator with a fixed seed)
math.randomseed(12345)
local function rnd(scale)
  return f32((math.random()*2-1)*scale)
end
local values={0,1,-1,0.5,-0.5,1000,-1000,3,-3,0.001,-0.001}
for _=1,60 do values[#values+1]=rnd(500) end

-- 8000B3B0
local n=0
for _,x in ipairs(values) do for _,y in ipairs(values) do
  vm.f[12]=W(x);vm.f[14]=W(y)
  local native=s16(vm:call(0x8000B3B0,{}))
  local lua=cam:atan2(x,y)
  if native~=lua then error(("FAIL atan2(%g,%g) ROM %d Lua %d"):format(x,y,native,lua),0) end
  n=n+1
end end
ok(n>5000,"8000B3B0 atan2 matches the ROM on "..n.." pairs")

-- 80037120
local A,B,DIST,PITCH,YAW=0x85000000,0x85000010,0x85000020,0x85000024,0x85000028
for i=1,400 do
  local from={rnd(300),rnd(300),rnd(300)}
  local to=i%7==0 and {from[1],from[2],from[3]} or {rnd(300),rnd(300),rnd(300)}
  vm:putVector(A,from);vm:putVector(B,to)
  vm:write(0x857FF010,YAW,4) -- fifth argument on the stack
  vm:call(0x80037120,{A,B,DIST,PITCH})
  local d,p,y=cam:angleTo(from,to)
  local nd,np,ny=vm:float(DIST),s16(vm:read(PITCH,2)),s16(vm:read(YAW,2))
  if nd~=d or np~=p or ny~=y then
    error(("FAIL angleTo #%d ROM %.9g %d %d Lua %.9g %d %d"):format(i,nd,np,ny,d,p,y),0)
  end
end
ok(true,"80037120 distance, pitch and yaw match the ROM")

-- 800371B4
for i=1,400 do
  local center={rnd(300),rnd(300),rnd(300)}
  local dist,pitch,yaw=f32(math.abs(rnd(800))),s16(math.floor(rnd(32768))),s16(math.floor(rnd(32768)))
  vm:putVector(A,center)
  vm:write(0x857FF010,yaw%65536,4)
  vm:call(0x800371B4,{A,B,W(dist),pitch%65536})
  local out=cam:placeEye(center,dist,pitch,yaw)
  local native=vm:vector(B)
  for k=1,3 do
    if native[k]~=out[k] then error(("FAIL placeEye #%d axis %d ROM %.9g Lua %.9g"):format(i,k,native[k],out[k]),0) end
  end
end
ok(true,"800371B4 eye placement matches the ROM")

-- 841203B4
for i=1,400 do
  local value,goal,rate=rnd(200),rnd(200),f32(math.abs(rnd(1)))
  if i%9==0 then goal=f32(value+0.0004) end
  vm:putFloat(A,value);vm.f[14]=W(goal);vm.r[6]=W(rate)
  vm:call(0x841203B4,{A,W(goal),W(rate)})
  local native=vm:float(A)
  local lua=Native.ease(value,goal,rate)
  if native~=lua then error(("FAIL ease #%d ROM %.9g Lua %.9g"):format(i,native,lua),0) end
end
ok(true,"841203B4 easing matches the ROM")

-- 8003570C
local s=0x1234567
vm:write(0x80124D50,s,4)
for i=1,50 do
  vm:call(0x8003570C,{})
  s=Native.nextRandom(s)
  if vm:read(0x80124D50,4)~=s then error("FAIL LCG step "..i,0) end
end
ok(true,"8003570C random sequence matches the ROM")

print(checks.." checks passed (battle camera maths vs ROM)")
