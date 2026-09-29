package.path="./?.lua;./?/init.lua;"..package.path
-- A particle is drawn only after its first update (841055D8: the scheduler
-- 84107B68 creates particles before the particle pass 841029DC, which updates
-- them at age 0 and builds their draw; a move route's zero-time births come
-- after that pass and wait for the next tick).
-- The hit sparks of Pound (move 1, impact bank; shape 109, a flat 32-unit
-- quad scaled by its 25/1000 scale curve) were drawn for one tick at scale 1
-- when born: a large white square on every hit that uses them.
local checks=0
local function ok(v,m) checks=checks+1 if not v then error("FAIL "..m,0) end end
local prefix="mods.STADIUM2_IMPORTER.lib."
local Packets=require(prefix.."stadium2_battle_fx_draw_packets")

-- never-updated particles make no draw packet
local pending={id=1,effectId=1,active=true,nativePending=true,position={0,0,0},
  scale={1,1,1},rotation={0,0,0},event={mode=1,flags=0,material={shapeId=109}},
  material={shapeId=109}}
local built=Packets.build({frame=0,particles={pending}},{})
ok(#built.packets==0 and #built.screenPackets==0,"a particle without an update is not drawn")

local file=io.open(os.getenv("STADIUM2_ROM") or "mods/STADIUM2_IMPORTER/baseroms/stadium2.z64","rb")
if not file then
  assert(os.getenv("STADIUM2_REQUIRE_ROM")~="1","ROM required")
  print(checks.." checks passed (battle FX birth update; SKIP ROM part)")
  return
end
local rom=file:read("*a");file:close()
local FxRom=require(prefix.."stadium2_battle_fx_rom")
local Runtime=require(prefix.."stadium2_battle_fx_runtime")
local catalog=assert(FxRom.catalog(rom))
local runtime=Runtime.new({catalog=catalog,rng=function() return 0.5 end})
assert(runtime:trigger({moveId=1,alternate=true,sourceSide="player",targetSide="enemy"}))
local sparks,largest=0,0
for _=1,20 do
  runtime:step(1)
  for _,p in ipairs(runtime:snapshot({shared=true}).particles) do
    local shape=p.event and p.event.material and p.event.material.shapeId
    if tonumber(shape)==109 and p.nativePending~=true then
      sparks=sparks+1
      largest=math.max(largest,tonumber(p.scale and p.scale[1]) or 0)
    end
  end
end
ok(sparks>0,"Pound's hit sparks are drawn")
ok(largest<0.1,("Pound's hit sparks are never drawn at full size (largest scale %.3f)"):format(largest))
print(checks.." checks passed (battle FX birth update)")
