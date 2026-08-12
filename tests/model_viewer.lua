local Viewer = {}
Viewer.__index = Viewer

Viewer.MIN_WIDTH = 160
Viewer.MIN_HEIGHT = 144
Viewer.MAX_WIDTH = 3840
Viewer.MAX_HEIGHT = 2160
Viewer.COUNT = 251
Viewer.ENTRIES = Viewer.COUNT * 2
Viewer.SPIN_SPEED = 0.28
Viewer.MIN_ZOOM = 0.25
Viewer.MAX_ZOOM = 3.2
Viewer.ZOOM_STEP = 1.20

local floor = math.floor
local pi = math.pi

local function clamp(value, lo, hi)
  return math.max(lo, math.min(hi, value))
end

local function clampEntry(index)
  index = floor(tonumber(index) or 1)
  return ((index - 1) % Viewer.ENTRIES) + 1
end

local function decodeEntry(index)
  index = clampEntry(index)
  local species = floor((index - 1) / 2) + 1
  local variant = index % 2 == 0 and "shiny" or "normal"
  return species, variant
end

local function encodeEntry(species, variant)
  species = math.max(1, math.min(Viewer.COUNT, floor(tonumber(species) or 1)))
  return (species - 1) * 2 + (variant == "shiny" and 2 or 1)
end

local function surfaceSize(pixelWidth, pixelHeight)
  pixelWidth = math.max(Viewer.MIN_WIDTH, floor(tonumber(pixelWidth) or Viewer.MAX_WIDTH))
  pixelHeight = math.max(Viewer.MIN_HEIGHT, floor(tonumber(pixelHeight) or Viewer.MAX_HEIGHT))
  local scale = math.max(1, math.ceil(math.max(pixelWidth / Viewer.MAX_WIDTH, pixelHeight / Viewer.MAX_HEIGHT)))
  local width = floor(pixelWidth / scale)
  local height = floor(pixelHeight / scale)
  if width < Viewer.MIN_WIDTH or height < Viewer.MIN_HEIGHT then
    return Viewer.MIN_WIDTH, Viewer.MIN_HEIGHT
  end
  return math.min(Viewer.MAX_WIDTH, width), math.min(Viewer.MAX_HEIGHT, height)
end

local function viewerLayout(width, height)
  width = math.max(Viewer.MIN_WIDTH, floor(tonumber(width) or Viewer.MIN_WIDTH))
  height = math.max(Viewer.MIN_HEIGHT, floor(tonumber(height) or Viewer.MIN_HEIGHT))
  local short = math.min(width, height)
  local textScale = clamp(floor(math.min(width / 400, height / 300)), 1, 4)
  local margin = math.max(8, floor(short * 0.024))
  local header = math.max(52 * textScale, floor(height * 0.11))
  local footer = math.max(58 * textScale, floor(height * 0.15))
  local availableHeight = math.max(64, height - header - footer - margin * 2)
  local viewport = math.max(64, math.min(width - margin * 2, availableHeight))
  local vx = floor((width - viewport) * 0.5)
  local vy = header + margin
  return {
    width = width, height = height, margin = margin, textScale = textScale,
    header = header, footer = footer, viewport = viewport, vx = vx, vy = vy,
  }
end

local function scaledPrintf(g, text, x, y, width, align, scale)
  scale = math.max(1, tonumber(scale) or 1)
  if scale == 1 then
    g.printf(text, x, y, width, align)
    return
  end
  g.push()
  g.translate(x, y)
  g.scale(scale, scale)
  g.printf(text, 0, 0, width / scale, align)
  g.pop()
end

function Viewer.new(game, importer)
  local self = setmetatable({
    game = game,
    importer = importer,
    entry = 1,
    species = 1,
    variant = "normal",
    rig = nil,
    yaw = 0,
    pitch = 0,
    zoom = 1,
    panX = 0,
    panY = 0,
    paused = false,
    dragMode = nil,
    dragX = nil,
    dragY = nil,
    error = nil,
    importRequested = false,
    isOpaque = true,
    holdsUIAnchors = true,
  }, Viewer)
  importer.configure({ count = Viewer.COUNT })
  self:ensureReady()
  return self
end

function Viewer:uiSize()
  local g = love and love.graphics
  if not g then return 1280, 720 end
  local pw, ph
  if g.getPixelDimensions then pw, ph = g.getPixelDimensions() end
  if not pw or not ph then pw, ph = g.getDimensions() end
  return surfaceSize(pw, ph)
