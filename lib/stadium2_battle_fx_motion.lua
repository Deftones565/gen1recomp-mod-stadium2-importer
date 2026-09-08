-- Pure Stadium 2 battle-FX particle motion evaluator.
--
-- The ROM reader intentionally exposes controller pointers without executing
-- them.  This module evaluates the parts for which the data contract is
-- explicit (initial vectors, authored velocities, and injected random-vector
-- records) and reports opaque controller pointers as diagnostics.  It never
-- calls the host RNG and never mutates its input tables.
local Motion = {}

local function number(value, fallback)
  value = tonumber(value)
  return value == nil and (fallback or 0) or value
end

local function vector(value, fallback)
  fallback = fallback or {0, 0, 0}
  if type(value) ~= "table" then
    return {number(fallback[1]), number(fallback[2]), number(fallback[3])}
  end
  return {number(value[1], fallback[1]), number(value[2], fallback[2]),
    number(value[3], fallback[3])}
end

local function add(a, b, factor)
  factor = factor or 1
  return {a[1] + b[1] * factor, a[2] + b[2] * factor,
    a[3] + b[3] * factor}
end

local function copy(value, seen)
  if type(value) ~= "table" then return value end
  seen = seen or {}
  if seen[value] then return seen[value] end
  local out = {}
  seen[value] = out
  for key, child in pairs(value) do out[copy(key, seen)] = copy(child, seen) end
  return out
end

local function addDiagnostic(state, code, detail, fields)
  state.diagnostics = state.diagnostics or {}
  local key = tostring(code) .. ":" .. tostring(detail or "")
  state._diagnosticKeys = state._diagnosticKeys or {}
  if state._diagnosticKeys[key] then return end
  state._diagnosticKeys[key] = true
  fields = fields or {}
  state.diagnostics[#state.diagnostics + 1] = {
    code = tostring(code), severity = fields.severity or "warning",
    effectId = state.effectId, programId = state.programId,
    address = fields.address or state.address,
    kind = fields.kind or "motion",
    message = fields.message or tostring(detail or code), detail = detail,
  }
end

-- The ROM reader establishes the record layout in func_8410679C,
-- func_84106AC4, and func_84106F34.  The scalar helper at
-- 0x84105E9C..0x84105F0C calls external variants 0/1 and returns a signed
-- halfword; vector initialization at 0x84105FC8..0x84106094 calls those
-- variants in X/Y/Z order for modes 0/1.  Modes 2/3/5 cross external angle
-- tables and remain behind an explicit resolver.
local function randomContext(state, rng, channel, component, bound)
  local context = {
    effectId = state.effectId, programId = state.programId,
    address = state.address, age = state.age, generation = state.generation,
    channel = channel,
    component = component, bound = bound,
    normalizedBound = bound == -1 and 0x10000 or bound,
    rng = rng,
    angle = copy(state.angleContext or {}),
    angleContext = copy(state.angleContext or {}),
  }
  return context
end

local function randomScalar(state, variant, bound, rng, channel, component)
  bound = tonumber(bound) or 0
  if bound == 0 then return 0, true end
  local resolver = state._options and state._options.randomScalar
  local context = randomContext(state, rng, channel, component, bound)
  if type(resolver) ~= "function" then
    addDiagnostic(state, "unsupported-random-scalar", variant, {
      kind = "random-scalar",
      message = "fragment-79 scalar random helper requires an explicit resolver",
    })
    return 0, false
  end
  local ok, value = pcall(resolver, variant, context.normalizedBound, context)
  if ok and tonumber(value) ~= nil then return tonumber(value), true end
  addDiagnostic(state, "invalid-random-scalar-resolver", variant, {
    kind = "random-scalar",
    message = "random-scalar resolver returned no signed value",
  })
  return 0, false
end

