local Manifest = require("mods.STADIUM2_IMPORTER.lib.effects.dynamic_object_manifest")

local DynamicObject = { manifest = Manifest }

local KOFFING_SPAWN_SCHEDULE = {
  {36,65,8,38,96,115}, {32,65,8,38,96,115}, {36,65,8,38,96,115},
  {44,65,8,38,96,115}, {32,65,8,38,96,115}, {44,65,8,38,96,115},
  {36,65,8,38,96,115}, {32,65,8,38,96,115}, {44,65,8,38,96,115},
  {44,65,8,38,96,115}, {36,65,8,38,96,115}, {44,65,8,38,96,115},
  {32,65,8,38,96,115}, {44,65,8,38,96,115}, {32,65,8,38,96,115},
  {44,65,8,38,96,115}, {36,65,8,38,96,115}, {32,65,8,38,96,115},
}

local SCALE_WAVE_12 = { .5, .65, .8, .95, .875, .8, .725, .65, .575, .5, .425, .35 }

local INITIALIZERS = {
  [0x8100404C] = { initialScale=1, speed=.5, searchSlots=10 },
  [0x81004070] = { initialScale=.1, speed=1, searchSlots=10, jitter={5,5,5} },
  [0x81004190] = { initialScale=.002, speed=.5, searchSlots=10, jitter={10,10,10} },
  [0x81004324] = { initialScale=.5, speed=0, searchSlots=10, jitter={10,10,10} },
  [0x810043D8] = { initialScale=.5, speed=0, searchSlots=10, jitter={30,10,30} },
  [0x8100448C] = { initialScale=20, speed=0, searchSlots=3 },
}

local function vector3(value, fallbackX, fallbackY, fallbackZ)
  if type(value) ~= "table" then return fallbackX or 0, fallbackY or 0, fallbackZ or 0 end
  return tonumber(value[1] or value.x) or fallbackX or 0,
    tonumber(value[2] or value.y) or fallbackY or 0,
    tonumber(value[3] or value.z) or fallbackZ or 0
end

local function randomBelow(runtime, modulus)
  local source = runtime.dynamicObjectRandom
  local value
  if type(source) == "function" then value = source(modulus)
  elseif tonumber(runtime.dynamicObjectRandomValue) then value = runtime.dynamicObjectRandomValue
  else value = math.random(0, modulus - 1) end
  value = math.floor(tonumber(value) or 0)
  return value % modulus
end

local function randomCentered(runtime, radius)
  return randomBelow(runtime, radius * 2) - radius
end

function DynamicObject.profile(species)
  return Manifest.profile(species)
end

function DynamicObject.isExclusiveCarrier(species)
  local profile = Manifest.profile(species)
  return profile ~= nil and profile.ownership == "exclusive-card"
end

function DynamicObject.isCarrierPrimitive(species, primitiveIndex)
  local profile = Manifest.profile(species)
  if not profile then return false end
  if profile.ownership == "exclusive-card" then return true end
  for _, index in ipairs(profile.carrierPrimitives or {}) do
    if index == tonumber(primitiveIndex) then return true end
  end
  return false
end

local function koffingSpawnExpected(runtime)
  if runtime.dynamicObjectEnabled == false then return false end
  local index = math.floor(tonumber(runtime.dynamicObjectIndex) or -1)
  if index < 0 or index >= #KOFFING_SPAWN_SCHEDULE then return false end
  local state = math.floor(tonumber(runtime.animationState) or -1)
  local frame = math.floor(tonumber(runtime.animationFrame) or -1)
  local row = KOFFING_SPAWN_SCHEDULE[index + 1]
  if state == 2 then return frame == row[6] end
  if state == 3 then return frame == row[3] or frame == row[4] or frame == row[5] end
  if state == 4 then return frame == row[2] end
  return frame == row[1]
end

local SPAWNERS = {
  [0x81004620] = koffingSpawnExpected,
  [0x8100474C] = function(runtime) return randomBelow(runtime, 60) == 0 end,
  [0x81004778] = function(runtime) return randomBelow(runtime, 30) == 0 end,
  [0x810047A4] = function(runtime) return randomBelow(runtime, 7) == 0 end,
  [0x810047D0] = function() return true end,
  [0x810047E0] = function(runtime) return randomBelow(runtime, 7) == 0 end,
}

