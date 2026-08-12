local Importer = require("mods.STADIUM2_IMPORTER.lib.importer")
local Battle = require("mods.STADIUM2_IMPORTER.lib.battle_router")
local BattleAA = require("mods.STADIUM2_IMPORTER.lib.battle_aa")
local BattlePresentation = require("mods.STADIUM2_IMPORTER.lib.battle_presentation")
local ImportScreen = require("mods.STADIUM2_IMPORTER.lib.import_screen")

return function(mod)
  Importer.bind(mod)
  Battle.bind(mod)
  BattleAA.bind(mod)
  local importScreen

  local function showImportScreen(game)
    local state = Importer.status().state
    if importScreen or not (game and game.stack)
        or (state ~= "building" and state ~= "picking" and state ~= "failed") then
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
    { key="stadium2_battle_aa", label="BATTLE AA", type="choice", default=0,
      choices={{"OFF",0},{"2X",2},{"4X",4}},
      help="Supersample the owned Stadium battle arena; the native UI stays crisp." },
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

  mod.exports.version = "0.10.2"
  mod.exports.configure = Importer.configure
  mod.exports.status = Importer.status
  mod.exports.available = Importer.available
  mod.exports.modelsEnabled = Importer.modelsEnabled
  mod.exports.battleEnabled = Importer.battleEnabled
  mod.exports.battleStatus = Battle.status
  mod.exports.configureGame = Battle.configureGame
  mod.exports.presentation = BattlePresentation
  mod.exports.newBattleActor = BattlePresentation.newActor
  mod.exports.newBattleScene = BattlePresentation.newScene
  mod.exports.autoImport = Importer.autoImport
  mod.exports.beginFrom = Importer.beginFrom
  mod.exports.beginPath = Importer.beginPath
  mod.exports.request = Importer.request
  mod.exports.modelPath = Importer.modelPath
  mod.exports.readPack = Importer.readPack
  mod.exports.parsePack = Importer.parsePack
  mod.exports.loadModel = Importer.loadModel
  mod.exports.newRenderer = Importer.newRenderer
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

  mod.hooks:wrap("input.step", function(next, game, dt)
    local result = next(game, dt)
    Importer.step()
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

  mod.events:on("game.ready", function(ev)
    -- game.ready is the generation-neutral owner seam.  Requiring
    -- src.core.Game here would bind Gold to Gen 1's unused singleton.
    local game = (ev and ev.game) or mod.game
    Battle.configureGame(game)
    -- The active generation is only authoritative once the live game owner
    -- exists. Installing earlier can patch Gen 1's dormant singleton on Gold.
    Battle.install()
    Importer.autoImport()
    showImportScreen(game)
  end)

  mod.events:on("battle.started", function(ev)
    Battle.ensure(ev and ev.battle)
  end)

  mod.events:on("battle.ended", function(ev)
    -- Gold decides the outcome before its visible faint/victory/experience
    -- queue has finished.  Pass the owner so its scene can defer teardown;
    -- Gen 1's implementation still finishes immediately.
    Battle.finish(ev and ev.battle)
  end)
end
