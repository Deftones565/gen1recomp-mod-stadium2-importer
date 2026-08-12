local Importer = require("mods.STADIUM2_IMPORTER.lib.importer")

local Gen1 = {}

function Gen1.bind()
  return Gen1
end

function Gen1.configureGame(game)
  local pokemon = game and game.data and game.data.pokemon
  local maxDex = 151
  if type(pokemon) == "table" then
    for _, def in pairs(pokemon) do
      if type(def) == "table" then
        local dex = tonumber(def.dex or def.index)
        if dex and dex > maxDex and dex <= 251 then maxDex = math.floor(dex) end
      end
    end
  end
  Importer.configure({count=maxDex})
  return maxDex
end

function Gen1.install()
  return false
end

function Gen1.update()
  return false
end

function Gen1.ensure()
  return false
end

function Gen1.finish()
  return false
end

function Gen1.status()
  return {enabled=false,ready=false,active=false,generation=1}
end

function Gen1.enabled()
  return false
end

function Gen1.ready()
  return false
end

function Gen1.resetForTests()
  return true
end

return Gen1
