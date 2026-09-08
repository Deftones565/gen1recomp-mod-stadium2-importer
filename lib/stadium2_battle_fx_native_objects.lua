-- Persistent scheduler kernel for fragment-79 native-object emitters.
--
-- The ROM command pointer is deliberately kept separate from the resolved
-- object.  The retail resolver and linked update/draw code are not available
-- in this layer; callers must inject them and unsupported work is reported.

local NativeObjects = {}

NativeObjects.CAPACITY = 64
NativeObjects.MODES = {[2] = true, [4] = true, [5] = true, [6] = true, [8] = true}
-- 0x80003240 dispatches 0x81xxxxxx..0x8fffffff through 0x800024A0.
-- Fragment 79 is registered at this logical base; its low-20-bit mapping is
-- safe to materialise only while it remains inside the extracted overlay.
NativeObjects.RESOLVER_ADDRESS = 0x80003240
NativeObjects.MAPPER_ADDRESS = 0x800024A0
NativeObjects.FRAGMENT_BASE = 0x84100000
NativeObjects.FRAGMENT_END = 0x84100000 + 0xA9BF0

local function clone(value, seen)
  if type(value) ~= "table" then return value end
  seen = seen or {}
  if seen[value] then return seen[value] end
  local out = {}
  seen[value] = out
  for key, item in pairs(value) do out[clone(key, seen)] = clone(item, seen) end
  return out
end

local function integer(value, name)
  if type(value) ~= "number" or value ~= math.floor(value) then
    error(("%s must be an integer"):format(name))
  end
  return value
end

local function diagnostic(code, message, commandPointer, mode, index, event)
  event = event or {}
  return {
    code=code,
    severity="warning",
    effectId=event.effectId,
    programId=event.programId,
    address=event.address or commandPointer,
    kind="native-object",
    commandPointer=commandPointer,
    mode=mode,
    schedulerIndex=index,
    message=message,
  }
end

local function normaliseResolution(resolved)
  if type(resolved) ~= "table" then return nil end
  if resolved.ok == false or resolved.resolved == false then return nil end
  local object = resolved.object or resolved.resolvedObject or resolved
  local delay = resolved.delay
  if delay == nil then delay = resolved.countdown end
  if delay == nil and object ~= resolved then
    delay = object.delay or object.countdown
  end
  if type(delay) ~= "number" or delay ~= math.floor(delay)
      or delay < 0 or delay > 0xFF then
    return nil
  end
  return object, delay, resolved
end

local function builtinResolution(commandPointer, event)
  if type(commandPointer) ~= "number"
      or commandPointer ~= math.floor(commandPointer)
      or commandPointer < NativeObjects.FRAGMENT_BASE
      or commandPointer >= NativeObjects.FRAGMENT_END then
    return nil, "native-object address is outside the fragment-79 image"
  end
  local offset = commandPointer - NativeObjects.FRAGMENT_BASE
  local resolvedPointer = NativeObjects.FRAGMENT_BASE + offset
  if resolvedPointer < NativeObjects.FRAGMENT_BASE
      or resolvedPointer >= NativeObjects.FRAGMENT_END then
    return nil, ("fragment-79 low-20-bit mapping is out of range: 0x%08X")
      :format(resolvedPointer)
  end
  local raw = event.encodedObjectRaw
  if type(raw) ~= "string" or #raw < 16 then
    return nil, "decoded native-object evidence must contain at least 16 raw bytes"
  end
  local expectedOffset = (event.mode == 5 or event.mode == 6) and 1 or 3
  local delayOffset = event.delayOffset
  if delayOffset == nil then delayOffset = expectedOffset end
  if delayOffset ~= expectedOffset then
    return nil, ("decoded delay offset %s disagrees with mode %s")
      :format(tostring(delayOffset), tostring(event.mode))
  end
  local encodedDelay = event.encodedDelay
  if type(encodedDelay) ~= "number" or encodedDelay ~= math.floor(encodedDelay)
      or encodedDelay < 0 or encodedDelay > 0xFF then
    return nil, "decoded native-object delay is not an unsigned byte"
  end
  local rawDelay = string.byte(raw, delayOffset + 1)
  if rawDelay == nil then
    return nil, "decoded native-object raw bytes do not contain the delay byte"
  end
  if rawDelay ~= encodedDelay then
    return nil, ("decoded delay 0x%02X disagrees with raw byte 0x%02X at +%d")
      :format(encodedDelay, rawDelay, delayOffset)
  end
  local evidence = {
    status = "fragment79-main-resolver",
    resolver = NativeObjects.RESOLVER_ADDRESS,
    mapper = NativeObjects.MAPPER_ADDRESS,
    commandPointer = commandPointer,
    resolvedPointer = resolvedPointer,
    fragmentBase = NativeObjects.FRAGMENT_BASE,
    low20Offset = offset,
    delayOffset = delayOffset,
    encodedDelay = encodedDelay,
    encodedObjectRaw = raw,
  }
  return {
    object = {
      pointer = resolvedPointer,
      resolvedPointer = resolvedPointer,
      commandPointer = commandPointer,
      encodedObjectRaw = raw,
      delay = encodedDelay,
      resolver = evidence,
    },
    delay = encodedDelay,
    -- Keep the evidence at the response root for callers that treat the
    -- resolver return as metadata, while retaining the nested form used by
    -- other injected resolvers.
    status = evidence.status,
    resolver = evidence.resolver,
    mapper = evidence.mapper,
    resolvedPointer = evidence.resolvedPointer,
    commandPointer = evidence.commandPointer,
    resolution = evidence,
  }