end

function Viewer:layout()
  local w, h = self:uiSize()
  return viewerLayout(w, h)
end

function Viewer:windowToSurface(x, y)
  local g = love and love.graphics
  if not g then return tonumber(x) or 0, tonumber(y) or 0 end
  local ww, wh = g.getDimensions()
  local pw, ph = ww, wh
  if g.getPixelDimensions then pw, ph = g.getPixelDimensions() end
  local sw, sh = self:uiSize()
  local dpiX = ww > 0 and pw / ww or 1
  local dpiY = wh > 0 and ph / wh or 1
  local fit = math.max(1, floor(math.min(pw / sw, ph / sh)))
  local ox = (pw - sw * fit) * 0.5
  local oy = (ph - sh * fit) * 0.5
  return ((tonumber(x) or 0) * dpiX - ox) / fit,
         ((tonumber(y) or 0) * dpiY - oy) / fit
end

function Viewer:ensureReady()
  if self.importer.available(Viewer.COUNT) then
    if not self.rig then self:loadEntry() end
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

function Viewer:releaseRig()
  if self.rig and self.rig.release then self.rig:release() end
  self.rig = nil
end

function Viewer:resetView()
  self.yaw = 0
  self.pitch = 0
  self.zoom = 1
  self.panX = 0
  self.panY = 0
end

function Viewer:zoomBy(steps)
  steps = tonumber(steps) or 0
  if steps == 0 then return self.zoom end
  self.zoom = clamp(self.zoom * (Viewer.ZOOM_STEP ^ steps), Viewer.MIN_ZOOM, Viewer.MAX_ZOOM)
  return self.zoom
end

function Viewer:loadEntry()
  self:releaseRig()
  self.species, self.variant = decodeEntry(self.entry)
  self:resetView()
  self.error = nil
  local rig, err = self.importer.newRenderer(self.species, self.variant, {
    yaw = 0,
    pitch = 0,
    fov = 35 * pi / 180,
    flipY = true,
    textureFilter = "linear",
    anisotropy = 8,
    ambient = { 0.62, 0.62, 0.62 },
    diffuse = { 0.62, 0.62, 0.62 },
  })
  if not rig then
    self.error = err or "Unable to load model"
    return false
  end
  rig:setContext("idle", true)
  self.rig = rig
  return true
end

function Viewer:setEntry(index)
  self.entry = clampEntry(index)
  self.species, self.variant = decodeEntry(self.entry)
  if self.importer.available(Viewer.COUNT) then self:loadEntry() end
  return self.entry
end

function Viewer:next()
  return self:setEntry(self.entry + 1)
end

function Viewer:previous()
  return self:setEntry(self.entry - 1)
end

function Viewer:toggleVariant()
  return self:setEntry(encodeEntry(self.species, self.variant == "shiny" and "normal" or "shiny"))
end

function Viewer:animationCount()
  return self.rig and self.rig.model and self.rig.model.anims and #self.rig.model.anims or 0
end

function Viewer:setAnimationIndex(index)
  local count = self:animationCount()
  if count <= 0 or not self.rig then return false end
  index = ((floor(tonumber(index) or 1) - 1) % count) + 1
  return self.rig:setAnimation(index, true)
end

function Viewer:nextAnimation()
  if not self.rig then return false end
  return self:setAnimationIndex((self.rig.animIndex or 0) + 1)
end

function Viewer:previousAnimation()
  if not self.rig then return false end
  return self:setAnimationIndex((self.rig.animIndex or 1) - 1)
end

function Viewer:onKeyPressed(key)
  if key == "left" or key == "a" then
    self:previous()
  elseif key == "right" or key == "d" then
    self:next()
  elseif key == "s" or key == "up" or key == "down" then
    self:toggleVariant()
  elseif key == "pageup" or key == "q" or key == "[" then
    self:previousAnimation()
  elseif key == "pagedown" or key == "e" or key == "]" then
    self:nextAnimation()
  elseif key == "space" then
    self.paused = not self.paused
  elseif key == "=" or key == "+" or key == "kp+" then
    self:zoomBy(1)
  elseif key == "-" or key == "_" or key == "kp-" then
    self:zoomBy(-1)
  elseif key == "r" then
    self:resetView()
  elseif key == "home" then
    self:setEntry(1)
  elseif key == "end" then
    self:setEntry(Viewer.ENTRIES)
  elseif key == "escape" and self.game and self.game.stack then
    self:releaseRig()
    self.game.stack:pop()
  end
