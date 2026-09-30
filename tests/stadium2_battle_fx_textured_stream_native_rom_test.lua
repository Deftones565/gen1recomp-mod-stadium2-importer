package.path="./?.lua;./?/init.lua;"..package.path
-- Ice Beam (family 13) and Hyper Beam (family 8) streams ported to Lua
-- against the ROM in the MIPS VM on identical memory: 84158E24 / 84159C2C
-- (init: 84168540, 84158C4C / 84159A50, 841597AC), 84158E58 / 84159C6C
-- (update: 84169040, 84168CA4, 84168680) and the draw builder 84169618
-- (with 84168C18 and libultra). The host boundaries are hooked the same way
-- on both sides; the core-beam calls (84166F60, 841670A8, 841677C4) are
-- recorded and their arguments compared word for word. __sinf, __cosf and
-- 84168C18 run from the ROM. Every byte of the pool, the counters, the
-- stale stack word 84168CA4 reads, the display list and the vertices must
-- match on every frame of whole effects.
local file=io.open(os.getenv("STADIUM2_ROM") or "mods/STADIUM2_IMPORTER/baseroms/stadium2.z64","rb")
if not file then assert(os.getenv("STADIUM2_REQUIRE_ROM")~="1","ROM required");print("SKIP textured stream native ROM");return end
local rom=file:read("*a");file:close()
local prefix="mods.STADIUM2_IMPORTER.lib."
local VM=require("mods.STADIUM2_IMPORTER.tests.support.stadium2_battle_fx_mips")
local FxRom=require(prefix.."stadium2_battle_fx_rom")
local Memory=require(prefix.."stadium2_native_memory")
local Random=require(prefix.."stadium2_battle_fx_random")
local S=require(prefix.."stadium2_battle_fx_textured_stream_native")
local checks=0
local function ok(v,m) checks=checks+1 if not v then error("FAIL "..m,0) end end

local fragment=assert(FxRom.catalog(rom)).lifecycleAssets.fragment79
local main=rom:sub(0x1001,0xA8000)
local POOL,DL,ARENA=0x85000000,0x85200000,0x85300000
math.randomseed(8080)
local function rd(s) return (math.random()*2-1)*s end

