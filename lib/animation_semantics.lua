-- Stadium 2 pose records do not contain human-readable clip names.  Their
-- per-species battle dispatch records do, however, identify which clip each
-- move selects.  Preserve those ROM-authored relationships without inventing
-- names that are not present in the cartridge.
local Semantics = {}

local MOVE_COUNT = 251

-- Runtime selector zero is the model's non-animated bind/default pose.  It is
-- not one of the external pose clips that the importer exposes.  External
-- selector 1 is exported as animation index 0; requests for the default pose
-- use that same first (idle) clip rather than exposing a one-frame T-pose.
local function exportedBodySelector(selector)
  selector = tonumber(selector)
  if selector == nil or selector < 0 or selector >= 0xFFFF then return 0xFFFF end
  if selector == 0 then return 0 end
  return selector - 1
end

function Semantics.apply(animations, auxiliary, Build, AnimationRouting, dispatchRows)
  animations = animations or {}
  local count = #animations
  if count == 0 then return nil, nil, "no animations" end

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
      exportedBodySelector(authored[1]), authored[2], romSelector = authored[1],
    } or { 0xFFFF, -1 }
    local animation = animations[(rows[move][1] or -1) + 1]
    if animation then animation.moveIds[#animation.moveIds + 1] = move end
  end

  local contexts = {}
  for index = 1, #(Build.CONTEXTS or {}) do
    local authored = dispatchRows and dispatchRows[MOVE_COUNT + index - 1]
    local selector = authored and exportedBodySelector(authored[1]) or 0xFFFF
    contexts[index] = selector
    local animation = animations[selector + 1]
    if animation then
      local role = Build.CONTEXTS[index]
      animation.contextIds[#animation.contextIds + 1] = MOVE_COUNT + index - 1
      animation.semanticRoles[#animation.semanticRoles + 1] = role
    end
  end
  local preferred = { "idle", "entrance", "faint", "hit" }
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
