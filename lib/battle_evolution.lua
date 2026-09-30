-- In-battle evolution for the 3D battle scene.
--
-- USER-REQUESTED EXTENSION, NOT STADIUM 2 BEHAVIOUR. Stadium 2 battles have
-- no levels and no evolution, so nothing here is decoded from the ROM or the
-- decomp. When a Pokemon evolves at the end of a won battle, the host still
-- runs its own evolution (Gen 1 EvolutionState, Gen 2 EvolutionAnim):
-- timing, the B cancel, the species change, the cries and every text are
-- the host's. This module only presents it in the battle scene instead of
-- the host's evolution screen:
--
--   * the host evolution screen (and, in Gen 1, its text boxes) is hidden;
--   * the camera closes in on the evolving Pokemon, the field dims;
--   * the Pokemon turns white, its old and new models trade places on the
--     host's own flash beats, sparkles rise around it;
--   * the white fades off the new form (or the old one, when cancelled)
--     with a burst of light;
--   * the host's lines show in the Stadium message box.
--
-- The Pokemon evolving need not be the one out (it may have been switched
-- back after it levelled): it is sent out into the player's slot for the
-- evolution, with Stadium's send-out effect.
--
-- Nothing here writes battle state, party data, the host stack or RNG.
local Actor = require("mods.STADIUM2_IMPORTER.lib.battle_actor")
local Renderer = require("mods.STADIUM2_IMPORTER.lib.renderer")
local Camera = require("mods.STADIUM2_IMPORTER.lib.battle_camera")
local Sequence = require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_sequence")

local Evolution = {}
Evolution.__index = Evolution

-- The Stadium message box comes from the Stadium 2 UI mod (STADIUM2_UI, a
-- dependency), through its exports; install() binds the lookup.
local uiExports = function() return nil end
function Evolution.bindUi(fn) uiExports = type(fn) == "function" and fn or function() return nil end end
local function ui()
  local ok, exports = pcall(uiExports)
  return ok and type(exports) == "table" and exports or nil
end

Evolution.CAMERA_TIME = .9   -- seconds for the camera to close in / return
Evolution.WHITE_TIME = 1.1   -- seconds to turn fully white
Evolution.REVEAL_TIME = 1.0  -- seconds for the white to leave the new form
Evolution.DIM = .5           -- field darkening at full strength
Evolution.FRAME = 3.4        -- camera distance in model heights

-- Gen 1 EvolutionState timing (engine/movie/evolution.asm, as the host
-- implements it in src/ui/EvolutionState.lua): 80 frames before the flash
-- loop, 288 frames of it.
local GEN1_GRACE, GEN1_LOOP = 80, 288

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end
local function smooth(t) t = clamp(t, 0, 1) return t * t * (3 - 2 * t) end
local function approach(v, goal, rate, dt)
  if v < goal then return math.min(goal, v + rate * dt) end
  return math.max(goal, v - rate * dt)
end

