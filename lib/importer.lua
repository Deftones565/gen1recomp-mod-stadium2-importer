local Rom = require("mods.STADIUM2_IMPORTER.lib.rom")
local Extract = require("mods.STADIUM2_IMPORTER.lib.extract")
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
local MODEL_KEEP = 4
local configuredCount = 151
local NATIVE_PICKED = "picked_rom.gb"
local NATIVE_PICKED_ALT = "picked_stadium.z64"
local NATIVE_PICKED_FILES = { NATIVE_PICKED_ALT, NATIVE_PICKED }
local nativePickPending = false
local nativePickBefore = nil
local nativePickLostFocus = false
local nativePickPrevious = nil
local nativePickMode = nil
local status = {
  state = "idle",
  done = 0,
  total = configuredCount,
  phase = nil,
  error = nil,
  rom = nil,
}

local function platformName()
  local system = love and love.system
  if not (system and type(system.getOS) == "function") then return nil end
  local ok, platform = pcall(system.getOS)
  return ok and platform or nil
end

local function nativePickerAvailable()
  local system = love and love.system
  if not (system and type(system.pickFile) == "function") then return false end
  local platform = platformName()
  -- pickFile is a per-port bridge, not a standard LOVE capability. Some
  -- builds expose the Lua symbol on desktop even though the backend returns
  -- false there, so function-existence alone can swallow the working desktop
  -- chooser. Mobile owns the save-file handoff; UWP/path-result builds own
  -- getPickedFile. Everything else must fall through to Discovery.choose().
  return platform == "Android" or platform == "iOS" or platform == "UWP"
    or type(system.getPickedFile) == "function"
end

local function nativePickerUsesPathResult()
  local system = love and love.system
  return nativePickerAvailable() and type(system.getPickedFile) == "function"
end

local function nativePickedPaths()
  return NATIVE_PICKED_FILES
end

local function pickedFingerprint(path)
  local fs = love and love.filesystem
  if not (fs and type(fs.getInfo) == "function") then return nil end
  local ok, info = pcall(fs.getInfo, path, "file")
  if not (ok and info) then return nil end
  return table.concat({ tostring(info.size or "?"), tostring(info.modtime or "?") }, ":")
end

local function clearNativePicker(restore)
  nativePickPending = false
  nativePickBefore = nil
  nativePickLostFocus = false
  nativePickMode = nil
  if restore and nativePickPrevious then
    status.state = nativePickPrevious.state
    status.phase = nativePickPrevious.phase
    status.error = nativePickPrevious.error
    status.rom = nativePickPrevious.rom
  end
  nativePickPrevious = nil
end

local function openNativePicker()
  if not nativePickerAvailable() then return false, "Native picker unavailable" end
  nativePickPrevious = {
    state = status.state, phase = status.phase, error = status.error, rom = status.rom,
  }
  nativePickMode = nativePickerUsesPathResult() and "path" or "save"
  if nativePickMode == "save" then
    nativePickBefore = {}
    for _, path in ipairs(nativePickedPaths()) do
      nativePickBefore[path] = pickedFingerprint(path)
    end
  else
    nativePickBefore = nil
  end
  nativePickLostFocus = false

  local system = love.system
  local function tryPick(...)
    local ok, opened = pcall(system.pickFile, ...)
    if ok and opened then return true end
    return false, ok and nil or tostring(opened)
  end

  local opened, err = tryPick("stadium")
  if not opened then opened, err = tryPick("rom") end
  if not opened then opened, err = tryPick() end
  if not opened then
    clearNativePicker(true)
    return false, err or "Native file picker did not open"
  end
  nativePickPending = true
  status.state = "picking"
  status.phase = "picker"
  status.error = nil
  status.rom = nil
  return true
end

local function removePickedFile(path)
  local fs = love and love.filesystem
  if fs and type(fs.remove) == "function" then pcall(fs.remove, path or NATIVE_PICKED) end
end

local function removeHostPickedFile(path)
  if type(path) ~= "string" or path == "" or not (os and os.remove) then return end
  pcall(os.remove, path)
end

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
  if Cache.available(configuredCount) and status.state ~= "building"
      and status.state ~= "picking" then setReady() end
  return Importer
end

function Importer.status()
  return status
end

function Importer.available(count)
  return Cache.available(count or configuredCount)
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
  return Renderer.new(model, options)
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
  return Renderer.new(model,options)
end

