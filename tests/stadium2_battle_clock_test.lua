package.path = "./?.lua;./?/init.lua;" .. package.path

local checks = 0
local function ok(value, message)
  checks = checks + 1
  if not value then error("FAIL " .. message, 0) end
end

local importerSteps = 0
local Importer = {
  bind=function() end, step=function() importerSteps = importerSteps + 1 end,
  appendRow=function() end, configure=function() end, status=function() end,
  available=function() end, modelsEnabled=function() return true end,
  battleEnabled=function() return true end, autoImport=function() end,
  beginFrom=function() end, beginPath=function() end, request=function() end,
  modelPath=function() end, readPack=function() end, parsePack=function() end,
  loadModel=function() end, newRenderer=function() end, releaseModels=function() end,
  readHandlers=function() end, handlerInfo=function() end, evaluateHandler=function() end,
  runHandlers=function() end, runModelHandlers=function() end, resolveHandlerPointer=function() end,
  shinyPalettesFromTransformSource=function() end, US_MD5="md5", FORMAT="format",
}
local battleUpdates = {}
local Battle = {
  bind=function() end, install=function() end, configureGame=function() end,
  status=function() end, ensure=function() end, finish=function() end,
  update=function(dt) battleUpdates[#battleUpdates + 1] = dt end,
}
package.loaded["mods.STADIUM2_IMPORTER.lib.importer"] = Importer
package.loaded["mods.STADIUM2_IMPORTER.lib.battle_router"] = Battle

local pipeline, inputWrap
local mod = {
  options={ define=function() end }, exports={},
  content={ render_pipelines={ register=function(_, id, def)
    ok(id == "stadium2_battle_clock", "internal pipeline id")
    pipeline = def
  end } },
  hooks={ wrap=function(_, name, fn)
    if name == "input.step" then inputWrap = fn end
  end },
  events={ on=function() end },
}

local install = assert(loadfile("mods/STADIUM2_IMPORTER/main.lua"))()
install(mod)
ok(type(pipeline) == "table" and type(pipeline.update) == "function",
  "real-time battle pipeline registered")
ok(#pipeline.levels == 1 and pipeline.levels[1] == "OFF",
  "clock pipeline cannot become a visible render pass")

for _ = 1, 8 do inputWrap(function() end, {}, 1 / 60) end
ok(importerSteps == 8, "cache builder remains on fixed logic steps")
ok(#battleUpdates == 0, "speed-scaled logic steps never advance battle animation")

pipeline.update(1 / 60)
ok(#battleUpdates == 1 and battleUpdates[1] == 1 / 60,
  "one presentation update advances the battle exactly once")

print(("%d checks passed (Stadium 2 real-time battle clock)"):format(checks))
