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
  local lifecycle=require("mods.STADIUM2_IMPORTER.lib.mod_lifecycle").new(mod)
  lifecycle:add(Battle.uninstall)
  lifecycle:add(BattleUIOwnership.resetForTests)
  lifecycle:add(BattleAA.release)
  lifecycle:add(function() require("mods.STADIUM2_IMPORTER.lib.battle_watercolor").release() end)
  Importer.bind(mod)
  require("mods.STADIUM2_IMPORTER.lib.battle_nature").bind(mod)
  require("mods.STADIUM2_IMPORTER.lib.battle_cave").bind(mod)
  require("mods.STADIUM2_IMPORTER.lib.battle_freshwater").bind(mod)
  require("mods.STADIUM2_IMPORTER.lib.battle_town").bind(mod)
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
  local mapContext,pendingEncounter,lastTimeOfDay
  local EnvironmentCache=require("mods.STADIUM2_IMPORTER.lib.environment_cache")
  EnvironmentCache.reset()
  local preparedContext,preparedStyle,preparedTest,preparedArena
  local function prepareEnvironment()
    if not (mapContext and Importer.available()) or Battle.currentScene() then return end
    local style,test,arena=Importer.environmentStyle(),Importer.environmentTest(),Importer.arenaTest()
    if preparedContext==mapContext and preparedStyle==style and preparedTest==test and preparedArena==arena then return end
    if not (love and love.graphics and love.graphics.newCanvas) then return end
    EnvironmentCache.location(love.graphics,mapContext,style,test,arena)
    preparedContext,preparedStyle,preparedTest,preparedArena=mapContext,style,test,arena
  end
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

  local arenaChoices={{'AUTOMATIC',-1}}
  local arenaNames={'FALKNER','BUGSY','WHITNEY','MORTY','JASMINE','CHUCK','PRYCE','CLAIR',
    'TEAM ROCKET','WILL','KOGA','BRUNO','KAREN','CHAMPION','BROCK','MISTY','LT. SURGE',
    'ERIKA','JANINE','SABRINA','BLAINE','BLUE','RED'}
  arenaNames[27]='BATTLE TOWER';arenaNames[28]='INDOOR';arenaNames[29]='FREE BATTLE PARK';arenaNames[30]='RIVAL'
  for index=0,require('mods.STADIUM2_IMPORTER.lib.layout').STADIUM_MODEL_TABLE_RECORDS-1 do
    arenaChoices[#arenaChoices+1]={('ARENA %02d%s'):format(index,arenaNames[index+1] and (' - '..arenaNames[index+1]) or ''),index}
  end

  mod.options:define({
    { key="stadium2_models", label="3D POKEMON MODELS", type="toggle", default=true },
    { key="stadium2_battle", label="3D BATTLE SCENE", type="toggle", default=true },
    { key="stadium2_battle_hud", label="BATTLE HUD", type="toggle",
      default=true,
      help="Show Stadium's glass battle HUD. Turn OFF to leave the native or another mod's battle UI unobstructed." },
    { key="stadium2_shader", label="SHADER STYLE", type="choice", default="stadium",
      choices={{"STADIUM","stadium"},{"WATERCOLOR MANGA","cel"}},
      help="Choose Stadium shading or watercolor manga on desktop and Android. Applies to imported Pokemon and the whole custom battle scene; battle UI stays unchanged." },
    { key="stadium2_weather", label="SCENE WEATHER", type="choice", default="off",
      choices={{"OFF","off"},{"RAIN","rain"},{"THUNDERSTORM","storm"}},
      help="Stylized rain and surface splashes in outdoor custom scenes. Thunderstorm adds occasional lightning and a brief scene illumination. Cosmetic only." },
    { key="stadium2_environment", label="BATTLE ENVIRONMENT", type="choice", default="classic",
      choices={{"CLASSIC","classic"},{"KENNEY NATURE","kenney"}},
      help="Watercolor woodland, cave, freshwater and town scenes for matching wild and trainer encounters. Unbuilt environments use Classic, or a contextual Stadium arena when arenas are enabled." },
    { key="stadium2_environment_test", label="TEST ENVIRONMENT", type="choice", default="automatic",
      choices={{"AUTOMATIC","automatic"},{"GRASS / WOODLAND","grass"},{"CAVE","cave"},
        {"FRESHWATER","freshwater"},{"TOWN","town"},{"OCEAN (FALLBACK)","ocean"},
        {"MOUNTAIN (FALLBACK)","mountain"},{"ICE CAVE (FALLBACK)","ice_cave"},
        {"INTERIOR (FALLBACK)","interior"},{"INDUSTRIAL (FALLBACK)","industrial"},
        {"RUINS / TOWER (FALLBACK)","ruins"},{"SHIP (FALLBACK)","ship"},
        {"GYM (FALLBACK)","gym"},{"LEAGUE (FALLBACK)","league"},
        {"CAVE WATER (FALLBACK)","cave_water"},{"INDOOR WATER (FALLBACK)","indoor_water"}},
      help="Force an environment on your next encounter, regardless of location or the Battle Environment option. Unbuilt scenes test the Classic/arena fallback. Automatic restores normal selection." },
    { key="stadium2_visitors", label="AMBIENT POKEMON", type="choice", default="natural",
      choices={{"OFF","off"},{"NATURAL","natural"},{"PREVIEW CAMEOS","preview"}},
      help="Cosmetic visitors in custom environments. Natural includes rare Mew/Ho-Oh cameos; Preview cycles them regularly. Visitors cannot battle or be caught." },
    { key="stadium2_arena_test", label="TEST ARENA", type="choice", default=-1,
      choices=arenaChoices,
      help="Force any Stadium arena on your next encounter, even with context arenas off. Takes priority over Test Environment. Set both tests to Automatic to restore normal routing." },
    { key="stadium2_battle_aa", label="BATTLE AA", type="choice", default=0,
      choices={{"OFF",0},{"2X",2},{"4X",4}},
      help="Supersample the owned Stadium battle arena; the native UI stays crisp." },
    { key="stadium2_rapidash_cut_fx", label="RAPIDASH CUT PARTICLES", type="toggle", default=true,
      help="Restore Rapidash's disconnected prototype particle callback in battles and model renderers." },
    { key="stadium2_beta_arena_test", label="CONTEXT ARENAS (BETA)", type="toggle", default=false,
      help="Select contextual Stadium fields for Gen 2 trainers. With Kenney environments enabled, also provides arena fallback for unbuilt environments in either game." },
    { key="stadium2_beta_arena_tod", label="PARK TIME OF DAY (BETA)", type="toggle", default=false,
      help="Experimental: when context arenas are enabled, tint Free Battle Park for Gen 2 morning, day, or night. Turn OFF for the arena's normal lighting." },
    { key="stadium2_beta_battle_fx", label="MOVE EFFECTS (BETA)", type="toggle", default=false,
      help="Experimental: Stadium 2 move and battle effects decoded from your imported ROM, with Stadium's own per-move Pokemon routines (Agility, Double Team, Minimize). OFF keeps the game's normal battle effects. Takes effect from the next battle." },
  })

  -- DSM animations are authored at 30 Hz, but advance from presented-frame
  -- real time. The speed-scaled logic clock can run many times per frame.
  mod.content.render_pipelines:register("stadium2_battle_clock", {
    label = "BATTLE CLOCK",
    levels = { "OFF" },
    update = function(dt)
      Battle.update(dt)
      prepareEnvironment()
    end,
    -- Satisfy the pipeline record contract without ever entering a render
    -- pass: its only level is OFF, while pipeline updates run unconditionally.
    present = function(canvas)
      return canvas
    end,
  })

  mod.exports.version = "0.15.2"
  mod.exports.configure = Importer.configure
  mod.exports.status = Importer.status
  mod.exports.cacheStatus = Importer.cacheStatus
  mod.exports.available = Importer.available
  mod.exports.modelsEnabled = Importer.modelsEnabled
  mod.exports.battleEnabled = Importer.battleEnabled
  mod.exports.battleHudEnabled = Importer.battleHudEnabled
  mod.exports.battleUI = {
    apiVersion=1,
    statusVisibleHook="battle.status_hud_visible",
    bottomVisibleHook="battle.bottom_ui_visible",
    statusOverlayHook="battle.ui.status_overlay.v1",
  }
  mod.exports.gen1ModernUi = {apiVersion=1,screens={},battle={
    native3d=function(_,state)
      local scene=Battle.currentScene()
      return scene~=nil and (scene.battle==state or scene.screen==state)
    end,
  }}
  local modernRegistered
  mod.hooks:wrap("input.step",function(next,game,dt)
    local handle=mod.find and mod.find("gen1_modern_ui")
    local api=handle and handle.exports
    if api and api~=modernRegistered and type(api.registerAdapter)=="function" then
      local ok,registered=pcall(api.registerAdapter,{owner="STADIUM2_IMPORTER",
        contract=mod.exports.gen1ModernUi})
      if ok and registered then modernRegistered=api end
    end
    return next(game,dt)
  end,6)
  mod.exports.shaderStyle = Importer.shaderStyle
  mod.exports.rapidashCutEffectEnabled = Importer.rapidashCutEffectEnabled
  mod.exports.betaArenaEnabled = Importer.betaArenaEnabled
  mod.exports.betaArenaTimeOfDayEnabled = Importer.betaArenaTimeOfDayEnabled
  mod.exports.betaBattleFxEnabled = Importer.betaBattleFxEnabled
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
  mod.exports.battleFxCatalog = Importer.battleFxCatalog
  mod.exports.battleFxResource = Importer.battleFxResource
  mod.exports.battleFxResources = Importer.battleFxResources
  mod.exports.battleFxShape = Importer.battleFxShape
  mod.exports.battleFxShapeModel = Importer.battleFxShapeModel
  mod.exports.battleFxProgram = Importer.battleFxProgram
  mod.exports.newBattleFxPlayer = Importer.newBattleFxPlayer
  mod.exports.releaseModel = Importer.releaseModel
  mod.exports.newRenderer = Importer.newRenderer
  mod.exports.newRendererFromModel = Importer.newRendererFromModel
  mod.exports.releaseModels = Importer.releaseModels
  -- Explicit cache eviction for tools/reloads; the next Nature battle rebuilds it.
  mod.exports.releaseEnvironment = function()
    EnvironmentCache.reset()
    require("mods.STADIUM2_IMPORTER.lib.battle_nature").release()
    require("mods.STADIUM2_IMPORTER.lib.battle_cave").release()
    require("mods.STADIUM2_IMPORTER.lib.battle_freshwater").release()
    require("mods.STADIUM2_IMPORTER.lib.battle_town").release()
  end
  lifecycle:add(mod.exports.releaseEnvironment)
  lifecycle:add(Importer.releaseModels)
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


  mod.events:on("map.entered",function(ev)
    local map=ev and ev.map
    local def=map and map.def
    local environment=def and def.environment
    local outside
    if environment~=nil then
      outside=environment=="TOWN" or environment=="ROUTE" or environment=="FOREST"
    end
    mapContext={mapId=ev and ev.mapId or map and map.id,
      environment=environment,outside=outside,waterType=def and def.waterType}
    pendingEncounter=nil
    prepareEnvironment()
  end)

  -- Observe the official chains without changing their answers. A successful
  -- water roll is the engine's authoritative signal that a wild fight began
  -- while surfing; fishing has its separate battleType on battle.started.
  mod.hooks:wrap("encounter.species",function(next,enc,ctx)
    local out=next(enc,ctx)
    if out~=nil then
      pendingEncounter={mapId=ctx and ctx.mapId,terrain=ctx and ctx.terrain,
        environment=ctx and ctx.environment,waterType=ctx and ctx.waterType,timeOfDay=ctx and ctx.daytime}
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
    local fxOk, FxAdapter = pcall(require,
      "mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_battle_adapter")
    if fxOk then FxAdapter.clearHits() end
    local current=mod.world and mod.world.current and mod.world:current() or nil
    local mapId=current and current.mapId or mapContext and mapContext.mapId
    local mapped=mapContext and mapContext.mapId==mapId and mapContext or nil
    -- Capture the live header as well: a mod enabled after map.entered must
    -- make the same selection at battle construction as at render time.
    if not mapped and mod.world and mod.world.overworld then
      local world=mod.world:overworld()
      local map=world and world.map
      local def=map and map.def
      if map and map.id==mapId and def and def.environment then
        local e=def.environment
        mapped={environment=e,outside=e=='TOWN' or e=='ROUTE' or e=='FOREST',waterType=def.waterType}
      end
    end
    local encounter=pendingEncounter and pendingEncounter.mapId==mapId
      and pendingEncounter or nil
    local battle=ev and ev.battle
    Battle.ensure(battle,{
      generation=Battle.status().generation,mapId=mapId,
      environment=(encounter and encounter.environment) or (mapped and mapped.environment),
      -- Preserve false: indoor is a meaningful classification, not absence.
      outside=mapped and mapped.outside,
      terrain=encounter and encounter.terrain or nil,
      waterType=(encounter and encounter.waterType) or (mapped and mapped.waterType),
      timeOfDay=lastTimeOfDay or (encounter and encounter.timeOfDay),
      kind=ev and ev.kind,trainerId=ev and ev.trainerId,
      battleType=ev and ev.battleType,
      battleTower=battle and battle.inBattleTowerBattle==true,
    })
    pendingEncounter=nil
  end)

  -- Hit facts for the battle FX result byte (Sequence.resultByte).
  mod.events:on("battle.damage_dealt", function(ev)
    local ok, Adapter = pcall(require,
      "mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_battle_adapter")
    if ok then Adapter.recordHit(ev) end
  end)

  mod.events:on("battle.ended", function(ev)
    -- Gold decides the outcome before its visible faint/victory/experience
    -- queue has finished.  Pass the owner so its scene can defer teardown;
    -- Gen 1's implementation still finishes immediately.
    Battle.finish(ev and ev.battle)
  end)
end
