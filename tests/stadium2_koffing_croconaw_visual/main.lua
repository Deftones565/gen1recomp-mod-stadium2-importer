local scene
local Importer
local Presentation
local Camera
local DynamicObject
local TagFile
local ArenaRom
local ArenaFragment
local ArenaHandlers
local ArenaMaterials
local ArenaPack
local BattleFxPreview
local BattleFxPack
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
local rapidashCutEffect = os.getenv("STADIUM2_VISUAL_RAPIDASH_CUT_FX") ~= "0"
local rapidashButtonHeld = false
local arenaButtonHeld = false
local cameraButtonHeld = false
local battleFxButtonHeld = false
local arenaSceneEnabled = os.getenv("STADIUM2_VISUAL_SCENE") ~= "classic"
local arenaIndex = math.max(0, math.min(29,
  math.floor(tonumber(os.getenv("STADIUM2_VISUAL_ARENA")) or 0)))
local arenaScale = tonumber(os.getenv("STADIUM2_VISUAL_ARENA_SCALE")) or 0.05
local arenaYOffset = tonumber(os.getenv("STADIUM2_VISUAL_ARENA_Y")) or 0
local arenaRomData
local arenaArchive
local arenaRenderer
local arenaModel
local arenaSource
local arenaError
local arenaUnhook
local battleFxUnhook
local battleFxBackgroundUnhook
local battleFxMove=math.max(1,math.min(251,
  math.floor(tonumber(os.getenv("STADIUM2_VISUAL_MOVE_FX")) or 7)))
local battleFx={active=false,frame=0,error=nil,
  alternate=os.getenv("STADIUM2_VISUAL_FX_ALTERNATE")=="1"}
local tagData
local tagFilePath
local tagEditing = false
local tagInput = ""

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
      if key == "stadium2_rapidash_cut_fx" then return rapidashCutEffect end
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

local function standaloneViewerMod(base)
  local Storage = require("src.mods.Storage")
  local modPath = base .. "/mods/STADIUM2_IMPORTER"
  local game = { save = {
    version = "stadium2_viewer",
    meta = { playthroughId = "standalone" },
  } }
  return {
    path = modPath,
    game = game,
    storage = Storage.new("STADIUM2_IMPORTER_VIEWER", love.filesystem),
    options = { get = function(_, key)
      if key == "stadium2_shader" then return shaderStyle end
      if key == "stadium2_rapidash_cut_fx" then return rapidashCutEffect end
    end },
    read = function(_, relative)
      relative = tostring(relative or "")
      if relative == "" or relative:sub(1, 1) == "/"
          or relative:find("..", 1, true) then
        return nil
      end
      local file = io.open(modPath .. "/" .. relative, "rb")
      if not file then return nil end
      local bytes = file:read("*a")
      file:close()
      return bytes
    end,
  }
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

local function showMessage(message)
  screenshotMessage = tostring(message)
  screenshotTimer = 7
  print("[stadium2-visual-test] " .. screenshotMessage)
end

local function arenaName(index)
  return ("arena_%02d"):format(tonumber(index) or 0)
end

local function loadArenaSource()
  local supplied = os.getenv("STADIUM2_VISUAL_ROM")
  local romPath = supplied and supplied ~= "" and supplied
    or (root .. "/mods/STADIUM2_IMPORTER/baseroms/stadium2.z64")
  local file = io.open(romPath, "rb")
  if file then
    local raw = assert(file:read("*a"))
    file:close()
    local normalized, normaliseError = ArenaRom.normalise(raw)
    if not normalized then return false, normaliseError end
    if #normalized ~= ArenaRom.SIZE
        or ArenaRom.title(normalized):upper() ~= ArenaRom.US_TITLE then
      return false, "STADIUM2_VISUAL_ROM is not the supported Stadium 2 US ROM"
    end
    local archive = ArenaRom.archiveAt(normalized, ArenaRom.STADIUM_MODEL_TABLE_START)
    if not archive or archive.count ~= ArenaRom.STADIUM_MODEL_TABLE_RECORDS then
      return false, "the Stadium field archive is unavailable"
    end
    arenaRomData, arenaArchive, arenaSource = normalized, archive, romPath
    return true
  end

  local dump = root .. "/mods/STADIUM2_IMPORTER/stadium2_arena_dump"
  local fragmentPath = dump .. "/arena_00/arena_00.fragment"
  if not fileExists(fragmentPath) then
    return false, "no Stadium 2 ROM or stadium2_arena_dump was found"
  end
  arenaSource = dump
  return true
end