end

function Viewer:onWheelMoved(_, dy)
  return self:zoomBy(dy)
end

function Viewer:onMousePressed(x, y, button)
  local sx, sy = self:windowToSurface(x, y)
  local l = self:layout()
  if sx < l.vx or sy < l.vy or sx > l.vx + l.viewport or sy > l.vy + l.viewport then return false end
  if button == 1 then
    self.dragMode = "pan"
  elseif button == 2 or button == 3 then
    self.dragMode = "orbit"
  else
    return false
  end
  self.dragX, self.dragY = sx, sy
  return true
end

function Viewer:onMouseMoved(x, y)
  if not self.dragMode then return false end
  local sx, sy = self:windowToSurface(x, y)
  local dx, dy = sx - (self.dragX or sx), sy - (self.dragY or sy)
  self.dragX, self.dragY = sx, sy
  local viewport = math.max(1, self:layout().viewport)
  if self.dragMode == "pan" then
    self.panX = clamp(self.panX + dx * 2 / viewport, -2.5, 2.5)
    self.panY = clamp(self.panY - dy * 2 / viewport, -2.5, 2.5)
  else
    self.yaw = (self.yaw + dx * 0.008) % (pi * 2)
    self.pitch = clamp(self.pitch + dy * 0.008, -1.35, 1.35)
  end
  return true
end

function Viewer:onMouseReleased(_, _, button)
  if not self.dragMode then return false end
  if (self.dragMode == "pan" and button == 1) or (self.dragMode == "orbit" and (button == 2 or button == 3)) then
    self.dragMode, self.dragX, self.dragY = nil, nil, nil
    return true
  end
  return false
end

function Viewer:pollMouse()
  local m = love and love.mouse
  if not (m and m.getPosition and m.isDown) then return end
  local x, y = m.getPosition()
  local left = m.isDown(1) == true
  local right = m.isDown(2) == true or m.isDown(3) == true
  if left and not self._pollLeft then
    self._pollLeft = true
    if not self.dragMode then self:onMousePressed(x, y, 1) end
  elseif not left and self._pollLeft then
    self._pollLeft = false
    if self.dragMode == "pan" then self:onMouseReleased(x, y, 1) end
  end
  if right and not self._pollRight then
    self._pollRight = true
    if not self.dragMode then self:onMousePressed(x, y, 3) end
  elseif not right and self._pollRight then
    self._pollRight = false
    if self.dragMode == "orbit" then self:onMouseReleased(x, y, 3) end
  end
  if self.dragMode and (left or right) then self:onMouseMoved(x, y) end
end

function Viewer:update(dt)
  if not self:ensureReady() then return end
  self:pollMouse()
  dt = math.max(0, tonumber(dt) or 0)
  if self.dragMode ~= "orbit" then
    self.yaw = (self.yaw + dt * Viewer.SPIN_SPEED) % (pi * 2)
  end
  if self.rig then
    self.rig.yaw = self.yaw
    self.rig.pitch = self.pitch
    if not self.paused then self.rig:step(dt) end
  end
end

local function statusText(status)
  if not status then return "Preparing Stadium 2 model cache" end
  if status.state == "building" then
    local phase = status.phase and ("  " .. tostring(status.phase)) or ""
    return ("Building Stadium 2 model cache  %d/%d%s"):format(status.done or 0, status.total or Viewer.COUNT, phase)
  end
  if status.state == "failed" then return tostring(status.error or "Stadium 2 import failed") end
  return "Preparing Stadium 2 model cache"
end

