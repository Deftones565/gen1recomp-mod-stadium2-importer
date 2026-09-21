-- Fragment-79 lifecycle metadata and persistent callback state.
-- Families 23/26/27 use the shared ROM ribbon kernel. Other direct callees
-- remain explicit resolver contracts with unsupported-phase diagnostics.
local Lifecycle = {}
local Ribbon = require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_ribbon")
local WaveGrid = require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_wave_grid")
local Radial = require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_radial")
local Swift = require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_swift")
local Needle = require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_needle")
local Beam = require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_beam")
local Random = require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_random")

local INIT_BASE = 0x84183700
local UPDATE_BASE = 0x84183778
local DRAW_BASE = 0x841837F0

local function row(id, init, update, draw, group, counter, terminal,
    drawHelper, phaseGate)
  return {
    id = id,
    init = init,
    update = update,
    draw = draw,
    empty = init == 0 and update == 0 and draw == 0,
    group = group,
    counterAddress = counter,
    counterWidth = counter and 2 or nil,
    counterSigned = counter and true or nil,
    terminationThreshold = terminal,
    phaseGate = phaseGate,
    drawGate = id == 12 and {kind = "minimum", first = 2} or nil,
    drawHelper = drawHelper,
  }
end

local DATA = {
  [0] = row(0, 0x84159198, 0x841591C8, 0x841591E8,
    "shared-wrapper", nil, nil, 0x84168000),
  [1] = row(1, 0, 0, 0, "empty"),
  [2] = row(2, 0x841572A0, 0x841572D4, 0x84157344,
    "timer-model", 0x841A4D4C, 1801, 0x84162DE8,
    {kind = "window-modulo", first = 1, last = 1769, modulo = 3}),
  [3] = row(3, 0x84157AB0, 0x84157ADC, 0x84157C58,
    "stochastic-controller", 0x841A4D54, nil, 0x84166A64),
  [4] = row(4, 0x84156E58, 0x84156E8C, 0x84156EFC,
    "timer-model", 0x841A4D4A, 181, 0x8415DBBC,
    {kind = "window-modulo", first = 1, last = 119, modulo = 7}),
  [5] = row(5, 0x84158BA8, 0x84158BD8, 0x84158BF8,
    "shared-wrapper", nil, nil, 0x84168000),
  [6] = row(6, 0x84157558, 0x8415758C, 0x841575FC,
    "timer-model", 0x841A4D4E, 181, 0x8415DBBC,
    {kind = "window-modulo", first = 1, last = 119, modulo = 7}),
  [7] = row(7, 0x84156BD4, 0x84156C40, 0x84156C60,
    "float-setup", nil, nil, 0x8415ADE0),
  [8] = row(8, 0x84159C2C, 0x84159C6C, 0x84159CC8,
    "cadence-controller", 0x841A4D50, nil, 0x84168000,
    {kind = "modulo", modulo = 10}),
  [9] = row(9, 0x84157EB0, 0x84157EE0, 0x84157F00,
    "parameterized-model", nil, nil, 0x8415FD8C),
  [10] = row(10, 0x84157F54, 0x84157F84, 0x84157FA4,
    "parameterized-model", nil, nil, 0x84161018),
  [11] = row(11, 0x84157FF8, 0x84158028, 0x84158048,
    "parameterized-model", nil, nil, 0x841621A4),
  [12] = row(12, 0x8415809C, 0x841580C8, 0x84158308,
    "complex-controller", 0x841A4D00, 50, 0x84164280,
    {kind = "window", first = 4, last = 49}),
  [13] = row(13, 0x84158E24, 0x84158E58, 0x84158EAC,
    "cadence-controller", 0x841A4D48, nil, 0x84169618,
    {kind = "modulo", modulo = 10}),
  [14] = row(14, 0, 0, 0, "empty"),
  [15] = row(15, 0x84157CB0, 0x84157CDC, 0x84157E58,
    "stochastic-controller", 0x841A4D56, nil, 0x84166A64),
  [16] = row(16, 0x84158370, 0x8415839C, 0x84158520,
    "complex-controller", 0x841A4D02, nil, 0x841650A8),
  [17] = row(17, 0x84158588, 0x841586C8, 0x84158714,
    "complex-controller", 0x841A4D04, 50, 0x84165CC0),
  [18] = row(18, 0x84159708, 0x84159738, 0x84159758,
    "shared-wrapper", nil, nil, 0x84168000),
  [19] = row(19, 0x841594E0, 0x84159510, 0x84159530,
    "shared-wrapper", nil, nil, 0x84168000),
  [20] = row(20, 0x84158840, 0x84158874, 0x841588C0,
    "timer-model", 0x841A4D06, 181, 0x8415DBBC),
  [21] = row(21, 0x841579B8, 0x841579EC, 0x84157A5C,
    "timer-model", 0x841A4D52, 181, 0x8415DBBC,
    {kind = "window-modulo", first = 1, last = 119, modulo = 7}),
  [22] = row(22, 0, 0, 0, "empty"),
  [23] = row(23, 0x84156F50, 0x84156FC8, 0x84156FE8,
    "model-parameter", nil, nil, 0x8415C2E0),
  [24] = row(24, 0, 0, 0, "empty"),
  [25] = row(25, 0, 0, 0, "empty"),
  [26] = row(26, 0x84157650, 0x841576CC, 0x841576EC,
    "model-parameter", nil, nil, 0x8415C2E0),
  [27] = row(27, 0x84157740, 0x841577B8, 0x841577D8,
    "model-parameter", nil, nil, 0x8415C2E0),
  [28] = row(28, 0, 0, 0, "empty"),
  [29] = row(29, 0x8415703C, 0x841570B4, 0x841570D4,
    "model-parameter", nil, nil, 0x8415C2E0),
}

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