local function randomVector(spec, state, rng, channel)
  if type(spec) ~= "table" then return {0, 0, 0}, false end
  local mode = tonumber(spec.mode)
  if mode == 0 or mode == 1 then
    local out = {}
    for component = 1, 3 do
      out[component] = select(1, randomScalar(state, mode,
        spec.values and spec.values[component], rng, channel, component))
    end
    return vector(out), true
  end
  local resolver = state._options and state._options.randomVector
  if mode == 2 or mode == 3 or mode == 5 then
    if type(resolver) == "function" then
      local context = randomContext(state, rng, channel, nil, nil)
      local ok, value = pcall(resolver, mode, copy(spec.values or {}), context)
      if ok and type(value) == "table" then return vector(value), true end
      addDiagnostic(state, "invalid-random-vector-resolver", mode, {
        message = "random-vector resolver returned no vector",
        kind = "random-vector",
      })
      return {0, 0, 0}, false
    end
    addDiagnostic(state, "unsupported-random-vector-mode", mode, {
      message = "fragment-79 angle-table arithmetic requires an explicit resolver",
      kind = "random-vector",
    })
    return {0, 0, 0}, false
  end
  addDiagnostic(state, "unsupported-random-vector-mode", spec.mode, {
    message = "fragment-79 random-vector arithmetic is not disassembled",
    kind = "random-vector",
  })
  return {0, 0, 0}, false
end

local function resolveController(value, kind, state, options)
  if value == nil or value == 0 then return nil end
  if type(value) == "table" then return value end
  if type(options.resolveController) == "function" then
    local ok, resolved = pcall(options.resolveController, value, kind)
    if ok and type(resolved) == "table" then return resolved end
  end
  addDiagnostic(state, "unsupported-controller", kind .. ":" .. tostring(value), {
    address = type(value) == "number" and value or nil, kind = kind,
    message = "opaque fragment-79 controller requires an explicit resolver",
  })
  return nil
end

local function controllerVector(controller, fields)
  if not controller then return nil end
  for _, field in ipairs(fields) do
    if type(controller[field]) == "table" then return vector(controller[field]) end
  end
  return nil
end

local function applyFrameRule(state, rule, options)
  if rule == nil then return end
  local mode, value = tonumber(rule.mode), number(rule.value)
  local generation = number(state.generation)
  if mode == 1 then
    state.frame = value * generation + 1
    return
  elseif mode == 2 then
    if value == 0 then
      addDiagnostic(state, "invalid-frame-rule", "zero modulo divisor", {
        kind = "frame-rule", message = "frame mode 2 has a zero divisor",
      })
      state.frame = 0
    else
      state.frame = (generation % value) + 1
    end
    return
  elseif mode == 3 then
    local resolver = options.randomScalar
    if type(resolver) == "function" then
      local context = randomContext(state, options.rng, "frame", nil, value)
      local ok, result = pcall(resolver, 0, context.normalizedBound, context)
      if ok and tonumber(result) ~= nil then
        state.frame = tonumber(result)
        return
      end
    end
    addDiagnostic(state, "unsupported-frame-rule-mode", mode, {
      kind = "frame-rule", message = "frame mode 3 requires an external scalar resolver",
    })
    state.frame = 0
    return
  end
  -- 0 and all other modes return the authored value exactly.
  state.frame = value
end

local function initialScale(particle)
  local authored = particle.scale
  if type(authored) == "table" then
    if authored.scale ~= nil then
      local scalar = number(authored.scale, 1)
      return {scalar, scalar, scalar}, authored
    end
    return vector(authored, {1, 1, 1}), authored
  end
  local value = number(authored, 1)
  return {value, value, value}, nil
end

local function initialLifetime(particle, scale)
  local lifetime = particle.lifetime
  if lifetime == nil then return nil end
  lifetime = tonumber(lifetime)
  return lifetime and lifetime >= 0 and lifetime or nil
end

-- Fragment 79's common-particle pool owns a byte age at +0x7f.  Motion rows
-- represent that native pool by default; a synthetic caller can explicitly
-- disable the endpoint with `nativeAgeEndpoint = false`.  An injected
-- `particle.lifetime` is a separate test/runtime contract and takes
-- precedence over the native byte endpoint.
local function nativeAgeEndpoint(particle)
  if particle.nativeAgeEndpoint ~= nil then
    return particle.nativeAgeEndpoint == true
  end
  return true
