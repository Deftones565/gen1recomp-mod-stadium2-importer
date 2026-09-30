package.path="./?.lua;./?/init.lua;"..package.path
-- Surf's water (family 7) ported to Lua against the ROM in the MIPS VM on
-- identical memory: 8415A9E4 (init), 8415AD58 (update: 8415A364), 8415AC64
-- and the draw builder 8415ADE0 (with 84159D30, 84159FA8, 80070BA4,
-- 80070C14, 8000B3B0 and libultra). Only the host boundaries are hooked
-- (841094EC, 80006DEC), the same on both sides; __sinf, __cosf, the vector
-- helpers, atan2 and guScale run from the ROM. Every byte of the grid
-- state, the scrolls, the display list and the allocations must match on
-- every frame, with a moving camera that crosses the water.
local file=io.open(os.getenv("STADIUM2_ROM") or "mods/STADIUM2_IMPORTER/baseroms/stadium2.z64","rb")
if not file then assert(os.getenv("STADIUM2_REQUIRE_ROM")~="1","ROM required");print("SKIP terrain grid native ROM");return end
local rom=file:read("*a");file:close()
local prefix="mods.STADIUM2_IMPORTER.lib."
local VM=require("mods.STADIUM2_IMPORTER.tests.support.stadium2_battle_fx_mips")
local FxRom=require(prefix.."stadium2_battle_fx_rom")
local Memory=require(prefix.."stadium2_native_memory")
local W=require(prefix.."stadium2_battle_fx_terrain_grid_native")
local checks=0
local function ok(v,m) checks=checks+1 if not v then error("FAIL "..m,0) end end

local fragment=assert(FxRom.catalog(rom)).lifecycleAssets.fragment79
local main=rom:sub(0x1001,0xA8000)
local CAM,DL,ARENA=0x85100000,0x85400000,0x85200000
math.randomseed(4711)

local frames,covers,drawn,ended=0,0,0,0
for run=1,8 do
  local side=run%2==0 and 1 or -1
  local count=run<=2 and math.random(1,40) or 0
  local signal=0
  local st={vm=ARENA,lua=ARENA}
  local vm=VM.new({{base=0x84100000,bytes=fragment},{base=0x80000400,bytes=main}},{
    [0x841094EC]=function(v) v.r[2]=signal end,
    [0x80006DEC]=function(v) v.r[2]=st.vm;st.vm=st.vm+v.r[4] end,
  })
  local mem=Memory.new({{base=0x84100000,bytes=fragment},{base=0x80000400,bytes=main}})
  local cb={signal=function() return signal end,
    alloc=function(n) local a=st.lua;st.lua=st.lua+n;return a end}
  local function camera(t)
    -- a camera sweeping over the water and down through its surface
    local eye={math.sin(t*0.05)*900,120+math.cos(t*0.07)*200,900+math.cos(t*0.03)*400}
    local at={math.sin(t*0.02)*200,math.random()*40,0}
    for _,m in ipairs({vm,mem}) do
      m:write(W.CAMERA_POINTER,CAM,4)
      local put=m==vm and function(a,x) vm:putFloat(a,x) end or function(a,x) mem:setF32(a,x) end
      for k=1,3 do put(CAM+0xA8+(k-1)*4,eye[k]);put(CAM+0xB4+(k-1)*4,at[k]) end
      put(CAM+0xC0,0);put(CAM+0xC4,1);put(CAM+0xC8,0)
      put(CAM+0x2C,30+(t%7)*5);put(CAM+0x30,4/3);put(CAM+0x34,20)
    end
  end
  local function compare(label)
    local function range(tag,lo,hi)
      for a=lo,hi-1 do
        if vm:byte(a)~=mem:u8(a) then
          error(("FAIL run %d %s %s byte %08X ROM %02X Lua %02X"):format(run,label,tag,a,vm:byte(a),mem:u8(a)),0)
        end
      end
    end
    local s=vm:read(W.STATE_POINTER,4)
    range("state",s,s+W.GRID+256*W.VERTEX)
    range("scrolls",0x841A4D60,0x841A4D66)
    return range
  end
  camera(0)
  vm:call(0x8415A9E4,{side%2^32,count,0x4650});W.init(mem,cb,side,count)
  compare("init")
  -- runs 7 and 8: a short effect, to reach the end (-1)
  if run>=7 then
    local at=vm:read(W.STATE_POINTER,4)+8
    local d=math.random(70,160)
    vm:write(at,d,2);mem:setU16(at,d)
  end
  if count>0 then
    local f=vm:read(W.CORNERS_POINTER,4)
    compare("init")("camera frame",f,f+0x24)
  end
  for frame=1,400 do
    frames=frames+1
    if frame==120 and run<7 then signal=1 end
    camera(frame)
    local rv=vm:call(0x8415AD58,{});rv=rv>=2^31 and rv-2^32 or rv
    local rl=W.update(mem,cb)
    ok(rv==rl,("update result run %d frame %d ROM %d Lua %d"):format(run,frame,rv,rl))
    compare("frame "..frame)
    if rv==-1 then ended=ended+1 break end
    st.vm,st.lua=ARENA,ARENA
    local vEnd=vm:call(0x8415ADE0,{DL},2000000)%4294967296
    local lEnd=W.draw(mem,cb,DL)
    if vEnd~=lEnd then error(("FAIL run %d frame %d draw end ROM %08X Lua %08X"):format(run,frame,vEnd,lEnd),0) end
    local range=compare("draw "..frame)
    range("display list",DL,vEnd)
    range("allocations",ARENA,st.vm)
    if st.vm-ARENA>0x1000 then covers=covers+1 end
    local f=vm:read(W.CORNERS_POINTER,4)
    range("camera frame",f,f+0x24)
    drawn=drawn+1
  end
end
print(("frames %d, draws %d, with the cover %d"):format(frames,drawn,covers))
ok(ended==2,"the short effects ended (-1)")
ok(covers>20 and covers<drawn,"the cover was drawn on some frames and not others")
print(checks.." checks passed (Surf water vs ROM)")
