local scene
local Importer
local Presentation
local Camera
local DynamicObject
local root
local loadError
local paused = false
local selectedSide = "enemy"
local enemyDex = math.max(1, math.min(251,
  math.floor(tonumber(os.getenv("STADIUM2_VISUAL_ENEMY")) or 109)))
local playerDex = math.max(1, math.min(251,
  math.floor(tonumber(os.getenv("STADIUM2_VISUAL_PLAYER")) or 159)))
local help = true
local screenshotMessage
local screenshotTimer = 0
local importing = false
local forceGas = os.getenv("STADIUM2_VISUAL_FORCE_EFFECT") == "1"
  or os.getenv("STADIUM2_VISUAL_FORCE_GAS") == "1"
local forceGasAge = math.max(0, math.min(15,
  tonumber(os.getenv("STADIUM2_VISUAL_FORCE_GAS_AGE")) or 0))
local debugPanel = true
local suppressGasDraw = false
local isolatePrimitive = math.max(0,
  math.floor(tonumber(os.getenv("STADIUM2_VISUAL_ISOLATE")) or 0))
local autoCapture = os.getenv("STADIUM2_VISUAL_AUTOCAPTURE")
local autoCaptureFrames = 0
local autoCaptureAt = math.max(1,
  math.floor(tonumber(os.getenv("STADIUM2_VISUAL_AUTOCAPTURE_FRAME")) or 8))
local autoKeys = os.getenv("STADIUM2_VISUAL_AUTOKEYS")
local autoKeysApplied = false
local shaderStyle = os.getenv("STADIUM2_VISUAL_SHADER") == "cel" and "cel" or "stadium"

local function fileExists(path)
  local handle = io.open(path, "rb")
  if not handle then return false end
  handle:close()
  return true
end

local function parent(path)
  path = tostring(path or ""):gsub("[/\\]+$", "")
  local value = path:match("^(.*)[/\\][^/\\]+$")
  return value and value ~= "" and value or nil
end

local function workingDirectory()
  if love.filesystem and love.filesystem.getWorkingDirectory then
    local ok, value = pcall(love.filesystem.getWorkingDirectory)
    if ok and type(value) == "string" and value ~= "" then return value end
  end
  return os.getenv("PWD") or "."
end

local function findRoot()
  local supplied = os.getenv("GEN1RECOMP_ROOT")
  if supplied and fileExists(supplied .. "/mods/STADIUM2_IMPORTER/lib/battle_scene.lua") then
    return supplied
  end
  local at = workingDirectory()
  for _ = 1, 10 do
    if fileExists(at .. "/mods/STADIUM2_IMPORTER/lib/battle_scene.lua") then return at end
    at = parent(at)
    if not at then break end
  end
  return nil
end