local frames,draws,ended,coreCalls=0,0,0,0
for run=1,12 do
  local family=run%2==0 and 8 or 13
  local seed=math.random(1,2^30)
  local vmRng,luaRng=Random.new(seed),Random.new(seed)
  local origin={rd(300),rd(80)+60,rd(300)}
  local d={rd(1),rd(0.4),rd(1)} local n=math.sqrt(d[1]^2+d[2]^2+d[3]^2)
  local direction={d[1]/n,d[2]/n,d[3]/n}
  local signal,endAt=0,math.random(40,120)
  local coreEnd=math.random(60,160)
  local st={vm=ARENA,lua=ARENA,vmCore={},luaCore={},vmStep=0,luaStep=0}
  local vm=VM.new({{base=0x84100000,bytes=fragment},{base=0x80000400,bytes=main}},{
    [0x84156BA0]=function() end,
    [0x841569E0]=function(v)
      for k=1,3 do v:putFloat(v.r[k+3],origin[k]) end
      v:putFloat(v.r[7],direction[1]);v:putFloat(v:read(v.r[29]+16,4),direction[2]);v:putFloat(v:read(v.r[29]+20,4),direction[3])
    end,
    [0x84109780]=function(v) v:putVector(v.r[4],origin) end,
    [0x841094EC]=function(v) v.r[2]=signal end,
    [0x841094A4]=function(v) v.r[2]=0x85600000 end,
    [0x8007AFA0]=function(v) v.r[2]=vmRng:next() end,
    [0x80006DEC]=function(v) v.r[2]=st.vm;st.vm=st.vm+v.r[4] end,
    [0x84166F60]=function() st.vmCore[#st.vmCore+1]="init" end,
    [0x841670A8]=function(v)
      local words={} for off=0x10,0x90,4 do words[off]=v:read(v.r[29]+off,4) end
      st.vmCore[#st.vmCore+1]=("spawn %08X %08X %08X %08X"):format(v.f[12]%2^32,v.f[14]%2^32,v.r[6]%2^32,v.r[7]%2^32)
      for off=0x10,0x90,4 do st.vmCore[#st.vmCore]=st.vmCore[#st.vmCore]..(" %08X"):format(words[off]) end
      v.r[2]=0
    end,
    [0x841677C4]=function(v) st.vmStep=st.vmStep+1;v.r[2]=st.vmStep>=coreEnd and -1 or 0 end,
    [0x800710A8]=function() end,
    [0x84169344]=function(v) v.r[2]=v.r[4] end,
    [0x84169214]=function(v) v.r[2]=v.r[4] end,
  })
  local mem=Memory.new({{base=0x84100000,bytes=fragment}})
  for _,m in ipairs({vm,mem}) do m:write(S.POOL_POINTER,POOL-0x900,4) end
  local word=Memory.floatWord
  local cb={anchor=function() return origin,direction end,origin=function() return origin end,
    signal=function() return signal end,random=function() return luaRng:next() end,
    alloc=function(k) local a=st.lua;st.lua=st.lua+k;return a end,
    coreInit=function() st.luaCore[#st.luaCore+1]="init" end,
    coreSpawn=function(c)
      local line=("spawn %08X %08X %08X %08X"):format(word(c.fa0),word(c.fa1),word(c.a2),word(c.a3))
      for off=0x10,0x90,4 do line=line..(" %08X"):format((c.stack[off] or 0)%2^32) end
      st.luaCore[#st.luaCore+1]=line
      return 0
    end,
    coreStep=function() st.luaStep=st.luaStep+1;return st.luaStep>=coreEnd and -1 or 0 end,
    combine=function() end,material=function(dl) return dl end,strip=function(dl) return dl end}
  local function compare(label)
    local function range(tag,lo,hi)
      for a=lo,hi-1 do
        if vm:byte(a)~=mem:u8(a) then
          error(("FAIL run %d (family %d) %s %s byte %08X ROM %02X Lua %02X"):format(run,family,label,tag,a,vm:byte(a),mem:u8(a)),0)
        end
      end
    end
    range("pool",POOL,POOL+S.SLOTS*S.SLOT_SIZE)
    range("counters",0x841A4D48,0x841A4D52)
    range("end",0x841A4DC0,0x841A4DC6)
    range("stale stack word",S.STALE,S.STALE+4)
    return range
  end
  vm:call(family==8 and 0x84159C2C or 0x84158E24);S.init(mem,cb,family)
  compare("init")
  for frame=0,400 do
    if frame>0 then
      frames=frames+1
      if frame==endAt then signal=1 end
      for k=1,3 do origin[k]=origin[k]+rd(2) end
      local rv=vm:call(family==8 and 0x84159C6C or 0x84158E58);rv=rv>=2^31 and rv-2^32 or rv
      local rl=S.update(mem,cb,family)
      ok(rv==rl,("update result run %d frame %d ROM %d Lua %d"):format(run,frame,rv,rl))
      compare("frame "..frame)
      if rv==-1 then ended=ended+1 break end
    end
    st.vm,st.lua=ARENA,ARENA
    local vEnd=vm:call(0x84169618,{DL})%4294967296
    local lEnd=S.draw(mem,cb,DL)
    if vEnd~=lEnd then error(("FAIL run %d frame %d draw end ROM %08X Lua %08X"):format(run,frame,vEnd,lEnd),0) end
    local range=compare("draw "..frame)
    range("display list",DL,vEnd)
    range("vertices",ARENA,st.vm)
    draws=draws+1
  end
  ok(#st.vmCore==#st.luaCore,"core-beam calls run "..run)
  for i=1,#st.vmCore do ok(st.vmCore[i]==st.luaCore[i],("core-beam call %d run %d:\nROM %s\nLua %s"):format(i,run,st.vmCore[i],st.luaCore[i])) end
  coreCalls=coreCalls+#st.vmCore
end
print(("frames %d, draws %d, ended %d, core-beam calls %d"):format(frames,draws,ended,coreCalls))
ok(ended==12,"every stream ran to its end")
ok(coreCalls==18,"Hyper Beam's core init and two core spawns match the ROM's calls")
print(checks.." checks passed (Ice Beam / Hyper Beam streams vs ROM)")
