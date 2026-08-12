package.path="./?.lua;./?/init.lua;"..package.path

local requested,configuredOptions
local Importer={
  configure=function(options) configuredOptions=options;requested=options and options.count end,
  modelsEnabled=function() return true end,battleEnabled=function() return true end,
  available=function() return true end,
}
package.loaded["mods.STADIUM2_IMPORTER.lib.importer"]=Importer
package.loaded["mods.STADIUM2_IMPORTER.lib.gen2_battle"]=nil

local Gen2=require("mods.STADIUM2_IMPORTER.lib.gen2_battle")
local normal={{1,2,3},{4,5,6}}
local shiny={{7,8,9},{10,11,12}}
local count=Gen2.configureGame({data={pokemon={
  BULBASAUR={dex=1},CYNDAQUIL={dex=155},SENTRET={dex=161},CELEBI={dex=251},
  UNOWN={dex=201},
},gen2Palettes={pokemon={UNOWN={normal=normal,shiny=shiny}}}}})
assert(count==251,"Gen 2 adapter did not discover all 251 species")
assert(requested==251,"Gen 2 adapter left the importer at its Gen 1 boundary")
assert(Gen2.status().count==251,"Gen 2 status reports the wrong configured range")
assert(configuredOptions.palettePairs[201].normal==normal
  and configuredOptions.palettePairs[201].shiny==shiny,
  "namespaced Gen 2 normal/shiny palettes were not handed to the form extractor")

print("4 checks passed (Stadium 2 Gen 2 importer configuration)")
