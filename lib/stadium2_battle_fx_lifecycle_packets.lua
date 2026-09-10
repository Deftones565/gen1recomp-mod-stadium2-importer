-- Renderer-neutral packets for native lifecycle snapshots.
--
-- The lifecycle callback audit proves the command words emitted by the draw
-- wrappers. The shared pointer is a matrix, not a model resource. Builtin
-- ribbon snapshots carry geometry from the ROM's draw routine; other families
-- require a resolver proving their model/geometry.
local Packets = {}

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

local function lifecycleSnapshot(snapshot)
  snapshot = type(snapshot) == "table" and snapshot or {}
  if type(snapshot.lifecycles) == "table"
      and (snapshot.instances == nil or snapshot.packets == nil) then
    return snapshot.lifecycles
  end
  return snapshot
end

local function diagnostic(fields)
  return {
    code = fields.code,
    severity = fields.severity or "warning",
    effectId = fields.effectId,
    programId = fields.programId,
    address = fields.address,
    kind = "lifecycle-packet",
    message = fields.message,
    instanceId = fields.instanceId,
    familyId = fields.familyId,
  }
end

local function evidenceFrom(packet, instance)
  local context = (instance and instance.context) or packet.context or {}
  return {
    kind = "lifecycle-command-evidence",
    instanceId = packet.instanceId or (instance and instance.id),
    familyId = packet.familyId or (instance and instance.familyId),
    effectId = context.effectId,
    programId = context.programId,
    address = context.address,
    command = packet.command,
    pointer = packet.pointer,
    drawHelper = packet.drawHelper,
    requiresDrawHelper = packet.requiresDrawHelper == true,
    counter = packet.counter,
    frame = packet.frame,
    context = copy(context),
    geometry = copy(packet.geometry),
  }
end

local function provenModel(value)
  if type(value) ~= "table" or value.proven ~= true then return nil end
  -- `model` and `geometry` are intentionally opaque resolver-owned values.
  -- A scalar model/shape identity is also acceptable when the resolver has
  -- marked it proven; this keeps resource lookup outside this module.
  if value.model == nil and value.geometry == nil and value.modelId == nil
      and value.shapeId == nil then
    return nil
  end
  return value
end

local function appendDiagnostic(out, item, seen)
  item = copy(item)
  local key = table.concat({tostring(item.code), tostring(item.effectId),
    tostring(item.programId), tostring(item.address), tostring(item.instanceId),
    tostring(item.message)}, "\31")
  if not seen[key] then
    seen[key] = true
    out.diagnostics[#out.diagnostics + 1] = item
  end
end

-- Convert a lifecycle-manager snapshot, or a full runtime snapshot containing
-- `lifecycles`, into deterministic evidence and (when proven) render packets.
--
-- `options.resolveModel(instance, evidence, context)` must return a table with
-- `proven=true` and one of `model`, `geometry`, `modelId`, or `shapeId`.  The
-- returned table is copied verbatim into the packet under `modelResolution`.
function Packets.build(snapshot, options)
  options = type(options) == "table" and options or {}
  local source = lifecycleSnapshot(snapshot)
  local out = {
    frame = (type(snapshot) == "table" and snapshot.frame) or source.frame or 0,
    packets = {},
    evidence = {},
    diagnostics = {},
  }
  local seenDiagnostics = {}

  for _, item in ipairs(source.diagnostics or {}) do
    appendDiagnostic(out, item, seenDiagnostics)
  end
  -- A full runtime snapshot has its own diagnostic stream in addition to the
  -- nested manager stream.  Keep both streams, deduplicated by evidence.
  if source ~= snapshot then
    for _, item in ipairs(snapshot.diagnostics or {}) do
      appendDiagnostic(out, item, seenDiagnostics)
    end
  end

  local instances = {}
  for _, instance in ipairs(source.instances or {}) do
    if type(instance) == "table" and instance.id ~= nil then
      instances[instance.id] = instance
    end
  end

  local resolver = options.resolveModel or options.modelResolver
  for _, rawPacket in ipairs(source.packets or {}) do
    if type(rawPacket) == "table" then
      local instance = instances[rawPacket.instanceId]
      local evidence = evidenceFrom(rawPacket, instance)
      out.evidence[#out.evidence + 1] = copy(evidence)

      local base = {
        effectId = evidence.effectId,
        programId = evidence.programId,
        address = evidence.address,
        instanceId = evidence.instanceId,
        familyId = evidence.familyId,
      }
      if evidence.instanceId == nil or evidence.familyId == nil then
        base.code = "lifecycle-identity-unresolved"
        base.message = "lifecycle draw evidence has no stable instance/family identity"
        appendDiagnostic(out, diagnostic(base), seenDiagnostics)
      elseif evidence.command ~= 0xDA380003
          or evidence.pointer ~= 0x841A4D08 then
        base.code = "lifecycle-command-unproven"
        base.message = "lifecycle draw evidence does not match the audited command words"
        appendDiagnostic(out, diagnostic(base), seenDiagnostics)
      elseif type(resolver) ~= "function" and evidence.geometry
          and (evidence.geometry.kind == "rom-ribbon" or evidence.geometry.kind == "rom-wave-grid"
            or evidence.geometry.kind == "rom-beam") then
        local packet = copy(evidence)
        packet.kind, packet.renderable = "lifecycle", true
        packet.modelResolution = {proven=true, geometry=copy(evidence.geometry)}
        out.packets[#out.packets + 1] = packet
      elseif type(resolver) ~= "function" then
        base.code = "lifecycle-model-unresolved"
        base.message = "lifecycle model/geometry requires an injected proof resolver"
        appendDiagnostic(out, diagnostic(base), seenDiagnostics)
      else
        local ok, resolution = pcall(resolver, copy(instance), copy(evidence),
          copy(evidence.context))
        if not ok then
          base.code = "lifecycle-model-resolver-error"
          base.message = tostring(resolution)
          appendDiagnostic(out, diagnostic(base), seenDiagnostics)
        else
          resolution = provenModel(resolution)
          if not resolution then
            base.code = "lifecycle-model-unresolved"
            base.message = "lifecycle model/geometry resolver did not prove a model"
            appendDiagnostic(out, diagnostic(base), seenDiagnostics)
          else
            local packet = copy(evidence)
            packet.kind = "lifecycle"
            packet.renderable = true
            packet.modelResolution = copy(resolution)
            out.packets[#out.packets + 1] = packet
          end
        end
      end
    else
      appendDiagnostic(out, diagnostic({
        code = "lifecycle-packet-malformed",
        message = "lifecycle draw entry is not a table",
      }), seenDiagnostics)
    end
  end
  return out
end

return Packets