-- Keep the backing records private so metadata cannot be mutated through the
-- public object.  __pairs is available in the Lua used by the project.
local function readonly(value, cache)
  if type(value) ~= "table" then return value end
  cache = cache or {}
  if cache[value] then return cache[value] end
  local proxy = {}
  cache[value] = proxy
  setmetatable(proxy, {
    __index = function(_, key) return readonly(value[key], cache) end,
    __newindex = function() error("lifecycle metadata is immutable", 2) end,
    __pairs = function()
      local key
      return function()
        local nextKey, child = next(value, key)
        key = nextKey
        if nextKey == nil then return nil end
        return nextKey, readonly(child, cache)
      end
    end,
    __len = function()
      local count = 0
      for _ in pairs(value) do count = count + 1 end
      return count
    end,
  })
  return proxy
end

local PUBLIC_DATA = readonly(DATA)
Lifecycle.families = PUBLIC_DATA
Lifecycle.metadata = function() return PUBLIC_DATA end
Lifecycle.INIT_TABLE = INIT_BASE
Lifecycle.UPDATE_TABLE = UPDATE_BASE
Lifecycle.DRAW_TABLE = DRAW_BASE
Lifecycle.COUNT = 30

local function integer(value)
  value = tonumber(value)
  if not value or value ~= math.floor(value) then return nil end
  return math.floor(value)
end

local function diagnostic(code, effectId, address, message, severity)
  return {
    code = code,
    severity = severity or "warning",
    effectId = effectId,
    programId = nil,
    address = address,
    kind = "lifecycle",
    message = message,
  }
end

local Manager = {}
Manager.__index = Manager

