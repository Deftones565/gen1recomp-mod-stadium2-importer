package.path="./?.lua;./?/init.lua;"..package.path
-- Stadium 2 portrait camera records from the ROM (func_84113014): the data
-- the embedded Stadium-2-UI's live 3D portraits read through
-- lib/stadium_portrait_data.lua.
local path=os.getenv("STADIUM2_ROM") or arg[1]
  or (io.open("mods/STADIUM2_IMPORTER/baseroms/stadium2.z64","rb")
    and "mods/STADIUM2_IMPORTER/baseroms/stadium2.z64")
local f=path and io.open(path,"rb")
if not f then
  assert(os.getenv("STADIUM2_REQUIRE_ROM")~="1","required Stadium 2 ROM unavailable")
  print("SKIP: Stadium portrait data ROM test (ROM unavailable)")
  return
end
local Rom=require("mods.STADIUM2_IMPORTER.lib.rom")
local Data=require("mods.STADIUM2_IMPORTER.lib.stadium_portrait_data")
local rom=assert(Rom.normalise(f:read("*a")))
f:close()
local checks=0
local function ok(v,m) checks=checks+1 if not v then error("FAIL "..m,0) end end

local loaded=assert(Data.fromRom(rom))
-- 32 bytes per species from 0x49B780 + 0x5730; the table itself starts at
-- 0x4A0EB0; the opponent's mirrors x and yaw unless the record names an
-- authored alternative (Pikachu's 0x188).
local function near(a,b) return math.abs(a-b)<1e-4 end
local pika=assert(Data.portraitRecord(loaded,25,false))
ok(pika.pitch==694 and pika.yaw==-5422 and pika.distance==74 and near(pika.x,1.3)
  and pika.y==15 and pika.frame==10 and pika.alt==0x188,"Pikachu's portrait record")
local pikaFoe=assert(Data.portraitRecord(loaded,25,true))
ok(pikaFoe.pitch==100 and pikaFoe.yaw==5882 and near(pikaFoe.x,-1.2),"the opponent's Pikachu uses the alternative record")
local bulba,bulbaFoe=Data.portraitRecord(loaded,1,false),Data.portraitRecord(loaded,1,true)
ok(bulba.yaw==-6664 and bulbaFoe.yaw==6664 and near(bulbaFoe.x,-bulba.x) and bulbaFoe.y==bulba.y,
  "an opponent without an alternative is mirrored")
ok(Data.portraitRecord(loaded,251,false).distance==108,"Celebi's record is inside the table")
ok(Data.portraitRecord(loaded,0,false)==nil and Data.portraitRecord(nil,25,false)==nil,"no record without data")

print(checks.." checks passed (Stadium portrait data from the ROM)")
