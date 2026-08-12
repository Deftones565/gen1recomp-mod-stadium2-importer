package.path = "./?.lua;./?/init.lua;" .. package.path

local Viewer = require("mods.STADIUM2_IMPORTER.tests.model_viewer")

local checks = 0
local function ok(value, message)
  checks = checks + 1
  if not value then error("FAIL " .. message, 0) end
end

local loaded = {}
local rigs = {}
local importer = {}
function importer.configure(options)
  importer.count = options.count
end
function importer.available(count)
  return count == 251
end
function importer.status()
  return { state = "ready", done = 251, total = 251 }
end
function importer.autoImport()
  return true
end
function importer.newRenderer(species, variant, options)
  loaded[#loaded + 1] = { species = species, variant = variant, options = options }
  local rig = {
    model = { anims = { { name = "idle", frames = 40 }, { name = "attack", frames = 20 }, { name = "hit", frames = 12 } } },
    animIndex = 1,
    frame = 0,
    yaw = 0,
    pitch = 0,
  }
  function rig:setContext(name, loop)
    self.context = name
    self.loop = loop
    self.animIndex = 1
    return true
  end
  function rig:setAnimation(index, loop)
    if not self.model.anims[index] then return false end
    self.animIndex = index
    self.loop = loop
    self.frame = 0
    return true
  end
  function rig:step(dt)
    self.lastDt = dt
    self.stepCount = (self.stepCount or 0) + 1
  end
  function rig:release()
    self.released = true
  end
  rigs[#rigs + 1] = rig
  return rig
end

local stack = { popped = false }
function stack:pop() self.popped = true end
local game = { stack = stack }

local viewer = Viewer.new(game, importer)
ok(importer.count == 251, "viewer configures all 251 species")
ok(viewer.entry == 1 and viewer.species == 1 and viewer.variant == "normal", "viewer starts on Bulbasaur normal")
ok(#loaded == 1 and loaded[1].species == 1 and loaded[1].variant == "normal", "first renderer loaded")
ok(loaded[1].options.flipY == true, "viewer requests corrected Stadium vertical orientation")
ok(loaded[1].options.textureFilter == "linear" and loaded[1].options.anisotropy == 8, "viewer requests high quality texture filtering")
ok(viewer.rig.context == "idle" and viewer.rig.loop == true, "idle animation loops")

viewer:onKeyPressed("right")
ok(viewer.entry == 2 and viewer.species == 1 and viewer.variant == "shiny", "right advances to same-species shiny")
viewer:onKeyPressed("right")
ok(viewer.entry == 3 and viewer.species == 2 and viewer.variant == "normal", "right advances from shiny to next species normal")
viewer:onKeyPressed("left")
ok(viewer.entry == 2 and viewer.species == 1 and viewer.variant == "shiny", "left reverses sequence")
viewer:setEntry(1)
viewer:previous()
ok(viewer.entry == 502 and viewer.species == 251 and viewer.variant == "shiny", "left wraps to Celebi shiny")
viewer:next()
ok(viewer.entry == 1 and viewer.species == 1 and viewer.variant == "normal", "right wraps to first entry")
viewer:setEntry(Viewer.encodeEntry(25, "normal"))
viewer:toggleVariant()
ok(viewer.species == 25 and viewer.variant == "shiny", "variant toggle preserves species")
ok(Viewer.encodeEntry(25, "normal") == 49 and Viewer.encodeEntry(25, "shiny") == 50, "paired entry encoding")
local s, v = Viewer.decodeEntry(502)
ok(s == 251 and v == "shiny", "last entry decoding")

viewer:onKeyPressed("e")
ok(viewer.rig.animIndex == 2, "E advances animation")
viewer:onKeyPressed("pagedown")
ok(viewer.rig.animIndex == 3, "PageDown advances animation")
viewer:onKeyPressed("e")
ok(viewer.rig.animIndex == 1, "animation selection wraps forward")
viewer:onKeyPressed("q")
ok(viewer.rig.animIndex == 3, "Q wraps animation backward")

viewer.yaw = 0
viewer:update(1)
ok(math.abs(viewer.yaw - Viewer.SPIN_SPEED) < 0.000001, "slow automatic yaw spin")
ok(viewer.rig.lastDt == 1, "viewer advances source animation")
local beforeSteps = viewer.rig.stepCount
viewer:onKeyPressed("space")
viewer:update(1)
ok(viewer.rig.stepCount == beforeSteps, "space pauses animation")
viewer:onKeyPressed("space")

local oldZoom = viewer.zoom
viewer:onWheelMoved(0, 1)
ok(viewer.zoom > oldZoom, "wheel up zooms in")
for _ = 1, 100 do viewer:onWheelMoved(0, 1) end
ok(viewer.zoom == Viewer.MAX_ZOOM, "zoom clamps at maximum")
for _ = 1, 200 do viewer:onWheelMoved(0, -1) end
ok(viewer.zoom == Viewer.MIN_ZOOM, "zoom clamps at minimum")
viewer:onKeyPressed("r")
ok(viewer.zoom == 1 and viewer.panX == 0 and viewer.panY == 0 and viewer.pitch == 0, "R resets view")
viewer:onKeyPressed("=")
ok(viewer.zoom > 1, "plus/equal keyboard fallback zooms in")
viewer:onKeyPressed("-")
ok(math.abs(viewer.zoom - 1) < 0.000001, "minus keyboard fallback zooms out")

local mouseState = { x = 0, y = 0, left = false, right = false }
_G.love = {
  graphics = {
    getDimensions = function() return 1024, 768 end,
    getPixelDimensions = function() return 1024, 768 end,
  },
  mouse = {
    getPosition = function() return mouseState.x, mouseState.y end,
    isDown = function(button)
      if button == 1 then return mouseState.left end
      if button == 2 or button == 3 then return mouseState.right end
      return false
    end,
  },
}
local l = viewer:layout()
local cx, cy = l.vx + l.viewport * 0.5, l.vy + l.viewport * 0.5
ok(viewer:onMousePressed(cx, cy, 1), "left mouse begins pan inside viewport")
viewer:onMouseMoved(cx + 100, cy + 50)
viewer:onMouseReleased(cx + 100, cy + 50, 1)
ok(viewer.panX > 0 and viewer.panY < 0, "left drag pans model in screen space")
local yawBefore = viewer.yaw
ok(viewer:onMousePressed(cx, cy, 3), "right mouse begins orbit")
viewer:onMouseMoved(cx + 50, cy + 25)
viewer:onMouseReleased(cx + 50, cy + 25, 3)
ok(viewer.yaw ~= yawBefore and viewer.pitch > 0, "right drag manually orbits model")
ok(not viewer:onMousePressed(0, 0, 1), "drag outside viewport is ignored")
viewer:onKeyPressed("r")
mouseState.x, mouseState.y = cx, cy
mouseState.left = true
viewer:pollMouse()
mouseState.x, mouseState.y = cx + 80, cy + 40
viewer:pollMouse()
mouseState.left = false
viewer:pollMouse()
ok(viewer.panX > 0 and viewer.panY < 0, "polled left drag pans without event forwarding")
viewer:onKeyPressed("r")
mouseState.x, mouseState.y = cx, cy
mouseState.right = true
viewer:pollMouse()
mouseState.x, mouseState.y = cx + 40, cy + 20
viewer:pollMouse()
mouseState.right = false
viewer:pollMouse()
ok(viewer.yaw ~= 0 and viewer.pitch > 0, "polled right drag orbits without event forwarding")
_G.love = nil

viewer:releaseRig()
ok(viewer.rig == nil and rigs[#rigs].released == true, "renderer released")

local sw, sh = Viewer.surfaceSize(1024, 768)
ok(sw == 1024 and sh == 768, "1024x768 viewer uses full framebuffer resolution")
sw, sh = Viewer.surfaceSize(1280, 720)
ok(sw == 1280 and sh == 720, "1280x720 viewer uses full framebuffer resolution")
sw, sh = Viewer.surfaceSize(1920, 1080)
ok(sw == 1920 and sh == 1080, "1920x1080 viewer uses full framebuffer resolution")
sw, sh = Viewer.surfaceSize(1366, 768)
ok(sw == 1366 and sh == 768, "1366x768 viewer uses full framebuffer resolution")
sw, sh = Viewer.surfaceSize(720, 1280)
ok(sw == 720 and sh == 1280, "portrait viewer uses full framebuffer resolution")
sw, sh = Viewer.surfaceSize(640, 480)
ok(sw == 640 and sh == 480, "640x480 remains native")
l = Viewer.layoutForSize(1024, 768)
ok(l.vx >= 0 and l.vy >= 0 and l.vx + l.viewport <= 1024 and l.vy + l.viewport <= 768, "viewer viewport stays inside 1024x768")
l = Viewer.layoutForSize(720, 1280)
ok(l.vx >= 0 and l.vy >= 0 and l.vx + l.viewport <= 720 and l.vy + l.viewport <= 1280, "viewer viewport stays inside portrait surface")

print(("%d checks passed (Stadium 2 model viewer)"):format(checks))
