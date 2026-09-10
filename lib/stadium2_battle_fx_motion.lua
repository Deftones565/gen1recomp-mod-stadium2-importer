-- Pure Stadium 2 battle-FX particle motion evaluator.
--
-- The ROM reader intentionally exposes controller pointers without executing
-- them.  This module evaluates the parts for which the data contract is
-- explicit (initial vectors, authored velocities, and injected random-vector
-- records) and reports opaque controller pointers as diagnostics.  It never
-- calls the host RNG and never mutates its input tables.
local Motion = {}
local single = require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_float")
local SCALE_UNIT = single(0.001)
local SPEED_UNIT = single(0.01)

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

local function fadd(a, b) return single(a + b) end
local function fmul(a, b) return single(a * b) end

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
    angle = copy(state.angleContext or state.rotation),
    angleContext = copy(state.angleContext or state.rotation),
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
      or particle.angle or particle.angleFields),
  }
  local scale, scaleEntry = initialScale(particle)
  state.scale = scale
  state.nativeScaleUpdate = copy(scaleEntry and scaleEntry.nativeScaleUpdate)
  if state.nativeScaleUpdate then
    state.nativeScalar=single(state.nativeScaleUpdate.initial*SCALE_UNIT)
    state.scale={state.nativeScalar,state.nativeScalar,state.nativeScalar}
  end
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
    if not particle.nativeGeometry and not transform.nativeGeometry then
      state.velocity = add(state.velocity, directional)
    else
      -- func_84106C78 adds the directional sample to the initial offset.
      state.position = {fadd(state.position[1],directional[1]),
        fadd(state.position[2],directional[2]),fadd(state.position[3],directional[3])}
    end
    state.frameRule = copy(transform.frameRule)
    state._scaleController = transform.scaleController
    state._motionController = transform.motionController
    state._motionAxes = transform.motionAxes
    state._nativeMotion = copy(particle.nativeMotion or transform.nativeMotion)
    applyFrameRule(state, state.frameRule, options)
  end

  if particle.nativeMotion ~= nil and state._nativeMotion == nil then
    state._nativeMotion = copy(particle.nativeMotion)
  end
  local nativeSpeed = state._nativeMotion and state._nativeMotion.direction
    and state._nativeMotion.direction.speed
  if type(nativeSpeed) == "table" and tonumber(nativeSpeed.random) ~= nil then
    state._nativeMotionRandomBound = number(nativeSpeed.random)
  end
  -- func_84106D50: modes 1/2 initialize speed at construction. Mode 2
  -- distributes the authored increment by particle index without RNG.
  state.nativeMotionSpeed=0
  if nativeSpeed and (nativeSpeed.mode==1 or nativeSpeed.mode==2) then
    state.nativeMotionSpeed=fmul(number(nativeSpeed.initial),SPEED_UNIT)
    local extra=0
    if nativeSpeed.mode==1 then
      extra=fmul(randomScalar(state,0,number(nativeSpeed.random),options.rng,
        "native-motion-speed",nil),SPEED_UNIT)
    else
      extra=fmul(fmul(number(nativeSpeed.random),SPEED_UNIT),number(particle.particleIndex))
    end
    state.nativeMotionSpeed=fadd(state.nativeMotionSpeed,extra)
  end
  state.nativeMotionOffset = {0, 0, 0}
  state.nativeMotionBase = vector(state.position)
  local vertical=state._nativeMotion and state._nativeMotion.verticalRamp
  if vertical then
    state.nativeVerticalSpeed=0
    state.nativeVerticalPercent=100
    if number(vertical.random)~=0 then
      state.nativeVerticalPercent=(randomScalar(state,1,vertical.random,options.rng,
        "native-vertical-percent",nil)+number(vertical.base))%256
    end
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

  -- 0x84101DF8..0x84101EB0: +6 is the START age of the size ramp,
  -- not a lifetime. Each native tick approaches +2 by signed +4 * .001f.
  -- Keep the persistent unscaled scalar (+0x1c); battle placement performs
  -- the final source-model/world conversion at the renderer boundary.
  local ramp=out.nativeScaleUpdate
  if ramp and delta==1 and ramp.step~=0 and out.age>=ramp.startAge then
    local current=out.nativeScalar
    local target=single(ramp.target*SCALE_UNIT)
    local increment=single(ramp.step*SCALE_UNIT)
    if current<target then current=math.min(target,single(current+increment))
    elseif target<current then current=math.max(target,single(current-increment)) end
    out.nativeScalar=current
    out.scale={current,current,current}
  elseif ramp and delta~=1 then
    addDiagnostic(out,"unsupported-scale-step",delta,{
      kind="motion",message="native scale controller requires individual 30 Hz ticks"})
  end

  local transform = out.particle and out.particle.transform
  transform = type(transform) == "table" and transform or {}
  local motionController
  if not out._nativeMotion then
    motionController=resolveController(out._motionController or transform.motionController,
      "motion",out,options)
  end
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

  -- Common native direction controllers write a persistent motion offset
  -- consumed by the final position assembly.  The tables are supplied by
  -- the ROM catalog as options.trigTables={tableA,tableB}.
  local function trig(tables, key, angle)
    if type(tables) ~= "table" then return nil end
    local values = tables[key == "TA" and "tableA" or "tableB"]
      or tables[key] or tables[key == "TA" and 1 or 2]
    local index = math.floor(angle) % 4096 + 1
    if type(values) == "function" then
      local ok, value = pcall(values, index)
      return ok and tonumber(value) or nil
    end
    if type(values) ~= "table" or #values == 0 then return nil end
    return number(values[index])
  end
  local function nativeSpeed(spec)
    if tonumber(spec.mode) ~= nil and (tonumber(spec.mode)<0 or tonumber(spec.mode)>2) then
      addDiagnostic(out, "unsupported-native-motion-speed-mode", spec.mode, {
        kind = "motion", message = "native speed mode is not disassembled",
      })
      return 0
    end
    local start = number(spec.startAge)
    if out.age < start then return out.nativeMotionSpeed or 0 end
    local target = fmul(number(spec.target), SPEED_UNIT)
    local value
    if out.age == start and (spec.mode==nil or spec.mode==0) then
      value = fmul(number(spec.initial), SPEED_UNIT)
    elseif out.age>start then
      local previous = out.nativeMotionSpeed or 0
      local step = fmul(number(spec.step), SPEED_UNIT)
      if previous < target then value = fadd(previous, step)
      elseif target < previous then value = fadd(previous, -step)
      else value = previous end
      if previous < target and value > target then value = target end
      if target < previous and value < target then value = target end
    else
      value=out.nativeMotionSpeed or 0
    end
    if out.age == start and (spec.mode==nil or spec.mode==0)
        and out._nativeMotionRandomBound ~= nil then
      if not out._nativeMotionRandomResolved then
        local resolved = randomScalar(out, 0, out._nativeMotionRandomBound, out._rng,
          "native-motion-speed", nil)
        out._nativeMotionRandom = fmul(resolved, SPEED_UNIT)
        out._nativeMotionRandomResolved = true
      end
      value = fadd(value, out._nativeMotionRandom)
    end
    return value
  end
  local function applyNativeMotion()
    local native = out._nativeMotion
    if type(native) ~= "table" then return end
    local direction = native.direction
    local function applyVertical(offset)
      local ramp=native.verticalRamp
      if ramp and out.age>=number(ramp.startAge) then
        local step=number(ramp.step)
        local value=out.nativeVerticalSpeed or 0
        if out.age==ramp.startAge and step==0 then value=number(ramp.target) end
        if step~=0 then
          value=(value+step+32768)%65536-32768
          if step>0 then value=math.min(value,number(ramp.target))
          else value=math.max(value,number(ramp.target)) end
        end
        out.nativeVerticalSpeed=value
        local percent=out.nativeVerticalPercent or 100
        local delta=percent==100 and fmul(SPEED_UNIT,value)
          or fmul(fmul(single(percent/100),SPEED_UNIT),value)
        offset[2]=fadd(offset[2],delta)
      end
      local subtract=native.verticalSubtract
      if subtract and out.age>=number(subtract.startAge) then
        offset[2]=fadd(offset[2],-fmul(number(subtract.value),SPEED_UNIT))
      end
    end
    local spec = type(direction) == "table" and direction.speed
    if type(direction) == "table" and type(spec) == "table" then
      local mode = tonumber(direction.mode)
      local speed = nativeSpeed(spec)
      out.nativeMotionSpeed = speed
      local motion
      if mode == 4 or mode == 5 then
        motion = {0, fmul(speed, mode == 4 and 1 or -1), 0}
      elseif mode == 7 or mode == 8 then
        local angles = direction.angles or native.angles or out.rotation or {0, 0, 0}
        local x, y = number(angles[1] or angles.x) / 16,
          number(angles[2] or angles.y) / 16
        local taX, taY, tbX, tbY = trig(options.trigTables, "TA", x),
          trig(options.trigTables, "TA", y), trig(options.trigTables, "TB", x),
          trig(options.trigTables, "TB", y)
        if not (taX and taY and tbX and tbY) then
          addDiagnostic(out, "unsupported-native-motion-trig", mode, {
            kind = "motion", message = "native direction mode requires TA/TB tables",
          })
          motion = {0, 0, 0}
        else
          local product = fmul(speed, tbX)
          motion = {fmul(taY, product), fmul(taX, -speed), fmul(tbY, product)}
        end
      else
        addDiagnostic(out, "unsupported-native-motion-mode", mode, {
          kind = "motion", message = "native direction mode is not disassembled",
        })
        motion = {0, 0, 0}
      end
      local prior = out.nativeMotionOffset or {0, 0, 0}
      local next = mode == 8 and motion or {
        fadd(prior[1], motion[1]), fadd(prior[2], motion[2]),
        fadd(prior[3], motion[3]),
      }
      out.nativeMotionOffset = next
      applyVertical(next)
      local base = out.nativeMotionBase or {0, 0, 0}
      out.position = {fadd(base[1], next[1]), fadd(base[2], next[2]),
        fadd(base[3], next[3])}
    end
    if type(spec) ~= "table" then
      local base=out.nativeMotionBase or out.position
      applyVertical(out.nativeMotionOffset)
      out.position[2]=fadd(base[2],out.nativeMotionOffset[2])
    end
    if native.curve ~= nil or (type(direction) == "table" and direction.curve ~= nil) then
      addDiagnostic(out, "unsupported-native-motion-curve", native.curve, {
        kind = "motion", message = "native curve controller requires an explicit resolver",
      })
    end
    if native.verticalController ~= nil and not native.verticalRamp then
      addDiagnostic(out, "unsupported-native-motion-vertical-controller",
        native.verticalController, {kind = "motion", message =
          "native vertical controller requires an explicit resolver"})
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

  applyNativeMotion()

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
