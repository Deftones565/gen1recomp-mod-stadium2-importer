package.path = "./?.lua;./?/init.lua;" .. package.path

local runtimeCall
package.loaded["src.mods.Runtime"]={call=function(name,fallback,ctx)
  runtimeCall={name=name,ctx=ctx}
  return fallback(ctx)
end}
package.loaded["mods.STADIUM2_IMPORTER.lib.battle_scene_extensions"]=nil
package.loaded["mods.STADIUM2_IMPORTER.lib.battle_scene_api"]=nil
local Api = require("mods.STADIUM2_IMPORTER.lib.battle_scene_api")
local Extensions=require("mods.STADIUM2_IMPORTER.lib.battle_scene_extensions")
local checks=0
local function ok(value,message)
  checks=checks+1
  if not value then error("FAIL "..message,0) end
end

local scene={actors={enemy={name="custom"}}}
Api.bind({currentScene=function() return scene end})
ok(Api.current()==scene,"current scene is resolved through battle router")
ok(Api.actor("enemy")==scene.actors.enemy,"active actor lookup")

local registered
local consumer={hooks={wrap=function(_,name,callback,priority)
  registered={name=name,callback=callback,priority=priority}
  return function() registered=nil end
end}}
local callback=function() return "owned" end
local unregister=Api.register(consumer,"environment",callback,77)
ok(registered and registered.name==Api.hooks.environment,
  "named phase maps to stable raw hook")
ok(registered.callback==callback and registered.priority==77,
  "consumer callback and priority pass through unchanged")
unregister()
ok(registered==nil,"consumer receives unregister function")

local capabilities=Api.capabilities()
ok(capabilities.apiVersion==1 and capabilities.phases.battlers,
  "capabilities advertise scene API and phases")
ok(capabilities.battlerModes.host and capabilities.battlerModes.provider
    and capabilities.battlerModes.native,"all battler ownership modes advertised")
ok(not pcall(Api.register,consumer,"missing",callback),
  "unknown phases are rejected")

local pushes,pops=0,0
local ctx={graphics={push=function(mode)
  if mode=="all" then pushes=pushes+1 end
end,pop=function() pops=pops+1 end}}
local marks={player={x=1},enemy={x=2}}
local result=Extensions.environment(ctx,function(received)
  ok(received==ctx,"scene hook fallback receives extension context")
  return marks
end)
ok(runtimeCall.name==Api.hooks.environment and runtimeCall.ctx==ctx and result==marks,
  "extension phase dispatches through the engine hook bus")
ok(pushes==1 and pops==1,"extension callback graphics state is isolated")

print(("%d checks passed (Stadium 2 public scene API)"):format(checks))
