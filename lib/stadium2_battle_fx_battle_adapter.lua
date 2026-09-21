-- Presentation-only bridge between a host battle scene and the persistent
-- Stadium 2 move-FX player. It translates fragment-79 source units at the
-- final renderer boundary; battle mechanics and battle RNG remain untouched.
local Attachment = require(
  "mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_attachment")
local Dispatch = require("mods.STADIUM2_IMPORTER.lib.animation_dispatch")
local Endpoints = require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_endpoints")

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

-- Map posed markers and ROM endpoint rules into the host battle frame.
function Adapter.beamInputs(context,sceneContext)
  local slots=sceneContext and sceneContext.world and sceneContext.world.actorSlots
  local source=context.sourceSide or "player"
  local target=context.targetSide or (source=="player" and "enemy" or "player")
  if not slots or not slots[source] or not slots[target] then return nil end
  local units=Adapter.worldUnits(sceneContext,source)
  local origin=scaled(slots[source],1/units)
  local a,b={0,0,0},{}
  local targetPosition=scaled(slots[target],1/units)
  for i=1,3 do b[i]=targetPosition[i]-origin[i] end
  local actors=sceneContext.scene and sceneContext.scene.actors
  local host=sceneContext.scene and sceneContext.scene.host
  local usedMarkers,profiles=0,0
  local swiftTarget,modelScale,sourceSpecies
  for _,pair in ipairs({{source,a},{target,b}}) do
    local actor=host and host.visualActor and host:visualActor(pair[1])
      or actors and actors[pair[1]]
    local renderer=actor and actor.renderer
    local model=renderer and renderer.model
    if pair[1]==source then sourceSpecies=model and model.species end
    local profile=Dispatch.battleProfile(model and model.fxBattleProfile)
    local position=scaled(slots[pair[1]],1/units)
    local height=0
    if not profile and renderer and renderer.worldMetrics then
      local ok,metrics=pcall(renderer.worldMetrics,renderer)
      if ok and metrics then height=metrics.height*.5 end
    end
    local bytes=model and model.fxDispatch
    local moveRow=(tonumber(context.moveId) or 0)-1
    if pair[1]==source and bytes and moveRow>=0 and #bytes>=(moveRow+1)*20 then
      -- 8411AF6C copies dispatch +0F to owner+661; 84109544 multiplies by .01f.
      local f32=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_float")
      modelScale=f32(bytes:byte(moveRow*20+16)*f32(.01))
    end
    local isTarget=pair[1]==target
    -- Target marker always comes from context 254, but its offset comes from
    -- the currently selected animation (84114730), including idle/hit.
    local current=renderer and renderer.fxDispatchRow
      or Dispatch.CONTEXT_ENTRY[actor and actor.context or "idle"] or 251
    local row=isTarget and 254 or (renderer and renderer.fxDispatchRow)
      or (tonumber(context.moveId) or 0)-1
    local offsetRow=isTarget and current or row
    local point,rotation,center
    local offset={0,0,0}
    local matrix
    if host and host.modelMatrix and actor then
      local ok,value=pcall(host.modelMatrix,host,pair[1],actor)
      if ok and type(value)=="table" then matrix=value end
    end
    if matrix then
      local scale=math.sqrt(matrix[1]^2+matrix[5]^2+matrix[9]^2)
      local function transform(p)
        local result={}
        for k=1,3 do
          local at=(k-1)*4
          result[k]=(matrix[at+1]*p[1]+matrix[at+2]*p[2]
            +matrix[at+3]*p[3]+matrix[at+4])/units
        end
        return result
      end
      if profile then
        height=profile.targetHeight*scale/units
        center=transform({0,profile.centerY,0})[2]
        if bytes and row>=0 and #bytes>=(row+1)*20
            and offsetRow>=0 and #bytes>=(offsetRow+1)*20 then profiles=profiles+1 end
      end
      rotation={}
      for k=1,3 do for j=1,3 do
        rotation[(k-1)*3+j]=scale>0 and matrix[(k-1)*4+j]/scale
          or (k==j and 1 or 0)
      end end
      if bytes and row>=0 and #bytes>=(row+1)*20 and renderer.attachmentPosition then
        local localPoint=renderer:attachmentPosition(bytes:byte(row*20+3))
        if localPoint then point=transform(localPoint);usedMarkers=usedMarkers+1 end
      end
      if bytes and offsetRow>=0 and #bytes>=(offsetRow+1)*20 then
        for k=1,3 do
          local value=bytes:byte(offsetRow*20+12+k)
          offset[k]=value>=128 and value-256 or value
        end
      end
    end
    if isTarget then
      swiftTarget=Endpoints.resolve({position=position,centerY=center or position[2]+height,
        flags=actor and actor.nativeFxFlags or 0,offset=offset,rotation=rotation},false)
      swiftTarget[2]=math.max(0,swiftTarget[2])
      for k=1,3 do swiftTarget[k]=swiftTarget[k]-origin[k] end
    end
    local resolved=Endpoints.resolve({position=position,marker=point,
      centerY=center or position[2]+height,targetHeight=height,
      flags=actor and actor.nativeFxFlags or 0,offset=offset,rotation=rotation},isTarget)
    for k=1,3 do pair[2][k]=resolved[k]-origin[k] end
  end
  local direction={b[1]-a[1],b[2]-a[2],b[3]-a[3]}
  local length=math.sqrt(direction[1]^2+direction[2]^2+direction[3]^2)
  if length==0 then return nil end
  for i=1,3 do direction[i]=direction[i]/length end
  local eye=sceneContext.camera and sceneContext.camera.eye
  local camera
  if eye then
    camera=scaled(eye,1/units)
    for i=1,3 do camera[i]=camera[i]-origin[i] end
  end
  local swiftDirection={swiftTarget[1]-a[1],swiftTarget[2]-a[2],swiftTarget[3]-a[3]}
  local swiftLength=math.sqrt(swiftDirection[1]^2+swiftDirection[2]^2+swiftDirection[3]^2)
  for i=1,3 do swiftDirection[i]=swiftLength>0 and swiftDirection[i]/swiftLength or 0 end
  return {origin=a,direction=direction,swiftDirection=swiftDirection,
    swiftOrigin={a[1]+origin[1],a[2]+origin[2],a[3]+origin[3]},swiftFrameOrigin=origin,
    modelScale=modelScale,sourceSpecies=sourceSpecies,endpointA=a,endpointB=b,cameraEye=camera,
    approximate=profiles<2,attachmentCount=usedMarkers}
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
    resolveBeam = Adapter.beamInputs,
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
  if effect then
    self:finish()
    self.activeEffect=effect
  end
  return effect, err
end

function Adapter:finish()
  if not self.player or not self.activeEffect then return false end
  local effect=self.activeEffect
  self.activeEffect=nil
  return self.player:finish(effect)
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

function Adapter:backgroundColor(base)
  return self.player and self.player:backgroundColor(base) or base
end

function Adapter:release()
  if not self.player then return false end
  local player = self.player
  self.player = nil
  return player:release()
end

return Adapter
