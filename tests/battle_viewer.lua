local BattleViewer = {}
BattleViewer.__index = BattleViewer

BattleViewer.COUNT = 251
BattleViewer.MIN_WIDTH = 320
BattleViewer.MIN_HEIGHT = 240
BattleViewer.MAX_WIDTH = 3840
BattleViewer.MAX_HEIGHT = 2160

local floor = math.floor
local pi = math.pi

local function clamp(value, lo, hi)
  return math.max(lo, math.min(hi, value))
end

local function wrapSpecies(value)
  value = floor(tonumber(value) or 1)
  return ((value - 1) % BattleViewer.COUNT) + 1
end

local function surfaceSize(pixelWidth, pixelHeight)
  pixelWidth = math.max(BattleViewer.MIN_WIDTH, floor(tonumber(pixelWidth) or 1280))
  pixelHeight = math.max(BattleViewer.MIN_HEIGHT, floor(tonumber(pixelHeight) or 720))
  local scale = math.max(1, math.ceil(math.max(pixelWidth / BattleViewer.MAX_WIDTH, pixelHeight / BattleViewer.MAX_HEIGHT)))
  return math.max(BattleViewer.MIN_WIDTH, floor(pixelWidth / scale)),
         math.max(BattleViewer.MIN_HEIGHT, floor(pixelHeight / scale))
end

local function layoutForSize(width, height)
  width = math.max(BattleViewer.MIN_WIDTH, floor(tonumber(width) or 1280))
  height = math.max(BattleViewer.MIN_HEIGHT, floor(tonumber(height) or 720))
  local margin = math.max(12, floor(math.min(width, height) * 0.028))
  local header = math.max(46, floor(height * 0.09))
  local footer = math.max(80, floor(height * 0.13))
  local arenaY = header
  local arenaH = math.max(120, height - header - footer)
  local arenaX = margin
  local arenaW = math.max(200, width - margin * 2)
  local foe = {
    x = arenaX + floor(arenaW * 0.50),
    y = arenaY + floor(arenaH * 0.02),
    w = floor(arenaW * 0.44),
    h = floor(arenaH * 0.54),
  }
  local player = {
    x = arenaX + floor(arenaW * 0.05),
    y = arenaY + floor(arenaH * 0.35),
    w = floor(arenaW * 0.47),
    h = floor(arenaH * 0.60),
  }
  local uiScale = clamp(math.min(width / 1280, height / 720), 0.65, 2.0)
  return {
    width = width,
    height = height,
    margin = margin,
    header = header,
    footer = footer,
    arenaX = arenaX,
    arenaY = arenaY,
    arenaW = arenaW,
    arenaH = arenaH,
    foe = foe,
    player = player,
    uiScale = uiScale,
  }
end

local function scaledPrintf(g, text, x, y, width, align, scale)
  scale = tonumber(scale) or 1
  g.push()
  g.translate(x, y)
  g.scale(scale, scale)
  g.printf(text, 0, 0, width / scale, align or "left")
  g.pop()
end

local function animationLabel(rig)
  if not rig or not rig.model then return "no model" end
  local count = rig.model.anims and #rig.model.anims or 0
  if count <= 0 then return "bind pose" end
  local index = rig.animIndex or 1
  local anim = rig.model.anims[index]
  local name = anim and anim.name or ""
  if name == "" then name = "animation " .. tostring(index) end
  return ("%02d/%02d %s  frame %d/%d"):format(index, count, name, (rig.frame or 0) + 1, anim and anim.frames or 0)
end

function BattleViewer.new(game, importer)
  local self = setmetatable({
    game = game,
    importer = importer,
    selected = "foe",
    playerSpecies = 25,
    foeSpecies = 248,
    playerVariant = "normal",
    foeVariant = "normal",
    playerRig = nil,
    foeRig = nil,
    paused = false,
    error = nil,
    importRequested = false,
    isOpaque = true,
    holdsUIAnchors = true,
  }, BattleViewer)
  importer.configure({ count = BattleViewer.COUNT })
  self:ensureReady()
  return self
