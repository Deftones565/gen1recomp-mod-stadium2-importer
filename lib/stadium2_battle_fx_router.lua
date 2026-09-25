-- Pure route selection for Stadium 2 battle effects.
--
-- The ROM catalog has already resolved variant and sequence indirection into
-- two ordered dispatch channels.  This module deliberately does not execute
-- those entries: program-local condition branches belong to Native.execute.
local Router = {}

local function clone(value, seen)
  if type(value) ~= "table" then return value end
  seen = seen or {}
  if seen[value] then return seen[value] end
  local copy = {}
  seen[value] = copy
  for key, item in pairs(value) do
    copy[clone(key, seen)] = clone(item, seen)
  end
  return copy
end

local function channelFor(move, alternate, variant)
  if type(move) ~= "table" then
    return nil, "missing decoded move row"
  end
  if type(alternate) ~= "boolean" then
    return nil, "alternate must be an explicit boolean"
  end
  if variant == true then
    -- Route mode 1 (841088CC): the +2 half of a side-variant primary.
    if alternate then return nil, "variant route has no alternate bank" end
    if type(move.variantDispatch) ~= "table" then
      return nil, "decoded move row has no variant route"
    end
    return move.variantDispatch
  end
  local key = alternate and "alternateDispatch" or "primaryDispatch"
  local channel = move[key]
  if type(channel) ~= "table" then
    return nil, ("decoded move row has no %s channel"):format(key)
  end
  return channel
end

-- Select exactly one ROM-authored channel, preserving its order.  Returned
-- entries are copies so a runtime may annotate them without mutating the ROM
-- catalog shared by other effects.
function Router.resolve(move, alternate, variant)
  local channel, err = channelFor(move, alternate, variant)
  if not channel then return nil, err end
  local out = {}
  for index, entry in ipairs(channel) do
    if type(entry) ~= "table" then
      return nil, ("dispatch entry %d is not a table"):format(index)
    end
    out[index] = clone(entry)
  end
  return out
end

-- Descriptive aliases keep callers independent of the internal name while
-- retaining one implementation and one contract.
Router.select = Router.resolve
Router.channel = Router.resolve

return Router
