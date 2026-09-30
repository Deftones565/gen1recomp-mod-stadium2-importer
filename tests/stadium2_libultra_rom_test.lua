package.path="./?.lua;./?/init.lua;"..package.path
-- libultra's gu routines ported to Lua (lib/stadium2_libultra.lua) against
-- the ROM's own copies run in the MIPS VM on the same inputs: __sinf,
-- __cosf, guMtxF2L, guMtxL2F, guMtxCatF, guMtxCatL, guMtxXFMF, guTranslate,
-- guScale, guRotateRPYF, guRotateRPY (8007D454) and guRotateF (with
-- guNormalize and sqrtf). Results must match bit
-- for bit.
local file=io.open(os.getenv("STADIUM2_ROM") or "mods/STADIUM2_IMPORTER/baseroms/stadium2.z64","rb")
if not file then assert(os.getenv("STADIUM2_REQUIRE_ROM")~="1","ROM required");print("SKIP libultra ROM");return end
local rom=file:read("*a");file:close()
local prefix="mods.STADIUM2_IMPORTER.lib."
local VM=require("mods.STADIUM2_IMPORTER.tests.support.stadium2_battle_fx_mips")
local U=require(prefix.."stadium2_libultra")
local Memory=require(prefix.."stadium2_native_memory")
local f32=require(prefix.."stadium2_battle_fx_float")
local checks=0
local function ok(v,m) checks=checks+1 if not v then error("FAIL "..m,0) end end
math.randomseed(31337)

local vm=VM.new({{base=0x80000400,bytes=rom:sub(0x1001,0xA8000)}},{})
local mem=Memory.new({})
local word=Memory.floatWord
local function same(a,b) return word(a)==word(b) end
local function show(v) return ("%.9g (%08X)"):format(v,word(v)) end

-- a spread of floats: tiny, small, around pi multiples, large, negative
local function randomFloat()
  local r=math.random(6)
  local v
  if r==1 then v=(math.random()-0.5)*0.001
  elseif r==2 then v=(math.random()-0.5)*3
  elseif r==3 then v=(math.random()-0.5)*40
  elseif r==4 then v=(math.random()-0.5)*4000
  elseif r==5 then v=(math.random()-0.5)*1e9
  else v=math.random(-8,8)*math.pi/2 end
  return f32(v)
end

-- __sinf / __cosf
for i=1,4000 do
  local x=randomFloat()
  vm.f[12]=word(x);vm:call(U.SINF,{})
  local s=Memory.wordFloat(vm.f[0])
  if not same(s,U.sinf(x)) then error("FAIL sinf("..show(x)..") ROM "..show(s).." Lua "..show(U.sinf(x)),0) end
  vm.f[12]=word(x);vm:call(U.COSF,{})
  local c=Memory.wordFloat(vm.f[0])
  if not same(c,U.cosf(x)) then error("FAIL cosf("..show(x)..") ROM "..show(c).." Lua "..show(U.cosf(x)),0) end
end
ok(true,"__sinf and __cosf match the ROM in 4000 cases each")

local MF,NF,RES,M,N,L=0x85000000,0x85000100,0x85000200,0x85000300,0x85000400,0x85000500
local function putF(at,mf) for i=0,15 do vm:putFloat(at+i*4,mf[i]) end end
local function getF(at) local mf={} for i=0,15 do mf[i]=vm:float(at+i*4) end return mf end
local function sameF(a,b) for i=0,15 do if not same(a[i],b[i]) then return false,i end end return true end
local function rf1() local v repeat v=f32((math.random()-0.5)*4) until math.abs(v)>0.01 return v end
local function randomF(scale)
  local mf={} for i=0,15 do mf[i]=f32((math.random()-0.5)*(scale or 200)) end return mf
end
local function sameL(at,label)
  for a=at,at+63 do
    if vm:byte(a)~=mem:u8(a) then error(("FAIL %s byte %08X ROM %02X Lua %02X"):format(label,a,vm:byte(a),mem:u8(a)),0) end
  end
end

