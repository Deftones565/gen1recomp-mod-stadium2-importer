package.path="./?.lua;./?/init.lua;"..package.path
-- Meditate's battler behaviour (84114804 kind 0x0D for move 0x60): start
-- 84122A78 and update 84122AB8 run in the MIPS VM on an actor with scale
-- 1.0, against Special's kind 13 port tick by tick: the scale vector
-- (+0x30/+0x34/+0x38) and the state (+0x5FC, +0x5FE, +0x600, +0x60C, +0x624).
local file=io.open(os.getenv("STADIUM2_ROM") or "mods/STADIUM2_IMPORTER/baseroms/stadium2.z64","rb")
if not file then assert(os.getenv("STADIUM2_REQUIRE_ROM")~="1","ROM required");print("SKIP Meditate ROM");return end
local rom=file:read("*a");file:close()
local VM=require("mods.STADIUM2_IMPORTER.tests.support.stadium2_battle_fx_mips")
local FxRom=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_rom")
local Special=require("mods.STADIUM2_IMPORTER.lib.battle_special_moves")
local checks=0
local function ok(v,m) checks=checks+1 if not v then error("FAIL "..m,0) end end

local catalog=assert(FxRom.catalog(rom))
local fragment=catalog.lifecycleAssets.fragment79
local A=0x85001000
local vm=VM.new({{base=0x80000400,bytes=rom:sub(0x1001,0xA8000)},{base=0x84100000,bytes=fragment}},{})
for i=0,2 do vm:putFloat(A+0x30+i*4,1.0) end

ok(Special.KINDS[96]==Special.MEDITATE,"Meditate (96) runs kind 13")
local state=assert(Special.new({kind=Special.MEDITATE,trig=catalog.trigTables}))
vm:call(0x84122A78,{A})
local ended,peak=nil,0
for tick=1,240 do
  vm:call(0x84122AB8,{A})
  Special.step(state)
  local m=state.meditate
  for axis=1,3 do
    local rom_=vm:float(A+0x2C+axis*4)
    if rom_~=state.axisScale[axis] then
      error(("FAIL tick %d axis %d scale ROM %.9g Lua %.9g"):format(tick,axis,rom_,state.axisScale[axis]),0)
    end
  end
  local function s16(v) return v>=0x8000 and v-0x10000 or v end
  if s16(vm:read(A+0x5FC,2))~=m.speedPhase or s16(vm:read(A+0x5FE,2))~=m.phase
      or s16(vm:read(A+0x600,2))~=m.speed or vm:float(A+0x60C)~=m.amplitude
      or vm:byte(A+0x624)~=m.stage then
    error(("FAIL tick %d state ROM %d %d %d %.6g %d Lua %d %d %d %.6g %d"):format(tick,
      s16(vm:read(A+0x5FC,2)),s16(vm:read(A+0x5FE,2)),s16(vm:read(A+0x600,2)),vm:float(A+0x60C),vm:byte(A+0x624),
      m.speedPhase,m.phase,m.speed,m.amplitude,m.stage),0)
  end
  peak=math.max(peak,state.axisScale[2])
  if not ended and m.amplitude<=Special.MEDITATE_SMALL then ended=tick end
end
ok(true,"84122A78 / 84122AB8 match the ROM over 240 ticks")
ok(peak>1.3,("the battler stretches up to %.2f x its height"):format(peak))
ok(ended and state.axisScale[1]==1 and state.axisScale[2]==1,"the wobble decays back to the base scale (tick "..tostring(ended)..")")
print(checks.." checks passed (Meditate kind 13 vs ROM)")
