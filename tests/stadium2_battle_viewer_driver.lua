return function(game)
  local Importer = require("mods.STADIUM2_IMPORTER.lib.importer")
  local BattleViewer = require("mods.STADIUM2_IMPORTER.tests.battle_viewer")
  local CoreRenderer = require("src.render.Renderer")
  local oldMaxWidth, oldMaxHeight = CoreRenderer.MAX_UI_WIDTH, CoreRenderer.MAX_UI_HEIGHT
  CoreRenderer.MAX_UI_WIDTH = BattleViewer.MAX_WIDTH
  CoreRenderer.MAX_UI_HEIGHT = BattleViewer.MAX_HEIGHT

  local viewer = BattleViewer.new(game, Importer)
  while game.stack:top() do game.stack:pop() end
  game.stack:push(viewer)
  print("[driver] Stadium 2 battle viewer: TAB side, LEFT/RIGHT species, S shiny, Q/E animation")
  while game.stack:top() == viewer do coroutine.yield() end
  viewer:release()
  CoreRenderer.MAX_UI_WIDTH = oldMaxWidth
  CoreRenderer.MAX_UI_HEIGHT = oldMaxHeight
end