for i=1,300 do
  -- guMtxF2L (including values that overflow s15.16 and wrap)
  local mf=randomF(i%10==0 and 1e6 or 200)
  putF(MF,mf);vm:call(U.GU_MTX_F2L,{MF,L});U.mtxF2L(mf,mem,L)
  sameL(L,"guMtxF2L")
  -- guMtxL2F from arbitrary fixed-point words
  for a=0,63,4 do local w=math.random(0,0xFFFF)*65536+math.random(0,0xFFFF) vm:write(M+a,w,4);mem:setU32(M+a,w) end
  vm:call(U.GU_MTX_L2F,{MF,M})
  local okL,at=sameF(getF(MF),U.mtxL2F(mem,M))
  if not okL then error("FAIL guMtxL2F element "..at,0) end
  -- guMtxCatF
  local a,b=randomF(),randomF()
  putF(MF,a);putF(NF,b);vm:call(U.GU_MTX_CATF,{MF,NF,RES})
  local okC,atC=sameF(getF(RES),U.mtxCatF(a,b))
  if not okC then error("FAIL guMtxCatF element "..atC,0) end
  -- guMtxCatL
  for a2=0,63,4 do
    local w1=math.random(0,0xFFFF)*65536+math.random(0,0xFFFF)
    local w2=math.random(0,0xFFFF)*65536+math.random(0,0xFFFF)
    vm:write(M+a2,w1,4);mem:setU32(M+a2,w1);vm:write(N+a2,w2,4);mem:setU32(N+a2,w2)
  end
  vm:call(U.GU_MTX_CATL,{M,N,L});U.mtxCatL(mem,M,N,L)
  sameL(L,"guMtxCatL")
  -- guMtxXFMF
  local x,y,z=randomFloat(),randomFloat(),randomFloat()
  putF(MF,a)
  vm:write(0x857FF010,RES,4);vm:write(0x857FF014,RES+4,4);vm:write(0x857FF018,RES+8,4)
  vm:call(U.GU_MTX_XFMF,{MF,word(x),word(y),word(z)})
  local ox,oy,oz=U.mtxXFMF(a,x,y,z)
  ok(same(vm:float(RES),ox) and same(vm:float(RES+4),oy) and same(vm:float(RES+8),oz),"guMtxXFMF case "..i)
  -- guTranslate / guScale
  vm:call(U.GU_TRANSLATE,{L,word(x),word(y),word(z)});U.translate(mem,L,x,y,z)
  sameL(L,"guTranslate")
  vm:call(U.GU_SCALE,{L,word(x),word(y),word(z)});U.scale(mem,L,x,y,z)
  sameL(L,"guScale")
  -- guRotateRPYF / guRotateRPY (degrees)
  local r,p,h=f32((math.random()-0.5)*720),f32((math.random()-0.5)*720),f32((math.random()-0.5)*720)
  if i%7==0 then r=90 end
  vm:call(U.GU_ROTATE_RPYF,{MF,word(r),word(p),word(h)})
  local okR,atR=sameF(getF(MF),U.rotateRPYF(r,p,h))
  if not okR then error("FAIL guRotateRPYF element "..atR,0) end
  vm:call(U.GU_ROTATE_RPY,{L,word(r),word(p),word(h)});U.rotateRPY(mem,L,r,p,h)
  sameL(L,"guRotateRPY (8007D454)")
  -- guRotateF (with guNormalize and sqrtf) about an arbitrary axis
  local a,ax,ay,az=f32((math.random()-0.5)*720),rf1(),rf1(),rf1()
  if i%5==0 then ax,ay,az=1,0,0 end
  vm:write(0x857FF010,word(az),4)
  vm:call(U.GU_ROTATE_F,{MF,word(a),word(ax),word(ay)})
  local okF,atF=sameF(getF(MF),U.rotateF(a,ax,ay,az))
  if not okF then error("FAIL guRotateF element "..atF,0) end
end
ok(true,"guMtxF2L, guMtxL2F, guMtxCatF, guMtxCatL, guMtxXFMF, guTranslate, guScale, guRotateRPYF, guRotateRPY and guRotateF match the ROM in 300 cases each")
print(checks.." checks passed (libultra gu vs ROM)")