function Importer.releaseModels()
  for _, model in pairs(modelCache) do Pack.release(model) end
  modelCache, modelOrder = {}, {}
end

function Importer.parsePack(bytes)
  return Pack.parse(bytes)
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

function Importer.beginFrom(bytes, label)
  if job then return false, "Stadium 2 import is already running" end
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
  job = Extract.newJob(normalized,
    function(species, normalBytes, shinyBytes)
      return Cache.writePair(species, normalBytes, shinyBytes)
    end,
    function(name,bytes) return Cache.writeSpecial(name,bytes) end)
  job.label = status.rom
  job.md5 = romMeta.md5
  return true
end

local function beginCandidate(candidate, options)
  options = type(options) == "table" and options or {}
  local function cleanup()
    if options.removeAfter then
      if candidate and candidate.kind == "love" then
        removePickedFile(type(options.removeAfter) == "string" and options.removeAfter or candidate.path)
      elseif candidate and candidate.kind == "host" then
        removeHostPickedFile(type(options.removeAfter) == "string" and options.removeAfter or candidate.path)
      end
    end
    if options.removeHostAfter then
      removeHostPickedFile(type(options.removeHostAfter) == "string"
        and options.removeHostAfter or (candidate and candidate.path))
    end
  end
  local bytes, err = Discovery.read(candidate)
  if not bytes then
    cleanup()
    return fail("reading ROM", err)
  end
  local started, beginErr = Importer.beginFrom(bytes, options.label or candidate.path)
  cleanup()
  return started, beginErr
end

function Importer.beginPath(path)
  return beginCandidate({ kind = "host", path = path })
end

local function pollNativePicker()
  if not nativePickPending then return false end

  if nativePickMode == "path" then
    local system = love and love.system
    if system and type(system.getPickedFile) == "function" then
      local ok, path = pcall(system.getPickedFile)
      if ok and type(path) == "string" and path ~= "" then
        clearNativePicker(false)
        local started = beginCandidate({ kind = "host", path = path }, {
          removeHostAfter = platformName() == "UWP",
          label = "native file picker",
        })
        return started and true or false
      end
    end
    if system and type(system.getPickError) == "function" then
      local okErr, errText = pcall(system.getPickError)
      if okErr and type(errText) == "string" and errText ~= "" then
        if errText:lower():find("cancel", 1, true) then
          clearNativePicker(true)
          return false
        end
        clearNativePicker(false)
        fail("opening file picker", errText)
        return false
      end
    end
  else
    for _, path in ipairs(nativePickedPaths()) do
      local current = pickedFingerprint(path)
      local before = nativePickBefore and nativePickBefore[path] or nil
      if current and current ~= before then
        clearNativePicker(false)
        local started = beginCandidate({ kind = "love", path = path }, {
          removeAfter = path,
          label = "native file picker",
        })
        return started and true or false
      end
    end
  end

  local window = love and love.window
  if window and type(window.hasFocus) == "function" then
    local ok, focused = pcall(window.hasFocus)
    if ok then
      if focused == false then
        nativePickLostFocus = true
      elseif focused == true and nativePickLostFocus then
        clearNativePicker(true)
      end
    end
  end
  return false
end

function Importer.autoImport()
  if Importer.available() then
    setReady()
    return true
  end
  local candidate = Discovery.find()
  if not candidate then return false, "no Pokemon Stadium 2 US ROM found" end
  return beginCandidate(candidate)
end

function Importer.request()
  if job then return false, "Stadium 2 import is already running" end
  if nativePickPending then return false, "Native file picker already open" end

  if nativePickerAvailable() then
    local opened, pickerErr = openNativePicker()
    if opened then return true end
    return fail("opening file picker", pickerErr)
  end

  local path = Discovery.choose()
  if not path then return false, "cancelled" end
  return Importer.beginPath(path)
end

function Importer.step()
  if not job then pollNativePicker() end
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
      Importer.request()
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
Importer.NATIVE_PICKED = NATIVE_PICKED
Importer.NATIVE_PICKED_ALT = NATIVE_PICKED_ALT
Importer.nativePickerAvailable = nativePickerAvailable
Importer.COUNT = function() return configuredCount end
Importer.shinyPalettesFromTransformSource = Palette.fromTransformSource
Importer.cache = Cache
Importer.rom = Rom
Importer.extract = Extract
Importer.pack = Pack
Importer.renderer = Renderer

return Importer
