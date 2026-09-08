-- Presentation-only bridge between a host battle scene and the persistent
-- Stadium 2 move-FX player. It translates fragment-79 source units at the
-- final renderer boundary; battle mechanics and battle RNG remain untouched.
local Attachment = require(
  "mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_attachment")

local Adapter = {}
Adapter.__index = Adapter

local function vector(value, fallback)
  fallback = fallback or {0, 0, 0}
  if type(value) ~= "table" then return {fallback[1], fallback[2], fallback[3]} end
  return {
    tonumber(value[1] or value.x) or fallback[1],
    tonumber(value[2] or value.y) or fallback[2],
    tonumber(value[3] or value.z) or fallback[3],
  }
end

local function scaled(value, factor)
  value = vector(value)
  return {value[1] * factor, value[2] * factor, value[3] * factor}
end

local function sourceSide(particle)
  local event = particle and particle.event
  local context = event and event.context
  return context and context.sourceSide or "player"
end

-- Effect geometry and battle models are authored in the same Stadium source
-- coordinate system. In classic mode modelMatrix supplies the per-model
-- conversion; arena mode normally resolves to the field's fixed .05 scale.
function Adapter.worldUnits(sceneContext, side)
  local scene = sceneContext and sceneContext.scene
  local host = scene and scene.host
  local actor = host and host.visualActor and host:visualActor(side)
  if host and actor and host.modelMatrix then
    local ok, matrix = pcall(host.modelMatrix, host, side, actor)
    if ok and type(matrix) == "table" then
      local value = math.sqrt((matrix[1] or 0) ^ 2 + (matrix[5] or 0) ^ 2
        + (matrix[9] or 0) ^ 2)
      if value > 0 then return value end
    end
  end
  if scene and scene.arena then
    return tonumber(host and host.arenaScale) or .05
  end
  return .05
end

function Adapter.placementContext(particle, sceneContext)
  sceneContext = type(sceneContext) == "table" and sceneContext or {}
  local side = sourceSide(particle)
  local units = Adapter.worldUnits(sceneContext, side)
  local world = sceneContext.world or {}
  local slot = world.actorSlots and world.actorSlots[side] or world.origin
  local anchor = scaled(slot or {0, world.groundY or 0, 0}, 1 / units)
  local position = vector(particle and particle.position)

  return {
    commonOffset = position,
    transform = {0, 0, 0},
    motion = {0, 0, 0},
    -- func_84104D28's shared origin is battle-controller state. At this
    -- adapter boundary that controller is represented by the source slot.
    sharedOrigin = anchor,
    anchor = {0, 0, 0},
    scale = 1,
    worldUnits = units,
    sourceSide = side,
    resolvers = {
      anchor = function() return anchor end,
      modelAnchor = function() return anchor end,
      anchorY = function() return anchor[2] end,
      -- func_8411E1D4 returns +1 for the first battler and -1 otherwise.
      laneScalar = function() return side == "player" and 1 or -1 end,
    },
  }
end

function Adapter.resolvePlacement(contract, context)
  local resolved, err = Attachment.resolve(contract, context)
  if not resolved then return nil, err end
  if not resolved.resolved then return resolved end
  local units = tonumber(context and context.worldUnits) or .05
  resolved.position = scaled(resolved.position, units)
  if type(resolved.scale) == "table" then
    resolved.scale = scaled(resolved.scale, units)
  else
    resolved.scale = (tonumber(resolved.scale) or 1) * units
  end
  return resolved
end

local function diagnosticText(value)
  if type(value) ~= "table" then return tostring(value) end
  return ("%s (move FX effect=%s program=%s address=%s)"):format(
    tostring(value.message or value.code or "diagnostic"),
    tostring(value.effectId or "?"), tostring(value.programId or "?"),
    value.address and ("0x%08X"):format(value.address) or "?")
end

function Adapter.new(importer, options)
  options = type(options) == "table" and options or {}
  if type(importer) ~= "table" or type(importer.betaBattleFxEnabled) ~= "function"
      or not importer.betaBattleFxEnabled() then
    return nil
  end
  if type(importer.newBattleFxPlayer) ~= "function" then
    return nil, "battle FX player factory is unavailable"
  end

  local self = setmetatable({warn = options.warn, warningKeys = {}}, Adapter)
  local player, err = importer.newBattleFxPlayer({
    contextForParticle = Adapter.placementContext,
    resolvePlacement = Adapter.resolvePlacement,
    warn = function(value) self:_warn(value) end,
  })
  if not player then return nil, err end
  self.player = player
  return self
end

function Adapter:_warn(value)
  local message = diagnosticText(value)
  if self.warningKeys[message] then return end
  self.warningKeys[message] = true
  if type(self.warn) == "function" then pcall(self.warn, message) end
end

function Adapter:trigger(moveId, source, alternate)
  if not self.player then return nil, "battle FX player is unavailable" end
  source = source == "enemy" and "enemy" or "player"
  local effect, err = self.player:trigger({
    moveId = tonumber(moveId), sourceSide = source,
    targetSide = source == "player" and "enemy" or "player",
    alternate = alternate == true, condition = 0,
  })
  if not effect and err then self:_warn(err) end
  return effect, err
end

function Adapter:update(dt)
  if self.player then return self.player:update(dt) end
end

function Adapter:draw(sceneContext)
  if not self.player then return nil end
  local ok, result = pcall(self.player.draw, self.player, sceneContext)
  if not ok then self:_warn(result); return nil end
  return result
end

function Adapter:release()
  if not self.player then return false end
  local player = self.player
  self.player = nil
  return player:release()
end

return Adapter
