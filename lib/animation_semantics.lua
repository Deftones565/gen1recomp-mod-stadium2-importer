-- Stadium 2 pose records do not contain human-readable clip names.  Their
-- per-species battle dispatch records do, however, identify which clip each
-- move selects.  Preserve those ROM-authored relationships without inventing
-- names that are not present in the cartridge.
local Semantics = {}

local MOVE_COUNT = 251

-- Stadium's per-species records use both selector layouts found in the ROM.
-- A record whose authored domain fits wholly inside the pose bundle indexes
-- file 0 directly.  A record that reaches the bundle count reserves selector
-- 0 for the model's default pose and indexes external files from selector 1.
-- Derive the layout from that species' complete record; never infer it from a
-- particular role's position in the animation list.
function Semantics.selectorBase(animations, dispatchRows)
  local count = #(animations or {})
  local maximum = 0
  for index = 0, tonumber(dispatchRows and dispatchRows.n) or -1 do
    local selector = tonumber(dispatchRows[index] and dispatchRows[index][1])
    if selector and selector >= 0 and selector < 0xFFFF then
      maximum = math.max(maximum, selector)
    end
  end
  return maximum < count and 0 or 1
end

-- The model fragment's animation descriptor, tagged (species << 16) | 1:
-- u8 count at +4 and, at +0x0C, a pointer to `count` 4-byte entries whose
-- u16 at +2 is the pose-bundle file. 8003F2C4 indexes it directly by the
-- dispatch selector and leaves the animation unchanged when the selector is
-- not below the count. Returns a 0-based selector -> file table, or nil.
function Semantics.readSelectorTable(fragment, sourceBase, species)
  species = tonumber(species)
  sourceBase = tonumber(sourceBase)
  if type(fragment) ~= "string" or not species or not sourceBase then return nil end
  local function u32(o) local a,b,c,d=fragment:byte(o+1,o+4) return ((a*256+b)*256+c)*256+d end
  local tag = species * 65536 + 1
  for o = 0, #fragment - 16, 4 do
    if u32(o) == tag then
      local count = fragment:byte(o + 5)
      local at = u32(o + 12) - sourceBase
      if count > 0 and at >= 0 and at % 2 == 0 and at + count * 4 <= #fragment then
        local table_ = { n = count }
        for i = 0, count - 1 do
          local a, b = fragment:byte(at + i * 4 + 3, at + i * 4 + 4)
          table_[i] = a * 256 + b
        end
        return table_
      end
    end
  end
  return nil
end

local function exportedBodySelector(selector, base)
  selector = tonumber(selector)
  if selector == nil or selector < 0 or selector >= 0xFFFF then return 0xFFFF end
  if selector == 0 then return 0 end
  return selector - (base or 0)
end

function Semantics.apply(animations, auxiliary, Build, AnimationRouting, dispatchRows, selectorTable)
  animations = animations or {}
  local count = #animations
  if count == 0 then return nil, nil, "no animations" end
  local selectorBase = Semantics.selectorBase(animations, dispatchRows)
  local function bodySelector(selector)
    if not selectorTable then return exportedBodySelector(selector, selectorBase) end
    selector = tonumber(selector)
    if selector == nil or selector < 0 or selector >= selectorTable.n then return 0xFFFF end
    local file = selectorTable[selector]
    if file == nil or file >= count then return 0xFFFF end
    return file
  end

  if AnimationRouting and AnimationRouting.apply then
    AnimationRouting.apply(animations, auxiliary or {})
  end

  for luaIndex, animation in ipairs(animations) do
    local index = luaIndex - 1
    animation.name = "animation_" .. tostring(index)
    animation.semanticRole = nil
    animation.semanticRoles = {}
    animation.contextIds = {}
    animation.moveIds = {}
  end

  local rows = {}
  for move = 1, MOVE_COUNT do
    local authored = dispatchRows and dispatchRows[move - 1]
    rows[move] = authored and {
      bodySelector(authored[1]), authored[2],
      romSelector = authored[1], selectorBase = selectorBase,
    } or { 0xFFFF, -1 }
    local animation = animations[(rows[move][1] or -1) + 1]
    if animation then animation.moveIds[#animation.moveIds + 1] = move end
  end

  local contexts = {}
  for index = 1, #(Build.CONTEXTS or {}) do
    local authored = dispatchRows and dispatchRows[MOVE_COUNT + index - 1]
    local selector = authored
      and bodySelector(authored[1]) or 0xFFFF
    contexts[index] = selector
    local animation = animations[selector + 1]
    if animation then
      local role = Build.CONTEXTS[index]
      animation.contextIds[#animation.contextIds + 1] = MOVE_COUNT + index - 1
      animation.semanticRoles[#animation.semanticRoles + 1] = role
    end
  end
  local preferred = { "idle", "entrance", "faint", "hit", "sleep" }
  local attackNumber = 0
  for _, animation in ipairs(animations) do
    local roles = {}
    for _, role in ipairs(animation.semanticRoles) do roles[role] = true end
    for _, role in ipairs(preferred) do
      if roles[role] then
        animation.name = role
        animation.semanticRole = role
        break
      end
    end
    if not animation.semanticRole and #animation.moveIds > 0 then
      attackNumber = attackNumber + 1
      animation.name = attackNumber == 1 and "attack_default"
        or ("attack_" .. tostring(attackNumber))
      animation.semanticRole = "attack"
    end
  end
  return rows, contexts
end

return Semantics
