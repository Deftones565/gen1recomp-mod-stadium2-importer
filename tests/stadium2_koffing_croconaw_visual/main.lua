local scene
local Importer
local Presentation
local Camera
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
local forceGas = os.getenv("STADIUM2_VISUAL_FORCE_GAS") == "1"
local forceGasAge = math.max(0, math.min(15,
  tonumber(os.getenv("STADIUM2_VISUAL_FORCE_GAS_AGE")) or 0))
local debugPanel = true
local suppressGasDraw = false
local isolatePrimitive = 0
local autoCapture = os.getenv("STADIUM2_VISUAL_AUTOCAPTURE")
local autoCaptureFrames = 0
local autoKeys = os.getenv("STADIUM2_VISUAL_AUTOKEYS")
local autoKeysApplied = false

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

local function installModLoader(base)
  local loaders = package.searchers or package.loaders
  table.insert(loaders, 2, function(name)
    local prefix = "mods.STADIUM2_IMPORTER"
    if name ~= prefix and name:sub(1, #prefix + 1) ~= prefix .. "." then return nil end
    local path = base .. "/" .. name:gsub("%.", "/") .. ".lua"
    if not fileExists(path) then return "\n\tmissing " .. path end
    local chunk, err = loadfile(path)
    if not chunk then return "\n\t" .. tostring(err) end
    return chunk
  end)
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
  if not scene or not scene.actors then return nil end
  for _, actor in pairs(scene.actors) do
    if actor and actor.dex == 109 and actor.renderer then return actor end
  end
  return nil
end

local function applyDebugControls()
  for side, actor in pairs(scene and scene.actors or {}) do
    local renderer = actor and actor.renderer
    if renderer then
      renderer.debugSuppressDynamicObjects = actor.dex == 109 and suppressGasDraw or false
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
    effect = { family = "koffing-gas", species = 109, particles = {}, textureSlots = {} }
    renderer.handlerState.dynamicObjectsBySite[site] = effect
  end
  effect.family = "koffing-gas"
  effect.species = 109
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
    emitter.particles[10] = {
      active = true, age = forceGasAge,
      x = origin[1] or 0, y = origin[2] or 0, z = origin[3] or 0,
      vx = 0, vy = 0, vz = 0, sx = 1, sy = 1, sz = 1, scale = 1, absolute = true,
      _debugForced = true,
    }
  end
  effect.particles = effect.emitters[1] and effect.emitters[1].particles or effect.particles
end

local function gasSnapshot()
  local actor = koffingActor()
  local renderer = actor and actor.renderer
  if not renderer then return { status = "Koffing renderer unavailable" } end
  local runtime = renderer.handlerRuntime or {}
  local dynamic = renderer.handlerState and renderer.handlerState.dynamicObjectsBySite or {}
  local active, site, ages, frames = 0, nil, {}, {}
  for key, effect in pairs(dynamic or {}) do
    if effect.family == "koffing-gas" then
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
    return false
  end
  scene = nextScene
  applyDebugControls()
  loadError = nil
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
  root = findRoot()
  if not root then
    loadError = "could not find the gen1recomp root; run this from the gen1recomp directory or set GEN1RECOMP_ROOT"
    return
  end
  installModLoader(root)
  local ok, result = pcall(function()
    Importer = require("mods.STADIUM2_IMPORTER.lib.importer")
    Presentation = require("mods.STADIUM2_IMPORTER.lib.battle_presentation")
    Camera = require("mods.STADIUM2_IMPORTER.lib.battle_camera")
    Importer.configure({ count = 251 })
    if not Importer.available(251) then
      local started, err = Importer.autoImport()
      if not started then error(err or "Stadium 2 cache is stale and automatic re-import failed") end
      importing = Importer.status().state == "building"
      if importing then return true end
    end
    return makeScene()
  end)
  if not ok then loadError = tostring(result) end
end

local function drawText(g)
  local selected = selectedActor()
  local renderer = selected and selected.renderer
  local model = renderer and renderer.model or {}
  local animations = model.anims or {}
  local animation = animations[renderer and renderer.animIndex or 0]
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
    g.print("G force gas   [ / ] age   X suppress gas draw", 24, 116)
    g.print("0 all primitives   1-9 isolate   S shot   H/D/P debug", 24, 134)
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
    g.print("Koffing gas: " .. tostring(d.active or 0) .. "  emitters: "
      .. tostring(d.emitterCount or 0) .. "  age: " .. tostring(forceGasAge), 24, y + 54)
    g.print("Gas forced: " .. tostring(forceGas) .. "  suppressed: "
      .. tostring(suppressGasDraw), 24, y + 72)
    g.print("Callback texture: " .. tostring(d.textureInfo or "none"), 24, y + 90)
    g.print("Cache models: 251  filter: nearest presentation", 24, y + 108)
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
    if autoCaptureFrames == 8 then
      love.graphics.captureScreenshot(autoCapture)
    elseif autoCaptureFrames >= 10 then
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
