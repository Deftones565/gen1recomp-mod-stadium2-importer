package.path = "./?.lua;./?/init.lua;" .. package.path

local checks = 0
local function ok(value, message)
  checks = checks + 1
  if not value then error("FAIL " .. message, 0) end
end

local events = {}
local viewerObject = { id = "viewer" }
function viewerObject:onWheelMoved(x, y) events[#events + 1] = { "wheel", x, y } end
function viewerObject:onMousePressed(x, y, button) events[#events + 1] = { "press", x, y, button } end
function viewerObject:onMouseMoved(x, y) events[#events + 1] = { "move", x, y } end
function viewerObject:onMouseReleased(x, y, button) events[#events + 1] = { "release", x, y, button } end

local stackItems = { { id = "old1" }, { id = "old2" } }
local stack = {}
function stack:top() return stackItems[#stackItems] end
function stack:pop() return table.remove(stackItems) end
function stack:push(v) stackItems[#stackItems + 1] = v end

local importer = {}
local coreRenderer = { MAX_UI_WIDTH = 640, MAX_UI_HEIGHT = 576 }
package.loaded["mods.STADIUM2_IMPORTER.lib.importer"] = importer
package.loaded["src.render.Renderer"] = coreRenderer
package.loaded["mods.STADIUM2_IMPORTER.tests.model_viewer"] = {
  MAX_WIDTH = 3840,
  MAX_HEIGHT = 2160,
  new = function(game, gotImporter)
    ok(game.stack == stack, "driver passes game to viewer")
    ok(gotImporter == importer, "driver passes importer to viewer")
    return viewerObject
  end,
}

local oldWheelCalls = 0
local oldPressCalls = 0
_G.love = {}
function love.wheelmoved() oldWheelCalls = oldWheelCalls + 1 end
function love.mousepressed() oldPressCalls = oldPressCalls + 1 end
function love.mousemoved() end
function love.mousereleased() end
local originalWheel = love.wheelmoved
local originalPress = love.mousepressed

local game = { stack = stack }
local fn = assert(loadfile("mods/STADIUM2_IMPORTER/tests/stadium2_model_viewer_driver.lua"))()
local co = coroutine.create(fn)
local resumed, err = coroutine.resume(co, game)
ok(resumed, tostring(err or "driver first resume"))
ok(coroutine.status(co) == "suspended", "driver stays alive after installing viewer")
ok(#stackItems == 1 and stackItems[1] == viewerObject, "driver replaces stack with viewer")
ok(coreRenderer.MAX_UI_WIDTH == 3840 and coreRenderer.MAX_UI_HEIGHT == 2160, "driver enables full-resolution viewer surfaces")

love.wheelmoved(0, 1)
love.mousepressed(10, 20, 1, false)
love.mousemoved(12, 24, 2, 4, false)
love.mousereleased(12, 24, 1, false)
ok(#events == 4 and events[1][1] == "wheel" and events[2][1] == "press" and events[3][1] == "move" and events[4][1] == "release", "driver captures LÖVE pointer and wheel callbacks directly")
ok(oldWheelCalls == 0 and oldPressCalls == 0, "viewer input does not leak into game controls")

stack:pop()
resumed, err = coroutine.resume(co, game)
ok(resumed, tostring(err or "driver final resume"))
ok(coroutine.status(co) == "dead", "driver exits after viewer closes")
ok(love.wheelmoved == originalWheel and love.mousepressed == originalPress, "driver restores LÖVE input callbacks")
ok(coreRenderer.MAX_UI_WIDTH == 640 and coreRenderer.MAX_UI_HEIGHT == 576, "driver restores core renderer limits")
_G.love = nil

print(("%d checks passed (Stadium 2 model viewer driver)"):format(checks))