-- Which of the two pics Gen 1 shows t frames into its flash loop (the
-- host's evoShowsNew: eight rounds of shrinking holds and growing swaps).
function Evolution.gen1ShowsNew(t)
  for b = 1, 8 do
    local hold = 18 - 2 * b
    if t < hold then return false end
    t = t - hold
    local swap = b * 6
    if t < swap then return t % 6 < 3 end
    t = t - swap
  end
  return true
end

local function statesOf(scene)
  local game = scene.game or (scene.screen and scene.screen.game)
    or (scene.battle and scene.battle.game)
  return game, game and game.stack and game.stack.states
end

local function dataOf(scene)
  local game = statesOf(scene)
  return (game and game.data) or (scene.battle and scene.battle.data)
end

function Evolution.dexFor(data, species)
  if type(species) == "number" then return math.floor(species) end
  local def = data and data.pokemon and data.pokemon[species]
  local dex = def and tonumber(def.dex or def.index)
  return dex and math.floor(dex) or nil
end

local function textOf(box)
  if not (box and type(box.visibleText) == "function") then return {} end
  local ok, lines = pcall(box.visibleText, box)
  return ok and type(lines) == "table" and lines or {}
end

-- All of a Gen 1 TextBox's text, pages and lines in order.
local function fullText(box)
  local out = {}
  for _, page in ipairs(type(box.pages) == "table" and box.pages or {}) do
    for _, line in ipairs(page) do out[#out + 1] = tostring(line) end
  end
  return table.concat(out, "\n")
end

local function flatten(text)
  return (tostring(text or ""):gsub("[\n\f\v]+", "\n"))
end

-- Gen 1: the intro box ("What? X is evolving!") shows before the movie is
-- pushed. Its Pokemon is the party member that levelled up this battle and
-- whose own intro text this is (the host's _IsEvolvingText, same format).
local function gen1IntroMon(battle, game, box)
  local party = game.save and game.save.party
  local leveled = battle.leveledUp
  if not (battle.evolutionsChecked and type(party) == "table" and type(leveled) == "table") then
    return nil
  end
  local okR, romText = pcall(require, "src.core.RomText")
  if not okR then return nil end
  local shown = flatten(fullText(box))
  for _, mon in ipairs(party) do
    if leveled[mon] then
      local def = game.data.pokemon[mon.species]
      local name = mon.nickname or (def and def.name)
      if name then
        local ok, expect = pcall(romText, game.data, "_IsEvolvingText", "What?\n%s is\nevolving!", name)
        if ok and type(expect) == "string" and flatten(expect) == shown then return mon end
      end
    end
  end
  return nil
end

-- The host's evolution, as { mon, from, to, phase, showsNew, progress,
-- lines, hides } or nil. phase: announce | flash | evolved | canceled.
function Evolution.gen1Info(scene)
  local battle = scene.battle
  local game, states = statesOf(scene)
  if not (battle and states and game) then return nil end
  local base
  for i = #states, 1, -1 do
    if states[i] == battle then base = i break end
  end
  if not base or base == #states then return nil end
  local okE, EvolutionState = pcall(require, "src.ui.EvolutionState")
  local okT, TextBox = pcall(require, "src.render.TextBox")
  local movie, boxes = nil, {}
  for i = base + 1, #states do
    local s = states[i]
    local mt = type(s) == "table" and getmetatable(s) or nil
    if okE and mt == EvolutionState then movie = s
    elseif okT and mt == TextBox then boxes[#boxes + 1] = s end
  end
  local top = boxes[#boxes]
  if movie and movie.mon then
    local info = { mon = movie.mon, to = movie.newSpecies, lines = textOf(top), hides = { movie } }
    for _, box in ipairs(boxes) do info.hides[#info.hides + 1] = box end
    local t = tonumber(movie.t) or 0
    if movie.done then
      info.phase = movie.canceled and "canceled" or "evolved"
    elseif movie.loading or t < GEN1_GRACE then
      info.phase, info.from = "announce", movie.mon.species
    else
      info.phase, info.from = "flash", movie.mon.species
      info.showsNew = Evolution.gen1ShowsNew(t - GEN1_GRACE)
      info.progress = clamp((t - GEN1_GRACE) / GEN1_LOOP, 0, 1)
    end
    return info
  end
  if top and #boxes == 1 then
    local mon = gen1IntroMon(battle, game, top)
    if mon then
      return { mon = mon, from = mon.species, phase = "announce", lines = textOf(top), hides = { top } }
    end
  end
  return nil
end

local GEN2_PHASE = { evolving = "announce", cry = "announce", flash = "flash",
  stopped = "canceled" }

function Evolution.gen2Info(scene)
  local screen = scene.screen
  local _, states = statesOf(scene)
  if not (screen and states) then return nil end
  local okA, EvolutionAnim = pcall(require, "src.ui.gen2.EvolutionAnim")
  if not okA then return nil end
  local base, anim
  for i, s in ipairs(states) do
    if s == screen then base = i
    elseif base and type(s) == "table" and getmetatable(s) == EvolutionAnim then anim = s end
  end
  if not (anim and anim.mon) then return nil end
  local phase = GEN2_PHASE[anim.phase] or (anim.canceled and "canceled" or "evolved")
  local info = { mon = anim.mon, from = anim.oldSpecies, to = anim.newSpecies, phase = phase,
    lines = type(anim.lines) == "table" and anim.lines or {}, hides = { anim } }
  if phase == "flash" then
    info.showsNew = anim.showNew == true
    local rounds = type(anim.rounds) == "table" and #anim.rounds or 8
    info.progress = clamp(((anim.round or 1) - 1) / math.max(1, rounds), 0, 1)
  end
  return info
end

function Evolution.hostInfo(scene)
  local ok, info
  if scene.screen then ok, info = pcall(Evolution.gen2Info, scene)
  else ok, info = pcall(Evolution.gen1Info, scene) end
  return ok and info or nil
end

-- ---------------------------------------------------------------- state

local function newActor(scene)
  local proto = scene.actors and scene.actors.player or {}
  return Actor.new("player", { warn = proto.warn, dexOf = proto.dexOf, shiny = proto.shiny,
    formFor = proto.formFor, label = (proto.label or "battle") .. " evolution" })
end

function Evolution.isOut(scene, mon)
  local shown = scene.shownMon and scene:shownMon("player")
  if shown == mon then return true end
  local active = scene.battle and scene.battle.player
  if active == mon or (type(active) == "table" and active.mon == mon) then return true end
  return false
end

function Evolution.new(scene, info)
  local data = dataOf(scene)
  local fromDex = Evolution.dexFor(data, info.from or info.mon.species)
  if not fromDex then return nil end
  local self = setmetatable({ scene = scene, mon = info.mon, data = data, fromDex = fromDex,
    camera = 0, white = 0, dim = 0, time = 0, particles = {}, showNew = false,
    phase = "announce", lines = {}, hides = {} }, Evolution)
  self.oldActor = newActor(scene)
  if not self.oldActor:load(data, info.mon, fromDex) then
    self.oldActor:release()
    return nil
  end
  -- the one evolving may not be the one out: sent out for the evolution.
  -- Gen 2's screen may show a display copy, so the battle's own active
  -- Pokemon (Gen 1 battle.player.mon, Gen 2 battle.player) counts too.
  if not Evolution.isOut(scene, info.mon) then
    self.oldActor:play("entrance", false)
    if scene.battleFx and scene.battleFx.signalEffect then
      pcall(scene.battleFx.signalEffect, scene.battleFx, Sequence.SEND_OUT_ENTRY, "player")
    end
  end
  return self
end

function Evolution:release()
  if self.oldActor then self.oldActor:release() end
  if self.newActor then self.newActor:release() end
  self.oldActor, self.newActor = nil, nil
end

-- Whether the scene can present this evolution (both models ready, and the
-- Stadium box for its text).
function Evolution:ready()
  if self.failed or not (self.oldActor and self.oldActor.renderer) then return false end
  if self.toDex and not (self.newActor and self.newActor.renderer) then return false end
  local api = ui()
  if not (api and type(api.messageAvailable) == "function") then return false end
  local ok, available = pcall(api.messageAvailable)
  return ok and available == true
end

function Evolution:observe(info)
  self.phase = info.phase
  self.lines = info.lines or {}
  self.hides = info.hides or {}
  self.progress = info.progress or self.progress or 0
  if info.to and not self.toDex then
    self.toDex = Evolution.dexFor(self.data, info.to)
    if self.toDex then
      self.newActor = newActor(self.scene)
      if not self.newActor:load(self.data, self.mon, self.toDex) then self.failed = true end
    else
      self.failed = true
    end
  end
  if info.phase == "flash" then self.showNew = info.showsNew == true
  elseif info.phase == "evolved" then self.showNew = true
  else self.showNew = false end
  if (info.phase == "evolved" or info.phase == "canceled") and not self.revealed then
    self.revealed = true
    self:burst(info.phase == "evolved" and 48 or 16)
  end
end

-- ------------------------------------------------------------- particles

local function rng(self)
  -- presentation-only LCG: never the host's battle RNG
  self.seed = ((self.seed or 12345) * 1103515245 + 12345) % 2147483648
  return self.seed / 2147483648
end

function Evolution:spawn(kind)
  local r = rng(self)
  local p = { angle = r * math.pi * 2, life = 0, kind = kind }
  if kind == "burst" then
    p.max = .7 + rng(self) * .5
    p.radius, p.height = .15, .2 + rng(self) * .7
    p.speed = 1.4 + rng(self) * 1.6
    p.rise = (rng(self) - .3) * .8
  else
    p.max = 1.1 + rng(self) * .8
    p.radius = .45 + rng(self) * .35
    p.height = rng(self) * .3
    p.speed = -.15 - rng(self) * .2  -- drawn in, spiralling
    p.rise = .5 + rng(self) * .6
    p.spin = (rng(self) < .5 and -1 or 1) * (1.2 + rng(self))
  end
  p.size = .6 + rng(self) * .8
  self.particles[#self.particles + 1] = p
end

function Evolution:burst(count)
  for _ = 1, count do self:spawn("burst") end
end

function Evolution:update(dt)
  self.time = self.time + dt
  local ending = self.ending
  self.camera = approach(self.camera, ending and 0 or 1, 1 / Evolution.CAMERA_TIME, dt)
  self.dim = approach(self.dim, ending and 0 or 1, 1 / Evolution.CAMERA_TIME, dt)
  if self.phase == "flash" then
    self.white = approach(self.white, 1, 1 / Evolution.WHITE_TIME, dt)
    self.spawnDebt = (self.spawnDebt or 0) + dt * (18 + 50 * (self.progress or 0))
    while self.spawnDebt >= 1 do self.spawnDebt = self.spawnDebt - 1; self:spawn("rise") end
  else
    self.white = approach(self.white, 0, 1 / Evolution.REVEAL_TIME, dt)
  end
  for i = #self.particles, 1, -1 do
    local p = self.particles[i]
    p.life = p.life + dt
    if p.life >= p.max then table.remove(self.particles, i)
    else
      p.radius = math.max(0, p.radius + p.speed * dt)
      p.height = p.height + p.rise * dt
      if p.spin then p.angle = p.angle + p.spin * dt end
    end
  end
  for _, actor in ipairs({ self.oldActor, self.newActor }) do
    if actor then actor:update(dt) end
  end
  self:stepFraming(dt)
end

-- The model standing in the player's slot now, with its white amount.
function Evolution:actor()
  local actor = (self.showNew and self.newActor and self.newActor.renderer) and self.newActor or self.oldActor
  if actor then actor.evolveWhite = smooth(self.white) end
  return actor
end

-- --------------------------------------------------------------- camera

local function apply(m, x, y, z)
  return m[1] * x + m[2] * y + m[3] * z + m[4], m[5] * x + m[6] * y + m[7] * z + m[8],
    m[9] * x + m[10] * y + m[11] * z + m[12]
end

-- World floor, top and position of one form standing in the player's slot.
function Evolution:formBounds(actor)
  if not (actor and actor.renderer and self.scene.modelMatrix) then return nil end
  local okM, matrix = pcall(self.scene.modelMatrix, self.scene, "player", actor)
  local okW, metrics = pcall(actor.renderer.worldMetrics, actor.renderer)
  if not (okM and okW and matrix and metrics) then return nil end
  local floor, top = tonumber(metrics.floor) or 0, tonumber(metrics.height) or 1
  local tx, ty, tz = apply(matrix, 0, top, 0)
  local bx, by, bz = apply(matrix, 0, floor, 0)
  return { x = (tx + bx) / 2, z = (tz + bz) / 2, floor = math.min(by, ty), top = math.max(by, ty) }
end

-- The framing the camera and the effects hold on: both forms together (the
-- one on screen changes on every flash beat; the framing must not), eased
-- towards any change (the new form loading, the Pokemon sent out).
Evolution.FRAMING_RATE = 3 -- per second (exponential ease)
function Evolution:targetBounds()
  local union
  for _, actor in ipairs({ self.oldActor, self.newActor }) do
    local b = self:formBounds(actor)
    if b then
      if not union then union = { x = b.x, z = b.z, floor = b.floor, top = b.top }
      else
        union.floor, union.top = math.min(union.floor, b.floor), math.max(union.top, b.top)
      end
    end
  end
  if not union then return nil end
  return { union.x, (union.floor + union.top) / 2, union.z }, math.max(union.top - union.floor, 1e-3)
end

function Evolution:stepFraming(dt)
  local centre, size = self:targetBounds()
  if not centre then return end
  local f = self.framing
  if not f then
    self.framing = { centre = centre, size = size }
    return
  end
  local k = 1 - math.exp(-Evolution.FRAMING_RATE * (dt or 0))
  for i = 1, 3 do f.centre[i] = f.centre[i] + (centre[i] - f.centre[i]) * k end
  f.size = f.size + (size - f.size) * k
end

-- World centre and size the evolution is framed on.
function Evolution:bounds()
  if not self.framing then self:stepFraming(0) end
  local f = self.framing
  if not f then return nil end
  return f.centre, f.size
end

-- The way the Pokemon in the player's slot faces: towards its opponent's
-- slot (on the ground plane).
function Evolution:facing()
  local scene = self.scene
  if type(scene.actorPosition) ~= "function" then return nil end
  local okP, p = pcall(scene.actorPosition, scene, "player")
  local okE, e = pcall(scene.actorPosition, scene, "enemy")
  if not (okP and okE and p and e) then return nil end
  local dx, dz = e[1] - p[1], e[3] - p[3]
  local len = math.sqrt(dx * dx + dz * dz)
  if len < 1e-6 then return nil end
  return dx / len, dz / len
end

Evolution.ELEVATION = math.rad(12) -- camera height above the Pokemon's middle
Evolution.SWAY = math.rad(10)      -- slow side-to-side sway at the front
Evolution.SWAY_PERIOD = 14         -- seconds

-- The default frame, swung round to the front of the evolving Pokemon by
-- `self.camera`: the eye orbits the Pokemon (yaw, height and distance
-- eased together) instead of cutting across the field.
function Evolution:frame(frame)
  local w = smooth(self.camera)
  if w <= 0 then return frame end
  local centre, size = self:bounds()
  if not centre then return frame end
  local e0, f0 = frame.eye, frame.focus
  -- where the default eye sits around the Pokemon
  local vx, vy, vz = e0[1] - centre[1], e0[2] - centre[2], e0[3] - centre[3]
  local flat0 = math.sqrt(vx * vx + vz * vz)
  local r0 = math.sqrt(flat0 * flat0 + vy * vy)
  if r0 < 1e-6 then return frame end
  local yaw0, elev0 = atan2(vx, vz), atan2(vy, flat0)
  -- the front: along the way it faces
  local fx1, fz1 = self:facing()
  local yaw1 = fx1 and atan2(fx1, fz1) or yaw0
  yaw1 = yaw1 + Evolution.SWAY * math.sin(self.time * 2 * math.pi / Evolution.SWAY_PERIOD)
  local elev1, r1 = Evolution.ELEVATION, size * Evolution.FRAME
  local dyaw = (yaw1 - yaw0 + math.pi) % (2 * math.pi) - math.pi
  local yaw = yaw0 + dyaw * w
  local elev = elev0 + (elev1 - elev0) * w
  local r = r0 + (r1 - r0) * w
  local ex = centre[1] + math.sin(yaw) * math.cos(elev) * r
  local ey = centre[2] + math.sin(elev) * r
  local ez = centre[3] + math.cos(yaw) * math.cos(elev) * r
  local fx = f0[1] + (centre[1] - f0[1]) * w
  local fy = f0[2] + (centre[2] - f0[2]) * w
  local fz = f0[3] + (centre[3] - f0[3]) * w
  local view = Renderer.lookAt(ex, ey, ez, fx, fy, fz)
  local out = {}
  for k, v in pairs(frame) do out[k] = v end
  out.view, out.eye, out.focus = view, { ex, ey, ez }, { fx, fy, fz }
  out.vp = Renderer.matMul(frame.projection, view)
  out.viewProjection = out.vp
  return out
end

-- ---------------------------------------------------------------- drawing

-- Before the models: the field dims and a soft glow gathers behind the
-- Pokemon as it turns white.
function Evolution:drawBackdrop(g, frame, width, height)
  local dim = smooth(self.dim) * Evolution.DIM
  local glow = smooth(self.white)
  if dim <= 0 and glow <= 0 then return end
  g.push("all")
  g.origin()
  g.setShader()
  if g.setDepthMode then g.setDepthMode("always", false) end
  if dim > 0 then
    g.setColor(.02, .03, .08, dim)
    g.rectangle("fill", 0, 0, width, height)
  end
  local centre, size = self:bounds()
  if glow > 0 and centre then
    local x, y, visible = Camera.project(frame, width, height, centre)
    local x2, y2 = Camera.project(frame, width, height, { centre[1], centre[2] + size * .5, centre[3] })
    local r = math.max(8, math.sqrt((x2 - x) ^ 2 + (y2 - y) ^ 2) * 1.6)
    if visible then
      g.setBlendMode("add")
      for i = 6, 1, -1 do
        g.setColor(.55, .75, 1, glow * .06)
        g.circle("fill", x, y, r * i / 4)
      end
    end
  end
  g.pop()
end

local function sparkle(g, x, y, size, alpha)
  g.setColor(.75, .88, 1, alpha * .35)
  g.circle("fill", x, y, size * 1.6)
  g.setColor(1, 1, 1, alpha)
  g.polygon("fill", x - size * 2.2, y, x, y - size * .35, x + size * 2.2, y, x, y + size * .35)
  g.polygon("fill", x, y - size * 2.2, x + size * .35, y, x, y + size * 2.2, x - size * .35, y)
end

-- After the models: the sparkles, and the flash of the reveal.
function Evolution:drawOverlay(g, frame, width, height)
  local centre, size = self:bounds()
  if not centre then return end
  g.push("all")
  g.origin()
  g.setShader()
  if g.setDepthMode then g.setDepthMode("always", false) end
  g.setBlendMode("add")
  local unit = height / 240
  for _, p in ipairs(self.particles) do
    local wx = centre[1] + math.cos(p.angle) * p.radius * size
    local wy = centre[2] + (p.height - .5) * size
    local wz = centre[3] + math.sin(p.angle) * p.radius * size
    local x, y, visible = Camera.project(frame, width, height, { wx, wy, wz })
    if visible then
      local t = p.life / p.max
      local alpha = math.sin(math.pi * clamp(t, 0, 1))
      sparkle(g, x, y, p.size * unit * 1.6, alpha)
    end
  end
  g.pop()
end

-- ----------------------------------------------------------- scene seams

-- Once per scene update (battle_scene.lua updateBattleFx).
function Evolution.step(scene, dt)
  if scene.evolutionDisabled then return end
  local info = Evolution.hostInfo(scene)
  local current = scene.evolution
  if info and info.mon then
    scene.evolutionFailed = scene.evolutionFailed or setmetatable({}, { __mode = "k" })
    if current and current.mon ~= info.mon then
      current:release()
      current = nil
      scene.evolution = nil
    end
    if not current and not scene.evolutionFailed[info.mon] then
      current = Evolution.new(scene, info)
      if not current then scene.evolutionFailed[info.mon] = true end
      scene.evolution = current
    end
    if current then
      current.ending = false
      current:observe(info)
      if current.failed then
        scene.evolutionFailed[info.mon] = true
        current:release()
        scene.evolution, current = nil, nil
      end
    end
  elseif current then
    current.ending = true
    current.hides, current.lines = {}, {}
  end
  if current then
    current:update(dt)
    if current.ending and current.camera <= 0 and current.white <= 0 then
      current:release()
      scene.evolution = nil
    end
  end
end

-- The evolution the scene is presenting (the host's evolution screen hidden),
-- or nil.
function Evolution.presenting(scene)
  local current = scene and scene.evolution
  if not (current and not current.ending and current:ready()) then return nil end
  if scene.defect or not scene.readyFrame then return nil end
  return current
end

-- screen.render_visible: the host evolution screen and its text boxes.
function Evolution.hides(scene, state)
  local current = Evolution.presenting(scene)
  if not current then return false end
  for _, hidden in ipairs(current.hides or {}) do
    if hidden == state then return true end
  end
  return false
end

-- The actor drawn in `side` while presenting: the evolving form in the
-- player's slot, nobody in the opponent's. Returns handled, actor.
function Evolution.actorFor(scene, side)
  local current = Evolution.presenting(scene) or (scene and scene.evolution and scene.evolution.ending
    and scene.evolution:ready() and scene.evolution) or nil
  if not current then return false end
  if side == "enemy" then return true, nil end
  return true, current:actor()
end

-- The camera frame while the evolution is on screen.
function Evolution.sceneFrame(scene, frame)
  local handled = Evolution.actorFor(scene, "player")
  if not handled then return frame end
  local ok, out = pcall(scene.evolution.frame, scene.evolution, frame)
  return ok and out or frame
end

function Evolution.drawBackdropFor(scene, g, frame, width, height)
  if not Evolution.actorFor(scene, "player") then return end
  local ok, err = pcall(scene.evolution.drawBackdrop, scene.evolution, g, frame, width, height)
  if not ok and scene.warn then pcall(scene.warn, "evolution backdrop: " .. tostring(err)) end
end

function Evolution.drawOverlayFor(scene, g, frame, width, height)
  if not Evolution.actorFor(scene, "player") then return end
  local ok, err = pcall(scene.evolution.drawOverlay, scene.evolution, g, frame, width, height)
  if not ok and scene.warn then pcall(scene.warn, "evolution overlay: " .. tostring(err)) end
end

-- ------------------------------------------------------------- the text

local function areaFor(viewport)
  local w, h = viewport.width or 0, viewport.height or 0
  if w >= h then return { x = 0, y = 0, w = w, h = h } end
  return { x = viewport.gameX or 0, y = viewport.gameY or 0,
    w = viewport.gameWidth or w, h = viewport.gameHeight or h }
end

function Evolution.drawHud(scene, viewport, warn)
  local current = Evolution.presenting(scene)
  if not (current and viewport) then return false end
  local api = ui()
  if not (api and type(api.drawMessage) == "function") then return false end
  local lines = {}
  for i, line in ipairs(current.lines or {}) do
    lines[i] = type(api.toLatin1) == "function" and api.toLatin1(tostring(line)) or tostring(line)
  end
  if #lines == 0 then return false end
  return api.drawMessage(areaFor(viewport), lines, "player", warn)
end

-- main.lua: the render.hud and screen.render_visible seams, and the export
-- other UI mods read to stand aside while an evolution is presented.
function Evolution.install(mod, currentScene, warn)
  if not (mod and mod.hooks and type(mod.hooks.wrap) == "function") then return false end
  Evolution.bindUi(function()
    local find = mod.find
    if type(find) ~= "function" then return nil end
    local handle = find(mod, "STADIUM2_UI")
    return handle and handle.exports or nil
  end)
  mod.hooks:wrap("render.hud", function(next, game, viewport, ...)
    local result = next(game, viewport, ...)
    local scene = currentScene()
    if scene then
      -- a mod's Renderer:endFrame wrap can drop the viewport (STADIUM2_UI's
      -- frame_viewport.lua rebuilds it from Renderer:frameRects)
      if type(viewport) ~= "table" then
        local okF, FrameViewport = pcall(require, "mods.STADIUM2_UI.lib.frame_viewport")
        if okF then viewport = FrameViewport.resolve(game, viewport, warn) end
      end
      local ok, err = pcall(Evolution.drawHud, scene, viewport, warn)
      if not ok and warn then pcall(warn, "evolution text: " .. tostring(err)) end
    end
    return result
  end, 115)
  mod.hooks:wrap("screen.render_visible", function(next, state)
    local scene = currentScene()
    if scene then
      local ok, hides = pcall(Evolution.hides, scene, state)
      if ok and hides then return false end
    end
    return next(state)
  end, 121)
  -- the battle's own text box and status boxes stay off while the evolution
  -- is presented (the battle screen shows again once the host evolution
  -- screen is hidden, with its last line still in its box)
  local function ownState(state)
    local scene = currentScene()
    if not (scene and state and Evolution.presenting(scene)) then return false end
    return state == scene.screen or state == scene.battle
  end
  for _, hook in ipairs({ "battle.bottom_ui_visible", "battle.status_hud_visible" }) do
    mod.hooks:wrap(hook, function(next, state, ...)
      local ok, own = pcall(ownState, state)
      if ok and own then return false end
      return next(state, ...)
    end, 125)
  end
  if mod.exports then
    mod.exports.evolutionPresented = function()
      return Evolution.presenting(currentScene()) ~= nil
    end
  end
  return true
end

return Evolution
