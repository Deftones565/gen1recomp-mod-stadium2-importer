-- Full-screen progress UI for the asynchronous Stadium 2 model extraction.
-- It owns no build state: Importer remains the single source of truth.
local Font = require("src.render.Font")

local Screen = {}
Screen.__index = Screen
Screen.isOpaque = true

local W, H = 160, 144
local COMPLETE_HOLD = 0.8

local function clamp(value)
  return math.max(0, math.min(1, tonumber(value) or 0))
end

local function centre(text, y)
  text = tostring(text or "")
  Font.draw(text, math.floor((W - #text * 8) / 2), y)
end

local function clip(text, length)
  text = tostring(text or "")
  if #text <= length then return text end
  return text:sub(1, math.max(0, length - 1)) .. "."
end

local PHASES = {
  scan = "SCANNING ROM",
  index = "INDEXING MODELS",
  build = "BUILDING MODELS",
  model = "BUILDING MODEL",
  animations = "ADDING ANIMATIONS",
  normal = "PACKING NORMAL",
  shiny = "PACKING SHINY",
  picker = "CHOOSE STADIUM 2 ROM",
}

function Screen.new(game, importer, onClose)
  return setmetatable({
    game = game,
    importer = importer,
    onClose = onClose,
    hold = 0,
  }, Screen)
end

function Screen:exit()
  if self.onClose then self.onClose(self) end
end

function Screen:close()
  local stack = self.game and self.game.stack
  if stack and stack:top() == self then stack:pop() end
end

function Screen:update(dt)
  local status = self.importer.status()
  if status.state == "idle" then
    self:close()
    return
  end
  if status.state == "picking" then return end
  if status.state == "ready" then
    self.hold = self.hold + math.max(0, tonumber(dt) or 1 / 60)
    if self.hold >= COMPLETE_HOLD then self:close() end
    return
  end

  if status.state ~= "failed" then return end
  local input = self.game and self.game.input
  if not (input and input.wasPressed) then return end
  if input:wasPressed("b") or input:wasPressed("select") then
    self:close()
  elseif input:wasPressed("a") or input:wasPressed("start") then
    local ok = self.importer.autoImport()
    if not ok then self.importer.request() end
    self.hold = 0
  end
end

function Screen:drawBar(progress)
  local g = love.graphics
  local x, y, w, h = 20, 75, 120, 10
  g.setColor(0.08, 0.10, 0.17, 1)
  g.rectangle("fill", x - 2, y - 2, w + 4, h + 4)
  g.setColor(0.72, 0.77, 0.84, 1)
  g.rectangle("fill", x, y, w, h)
  g.setColor(0.20, 0.45, 0.78, 1)
  g.rectangle("fill", x, y, math.floor(w * clamp(progress) + 0.5), h)
end

function Screen:draw()
  local g = love.graphics
  local status = self.importer.status()
  g.setColor(0.10, 0.16, 0.27, 1)
  g.rectangle("fill", 0, 0, W, H)
  g.setColor(0.88, 0.91, 0.95, 1)
  g.rectangle("fill", 5, 5, W - 10, H - 10)
  g.setColor(0.08, 0.10, 0.17, 1)
  g.rectangle("line", 5, 5, W - 10, H - 10)

  centre("STADIUM 2 IMPORT", 15)
  g.rectangle("fill", 16, 29, W - 32, 1)

  if status.state == "failed" then
    centre("IMPORT FAILED", 43)
    centre(clip(status.phase or "EXTRACTION", 18), 59)
    centre(clip(status.error or "UNKNOWN ERROR", 18), 75)
    centre("A:RETRY", 105)
    centre("B:CLOSE", 117)
    g.setColor(1, 1, 1, 1)
    return
  end

  if status.state == "picking" then
    centre("CHOOSE STADIUM 2 ROM", 50)
    centre("ANDROID FILE PICKER", 70)
    centre("RETURN HERE WHEN DONE", 102)
    g.setColor(1, 1, 1, 1)
    return
  end

  if status.state == "ready" then
    centre("MODEL CACHE READY", 52)
    self:drawBar(1)
    centre(("%d/%d MODELS"):format(status.done or 0,
      status.total or 0), 96)
    g.setColor(1, 1, 1, 1)
    return
  end

  local phase = tostring(status.phase or "build")
  centre(PHASES[phase] or clip(phase:upper(), 18), 43)
  if status.species then
    centre(("POKEMON %03d"):format(status.species), 57)
  else
    centre("READING ASSETS", 57)
  end
  self:drawBar(status.progress)
  centre(("%3d%%"):format(math.floor(clamp(status.progress) * 100 + 0.5)), 91)
  centre(("%d/%d COMPLETE"):format(status.done or 0,
    status.total or 0), 105)
  centre("DO NOT CLOSE THE GAME", 121)
  g.setColor(1, 1, 1, 1)
end

return Screen
