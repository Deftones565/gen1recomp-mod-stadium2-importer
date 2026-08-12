package.path="./?.lua;./?/init.lua;"..package.path

local Battle=require("mods.STADIUM2_IMPORTER.lib.gen1_battle")
local checks=0
local function ok(value,message)
  checks=checks+1
  if not value then error("FAIL "..message,0) end
end

ok(Battle.bind({})==Battle,"Gen 1 implementation binds without side effects")
ok(Battle.configureGame({})==151,"Gen 1 keeps the normal 151-species boundary")
ok(Battle.configureGame({data={pokemon={extra={dex=251}}}})==251,
  "Gen 1 model importing can still expand to 251 species")
ok(Battle.install()==false,"Gen 1 installs no battle hooks")
ok(Battle.update(1/60)==false,"Gen 1 has no battle presentation tick")
ok(Battle.ensure({})==false,"Gen 1 never claims a battle")
ok(Battle.finish({})==false,"Gen 1 finish is a no-op")
ok(Battle.enabled()==false and Battle.ready()==false,"Gen 1 battle integration stays disabled")
local status=Battle.status()
ok(status.generation==1 and status.enabled==false and status.active==false,
  "Gen 1 status reports an inactive implementation")

print(("%d checks passed (Stadium 2 Gen 1 battle no-op)"):format(checks))
