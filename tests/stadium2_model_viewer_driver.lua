return function(game)
  local Importer = require("mods.STADIUM2_IMPORTER.lib.importer")
  local Viewer = require("mods.STADIUM2_IMPORTER.tests.model_viewer")
  local CoreRenderer = require("src.render.Renderer")
  local oldMaxWidth, oldMaxHeight = CoreRenderer.MAX_UI_WIDTH, CoreRenderer.MAX_UI_HEIGHT
  CoreRenderer.MAX_UI_WIDTH = Viewer.MAX_WIDTH
  CoreRenderer.MAX_UI_HEIGHT = Viewer.MAX_HEIGHT

  local viewer = Viewer.new(game, Importer)
  local oldWheel = love and love.wheelmoved
  local oldMousePressed = love and love.mousepressed
  local oldMouseMoved = love and love.mousemoved
  local oldMouseReleased = love and love.mousereleased

  if love then
    love.wheelmoved = function(x, y)
      if game.stack:top() == viewer then return viewer:onWheelMoved(x, y) end
      if oldWheel then return oldWheel(x, y) end
    end
    love.mousepressed = function(x, y, button, istouch, presses)
      if game.stack:top() == viewer and not istouch then return viewer:onMousePressed(x, y, button) end
      if oldMousePressed then return oldMousePressed(x, y, button, istouch, presses) end
    end
    love.mousemoved = function(x, y, dx, dy, istouch)
      if game.stack:top() == viewer and not istouch then return viewer:onMouseMoved(x, y) end
      if oldMouseMoved then return oldMouseMoved(x, y, dx, dy, istouch) end
    end
    love.mousereleased = function(x, y, button, istouch, presses)
      if game.stack:top() == viewer and not istouch then return viewer:onMouseReleased(x, y, button) end
      if oldMouseReleased then return oldMouseReleased(x, y, button, istouch, presses) end
    end
  end

  while game.stack:top() do game.stack:pop() end
  game.stack:push(viewer)
  print("[driver] Stadium 2 model viewer: LEFT/RIGHT models, Q/E animations, wheel/+/- zoom, left-drag move")
  while game.stack:top() == viewer do
    coroutine.yield()
  end

  if love then
    love.wheelmoved = oldWheel
    love.mousepressed = oldMousePressed
    love.mousemoved = oldMouseMoved
    love.mousereleased = oldMouseReleased
  end
  CoreRenderer.MAX_UI_WIDTH = oldMaxWidth
  CoreRenderer.MAX_UI_HEIGHT = oldMaxHeight
end