end

function BattleViewer:uiSize()
  local g = love and love.graphics
  if not g then return 1280, 720 end
  local pw, ph
  if g.getPixelDimensions then pw, ph = g.getPixelDimensions() end
  if not pw or not ph then pw, ph = g.getDimensions() end
  return surfaceSize(pw, ph)
end

function BattleViewer:layout()
  local w, h = self:uiSize()
  return layoutForSize(w, h)
end

function BattleViewer:releaseRig(side)
  local key = side == "player" and "playerRig" or "foeRig"
  local rig = self[key]
  if rig and rig.release then rig:release() end
  self[key] = nil
end

function BattleViewer:release()
  self:releaseRig("player")
  self:releaseRig("foe")
end

function BattleViewer:loadSide(side)
  local species = side == "player" and self.playerSpecies or self.foeSpecies
  local variant = side == "player" and self.playerVariant or self.foeVariant
  self:releaseRig(side)
  local rig, err = self.importer.newRenderer(species, variant, {
    yaw = side == "player" and -0.38 or 0.38,
    pitch = 0,
    fov = 32 * pi / 180,
    flipY = true,
    textureFilter = "linear",
    anisotropy = 8,
    ambient = { 0.68, 0.68, 0.68 },
    diffuse = { 0.58, 0.58, 0.58 },
    lightDir = side == "player" and { -0.35, 0.75, 0.56 } or { 0.35, 0.75, 0.56 },
  })
  if not rig then
    self.error = err or ("unable to load " .. side .. " model")
    return false
  end
  rig:setContext("idle", true)
  if side == "player" then self.playerRig = rig else self.foeRig = rig end
  self.error = nil
  return true
end

function BattleViewer:loadBattle()
  local a = self:loadSide("player")
  local b = self:loadSide("foe")
  return a and b
end

function BattleViewer:ensureReady()
  if self.importer.available(BattleViewer.COUNT) then
    if not self.playerRig or not self.foeRig then self:loadBattle() end
    return true
  end
  local status = self.importer.status()
  if status and status.state == "failed" then
    self.error = status.error or "Stadium 2 import failed"
    return false
  end
  if not self.importRequested and (not status or status.state ~= "building") then
    self.importRequested = true
    local ok, err = self.importer.autoImport()
    if not ok and err then self.error = err end
  end
  return false
end

function BattleViewer:selectedRig()
  return self.selected == "player" and self.playerRig or self.foeRig
end

function BattleViewer:selectedSpecies()
  return self.selected == "player" and self.playerSpecies or self.foeSpecies
end

function BattleViewer:setSelectedSpecies(value)
  value = wrapSpecies(value)
  if self.selected == "player" then
    self.playerSpecies = value
  else
    self.foeSpecies = value
  end
  if self.importer.available(BattleViewer.COUNT) then self:loadSide(self.selected) end
  return value
end

function BattleViewer:cycleSpecies(delta)
  return self:setSelectedSpecies(self:selectedSpecies() + (tonumber(delta) or 0))
end

function BattleViewer:toggleSelectedVariant()
  if self.selected == "player" then
    self.playerVariant = self.playerVariant == "shiny" and "normal" or "shiny"
  else
    self.foeVariant = self.foeVariant == "shiny" and "normal" or "shiny"
  end
  if self.importer.available(BattleViewer.COUNT) then self:loadSide(self.selected) end
end

function BattleViewer:cycleAnimation(delta)
  local rig = self:selectedRig()
  if not (rig and rig.model and rig.model.anims) then return false end
  local count = #rig.model.anims
  if count <= 0 then return false end
  local index = ((rig.animIndex or 1) - 1 + (tonumber(delta) or 0)) % count + 1
  return rig:setAnimation(index, true)
end