local function installRepoLoader(base)
  local loaders = package.searchers or package.loaders
  table.insert(loaders, 2, function(name)
    local modPrefix = "mods.STADIUM2_IMPORTER"
    local isImporter = name == modPrefix
      or name:sub(1, #modPrefix + 1) == modPrefix .. "."
    local isEngine = name == "src" or name:sub(1, 4) == "src."
    if not isImporter and not isEngine then return nil end
    local path = base .. "/" .. name:gsub("%.", "/") .. ".lua"
    if not fileExists(path) then return "\n\tmissing " .. path end
    local chunk, err = loadfile(path)
    if not chunk then return "\n\t" .. tostring(err) end
    return chunk
  end)
end

local function packagedDataRoot()
  local supplied = os.getenv("STADIUM2_VISUAL_DATA_ROOT")
  if supplied and supplied ~= "" then return supplied:gsub("[/\\]+$", "") end
  local osName = love.system and love.system.getOS and love.system.getOS() or ""
  if osName == "Windows" then
    local appData = os.getenv("APPDATA")
    if appData and appData ~= "" then return appData .. "/pokemon-love2d" end
  elseif osName == "OS X" then
    local home = os.getenv("HOME")
    if home and home ~= "" then
      return home .. "/Library/Application Support/pokemon-love2d"
    end
  else
    local data = os.getenv("XDG_DATA_HOME")
    if not data or data == "" then
      local home = os.getenv("HOME")
      if home and home ~= "" then data = home .. "/.local/share" end
    end
    if data and data ~= "" then return data .. "/pokemon-love2d" end
  end
  return love.filesystem.getSaveDirectory()
end

local function hostReadFs(base)
  local packRoot = os.getenv("STADIUM2_VISUAL_PACK_ROOT")
  local tempRoot = os.getenv("STADIUM2_VISUAL_TEMP_ROOT")
    or os.getenv("TMPDIR") or "/tmp"
  tempRoot = tempRoot:gsub("[/\\]+$", "")
  local tempPrefix = tempRoot .. "/stadium2-importer-visual-cache-"
  local removed = {}
  local function tempPath(path)
    -- Storage keys are already sandboxed. Escape separators as well so the
    -- visual cache remains a flat set of files and needs no host directories.
    local token = tostring(path or ""):gsub("([^%w%._-])", function(char)
      return ("_%02x"):format(char:byte())
    end)
    return tempPrefix .. token
  end
  local function readFile(path)
    local file, err = io.open(path, "rb")
    if not file then return nil, err end
    local bytes = file:read("*a")
    file:close()
    return bytes
  end
  local function fileInfo(path)
    local file = io.open(path, "rb")
    if not file then return nil end
    local size = file:seek("end")
    file:close()
    return { type = "file", size = size }
  end
  local function tempOwnsAlternateStorageType(path)
    local stem = tostring(path or ""):match("^(.*)%.lua")
    local alternate = ".bin"
    if not stem then
      stem = tostring(path or ""):match("^(.*)%.bin")
      alternate = ".lua"
    end
    if not stem then return false end
    for _, suffix in ipairs({ "", ".bak", ".tmp" }) do
      if fileInfo(tempPath(stem .. alternate .. suffix)) then return true end
    end
    return false
  end
  local function packOverride(path)
    if not packRoot or packRoot == "" then return nil end
    local kind, species = tostring(path or ""):match(
      "STADIUM2_IMPORTER/cache/(normal|shiny)/(%d+)%.lua$")
    if not kind then return nil end
    local file = io.open(("%s/%s/%s.dsm"):format(packRoot, kind, species), "rb")
    if not file then return nil end
    local bytes = file:read("*a")
    file:close()
    return "return { bytes = " .. string.format("%q", bytes) .. " }\n"
  end
  local function absolute(path)
    return base .. "/" .. tostring(path or ""):gsub("^[/\\]+", "")
  end
  return {
    getInfo = function(path)
      local info = fileInfo(tempPath(path))
      if info then return info end
      if removed[path] then return nil end
      -- A rebuilt opaque .bin record must hide the installed legacy .lua
      -- record (and vice versa) across visual-harness process restarts.
      if tempOwnsAlternateStorageType(path) then return nil end
      local override = packOverride(path)
      if override then return { type = "file", size = #override } end
      return fileInfo(absolute(path))
    end,
    read = function(path)
      local bytes = readFile(tempPath(path))
      if bytes ~= nil then return bytes end
      if removed[path] then return nil, "visual cache record was removed" end
      if tempOwnsAlternateStorageType(path) then
        return nil, "visual cache owns the alternate storage record type"
      end
      local override = packOverride(path)
      if override then return override end
      return readFile(absolute(path))
    end,
    write = function(path, bytes)
      local file, err = io.open(tempPath(path), "wb")
      if not file then return false, err end
      local ok, writeErr = file:write(bytes)
      file:close()
      if not ok then return false, writeErr end
      removed[path] = nil
      return true
    end,
    remove = function(path)
      os.remove(tempPath(path))
      removed[path] = true
      return true
    end,
    createDirectory = function() return true end,
  }
end

local function bindPlaythroughStorage(base)
  local SaveData = require("src.core.SaveData")
  local Storage = require("src.mods.Storage")
  local version = tostring(os.getenv("STADIUM2_VISUAL_GAME") or "gold"):lower()
  local dataRoot = packagedDataRoot()
  local fs = hostReadFs(dataRoot)
  local options = SaveData.loadOptions(fs)
  local registry = options.saveSlots and options.saveSlots[version]
  local slot = registry and registry.active or "legacy"
  local ids = options.playthroughIds and options.playthroughIds[version]
  local playthroughId = ids and ids[slot]
  if type(playthroughId) ~= "string" or playthroughId == "" then
    return nil, ("no selected %s Stadium cache under %s; set "
      .. "STADIUM2_VISUAL_DATA_ROOT if the packaged game uses another location")
      :format(version, dataRoot)
  end

  local game = { save = {
    version = version,
    meta = { playthroughId = playthroughId },
  } }
  local storage = Storage.new("STADIUM2_IMPORTER", fs)
  -- Storage:list normally walks through love.filesystem. This harness layers
  -- a writable cache in the host temp directory over the packaged save root,
  -- so enumerate fixed Stadium keys by probing main/backup records instead.
  -- A stale cache can then rebuild for the visual test without modifying the
  -- selected playthrough's installed cache.
  local storageBase = ("mod_storage/%s/%s/STADIUM2_IMPORTER/")
    :format(version, playthroughId)
  local function stored(key)
    local path = storageBase .. key
    return fs.getInfo(path .. ".bin") or fs.getInfo(path .. ".bin.bak")
      or fs.getInfo(path .. ".lua") or fs.getInfo(path .. ".lua.bak")
  end
  storage.list = function(_, _, prefix)
    if prefix ~= nil and prefix ~= "" and prefix ~= "cache" then return {} end
    local keys = {}
    local function add(key) if stored(key) then keys[#keys + 1] = key end end
    add("cache/marker")
    add("cache/error")
    add("cache/battle/specials")
    for index = 1, math.ceil(251 / 8) do
      add(("cache/battle/shard_%03d"):format(index))
    end
    -- Retain legacy enumeration so an S2IMP38 cache is recognized as stale
    -- and can be rebuilt into the current sharded representation.
    add("cache/battle/substitute")
    for byte = string.byte("b"), string.byte("z") do
      local form = "cache/battle/unown_" .. string.char(byte)
      add(form)
      add(form .. "_shiny")
    end
    for species = 1, 251 do
      add(("cache/normal/%03d"):format(species))
      add(("cache/shiny/%03d"):format(species))
    end
    return keys
  end
  local context, code, message = storage:context(game)
  if not context then
    return nil, message or code or "could not resolve Stadium cache scope"
  end

  local handle = {
    game = game,
    storage = storage,
    options = { get = function(_, key)
      if key == "stadium2_shader" then return shaderStyle end
    end },
    -- Cache reuse does not need the ROM.  Keep a scoped development fallback
    -- for an explicitly extracted local install without teaching the harness
    -- to search arbitrary host paths or release archives.
    read = function(_, path)
      local filename = base .. "/mods/STADIUM2_IMPORTER/" .. tostring(path)
      local file = io.open(filename, "rb")
      if not file then return nil end
      local bytes = file:read("*a")
      file:close()
      return bytes
    end,
  }
  context.dataRoot = dataRoot
  return handle, context
end

local function warn(message)
  print("[stadium2-visual-test] " .. tostring(message))
end

local function wrapSpecies(value)
  return ((math.floor(tonumber(value) or 1) - 1) % 251) + 1
end

local function actorForSide(side)
  return scene and scene.actors and scene.actors[side] or nil
end

local function selectedActor()
  return actorForSide(selectedSide)
end

local function koffingActor()
  -- Compatibility name retained for the legacy visual entry point. FX
  -- inspection follows the currently selected model.
  local actor = selectedActor()
  return actor and actor.renderer and actor or nil
end

local function applyDebugControls()
  for side, actor in pairs(scene and scene.actors or {}) do
    local renderer = actor and actor.renderer
    if renderer then
      renderer.debugSuppressDynamicObjects = side == selectedSide and suppressGasDraw or false
      renderer.debugOnlyPrimitive = side == selectedSide and isolatePrimitive > 0
        and isolatePrimitive or nil
    end
  end
end

local function ensureForcedGas()
  local actor = koffingActor()
  local renderer = actor and actor.renderer
  if not renderer then return end
  if not forceGas then
    local dynamic = renderer.handlerState and renderer.handlerState.dynamicObjectsBySite or {}
    for _, effect in pairs(dynamic or {}) do
      for _, emitter in ipairs(effect.emitters or {}) do
        local particle = emitter.particles and emitter.particles[10]
        if particle and particle._debugForced then emitter.particles[10] = nil end
      end
    end
    return
  end
  local model = renderer and renderer.model
  local extension = model and model.handlers
  if not (renderer and extension and type(extension.records) == "table") then return end
  renderer.handlerState = type(renderer.handlerState) == "table" and renderer.handlerState or {}
  renderer.handlerState.dynamicObjectsBySite = type(renderer.handlerState.dynamicObjectsBySite) == "table"
    and renderer.handlerState.dynamicObjectsBySite or {}
  local record
  for _, row in ipairs(extension.records) do
    if row.descriptor == 0x81000070 then record = row break end
  end
  if not record then return end
  local site = tonumber(record.commandOffset)
  if not site then return end
  local effect = renderer.handlerState.dynamicObjectsBySite[site]
  if type(effect) ~= "table" then
    local profile = DynamicObject and DynamicObject.profile(actor.dex)
    if not profile then return end
    effect = { family = (actor.dex == 109 or actor.dex == 110) and "koffing-gas" or "dynamic-object",
      kind = profile.name:lower() .. "-fx", species = actor.dex, profile = profile,
      particles = {}, textureSlots = {} }
    renderer.handlerState.dynamicObjectsBySite[site] = effect
  end
  effect.family = (actor.dex == 109 or actor.dex == 110) and "koffing-gas" or "dynamic-object"
  effect.species = actor.dex
  effect.profile = DynamicObject and DynamicObject.profile(actor.dex) or effect.profile
  effect.geometry = record.program and record.program.geometry or effect.geometry
  effect.textureSlots = {}
  for i, texture in ipairs(record.program and record.program.textures or {}) do
    effect.textureSlots[i] = (tonumber(texture.slot) or -1) + 1
  end
  effect.emitters = type(effect.emitters) == "table" and effect.emitters or {}
  local sources = renderer.handlerRuntime and renderer.handlerRuntime.dynamicObjectEmitters or {}
  for i, source in ipairs(sources) do
    local emitter = effect.emitters[i]
    if type(emitter) ~= "table" then
      emitter = { index = i - 1, particles = {} }
      effect.emitters[i] = emitter
    end
    emitter.bone, emitter.origin, emitter.reference = source.bone, source.origin, source.reference
    emitter.particles = emitter.particles or {}
    local origin = emitter.origin or {0,0,0}
    local init = effect.profile and DynamicObject.INITIALIZERS[effect.profile.routes.initialize]
    local scale = init and init.initialScale or 1
    emitter.particles[10] = {
      active = true, age = forceGasAge,
      x = origin[1] or 0, y = origin[2] or 0, z = origin[3] or 0,
      vx = 0, vy = 0, vz = 0, sx = scale, sy = scale, sz = scale, scale = scale, absolute = true,
      _debugForced = true,
    }
  end
  effect.particles = effect.emitters[1] and effect.emitters[1].particles or effect.particles
end

local function gasSnapshot()
  local actor = koffingActor()
  local renderer = actor and actor.renderer
  if not renderer then return { status = "selected renderer unavailable" } end
  local runtime = renderer.handlerRuntime or {}
  local dynamic = renderer.handlerState and renderer.handlerState.dynamicObjectsBySite or {}
  local active, site, ages, frames = 0, nil, {}, {}
  for key, effect in pairs(dynamic or {}) do
    if effect.family == "koffing-gas" or effect.family == "dynamic-object" then
      site = key
      for _, emitter in ipairs(effect.emitters or {}) do
        for i = 1, 10 do
          local particle = emitter.particles and emitter.particles[i]
          if particle and particle.active then
            active = active + 1
            ages[#ages + 1] = tostring(particle.age)
            local frame = math.floor((tonumber(particle.age) or 0) / 2) + 1
            frames[#frames + 1] = tostring(frame)
          end
        end
      end
    end
  end
  local emitterCount = #(renderer.handlerRuntime and renderer.handlerRuntime.dynamicObjectEmitters or {})
  local anchor = site and dynamic[site] and dynamic[site].emitters
    and dynamic[site].emitters[1] and dynamic[site].emitters[1].origin or nil
  local textureInfo = "none"
  for _, record in ipairs(renderer.model and renderer.model.handlers and renderer.model.handlers.records or {}) do
    if record.descriptor == 0x81000070 then
      local row = record.program and record.program.textures and record.program.textures[1]
      if row then
        textureInfo = tostring(row.w) .. "x" .. tostring(row.h) .. " fmt="
          .. tostring(row.format) .. " siz=" .. tostring(row.size)
      end
      break
    end
  end
  return {
    status = "ok", active = active, site = site, ages = table.concat(ages, ","),
    frames = table.concat(frames, ","), anchor = anchor, runtime = runtime,
    context = actor.context, sourceFrame = renderer.frame, callbackFrame = actor.callbackFrame,
    emitterCount = emitterCount,
    textureInfo = textureInfo, suppressGasDraw = suppressGasDraw, isolatePrimitive = isolatePrimitive,
  }
end

local function printGasSnapshot()
  local d = gasSnapshot()
  print("[stadium2-visual-test] GAS status=" .. tostring(d.status)
    .. " active=" .. tostring(d.active) .. " site=" .. tostring(d.site)
    .. " ages=" .. tostring(d.ages) .. " texFrames=" .. tostring(d.frames)
    .. " context=" .. tostring(d.context) .. " sourceFrame=" .. tostring(d.sourceFrame)
    .. " callbackFrame=" .. tostring(d.callbackFrame))
  print("[stadium2-visual-test] EMITTERS count=" .. tostring(d.emitterCount))
  local r = d.runtime or {}
  print("[stadium2-visual-test] RUNTIME dynamicObjectIndex=" .. tostring(r.dynamicObjectIndex)
    .. " animationState=" .. tostring(r.animationState) .. " animationFrame=" .. tostring(r.animationFrame)
    .. " dynamicObjectEnabled=" .. tostring(r.dynamicObjectEnabled)
    .. " dynamicObjectUpdateEnabled=" .. tostring(r.dynamicObjectUpdateEnabled))
  print("[stadium2-visual-test] TEXTURE " .. tostring(d.textureInfo)
    .. " suppressGasDraw=" .. tostring(suppressGasDraw)
    .. " isolatePrimitive=" .. tostring(isolatePrimitive))
  if d.anchor then
    print(("[stadium2-visual-test] ANCHOR %.6f %.6f %.6f"):format(d.anchor[1] or 0,d.anchor[2] or 0,d.anchor[3] or 0))
  end
end

local function makeScene(resetView)
  if scene then scene:release() end
  if resetView ~= false then
    Camera.recentre()
    Camera.reset()
    local initialOrbit = tonumber(os.getenv("STADIUM2_VISUAL_ORBIT"))
    if initialOrbit then
      Camera.orbit(initialOrbit)
      Camera.update(1)
    end
  end
  local nextScene = Presentation.newScene({ warn = warn, label = "Stadium 2 model viewer" })
  nextScene.game = {
    world = {
      map = { def = { environment = "TOWN" } },
      clockHour = 12,
      daytime = "DAY",
    },
  }
  local enemyOk = Presentation.setBattler(nextScene, "enemy", nil,
    { species = enemyDex, shiny = false }, enemyDex)
  local playerOk = Presentation.setBattler(nextScene, "player", nil,
    { species = playerDex, shiny = false }, playerDex)
  if not enemyOk or not playerOk then
    nextScene:release()
    scene = nil
    loadError = ("could not load Stadium packs: enemy=%03d %s player=%03d %s\ncache=%s")
      :format(enemyDex, tostring(enemyOk), playerDex, tostring(playerOk),
        love.filesystem.getSaveDirectory() .. "/stadium2_importer")
    warn(loadError)
    return false
  end
  scene = nextScene
  applyDebugControls()
  loadError = nil
  local enemy = actorForSide("enemy")
  local player = actorForSide("player")
  warn(("READY enemy=%03d shader=%s player=%03d shader=%s cache=%s")
    :format(enemyDex, tostring(enemy and enemy.renderer and enemy.renderer.shaderTier),
      playerDex, tostring(player and player.renderer and player.renderer.shaderTier),
      tostring(Importer and Importer.FORMAT)))
  for side, actor in pairs(scene.actors or {}) do
    local renderer = actor and actor.renderer
    if renderer and renderer.shaderError then
      warn(("SHADER_ERROR side=%s dex=%03d %s")
        :format(tostring(side), tonumber(actor.dex) or 0, tostring(renderer.shaderError)))
    end
  end
  return true
end

local function setSelectedSpecies(value)
  if selectedSide == "enemy" then enemyDex = wrapSpecies(value)
  else playerDex = wrapSpecies(value) end
  isolatePrimitive = 0
  return makeScene(false)
end

local function cycleSelectedSpecies(delta)
  local current = selectedSide == "enemy" and enemyDex or playerDex
  return setSelectedSpecies(current + (tonumber(delta) or 0))
end

local function cycleSelectedAnimation(delta)
  local actor = selectedActor()
  local renderer = actor and actor.renderer
  local animations = renderer and renderer.model and renderer.model.anims
  if not (renderer and type(animations) == "table" and #animations > 0) then return false end
  local index = ((renderer.animIndex or 1) - 1 + (tonumber(delta) or 0)) % #animations + 1
  return renderer:setAnimation(index, true)
end

local function initialise()
  -- LOVE's distro boot scripts do not all honor conf.lua's appendidentity
  -- field.  Select it explicitly before SaveData or Storage touches the
  -- filesystem so a source-launched harness shares the packaged game cache.
  if love.filesystem and love.filesystem.setIdentity then
    love.filesystem.setIdentity("pokemon-love2d",
      os.getenv("STADIUM2_VISUAL_APPEND_IDENTITY") == "1")
  end
  root = findRoot()
  if not root then
    loadError = "could not find the gen1recomp root; run this from the gen1recomp directory or set GEN1RECOMP_ROOT"
    return
  end
  installRepoLoader(root)
  local ok, result = pcall(function()
    Importer = require("mods.STADIUM2_IMPORTER.lib.importer")
    local handle, contextOrError = bindPlaythroughStorage(root)
    if not handle then error(contextOrError, 0) end
    Importer.bind(handle)
    Importer.setPlaythroughReady(true)
    warn(("CACHE_SCOPE game=%s playthrough=%s root=%s")
      :format(tostring(contextOrError.gameVersion),
        tostring(contextOrError.playthroughId), tostring(contextOrError.dataRoot)))
    Presentation = require("mods.STADIUM2_IMPORTER.lib.battle_presentation")
    Camera = require("mods.STADIUM2_IMPORTER.lib.battle_camera")
    DynamicObject = require("mods.STADIUM2_IMPORTER.lib.effects.dynamic_object")
    local shadowBias=tonumber(os.getenv("STADIUM2_VISUAL_SHADOW_BIAS"))
    if os.getenv("STADIUM2_VISUAL_DISABLE_SUN_SHADOW") == "1" or shadowBias then
      local Shadow=require("mods.STADIUM2_IMPORTER.lib.battle_shadow")
      if shadowBias then Shadow.bias=shadowBias end
      if os.getenv("STADIUM2_VISUAL_DISABLE_SUN_SHADOW") == "1" then
      Shadow.begin=function() return nil end
      end
    end
    Importer.configure({ count = 251 })
    if not Importer.available(251) then
      local started, err = Importer.autoImport()
      if not started then error(err or "Stadium 2 cache is stale and automatic re-import failed") end
      importing = Importer.status().state == "building"
      if importing then return true end
    end
    return makeScene()
  end)
  if not ok then loadError = tostring(result); warn(loadError) end
end

local function drawText(g)
  local selected = selectedActor()
  local renderer = selected and selected.renderer
  local model = renderer and renderer.model or {}
  local animations = model.anims or {}
  local animation = animations[renderer and renderer.animIndex or 0]
  local authoredTextures, neutralTextures, resolvedTextures = 0, 0, 0
  for _, prim in ipairs(model.prims or {}) do
    if prim.sourceTextureMissing then neutralTextures = neutralTextures + 1
    else authoredTextures = authoredTextures + 1 end
    if renderer and renderer:currentTexture(prim) then resolvedTextures = resolvedTextures + 1 end
  end
  local enemyMark = selectedSide == "enemy" and "> " or "  "
  local playerMark = selectedSide == "player" and "> " or "  "
  g.setColor(0, 0, 0, .72)
  local panelHeight = help and (debugPanel and 256 or 134) or (debugPanel and 192 or 52)
  g.rectangle("fill", 12, 12, 430, panelHeight, 6, 6)
  g.setColor(1, 1, 1, 1)
  g.print(enemyMark .. "Enemy species #" .. string.format("%03d", enemyDex), 24, 22)
  g.print(playerMark .. "Player species #" .. string.format("%03d", playerDex), 24, 40)
  if help then
    g.print("TAB select side   LEFT/RIGHT species   UP/DOWN +/-10", 24, 62)
    g.print("Drag mouse orbit/pitch   Wheel zoom", 24, 80)
    g.print("Q/E animation   R recenter   SPACE pause", 24, 98)
    g.print("G force selected FX   [ / ] age   X suppress FX draw", 24, 116)
    g.print("0 all primitives   1-9 isolate   V shader   S shot   H/D/P debug", 24, 134)
  end
  if debugPanel then
    local d = gasSnapshot()
    local y = help and 158 or 62
    g.print(("Selected %s #%03d  bones:%d prims:%d textures:%d"):format(
      selectedSide, selected and selected.dex or 0, #(model.bones or {}),
      #(model.prims or {}), #(model.textures or {})), 24, y)
    g.print(("Animation %d/%d %s  frame:%s/%s"):format(
      renderer and renderer.animIndex or 0, #animations,
      tostring(animation and animation.name or "bind pose"),
      tostring(renderer and renderer.frame or 0), tostring(animation and animation.frames or 0)), 24, y + 18)
    g.print("Primitive: " .. (isolatePrimitive == 0 and "all" or tostring(isolatePrimitive))
      .. "  paused: " .. tostring(paused), 24, y + 36)
    g.print("Dynamic FX: " .. tostring(d.active or 0) .. "  emitters: "
      .. tostring(d.emitterCount or 0) .. "  age: " .. tostring(forceGasAge), 24, y + 54)
    g.print("FX forced: " .. tostring(forceGas) .. "  suppressed: "
      .. tostring(suppressGasDraw), 24, y + 72)
    g.print("Callback texture: " .. tostring(d.textureInfo or "none"), 24, y + 90)
    g.print(("Textures: %d authored + %d neutral; resolved %d/%d; shader %s/%s; cache %s")
      :format(authoredTextures, neutralTextures, resolvedTextures, #(model.prims or {}),
        tostring(renderer and renderer.shaderTier or "none"),
        tostring(renderer and renderer:currentShaderStyle() or shaderStyle),
        tostring(Importer and Importer.FORMAT or "?")), 24, y + 108)
  end
  if screenshotMessage then
    local width = g.getWidth()
    g.setColor(0, 0, 0, .72)
    g.rectangle("fill", 12, g.getHeight() - 42, width - 24, 30, 6, 6)
    g.setColor(1, 1, 1, 1)
    g.print(screenshotMessage, 24, g.getHeight() - 34)
  end
end

function love.load()
  love.graphics.setDefaultFilter("nearest", "nearest")
  initialise()
end

function love.update(dt)
  if screenshotTimer > 0 then
    screenshotTimer = screenshotTimer - dt
    if screenshotTimer <= 0 then screenshotMessage = nil end
  end
  if autoCapture and not importing and scene and not loadError then
    autoCaptureFrames = autoCaptureFrames + 1
    if autoCaptureFrames == autoCaptureAt then
      if autoCapture:sub(1,1)=="/" then
        love.graphics.captureScreenshot(function(imageData)
          local encoded=imageData:encode("png")
          local file=assert(io.open(autoCapture,"wb"))
          file:write(encoded:getString());file:close()
        end)
      else
        love.graphics.captureScreenshot(autoCapture)
      end
    elseif autoCaptureFrames >= autoCaptureAt + 2 then
      love.event.quit()
    end
  end
  if importing and Importer then
    Importer.step()
    local status = Importer.status()
    if status.state == "ready" then
      importing = false
      makeScene()
    elseif status.state == "failed" then
      importing = false
      loadError = status.error or "Stadium 2 cache rebuild failed"
    end
    return
  end
  if scene and not autoKeysApplied then
    autoKeysApplied = true
    for key in tostring(autoKeys or ""):gmatch("[^,%s]+") do love.keypressed(key) end
  end
  if scene and not paused then
    Camera.update(dt)
    for _, actor in pairs(scene.actors or {}) do actor:update(dt) end
    applyDebugControls()
    ensureForcedGas()
    local ok = scene:render()
    if not ok then loadError = scene.defect or "battle scene render failed" end
  elseif scene then
    applyDebugControls()
    ensureForcedGas()
    local ok = scene:render()
    if not ok then loadError = scene.defect or "battle scene render failed" end
  end
end

function love.draw()
  local g = love.graphics
  g.clear(.03, .03, .04, 1)
  if importing and Importer then
    local status = Importer.status()
    g.setColor(1,1,1,1)
    g.printf(("Building Stadium 2 model viewer cache\n\n%s  %d/%d"):format(
      tostring(status.phase or status.state), tonumber(status.done) or 0, tonumber(status.total) or 251),
      40, 60, math.max(100, g.getWidth() - 80))
  elseif scene and scene.presentCanvas then
    local canvas = scene.presentCanvas
    local cw, ch = canvas:getDimensions()
    local ww, wh = g.getDimensions()
    g.setColor(1, 1, 1, 1)
    g.draw(canvas, 0, 0, 0, ww / cw, wh / ch)
    drawText(g)
  elseif loadError then
    g.setColor(1, 1, 1, 1)
    g.printf("Stadium 2 model viewer\n\n" .. loadError ..
      "\n\nExpected cache:\n" .. love.filesystem.getSaveDirectory() .. "/stadium2_importer",
      40, 60, math.max(100, g.getWidth() - 80))
  end
end

function love.keypressed(key)
  if key == "escape" then
    love.event.quit()
  elseif key == "tab" and Presentation then
    selectedSide = selectedSide == "enemy" and "player" or "enemy"
    isolatePrimitive = 0
    applyDebugControls()
  elseif key == "left" and scene then
    cycleSelectedSpecies(-1)
  elseif key == "right" and scene then
    cycleSelectedSpecies(1)
  elseif key == "up" and scene then
    cycleSelectedSpecies(10)
  elseif key == "down" and scene then
    cycleSelectedSpecies(-10)
  elseif key == "home" and scene then
    setSelectedSpecies(1)
  elseif key == "end" and scene then
    setSelectedSpecies(251)
  elseif key == "q" or key == "pageup" then
    cycleSelectedAnimation(-1)
  elseif key == "e" or key == "pagedown" then
    cycleSelectedAnimation(1)
  elseif key == "r" and Camera then
    Camera.recentre()
    Camera.reset()
  elseif key == "space" then
    paused = not paused
  elseif key == "h" then
    help = not help
  elseif key == "g" then
    forceGas = not forceGas
    printGasSnapshot()
  elseif key == "[" then
    forceGasAge = math.max(0, forceGasAge - 1)
    printGasSnapshot()
  elseif key == "]" then
    forceGasAge = math.min(15, forceGasAge + 1)
    printGasSnapshot()
  elseif key == "x" then
    suppressGasDraw = not suppressGasDraw
    applyDebugControls()
    printGasSnapshot()
  elseif key == "0" then
    isolatePrimitive = 0
    applyDebugControls()
  elseif key:match("^[1-9]$") then
    isolatePrimitive = tonumber(key) or 0
    applyDebugControls()
  elseif key == "d" then
    debugPanel = not debugPanel
  elseif key == "v" then
    shaderStyle = shaderStyle == "cel" and "stadium" or "cel"
  elseif key == "p" then
    printGasSnapshot()
  elseif key == "s" then
    local name = ("stadium2-models-%03d-vs-%03d.png"):format(enemyDex, playerDex)
    love.graphics.captureScreenshot(name)
    screenshotMessage = "saved " .. love.filesystem.getSaveDirectory() .. "/" .. name
    screenshotTimer = 5
    print("[stadium2-visual-test] " .. screenshotMessage)
  end
end

function love.mousemoved(x, y, dx, dy)
  if Camera and love.mouse.isDown(1) then
    Camera.mouseOrbit(dx)
    Camera.mousePitch(dy)
  end
end

function love.wheelmoved(x, y)
  if Camera and y ~= 0 then Camera.stepZoom(y) end
end

function love.quit()
  if scene then scene:release() end
  if Importer then Importer.releaseModels() end
end