end

local function nativeYTermination(particle)
  local event=type(particle.event)=="table" and particle.event or {}
  local descriptorFlags=tonumber(event.flags) or 0
  -- 0x84107240..0x84107254 maps descriptor bit 28 to object flag
  -- 0x20000, whose termination path replaces the ordinary age endpoint.
  return math.floor(descriptorFlags/0x10000000)%2==1
end

-- Create a detached state snapshot.  `particle` may be a Native.particles()
-- row or a small plain fixture with equivalent fields.
function Motion.init(particle, options)
  particle = type(particle) == "table" and particle or {}
  options = type(options) == "table" and options or {}
  local state = {
    age = number(particle.age),
    frame = number(particle.age),
    generation = number(particle.generation),
    position = vector(particle.position),
    velocity = vector(particle.velocity),
    acceleration = vector(particle.acceleration),
    rotation = vector(particle.rotation),
    angularVelocity = vector(particle.angularVelocity),
    scale = {1, 1, 1},
    alive = true,
    diagnostics = {},
    _options = copy(options),
    nativeAgeEndpoint = nativeAgeEndpoint(particle),
    -- The ROM's flag-0x20000 branch additionally checks the final Y field
    -- (+0x24).  The runtime does not yet expose that resolved native field,
    -- so keep the boundary explicit and do not invent the Y termination.
    nativeYTermination = {
      flag = 0x20000, descriptorFlag = 0x10000000, field = "+0x24",
      active = nativeYTermination(particle), status = "unresolved",
    },
    shapeId = particle.shapeId,
    born = particle.born,
    effectId = particle.effectId,
    programId = particle.programId
      or (particle.event and particle.event.programId),
    address = particle.address
      or (particle.event and particle.event.address),
    particle = copy(particle),
    angleContext = copy(particle.angleContext or particle.angles
      or particle.angle or particle.angleFields or {}),
  }
  local scale, scaleEntry = initialScale(particle)
  state.scale = scale
  state.lifetime = initialLifetime(particle, scaleEntry)
  state.authoredLifetime = scaleEntry and tonumber(scaleEntry.lifetime) or nil
  if state.lifetime == nil then
    addDiagnostic(state, "unsupported-lifetime", "lifetime is unresolved", {
      kind = "particle",
      message = "authored lifetime is unresolved; native age termination remains active",
    })
  end

  local transform = particle.transform
  if type(transform) == "table" then
    local rng = options.rng or particle.rng
    local rotationOffset = randomVector(transform.rotationOffset, state, rng,
      "rotation-offset")
    state.rotation = add(state.rotation, rotationOffset)
    local directional = randomVector(transform.directionalVelocity, state, rng,
      "directional-velocity")
    state.velocity = add(state.velocity, directional)
    state.frameRule = copy(transform.frameRule)
    state._scaleController = transform.scaleController
    state._motionController = transform.motionController
    state._motionAxes = transform.motionAxes
    applyFrameRule(state, state.frameRule, options)
  end

  -- Direct fixture fields are useful for evaluators fed by a future runtime
  -- that has already resolved a ROM transform block.
  if particle.initialRotation then state.rotation = vector(particle.initialRotation) end
  if particle.initialScale then state.scale = vector(particle.initialScale, state.scale) end
  state._rng = options.rng or particle.rng
  state._options = state._options or copy(options)
  return state
end

Motion.initialize = Motion.init