function BattleViewer:onKeyPressed(key)
  if key == "tab" or key == "up" or key == "down" then
    self.selected = self.selected == "player" and "foe" or "player"
  elseif key == "1" then
    self.selected = "player"
  elseif key == "2" then
    self.selected = "foe"
  elseif key == "left" or key == "a" then
    self:cycleSpecies(-1)
  elseif key == "right" or key == "d" then
    self:cycleSpecies(1)
  elseif key == "s" then
    self:toggleSelectedVariant()
  elseif key == "q" or key == "pageup" or key == "[" then
    self:cycleAnimation(-1)
  elseif key == "e" or key == "pagedown" or key == "]" then
    self:cycleAnimation(1)
  elseif key == "space" then
    self.paused = not self.paused
  elseif key == "home" then
    self:setSelectedSpecies(1)
  elseif key == "end" then
    self:setSelectedSpecies(BattleViewer.COUNT)
  elseif key == "escape" and self.game and self.game.stack then
    self:release()
    self.game.stack:pop()
  end
end

function BattleViewer:update(dt)
  if not self:ensureReady() then return end
  if self.paused then return end
  dt = math.max(0, tonumber(dt) or 0)
  if self.playerRig then self.playerRig:step(dt) end
  if self.foeRig then self.foeRig:step(dt) end
end

local function drawArena(g, l)
  local bands = 40
  for i = 0, bands - 1 do
    local t = i / math.max(1, bands - 1)
    local r = 0.025 + t * 0.025
    local gg = 0.045 + t * 0.055
    local b = 0.075 + t * 0.085
    g.setColor(r, gg, b, 1)
    local y = l.arenaY + l.arenaH * i / bands
    g.rectangle("fill", l.arenaX, y, l.arenaW, l.arenaH / bands + 1)
  end
  local cx = l.arenaX + l.arenaW * 0.5
  local groundY = l.arenaY + l.arenaH * 0.72
  g.setColor(0.08, 0.13, 0.16, 1)
  g.ellipse("fill", cx, groundY, l.arenaW * 0.46, l.arenaH * 0.24)
  g.setColor(0.14, 0.21, 0.24, 1)
  g.ellipse("line", cx, groundY, l.arenaW * 0.46, l.arenaH * 0.24)
  g.setColor(0.06, 0.08, 0.11, 0.55)
  g.ellipse("fill", l.player.x + l.player.w * 0.50, l.player.y + l.player.h * 0.82, l.player.w * 0.26, l.player.h * 0.065)
  g.ellipse("fill", l.foe.x + l.foe.w * 0.50, l.foe.y + l.foe.h * 0.83, l.foe.w * 0.22, l.foe.h * 0.055)
end

local function drawHudBox(g, x, y, w, h, selected, scale)
  g.setColor(0.025, 0.03, 0.043, 0.92)
  g.rectangle("fill", x, y, w, h, 9 * scale, 9 * scale)
  if selected then g.setColor(0.95, 0.72, 0.18, 1) else g.setColor(0.18, 0.22, 0.30, 1) end
  if g.setLineWidth then g.setLineWidth(math.max(1, 2 * scale)) end
  g.rectangle("line", x, y, w, h, 9 * scale, 9 * scale)
end

local function statusText(status)
  if not status then return "Preparing Stadium 2 model cache" end
  if status.state == "building" then
    return ("Building Stadium 2 model cache  %d/%d  %s"):format(status.done or 0, status.total or BattleViewer.COUNT, tostring(status.phase or ""))
  end
  if status.state == "failed" then return tostring(status.error or "Stadium 2 import failed") end
  return "Preparing Stadium 2 model cache"
end

