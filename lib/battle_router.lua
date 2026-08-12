local Router = {}

local modRef, implementation, gameRef

local function generation(game)
  local chart = game and game.data and game.data.type_chart
  local value = tonumber(chart and chart.generation)
  if value then return value end
  local ok, Version = pcall(require, "src.core.GameVersion")
  if ok and Version and Version.generation then
    local got = tonumber(Version.generation())
    if got then return got end
  end
  return 1
end

local function choose(game)
  if implementation then return implementation end
  if generation(game or gameRef) == 2 then
    implementation = require("mods.STADIUM2_IMPORTER.lib.gen2_battle")
  else
    implementation = require("mods.STADIUM2_IMPORTER.lib.gen1_battle")
  end
  if implementation.bind then implementation.bind(modRef) end
  return implementation
end

function Router.bind(mod)
  modRef = mod
  return Router
end

function Router.configureGame(game)
  gameRef = game
  return choose(game).configureGame(game)
end

function Router.install()
  if not gameRef then return false end
  return choose(gameRef).install()
end

function Router.update(dt)
  return implementation and implementation.update(dt) or false
end

function Router.ensure(battle)
  return implementation and implementation.ensure(battle) or false
end

function Router.finish(...)
  if implementation then return implementation.finish(...) end
  return false
end

function Router.status()
  return implementation and implementation.status()
    or {enabled=false,ready=false,active=false}
end

function Router.enabled()
  local impl = implementation
  return impl and impl.enabled and impl.enabled() or false
end

function Router.ready()
  local impl = implementation
  return impl and impl.ready and impl.ready() or false
end

function Router.resetForTests()
  if implementation and implementation.resetForTests then
    pcall(implementation.resetForTests)
  end
  implementation, gameRef, modRef = nil, nil, nil
end

return Router