function Manager:_emit(item, instance)
  item = item or {}
  local context = instance and instance.context or nil
  local effectId = item.effectId
  if effectId == nil and context then effectId = context.effectId end
  local out = diagnostic(item.code or "unsupported-lifecycle", effectId,
    item.address, item.message or item.detail or "unsupported lifecycle phase",
    item.severity)
  if item.programId ~= nil then
    out.programId = item.programId
  elseif context and context.programId ~= nil then
    out.programId = context.programId
  end
  if item.kind ~= nil then out.kind = item.kind end
  if instance then
    out.instanceId = instance.id
    out.context = copy(context)
  elseif item.context ~= nil then
    out.context = copy(item.context)
  end
  local key = table.concat({tostring(out.code), tostring(out.effectId),
    tostring(out.address), tostring(out.message)}, "|")
  if not self._diagnosticKeys[key] then
    self._diagnosticKeys[key] = true
    self.diagnostics[#self.diagnostics + 1] = out
    if type(self.warn) == "function" then pcall(self.warn, copy(out)) end
  end
  return out
end

function Manager:_missing(instance, phase, address)
  return self:_emit(diagnostic("unsupported-lifecycle-callback", nil, address,
    "lifecycle phase requires an injected callback resolver"), instance)
end

function Manager:_phase(instance, phase, address)
  local signal=self.finishedEffects[instance.context.effectId] and 1 or self.nativeSignal
  if type(self.callback) ~= "function" then
    if instance.familyId==17 then
      if phase=="draw" then return 0 end
      if not instance.needle then
        local inputs=instance.context.lifecycleBeam
        if self.resolveBeam then
          local ok,value=pcall(self.resolveBeam,copy(instance.context),instance)
          if ok then inputs=value else
            self:_emit(diagnostic("lifecycle-needle-input-error",nil,address,tostring(value),"error"),instance)
            return nil
          end
        end
        local function valid(v)
          if type(v)~="table" then return false end
          for i=1,3 do if type(v[i])~="number" or v[i]~=v[i] or math.abs(v[i])==math.huge then return false end end
          return true
        end
        if type(inputs)~="table" or not valid(inputs.swiftOrigin or inputs.origin) or not valid(inputs.direction)
            or (inputs.swiftFrameOrigin and not valid(inputs.swiftFrameOrigin)) then
          self:_emit(diagnostic("unresolved-needle-endpoints",nil,address,"needle projectiles require live source and target anchors"),instance)
          return nil
        end
        if not (self.assets and self.assets.needle) then
          self:_emit(diagnostic("unresolved-needle-model",nil,0x84188A70,"needle ROM model is unavailable"),instance)
          return nil
        end
        if inputs.approximate or not inputs.sourceSpecies then
          self:_emit(diagnostic("approximate-needle-inputs",nil,address,"needle uses fallback anchors or species where imported model data is unavailable"),instance)
        end
        instance.needle=Needle.new(inputs.swiftOrigin or inputs.origin,inputs.direction,
          inputs.sourceSpecies,self.random,inputs.swiftFrameOrigin)
      end
      if phase=="update" then return Needle.step(instance.needle) end
      return 0
    end
    if Radial.families[instance.familyId] then
      if phase=="draw" then return 0 end
      local inputs=instance.context.lifecycleBeam
      if self.resolveBeam then
        local ok,value=pcall(self.resolveBeam,copy(instance.context),instance)
        if ok then inputs=value else
          self:_emit(diagnostic("lifecycle-radial-input-error",nil,address,tostring(value),"error"),instance)
          return nil
        end
      end
      local function valid(v)
        if type(v)~="table" then return false end
        for i=1,3 do
          if type(v[i])~="number" or v[i]~=v[i] or math.abs(v[i])==math.huge then return false end
        end
        return true
      end
      if type(inputs)~="table" or not valid(inputs.swiftOrigin or inputs.origin) or not valid(inputs.direction)
          or (inputs.swiftFrameOrigin and not valid(inputs.swiftFrameOrigin)) then
        self:_emit(diagnostic("unresolved-radial-endpoints",nil,address,"radial ribbons require live source and target anchors"),instance)
        return nil
      end
      local scale=instance.context.lifecycleScale or inputs.modelScale or 1
      if type(scale)~="number" or scale~=scale or math.abs(scale)==math.huge then
        self:_emit(diagnostic("invalid-radial-scale",nil,address,"radial ribbons require a finite model scale"),instance)
        return nil
      end
      if inputs.approximate or not (instance.context.lifecycleScale or inputs.modelScale) then
        self:_emit(diagnostic("approximate-radial-inputs",nil,address,"radial ribbons use fallback anchors/scale where imported ROM data is unavailable"),instance)
      end
      local fresh=not instance.radial
      if fresh then instance.radial=Radial.new(instance.familyId,inputs.swiftFrameOrigin) end
      local origin=inputs.swiftOrigin or inputs.origin
      if fresh or (phase=="update" and instance.counter<120 and instance.counter%7==0) then
        Radial.spawn(instance.radial,origin,inputs.direction,scale,self.random)
      end
      if phase=="update" then return Radial.step(instance.radial,origin) end
      return 0
    end
    if instance.familyId==2 then
      if phase=="draw" then return 0 end
      local inputs=instance.context.lifecycleBeam
      if self.resolveBeam then
        local ok,value=pcall(self.resolveBeam,copy(instance.context),instance)
        if ok then inputs=value else
          self:_emit(diagnostic("lifecycle-swift-input-error",nil,address,
            tostring(value),"error"),instance)
          return nil
        end
      end
      local function valid(v)
        if type(v)~="table" then return false end
        for i=1,3 do
          if type(v[i])~="number" or v[i]~=v[i] or math.abs(v[i])==math.huge then return false end
        end
        return true
      end
      if type(inputs)~="table" or not valid(inputs.swiftOrigin or inputs.origin)
          or not valid(inputs.swiftDirection or inputs.direction)
          or (inputs.swiftFrameOrigin and not valid(inputs.swiftFrameOrigin)) then
        self:_emit(diagnostic("unresolved-swift-endpoints",nil,address,
          "Swift requires live source and target anchors"),instance)
        return nil
      end
      local scale=instance.context.lifecycleScale or inputs.modelScale or 1
      if type(scale)~="number" or scale~=scale or math.abs(scale)==math.huge then
        self:_emit(diagnostic("invalid-swift-scale",nil,0x84109544,
          "Swift requires a finite native model scale"),instance)
        return nil
      end
      if inputs.approximate then
        self:_emit(diagnostic("approximate-swift-endpoints",nil,0x841098C0,
          "Swift uses host fallback anchors where imported ROM attachments/profile are unavailable"),instance)
      end
      if not (instance.context.lifecycleScale or inputs.modelScale) then
        self:_emit(diagnostic("approximate-swift-scale",nil,0x84109544,
          "native secondary-owner model scale unavailable; using scale 1"),instance)
      end
      local fresh=not instance.swift
      if fresh then instance.swift=Swift.new(inputs.swiftFrameOrigin) end
      if fresh or (phase=="update" and instance.counter<1770 and instance.counter%3==0) then
        Swift.spawn(instance.swift,inputs.swiftOrigin or inputs.origin,inputs.swiftDirection or inputs.direction,scale,self.random)
      end
      if phase=="update" then return Swift.step(instance.swift,signal) end
      return 0
    end
    if Beam.families[instance.familyId] and phase ~= "draw" then
      local inputs=instance.context.lifecycleBeam
      if self.resolveBeam then
        local ok,value=pcall(self.resolveBeam,copy(instance.context),instance)
        if ok then inputs=value else
          self:_emit(diagnostic("lifecycle-beam-input-error",nil,address,
            tostring(value),"error"),instance)
          return nil
        end
      end
      local function valid(v)
        if type(v)~="table" then return false end
        for i=1,3 do
          if type(v[i])~="number" or v[i]~=v[i] or math.abs(v[i])==math.huge then return false end
        end
        return true
      end
      if type(inputs)~="table" or not valid(inputs.endpointA)
          or not valid(inputs.endpointB) or (not instance.beam
          and (not valid(inputs.origin) or not valid(inputs.direction))) then
        self:_emit(diagnostic("unresolved-beam-endpoints",nil,address,
          "beam requires native setup origin/direction and live model endpoints"),instance)
        return nil
      end
      if not instance.beam then
        instance.beam=Beam.forFamily(instance.familyId,inputs.origin,inputs.direction)
      end
      instance.beam.cameraEye=copy(inputs.cameraEye)
      if inputs.approximate then
        self:_emit(diagnostic("approximate-beam-endpoints",nil,0x84109780,
          (inputs.attachmentCount or 0)>0
            and "beam uses posed ROM attachments; native battle profile unavailable (reimport models)"
            or "beam uses host model centers; imported ROM attachments are unavailable"),instance)
      end
      if phase=="update" then
        return Beam.step(instance.beam,inputs.endpointA,inputs.endpointB,signal)
      end
      return 0
    end
    if instance.beam and phase=="draw" then
      if not instance.beam.cameraEye then
        self:_emit(diagnostic("unresolved-beam-camera",nil,0x84163380,
          "beam glow requires a camera eye in native endpoint coordinates"),instance)
      end
      return 0
    end
    if WaveGrid.families[instance.familyId] then
      if phase == "init" then
        instance.waveGrid = WaveGrid.new(instance.familyId, self.random)
        return 0
      elseif phase == "update" then
        return WaveGrid.step(instance.waveGrid, signal)
      elseif phase == "draw" then
        return 0
      end
    end
    if Ribbon.families[instance.familyId] then
      if phase == "init" then
        instance.ribbon = Ribbon.new(instance.familyId, instance.context)
      elseif phase == "update" then
        local anchor = instance.context.lifecycleAnchor
        if self.resolveAnchor then
          local ok, value = pcall(self.resolveAnchor, instance.context, instance)
          if ok then anchor = value else
            self:_emit(diagnostic("lifecycle-anchor-error", nil, address,
              tostring(value), "error"), instance)
          end
        end
        return Ribbon.step(instance.ribbon, anchor)
      end
      return 0
    end
    self:_missing(instance, phase, address)
    return nil
  end
  local phaseContext = copy(instance.context)
  local ok, result, item = pcall(self.callback, phase, address, instance,
    phaseContext)
  if not ok then
    self:_emit(diagnostic("lifecycle-callback-error", nil, address,
      tostring(result), "error"), instance)
    return nil
  end
  if type(item) == "table" then
    item.effectId = item.effectId or instance.context.effectId
    item.address = item.address or address
    self:_emit(item, instance)
  elseif type(result) == "table" and result.code then
    result.effectId = result.effectId or instance.context.effectId
    result.address = result.address or address
    self:_emit(result, instance)
  end
  return result
end

local function gateEligible(gate, counter)
  if not gate then return true end
  if gate.first and counter < gate.first then return false end
  if gate.last and counter > gate.last then return false end
  if gate.modulo and counter % gate.modulo ~= 0 then return false end
  return true
end

function Lifecycle.new(options)
  options = type(options) == "table" and options or {}
  local clockHz = tonumber(options.clockHz) or 30
  if clockHz <= 0 then error("lifecycle clockHz must be positive", 2) end
  return setmetatable({
    clockHz = clockHz,
    callback = options.callback or options.phaseResolver,
    resolveAnchor = options.resolveAnchor,
    resolveBeam = options.resolveBeam,
    assets = options.assets,
    nativeSignal = options.nativeSignal or 0,
    finishedEffects = {},
    random = options.random or Random.new(options.seed or 0),
    warn = options.warn,
    frame = 0,
    accumulator = 0,
    nextId = 1,
    instances = {},
    order = {},
    diagnostics = {},
    _diagnosticKeys = {},
    released = false,
  }, Manager)
end

function Manager:spawn(familyId, context)
  if self.released then return nil, "lifecycle manager has been released" end
  if type(familyId) == "table" then
    context = familyId
    familyId = context.familyId or context.lifecycleId
  end
  familyId = integer(familyId)
  local family = familyId and DATA[familyId]
  if not family then return nil, "lifecycle family is out of range" end
  if family.empty then
    local item = self:_emit(diagnostic("unsupported-empty-lifecycle", nil,
      nil, "empty lifecycle table row is a safe no-op"))
    return nil, item
  end
  local instance = {
    id = self.nextId,
    familyId = familyId,
    family = family,
    context = copy(context or {}),
    counter = 0,
    frame = 0,
    active = true,
    born = self.frame,
    lastPhase = nil,
    lastResult = nil,
    gateEligible = true,
  }
  self.nextId = self.nextId + 1
  self.instances[instance.id] = instance
  self.order[#self.order + 1] = instance.id
  instance.lastPhase = "init"
  instance.lastResult = self:_phase(instance, "init", family.init)
  return instance.id
end

function Manager:_update(instance)
  local family = instance.family
  instance.frame = instance.frame + 1
  if family.counterAddress then instance.counter = (instance.counter + 1 + 32768)%65536-32768 end
  local count = instance.counter
  instance.gateEligible = gateEligible(family.phaseGate, count)

  -- These are the only direct -1 callback returns proven in the row audit.
  -- The native code branches before its unresolved helper call on this tick.
  if family.terminationThreshold and count >= family.terminationThreshold then
    instance.active = false
    instance.lastPhase = "update"
    instance.lastResult = -1
    return
  end

  -- Family 12 has an exact update window (frames 4..49).  The first three
  -- increments return through native code without the unresolved work.
  if family.id == 12 and not gateEligible(family.phaseGate, count) then
    instance.lastPhase = "update"
    instance.lastResult = nil
    return
  end
  instance.lastPhase = "update"
  instance.lastResult = self:_phase(instance, "update", family.update)
  if instance.lastResult == -1 then instance.active = false end
end

function Manager:step(count)
  if self.released then return nil, "lifecycle manager has been released" end
  count = integer(count)
  if not count or count < 0 then
    error("lifecycle step count must be a non-negative integer", 2)
  end
  for _ = 1, count do
    self.frame = self.frame + 1
    local ids = {}
    for _, id in ipairs(self.order) do ids[#ids + 1] = id end
    for _, id in ipairs(ids) do
      local instance = self.instances[id]
      if instance and instance.active then self:_update(instance) end
    end
  end
  return self.frame
end

-- Presentation controller's 841901B8 value. Only 1 starts the native fade;
-- callers must not infer it from a move's name or an invented timeout.
function Manager:setNativeSignal(value)
  value = integer(value)
  if value == nil then error("lifecycle native signal must be an integer", 2) end
  self.nativeSignal = value
end

-- Host animation completion applies to one move, including lifecycle objects
-- whose scheduled init has not run yet. It must not leak to subsequent moves.
function Manager:finishEffect(effectId)
  effectId=integer(effectId)
  if not effectId then return false end
  self.finishedEffects[effectId]=true
  return true
end

function Manager:update(dt)
  dt = tonumber(dt)
  if not dt or dt < 0 then error("lifecycle dt must be non-negative", 2) end
  self.accumulator = self.accumulator + dt * self.clockHz
  local ticks = math.floor(self.accumulator)
  self.accumulator = self.accumulator - ticks
  self:step(ticks)
  return ticks
end

function Manager:_draw(invokeResolver)
  local packets = {}
  for _, id in ipairs(self.order) do
    local instance = self.instances[id]
    if instance and instance.active then
      local family = instance.family
      local drawAllowed = gateEligible(family.drawGate, instance.counter)
      if drawAllowed and (not instance.ribbon or instance.ribbon.count >= 2) then
        if invokeResolver then
          instance.lastPhase = "draw"
          self:_phase(instance, "draw", family.draw)
        end
        packets[#packets + 1] = {
          command = 0xDA380003,
          pointer = 0x841A4D08,
          drawHelper = family.drawHelper,
          requiresDrawHelper = true,
          familyId = family.id,
          instanceId = instance.id,
          context = copy(instance.context),
          counter = instance.counter,
          frame = instance.frame,
          geometry = instance.needle and Needle.geometry(instance.needle,self.assets.needle) or instance.radial and Radial.geometry(instance.radial) or instance.swift and Swift.geometry(instance.swift) or instance.ribbon and Ribbon.geometry(instance.ribbon)
            or instance.waveGrid and WaveGrid.geometry(instance.waveGrid)
            or instance.beam and Beam.geometry(instance.beam) or nil,
        }
      end
    end
  end
  return packets
end

function Manager:draw()
  return self:_draw(true)
end

function Manager:snapshot()
  local instances = {}
  for _, id in ipairs(self.order) do
    local instance = self.instances[id]
    if instance then
      instances[#instances + 1] = {
        id = instance.id, familyId = instance.familyId,
        context = copy(instance.context), counter = instance.counter,
        frame = instance.frame, born = instance.born,
        active = instance.active, gateEligible = instance.gateEligible,
        lastPhase = instance.lastPhase, lastResult = instance.lastResult,
        nativeState = instance.waveGrid and WaveGrid.snapshot(instance.waveGrid)
          or instance.beam and Beam.snapshot(instance.beam) or instance.swift and Swift.snapshot(instance.swift) or instance.radial and Radial.snapshot(instance.radial) or instance.needle and Needle.snapshot(instance.needle) or nil,
      }
    end
  end
  return {frame = self.frame, instances = instances,
    packets = copy(self:_draw(false)), diagnostics = copy(self.diagnostics)}
end

function Manager:release(id)
  if id == nil then
    self.finishedEffects={}
    for key, instance in pairs(self.instances) do
      instance.active = false
      self.instances[key] = nil
    end
    return true
  end
  id = integer(id)
  if id and self.instances[id] then
    self.instances[id].active = false
    self.instances[id] = nil
    return true
  end
  return false
end

function Manager:diagnosticSnapshot()
  return copy(self.diagnostics)
end

function Manager:close()
  self:release()
  self.released = true
end

Lifecycle.Manager = Manager
Lifecycle.newManager = Lifecycle.new

return Lifecycle
