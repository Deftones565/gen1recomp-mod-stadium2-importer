-- Persistent, deterministic Stadium 2 battle-effect runtime.
--
-- This layer owns effect and particle lifetime.  ROM decoding, route
-- selection, motion, attachments, materials, and drawing deliberately stay
-- outside it.  In particular, a renderer consumes snapshots from this
-- module; it must never reconstruct the particle list from frame zero.
local Native = require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_native")
local NativeObjects = require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_native_objects")
local Lifecycle = require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_lifecycle")
local Material = require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_material")
local Router = require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_router")
local Motion = require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_motion")
local Random = require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_random")

local Runtime = {}
Runtime.__index = Runtime

local function integer(value)
  local number = tonumber(value)
  if number == nil or number ~= math.floor(number) then return nil end
  return math.floor(number)
end

local function vector(value, default)
  if type(value) ~= "table" then
    return {default or 0, default or 0, default or 0}
  end
  return {
    tonumber(value[1] or value.x) or default or 0,
    tonumber(value[2] or value.y) or default or 0,
    tonumber(value[3] or value.z) or default or 0,
  }
end

local function copy(value, seen)
  if type(value) ~= "table" then return value end
  seen = seen or {}
  if seen[value] then return seen[value] end
  local out = {}
  seen[value] = out
  for key, child in pairs(value) do
    out[copy(key, seen)] = copy(child, seen)
  end
  return out
end

local function copyContext(context)
  local out = {}
  for key, value in pairs(type(context) == "table" and context or {}) do
    out[key] = value
  end
  return out
end

local function orderedLess(a, b)
  if a.effectId ~= b.effectId then return a.effectId < b.effectId end
  if a.schedulerIndex ~= b.schedulerIndex then
    return a.schedulerIndex < b.schedulerIndex
  end
  if a.generation ~= b.generation then return a.generation < b.generation end
  if a.particleIndex ~= b.particleIndex then
    return a.particleIndex < b.particleIndex
  end
  return a.id < b.id
end

