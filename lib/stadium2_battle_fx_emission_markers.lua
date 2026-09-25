-- 84107998: which owner markers one common-particle emission uses. Each
-- returned marker receives the emitter's full particle set from 841072BC
-- (label stored at object +0x7E; the secondary call also sets flag 0x2).
local Markers = {}

local function has(value, mask) return math.floor((value or 0) / mask) % 2 == 1 end
local NONE = 0xFF

-- `markerSelect` is D_84190178 (opcode 17 sets it, opcodes 1/3 clear it).
-- `inputs`: primary (owner +61C, dispatch byte 2), secondary (+61D, byte 3),
-- context (8411E244 label), attachments (ordered owner marker labels,
-- owner +A8 list). Returns a list of {label=, secondary=} or nil plus a
-- reason when a required input is missing.
function Markers.select(event, markerSelect, inputs)
  inputs = type(inputs) == "table" and inputs or {}
  local flags, flags2 = event.flags or 0, event.flags2 or 0
  local out = {}
  local function add(label, secondary)
    if label ~= nil and label ~= NONE then out[#out + 1] = {label = label, secondary = secondary} end
  end
  if has(flags2, 1) then
    if type(inputs.attachments) ~= "table" then return nil, "owner marker list is unavailable" end
    for _, label in ipairs(inputs.attachments) do
      -- Label 100 (the model centre marker) is never an emission site.
      if label ~= 100 then add(label, false) end
    end
    return out
  end
  if has(flags, 8) then
    if inputs.context == nil then return nil, "context marker is unavailable" end
    add(inputs.context, false)
    return out
  end
  if (tonumber(markerSelect) or 0) == 0 then
    if inputs.primary == nil or inputs.secondary == nil then
      return nil, "owner dispatch markers are unavailable"
    end
    add(inputs.primary, false)
    add(inputs.secondary, true)
  elseif has(flags, 0x2000000) then
    if inputs.secondary == nil then return nil, "owner dispatch markers are unavailable" end
    add(inputs.secondary, true)
  else
    if inputs.primary == nil then return nil, "owner dispatch markers are unavailable" end
    add(inputs.primary, false)
  end
  return out
end

return Markers
