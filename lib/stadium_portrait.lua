-- Stadium 2 status-panel portraits (STADIUM UI option).
--
-- In the game the box under each status card is a live 3D render
-- (michiiik 0ed78d4 / US assembly):
-- * func_8410AA18 allocates two 32x32 16-bit framebuffers (D_84190414/18)
--   and two portrait cameras (D_84190230/320) with func_80038DC8(fovy 10,
--   near 10, far 1280);
-- * func_8411F400 builds a separate model instance of the battler's species
--   at the origin, plays animation selector 0 (idle) and sets its frame to
--   the record's start frame (func_8003EB84 = ModelAnim_SetFrame);
-- * func_8411F4F4 aims the camera at (record x, record y, 0) and places the
--   eye with func_800371B4 (distance, pitch, yaw; 4096-entry sin/cos tables);
-- * func_8411F340 clears the buffer to 0x4A53 (RGBA5551 grey 74,74,74) and
--   renders; func_8413FBC4 draws it as a 32x32 RGBA16 texture.
-- Records come from the ROM table read by func_84113014
-- (stadium_ui_assets.lua, Assets.portraitRecord).
--
-- Emulators without framebuffer emulation draw this box as noise, which is
-- why it looked garbled in the captures.
local Assets = require("mods.STADIUM2_IMPORTER.lib.stadium_ui_assets")
local Renderer = require("mods.STADIUM2_IMPORTER.lib.renderer")

local Portrait = {}
Portrait.SIZE = 32
Portrait.BACKGROUND = { 74 / 255, 74 / 255, 74 / 255, 1 }
Portrait.FOV, Portrait.NEAR, Portrait.FAR = 10, 10, 1280
Portrait.SUBSTITUTE = 0xFC

local LOVE_CANVAS_Y = { 1, 0, 0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1 }
local IDENTITY = { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1 }
local TAU = math.pi * 2

-- func_800371B4 indexes 4096-entry tables with angle >> 4.
local function tableAngle(a)
  a = math.floor(tonumber(a) or 0) % 65536
  return math.floor(a / 16) * 16 * TAU / 65536
end

function Portrait.eye(record)
  local pitch, yaw = tableAngle(record.pitch), tableAngle(record.yaw)
  local d = record.distance
  local cp = math.cos(pitch) * d
  return record.x + math.sin(yaw) * cp, record.y + math.sin(pitch) * d, math.cos(yaw) * cp
end

local slots = {}

-- The portrait renderer for one side: a separate model instance that idles
-- from the record's start frame.
local function slotFor(side, dex, variant, opponent, newRenderer)
  local slot = slots[side]
  local key = tostring(dex) .. ":" .. tostring(variant) .. ":" .. tostring(opponent)
  if slot and slot.key == key then return slot end
  if slot and slot.renderer and slot.renderer.release then pcall(slot.renderer.release, slot.renderer) end
  slots[side] = nil
  local images = Assets.images()
  local record = images and Assets.portraitRecord(images, dex, opponent)
  if not record or tonumber(dex) == Portrait.SUBSTITUTE then return nil end
  local ok, renderer = pcall(newRenderer, dex, variant,
    { textureFilter = "nearest", anisotropy = 4, flipY = false })
  if not ok or not renderer then return nil end
  if renderer.setContext then pcall(renderer.setContext, renderer, "idle", true) end
  if renderer.seekFrame then pcall(renderer.seekFrame, renderer, math.max(0, record.frame or 0)) end
  slot = { key = key, renderer = renderer, record = record }
  slots[side] = slot
  return slot
end

-- Sharp portraits (port extension, requested by the user 2026-09-27; not
-- ROM behaviour): the game renders 32x32. Given the box's on-screen size,
-- the port renders at twice that (rounded up to 32 px steps, capped) and
-- the UI draws it scaled into the same 32x32 box. Without `pixels` the
-- native 32x32 buffer is used.
Portrait.SHARP_MAX = 512
function Portrait.canvasSize(pixels)
  pixels = tonumber(pixels)
  if not pixels or pixels <= Portrait.SIZE then return Portrait.SIZE end
  local size = math.ceil(pixels * 2 / Portrait.SIZE) * Portrait.SIZE
  return math.min(size, Portrait.SHARP_MAX)