function DynamicObject.spawnExpected(species, runtime)
  runtime = type(runtime) == "table" and runtime or {}
  if runtime.dynamicObjectEnabled == false then return false end
  if runtime.dynamicObjectForceSpawn == true then return true end
  local profile = Manifest.profile(species)
  local strategy = profile and SPAWNERS[profile.routes.spawn]
  return strategy and strategy(runtime) or false
end

local function spawnParticle(emitter, runtime, profile)
  local init = INITIALIZERS[profile.routes.initialize]
  if not init then return false, "unsupported initialize route" end
  emitter.particles = type(emitter.particles) == "table" and emitter.particles or {}
  local slot
  for i = 1, init.searchSlots do
    local particle = emitter.particles[i]
    if not (particle and particle.active) then slot = i break end
  end
  if not slot then return false end

  local ox, oy, oz = vector3(runtime.dynamicObjectOrigin, 0, 0, 0)
  local rx, ry, rz = vector3(runtime.dynamicObjectReference, ox, oy, oz)
  local jitter = init.jitter
  if jitter then
    ox = ox + randomCentered(runtime, jitter[1]) * (tonumber(runtime.modelScaleX) or 1)
    oy = oy + randomCentered(runtime, jitter[2]) * (tonumber(runtime.modelScaleY) or 1)
    oz = oz + randomCentered(runtime, jitter[3]) * (tonumber(runtime.modelScaleZ) or 1)
  end
  local dx, dy, dz = ox - rx, oy - ry, oz - rz
  local length = math.sqrt(dx * dx + dy * dy + dz * dz)
  local speed = tonumber(runtime.dynamicObjectInitialSpeed)
  if speed == nil then speed = init.speed end
  local vx, vy, vz = 0, 0, 0
  if length > 0 then vx, vy, vz = dx / length * speed, dy / length * speed, dz / length * speed end

  local scale = init.initialScale
  local particle = emitter.particles[slot] or {}
  particle.active, particle.age, particle.absolute = true, 0, true
  particle.x, particle.y, particle.z = ox, oy, oz
  particle.vx, particle.vy, particle.vz = vx, vy, vz
  particle.sx, particle.sy, particle.sz, particle.scale = scale, scale, scale, scale
  emitter.particles[slot] = particle
  return true
end

local function commonMove(particle, damping)
  local vx, vy, vz = tonumber(particle.vx) or 0, tonumber(particle.vy) or 0, tonumber(particle.vz) or 0
  particle.x = (tonumber(particle.x) or 0) + vx
  particle.y = (tonumber(particle.y) or 0) + vy
  particle.z = (tonumber(particle.z) or 0) + vz
  particle.vx, particle.vy, particle.vz = vx * damping, vy * damping, vz * damping
end

local UPDATERS = {
  [0x8100512C] = function(p, runtime)
    local growth = tonumber(runtime.dynamicObjectGrowth) or .10000000149011612
    p.age = math.floor(tonumber(p.age) or 0) + 1
    p.sx = (tonumber(p.sx) or 1) + growth
    p.sy = (tonumber(p.sy) or 1) + growth
    p.sz = (tonumber(p.sz) or 1) + growth
    p.y = (tonumber(p.y) or 0) + .5 * (tonumber(runtime.modelScaleY) or 1)
    if p.age >= 16 then p.active = false end
  end,
  [0x81005198] = function(p)
    p.age = math.floor(tonumber(p.age) or 0) + 2
    if p.age >= 16 then p.active = false end
  end,
  [0x810051C0] = function(p, runtime)
    local growth = tonumber(runtime.dynamicObjectGrowth) or .005000000353902578
    p.age = math.floor(tonumber(p.age) or 0) + 1
    p.sx, p.sy, p.sz = (p.sx or 0)+growth, (p.sy or 0)+growth, (p.sz or 0)+growth
    p.y = (tonumber(p.y) or 0) + 1.5 * (tonumber(runtime.modelScaleY) or 1)
    if p.age >= 16 then p.active = false end
  end,
  [0x8100522C] = function(p, runtime)
    local growth = tonumber(runtime.dynamicObjectGrowth) or .10000000149011612
    p.age = math.floor(tonumber(p.age) or 0) + 1
    p.sx, p.sy, p.sz = (p.sx or 0)+growth, (p.sy or 0)+growth, (p.sz or 0)+growth
    p.y = (tonumber(p.y) or 0) + .75 * (tonumber(runtime.modelScaleY) or 1)
    if p.age >= 16 then p.active = false end
  end,
  [0x810052F8] = function(p, runtime)
    p.age = math.floor(tonumber(p.age) or 0) + 1
    p.y = (tonumber(p.y) or 0) - .5 * (tonumber(runtime.modelScaleY) or 1)
    local scale = SCALE_WAVE_12[p.age % 12 + 1]
    p.sx, p.sy, p.sz = scale, scale, scale
    if p.age >= 12 or p.y < 0 then p.active = false end
  end,
  [0x8100537C] = function(p)
    p.age = math.floor(tonumber(p.age) or 0) + 1
    local scale = SCALE_WAVE_12[p.age % 12 + 1]
    p.sx, p.sy, p.sz = scale, scale, scale
    if p.age >= 12 or (tonumber(p.y) or 0) < 0 then p.active = false end
  end,
}

