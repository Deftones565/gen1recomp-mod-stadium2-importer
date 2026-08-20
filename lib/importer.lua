local Rom = require("mods.STADIUM2_IMPORTER.lib.rom")
local Extract = require("mods.STADIUM2_IMPORTER.lib.extract")
local ExportPool = require("mods.STADIUM2_IMPORTER.lib.export_pool")
local Cache = require("mods.STADIUM2_IMPORTER.lib.cache")
local Discovery = require("mods.STADIUM2_IMPORTER.lib.discovery")
local Palette = require("mods.STADIUM2_IMPORTER.lib.palette")
local Handlers = require("mods.STADIUM2_IMPORTER.lib.model_handlers")
local Pack = require("mods.STADIUM2_IMPORTER.lib.pack")
local Renderer = require("mods.STADIUM2_IMPORTER.lib.renderer")

local Importer = {}

local modRef
local job
local romMeta
local modelCache = {}
local modelOrder = {}
local ownedModels = setmetatable({}, {__mode="k"})
local MODEL_KEEP = 4
local configuredCount = 151
local playthroughReady = false
local status = {
  state = "idle",
  done = 0,
  total = configuredCount,
  phase = nil,
  error = nil,
  rom = nil,
}

local function fail(stage, reason)
  status.state = "failed"
  status.phase = stage
  status.error = tostring(reason or "unknown error")
  Cache.writeError(("Stage: %s\nReason: %s"):format(stage, status.error))
  if modRef and modRef.log then
    pcall(function() modRef.log:error("stadium2 importer: %s: %s", stage, status.error) end)
  end
  job = nil
  return false, status.error
end

local function setReady()
  status.state = "ready"
  status.done = configuredCount
  status.total = configuredCount
  status.progress = 1
  status.phase = nil
  status.species = nil
  status.error = nil
end

function Importer.bind(mod)
  modRef = mod
  Cache.bind(mod)
  Discovery.bind(mod)
  return Importer
end

function Importer.setPlaythroughReady(value)
  local ready = value == true
  if not ready then
    playthroughReady = false
    if status.state == "ready" then
      status.state = "idle"
      status.done = 0
      status.progress = 0
      status.phase = nil
      status.species = nil
      status.error = nil
    end
    return Importer
  end

  playthroughReady = true
  if Cache.available(configuredCount) and status.state ~= "building"
      and status.state ~= "picking" then
    setReady()
  end
  return Importer
end

function Importer.configure(options)
  options = type(options) == "table" and options or {}
  local requested = math.floor(tonumber(options.count) or configuredCount)
  if requested < 151 then requested = 151 end
  if requested > 251 then requested = 251 end
  configuredCount = math.max(configuredCount, requested)
  status.total = configuredCount
  Extract.configure({
    count = configuredCount,
    cache = options.cache,
    shinyPalettes = options.shinyPalettes,
    palettePairs = options.palettePairs,
  })
  if playthroughReady and Cache.available(configuredCount)
      and status.state ~= "building" and status.state ~= "picking" then
    setReady()
  end
  return Importer
end

function Importer.status()
  return status
end

function Importer.cacheStatus()
  if not playthroughReady then
    return { state = "error", code = "not_in_playthrough",
      message = "Start or continue a game before checking Stadium 2 cache" }
  end
  return Cache.inspect(configuredCount)
end

function Importer.available(count)
  if not playthroughReady then return false end
  return Cache.inspect(count or configuredCount).state == "valid"
end

function Importer.modelsEnabled()
  if modRef and modRef.options and modRef.options.get then
    local ok, value = pcall(modRef.options.get, modRef.options, "stadium2_models")
    if ok and value == false then return false end
  end
  return true
end

function Importer.battleEnabled()
  if modRef and modRef.options and modRef.options.get then
    local ok, value = pcall(modRef.options.get, modRef.options, "stadium2_battle")
    if ok and value == false then return false end
  end
  return true
end

function Importer.shaderStyle()
  if modRef and modRef.options and modRef.options.get then
    local ok, value = pcall(modRef.options.get, modRef.options, "stadium2_shader")
    if ok and value == "cel" then return "cel" end
  end
  return "stadium"
end