end

local function releaseCanvases(slot)
  if slot.canvas and slot.canvas.release then pcall(slot.canvas.release, slot.canvas) end
  if slot.depth and slot.depth.release then pcall(slot.depth.release, slot.depth) end
  slot.canvas, slot.depth, slot.size = nil, nil, nil
end

local function canvases(slot, g, size)
  if slot.canvas and slot.size == size then return slot.canvas, slot.depth end
  releaseCanvases(slot)
  local okC, canvas = pcall(g.newCanvas, size, size,
    { format = "rgba8", readable = true, dpiscale = 1 })
  if not okC then return nil end
  if size == Portrait.SIZE then canvas:setFilter("nearest", "nearest")
  else canvas:setFilter("linear", "linear") end
  local depth
  for _, format in ipairs({ "depth24", "depth16", "depth24stencil8", "depth32f" }) do
    local okD, d = pcall(g.newCanvas, size, size,
      { format = format, readable = false, dpiscale = 1 })
    if okD and d then depth = d break end
  end
  slot.canvas, slot.depth, slot.size = canvas, depth, size
  return canvas, depth
end

-- Render the portrait for `side` and return its 32x32 canvas (nil when the
-- species has no record or the model is unavailable).
-- opts = { dex, variant, opponent, dt, light = {lightDir, ambient, diffuse},
--          pixels = on-screen box size (sharp extension; nil = native 32),
--          newRenderer = fn(dex, variant, options) }
function Portrait.render(side, opts)
  local g = love and love.graphics
  if not (g and opts and opts.dex and type(opts.newRenderer) == "function") then return nil end
  local slot = slotFor(side, opts.dex, opts.variant, opts.opponent, opts.newRenderer)
  if not slot then return nil end
  local renderer, record = slot.renderer, slot.record
  -- step once per frame on the portrait's own clock (providers may be
  -- called more than once per frame)
  local now = love.timer and love.timer.getTime and love.timer.getTime() or 0
  local dt = opts.dt
  if dt == nil then dt = slot.lastTime and math.min(now - slot.lastTime, 0.1) or 0 end
  slot.lastTime = now
  if dt > 0 and renderer.step then pcall(renderer.step, renderer, dt) end
  local canvas, depth = canvases(slot, g, Portrait.canvasSize(opts.pixels))
  if not canvas then return nil end
  local ex, ey, ez = Portrait.eye(record)
  local view = Renderer.lookAt(ex, ey, ez, record.x, record.y, 0)
  local projection = Renderer.matMul(LOVE_CANVAS_Y,
    Renderer.perspective(math.rad(Portrait.FOV), 1, Portrait.NEAR, Portrait.FAR))
  local vp = Renderer.matMul(projection, view)
  local light = opts.light or {}
  g.push("all")
  local ok, err = pcall(function()
    g.setCanvas(depth and { canvas, depthstencil = depth } or { canvas, depth = true })
    g.origin()
    g.setScissor()
    g.clear(Portrait.BACKGROUND[1], Portrait.BACKGROUND[2], Portrait.BACKGROUND[3], 1, true, true)
    for _, pass in ipairs({ "opaque", "additive" }) do
      renderer:drawScene(pass, IDENTITY, {
        viewProjection = vp, viewMatrix = view,
        normalMatrix = Renderer.normalMatrix(0, 0, false),
        lightDir = light.lightDir or { -.4, -.8, -.4 },
        ambient = light.ambient or { .62, .66, .70 },
        diffuse = light.diffuse or { .86, .78, .64 },
        skipHandlers = pass == "additive",
        flipWinding = true, disableCulling = true, tint = { 1, 1, 1, 1 },
      })
    end
  end)
  g.pop()
  if not ok then return nil, err end
  return canvas
end

function Portrait.release()
  for side, slot in pairs(slots) do
    if slot.renderer and slot.renderer.release then pcall(slot.renderer.release, slot.renderer) end
    releaseCanvases(slot)
    slots[side] = nil
  end
end

return Portrait