local function stepEmitter(emitter, runtime, profile)
  if runtime.dynamicObjectUpdateEnabled == false then return end
  local update = UPDATERS[profile.routes.update]
  if not update then return end
  local damping = tonumber(runtime.dynamicObjectDamping) or .8999999761581421
  for i = 1, 10 do
    local particle = emitter.particles and emitter.particles[i]
    if particle and particle.active then
      update(particle, runtime)
      commonMove(particle, damping)
      particle.scale = particle.sx
    end
  end
end

local function clampByte(value)
  return math.max(0, math.min(255, math.floor(tonumber(value) or 0)))
end

local RENDERERS = {
  [0x81004A38] = function(age)
    local alpha = clampByte(200 - 13 * age)
    return { frame=math.floor(age/2)+1, alphaByte=alpha,
      primitiveColor={10/255,0,0,alpha/255}, environmentColor={128/255,0,0,0},
      combine={0x3097FF,0x5FFEFE38}, intensity=true }
  end,
  [0x81004B48] = function(age, runtime)
    local baseAlpha = tonumber(runtime.dynamicObjectAlpha or runtime.modelAlphaByte) or 255
    local alpha = age < 10 and clampByte(baseAlpha)
      or clampByte((655 - age * 40) * baseAlpha / 255)
    local alternate = runtime.dynamicObjectGastlyAlternate == true
    local primitive = alternate and {78/255,81/255,151/255,alpha/255}
      or {100/255,70/255,130/255,alpha/255}
    local environment = alternate and {38/255,35/255,96/255,0}
      or {50/255,20/255,70/255,0}
    return { frame=math.floor(age/2)+1, alphaByte=alpha,
      primitiveColor=runtime.dynamicObjectPrimitiveColor or primitive,
      environmentColor=runtime.dynamicObjectEnvironmentColor or environment, intensity=true }
  end,
  [0x81004D44] = function(age)
    local alpha = clampByte(250 - 3 * age)
    return { frame=math.floor(age/2)+1, alphaByte=alpha,
      primitiveColor={1,1,1,alpha/255}, environmentColor={0,0,0,0}, intensity=true }
  end,
  [0x81004E50] = function(age)
    local alpha = clampByte(age < 4 and (180 + 20 * age) or (290 - 10 * age))
    return { frame=math.floor(age/2)+1, alphaByte=alpha,
      primitiveColor={1,1,1,alpha/255}, environmentColor={0,0,0,0}, intensity=true }
  end,
}

function DynamicObject.renderState(species, age, runtime)
  local profile = Manifest.profile(species)
  local renderer = profile and RENDERERS[profile.routes.render]
  if not renderer then return nil, "unsupported render route" end
  age = math.max(0, math.floor(tonumber(age) or 0))
  local state = renderer(age, type(runtime) == "table" and runtime or {})
  state.frame = math.max(1, state.frame or 1)
  state.alphaByte = clampByte(state.alphaByte)
  return state
end