local function tick(state, delta, options)
  delta = number(delta, 1)
  options = type(options) == "table" and options or state._options or {}
  local out = copy(state)
  out._options = copy(options)
  out.diagnostics = copy(state.diagnostics or {})
  out._diagnosticKeys = copy(state._diagnosticKeys or {})
  if delta < 0 then
    addDiagnostic(out, "negative-delta", delta)
    delta = 0
  end
  if not out.alive or delta == 0 then return out end

  -- 0x841054D4 runs before 0x841029DC in the ROM.  Controllers therefore
  -- observe the post-increment age.  Native age is an unsigned byte; the
  -- runtime advances in whole 30 Hz ticks, while synthetic states retain
  -- their ordinary numeric age semantics.
  if out.nativeAgeEndpoint and out.lifetime == nil then
    out.age = (out.age + delta) % 256
  else
    out.age = out.age + delta
  end

  local transform = out.particle and out.particle.transform
  transform = type(transform) == "table" and transform or {}
  local motionController = resolveController(
    out._motionController or transform.motionController, "motion", out, options)
  local axes = resolveController(
    out._motionAxes or transform.motionAxes, "motion-axes", out, options)
  local acceleration = vector(out.acceleration)
  local authoredAcceleration = controllerVector(motionController,
    {"acceleration", "velocityDelta", "delta"})
  if authoredAcceleration then acceleration = authoredAcceleration end
  if type(axes) == "table" then
    local mask = axes.mask or axes
    for i = 1, 3 do
      if mask[i] == false or mask[i] == 0 then acceleration[i] = 0 end
    end
  end

  -- Position/velocity/rotation/scale integration order is native behavior in
  -- func_84105E9C..func_84107170, not established by the decoder alone.
  -- Require an explicit evaluator rather than baking in an Euler guess.
  if type(options.integrate) == "function" then
    local ok, integrated = pcall(options.integrate, copy(out), delta,
      acceleration, copy(options))
    if ok and type(integrated) == "table" then
      for _, field in ipairs({"position", "velocity", "acceleration", "rotation",
          "angularVelocity", "scale"}) do
        if integrated[field] ~= nil then out[field] = vector(integrated[field], out[field]) end
      end
      -- Frame selection is proven only in the initializer at
      -- 0x84106AF8..0x84106BBC.  A future update owner may explicitly return
      -- a frame, but ordinary ticking must not reinterpret the frame rule.
      if integrated.frame ~= nil and tonumber(integrated.frame) ~= nil then
        out.frame = tonumber(integrated.frame)
      end
    else
      addDiagnostic(out, "invalid-motion-integrator", "integrate", {
        kind = "motion", message = "motion integrator returned no state",
      })
    end
  elseif out.velocity[1] ~= 0 or out.velocity[2] ~= 0 or out.velocity[3] ~= 0
      or out.angularVelocity[1] ~= 0 or out.angularVelocity[2] ~= 0
      or out.angularVelocity[3] ~= 0 or motionController or axes
      or out._scaleController or transform.scaleController then
    addDiagnostic(out, "unsupported-motion-integration", "native-order", {
      kind = "motion",
      message = "native motion integration order requires disassembly evidence",
    })
  end

  -- 0x8410009C observes age == 0xff after the category update.  It is an
  -- exact byte equality, not a >= comparison.  The unresolved
  -- flag-0x20000/Y branch remains represented by nativeYTermination above.
  if out.lifetime ~= nil then
    if out.age >= out.lifetime then out.alive = false end
  elseif out.nativeAgeEndpoint and out.age == 0xff
      and not (out.nativeYTermination and out.nativeYTermination.active) then
    out.alive = false
  end
  return out
end

-- Evaluate one authored frame/tick.  The returned table is detached from the
-- input state, allowing callers to retain snapshots for golden comparisons.
function Motion.step(state, delta, options)
  if type(state) ~= "table" then return nil, "motion state is required" end
  return tick(state, delta, options)
end

Motion.evaluate = Motion.step
Motion.tick = Motion.step

function Motion.snapshot(state)
  if type(state) ~= "table" then return nil end
  local out = copy(state)
  out._rng, out._options, out._diagnosticKeys = nil, nil, nil
  out._scaleController, out._motionController, out._motionAxes = nil, nil, nil
  out.particle = nil
  return out
end

return Motion
