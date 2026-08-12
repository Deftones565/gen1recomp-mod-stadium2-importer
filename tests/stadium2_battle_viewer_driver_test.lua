package.path = "./?.lua;./?/init.lua;" .. package.path

local checks = 0
local function ok(value, message)
  checks = checks + 1
  if not value then error("FAIL " .. message, 0) end
end

local viewer = { released = false }
function viewer:release() self.released = true end
local stackItems = { { id = "old1" }, { id = "old2" } }
local stack = {}
function stack:top() return stackItems[#stackItems] end
function stack:pop() return table.remove(stackItems) end
function stack:push(v) stackItems[#stackItems + 1] = v end

local importer = {}
local coreRenderer = { MAX_UI_WIDTH = 640, MAX_UI_HEIGHT = 576 }
package.loaded["mods.STADIUM2_IMPORTER.lib.importer"] = importer
package.loaded["src.render.Renderer"] = coreRenderer
package.loaded["mods.STADIUM2_IMPORTER.tests.battle_viewer"] = {
  MAX_WIDTH = 3840,
  MAX_HEIGHT = 2160,
  new = function(game, gotImporter)
    ok(game.stack == stack, "driver passes game")
    ok(gotImporter == importer, "driver passes importer")
    return viewer
  end,
}

local game = { stack = stack }
local fn = assert(loadfile("mods/STADIUM2_IMPORTER/tests/stadium2_battle_viewer_driver.lua"))()
local co = coroutine.create(fn)
local resumed, err = coroutine.resume(co, game)
ok(resumed, tostring(err or "driver first resume"))
ok(coroutine.status(co) == "suspended", "driver remains alive")
ok(#stackItems == 1 and stackItems[1] == viewer, "driver replaces stack with battle viewer")
ok(coreRenderer.MAX_UI_WIDTH == 3840 and coreRenderer.MAX_UI_HEIGHT == 2160, "driver enables full-resolution battle surface")
stack:pop()
resumed, err = coroutine.resume(co, game)
ok(resumed, tostring(err or "driver final resume"))
ok(coroutine.status(co) == "dead", "driver exits when viewer closes")
ok(viewer.released == true, "driver releases battle rigs")
ok(coreRenderer.MAX_UI_WIDTH == 640 and coreRenderer.MAX_UI_HEIGHT == 576, "driver restores renderer limits")

print(("%d checks passed (Stadium 2 battle viewer driver)"):format(checks))
