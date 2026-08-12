package.path = "./?.lua;./?/init.lua;" .. package.path
require("tests.modkit")

local Screen = require("mods.STADIUM2_IMPORTER.lib.import_screen")
local checks = 0
local function ok(value, message)
  checks = checks + 1
  if not value then error("FAIL " .. message, 0) end
end

local status = { state = "building", progress = 0.25, done = 10, total = 251 }
local importer = {
  status = function() return status end,
  autoImport = function() return true end,
  request = function() return true end,
}
local current, popped
local stack = {
  top = function() return current end,
  pop = function()
    local value = current
    current = nil
    popped = value
    if value and value.exit then value:exit() end
    return value
  end,
}
local game = { stack = stack, input = { wasPressed = function() return false end } }
local closed
current = Screen.new(game, importer, function(screen) closed = screen end)
ok(current.isOpaque == true, "import screen pauses the screen beneath it")
current:update(1)
ok(current ~= nil, "active extraction keeps its progress screen open")

status.state = "ready"
current:update(1)
ok(popped ~= nil and closed == popped,
  "completed extraction closes after showing the ready state")

local pressed = { b = true }
game.input.wasPressed = function(_, button) return pressed[button] == true end
status.state = "failed"
current = Screen.new(game, importer)
current:update(1 / 60)
ok(current == nil, "a failed import can be dismissed with the normal B input")

pressed = {}
status.state = "picking"
current = Screen.new(game, importer)
current:update(1 / 60)
ok(current ~= nil, "Android picker keeps an existing import screen alive while pending")
status.state = "idle"
current:update(1 / 60)
ok(current == nil, "cancelled Android picker closes a retry screen after state restoration")

print(("%d checks passed (Stadium 2 import screen)"):format(checks))
