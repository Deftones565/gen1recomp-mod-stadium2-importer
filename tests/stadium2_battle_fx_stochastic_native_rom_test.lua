package.path="./?.lua;./?/init.lua;"..package.path
-- The leaf / petal controller (families 3 and 15) ported to Lua against the
-- ROM in the MIPS VM on identical memory: 84157AB0 / 84157CB0 (init),
-- 84157ADC / 84157CDC (update, with 84166270, 8416691C, 841665D4) and the
-- draw builder 84166A64 (with 8416654C and libultra). The host boundaries
-- are the same callbacks on both sides; __sinf / __cosf and the gu routines
-- run from the ROM in the VM. Every byte of the pool, the counters, the
-- display list and the allocated matrices and vertices must match, every
-- frame of whole effects.
local file=io.open(os.getenv("STADIUM2_ROM") or "mods/STADIUM2_IMPORTER/baseroms/stadium2.z64","rb")
if not file then assert(os.getenv("STADIUM2_REQUIRE_ROM")~="1","ROM required");print("SKIP stochastic native ROM");return end
local rom=file:read("*a");file:close()
local prefix="mods.STADIUM2_IMPORTER.lib."
local VM=require("mods.STADIUM2_IMPORTER.tests.support.stadium2_battle_fx_mips")
local FxRom=require(prefix.."stadium2_battle_fx_rom")
local Memory=require(prefix.."stadium2_native_memory")
local Random=require(prefix.."stadium2_battle_fx_random")
local N=require(prefix.."stadium2_battle_fx_stochastic_native")
local f32=require(prefix.."stadium2_battle_fx_float")
local checks=0
local function ok(v,m) checks=checks+1 if not v then error("FAIL "..m,0) end end

local fragment=assert(FxRom.catalog(rom)).lifecycleAssets.fragment79
local main=rom:sub(0x1001,0xA8000)
local DL,ARENA=0x85200000,0x85300000
math.randomseed(2718)
local function rf(s) return f32((math.random()*2-1)*s) end

local frames,drawn,ended=0,0,0
for run=1,24 do
  local family=run%2==0 and 3 or 15
  local seed=math.random(1,2^30)
  local vmRng,luaRng=Random.new(seed),Random.new(seed)
  -- unrounded doubles, as the host passes them (the ROM stores floats)
  local function rd(s) return (math.random()*2-1)*s end
  local origin={rd(300),rd(100)+100,rd(300)}
  local target={rd(300),rd(150),rd(300)}
  local scale=0.5+math.random()*1.5
  local signal=0
  local endAt=math.random(15,70)
  local vmAlloc,luaAlloc=ARENA,ARENA
  local vm=VM.new({{base=0x84100000,bytes=fragment},{base=0x80000400,bytes=main}},{
    [0x84156BA0]=function() end,
    [0x84109780]=function(v) v:putVector(v.r[4],origin) end,
    [0x841098FC]=function(v) v:putVector(v.r[4],target) end,
    [0x84109544]=function(v) v.f[0]=VM.floatWord(scale) end,
    [0x841094EC]=function(v) v.r[2]=signal end,
    [0x8007AFA0]=function(v) v.r[2]=vmRng:next() end,
    [0x80006DEC]=function(v) v.r[2]=vmAlloc;vmAlloc=vmAlloc+v.r[4] end,
  })
  local mem=Memory.new({{base=0x84100000,bytes=fragment},{base=0x80000400,bytes=main}})
  local cb={origin=function() return origin end,target=function() return target end,
    scale=function() return scale end,signal=function() return signal end,
    random=function() return luaRng:next() end,
    alloc=function(n) local a=luaAlloc;luaAlloc=luaAlloc+n;return a end}
  local function compare(label,lo,hi)
    for a=lo,hi-1 do
      if vm:byte(a)~=mem:u8(a) then
        error(("FAIL %s run %d (family %d) frame %d byte %08X ROM %02X Lua %02X"):format(label,run,family,frames,a,vm:byte(a),mem:u8(a)),0)
      end
    end
  end
  local function compareState()
    compare("pool",N.POOL,N.POOL+N.SLOTS*N.SLOT_SIZE)
    compare("counters",0x841A4D54,0x841A4D58)
    compare("phase",0x841A4DB0,0x841A4DB6)
  end
  vm:call(family==3 and 0x84157AB0 or 0x84157CB0);N.init(mem,family)
  compareState()
  for frame=1,400 do
    frames=frames+1
    if frame==endAt then signal=1 end
    -- the anchors move a little every frame
    for k=1,3 do origin[k]=origin[k]+rd(3);target[k]=target[k]+rd(3) end
    local rv=vm:call(family==3 and 0x84157ADC or 0x84157CDC)
    rv=rv>=2^31 and rv-2^32 or rv
    local rl=N.update(mem,cb,family)
    ok(rv==rl,("update result run %d frame %d: ROM %d Lua %d"):format(run,frame,rv,rl))
    compareState()
    if rv==-1 then ended=ended+1 break end
    vmAlloc,luaAlloc=ARENA,ARENA
    local texture=family==3 and 34 or 35
    local vEnd=vm:call(0x84166A64,{DL,texture})%4294967296
    local lEnd=N.draw(mem,cb,DL,texture)
    if vEnd~=lEnd then error(("FAIL draw end run %d frame %d ROM %08X Lua %08X"):format(run,frame,vEnd,lEnd),0) end
    if vmAlloc~=luaAlloc then error("FAIL allocation size",0) end
    compare("display list",DL,vEnd)
    compare("matrices and vertices",ARENA,vmAlloc)
    compareState()
    drawn=drawn+1
  end
end
print(("frames %d, draws %d, effects ended %d"):format(frames,drawn,ended))
ok(ended==24,"every effect ran to its end (-1)")
ok(drawn>2000,"the draw builder matched the ROM on "..drawn.." frames")
print(checks.." checks passed (leaf / petal controller vs ROM)")
