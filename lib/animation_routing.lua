-- Align external skeletal clips with model-local texture/facial streams.
-- Both archives retain authored order, but auxiliary-only expressions may be
-- interleaved. A longest monotonic equal-duration alignment recovers the
-- paired streams without assuming equal array indices.
local Routing = {}

local function better(a, b)
  if not b then return true end
  if a.matches ~= b.matches then return a.matches > b.matches end
  if a.cost ~= b.cost then return a.cost < b.cost end
  return a.key < b.key
end

function Routing.assign(anims, aux)
  anims, aux = anims or {}, aux or {}
  local na, nx = #anims, #aux
  local memo = {}
  local function solve(i, j)
    local key = i .. ":" .. j
    if memo[key] then return memo[key] end
    if i > na or j > nx then
      local result = { matches = 0, cost = 0, pairs = {}, key = "" }
      memo[key] = result
      return result
    end
    local candidates = {}
    do
      local tail = solve(i + 1, j)
      candidates[#candidates + 1] = { matches=tail.matches, cost=tail.cost,
        pairs=tail.pairs, key="A"..tail.key }
    end
    do
      local tail = solve(i, j + 1)
      candidates[#candidates + 1] = { matches=tail.matches, cost=tail.cost,
        pairs=tail.pairs, key="X"..tail.key }
    end
    if tonumber(anims[i].frames) == tonumber(aux[j].frames) then
      local tail = solve(i + 1, j + 1)
      local pairs = { { i, j } }
      for _, pair in ipairs(tail.pairs) do pairs[#pairs + 1] = pair end
      candidates[#candidates + 1] = { matches=tail.matches + 1,
        cost=tail.cost + math.abs(i-j), pairs=pairs, key="M"..tail.key }
    end
    local best
    for _, candidate in ipairs(candidates) do if better(candidate, best) then best = candidate end end
    memo[key] = best
    return best
  end

  local route = {}
  for i = 1, na do route[i] = -1 end
  -- Slot zero is the source's default facial stream and remains the idle
  -- fallback when it is not consumed by a duration-aligned clip.
  if na > 0 and nx > 0 then route[1] = 0 end
  local result = solve(2, 1)
  for _, pair in ipairs(result.pairs) do route[pair[1]] = pair[2] - 1 end
  return route, { matches = result.matches, pairs = result.pairs }
end

function Routing.apply(anims, aux)
  local route, info = Routing.assign(anims, aux)
  for i, animation in ipairs(anims or {}) do animation.aux = route[i] or -1 end
  return route, info
end

return Routing
