-- Renderer-neutral packets for the persistent native-object scheduler.
--
-- Native-object callbacks are deliberately not treated as common particles.
-- This adapter carries the scheduler/object evidence through to a renderer and
-- only adds placement or geometry when an explicitly injected resolver proves
-- it.  An unresolved object remains visible in diagnostics, never as guessed
-- geometry.
local NativePackets = {}

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

local function number(value)
  return type(value) == "number" and value or nil
end

local function slotIndex(slot)
  return number(slot.schedulerIndex) or number(slot.index) or 0
end

local function identity(slot)
  return ("native-object:%d:%d"):format(slotIndex(slot),
    number(slot.generation) or 0)
end

local function diagnostic(slot, code, message, fields)
  fields = fields or {}
  local event = type(slot.event) == "table" and slot.event or {}
  local item = {
    code = code,
    severity = fields.severity or "warning",
    effectId = fields.effectId or event.effectId,
    programId = fields.programId or event.programId,
    address = fields.address or event.address or slot.commandPointer,
    kind = "native-object-packet",
    schedulerIndex = slotIndex(slot),
    generation = number(slot.generation) or 0,
    commandPointer = slot.commandPointer,
    mode = slot.mode,
    message = message,
  }
  for key, value in pairs(fields) do
    if item[key] == nil then item[key] = copy(value) end
  end
  return item
end

local function append(list, value)
  list[#list + 1] = copy(value)
end

local function callbackProof(callback, slot, context, code)
  if type(callback) ~= "function" then
    return nil, diagnostic(slot, code,
      "no explicit native-object resolver is installed")
  end
  local ok, value, detail = pcall(callback, copy(slot), copy(context))
  if not ok then
    return nil, diagnostic(slot, code, tostring(value))
  end
  if type(value) ~= "table" or value.resolved == false then
    return nil, diagnostic(slot, code,
      tostring(detail or "native-object resolver returned no proven result"))
  end
  -- A resolver must opt into proof.  Accepting arbitrary object-shaped data
  -- here would silently turn unresolved external ABI fields into visuals.
  if value.resolved ~= true then
    return nil, diagnostic(slot, code,
      "native-object resolver result is missing resolved=true")
  end
  return value
end

local function payloadProof(drawPackets, field)
  for _, payload in ipairs(drawPackets or {}) do
    if type(payload) == "table" and payload[field] ~= nil then return true end
  end
  return false
end

local function copySourceDiagnostics(out, snapshot)
  for _, item in ipairs(snapshot.diagnostics or {}) do append(out.diagnostics, item) end
end

local function sortSlots(slots)
  local out = {}
  for _, slot in ipairs(slots or {}) do out[#out + 1] = slot end
  table.sort(out, function(a, b)
    local ai, bi = slotIndex(a), slotIndex(b)
    if ai ~= bi then return ai < bi end
    return (number(a.generation) or 0) < (number(b.generation) or 0)
  end)
  return out
end

-- Build one packet per active scheduler slot.  The packet's `visualObjects`
-- and `drawPackets` fields are callback-owned payloads; this module never
-- expands them into common-particle packets.
function NativePackets.build(snapshot, options)
  snapshot = type(snapshot) == "table" and snapshot or {}
  options = type(options) == "table" and options or {}
  local out = {
    tickCount = snapshot.tickCount or 0,
    capacity = snapshot.capacity,
    packets = {},
    diagnostics = {},
  }
  copySourceDiagnostics(out, snapshot)
  local context = type(options.context) == "table" and options.context or {}

  for _, source in ipairs(sortSlots(snapshot.slots)) do
    local slot = copy(source)
    local packet = {
      kind = "native-object",
      nativeObjectId = identity(slot),
      schedulerIndex = slotIndex(slot),
      generation = number(slot.generation) or 0,
      active = slot.active == true,
      mode = slot.mode,
      countdown = slot.countdown,
      reload = slot.reload,
      age = slot.age,
      state = slot.state,
      effectId = slot.event and slot.event.effectId,
      programId = slot.event and slot.event.programId,
      commandPointer = slot.commandPointer,
      -- Keep every resolver boundary field detached and inspectable.
      event = copy(slot.event),
      object = copy(slot.object),
      resolution = copy(slot.resolution),
      visualObjects = copy(slot.visualObjects or {}),
      rawFields = copy(slot.rawFields or {}),
      drawPackets = copy(slot.drawPackets or {}),
      callbackDiagnostics = copy(slot.diagnostics or {}),
      placement = nil,
      geometry = nil,
    }

    local placement, placementDiagnostic = callbackProof(
      options.resolvePlacement, slot, context, "native-object-placement-unresolved")
    if placement then
      packet.placement = placement
    elseif payloadProof(packet.drawPackets, "placement") then
      packet.placement = {resolved = true, source = "native-draw-callback"}
    else
      append(out.diagnostics, placementDiagnostic)
    end

    local geometry, geometryDiagnostic = callbackProof(
      options.resolveGeometry, slot, context, "native-object-geometry-unresolved")
    if geometry then
      packet.geometry = geometry
    elseif payloadProof(packet.drawPackets, "geometry") then
      packet.geometry = {resolved = true, source = "native-draw-callback"}
    else
      append(out.diagnostics, geometryDiagnostic)
    end

    for _, item in ipairs(packet.callbackDiagnostics) do
      append(out.diagnostics, item)
    end
    out.packets[#out.packets + 1] = packet
  end
  return out
end

NativePackets.fromSnapshot = NativePackets.build

return NativePackets
