local scene
local Importer
local Presentation
local Camera
local DynamicObject
local root
local loadError
local paused = false
local selectedSide = "enemy"
local enemyDex = math.max(1,math.floor(tonumber(os.getenv("STADIUM2_VISUAL_ENEMY")) or 109))
local playerDex = math.max(1,math.floor(tonumber(os.getenv("STADIUM2_VISUAL_PLAYER")) or 159))
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
local customGLBs={}
local activeCustomByDex={}
local customNamesByPath={}

local function fileExists(path)
  local handle = io.open(path, "rb")
  if not handle then return false end
  handle:close()
  return true
end

local function readFile(path)
  local handle = io.open(path, "rb")
  if not handle then return nil end
  local bytes = handle:read("*a")
  handle:close()
  return bytes
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
  local count=251+#customGLBs
  return ((math.floor(tonumber(value) or 1)-1)%count)+1
end

local function selectionLabel(value)
  value=math.floor(tonumber(value) or 1)
  local path=customGLBs[value-251]
  if not path then return ("species #%03d"):format(value) end
  return ("custom %d/%d: %s"):format(value-251,#customGLBs,
    customNamesByPath[path] or path:match("([^/]+)$") or path)
end

local function customDisplayName(path,internalName)
  local filename=(path:match("([^/]+)$") or path):lower()
  if filename:match("unit[_%- ]?0?1") then return "Eva Unit-01" end
  if filename:find("sachiel",1,true) then return "Sachiel" end
  return internalName or (path:match("([^/]+)%.glb$") or path)
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
  if Importer then Importer.releaseModels() end
  activeCustomByDex={}
  local reserved={}
  if enemyDex<=251 then reserved[enemyDex]=true end
  if playerDex<=251 then reserved[playerDex]=true end
  local function loadDex(selection)
    if selection<=251 then return selection end
    local path=customGLBs[selection-251]
    if not path then return 1 end
    for candidate=251,1,-1 do
      if not reserved[candidate] then
        reserved[candidate]=true;activeCustomByDex[candidate]=path;return candidate
      end
    end
    return 1
  end
  local enemyLoadDex,playerLoadDex=loadDex(enemyDex),loadDex(playerDex)
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
    { species = enemyLoadDex, shiny = false }, enemyLoadDex)
  local playerOk = Presentation.setBattler(nextScene, "player", nil,
    { species = playerLoadDex, shiny = false }, playerLoadDex)
  if not enemyOk or not playerOk then
    nextScene:release()
    scene = nil
    loadError = ("could not load models: enemy=%s %s player=%s %s\ncache=%s")
      :format(selectionLabel(enemyDex), tostring(enemyOk), selectionLabel(playerDex), tostring(playerOk),
        love.filesystem.getSaveDirectory() .. "/stadium2_importer")
    warn(loadError)
    return false
  end
  scene = nextScene
  applyDebugControls()
  loadError = nil
  local enemy = actorForSide("enemy")
  local player = actorForSide("player")
  local enemyModel=enemy and enemy.renderer and enemy.renderer.model
  local playerModel=player and player.renderer and player.renderer.model
  local enemyCustom=activeCustomByDex[enemyLoadDex]
  local playerCustom=activeCustomByDex[playerLoadDex]
  if enemyCustom and enemyModel and enemyModel.name then
    customNamesByPath[enemyCustom]=customDisplayName(enemyCustom,enemyModel.name)
  end
  if playerCustom and playerModel and playerModel.name then
    customNamesByPath[playerCustom]=customDisplayName(playerCustom,playerModel.name)
  end
  local enemySource=enemyModel and enemyModel.sourceFormat or "dsm4"
  local playerSource=playerModel and playerModel.sourceFormat or "dsm4"
  warn(("READY enemy=%s shader=%s source=%s path=%s player=%s shader=%s source=%s path=%s cache=%s")
    :format(selectionLabel(enemyDex), tostring(enemy and enemy.renderer and enemy.renderer.shaderTier),
      tostring(enemySource),tostring(enemyCustom
        or enemyModel and enemyModel.packagedPath or "cache"),
      selectionLabel(playerDex), tostring(player and player.renderer and player.renderer.shaderTier),
      tostring(playerSource),tostring(playerCustom
        or playerModel and playerModel.packagedPath or "cache"),
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
  root = findRoot()
  if not root then
    loadError = "could not find the gen1recomp root; run this from the gen1recomp directory or set GEN1RECOMP_ROOT"
    return
  end
  installModLoader(root)
  local ok, result = pcall(function()
    Importer = require("mods.STADIUM2_IMPORTER.lib.importer")
    local modRoot=root.."/mods/STADIUM2_IMPORTER/"
    local legacyRoot=love.filesystem.getSaveDirectory().."/stadium2_importer/"
    local memory={}
    local storage={}
    function storage:context() return {gameVersion="visual",playthroughId="viewer"} end
    function storage:read(_,key)
      if memory[key]~=nil then return memory[key] end
      if key=="cache/marker" then
        local text=readFile(legacyRoot.."pack.info")
        if not text then return nil end
        local marker={}
        for name,value in text:gmatch("([^=\n]+)=([^\n]*)") do
          marker[name]=name=="count" and tonumber(value) or value
        end
        return {marker=marker}
      end
      local relative=key:match("^cache/(.+)$")
      if relative and relative~="error" then
        local bytes=readFile(legacyRoot..relative..".dsm")
        if bytes then return {bytes=bytes} end
      end
      return nil
    end
    function storage:write(_,key,value) memory[key]=value;return true end
    function storage:delete(_,key) memory[key]=nil;return true end
    local requestedGLB=os.getenv("STADIUM2_VISUAL_GLB")
    if requestedGLB and requestedGLB:sub(1,1)~="/" then requestedGLB=root.."/"..requestedGLB end
    local seen={}
    local function addCustom(path)
      if path and path~="" and not seen[path] and fileExists(path) then
        seen[path]=true;customGLBs[#customGLBs+1]=path
      end
    end
    addCustom(requestedGLB)
    local dropDirectory=modRoot.."build/glb-drop"
    local command=("find %q -maxdepth 1 -type f -iname '*.glb' -print 2>/dev/null | sort")
      :format(dropDirectory)
    local pipe=io.popen(command,"r")
    if pipe then for path in pipe:lines() do addCustom(path) end;pipe:close() end
    enemyDex=wrapSpecies(requestedGLB and 252 or enemyDex)
    playerDex=wrapSpecies(playerDex)
    local developmentMod={game={save={version="visual",meta={playthroughId="viewer"}}},
      storage=storage,options={ get=function(_, key)
      if key == "stadium2_shader" then return shaderStyle end
    end }}
    function developmentMod:read(path)
      local direct=modRoot..tostring(path or "")
      local bytes=readFile(direct)
      if bytes then return bytes end
      local filename=tostring(path or ""):match("^models/([^/]+%.glb)$")
      if filename and (filename:match("^%d%d%d%-normal%.glb$")
          or filename:match("^%d%d%d%-shiny%.glb$")) then
        local requestedSpecies=tonumber(filename:match("^(%d%d%d)"))
        local customPath=activeCustomByDex[requestedSpecies]
        if customPath then
          bytes=readFile(customPath)
          if bytes then return bytes end
        end
        bytes=readFile(modRoot.."build/blender-roundtrip/"..filename)
        if bytes then return bytes end
        return readFile(modRoot.."build/glb/"..filename)
      end
      return nil
    end
    Importer.bind(developmentMod)
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
  local selectedSelection=selectedSide=="enemy" and enemyDex or playerDex
  g.setColor(0, 0, 0, .72)
  local panelHeight = help and (debugPanel and 274 or 134) or (debugPanel and 210 or 52)
  g.rectangle("fill", 12, 12, 430, panelHeight, 6, 6)
  g.setColor(1, 1, 1, 1)
  g.print(enemyMark.."Enemy "..selectionLabel(enemyDex),24,22)
  g.print(playerMark.."Player "..selectionLabel(playerDex),24,40)
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
    g.print(("Selected %s %s  bones:%d prims:%d textures:%d"):format(
      selectedSide,selectionLabel(selectedSelection),#(model.bones or {}),
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
    g.print(("Model source: %s   path: %s"):format(
      tostring(model.sourceFormat or "dsm4"),
      tostring(activeCustomByDex[selected and selected.dex or -1]
        or model.packagedPath or "cache")),24,y+126)
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
    setSelectedSpecies(251+#customGLBs)
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
