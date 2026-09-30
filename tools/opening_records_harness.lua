io.stdout:setvbuf("no")
-- Oracle harness: Stadium 2's record loop, text system, HP bars and actor
-- states running together in the MIPS VM over the battle opening, to see
-- when the second 0x22 record plays. Run from /opt/git/gen1recomp.
package.path="./?.lua;./?/init.lua;"..package.path
local f=io.open("mods/STADIUM2_IMPORTER/baseroms/stadium2.z64","rb");local rom=f:read("*a");f:close()
local VM=require("mods.STADIUM2_IMPORTER.tests.support.stadium2_battle_fx_mips")
local FxRom=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_rom")
local fragment=assert(FxRom.catalog(rom)).lifecycleAssets.fragment79
local TRACE=os.getenv("TRACE")
local A0,A1,C0,C1=0x85001000,0x85002000,0x85000000,0x85000100
local VIEW0,VIEW1=0x84190428,0x841910E0
local frame=0
LINES={[0]=tonumber(os.getenv("LINES0") or 1),[1]=tonumber(os.getenv("LINES1") or 2)}
currentSide=0
local entranceFrames={[A0]=tonumber(os.getenv("PLAYER_ANIM") or 45),[A1]=tonumber(os.getenv("FOE_ANIM") or 45)}
local animStart={}
local function stub(v) v.r[2]=0 end
local hooks={
  [0x8411DD8C]=function(v) local a=v.r[4]%4294967296 v:putVector(v.r[5],{v:float(a+0x24),v:float(a+0x28)+40,v:float(a+0x2C)}) end,
  -- model animation: 84112158(actor, anim) starts one; 8003EC34 answers
  -- finished after the entrance length for 0xFC, at once otherwise
  [0x84112158]=function(v) local a,anim=v.r[4]%4294967296,v.r[5]%65536 animStart[a]={frame=frame,anim=anim} v.r[2]=0 end,
  [0x8003EC34]=function(v) local a=v.r[4]%4294967296 local s=animStart[a]
    if s and s.anim==0xFC then v.r[2]=(frame-s.frame>=(entranceFrames[a] or 45)) and 1 or 0 else v.r[2]=1 end end,
  [0x841120AC]=stub,[0x84111C1C]=stub,[0x8410890C]=stub,[0x8006456C]=stub,[0x80023A3C]=stub,
  [0x80024480]=stub,[0x84108A10]=stub,[0x84108E00]=stub,[0x84147228]=stub,
  -- the message system: 8004C874(table, id) gives the string, 800472E0 its
  -- line count (the record's text time is 0x1E + 10 * lines, 84135A2C),
  -- 8004C8A0 formats it into the record (not needed here)
  [0x8004C874]=function(v) v.r[2]=0x85200000 end,
  [0x800472E0]=function(v) v.r[2]=LINES[currentSide] or 1 end,
  [0x8004C8A0]=stub,[0x84134994]=stub, -- "MVED": presentation done, to the battle engine
}
for k,v in pairs(loadfile(os.getenv("HOOKS") or "/dev/null") and (loadfile(os.getenv("HOOKS"))() or {}) or {}) do hooks[k]=v end
local zeros=string.rep("\0",0x80400000-0x800A7400)
local vm=VM.new({{base=0x80000400,bytes=rom:sub(0x1001,0xA8000)},{base=0x84100000,bytes=fragment},
  {base=0x800A7400,bytes=zeros}},hooks)
local function w(a,v,n) vm:write(a,v,n) end
-- the record ring and its indices (D_84195280, 0x1E records of 0x280, read
-- +0x4D80 / write +0x4D81), the current record and the text / gate globals
-- start cleared, as at the battle's start
for a=0x84195280,0x8419A010 do vm.memory[a]=0 end
-- globals
w(0x84193DD0,0x84199D80,4)
w(0x84191208,A0,4);w(0x8419120C,A1,4)
w(0x841911E0,C0,4);w(0x841911E4,C1,4);w(C0,VIEW0,4);w(C1,VIEW1,4)
for _,a in ipairs({A0,A1}) do
  w(a+0x1A,a==A0 and 1 or 4,2); w(a+0x658,a==A0 and 1 or 4,2)
  vm:putFloat(a+0x24,a==A0 and -150 or 150); vm:putFloat(a+0x2C,0)
  w(a+0x20,a==A0 and 0x4000 or 0xC000,2)
  vm:putFloat(a+0x64C,1); vm:putFloat(a+0x640,40)
  w(a+0x2D4,0x85004000,4)
  -- the model: +0xC -> +0x2C, a function returning the animation header
  w(a+0xC,0x85006000,4)
end
w(0x8500602C,0x85006100,4)
hooks[0x85006100]=function(v) v.r[2]=0x85006200 end
-- battle mons (D_84195200[side]), party entries (D_841951F8[side]), volatiles
local MON,PARTY,VOL,BATTLE={0x85100000,0x85100100},{0x85100200,0x85100300},{0x85100400,0x85100500},0x85101000
for s=0,1 do
  w(0x84195200+s*4,MON[s+1],4);w(0x841951F8+s*4,PARTY[s+1],4);w(0x84195208+s*4,VOL[s+1],4)
  w(MON[s+1]+0x26,30,2);w(MON[s+1]+0x28,30,2);w(PARTY[s+1]+0xA,12,1);w(PARTY[s+1]+0x3,12,1)
end
w(0x841951F0,BATTLE,4);w(BATTLE+0x9C7,1,1)
-- the two send-out records as 8413425C builds them (84136A9C mode 4, then
-- 84133714's 0x22 branch: 84134CBC, 84135B00(0x16), 84136CA8)
local function call(fn,args,label)
  local before,t0=vm.steps,os.clock()
  local ok,err=pcall(vm.call,vm,fn,args,tonumber(os.getenv("STEPS") or 200000))
  if os.getenv("VERBOSE") then print(("-> %s %d steps %.2fs"):format(label,vm.steps-before,os.clock()-t0)) end
  if not ok then error(("%s (%08X): %s"):format(label or "call",fn,tostring(err)),0) end
  return err
end
for s=0,1 do
  currentSide=s
  call(0x84136A9C,{s,0xFFFFFFFF,12,4},"hp fill "..s)
  call(0x84134CBC,{s,0x22},"queue 0x22 "..s)
  call(0x84135B00,{0x16},"text 0x16 "..s)
  call(0x84136CA8,{},"commit "..s)
end
print(("records queued: read %d write %d"):format(vm:byte(0x84195280+0x4D80),vm:byte(0x84195280+0x4D81)))
w(0x84195278,2,1)
local last=""
for f=1,tonumber(os.getenv("FRAMES") or 600) do
  frame=f
  call(0x8411DA4C,{},"anim update")
  call(0x841359D0,{},"record loop")
  call(0x84137778,{},"text")
  call(0x84136D9C,{},"hp bars")
  local rec=0x84199D80
  local line=("rd %d code %X side %d new %d | A0 sub %d slot0 %08X | text4 %d FFC %d | hp %d %d"):format(
    vm:byte(0x84195280+0x4D80),vm:read(rec+4,2),vm:byte(rec),vm:byte(rec+2),vm:byte(A0+0x7F6),vm:read(A0+0x5C8,4),
    vm:byte(0x8419A004),vm:read(0x84199FFC,2),vm:read(rec+0x36,2),vm:read(rec+0x4E,2))
  if line~=last or TRACE then print(("f%04d timer %4d %s"):format(f,vm:read(rec+6,2),line)); last=line end
end