function Viewer:draw()
  local g = love and love.graphics
  if not g then return end
  local w, h = self:uiSize()
  local layout = viewerLayout(w, h)
  local margin = layout.margin
  local ts = layout.textScale
  g.clear(0.018, 0.022, 0.032, 1)
  g.setColor(0.045, 0.052, 0.072, 1)
  g.rectangle("fill", margin, margin, w - margin * 2, h - margin * 2, 10 * ts, 10 * ts)
  g.setColor(0.12, 0.14, 0.19, 1)
  if g.setLineWidth then g.setLineWidth(math.max(1, ts)) end
  g.rectangle("line", margin + 0.5, margin + 0.5, w - margin * 2 - 1, h - margin * 2 - 1, 10 * ts, 10 * ts)

  if not self.importer.available(Viewer.COUNT) then
    g.setColor(0.94, 0.95, 0.98, 1)
    scaledPrintf(g, "POKEMON STADIUM 2 MODEL VIEWER", margin * 2, h * 0.38, w - margin * 4, "center", ts)
    g.setColor(0.66, 0.7, 0.78, 1)
    scaledPrintf(g, self.error or statusText(self.importer.status()), margin * 2, h * 0.48, w - margin * 4, "center", ts)
    return
  end

  local viewport = layout.viewport
  local vx, vy = layout.vx, layout.vy
  g.setColor(0.008, 0.01, 0.015, 1)
  g.rectangle("fill", vx - 5 * ts, vy - 5 * ts, viewport + 10 * ts, viewport + 10 * ts, 7 * ts, 7 * ts)
  g.setColor(0.14, 0.16, 0.22, 1)
  g.rectangle("line", vx - 4.5 * ts, vy - 4.5 * ts, viewport + 9 * ts, viewport + 9 * ts, 7 * ts, 7 * ts)

  if self.rig then
    local supersample = math.max(1, math.min(2.5, 2048 / math.max(1, viewport)))
    local ok, err = self.rig:draw(vx, vy, viewport, viewport, {
      yaw = self.yaw,
      pitch = self.pitch,
      zoom = self.zoom,
      panX = self.panX,
      panY = self.panY,
      fitPadding = 1.10,
      supersample = supersample,
      msaa = 4,
    })
    if not ok then self.error = err end
  end

  local variantLabel = self.variant == "shiny" and "SHINY" or "NORMAL"
  local variantColor = self.variant == "shiny" and { 1.0, 0.82, 0.3, 1 } or { 0.84, 0.9, 1.0, 1 }
  g.setColor(0.94, 0.95, 0.98, 1)
  scaledPrintf(g, "POKEMON STADIUM 2 MODEL VIEWER", margin * 2, margin + 5 * ts, w - margin * 4, "center", ts)
  g.setColor(variantColor)
  scaledPrintf(g, ("SPECIES %03d   %s   %03d/%03d"):format(self.species, variantLabel, self.entry, Viewer.ENTRIES), margin * 2, margin + 20 * ts, w - margin * 4, "center", ts)

  local infoY = h - layout.footer + 5 * ts
  if self.error then
    g.setColor(1, 0.4, 0.4, 1)
    scaledPrintf(g, self.error, margin * 2, infoY, w - margin * 4, "center", ts)
  else
    local count = self:animationCount()
    local index = self.rig and self.rig.animIndex or 0
    local anim = self.rig and self.rig.model and index > 0 and self.rig.model.anims[index]
    local animName = anim and anim.name ~= "" and anim.name or "bind pose"
    local frame = self.rig and self.rig.frame or 0
    local frames = anim and anim.frames or 0
    g.setColor(0.62, 0.67, 0.76, 1)
    scaledPrintf(g, ("animation %02d/%02d: %s   frame %d/%d   zoom %.2fx   pan %.2f, %.2f%s"):format(index, count, animName, frame + 1, frames, self.zoom, self.panX, self.panY, self.paused and "   PAUSED" or ""), margin * 2, infoY, w - margin * 4, "center", ts)
  end

  g.setColor(0.78, 0.81, 0.88, 1)
  scaledPrintf(g, "LEFT / RIGHT model    S shiny    Q / E or PGUP / PGDN animation    SPACE pause    R reset", margin * 2, h - margin - 29 * ts, w - margin * 4, "center", ts)
  scaledPrintf(g, "MOUSE WHEEL or +/- zoom    LEFT DRAG move    RIGHT DRAG orbit    HOME / END first / last    ESC close", margin * 2, h - margin - 14 * ts, w - margin * 4, "center", ts)
  if g.setLineWidth then g.setLineWidth(1) end
  g.setColor(1, 1, 1, 1)
end

Viewer.clampEntry = clampEntry
Viewer.decodeEntry = decodeEntry
Viewer.encodeEntry = encodeEntry
Viewer.surfaceSize = surfaceSize
Viewer.layoutForSize = viewerLayout
Viewer.clamp = clamp

return Viewer
