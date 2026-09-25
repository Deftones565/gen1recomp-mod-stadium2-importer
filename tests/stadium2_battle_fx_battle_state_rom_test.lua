local prefix='mods.STADIUM2_IMPORTER.lib.'
local State=require(prefix..'stadium2_battle_fx_battle_state')
local Rom=require(prefix..'stadium2_battle_fx_rom')
local VM=require(prefix..'stadium2_battle_fx_mips')
local Material=require(prefix..'stadium2_battle_fx_material')
local Player=require(prefix..'stadium2_battle_fx_player')
local file=io.open(os.getenv('STADIUM2_ROM') or 'mods/STADIUM2_IMPORTER/baseroms/stadium2.z64','rb')
if not file then assert(os.getenv('STADIUM2_REQUIRE_ROM')~='1');print('SKIP battle-state ROM');return end
local rom=file:read('*a');file:close()
local catalog=assert(Rom.catalog(rom))
local images={{base=0x84100000,bytes=catalog.lifecycleAssets.fragment79},
  {base=0x80000400,bytes=rom:sub(0x1001,0xA8000)},
  {base=0x81100000,bytes=rom:sub(0x165C51,0x165F00)}}
local vm=VM.new(images,{[0x8411E1F8]=function(v)v.r[2]=0 end})
local actor,tableAddress=0x85000000,0x85001000
vm:write(0x84190194,actor,4);vm:write(0x84190198,actor,4)
vm:write(0x84193DD0,tableAddress,4);vm:write(0x84190170,0,4)
local cases=0
local function compare(id,input)
  vm:write(0x8416A214,id,2);vm:write(0x8416A210,9,4)
  vm:write(actor+0x1A,input.ownerSpecies or 0,2)
  vm:write(tableAddress+9,input.resultFlags or 0,1)
  vm:write(tableAddress+0x10,input.sourceStatus or 0,2)
  vm:write(tableAddress+0x14,input.ownerStatusPattern or 0,2)
  vm:call(0x841083B0,{})
  assert(State.condition(id,input,9)==vm:read(0x8416A210,4),'condition '..id)
  cases=cases+1
end
for species=1,251 do
  for _,id in ipairs({10,15,22,154,163,206,210,211,231,232}) do
    compare(id,{ownerSpecies=species})
  end
end
for id=0,300 do compare(id,{ownerSpecies=52,resultFlags=0,sourceStatus=0,ownerStatusPattern=0}) end
for flags=0,255 do
  compare(168,{resultFlags=flags});compare(217,{resultFlags=flags})
  for _,status in ipairs({0,1,7,8,255}) do compare(173,{resultFlags=flags,sourceStatus=status}) end
end
for _,id in ipairs({274,290,292,298,299}) do
  for _,status in ipairs({0,0x2AAA,0x3AAA,0xAAAA,0xFFFF}) do compare(id,{ownerStatusPattern=status}) end
end
assert(State.condition(10,{})==nil and State.condition(173,{sourceStatus=1})==nil)

-- Global alpha gate versus actual 84101D54 with a retail gated material.
local emitter
for _,program in pairs(catalog.programs) do for _,r in ipairs(program.records) do
  local e=r.emitter
  if e and e.flags2 and math.floor(e.flags2/4)%2==1 and e.material and e.material.nativeAlphaRamp then emitter=e end
end end
assert(emitter)
local m=emitter.material
vm=VM.new(images)
local p,d,t=0x85000000,0x85001000,0x85002000
vm:write(d+4,0,4);vm:write(d+16,t,4);vm:write(d+20,m.address,4)
vm:write(p+16,d,4);vm:write(p+0x14,0x80000,4);vm:write(p+0x92,1,1)
vm:write(p+0x87,255,1)
vm:call(0x84106F34,{p,d})
local gate=0
local mat=Material.init(m,{flags2=4,resolveNativeAlphaGate=function()return gate end})
for tick=1,30 do
  gate=tick>=5 and 1 or 0
  vm:write(0x841901A4,gate,4);vm:write(p+0x7F,tick,1)
  vm:call(0x84101D54,{p})
  mat=Material.step(mat,{age=tick})
  assert(mat.nativeAlpha==vm:read(p+0x87,1),('global alpha at %d: Lua %s ROM %s flags %X material %X track %s'):format(tick,mat.nativeAlpha,vm:read(p+0x87,1),vm:read(p+0x14,4),m.address,tostring(m.nativePrimaryTrack)))
end
local player=Player.new({catalog=catalog})
assert(player.signals.global==0)
player:signalContext(299);assert(player.signals.global==0)
player:signalContext(300);assert(player.signals.global==1)
player:release()
-- The newly decoded base controller is shared by many materials. Compare
-- every distinct retail material/alpha-gate combination against the ROM.
local bit=require('bit')
local seen,materials={},0
for _,program in pairs(catalog.programs) do for _,record in ipairs(program.records) do
  local e=record.emitter
  local material=e and e.material
  if material and material.nativeAlphaBaseRamp then
    local flags=bit.band(e.flags or 0,0x40001A12)
    local flags2=bit.band(e.flags2 or 0,4)
    local key=material.address..':'..flags..':'..flags2
    if not seen[key] then
      seen[key]=true;materials=materials+1
      local v=VM.new(images,{[0x841094EC]=function(machine)machine.r[2]=1 end})
      v:write(d+4,flags,4);v:write(d+16,t,4);v:write(d+20,material.address,4)
      v:write(p+16,d,4);v:write(p+0x92,1,1);v:write(p+0x87,255,1)
      v:write(p+0x14,(flags2~=0 and 0x80000 or 0)+(bit.band(flags,16)~=0 and 1 or 0),4)
      v:call(0x84106F34,{p,d})
      local s=Material.init(material,{flags=flags,flags2=flags2,
        nativeAlphaGlobalGate=0,nativeAlphaSignal=1})
      for age=1,32 do
        local global=age>=8 and 1 or 0
        v:write(0x841901A4,global,4);v:write(p+0x7F,age,1)
        v:call(0x84101D54,{p})
        s=Material.step(s,{age=age,nativeAlphaGlobalGate=global})
        assert(s.nativeAlpha==v:read(p+0x87,1),
          ('material %X flags %X/%X age %d: %s/%s'):format(material.address,flags,flags2,age,s.nativeAlpha,v:read(p+0x87,1)))
      end
    end
  end
end end
print(('Alpha ROM: %d distinct retail material/gate combinations, 32 ticks each passed'):format(materials))
print(('Battle-state ROM: %d branch cases, live alpha gate and context-300 latch passed'):format(cases))
