package.path="./?.lua;./?/init.lua;"..package.path
-- Tri Attack (family 20) ported to Lua against the ROM in the MIPS VM on
-- identical memory: 84169B80 + 84158840 (init: 8415C530, 84169BA8,
-- 84158768, 8415C644), 84158874 (update: 8415DAE4, 8415D4C4, 84169DBC) and
-- the draw builder 8415DBBC in mode 5 (8415D430 with libultra's guRotateF,
-- 84169C74). The host boundaries are the same callbacks on both sides
-- (8416A050, the camera-facing spark submit, returns the list unchanged on
-- both). Every byte of both pools, the counter, the display list and the
-- vertices must match on every frame of whole effects. 8415D4C4's other
-- modes are checked by stepping slots forced into each mode.
local file=io.open(os.getenv("STADIUM2_ROM") or "mods/STADIUM2_IMPORTER/baseroms/stadium2.z64","rb")
if not file then assert(os.getenv("STADIUM2_REQUIRE_ROM")~="1","ROM required");print("SKIP Tri Attack native ROM");return end
local rom=file:read("*a");file:close()
local prefix="mods.STADIUM2_IMPORTER.lib."
local VM=require("mods.STADIUM2_IMPORTER.tests.support.stadium2_battle_fx_mips")
local FxRom=require(prefix.."stadium2_battle_fx_rom")
local Memory=require(prefix.."stadium2_native_memory")
local Random=require(prefix.."stadium2_battle_fx_random")
local T=require(prefix.."stadium2_battle_fx_tri_attack_native")
local f32=require(prefix.."stadium2_battle_fx_float")
local checks=0
local function ok(v,m) checks=checks+1 if not v then error("FAIL "..m,0) end end

local fragment=assert(FxRom.catalog(rom)).lifecycleAssets.fragment79
local main=rom:sub(0x1001,0xA8000)
local POOL,AUX,DL,ARENA=0x85000000,0x85010000,0x85200000,0x85300000
math.randomseed(1618)
local function rf(s) return f32((math.random()*2-1)*s) end

local function setup(origin,direction,seed,modeOverride)
  local vmRng,luaRng=Random.new(seed),Random.new(seed)
  local st={vmAlloc=ARENA,luaAlloc=ARENA}
  local vm=VM.new({{base=0x84100000,bytes=fragment},{base=0x80000400,bytes=main}},{
    [0x84156BA0]=function() end,
    [0x841569E0]=function(v)
      for k=1,3 do v:putFloat(v.r[k+3],origin[k]) end
      v:putFloat(v.r[7],direction[1]);v:putFloat(v:read(v.r[29]+16,4),direction[2]);v:putFloat(v:read(v.r[29]+20,4),direction[3])
    end,
    [0x84109780]=function(v) v:putVector(v.r[4],origin) end,
    [0x8007AFA0]=function(v) v.r[2]=vmRng:next() end,
    [0x80006DEC]=function(v) v.r[2]=st.vmAlloc;st.vmAlloc=st.vmAlloc+v.r[4] end,
    [0x8416A050]=function(v) v.r[2]=v.r[5] end,
  })
  local mem=Memory.new({{base=0x84100000,bytes=fragment}})
  for _,m in ipairs({vm,mem}) do
    m:write(T.POOL_POINTER,POOL-0x3C8,4);m:write(T.SPARK_POINTER,AUX,4)
  end
  local cb={anchor=function() return origin,direction end,origin=function() return origin end,
    random=function() return luaRng:next() end,
    alloc=function(n) local a=st.luaAlloc;st.luaAlloc=st.luaAlloc+n;return a end,
    sparks=function(_,dl) return dl end}
  return vm,mem,cb,st
end

local function comparer(vm,mem,label)
  return function(tag,lo,hi)
    for a=lo,hi-1 do
      if vm:byte(a)~=mem:u8(a) then
        error(("FAIL %s %s byte %08X ROM %02X Lua %02X"):format(label,tag,a,vm:byte(a),mem:u8(a)),0)
      end
    end
  end
end

local frames,draws,ended=0,0,0
for run=1,14 do
  local origin={(math.random()*2-1)*300,rf(100)+60,rf(300)}
  local d={rf(1),rf(0.5),rf(1)}
  local n=math.sqrt(d[1]^2+d[2]^2+d[3]^2)
  -- unrounded doubles, as the host passes them (the ROM stores floats)
  local direction={d[1]/n,d[2]/n,d[3]/n}
  local vm,mem,cb,st=setup(origin,direction,math.random(1,2^30))
  vm:call(0x84169B80);vm:call(0x84158840);T.init(mem,cb)
  for frame=1,200 do
    local compare=comparer(vm,mem,("run %d frame %d"):format(run,frame))
    compare("radial pool",POOL,POOL+T.SLOTS*T.SLOT_SIZE)
    compare("spark groups",AUX,AUX+T.GROUPS*T.GROUP_SIZE)
    compare("counter",T.COUNTER,T.COUNTER+2)
    st.vmAlloc,st.luaAlloc=ARENA,ARENA
    local vEnd=vm:call(0x8415DBBC,{DL})%4294967296
    local lEnd=T.draw(mem,cb,DL)
    if vEnd~=lEnd then error(("FAIL run %d frame %d draw end ROM %08X Lua %08X"):format(run,frame,vEnd,lEnd),0) end
    compare("display list",DL,vEnd)
    compare("vertices",ARENA,st.vmAlloc)
    compare("spark groups after draw",AUX,AUX+T.GROUPS*T.GROUP_SIZE)
    draws=draws+1
    for k=1,3 do origin[k]=origin[k]+(math.random()*2-1)*2 end
    local rv=vm:call(0x84158874);rv=rv>=2^31 and rv-2^32 or rv
    local rl=T.update(mem,cb)
    frames=frames+1
    ok(rv==rl,("update result run %d frame %d ROM %d Lua %d"):format(run,frame,rv,rl))
    if rv==-1 then ended=ended+1 break end
  end
end
print(("frames %d, draws %d, ended %d"):format(frames,draws,ended))
ok(ended==14,"every Tri Attack ran to its end")

-- 8415D4C4 in every mode (0..6), on slots with random elements
for round=1,120 do
  local origin={rf(200),rf(100),rf(200)}
  local vm,mem,cb=setup(origin,{1,0,0},round)
  vm:call(0x84169B80);vm:call(0x8415C530);T.clearGroups(mem);T.initPool(mem)
  local slot=POOL
  local mode=round%7
  local w={}
  local function set(a,n,v) vm:write(a,v,n);mem:write(a,v,n) end
  local function setF(a,v) vm:putFloat(a,v);mem:setF32(a,v) end
  set(slot+8,2,mode);setF(slot+0x14,f32(5+math.random()*20));setF(slot+0x18,rf(0.3))
  for k=0,T.ELEMENTS-1 do
    local e=slot+0x48+k*T.ELEMENT_SIZE
    setF(e,math.random(4)==1 and f32(math.random(0,3)) or 0)
    setF(e+8,f32(math.random()*25))
    for o=0xC,0x24,4 do setF(e+o,rf(o>=0x1C and 3 or 200)) end
  end
  for step=1,6 do
    vm:call(0x8415D4C4,{slot});T.stepSlot(mem,cb,slot)
    comparer(vm,mem,("mode %d round %d step %d"):format(mode,round,step))("slot",slot,slot+T.SLOT_SIZE)
  end
end
ok(true,"8415D4C4 matches the ROM in every mode (0-6)")
ok(draws>500,"the mode-5 draw builder matched the ROM on "..draws.." frames")
print(checks.." checks passed (Tri Attack vs ROM)")