local function rendererOptions(options)
  local out = {}
  for key, value in pairs(type(options) == "table" and options or {}) do
    out[key] = value
  end
  if out.shaderStyle == nil then out.shaderStyle = Importer.shaderStyle() end
  -- Existing battle actors observe an option change immediately; this does
  -- not rebuild packs, meshes, shaders, or the active battle scene.
  if out.shaderStyleProvider == nil then out.shaderStyleProvider = Importer.shaderStyle end
  return out
end

function Importer.modelPath(species, variant)
  species = tonumber(species)
  if not species or species < 1 or species > configuredCount then return nil end
  return Cache.path(species, variant)
end

function Importer.readPack(species, variant)
  return Cache.read(species, variant)
end

local function modelKey(species, variant)
  return tostring(variant == "shiny" and "shiny" or "normal") .. ":" .. tostring(species)
end

local function touchModel(key)
  for i = #modelOrder, 1, -1 do
    if modelOrder[i] == key then table.remove(modelOrder, i) end
  end
  modelOrder[#modelOrder + 1] = key
  while #modelOrder > MODEL_KEEP do
    local drop = table.remove(modelOrder, 1)
    local model = modelCache[drop]
    modelCache[drop] = nil
    if model then Pack.release(model) end
  end
end

function Importer.loadModel(species, variant)
  species = math.floor(tonumber(species) or 0)
  if species < 1 or species > configuredCount then return nil, "species out of range" end
  variant = variant == "shiny" and "shiny" or "normal"
  local key = modelKey(species, variant)
  local hit = modelCache[key]
  if hit then
    touchModel(key)
    return hit
  end
  local bytes = Cache.read(species, variant)
  if not bytes then return nil, "model pack unavailable" end
  local model, err = Pack.parse(bytes)
  if not model then return nil, err end
  model.variant = variant
  modelCache[key] = model
  touchModel(key)
  return model
end

function Importer.newRenderer(species, variant, options)
  if not Importer.modelsEnabled() then return nil, "Stadium 2 models disabled" end
  local model, err = Importer.loadModel(species, variant)
  if not model then return nil, err end
  return Renderer.new(model, rendererOptions(options))
end

-- Return an independently owned model. Unlike loadModel(), this instance is
-- never placed in the importer's small shared LRU and may be freely mutated by
-- the caller. The caller must eventually pass it to releaseModel().
function Importer.createModel(species, variant)
  species = math.floor(tonumber(species) or 0)
  if species < 1 or species > configuredCount then return nil, "species out of range" end
  variant = variant == "shiny" and "shiny" or "normal"
  local bytes = Cache.read(species, variant)
  if not bytes then return nil, "model pack unavailable" end
  local model, err = Pack.parse(bytes)
  if not model then return nil, err end
  model.variant = variant
  ownedModels[model] = true
  return model
end

function Importer.releaseModel(model)
  if type(model) ~= "table" or not ownedModels[model] then
    return false, "model is not owned by the caller"
  end
  ownedModels[model] = nil
  Pack.release(model)
  return true
end

-- Build a renderer from either an owned model or a compatible caller-created
-- model table. Releasing the renderer does not release the model.
function Importer.newRendererFromModel(model, options)
  return Renderer.new(model, rendererOptions(options))
end

function Importer.createSpecialModel(name)
  local bytes=Cache.readSpecial(name)
  if not bytes then return nil,"special battle pack unavailable" end
  local model,err=Pack.parse(bytes)
  if not model then return nil,err end
  model.variant="normal"
  ownedModels[model]=true
  return model
end

function Importer.loadSpecial(name)
  local key="special:"..tostring(name)
  local hit=modelCache[key]
  if hit then touchModel(key);return hit end
  local bytes=Cache.readSpecial(name)
  if not bytes then return nil,"special battle pack unavailable" end
  local model,err=Pack.parse(bytes)
  if not model then return nil,err end
  model.variant="normal"
  modelCache[key]=model
  touchModel(key)
  return model
end

function Importer.newSpecialRenderer(name,options)
  local model,err=Importer.loadSpecial(name)
  if not model then return nil,err end
  return Renderer.new(model,rendererOptions(options))
end

function Importer.releaseModels()
  for _, model in pairs(modelCache) do Pack.release(model) end
  modelCache, modelOrder = {}, {}
end

function Importer.parsePack(bytes)
  local model,err=Pack.parse(bytes)
  if model then ownedModels[model]=true end
  return model,err
end

function Importer.readHandlers(species, variant)
  local bytes = Importer.readPack(species, variant)
  if not bytes then return nil end
  return Handlers.readExtension(bytes)
end

function Importer.handlerInfo(address)
  return Handlers.info(address)
end

function Importer.evaluateHandler(record, phase, runtime)
  return Handlers.evaluate(record, phase, runtime)
end

function Importer.runHandlers(records, phase, runtime, state)
  return Handlers.run(records, phase, runtime, state)
end

function Importer.runModelHandlers(species, variant, phase, runtime, state)
  local extension = Importer.readHandlers(species, variant)
  if not extension then return nil, nil end
  return Handlers.runExtension(extension, phase, runtime, state)
end

function Importer.resolveHandlerPointer(extension, pointer, length)
  return Handlers.resolvePointer(extension, pointer, length)
end

function Importer.beginFrom(bytes, label, options)
  if not playthroughReady then
    return false, "Start or continue a game before importing Stadium 2"
  end
  if job then return false, "Stadium 2 import is already running" end
  options = type(options) == "table" and options or {}

  -- FINAL DESTRUCTIVE GUARD: no automatic/internal path is allowed to clear a
  -- valid persistent cache.  Only the Options-row manual reimport passes
  -- forceReimport=true.  This protects against any stray caller above us --
  -- exported beginPath/autoImport, retry UI, or a future hook -- reaching the
  -- destructive cache-clear boundary after the cache was already proven valid.
  if not options.forceReimport then
    local cache = Cache.inspect(configuredCount)
    if cache.state == "valid" then
      setReady()
      if modRef and modRef.log then
        local ctx = cache.context or {}
        pcall(function()
          modRef.log:info(
            "stadium2 import suppressed: valid cache game=%s playthrough=%s count=%s",
            tostring(ctx.gameVersion or "?"), tostring(ctx.playthroughId or "?"),
            tostring(cache.marker and cache.marker.count or "?"))
        end)
      end
      return true, "ready"
    end
    if cache.state == "error" then
      return fail("checking persistent cache",
        ("%s: %s"):format(tostring(cache.code or "storage_error"),
          tostring(cache.message or "persistent cache unavailable")))
    end
  end

  if nativePickPending then clearNativePicker(false) end
  local normalized, metaOrErr = Rom.validate(bytes)
  if not normalized then return fail("validating ROM", metaOrErr) end
  Importer.releaseModels()
  local ok, clearErr = Cache.clear(configuredCount)
  if not ok then return fail("preparing cache", clearErr) end
  romMeta = metaOrErr
  status.state = "building"
  status.done = 0
  status.total = configuredCount
  status.progress = 0
  status.phase = "scan"
  status.error = nil
  status.rom = label or "Pokemon Stadium 2 (US)"
  local function writePack(species, normalBytes, shinyBytes)
    return Cache.writePair(species, normalBytes, shinyBytes)
  end
  local function writeSpecial(name, bytes)
    return Cache.writeSpecial(name, bytes)
  end
  -- Thread creation is capability/platform dependent. The serial job remains
  -- a transparent fallback and produces the exact same cache/API surface.
  if not options.serialExport then
    local workerSource
    if modRef and type(modRef.read) == "function" then
      local okRead, source = pcall(modRef.read, modRef, "workers/export_worker.lua")
      if okRead and type(source) == "string" then workerSource = source end
    end
    job = ExportPool.new(normalized, configuredCount, writePack, writeSpecial,
      { root = modRef and modRef.path, workerSource = workerSource })
  end
  if not job then
    job = Extract.newJob(normalized, writePack, writeSpecial)
  end
  job.label = status.rom
  job.md5 = romMeta.md5
  return true
end

local function beginCandidate(candidate, options)
  options = type(options) == "table" and options or {}
  local bytes, err = Discovery.read(candidate)
  if not bytes then return fail("reading ROM", err) end
  local started, beginErr = Importer.beginFrom(
    bytes, options.label or candidate.path, options)
  return started, beginErr
end

function Importer.beginPath(path)
  return beginCandidate({ kind = "mod", path = path })
end

function Importer.autoImport()
  if not playthroughReady then
    return false, "Start or continue a game before importing Stadium 2"
  end

  local cache = Cache.inspect(configuredCount)
  if cache.state == "valid" then
    setReady()
    return true, "ready"
  end

  -- A broken/unavailable persistence lookup is NOT evidence that the cache is
  -- absent. Rebuilding in that situation causes the endless auto-import loop:
  -- every failed read looks missing, so every gameplay entry extracts again.
  if cache.state == "error" then
    return fail("checking persistent cache",
      ("%s: %s"):format(tostring(cache.code or "storage_error"),
        tostring(cache.message or "persistent cache unavailable")))
  end

  -- missing / stale / incomplete are the only automatic rebuild states.
  local candidate = Discovery.find()
  if not candidate then
    return fail("reading required ROM",
      "the engine-managed Pokemon Stadium 2 required ROM is unavailable")
  end
  return beginCandidate(candidate)
end

function Importer.request(options)
  if not playthroughReady then
    return false, "Start or continue a game before importing Stadium 2"
  end
  if job then return false, "Stadium 2 import is already running" end
  options = type(options) == "table" and options or {}

  -- Generic request is SAFE by default: it cannot overwrite a valid cache.
  -- A deliberate Options-row reimport supplies forceReimport=true below.
  local candidate=Discovery.find()
  if candidate then return beginCandidate(candidate, options) end
  return fail("selecting ROM","The engine-managed Pokemon Stadium 2 ROM is unavailable. "
    .."Open the mod's Imported Files panel and provide the required ROM.")
end

function Importer.reimport()
  return Importer.request({ forceReimport = true, source = "options" })
end

function Importer.step()
  if not job then return false end
  local active = job
  local ok, more = pcall(active.step, active)
  if not ok then return fail("extracting ROM", more) end
  status.done = active.done or 0
  status.total = active.total or configuredCount
  status.progress = active.progress and active:progress()
    or (status.total > 0 and status.done / status.total or 0)
  status.phase = active.buildStage or active.phase
  status.species = active.species
  status.modelSpecies = active.modelSpecies or 0
  status.animatedSpecies = active.animatedSpecies or 0
  status.animationClips = active.animationClips or 0
  if active.error then return fail("building packs", active.error) end
  if more == false then
    if not active.success then return fail("building packs", active.error or "incomplete Stadium 2 import") end
    local finished, markerErr = Cache.finish(romMeta, configuredCount)
    if not finished then return fail("writing completion marker", markerErr) end
    job = nil
    setReady()
    if modRef and modRef.log then
      pcall(function()
        modRef.log:info("stadium2 importer: built %d/%d species, %d Unown forms, Substitute; animation species=%d",
          active.builtCount or 0,configuredCount,(active.unownBuilt or 0)+1,
          active.animatedBuilt or 0)
      end)
    end
    return false
  end
  return true
end

function Importer.row()
  return {
    id = "STADIUM2_IMPORTER:rom",
    stadium2Importer = true,
    label = "STADIUM 2 ROM",
    value = function()
      if status.state == "building" then
        return ("%d/%d"):format(status.done or 0, status.total or configuredCount)
      end
      if status.state == "picking" then return "PICKING" end
      if Importer.available() then return "READY" end
      if status.state == "failed" then return "FAILED" end
      return "IMPORT"
    end,
    -- This row opens a screen/activity; it is an action, not a value that
    -- should cycle on Left/Right. Both Gen 1 and Gen 2 option menus give
    -- action rows an explicit `activate` callback on A.
    activate = function()
      if status.state == "building" or status.state == "picking" then return true end
      -- This is the one intentional destructive path: the player explicitly
      -- selected STADIUM 2 ROM from Options while a valid cache may exist.
      Importer.reimport()
      return true
    end,
  }
end

function Importer.appendRow(rows)
  if type(rows) ~= "table" then return rows end
  for _, row in ipairs(rows) do
    if type(row) == "table" and row.stadium2Importer then return rows end
  end
  rows[#rows + 1] = Importer.row()
  return rows
end

Importer.US_MD5 = Rom.US_MD5
Importer.FORMAT = Cache.FORMAT
Importer.COUNT = function() return configuredCount end
Importer.shinyPalettesFromTransformSource = Palette.fromTransformSource
Importer.cache = Cache
Importer.rom = Rom
Importer.extract = Extract
Importer.pack = Pack
Importer.renderer = Renderer

return Importer
