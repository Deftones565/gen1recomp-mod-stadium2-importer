local Importer = require("mods.STADIUM2_IMPORTER.lib.importer")
local Battle = require("mods.STADIUM2_IMPORTER.lib.battle_router")
local BattleAA = require("mods.STADIUM2_IMPORTER.lib.battle_aa")
local BattlePresentation = require("mods.STADIUM2_IMPORTER.lib.battle_presentation")
local ImportScreen = require("mods.STADIUM2_IMPORTER.lib.import_screen")
local Fx = require("mods.STADIUM2_IMPORTER.lib.fx")
local BattleSceneApi = require("mods.STADIUM2_IMPORTER.lib.battle_scene_api")
local ModelApi = require("mods.STADIUM2_IMPORTER.lib.model_api")
local BattleUIOwnership = require("mods.STADIUM2_IMPORTER.lib.battle_ui_ownership")

return function(mod)
  Importer.bind(mod)
  Fx.bind(mod)
  Battle.bind(mod)
  BattleAA.bind(mod)
  BattleSceneApi.bind(Battle)
  BattleUIOwnership.bind(mod,function(state)
    local scene=Battle.currentScene()
    return scene~=nil and (scene.battle==state or scene.screen==state
      or (state and scene.battle==state.battle))
  end)
  local Models = ModelApi.new(Importer)
  local importScreen
  local activatedSave
  local pendingAutoImport = false
  local activatePlaythrough

  local function gameplayActive(game)
    if not (game and game.save) then return false end
    -- Gen 2 owns a World service rather than Gen 1's overworld stack state.
    if game.phase == "play" and game.world then return true end
    -- Gen 1 (including overhaul mods such as Crystal 251) is ready once the
    -- real overworld is the visible owner. At this point CONTINUE/New Game has
    -- already replaced the temporary title save.
    local stack = game.stack
    return game.overworld ~= nil and stack ~= nil and type(stack.top) == "function"
      and stack:top() == game.overworld
  end

  local function screenIsOnStack(game, screen)
    local states = game and game.stack and game.stack.states
    if type(states) ~= "table" or not screen then return false end
    for _, state in ipairs(states) do
      if state == screen then return true end
    end
    return false
  end

  local function showImportScreen(game, force)
    local state = Importer.status().state
    if not (game and game.stack) then return false end

    -- A stale local reference must never suppress the UI.  If another engine
    -- transition removed the screen, forget it and recreate it below.
    if importScreen and not screenIsOnStack(game, importScreen) then
      importScreen = nil
    end

    if importScreen then return true end
    if not force and state ~= "building" and state ~= "picking" and state ~= "failed" then
      return false
    end

    importScreen = ImportScreen.new(game, Importer, function(screen)
      if importScreen == screen then importScreen = nil end
    end)
    game.stack:push(importScreen)
    return true
  end

  mod.options:define({
    { key="stadium2_models", label="STADIUM 2 MODELS", type="toggle", default=true },
    { key="stadium2_battle", label="STADIUM 2 BATTLE", type="toggle", default=true },
    { key="stadium2_shader", label="MODEL SHADER", type="choice", default="stadium",
      choices={{"STADIUM","stadium"},{"WATERCOLOR MANGA","cel"}},
      help="Choose authentic Stadium lighting or an inked watercolor-manga treatment for imported Pokemon models." },
    { key="stadium2_battle_aa", label="BATTLE AA", type="choice", default=0,
      choices={{"OFF",0},{"2X",2},{"4X",4}},
      help="Supersample the owned Stadium battle arena; the native UI stays crisp." },
    { key="stadium2_rapidash_cut_fx", label="RAPIDASH CUT PARTICLES", type="toggle", default=true,
      help="Restore Rapidash's disconnected prototype particle callback in battles and model renderers." },
    { key="stadium2_beta_arena_test", label="BETA CONTEXT ARENAS", type="toggle", default=false,
      help="Experimental, Gen 2 trainer battles only: select Stadium 2 fields from the current gym, story battle, or indoor/outdoor location. All wild battles keep the classic scene." },
    { key="stadium2_beta_arena_tod", label="BETA PARK TIME OF DAY", type="toggle", default=false,
      help="Experimental: when context arenas are enabled, tint Free Battle Park for Gen 2 morning, day, or night. Turn OFF for the arena's normal lighting." },
  })

  -- DSM animations are authored at 30 Hz, but advance from presented-frame
  -- real time. The speed-scaled logic clock can run many times per frame.
  mod.content.render_pipelines:register("stadium2_battle_clock", {
    label = "STADIUM 2 BATTLE CLOCK",
    levels = { "OFF" },
    update = function(dt)
      Battle.update(dt)
    end,
    -- Satisfy the pipeline record contract without ever entering a render
    -- pass: its only level is OFF, while pipeline updates run unconditionally.
    present = function(canvas)
      return canvas
    end,
  })

  mod.exports.version = "0.12.0"
  mod.exports.configure = Importer.configure
  mod.exports.status = Importer.status
  mod.exports.cacheStatus = Importer.cacheStatus
  mod.exports.available = Importer.available
  mod.exports.modelsEnabled = Importer.modelsEnabled
  mod.exports.battleEnabled = Importer.battleEnabled
  mod.exports.shaderStyle = Importer.shaderStyle
  mod.exports.rapidashCutEffectEnabled = Importer.rapidashCutEffectEnabled
  mod.exports.betaArenaEnabled = Importer.betaArenaEnabled
  mod.exports.betaArenaTimeOfDayEnabled = Importer.betaArenaTimeOfDayEnabled
  mod.exports.battleStatus = Battle.status
  mod.exports.configureGame = Battle.configureGame
  mod.exports.presentation = BattlePresentation
  mod.exports.newBattleActor = BattlePresentation.newActor
  mod.exports.newBattleScene = BattlePresentation.newScene
  mod.exports.autoImport = Importer.autoImport
  mod.exports.beginFrom = Importer.beginFrom
  mod.exports.beginPath = Importer.beginPath
  mod.exports.request = Importer.request
  mod.exports.reimport = Importer.reimport
  mod.exports.modelPath = Importer.modelPath
  mod.exports.readPack = Importer.readPack
  mod.exports.parsePack = Importer.parsePack
  mod.exports.loadModel = Importer.loadModel
  mod.exports.createModel = Importer.createModel
  mod.exports.createSpecialModel = Importer.createSpecialModel
  mod.exports.releaseModel = Importer.releaseModel
  mod.exports.newRenderer = Importer.newRenderer
  mod.exports.newRendererFromModel = Importer.newRendererFromModel
  mod.exports.releaseModels = Importer.releaseModels
  mod.exports.readHandlers = Importer.readHandlers
  mod.exports.handlerInfo = Importer.handlerInfo
  mod.exports.evaluateHandler = Importer.evaluateHandler
  mod.exports.runHandlers = Importer.runHandlers
  mod.exports.runModelHandlers = Importer.runModelHandlers
  mod.exports.resolveHandlerPointer = Importer.resolveHandlerPointer
  mod.exports.shinyPalettesFromTransformSource = Importer.shinyPalettesFromTransformSource
  mod.exports.US_MD5 = Importer.US_MD5
  mod.exports.FORMAT = Importer.FORMAT
  mod.exports.scene = BattleSceneApi
  mod.exports.getActiveBattleScene = BattleSceneApi.current
  mod.exports.registerBattleSceneExtension = BattleSceneApi.register
  mod.exports.battleSceneCapabilities = BattleSceneApi.capabilities()
  mod.exports.models = Models
  mod.exports.modelCapabilities = Models.capabilities()

  mod.hooks:wrap("input.step", function(next, game, dt)
    local result = next(game, dt)

    -- Do not inspect or allocate playthrough-scoped storage at game.ready.
    -- Wait until the actual world owner is running, matching the engine's
    -- importer/cache pattern and working for both Gen 1 overhauls and Gen 2.
    activatePlaythrough(game)

    -- HARD UI ORDERING GUARANTEE: automatic recovery is queued by
    -- activatePlaythrough(), but extraction does not start until its progress
    -- screen has been pushed onto the live stack.  This prevents a background
    -- auto-import from running before the player ever sees the importer UI.
    if pendingAutoImport then
      if showImportScreen(game, true) then
        pendingAutoImport = false
        Importer.autoImport()
      end
    else
      -- Manual reimports transition to BUILDING from the Options row; surface
      -- those on the following input boundary as before.
      showImportScreen(game)
    end

    -- Only advance extraction after the import screen has been installed.
    if not pendingAutoImport then Importer.step() end

    -- A first-step failure transitions to FAILED; keep it visible immediately.
    showImportScreen(game)
    return result
  end, 5)

  mod.hooks:wrap("ui.options.rows", function(next, game, rows)
    local out = next(game, rows)
    if type(out) == "table" then
      -- The internal real-time clock is deliberately not a user-facing
      -- display mode.
      for i = #out, 1, -1 do
        if out[i] and out[i].id == "pipeline:stadium2_battle_clock" then
          table.remove(out, i)
        end
      end
      Importer.appendRow(out)
    end
    return out
  end, 95)

  activatePlaythrough = function(game)
    if not gameplayActive(game) or activatedSave == game.save then return false end

    -- Configure from the final merged data only after the real playthrough is
    -- live. Crystal 251 has already registered its overhaul by this point, so
    -- the dex scan naturally resolves to 251 instead of the boot-time 151.
    Importer.setPlaythroughReady(false)
    Battle.configureGame(game)
    Importer.setPlaythroughReady(true)
    Battle.install()

    activatedSave = game.save

    -- Cache validity is decided only inside the real playthrough namespace.
    -- A valid cache needs no work. Missing/stale/incomplete rebuilds; a storage
    -- access error is surfaced and NEVER misclassified as a missing cache.
    local cache = Importer.cacheStatus()
    if mod.log and cache then
      local ctx = cache.context or {}
      pcall(function()
        mod.log:info("stadium2 cache: state=%s code=%s game=%s playthrough=%s",
          tostring(cache.state), tostring(cache.code),
          tostring(ctx.gameVersion or "?"), tostring(ctx.playthroughId or "?"))
      end)
    end
    if cache.state == "valid" then
      -- setPlaythroughReady already marked the importer READY.
      pendingAutoImport = false
    elseif cache.state == "missing" or cache.state == "stale"
        or cache.state == "incomplete" then
      -- Queue the automatic recovery.  The input.step wrapper above MUST push
      -- the importer screen first; only then is autoImport() allowed to begin.
      pendingAutoImport = true
    else
      -- Storage/backend errors are not cache misses and must never rebuild.
      pendingAutoImport = false
      Importer.autoImport() -- turns the classified storage error into FAILED
      showImportScreen(game)
    end
    return true
  end


  local mapContext,pendingEncounter,lastTimeOfDay
  mod.events:on("map.entered",function(ev)
    local map=ev and ev.map
    local def=map and map.def
    local environment=def and def.environment
    local outside
    if environment~=nil then
      outside=environment=="TOWN" or environment=="ROUTE"
    end
    mapContext={mapId=ev and ev.mapId or map and map.id,
      environment=environment,outside=outside}
    pendingEncounter=nil
  end)

  -- Observe the official chains without changing their answers. A successful
  -- water roll is the engine's authoritative signal that a wild fight began
  -- while surfing; fishing has its separate battleType on battle.started.
  mod.hooks:wrap("encounter.species",function(next,enc,ctx)
    local out=next(enc,ctx)
    if out~=nil then
      pendingEncounter={mapId=ctx and ctx.mapId,terrain=ctx and ctx.terrain,
        environment=ctx and ctx.environment,timeOfDay=ctx and ctx.daytime}
    end
    return out
  end,95)
  mod.hooks:wrap("world.tod",function(next,tod,ctx)
    local out=next(tod,ctx)
    local hour=tonumber(ctx and ctx.hour)
    -- Gen 2 calls 18:00 onward NITE. Preserve its authoritative period but
    -- split the first three hours into a presentation-only warm evening; no
    -- world clock, palette, encounter table, or other mod sees this alias.
    lastTimeOfDay=out=="NITE" and hour and hour>=18 and hour<21 and "EVE" or out
    return out
  end,95)
  mod.events:on("world.stepped",function() pendingEncounter=nil end)

  mod.events:on("battle.started", function(ev)
    local current=mod.world and mod.world.current and mod.world:current() or nil
    local mapId=current and current.mapId or mapContext and mapContext.mapId
    local mapped=mapContext and mapContext.mapId==mapId and mapContext or nil
    local encounter=pendingEncounter and pendingEncounter.mapId==mapId
      and pendingEncounter or nil
    local battle=ev and ev.battle
    Battle.ensure(battle,{
      generation=Battle.status().generation,mapId=mapId,
      environment=(encounter and encounter.environment) or (mapped and mapped.environment),
      -- Preserve false: indoor is a meaningful classification, not absence.
      outside=mapped and mapped.outside,
      terrain=encounter and encounter.terrain or nil,
      timeOfDay=lastTimeOfDay or (encounter and encounter.timeOfDay),
      kind=ev and ev.kind,trainerId=ev and ev.trainerId,
      battleType=ev and ev.battleType,
      battleTower=battle and battle.inBattleTowerBattle==true,
    })
    pendingEncounter=nil
  end)

  mod.events:on("battle.ended", function(ev)
    -- Gold decides the outcome before its visible faint/victory/experience
    -- queue has finished.  Pass the owner so its scene can defer teardown;
    -- Gen 1's implementation still finishes immediately.
    Battle.finish(ev and ev.battle)
  end)
end