end

local function callbackResult(value)
  if type(value) == "number" then return value, nil, nil, nil end
  if type(value) ~= "table" then return nil, nil, nil, nil end
  return value.result or value.returnValue or value.lifetime,
    value.visualObjects or value.visuals or value.objects,
    value.rawFields,
    value.diagnostics
end

local function retain(list, value)
  if type(value) == "table" and #value > 0 then
    for _, item in ipairs(value) do list[#list + 1] = clone(item) end
  else
    list[#list + 1] = clone(value)
  end
end

function NativeObjects.new(options)
  options = options or {}
  local self = {
    capacity=options.capacity or NativeObjects.CAPACITY,
    resolve=options.resolve,
    callbacks=options.callbacks or {},
    drawCallbacks=options.drawCallbacks or {},
    slots={},
    diagnostics={},
    tickCount=0,
  }
  integer(self.capacity, "capacity")
  if self.capacity < 1 then error("capacity must be positive") end
  for index = 0, self.capacity - 1 do
    self.slots[index] = {index=index, active=false, generation=0}
  end
  return setmetatable(self, {__index=NativeObjects})
end

function NativeObjects:_diagnose(item)
  self.diagnostics[#self.diagnostics + 1] = item
  return item
end

function NativeObjects:_unsupported(slot, code, message)
  local item = diagnostic(code, message, slot.commandPointer, slot.mode,
    slot.index, slot.event)
  local key = table.concat({item.code, tostring(item.address), item.message}, "\31")
  slot.diagnosticKeys = slot.diagnosticKeys or {}
  if slot.diagnosticKeys[key] then return item end
  slot.diagnosticKeys[key] = true
  slot.diagnostics[#slot.diagnostics + 1] = item
  self:_diagnose(item)
  return item
end

function NativeObjects:enqueue(commandPointer, event)
  if type(commandPointer) == "table" and event == nil then
    event = commandPointer
    commandPointer = event.commandPointer
  end
  if type(commandPointer) ~= "number" then
    error("commandPointer must be a number")
  end
  event = clone(event or {})
  local mode = event.mode
  if not NativeObjects.MODES[mode] then
    return nil, self:_diagnose(diagnostic("unsupported-native-mode",
      ("native-object mode %s is not supported"):format(tostring(mode)),
      commandPointer, mode, nil, event))
  end
  -- An injected resolver remains authoritative.  When absent, only the
  -- decoded fragment-79 evidence path is available; it validates every byte
  -- before exposing a mapped object and never supplies update/draw callbacks.
  local resolver = self.resolve or builtinResolution
  local resolved, resolveError = resolver(commandPointer, clone(event))
  if type(resolveError) == "number" then
    resolved = {object=resolved, delay=resolveError}
    resolveError = nil
  end
  local object, delay, resolution = normaliseResolution(resolved)
  if not object then
    local message = resolveError or "native-object resolver returned no explicit object/delay"
    return nil, self:_diagnose(diagnostic("unsupported-native-resolution",
      message, commandPointer, mode, nil, event))
  end
  local free
  for index = 0, self.capacity - 1 do
    if not self.slots[index].active then free = self.slots[index]; break end
  end
  if not free then
    return nil, self:_diagnose(diagnostic("native-object-capacity",
      ("native-object scheduler capacity %d exhausted"):format(self.capacity),
      commandPointer, mode, nil, event))
  end
  free.generation = free.generation + 1
  free.commandPointer = commandPointer
  free.event = event
  free.object = clone(object)
  free.resolution = clone(resolution)
  free.countdown = delay
  free.reload = 0
  free.age = 0
  free.state = 1
  free.active = true
  free.mode = mode
  free.visualObjects = {}
  free.rawFields = {}
  free.drawPackets = {}
  free.diagnostics = {}
  free.diagnosticKeys = {}
  return free.index, nil
end

function NativeObjects:_releaseSlot(slot)
  slot.commandPointer = nil
  slot.event = nil
  slot.object = nil
  slot.resolution = nil
  slot.countdown = nil
  slot.reload = nil
  slot.age = nil
  slot.state = nil
  slot.mode = nil
  slot.visualObjects = nil
  slot.rawFields = nil
  slot.drawPackets = nil
  slot.diagnostics = nil
  slot.diagnosticKeys = nil
  slot.active = false
end

function NativeObjects:release(index)
  if index == nil then
    for slotIndex = 0, self.capacity - 1 do
      if self.slots[slotIndex].active then self:_releaseSlot(self.slots[slotIndex]) end
    end
    return true
  end
  integer(index, "scheduler index")
  local slot = self.slots[index]
  if not slot then error("scheduler index out of range") end
  if slot.active then self:_releaseSlot(slot) end
  return true
end

function NativeObjects:_invoke(slot)
  local callback = self.callbacks[slot.mode]
  if type(callback) ~= "function" then
    self:_unsupported(slot, "unsupported-native-update",
      ("native-object update callback for mode %d is not installed"):format(slot.mode),
      slot.commandPointer, slot.mode, slot.index)
    -- Every audited mode wrapper returns signed slot+7 after its local body.
    -- The body remains unresolved, but scheduler completion does not: retain
    -- the diagnostic and use the constructor's exact state byte.
    return tonumber(slot.state) or 0
  end
  local ok, result = pcall(callback, clone(slot.object), clone(slot), clone(slot.event))
  if not ok then
    self:_unsupported(slot, "unsupported-native-update", result)
    return tonumber(slot.state) or 0
  end
  local value, visuals, rawFields, callbackDiagnostics = callbackResult(result)
  if visuals ~= nil then retain(slot.visualObjects, visuals) end
  if rawFields ~= nil then retain(slot.rawFields, rawFields) end
  if type(callbackDiagnostics) == "table" then
    for _, item in ipairs(callbackDiagnostics) do
      local normalized = diagnostic(item.code or "native-object-callback",
        item.message or "native-object callback diagnostic",
        slot.commandPointer, slot.mode, slot.index, slot.event)
      for key, value in pairs(item) do
        if normalized[key] == nil then normalized[key] = clone(value) end
      end
      slot.diagnostics[#slot.diagnostics + 1] = normalized
      self:_diagnose(normalized)
    end
  end
  if type(value) ~= "number" then
    self:_unsupported(slot, "unsupported-native-update",
      "native-object callback returned no scheduler result")
    return tonumber(slot.state) or 0
  end
  return value
end

function NativeObjects:tick(count)
  count = count == nil and 1 or integer(count, "tick count")
  if count < 0 then error("tick count must be non-negative") end
  for _ = 1, count do
    self.tickCount = self.tickCount + 1
    for index = 0, self.capacity - 1 do
      local slot = self.slots[index]
      if slot.active then
        if slot.countdown > 0 then
          slot.countdown = slot.countdown - 1
        end
        -- 0x84107BA4..0x84107BC4 dispatches on the same scheduler tick
        -- that decrements a positive countdown to zero.
        if slot.active and slot.countdown == 0 then
          local result = self:_invoke(slot)
          if result > 0 then
            if result == 0xFF then
              slot.countdown = slot.reload
            else
              slot.age = slot.age + 1
              if result == slot.age then self:_releaseSlot(slot)
              else slot.countdown = slot.reload end
            end
          end
        end
      end
    end
  end
  return self:snapshot()
end

function NativeObjects:step(count)
  return self:tick(count)
end

function NativeObjects:schedule(event)
  if type(event) ~= "table" then error("event must be a table") end
  return self:enqueue(event.commandPointer, event)
end

function NativeObjects:draw()
  for index = 0, self.capacity - 1 do
    local slot = self.slots[index]
    if slot.active then
      local callback = self.drawCallbacks and self.drawCallbacks[slot.mode]
      if type(callback) ~= "function" then
        self:_unsupported(slot, "unsupported-native-draw",
          ("native-object draw callback for mode %d is not installed"):format(slot.mode))
      else
        local ok, packet = pcall(callback, clone(slot.object), clone(slot),
          clone(slot.event), clone(slot.visualObjects), clone(slot.rawFields))
        if not ok then
          self:_unsupported(slot, "unsupported-native-draw", packet)
        elseif packet ~= nil then
          slot.drawPackets[#slot.drawPackets + 1] = clone(packet)
        end
      end
    end
  end
  return self:snapshot()
end

function NativeObjects:snapshot()
  local slots = {}
  for index = 0, self.capacity - 1 do
    local slot = self.slots[index]
    if slot.active then slots[#slots + 1] = clone(slot) end
  end
  return {
    capacity=self.capacity,
    tickCount=self.tickCount,
    slots=slots,
    diagnostics=clone(self.diagnostics),
  }
end

NativeObjects.Scheduler = NativeObjects

return NativeObjects