function BattleViewer:draw()
  local g = love and love.graphics
  if not g then return end
  local w, h = self:uiSize()
  local l = layoutForSize(w, h)
  local s = l.uiScale
  g.clear(0.012, 0.016, 0.025, 1)
  drawArena(g, l)

  g.setColor(0.94, 0.95, 0.98, 1)
  scaledPrintf(g, "POKEMON STADIUM 2 BATTLE VIEWER", l.margin, l.margin * 0.45, w - l.margin * 2, "center", math.max(0.8, s))

  if not self.importer.available(BattleViewer.COUNT) then
    g.setColor(0.72, 0.76, 0.84, 1)
    scaledPrintf(g, self.error or statusText(self.importer.status()), l.margin * 2, h * 0.48, w - l.margin * 4, "center", s)
    return
  end

  if self.foeRig then
    local ss = math.max(1, math.min(2.0, 1500 / math.max(1, l.foe.h)))
    local ok, err = self.foeRig:draw(l.foe.x, l.foe.y, l.foe.w, l.foe.h, {
      yaw = 0.38,
      pitch = 0,
      fitPadding = 1.05,
      supersample = ss,
      msaa = 4,
    })
    if not ok then self.error = err end
  end

  if self.playerRig then
    local ss = math.max(1, math.min(2.0, 1600 / math.max(1, l.player.h)))
    local ok, err = self.playerRig:draw(l.player.x, l.player.y, l.player.w, l.player.h, {
      yaw = -0.38,
      pitch = 0,
      fitPadding = 1.05,
      supersample = ss,
      msaa = 4,
    })
    if not ok then self.error = err end
  end

  local foeBoxW = l.arenaW * 0.36
  local foeBoxH = math.max(72 * s, l.arenaH * 0.13)
  local foeBoxX = l.arenaX + l.arenaW - foeBoxW - 18 * s
  local foeBoxY = l.arenaY + 14 * s
  drawHudBox(g, foeBoxX, foeBoxY, foeBoxW, foeBoxH, self.selected == "foe", s)
  g.setColor(0.93, 0.94, 0.98, 1)
  scaledPrintf(g, ("FOE  SPECIES %03d  %s"):format(self.foeSpecies, self.foeVariant:upper()), foeBoxX + 14 * s, foeBoxY + 10 * s, foeBoxW - 28 * s, "left", s)
  g.setColor(0.58, 0.64, 0.72, 1)
  scaledPrintf(g, animationLabel(self.foeRig), foeBoxX + 14 * s, foeBoxY + 31 * s, foeBoxW - 28 * s, "left", math.max(0.72, s * 0.82))

  local playerBoxW = l.arenaW * 0.39
  local playerBoxH = math.max(72 * s, l.arenaH * 0.13)
  local playerBoxX = l.arenaX + 18 * s
  local playerBoxY = l.arenaY + l.arenaH - playerBoxH - 14 * s
  drawHudBox(g, playerBoxX, playerBoxY, playerBoxW, playerBoxH, self.selected == "player", s)
  g.setColor(0.93, 0.94, 0.98, 1)
  scaledPrintf(g, ("PLAYER  SPECIES %03d  %s"):format(self.playerSpecies, self.playerVariant:upper()), playerBoxX + 14 * s, playerBoxY + 10 * s, playerBoxW - 28 * s, "left", s)
  g.setColor(0.58, 0.64, 0.72, 1)
  scaledPrintf(g, animationLabel(self.playerRig), playerBoxX + 14 * s, playerBoxY + 31 * s, playerBoxW - 28 * s, "left", math.max(0.72, s * 0.82))

  if self.error then
    g.setColor(1, 0.38, 0.38, 1)
    scaledPrintf(g, self.error, l.margin, h - l.footer + 4 * s, w - l.margin * 2, "center", s)
  else
    g.setColor(0.80, 0.83, 0.90, 1)
    scaledPrintf(g, "TAB / UP / DOWN select side    LEFT / RIGHT species    S shiny    Q / E animation    SPACE pause", l.margin, h - l.footer + 10 * s, w - l.margin * 2, "center", math.max(0.72, s * 0.82))
    scaledPrintf(g, "1 player    2 foe    HOME / END first / last species    ESC close", l.margin, h - l.footer + 36 * s, w - l.margin * 2, "center", math.max(0.72, s * 0.82))
  end

  if g.setLineWidth then g.setLineWidth(1) end
  g.setColor(1, 1, 1, 1)
end

BattleViewer.wrapSpecies = wrapSpecies
BattleViewer.surfaceSize = surfaceSize
BattleViewer.layoutForSize = layoutForSize

return BattleViewer