function DynamicObject.updateState(state, key, result, runtime)
  runtime = type(runtime) == "table" and runtime or {}
  local species = math.floor(tonumber(runtime.species) or -1)
  local profile = Manifest.profile(species)
  if not profile then
    state.dynamicObjectDiagnostics = state.dynamicObjectDiagnostics or {}
    state.dynamicObjectDiagnostics[key] = "unsupported dynamic-object species"
    return
  end
  state.dynamicObjectsBySite = type(state.dynamicObjectsBySite) == "table" and state.dynamicObjectsBySite or {}
  local effect = state.dynamicObjectsBySite[key]
  if type(effect) ~= "table" then
    effect = { family=(species == 109 or species == 110) and "koffing-gas" or "dynamic-object",
      kind=profile.name:lower().."-fx", species=species,
      profile=profile, particles={}, emitters={}, lastFrame=nil, textureSlots={} }
    state.dynamicObjectsBySite[key] = effect
  end
  effect.species, effect.profile = species, profile
  effect.emitters = type(effect.emitters) == "table" and effect.emitters or {}
  if #effect.emitters == 0 and type(effect.particles) == "table" and next(effect.particles) ~= nil then
    effect.emitters[1] = { index=0, particles=effect.particles }
  end
  effect.geometry = result.program and result.program.geometry or effect.geometry
  effect.textureSlots = {}
  for i, texture in ipairs(result.program and result.program.textures or {}) do
    effect.textureSlots[i] = (tonumber(texture.slot) or -1) + 1
  end

  local frame = math.max(0, math.floor(tonumber(result.callbackFrame) or tonumber(runtime.callbackFrame) or 0))
  local first = effect.lastFrame == nil or frame < effect.lastFrame
  if first then effect.emitters, effect.particles, effect.lastFrame = {}, {}, frame
  elseif frame > effect.lastFrame then
    for _, emitter in ipairs(effect.emitters) do stepEmitter(emitter, runtime, profile) end
    effect.lastFrame = frame
  end

  local sources = runtime.dynamicObjectEmitters
  if type(sources) ~= "table" or #sources == 0 then
    sources = {{ index=math.floor(tonumber(runtime.dynamicObjectIndex) or 0), bone=result.bone,
      origin=runtime.dynamicObjectOrigin, reference=runtime.dynamicObjectReference }}
  end
  for order, source in ipairs(sources) do
    local index = math.floor(tonumber(source.index) or (order - 1))
    local slot = index + 1
    local emitter = effect.emitters[slot]
    if type(emitter) ~= "table" then emitter={index=index,particles={}}; effect.emitters[slot]=emitter end
    emitter.index, emitter.bone = index, tonumber(source.bone) or emitter.bone
    emitter.origin, emitter.reference = source.origin or emitter.origin, source.reference or emitter.reference
    local spawnFrame = tonumber(emitter.spawnFrame) or -1
    if first or frame > spawnFrame then
      local values = {}
      for name, value in pairs(runtime) do values[name] = value end
      values.dynamicObjectIndex, values.dynamicObjectOrigin = index, emitter.origin
      values.dynamicObjectReference = emitter.reference
      if DynamicObject.spawnExpected(species, values) then spawnParticle(emitter, values, profile) end
      emitter.spawnFrame = frame
    end
  end
  effect.particles = effect.emitters[1] and effect.emitters[1].particles or effect.particles
end

-- Compatibility oracles used by the existing Koffing ASM audit.
function DynamicObject.koffingSpawnExpected(runtime) return koffingSpawnExpected(runtime or {}) end
function DynamicObject.koffingRenderState(age)
  local state = DynamicObject.renderState(109, age)
  return state.frame, state.alphaByte, state.alphaByte / 255
end
function DynamicObject.koffingInitialize(origin, reference, speed)
  local emitter = { particles={} }
  spawnParticle(emitter, {dynamicObjectOrigin=origin,dynamicObjectReference=reference,
    dynamicObjectInitialSpeed=speed}, assert(Manifest.profile(109)))
  return emitter.particles[1]
end

DynamicObject.INITIALIZERS = INITIALIZERS
DynamicObject.SPAWNERS = SPAWNERS
DynamicObject.RENDERERS = RENDERERS
DynamicObject.UPDATERS = UPDATERS

return DynamicObject
