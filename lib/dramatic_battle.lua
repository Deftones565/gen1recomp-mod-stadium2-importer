local Importer = require("mods.STADIUM2_IMPORTER.lib.importer")

local Battle = { COUNT = 251 }

local modRef
local V
local modules = {}
local dataFiles = {}
local installed = false
local configured = 151
local generation = 1
local gen2

local SHINY_ATTACK = { [2]=true, [3]=true, [6]=true, [7]=true,
  [10]=true, [11]=true, [14]=true, [15]=true }

local function isShiny(mon)
  local d = mon and mon.dvs
  return d and d.defense == 10 and d.speed == 10 and d.special == 10
    and SHINY_ATTACK[d.attack] == true or false
end

local function dexFor(battle, battler)
  local mon = battler and battler.mon
  local data = battle and battle.data
  local def = mon and data and data.pokemon and data.pokemon[mon.species]
  local dex = def and tonumber(def.dex or def.index)
  if not dex and type(mon and mon.species) == "number" then dex = mon.species end
  dex = dex and math.floor(dex) or nil
  if not dex or dex < 1 or dex > Battle.COUNT then return nil end
  return dex
end

local function sourceFor(rel)
  if not modRef then return nil end
  if modRef.read then
    local ok, source = pcall(modRef.read, modRef, "vendor/dramatic_shape/" .. rel)
    if ok and type(source) == "string" then return source end
  end
  local base = modRef.path and (modRef.path .. "/vendor/dramatic_shape/" .. rel)
  if base then
    local file = io and io.open and io.open(base, "rb") or nil
    if file then
      local source = file:read("*a")
      file:close()
      return source
    end
  end
  return nil
end

local function chunkFor(rel)
  local source = sourceFor(rel)
  if not source then
    error(("STADIUM2_IMPORTER: vendored Dramatic Shape file missing: %s"):format(rel), 0)
  end
  if source:sub(1, 3) == "\239\187\191" then source = source:sub(4) end
  local chunk, err = load(source, "@" .. tostring(modRef.path or "STADIUM2_IMPORTER") .. "/vendor/dramatic_shape/" .. rel)
  if not chunk then error(tostring(err), 0) end
  return chunk
end

local function ready()
  return Importer.modelsEnabled() and Importer.battleEnabled()
    and Importer.available(configured)
end

local battleSetting = {
  get = function() return ready() and "stadiumB" or false end,
  read = function() return ready() and 4 or 5 end,
  level = function() return ready() and 3 or 4 end,
}

local offSetting = {
  get = function() return false end,
  read = function() return 1 end,
  level = function() return 0 end,
}

local VR = {
  enabled = function() return false end,
  active = function() return false end,
}

local function makeNamespace()
  V = { mod = modRef, path = modRef and modRef.path, importer = Importer }

  function V.require(name)
    if name == "VR" then return VR end
    local hit = modules[name]
    if hit ~= nil then return hit end
    local value = chunkFor("lib/" .. name .. ".lua")(V)
    modules[name] = value
    return value
  end

  function V.data(name)
    local hit = dataFiles[name]
    if hit ~= nil then return hit end
    local value = chunkFor("data/" .. name .. ".lua")(V)
    dataFiles[name] = value
    return value
  end
end

local function overworldBattle()
  if not V then return nil end
  local mode = V.require("OverworldBattle")
  mode.setting = battleSetting
  mode.backSetting = offSetting
  return mode
end

function Battle.bind(mod)
  modRef = mod
  modules, dataFiles = {}, {}
  makeNamespace()
  return Battle
end

function Battle.configureGame(game)
  local pokemon = game and game.data and game.data.pokemon
  local maxDex = 151
  if type(pokemon) == "table" then
    for _, def in pairs(pokemon) do
      if type(def) == "table" then
        local dex = tonumber(def.dex or def.index)
        if dex and dex > maxDex and dex <= Battle.COUNT then maxDex = math.floor(dex) end
      end
    end
  end
  configured = maxDex
  local chart = game and game.data and game.data.type_chart
  generation = tonumber(chart and chart.generation) or 1
  if generation == 2 then
    gen2 = gen2 or require("mods.STADIUM2_IMPORTER.lib.gen2_battle")
    gen2.bind(modRef)
    gen2.configureGame(game)
  end
  Importer.configure({ count = maxDex })
  return maxDex
end

function Battle.install()
  if installed then return false end
  if not V then return false end
  -- Installation happens before game.ready, so the active version is the
  -- reliable discriminator here. Gold has its own battle screen and must not
  -- receive the Gen 1 BattleState/OverworldController patches below.
  local okVersion, GameVersion = pcall(require, "src.core.GameVersion")
  if generation == 2 or (okVersion and GameVersion and GameVersion.generation
      and GameVersion.generation() == 2) then
    generation = 2
    gen2 = gen2 or require("mods.STADIUM2_IMPORTER.lib.gen2_battle")
    gen2.bind(modRef)
    installed = gen2.install()
    return installed
  end
  local mode = overworldBattle()
  mode.install()
  local okCam, cam = pcall(V.require, "CamControl")
  if okCam and cam and cam.install then pcall(cam.install) end
  installed = true
  return true
end

function Battle.update(dt)
  if not installed then return false end
  -- Presented-frame time, never the speed-scaled logic delta.  Cap a long
  -- suspended/window-drag frame so animations do not skip whole authored
  -- actions when presentation resumes.
  dt = math.min(math.max(tonumber(dt) or 0, 0), 0.1)
  if generation == 2 then return gen2 and gen2.update(dt) or false end
  local okDay, day = pcall(V.require, "DayNight")
  if okDay and day and day.update then pcall(day.update, dt) end
  local mode = overworldBattle()
  if not ready() then
    mode.finish()
    return false
  end
  mode.update(dt)
  return mode.shot() ~= nil
end

function Battle.ensure(battle)
  if not installed or not ready() then return false end
  if generation == 2 then return gen2 and gen2.ensure(battle) or false end
  local mode = overworldBattle()
  mode.ensure(battle)
  return mode.arena() ~= nil
end

function Battle.finish()
  if generation == 2 then
    if gen2 then gen2.finish() end
    return
  end
  if not V then return end
  overworldBattle().finish()
end

function Battle.enabled()
  return Importer.modelsEnabled() and Importer.battleEnabled()
end

function Battle.ready()
  return ready()
end

function Battle.status()
  if generation == 2 and gen2 then return gen2.status() end
  local mode = V and overworldBattle() or nil
  return {
    enabled = Battle.enabled(),
    ready = ready(),
    count = configured,
    active = mode and mode.arena() ~= nil or false,
    shot = mode and mode.shot() or nil,
  }
end

function Battle.lib(name)
  return V and V.require(name) or nil
end

function Battle.namespace()
  return V
end

Battle.isShiny = isShiny
Battle.dexFor = dexFor

function Battle.resetForTests()
  if gen2 then pcall(gen2.resetForTests) end
  if V then pcall(Battle.finish) end
  installed = false
  modRef = nil
  V = nil
  modules, dataFiles = {}, {}
  configured = 151
  generation = 1
  gen2 = nil
end

return Battle