local function warning(runtime, diagnostic)
  local key = table.concat({tostring(diagnostic.code), tostring(diagnostic.effectId),
    tostring(diagnostic.programId), tostring(diagnostic.address),
    tostring(diagnostic.message)}, "\31")
  runtime._diagnosticKeys = runtime._diagnosticKeys or {}
  if runtime._diagnosticKeys[key] then return end
  runtime._diagnosticKeys[key] = true
  runtime.diagnostics[#runtime.diagnostics + 1] = diagnostic
  if type(runtime.warn) == "function" then
    pcall(runtime.warn, diagnostic)
  end
end

local function diagnostic(runtime, code, effect, fields)
  local out = {
    code = code,
    severity = "warning",
    effectId = effect and effect.id or nil,
    programId = fields and fields.programId or nil,
    address = fields and fields.address or nil,
    kind = fields and fields.kind or nil,
    message = fields and fields.message or code,
  }
  if fields then
    for key, value in pairs(fields) do
      if out[key] == nil then out[key] = value end
    end
  end
  warning(runtime, out)
end

local MOTION_FIELDS = {"age", "lifetime", "position", "velocity", "rotation", "scale", "nativeAnchor", "nativeHidden"}
-- The particle shares the motion state's vectors: nothing outside the motion
-- step writes into them, and the step (in place or not) runs before every
-- refresh, so the values are the same as a per-tick copy.
local function copyMotionFields(particle, motionState)
  for _, field in ipairs(MOTION_FIELDS) do
    if motionState[field] ~= nil then
      particle[field] = motionState[field]
    elseif field == "lifetime" then
      particle[field] = nil
    end
  end
  if motionState.alive ~= nil then
    particle.active = motionState.alive
    particle.alive = motionState.alive
  end
end

local function validateTicks(count)
  local value = integer(count)
  if not value or value < 0 then
    error("battle FX step count must be a non-negative integer", 3)
  end
  return value
end

function Runtime.new(options)
  options = type(options) == "table" and options or {}
  local clockHz = tonumber(options.clockHz) or 30
  if clockHz <= 0 then error("battle FX clockHz must be positive", 2) end
  local catchUpLimit = options.catchUpLimit
  if catchUpLimit ~= nil then
    catchUpLimit = validateTicks(catchUpLimit)
    if catchUpLimit == 0 then error("battle FX catchUpLimit must be positive", 2) end
  end
  local motionOptions = copy(options.motionOptions or {})
  if motionOptions.trigTables == nil then
    local tables=options.catalog and options.catalog.trigTables
    if tables then
      -- Immutable ROM data stays outside per-particle snapshot copies.
      motionOptions.trigTables={
        tableA=function(index) return tables.tableA[index] end,
        tableB=function(index) return tables.tableB[index] end,
      }
    end
  end
  -- A motion-specific RNG wins, so evaluating FX cannot perturb the battle RNG.
  if motionOptions.rng == nil then motionOptions.rng = options.rng end
  -- Fragment-79's random helpers own a separate stream.  Connect the
  -- ROM-backed implementation by default, while leaving explicit resolver
  -- functions authoritative for fixtures and future native integrations.
  local random = options.randomMotion or options.battleFxRandom
  local defaultRandom = random == nil
  if defaultRandom then
    local randomOptions=copy(options.randomOptions or {})
    local tables=options.catalog and options.catalog.trigTables
    if tables then
      local supplied=randomOptions.tables or {}
      if randomOptions.tableA==nil and supplied.a==nil and supplied.A==nil
          and supplied.TA==nil and supplied[1]==nil then randomOptions.tableA=tables.tableA end
      if randomOptions.tableB==nil and supplied.b==nil and supplied.B==nil
          and supplied.TB==nil and supplied[2]==nil then randomOptions.tableB=tables.tableB end
    end
    random = Random.new(randomOptions)
  end
  if random ~= nil then
    if motionOptions.randomScalar == nil and type(random.scalar) == "function" then
      motionOptions.randomScalar = function(variant, bound)
        -- Motion exposes the -1 sentinel as normalizedBound=0x10000 in
        -- resolver context; Random:scalar expects the original signed value.
        if defaultRandom and bound == 0x10000 then bound = -1 end
        return random:scalar(variant, bound)
      end
    end
    local hasTrigTables = random.tableA ~= nil and random.tableB ~= nil
    local nativeMode4Vector={0,0,0}
    if motionOptions.randomVector == nil and type(random.vector) == "function"
        and (not defaultRandom or hasTrigTables) then
      motionOptions.randomVector = function(mode, values, context)
        values = type(values) == "table" and values or {}
        if defaultRandom and mode==4 then
          -- 841063D8 writes D_84190158 only for particle index zero, then
          -- adds the saved signed halfwords for every sibling in the burst.
          if context and context.particleIndex==0 then
            local sampled={}
            for axis=1,3 do
              sampled[axis]=random:scalar(0,values[axis] or 0)
              if sampled[axis]==nil then return nil end
            end
            nativeMode4Vector=sampled
          end
          return {nativeMode4Vector[1],nativeMode4Vector[2],
            nativeMode4Vector[3]}
        end
        local angles = context and (context.angleContext or context.angle) or nil
        return random:vector(mode, values[1], values[2], angles)
      end
    end
  end
  local nativeObjects = options.nativeObjects
  if nativeObjects == nil then
    nativeObjects = NativeObjects.new(options.nativeObjectOptions or {})
  end
  local lifecycle = options.lifecycle
  if lifecycle == nil then
    local lifecycleOptions=copyContext(options.lifecycleOptions or {})
    lifecycleOptions.assets=lifecycleOptions.assets or (options.catalog and options.catalog.lifecycleAssets)
    lifecycle = Lifecycle.new(lifecycleOptions)
  end
  local material = options.material or Material
  local materialOptions=copy(options.materialOptions or {})
  if materialOptions.resolveNativeAlphaGate==nil then
    materialOptions.resolveNativeAlphaGate=function(kind,state,context)
      if kind~="signal" or context.nativeAlphaSignal~=nil then return nil end
      local effectId=context.effectId or state.effectId
      if lifecycle and lifecycle.finishedEffects
          and lifecycle.finishedEffects[effectId] then return 1 end
      return lifecycle and lifecycle.nativeSignal or nil
    end
  end
  return setmetatable({
    catalog = options.catalog or {},
    native = options.native or Native,
    router = options.router or Router,
    motion = options.motion or Motion,
    motionOptions = motionOptions,
    nativeObjects = nativeObjects,
    lifecycle = lifecycle,
    material = material,
    materialOptions = materialOptions,
    writeDynamicAnchor = options.writeDynamicAnchor,
    modelAnimationFinished = options.modelAnimationFinished,
    -- 84107998 marker selection; injected because it needs owner data.
    emissionMarkers = options.emissionMarkers,
    nativeMarkerSelect = 0,
    clockHz = clockHz,
    catchUpLimit = catchUpLimit,
    lifetimeResolver = options.lifetimeResolver,
    rng = options.rng,
    warn = options.warn,
    frame = 0,
    accumulator = 0,
    nextEffectId = 1,
    nextParticleId = 1,
    -- D_8418C950: 300 particle slots shared by every effect; D_8418C954 is
    -- the round-robin allocation cursor (84100260).
    nativePool = {cursor = 0, slots = {}},
    effects = {},
    effectOrder = {},
    diagnostics = {},
    _diagnosticKeys = {},
    released = false,
  }, Runtime)
end

function Runtime:_emitUnsupported(effect, code, fields)
  diagnostic(self, code, effect, fields)
end

function Runtime:_resolveLifetime(effect, particle)
  if type(self.lifetimeResolver) ~= "function" then
    -- Motion may have an authored scale-entry lifetime.  Leave resolution to
    -- it when no explicit runtime resolver was supplied.
    return nil
  end
  local ok, value = pcall(self.lifetimeResolver, particle, particle.event)
  if not ok then
    self:_emitUnsupported(effect, "unsupported-lifetime", {
      programId = particle.event and particle.event.programId,
      address = particle.event and particle.event.address,
      kind = "particle",
      message = tostring(value),
    })
    return nil
  end
  value = tonumber(value)
  if value == nil or value < 0 then
    self:_emitUnsupported(effect, "unsupported-lifetime", {
      programId = particle.event and particle.event.programId,
      address = particle.event and particle.event.address,
      kind = "particle",
      message = "lifetime resolver returned no non-negative lifetime",
    })
    return nil
  end
  return value
end

function Runtime:_particle(effect, source)
  local scaleEntry = source.scale
  local scale = tonumber(scaleEntry and scaleEntry.scale) or 1
  local event = source.event or {}
  local state = {
    id = self.nextParticleId,
    effectId = effect.id,
    schedulerIndex = source.schedulerIndex or 0,
    generation = source.generation or 0,
    particleIndex = source.particleIndex or 0,
    born = source.born or self.frame,
    age = source.age or 0,
    lifetime = nil,
    position = vector(source.position),
    velocity = vector(source.velocity),
    attribute = source.attribute,
    transform = copy(source.transform or {}),
    rotation = {0, 0, 0},
    scale = {scale, scale, scale},
    -- Keep the authored table entry available to lifetime/material workers;
    -- `scale` above is the renderer-facing normalized vector.
    scaleEntry = copy(scaleEntry),
    shapeId = source.material and source.material.shapeId or event.shapeId,
    material = copy(source.material or {}),
    attachment = copy(event.attachment or {}),
    event = copy(event),
    -- 841072BC stores the 84107998 marker at +0x7E (flag 0x2 when secondary).
    nativeMarkerLabel = source.nativeMarkerLabel,
    nativeSecondaryEmission = source.nativeSecondaryEmission,
    active = true,
  }
  -- The resolver receives the source-shaped particle and event, so later
  -- motion/lifecycle workers can use authored fields without re-decoding ROM.
  local resolvedLifetime = self:_resolveLifetime(effect, state)
  local motionInput = copy(source)
  motionInput.id = state.id
  motionInput.effectId = effect.id
  motionInput.event = copy(event)
  if resolvedLifetime ~= nil then motionInput.lifetime = resolvedLifetime end
  local init = self.motion and (self.motion.init or self.motion.initialize)
  local motionState
  if type(init) == "function" then
    local ok, value = pcall(init, motionInput, self.motionOptions)
    if ok and type(value) == "table" then
      motionState = value
    else
      self:_emitUnsupported(effect, "motion-initialization", {
        programId = event.programId, address = event.address, kind = "motion",
        message = ok and "motion initializer returned no state" or tostring(value),
      })
    end
  else
    self:_emitUnsupported(effect, "motion-initialization", {
      programId = event.programId, address = event.address, kind = "motion",
      message = "motion evaluator has no init function",
    })
  end
  self.nextParticleId = self.nextParticleId + 1
  state._motionState = motionState
  if motionState then
    copyMotionFields(state, motionState)
    state.active = motionState.alive ~= false
    state.lifetime = motionState.lifetime
    state._motionDiagnosticKeys = {}
    self:_appendMotionDiagnostics(effect, state, motionState)
  end
  self:_initMaterial(effect, state, source)
  if state.lifetime == 0 then state.active = false end
  return state
end

function Runtime:_appendMotionDiagnostics(effect, particle, motionState)
  if type(motionState) ~= "table" or type(motionState.diagnostics) ~= "table" then
    return
  end
  particle._motionDiagnosticKeys = particle._motionDiagnosticKeys or {}
  for _, item in ipairs(motionState.diagnostics) do
    if type(item) == "table" then
      local code = item.code or "unsupported-motion"
      local address = item.address
      local message = item.message or item.detail or code
      local key = table.concat({tostring(code), tostring(address), tostring(message)}, ":")
      if not particle._motionDiagnosticKeys[key] then
        particle._motionDiagnosticKeys[key] = true
        diagnostic(self, code, effect, {
          severity = item.severity or "warning",
          programId = item.programId or (particle.event and particle.event.programId),
          address = address or (particle.event and particle.event.address),
          kind = item.kind or "motion",
          message = message,
        })
      end
    end
  end
end

function Runtime:_appendMaterialDiagnostics(effect, particle, materialState)
  if type(materialState) ~= "table" or type(materialState.diagnostics) ~= "table" then
    return
  end
  particle._materialDiagnosticKeys = particle._materialDiagnosticKeys or {}
  for _, item in ipairs(materialState.diagnostics) do
    if type(item) == "table" then
      local code = item.code or "unsupported-material"
      local address = item.address or (particle.event and particle.event.address)
      local message = item.message or item.detail or code
      local key = table.concat({tostring(code), tostring(address), tostring(message)}, ":")
      if not particle._materialDiagnosticKeys[key] then
        particle._materialDiagnosticKeys[key] = true
        diagnostic(self, code, effect, {
          severity = item.severity or "warning",
          programId = item.programId or (particle.event and particle.event.programId),
          address = address, kind = item.kind or "material", message = message,
        })
      end
    end
  end
end

function Runtime:_materialSnapshot(state)
  local snapshot = self.material and self.material.snapshot
  if type(snapshot) == "function" then
    local ok, value = pcall(snapshot, state)
    if ok and value ~= nil then
      if self.material.snapshotIsFresh then return value end
      return copy(value)
    end
  end
  return copy(state)
end

function Runtime:_initMaterial(effect, particle, source)
  local init = self.material and (self.material.init or self.material.initialize)
  if type(init) ~= "function" then
    self:_emitUnsupported(effect,"material-initialization",{
      programId=particle.event and particle.event.programId,
      address=particle.event and particle.event.address,kind="material",
      message="material evaluator has no init function"})
    particle._materialState = copy(particle.material)
    return
  end
  local context = copy(self.materialOptions)
  if math.floor((particle.event.flags2 or 0)/4)%2==1
      and context.resetNativeAlphaGlobalGate then context.resetNativeAlphaGlobalGate() end
  for key, value in pairs(effect.context) do context[key] = copy(value) end
  for key, value in pairs(particle.event or {}) do context[key] = copy(value) end
  context.effectId = effect.id
  context.programId = particle.event and particle.event.programId
  context.address = particle.event and particle.event.address
  context.age = particle.age
  context.attribute=source.attribute
  local ok, value = pcall(init, source.material or {}, context)
  if not ok or type(value) ~= "table" then
    self:_emitUnsupported(effect, "material-initialization", {
      programId = particle.event and particle.event.programId,
      address = particle.event and particle.event.address,
      kind = "material",
      message = ok and "material initializer returned no state" or tostring(value),
    })
    particle._materialState = copy(particle.material)
    return
  end
  particle._materialState = value
  particle.material = self:_materialSnapshot(value)
  particle._materialDiagnosticKeys = {}
  self:_appendMaterialDiagnostics(effect, particle, value)
end

function Runtime:_stepMaterial(effect, particle)
  if not particle._materialState then return end
  local step = self.material and (self.material.advance or self.material.step
    or self.material.evaluate)
  if type(step) ~= "function" then
    self:_emitUnsupported(effect,"material-evaluation",{
      programId=particle.event and particle.event.programId,
      address=particle.event and particle.event.address,kind="material",
      message="material evaluator has no step function"})
    return
  end
  local options = copy(self.materialOptions)
  options.delta = options.delta or 1
  options.age = particle.age
  options.effectId = effect.id
  options.programId = particle.event and particle.event.programId
  options.address = particle.event and particle.event.address
  local ok, value = pcall(step, particle._materialState, options)
  if not ok or type(value) ~= "table" then
    self:_emitUnsupported(effect, "material-evaluation", {
      programId = particle.event and particle.event.programId,
      address = particle.event and particle.event.address,
      kind = "material",
      message = ok and "material evaluator returned no state" or tostring(value),
    })
    return
  end
  particle._materialState = value
  particle.material = self:_materialSnapshot(value)
  self:_appendMaterialDiagnostics(effect, particle, value)
  if value.nativeAlphaFinished then particle.active=false;particle.alive=false end
end

function Runtime:_mergeManagerDiagnostics(manager)
  if type(manager) ~= "table" then return end
  local items
  if type(manager.diagnosticSnapshot) == "function" then
    local ok, value = pcall(manager.diagnosticSnapshot, manager)
    if ok then items = value end
  end
  if items == nil and type(manager.snapshot) == "function" then
    local ok, value = pcall(manager.snapshot, manager)
    if ok and type(value) == "table" then items = value.diagnostics end
  end
  if type(items) == "table" then
    for _, item in ipairs(items) do
      if type(item) == "table" then warning(self, copy(item)) end
    end
  end
end

function Runtime:_stepManagers()
  local step = self.nativeObjects and (self.nativeObjects.step or self.nativeObjects.tick)
  if type(step) == "function" then
    local ok, value = pcall(step, self.nativeObjects, 1)
    if not ok then
      self:_emitUnsupported(nil, "native-object-manager", {
        kind = "native-object", message = tostring(value),
      })
    end
  end
  self:_mergeManagerDiagnostics(self.nativeObjects)
  step = self.lifecycle and (self.lifecycle.step or self.lifecycle.update)
  if type(step) == "function" then
    local ok, value = pcall(step, self.lifecycle, 1)
    if not ok then
      self:_emitUnsupported(nil, "lifecycle-manager", {
        kind = "lifecycle", message = tostring(value),
      })
    end
  end
  self:_mergeManagerDiagnostics(self.lifecycle)
end

Runtime.NATIVE_POOL_SIZE = 0x12C

local function hasBit(value, mask)
  return math.floor((tonumber(value) or 0) / mask) % 2 == 1
end

local function slotLive(particle)
  return particle ~= nil and particle.active == true and not particle.nativeDropped
end

-- 84100260: from the cursor, take the first slot whose +0x98 is clear,
-- wrapping at 300. NULL (nil) when all 300 are live; the cursor then stays.
-- Otherwise the cursor moves to the slot after the one taken.
function Runtime:_allocateNativeSlot()
  local pool, size = self.nativePool, Runtime.NATIVE_POOL_SIZE
  local index = pool.cursor
  for _ = 1, size do
    if not slotLive(pool.slots[index]) then
      pool.cursor = (index + 1) % size
      return index
    end
    index = (index + 1) % size
  end
  return nil
end

-- 8410668C: scan slots 0..299 for the first live particle whose descriptor
-- has 0x400000 and whose secondary flag (0x2) equals the new particle's, and
-- return its +0x20 position. 84100174 zeroes +0x20 at allocation and the
-- update writes it, so a particle not yet updated contributes (0,0,0). The
-- new particle occupies its slot during the scan. Returns (0,0,0) when no
-- slot matches: the constructor then adds nothing and skips 84104A00.
function Runtime:nativePoolOrigin(particle)
  local secondary = particle and particle.nativeSecondaryEmission == true
  local slots = self.nativePool.slots
  for index = 0, Runtime.NATIVE_POOL_SIZE - 1 do
    local other = slots[index]
    if slotLive(other) and hasBit(other.event and other.event.flags, 0x400000)
        and (other.nativeSecondaryEmission == true) == secondary then
      if not other.nativeStepped then return {0, 0, 0}, other end
      local anchor, position = other.nativeAnchor or {0, 0, 0}, other.position or {0, 0, 0}
      return {anchor[1] + position[1], anchor[2] + position[2], anchor[3] + position[3]}, other
    end
  end
  return {0, 0, 0}, nil
end

function Runtime:_spawn(effect, previousFrame, frame)
  if effect.emissionCancelled then return end
  -- Program schedulers are authored relative to the move's start, whereas
  -- the runtime clock is shared by every active move.  Keep that local frame
  -- conversion here so a move triggered at presentation frame 240 still
  -- starts its ROM scheduler at local frame zero.
  local previousLocal = previousFrame - effect.originFrame
  local localFrame = frame - effect.originFrame
  local function spawn(source)
    -- 841072BC stops creating the rest of this emission when 84100328
    -- (84100260) returns NULL.
    local slot = self:_allocateNativeSlot()
    if slot == nil then
      self:_emitUnsupported(effect, "native-particle-pool-full", {
        programId = source.event and source.event.programId,
        address = source.event and source.event.address, kind = "particle",
        message = "all 300 native particle slots are live; the rest of this emission is dropped",
      })
      return false
    end
    source.born = source.born + effect.originFrame
    source.nativeSlot = slot
    -- Reserve the slot while the constructor (and 8410668C) runs.
    local reserve = {active = true, event = source.event, nativeSlot = slot,
      nativeSecondaryEmission = source.nativeSecondaryEmission}
    self.nativePool.slots[slot] = reserve
    local state = self:_particle(effect, source)
    state.nativeSlot = slot
    self.nativePool.slots[slot] = state
    effect.particles[#effect.particles + 1] = state
    return true
  end
  for _, execution in ipairs(effect.executions) do
    local particles = self.native.particles(execution, previousLocal, localFrame) or {}
    local index = 1
    while index <= #particles do
      -- One scheduler emission: consecutive particles of one birth.
      local first = particles[index]
      local last = index
      while particles[last + 1] and particles[last + 1].schedulerIndex == first.schedulerIndex
          and particles[last + 1].generation == first.generation do
        last = last + 1
      end
      local event = first.event or {}
      local markers
      if type(self.emissionMarkers) == "function" and (event.mode == 0 or event.mode == 1) then
        local ok, value, reason = pcall(self.emissionMarkers, event, effect.context,
          self.nativeMarkerSelect)
        if ok and type(value) == "table" then markers = value
        else
          self:_emitUnsupported(effect, "unresolved-emission-markers", {
            programId = event.programId, address = event.address, kind = "particle",
            message = ok and (reason or "84107998 marker inputs are unavailable") or tostring(value),
          })
        end
      end
      if markers then
        -- 841072BC runs once per selected marker, each creating the full set.
        for _, marker in ipairs(markers) do
          for i = index, last do
            local source = {}
            for key, value in pairs(particles[i]) do source[key] = value end
            source.nativeMarkerLabel = marker.label
            source.nativeSecondaryEmission = marker.secondary == true or nil
            if not spawn(source) then break end
          end
        end
      else
        for i = index, last do
          if not spawn(particles[i]) then break end
        end
      end
      index = last + 1
    end
  end
end

function Runtime:_stepEffect(effect, previousFrame, frame)
  for _, particle in ipairs(effect.particles) do
    if particle.active then
      -- advance is step without the per-tick state copy (same result).
      local step = self.motion and (self.motion.advance or self.motion.step)
      if type(step) == "function" and particle._motionState then
        local ok, value = pcall(step, particle._motionState, 1,
          self.motionOptions)
      if ok and type(value) == "table" then
          particle._motionState = value
          copyMotionFields(particle, value)
          self:_appendMotionDiagnostics(effect, particle, value)
        else
          self:_emitUnsupported(effect, "motion-evaluation", {
            programId = particle.event and particle.event.programId,
            address = particle.event and particle.event.address,
            kind = "motion",
            message = ok and "motion evaluator returned no state" or tostring(value),
          })
        end
      elseif not particle._motionState then
        self:_emitUnsupported(effect, "motion-evaluation", {
          programId = particle.event and particle.event.programId,
          address = particle.event and particle.event.address,
          kind = "motion",
          message = "particle has no persistent motion state",
        })
      end
      -- +0x20 now holds an updated position (read by 8410668C).
      particle.nativeStepped = true
      self:_stepMaterial(effect, particle)
      if particle.active and self.modelAnimationFinished then
        local ok,finished,err=pcall(self.modelAnimationFinished,particle,frame)
        if ok and finished==true then particle.active=false
        elseif not ok or finished==nil then
          self:_emitUnsupported(effect,'model-animation-completion',{
            programId=particle.event.programId,address=particle.event.address,
            message=tostring(ok and err or finished),kind='particle'})
        end
      end
      local rule=particle.event.transform and particle.event.transform.nativeAnchorTable
      if rule and rule.mode==0 then
        local ok,value,err=false,nil,'native marker-1 pose resolver unavailable'
        if self.writeDynamicAnchor then ok,value,err=pcall(self.writeDynamicAnchor,particle,rule) end
        if not ok or value==nil then
          self:_emitUnsupported(effect,'dynamic-anchor-write',{
            programId=particle.event.programId,address=particle.event.address,
            message=tostring(ok and err or value or err),kind='particle'})
        end
      end
    end
  end
  self:_spawn(effect, previousFrame, frame)
end

local function program(catalog, id)
  return catalog.programs and catalog.programs[id]
end

function Runtime:trigger(context)
  self:touch()
  if self.released then return nil, "battle FX runtime has been released" end
  if type(context) ~= "table" then return nil, "battle FX trigger context is required" end
  local moveId = integer(context.moveId)
  if not moveId then return nil, "battle FX move ID is required" end
  local move = self.catalog.moves and self.catalog.moves[moveId]
  if not move then return nil, "battle FX move is unavailable" end
  local alternate = context.alternate == true
  local variant = context.variant == true
  local select = self.router and (self.router.resolve or self.router.select
    or self.router.channel)
  if type(select) ~= "function" then return nil, "battle FX router is unavailable" end
  local okRoute, dispatch, routeError = pcall(select, move, alternate, variant or nil)
  if not okRoute then return nil, tostring(dispatch) end
  if type(dispatch) ~= "table" then
    return nil, routeError or "battle FX dispatch is unavailable"
  end

  local effect = {
    id = self.nextEffectId,
    moveId = moveId,
    sourceSide = context.sourceSide,
    targetSide = context.targetSide,
    alternate = alternate,
    variant = variant or nil,
    originFrame = self.frame,
    context = copyContext(context),
    executions = {},
    dispatch = copy(dispatch),
    particles = {},
  }
  self.nextEffectId = self.nextEffectId + 1
  effect.context.moveId = moveId
  effect.context.alternate = alternate
  effect.context.effectId = effect.id
  self.effects[effect.id] = effect
  self.effectOrder[#self.effectOrder + 1] = effect.id

  for _, entry in ipairs(dispatch) do
    if entry.kind == "program" then
      local nativeProgram = program(self.catalog, entry.programId)
      if not nativeProgram then
        self:_emitUnsupported(effect, "missing-program", {
          programId = entry.programId,
          kind = "program",
          message = "dispatch references an unavailable native FX program",
        })
      else
        local ok, execution = pcall(self.native.execute, nativeProgram,
          effect.context)
        if ok and execution then
          execution.programId = entry.programId
          -- D_84190178 is global: the latest executed program's value is
          -- what 84107998 reads at every later emission.
          if execution.nativeMarkerSelect ~= nil then
            self.nativeMarkerSelect = execution.nativeMarkerSelect
          end
          for _,item in ipairs(execution.diagnostics or {}) do
            self:_emitUnsupported(effect,item.code,item)
          end
          for _, event in ipairs(execution.scheduled or {}) do
            event.programId = entry.programId
            event.effectId = effect.id
            event.context = copyContext(effect.context)
            if event.descriptorKind == "native-object" then
              local enqueue = self.nativeObjects and
                (self.nativeObjects.enqueue or self.nativeObjects.schedule)
              if type(enqueue) == "function" then
                local okEnqueue, index, enqueueError = pcall(enqueue,
                  self.nativeObjects, event.commandPointer, event)
                if okEnqueue and index ~= nil then
                  event.schedulerIndex = index
                  effect.nativeObjectEvents = effect.nativeObjectEvents or {}
                  effect.nativeObjectEvents[#effect.nativeObjectEvents + 1] = copy(event)
                elseif not okEnqueue then
                  self:_emitUnsupported(effect, "native-object-enqueue", {
                    programId = entry.programId, address = event.address,
                    kind = "native-object", message = tostring(index),
                  })
                elseif type(enqueueError) == "table" then
                  -- The manager owns unsupported-resolution diagnostics.
                  -- They are merged once below, without a runtime duplicate.
                end
              else
                self:_emitUnsupported(effect, "native-object-manager", {
                  programId = entry.programId, address = event.address,
                  kind = "native-object", message = "native-object manager is unavailable",
                })
              end
            end
          end
          effect.executions[#effect.executions + 1] = execution
        else
          self:_emitUnsupported(effect, "program-execution", {
            programId = entry.programId,
            kind = "program",
            message = ok and "native FX program returned no execution"
              or tostring(execution),
          })
        end
      end
    elseif entry.kind == "lifecycle" then
      local lifecycle = self.catalog.lifecycle
        and self.catalog.lifecycle[entry.lifecycleId]
      local spawn = self.lifecycle and self.lifecycle.spawn
      local lifecycleContext = copyContext(effect.context)
      lifecycleContext.familyId = entry.lifecycleId
      lifecycleContext.lifecycleId = entry.lifecycleId
      lifecycleContext.programId = entry.programId
      lifecycleContext.address = lifecycle and lifecycle.init or nil
      if type(spawn) == "function" then
        local okSpawn, instanceId = pcall(spawn, self.lifecycle,
          entry.lifecycleId, lifecycleContext)
        if okSpawn and instanceId ~= nil then
          effect.lifecycleInstances = effect.lifecycleInstances or {}
          effect.lifecycleInstances[#effect.lifecycleInstances + 1] = instanceId
        elseif not okSpawn then
          self:_emitUnsupported(effect, "lifecycle-spawn", {
            programId = entry.programId, address = lifecycleContext.address,
            kind = "lifecycle", message = tostring(instanceId),
          })
        end
      else
        self:_emitUnsupported(effect, "lifecycle-manager", {
          programId = entry.programId, address = lifecycleContext.address,
          kind = "lifecycle", message = "lifecycle manager is unavailable",
        })
      end
    else
      self:_emitUnsupported(effect, "unsupported-dispatch", {
        kind = tostring(entry.kind),
        message = "unknown native FX dispatch kind",
      })
    end
  end

  self:_mergeManagerDiagnostics(self.nativeObjects)
  self:_mergeManagerDiagnostics(self.lifecycle)

  -- Frame zero is a real Stadium tick.  Spawn its zero-time births now so a
  -- caller can inspect the initial snapshot without forcing a fake update.
  self:_spawn(effect, self.frame - 1, self.frame)
  return effect.id
end

-- 841089D8(1), the failed-move path of 841087B8:
-- 84105E3C releases every active slot of the 64-entry scheduler at
-- D_84190150 (pending emitters and native objects); 841003AC (argument 1)
-- resets the background and both battlers' colors and frees every particle
-- except those holding object flag 0x10000 (descriptor bit 0x20000000,
-- 84107170); 84109460(1) -> 841093E8 clears every lifecycle slot.
function Runtime:abortAll()
  self:touch()
  if self.released then return false end
  for _, id in ipairs(self.effectOrder) do
    local effect = self.effects[id]
    if effect then
      effect.emissionCancelled = true
      local kept = {}
      for _, particle in ipairs(effect.particles) do
        local flags = tonumber(particle.event and particle.event.flags) or 0
        if math.floor(flags / 0x20000000) % 2 == 1 and not particle.nativeReleased then
          kept[#kept + 1] = particle
        else
          particle.nativeDropped = true
        end
      end
      effect.particles = kept
    end
  end
  if self.nativeObjects and type(self.nativeObjects.release) == "function" then
    self.nativeObjects:release()
  end
  if self.lifecycle and type(self.lifecycle.release) == "function" then
    self.lifecycle:release()
  end
  return true
end

-- 84108A10(owner): for every live particle owned by `owner` (object +8,
-- the route owner D_84190194 at construction) that holds object flag 0x10000
-- (descriptor bit 0x20000000): clear flags 0x10080, and if it also holds
-- flag 0x8000 (descriptor bit 0x08000000) end it (+0x92 = 0) and hide its
-- visual. Released particles are no longer exempt from abortAll.
function Runtime:releaseHeld(ownerSide)
  self:touch()
  if self.released then return 0 end
  local count = 0
  for _, id in ipairs(self.effectOrder) do
    local effect = self.effects[id]
    local owner = effect and (effect.context.nativeOwnerSide or effect.sourceSide)
    if effect and owner == ownerSide then
      local kept = {}
      for _, particle in ipairs(effect.particles) do
        local flags = tonumber(particle.event and particle.event.flags) or 0
        local held = math.floor(flags / 0x20000000) % 2 == 1 and not particle.nativeReleased
        if held then
          particle.nativeReleased = true
          count = count + 1
          if math.floor(flags / 0x08000000) % 2 == 0 then kept[#kept + 1] = particle
          else particle.nativeDropped = true end
        else
          kept[#kept + 1] = particle
        end
      end
      effect.particles = kept
    end
  end
  return count
end

function Runtime:step(count)
  self:touch()
  if self.released then return self.frame end
  count = validateTicks(count)
  for _ = 1, count do
    local previousFrame = self.frame
    self.frame = self.frame + 1
    for _, id in ipairs(self.effectOrder) do
      local effect = self.effects[id]
      if effect then self:_stepEffect(effect, previousFrame, self.frame) end
    end
    -- Native-object scheduling and lifecycle updates are separate engines.
    -- Their order is part of the runtime contract and each receives one tick.
    self:_stepManagers()
  end
  return self.frame
end

function Runtime:update(dt)
  self:touch()
  if self.released then return self.frame end
  dt = tonumber(dt)
  if dt == nil or dt < 0 then error("battle FX update dt must be non-negative", 2) end
  self.accumulator = self.accumulator + dt * self.clockHz
  local available = math.floor(self.accumulator + 1e-9)
  local advance = available
  if self.catchUpLimit and advance > self.catchUpLimit then
    advance = self.catchUpLimit
  end
  if advance > 0 then
    self.accumulator = self.accumulator - advance
    self:step(advance)
  end
  return self.frame
end

-- Every state change bumps the revision, so read-only consumers can reuse
-- one snapshot until the runtime changes. snapshot() itself always returns
-- a fresh caller-owned copy.
function Runtime:touch()
  self.revision = (self.revision or 0) + 1
end

-- options.shared: read-only view for internal draw consumers. Particles are
-- shallow tables whose nested values are the live runtime tables; valid
-- until the next revision (see Runtime:touch). Default: full copies.
function Runtime:snapshot(options)
  local shared = type(options) == "table" and options.shared == true
  self:_mergeManagerDiagnostics(self.nativeObjects)
  self:_mergeManagerDiagnostics(self.lifecycle)
  local particles = {}
  for _, id in ipairs(self.effectOrder) do
    local effect = self.effects[id]
    if effect then
      for _, particle in ipairs(effect.particles) do
        if particle.active then particles[#particles + 1] = particle end
      end
    end
  end
  table.sort(particles, orderedLess)
  local result = {
    frame = self.frame,
    accumulator = self.accumulator,
    effects = {},
    particles = {},
    materials = {},
    nativeObjects = {},
    lifecycles = {},
    diagnostics = shared and self.diagnostics or copy(self.diagnostics),
  }
  if self.nativeObjects and type(self.nativeObjects.snapshot) == "function" then
    local ok, value = pcall(self.nativeObjects.snapshot, self.nativeObjects)
    if ok then result.nativeObjects = copy(value) end
  end
  if self.lifecycle and type(self.lifecycle.snapshot) == "function" then
    local ok, value = pcall(self.lifecycle.snapshot, self.lifecycle)
    -- Manager:snapshot already returns freshly copied tables.
    if ok then result.lifecycles = value end
  end
  for _, id in ipairs(self.effectOrder) do
    local effect = self.effects[id]
    if effect then
      result.effects[#result.effects + 1] = {
        id = effect.id, moveId = effect.moveId,
        sourceSide = effect.sourceSide, targetSide = effect.targetSide,
        alternate = effect.alternate,
      }
    end
  end
  for index, particle in ipairs(particles) do
    local public={}
    for key,value in pairs(particle) do
      if key~='_motionState' and key~='_motionDiagnosticKeys'
          and key~='_materialState' and key~='_materialDiagnosticKeys' then
        public[key]=value
      end
    end
    result.particles[index] = shared and public or copy(public)
    result.materials[index] = {
      particleId = particle.id,
      effectId = particle.effectId,
      state = shared and public.material or copy(result.particles[index].material),
    }
  end
  return result
end

function Runtime:release()
  self:touch()
  if self.released then return false end
  if self.nativeObjects and type(self.nativeObjects.release) == "function" then
    pcall(self.nativeObjects.release, self.nativeObjects)
  end
  if self.lifecycle and type(self.lifecycle.release) == "function" then
    pcall(self.lifecycle.release, self.lifecycle)
  end
  self.effects = {}
  self.effectOrder = {}
  self.nativePool = {cursor = 0, slots = {}}
  self.released = true
  return true
end

return Runtime