local function arenaBytes(index)
  if arenaRomData and arenaArchive then
    local record = arenaArchive.records[index + 1]
    local packed = record and ArenaRom.recordBytes(arenaRomData, record)
    if not packed then return nil, "arena archive record is unavailable" end
    return ArenaRom.decompress(packed)
  end
  if not arenaSource then return nil, "arena source is unavailable" end
  local name = arenaName(index)
  local path = arenaSource .. "/" .. name .. "/" .. name .. ".fragment"
  local file, err = io.open(path, "rb")
  if not file then return nil, err end
  local bytes = assert(file:read("*a"))
  file:close()
  return bytes
end

local function loadArena(index)
  index = math.floor(tonumber(index) or 0) % 30
  local decoded, decodeError = arenaBytes(index)
  if not decoded then
    arenaError = tostring(decodeError)
    return false, arenaError
  end
  ArenaFragment.setBase(0x8FF00000)
  local model, extractError = ArenaFragment.extractStage(decoded, arenaName(index), index)
  if not model then
    arenaError = tostring(extractError)
    return false, arenaError
  end
  -- The shared live renderer uses one uniform root-scale value. Stadium's
  -- field archive authors the same 0.5 value on all three axes.
  if type(model.rootScale) == "table" then
    model.rootScaleVector = model.rootScale
    model.rootScale = tonumber(model.rootScale[1]) or 1
  end
  model.staticPose = true
  model.handlers = ArenaHandlers.readExtension(ArenaHandlers.packExtension(
    ArenaHandlers.compile(model.fx, decoded, 0x8FF00000), 0x8FF00000,
    decoded, { prims = model.prims, handlerTextures = model.handlerTextures }))
  ArenaMaterials.attach(model)
  -- Fragment extraction uses N64/OBJ-style zero-based slots. The live LOVE
  -- renderer consumes the same one-based contract as parsed DSM packs.
  for _, primitive in ipairs(model.prims or {}) do
    primitive.tex = primitive.tex and primitive.tex >= 0
      and primitive.tex + 1 or 0x10000
    primitive.additive = primitive.blend == "add"
    for i, vertexIndex in ipairs(primitive.idx or {}) do
      primitive.idx[i] = vertexIndex + 1
    end
    for key, textureIndex in pairs(primitive.texMap or {}) do
      primitive.texMap[key] = textureIndex + 1
    end
    for i, textureIndex in ipairs(primitive.fxFrames or {}) do
      primitive.fxFrames[i] = textureIndex + 1
    end
  end
  local renderer, rendererError = Importer.newRendererFromModel(model, {
    shaderStyleProvider = function() return shaderStyle end,
    textureFilter = "nearest",
  })
  if not renderer then
    arenaError = tostring(rendererError)
    return false, arenaError
  end
  if arenaRenderer and arenaRenderer.release then pcall(arenaRenderer.release, arenaRenderer) end
  if arenaModel then ArenaPack.release(arenaModel) end
  arenaIndex, arenaModel, arenaRenderer, arenaError = index, model, renderer, nil
  warn(("ARENA_READY index=%02d prims=%d textures=%d source=%s")
    :format(index, #model.prims, #model.textures, tostring(arenaSource)))
  return true
end

local function cycleArena(delta)
  local nextIndex = (arenaIndex + (tonumber(delta) or 0)) % 30
  local ok, err = loadArena(nextIndex)
  if ok then showMessage(("Stadium field %02d/29"):format(arenaIndex))
  else showMessage("arena swap failed: " .. tostring(err)) end
  return ok
end

local function cycleCameraMode(delta)
  if not Camera then return false end
  Camera.setArenaTarget(selectedSide)
  Camera.cycleArenaMode(delta)
  showMessage("Stadium camera " .. Camera.arenaModeLabel()
    .. " / " .. selectedSide)
  return true
end

local function arenaModelMatrix()
  local scale = arenaScale
  return {
    scale, 0, 0, 0,
    0, scale, 0, arenaYOffset,
    0, 0, scale, 0,
    0, 0, 0, 1,
  }
end

local function drawArena(nextDraw, context)
  if not arenaSceneEnabled or not arenaRenderer then return nextDraw() end
  local environment = context.environment or {}
  local shadow = context.shadow or {}
  local matrix = arenaModelMatrix()
  arenaRenderer.debugOnlyPrimitive = isolatePrimitive > 0 and isolatePrimitive or nil
  local options = {
    viewProjection = context.camera and context.camera.vp,
    viewMatrix = context.camera and context.camera.view,
    normalMatrix = {1,0,0, 0,1,0, 0,0,1},
    lightDir = environment.light,
    ambient = environment.ambient,
    diffuse = environment.diffuse,
    modernLighting = true,
    tint = {1,1,1,1},
    flipWinding = true,
    sunMap = shadow.map,
    sunVP = shadow.sunVP,
    sunDark = shadow.sunDark,
    sunBias = shadow.sunBias,
    sunTexel = shadow.sunTexel,
  }
  local drawn, err = arenaRenderer:drawScene("opaque", matrix, options)
  if drawn then drawn, err = arenaRenderer:drawScene("additive", matrix, options) end
  if not drawn then
    arenaError = tostring(err)
    warn("ARENA_DRAW_FAILED " .. arenaError)
    return nextDraw()
  end
  return context.marks
end

local function installArenaHook()
  local Runtime = require("src.mods.Runtime")
  if type(Runtime.hooks.wrap) ~= "function" then
    local Hooks = require("src.mods.Hooks")
    Runtime.install(Runtime.events, Hooks.new(), Runtime.errors)
  end
  arenaUnhook = Runtime.hooks:wrap("battle.scene.environment.v1",
    drawArena, 1000, "stadium2-arena-visual")
end

local function releaseBattleFx()
  if battleFx.preview then battleFx.preview:release() end
  battleFx.active=false
end

local function startBattleFx()
  releaseBattleFx()
  battleFx.error=nil
  if not battleFx.preview then
    battleFx.preview=BattleFxPreview.new({rom=arenaRomData, importer=Importer,
      releaseModel=BattleFxPack.release,
      shaderStyleProvider=function() return shaderStyle end,
      warn=function(d)
        battleFx.error=tostring(d.code)..": "..tostring(d.message)
        warn("ROM_FX "..battleFx.error)
      end,
    })
  end
  local effect, err=battleFx.preview:start(battleFxMove, selectedSide,
    battleFx.alternate)
  battleFx.active=effect~=nil
  battleFx.frame=0
  if not effect then battleFx.error=tostring(err) end
  showMessage(effect and ("Playing ROM FX #%03d (%s)"):format(battleFxMove,
    battleFx.alternate and "alternate" or "primary")
    or "move FX unavailable: "..tostring(err))
  return battleFx.active
end

local function cycleBattleFx(delta)
  battleFxMove=((battleFxMove-1+(tonumber(delta) or 0))%251)+1
  return startBattleFx()
end

local function drawBattleFx(nextDraw,context)
  local result=nextDraw()
  if battleFx.active then battleFx.preview:draw(context) end
  return result
end

local function installBattleFxHook()
  local Runtime=require("src.mods.Runtime")
  if type(Runtime.hooks.wrap)~="function" then
    local Hooks=require("src.mods.Hooks")
    Runtime.install(Runtime.events,Hooks.new(),Runtime.errors)
  end
  battleFxUnhook=Runtime.hooks:wrap("battle.scene.geometry.v1",
    drawBattleFx,1100,"stadium2-rom-fx-visual")
  battleFxBackgroundUnhook=Runtime.hooks:wrap("battle.scene.background.v1",
    function(nextDraw,context)
      if battleFx.active then battleFx.preview:drawBackground(context) end
      return nextDraw()
    end,1100,"stadium2-rom-fx-background")
end

local function animationTagPath()
  local supplied = os.getenv("STADIUM2_ANIMATION_TAGS_EXPORT")
  if supplied and supplied ~= "" then return supplied end
  return love.filesystem.getSaveDirectory() .. "/stadium2_animation_tags.tsv"
end

local function loadAnimationTags()
  tagFilePath = animationTagPath()
  tagData = TagFile.new()
  if not fileExists(tagFilePath) then return true end
  local loaded, err = TagFile.load(tagFilePath)
  if not loaded then
    showMessage("could not read animation tags: " .. tostring(err))
    return false
  end
  tagData = loaded
  warn("ANIMATION_TAGS loaded " .. tagFilePath)
  return true
end

local function saveAnimationTags()
  if not (TagFile and tagData and tagFilePath) then return false end
  local ok, err = TagFile.save(tagFilePath, tagData)
  if not ok then
    showMessage("animation tag export failed: " .. tostring(err))
    return false
  end
  showMessage("animation tags saved: " .. tagFilePath)
  return true
end

local function syncTagCount(actor)
  local renderer = actor and actor.renderer
  local animations = renderer and renderer.model and renderer.model.anims
  if tagData and actor and type(animations) == "table" then
    TagFile.setCount(tagData, actor.dex, #animations)
  end
end

local function currentTagSelection()
  local actor = selectedActor()
  local renderer = actor and actor.renderer
  local animations = renderer and renderer.model and renderer.model.anims
  local luaIndex = renderer and renderer.animIndex or nil
  if not (actor and type(animations) == "table" and luaIndex and animations[luaIndex]) then
    return nil
  end
  local animation = animations[luaIndex]
  return actor.dex, luaIndex - 1, animation, #animations
end

local function currentTag()
  local species, index = currentTagSelection()
  return species and TagFile.get(tagData, species, index) or nil
end

local function tagProgress()
  local species, _, _, count = currentTagSelection()
  local current, total, visited = 0, 0, 0
  for dex = 1, 251 do
    local known = tagData and tagData.counts[dex]
    if known then total, visited = total + known, visited + 1 end
  end
  local rows = tagData and tagData.species or {}
  local tagged = 0
  for dex = 1, 251 do
    for index, tag in pairs(rows[dex] or {}) do
      if tag ~= "" and (not tagData.counts[dex] or index < tagData.counts[dex]) then
        tagged = tagged + 1
        if dex == species then current = current + 1 end
      end
    end
  end
  return current, count or 0, tagged, total, visited
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
  local nextScene = Presentation.newScene({
    warn = warn,
    label = "Stadium 2 model viewer",
    sceneMode = arenaSceneEnabled and arenaRenderer ~= nil and "arena" or "classic",
    arenaMode = arenaSceneEnabled and arenaRenderer ~= nil,
    arenaScale = arenaScale,
    arenaGroundY = arenaYOffset,
    arenaEnvironment = arenaModel and arenaModel.arenaLighting
      and arenaModel.arenaLighting.environment or nil,
  })
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
  syncTagCount(actorForSide("enemy"))
  syncTagCount(actorForSide("player"))
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

local function toggleSceneMode()
  if not arenaRenderer then
    showMessage("arena unavailable")
    return false
  end
  arenaSceneEnabled=not arenaSceneEnabled
  makeScene(false)
  showMessage(arenaSceneEnabled and "Arena battle scene" or "Classic battle scene")
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

local function advanceTagCursor()
  local _, index, _, count = currentTagSelection()
  if not index then return false end
  if index + 1 < count then return cycleSelectedAnimation(1) end
  return cycleSelectedSpecies(1)
end

local function commitAnimationTag(value, advance)
  local species, index = currentTagSelection()
  if not species then return false end
  local ok, err = TagFile.set(tagData, species, index, value)
  if not ok then
    showMessage("could not set animation tag: " .. tostring(err))
    return false
  end
  saveAnimationTags()
  if advance then advanceTagCursor() end
  return true
end

local function beginTagEdit()
  local _, _, animation = currentTagSelection()
  if not animation then return false end
  tagInput = currentTag() or tostring(animation.name or "")
  tagEditing = true
  if love.keyboard and love.keyboard.setTextInput then love.keyboard.setTextInput(true) end
  return true
end

local function finishTagEdit(save)
  if save then commitAnimationTag(tagInput, true) end
  tagEditing = false
  tagInput = ""
  if love.keyboard and love.keyboard.setTextInput then love.keyboard.setTextInput(false) end
end

local function removeLastCharacter(value)
  local length = #value
  if length == 0 then return value end
  repeat
    length = length - 1
  until length == 0 or value:byte(length + 1) < 128 or value:byte(length + 1) >= 192
  return value:sub(1, length)
end

local function compactMoveIds(moveIds)
  if type(moveIds) ~= "table" or #moveIds == 0 then return "none" end
  local out = {}
  local first, last = moveIds[1], moveIds[1]
  for index = 2, #moveIds + 1 do
    local value = moveIds[index]
    if value == last + 1 then
      last = value
    else
      out[#out + 1] = first == last and tostring(first)
        or (tostring(first) .. "-" .. tostring(last))
      first, last = value, value
    end
  end
  local text = table.concat(out, ",")
  return #text > 96 and (text:sub(1, 93) .. "...") or text
end

local function toggleRapidashCutEffect()
  rapidashCutEffect = not rapidashCutEffect
  for _, actor in pairs(scene and scene.actors or {}) do
    local renderer = actor and actor.renderer
    if renderer and renderer.setRapidashCutEffect then
      renderer:setRapidashCutEffect(rapidashCutEffect)
    end
  end
  warn("RAPIDASH_CUT_FX " .. (rapidashCutEffect and "ON" or "OFF"))
  return rapidashCutEffect
end

local function rapidashButtonBounds()
  local width, height = love.graphics.getDimensions()
  local buttonWidth = math.min(240, math.max(120, width - 24))
  return width - buttonWidth - 12, height - 50, buttonWidth, 36
end

local function drawRapidashButton(g)
  local x, y, width, height = rapidashButtonBounds()
  if rapidashCutEffect then g.setColor(.18, .55, .28, .94)
  else g.setColor(.12, .14, .19, .94) end
  g.rectangle("fill", x, y, width, height, 6, 6)
  g.setColor(.9, .93, 1, 1)
  g.printf("RAPIDASH CUT FX: " .. (rapidashCutEffect and "ON" or "OFF"),
    x, y + 9, width, "center")
end

local function arenaButtonBounds()
  local width = love.graphics.getWidth()
  local groupWidth = math.min(300, math.max(210, width - 470))
  local arrowWidth = 44
  local x, y, height = width - groupWidth - 12, 12, 36
  return x, y, arrowWidth, groupWidth - arrowWidth * 2, arrowWidth, height
end

local function drawArenaButtons(g)
  local x, y, previousWidth, labelWidth, nextWidth, height = arenaButtonBounds()
  g.setColor(.12, .14, .19, .94)
  g.rectangle("fill", x, y, previousWidth, height, 6, 6)
  g.rectangle("fill", x + previousWidth + labelWidth, y, nextWidth, height, 6, 6)
  g.setColor(arenaSceneEnabled and arenaRenderer and .14 or .28,
    arenaSceneEnabled and arenaRenderer and .38 or .16,
    arenaSceneEnabled and arenaRenderer and .60 or .16, .94)
  g.rectangle("fill", x + previousWidth + 3, y, labelWidth - 6, height, 6, 6)
  g.setColor(.9, .93, 1, 1)
  g.printf("<", x, y + 9, previousWidth, "center")
  g.printf(not arenaRenderer and "ARENA UNAVAILABLE"
      or arenaSceneEnabled and (("ARENA %02d / 29"):format(arenaIndex))
      or "CLASSIC SCENE",
    x + previousWidth, y + 9, labelWidth, "center")
  g.printf(">", x + previousWidth + labelWidth, y + 9, nextWidth, "center")
end

local function cameraButtonBounds()
  local x, _, previousWidth, labelWidth, nextWidth, height = arenaButtonBounds()
  return x, 56, previousWidth, labelWidth, nextWidth, height
end

local function drawCameraButtons(g)
  local x,y,previousWidth,labelWidth,nextWidth,height=cameraButtonBounds()
  g.setColor(.12,.14,.19,.94)
  g.rectangle("fill",x,y,previousWidth,height,6,6)
  g.rectangle("fill",x+previousWidth+labelWidth,y,nextWidth,height,6,6)
  g.setColor(.30,.22,.55,.94)
  g.rectangle("fill",x+previousWidth+3,y,labelWidth-6,height,6,6)
  g.setColor(.9,.93,1,1)
  g.printf("<",x,y+9,previousWidth,"center")
  local label=Camera and Camera.arenaModeLabel() or "FIELD"
  g.printf("CAMERA "..label,x+previousWidth,y+9,labelWidth,"center")
  g.printf(">",x+previousWidth+labelWidth,y+9,nextWidth,"center")
end

local function battleFxButtonBounds()
  local x,y,previousWidth,labelWidth,nextWidth,height=cameraButtonBounds()
  return x,y+44,previousWidth,labelWidth,nextWidth,height
end

local function drawBattleFxButtons(g)
  local x,y,previousWidth,labelWidth,nextWidth,height=battleFxButtonBounds()
  g.setColor(.12,.14,.19,.94)
  g.rectangle("fill",x,y,previousWidth,height,6,6)
  g.rectangle("fill",x+previousWidth+labelWidth,y,nextWidth,height,6,6)
  g.setColor(battleFx.active and .18 or .25,battleFx.active and .55 or .24,
    battleFx.active and .28 or .42,.94)
  g.rectangle("fill",x+previousWidth+3,y,labelWidth-6,height,6,6)
  g.setColor(.9,.93,1,1)
  g.printf("<",x,y+9,previousWidth,"center")
  g.printf(("FX %03d %s%s"):format(battleFxMove,
    battleFx.alternate and "ALT" or "PRI",
    battleFx.active and ("  %dF"):format(math.floor(battleFx.frame)) or ""),
    x+previousWidth,y+9,labelWidth,"center")
  g.printf(">",x+previousWidth+labelWidth,y+9,nextWidth,"center")
  if battleFx.preview and battleFx.active then
    g.printf(("Drawn: %d   Diagnostics: %d"):format(
      battleFx.preview.drawn or 0,#battleFx.preview.diagnostics),
      x,y+height+4,previousWidth+labelWidth+nextWidth,"right")
  end
  if battleFx.error then
    g.setColor(1,.72,.35,1)
    g.printf(battleFx.error,x,y+height+24,previousWidth+labelWidth+nextWidth,"left")
  end
  local color=battleFx.active and battleFx.preview and battleFx.preview.nativeColor
  if color then
    g.setColor(.9,.93,1,1)
    g.printf(("Native background RGBA: %d %d %d %d"):format(color[1],color[2],color[3],color[4]),
      x,y+height+64,previousWidth+labelWidth+nextWidth,"right")
  end
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
    if not handle then
      warn("CACHE_SCOPE selected playthrough unavailable: " .. tostring(contextOrError))
      handle = standaloneViewerMod(root)
      contextOrError = {
        gameVersion = "stadium2_viewer",
        playthroughId = "standalone",
        dataRoot = love.filesystem.getSaveDirectory(),
      }
    end
    Importer.bind(handle)
    Importer.setPlaythroughReady(true)
    warn(("CACHE_SCOPE game=%s playthrough=%s root=%s")
      :format(tostring(contextOrError.gameVersion),
        tostring(contextOrError.playthroughId), tostring(contextOrError.dataRoot)))
    Presentation = require("mods.STADIUM2_IMPORTER.lib.battle_presentation")
    Camera = require("mods.STADIUM2_IMPORTER.lib.battle_camera")
    DynamicObject = require("mods.STADIUM2_IMPORTER.lib.effects.dynamic_object")
    TagFile = require("mods.STADIUM2_IMPORTER.lib.animation_tag_file")
    ArenaRom = require("mods.STADIUM2_IMPORTER.lib.rom")
    ArenaFragment = require("mods.STADIUM2_IMPORTER.lib.fragment")
    ArenaHandlers = require("mods.STADIUM2_IMPORTER.lib.model_handlers")
    ArenaMaterials = require("mods.STADIUM2_IMPORTER.lib.materials")
    ArenaPack = require("mods.STADIUM2_IMPORTER.lib.pack")
    BattleFxPreview=require(
      "mods.STADIUM2_IMPORTER.tests.stadium2_koffing_croconaw_visual.battle_fx")
    BattleFxPack=ArenaPack
    loadAnimationTags()
    local shadowBias=tonumber(os.getenv("STADIUM2_VISUAL_SHADOW_BIAS"))
    if os.getenv("STADIUM2_VISUAL_DISABLE_SUN_SHADOW") == "1" or shadowBias then
      local Shadow=require("mods.STADIUM2_IMPORTER.lib.battle_shadow")
      if shadowBias then Shadow.bias=shadowBias end
      if os.getenv("STADIUM2_VISUAL_DISABLE_SUN_SHADOW") == "1" then
      Shadow.begin=function() return nil end
      end
    end
    Importer.configure({ count = 251 })
    local arenaSourceOk, arenaSourceError = loadArenaSource()
    if arenaSourceOk then
      installArenaHook()
      local arenaOk, loadArenaError = loadArena(arenaIndex)
      if not arenaOk then warn("ARENA_LOAD_FAILED " .. tostring(loadArenaError)) end
    else
      arenaError = tostring(arenaSourceError)
      warn("ARENA_UNAVAILABLE " .. arenaError)
    end
    installBattleFxHook()
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
  local manualTag = currentTag()
  local currentTagged, currentTotal, allTagged, allTotal, visited = tagProgress()
  local playbackState = paused and "PAUSED"
    or (renderer and renderer.finished and "FINISHED" or "PLAYING")
  local authoredTextures, neutralTextures, resolvedTextures = 0, 0, 0
  for _, prim in ipairs(model.prims or {}) do
    if prim.sourceTextureMissing then neutralTextures = neutralTextures + 1
    else authoredTextures = authoredTextures + 1 end
    if renderer and renderer:currentTexture(prim) then resolvedTextures = resolvedTextures + 1 end
  end
  local enemyMark = selectedSide == "enemy" and "> " or "  "
  local playerMark = selectedSide == "player" and "> " or "  "
  g.setColor(0, 0, 0, .72)
  local panelHeight = help and (debugPanel and 400 or 260) or (debugPanel and 264 or 124)
  g.rectangle("fill", 12, 12, 430, panelHeight, 6, 6)
  g.setColor(1, 1, 1, 1)
  g.print(enemyMark .. "Enemy species #" .. string.format("%03d", enemyDex), 24, 22)
  g.print(playerMark .. "Player species #" .. string.format("%03d", playerDex), 24, 40)
  g.print(("NOW %s  %d/%d  %s  frame:%s/%s"):format(
    playbackState, renderer and renderer.animIndex or 0, #animations,
    tostring(animation and animation.name or "bind pose"),
    tostring(renderer and renderer.frame or 0),
    tostring(animation and animation.frames or 0)), 24, 58)
  if tagEditing then
    g.setColor(1, .9, .35, 1)
    g.print("TAG EDIT> " .. tagInput .. "_", 24, 78)
  else
    g.setColor(manualTag and .45 or 1, manualTag and 1 or .75, .55, 1)
    g.print("TAG: " .. tostring(manualTag or "<untagged>")
      .. "   suggested: " .. tostring(animation and animation.name or "none"), 24, 78)
  end
  g.setColor(1, 1, 1, 1)
  g.print(("TAGGED %d/%d THIS MODEL   %d/%d VISITED CLIPS   SPECIES VISITED %d/251")
    :format(currentTagged, currentTotal, allTagged, allTotal, visited), 24, 98)
  if help then
    g.print("T edit tag   A accept suggested + next   DELETE clear tag", 24, 122)
    g.print("CTRL+S or F6 export tags   ENTER saves edits + next", 24, 140)
    g.print("TAB select side   LEFT/RIGHT species   UP/DOWN +/-10", 24, 158)
    g.print("Drag mouse orbit/pitch   Wheel zoom", 24, 176)
    g.print("Q/E animation   R recenter   SPACE pause", 24, 194)
    g.print("G force selected FX   [ / ] age   X suppress FX draw   F Rapidash FX", 24, 212)
    g.print("0 all primitives   1-9 isolate   ,/. arena   B scene   C camera   V shader   S shot", 24, 230)
    g.print("J/L move FX   K replay   O primary/alternate   N step FX (paused)   M stop",24,248)
  end
  if debugPanel then
    local d = gasSnapshot()
    local y = help and 272 or 134
    g.print(("Selected %s #%03d  bones:%d prims:%d textures:%d"):format(
      selectedSide, selected and selected.dex or 0, #(model.bones or {}),
      #(model.prims or {}), #(model.textures or {})), 24, y)
    g.print(("Animation %d/%d %s  frame:%s/%s"):format(
      renderer and renderer.animIndex or 0, #animations,
      tostring(animation and animation.name or "bind pose"),
      tostring(renderer and renderer.frame or 0), tostring(animation and animation.frames or 0)), 24, y + 18)
    g.print("ROM move IDs: " .. compactMoveIds(animation and animation.moveIds), 24, y + 36)
    g.print("Primitive: " .. (isolatePrimitive == 0 and "all" or tostring(isolatePrimitive))
      .. "  paused: " .. tostring(paused), 24, y + 54)
    g.print("Dynamic FX: " .. tostring(d.active or 0) .. "  emitters: "
      .. tostring(d.emitterCount or 0) .. "  age: " .. tostring(forceGasAge), 24, y + 72)
    g.print("FX forced: " .. tostring(forceGas) .. "  suppressed: "
      .. tostring(suppressGasDraw), 24, y + 90)
    g.print("Callback texture: " .. tostring(d.textureInfo or "none"), 24, y + 108)
    g.print(("Textures: %d authored + %d neutral; resolved %d/%d; shader %s/%s; cache %s")
      :format(authoredTextures, neutralTextures, resolvedTextures, #(model.prims or {}),
        tostring(renderer and renderer.shaderTier or "none"),
        tostring(renderer and renderer:currentShaderStyle() or shaderStyle),
        tostring(Importer and Importer.FORMAT or "?")), 24, y + 126)
  end
  if screenshotMessage then
    local width = g.getWidth()
    g.setColor(0, 0, 0, .72)
    g.rectangle("fill", 12, g.getHeight() - 42, width - 24, 30, 6, 6)
    g.setColor(1, 1, 1, 1)
    g.print(screenshotMessage, 24, g.getHeight() - 34)
  end
  drawArenaButtons(g)
  drawCameraButtons(g)
  drawBattleFxButtons(g)
  drawRapidashButton(g)
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
    if arenaRenderer then arenaRenderer:step(dt) end
    for _, actor in pairs(scene.actors or {}) do actor:update(dt) end
    if battleFx.active then
      battleFx.preview:update(dt)
      battleFx.frame=battleFx.preview.frame
    end
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
  if tagEditing then
    if key == "escape" then
      finishTagEdit(false)
    elseif key == "return" or key == "kpenter" then
      finishTagEdit(true)
    elseif key == "backspace" then
      tagInput = removeLastCharacter(tagInput)
    elseif key == "delete" then
      tagInput = ""
    end
    return
  end
  local control = love.keyboard and love.keyboard.isDown
    and love.keyboard.isDown("lctrl", "rctrl")
  if (key == "s" and control) or key == "f6" then
    saveAnimationTags()
  elseif key == "escape" then
    love.event.quit()
  elseif key == "tab" and Presentation then
    selectedSide = selectedSide == "enemy" and "player" or "enemy"
    if Camera then Camera.setArenaTarget(selectedSide) end
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
  elseif key == "," then
    cycleArena(-1)
  elseif key == "." then
    cycleArena(1)
  elseif key == "c" then
    cycleCameraMode(1)
  elseif key == "j" then
    cycleBattleFx(-1)
  elseif key == "k" then
    startBattleFx()
  elseif key == "l" then
    cycleBattleFx(1)
  elseif key == "o" then
    battleFx.alternate=not battleFx.alternate
    startBattleFx()
  elseif key == "n" and paused and battleFx.active then
    battleFx.preview:step()
    battleFx.frame=battleFx.preview.frame
  elseif key == "m" then
    releaseBattleFx()
  elseif key == "b" then
    toggleSceneMode()
  elseif key == "t" then
    beginTagEdit()
  elseif key == "a" then
    local _, _, animation = currentTagSelection()
    if animation then commitAnimationTag(animation.name or "", true) end
  elseif key == "delete" then
    commitAnimationTag("", false)
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
  elseif key == "f" then
    toggleRapidashCutEffect()
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
    showMessage("saved " .. love.filesystem.getSaveDirectory() .. "/" .. name)
  end
end

function love.textinput(text)
  if tagEditing then tagInput = tagInput .. tostring(text or "") end
end

function love.mousepressed(x, y, button)
  if button ~= 1 then return end
  local ax, ay, previousWidth, labelWidth, nextWidth, arenaHeight = arenaButtonBounds()
  if y >= ay and y <= ay + arenaHeight then
    if x >= ax and x <= ax + previousWidth then
      arenaButtonHeld = true
      cycleArena(-1)
      return
    end
    if x >= ax + previousWidth and x <= ax + previousWidth + labelWidth then
      arenaButtonHeld = true
      toggleSceneMode()
      return
    end
    local nextX = ax + previousWidth + labelWidth
    if x >= nextX and x <= nextX + nextWidth then
      arenaButtonHeld = true
      cycleArena(1)
      return
    end
  end
  local cx,cy,cPreviousWidth,cLabelWidth,cNextWidth,cameraHeight=cameraButtonBounds()
  if y>=cy and y<=cy+cameraHeight then
    if x>=cx and x<=cx+cPreviousWidth then
      cameraButtonHeld=true
      cycleCameraMode(-1)
      return
    end
    local cameraNextX=cx+cPreviousWidth+cLabelWidth
    if x>=cameraNextX and x<=cameraNextX+cNextWidth then
      cameraButtonHeld=true
      cycleCameraMode(1)
      return
    end
  end
  local fx,fy,fxPreviousWidth,fxLabelWidth,fxNextWidth,fxHeight=battleFxButtonBounds()
  if y>=fy and y<=fy+fxHeight then
    if x>=fx and x<=fx+fxPreviousWidth then
      battleFxButtonHeld=true
      cycleBattleFx(-1)
      return
    end
    if x>=fx+fxPreviousWidth and x<=fx+fxPreviousWidth+fxLabelWidth then
      battleFxButtonHeld=true
      startBattleFx()
      return
    end
    local nextX=fx+fxPreviousWidth+fxLabelWidth
    if x>=nextX and x<=nextX+fxNextWidth then
      battleFxButtonHeld=true
      cycleBattleFx(1)
      return
    end
  end
  local bx, by, width, height = rapidashButtonBounds()
  if x >= bx and y >= by and x <= bx + width and y <= by + height then
    rapidashButtonHeld = true
    toggleRapidashCutEffect()
  end
end

function love.mousereleased(_, _, button)
  if button == 1 then
    rapidashButtonHeld = false
    arenaButtonHeld = false
    cameraButtonHeld = false
    battleFxButtonHeld=false
  end
end

function love.mousemoved(x, y, dx, dy)
  if Camera and not rapidashButtonHeld and not arenaButtonHeld
      and not cameraButtonHeld and not battleFxButtonHeld and love.mouse.isDown(1) then
    Camera.mouseOrbit(dx)
    Camera.mousePitch(dy)
  end
end

function love.wheelmoved(x, y)
  if Camera and y ~= 0 then Camera.stepZoom(y) end
end

function love.quit()
  if tagData and tagFilePath then TagFile.save(tagFilePath, tagData) end
  if arenaUnhook then pcall(arenaUnhook); arenaUnhook = nil end
  if arenaRenderer and arenaRenderer.release then
    pcall(arenaRenderer.release, arenaRenderer)
    arenaRenderer = nil
  end
  if arenaModel and ArenaPack then ArenaPack.release(arenaModel); arenaModel = nil end
  if battleFxUnhook then pcall(battleFxUnhook); battleFxUnhook=nil end
  if battleFxBackgroundUnhook then pcall(battleFxBackgroundUnhook); battleFxBackgroundUnhook=nil end
  releaseBattleFx()
  if scene then scene:release() end
  if Importer then Importer.releaseModels() end
end
