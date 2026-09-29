-- FREE CAMERA ADDITION (user-requested 2026-09-29; not Stadium 2 behaviour).
--
-- Some common particles are placed on the camera's view ray (descriptor bit
-- 0x1: CommonAnchor takes the prepared anchor of 8411DCCC / 84105930), such
-- as the Vice Grip / Guillotine / Bite jaws. In Stadium the attack camera
-- holds still while they play and then cuts to the defender, which takes
-- them off screen while they are still alive (verified from a retail save
-- state: docs/luna/research/fx-clock-rate-2026-09-29.md). The port has a free
-- camera and no cut, so when a move's impact starts (where Stadium cuts),
-- that move bank's camera-placed particles stop drawing.
--
-- Placement and simulation stay native; this only skips their packets, and
-- only when the battle adapter enables it (the viewer stays native). (A first
-- version also turned them with the free camera and pulled them in front of
-- the eye; the user removed that after testing.)
local Follow = {}

-- A common particle (mode 0/1) placed on the camera ray.
function Follow.placed(packet)
  if type(packet) ~= "table" or packet.kind ~= "common-particle" then return false end
  local mode = packet.descriptorMode
  if mode ~= 0 and mode ~= 1 then return false end
  return math.floor((tonumber(packet.descriptorFlags) or 0)) % 2 == 1
end

function Follow.new()
  return setmetatable({ hidden = {} }, { __index = Follow })
end

function Follow:hideEffect(effectId)
  if effectId ~= nil then self.hidden[effectId] = true end
end

function Follow:isHidden(packet)
  return self.hidden[packet.effectId] == true
end

return Follow
