package.path="./?.lua;./?/init.lua;"..package.path

local checks=0
local function ok(value,message)
  checks=checks+1
  if not value then error("FAIL "..message,0) end
end

local goldCalls,gen1Calls=0,0
local Gold={bind=function() goldCalls=goldCalls+1 end,
  configureGame=function() goldCalls=goldCalls+1;return 251 end,
  install=function() goldCalls=goldCalls+1;return true end,
  update=function() return true end,ensure=function() return true end,
  finish=function() return false end,status=function() return {generation=2} end}
local Gen1={bind=function() gen1Calls=gen1Calls+1 end,
  configureGame=function() gen1Calls=gen1Calls+1;return 151 end,
  install=function() gen1Calls=gen1Calls+1;return false end,
  update=function() return false end,ensure=function() return false end,
  finish=function() return false end,status=function() return {generation=1,enabled=false} end}
package.loaded["mods.STADIUM2_IMPORTER.lib.gen2_battle"]=Gold
package.loaded["mods.STADIUM2_IMPORTER.lib.gen1_battle"]=Gen1
package.loaded["mods.STADIUM2_IMPORTER.lib.battle_router"]=nil

local Router=require("mods.STADIUM2_IMPORTER.lib.battle_router")
Router.bind({})
ok(Router.update(1/60)==false and gen1Calls==0 and goldCalls==0,
  "presentation ticks before game.ready load neither implementation")
ok(Router.configureGame({data={type_chart={generation=2}}})==251,
  "Gold selects the owned Gen 2 scene")
ok(Router.install(),"Gold scene installs")
ok(goldCalls==3,"Gold implementation receives bind, configure and install")
ok(gen1Calls==0,"Gold never initializes the Gen 1 implementation")
ok(Router.status().generation==2,"Gold status comes from owned scene")

Router.resetForTests()
Router.bind({})
ok(Router.configureGame({data={type_chart={generation=1}}})==151,
  "Gen 1 selects the disabled implementation")
ok(Router.install()==false,"Gen 1 battle install is a no-op")
ok(Router.ensure({})==false and Router.update(1/60)==false,
  "Gen 1 battle runtime stays inactive")
ok(Router.status().generation==1 and Router.status().enabled==false,
  "Gen 1 reports disabled battle integration")

print(("%d checks passed (Stadium 2 generation router)"):format(checks))
