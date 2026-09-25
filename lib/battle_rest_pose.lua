-- The pose a battler holds while no other clip is playing.
--
-- Stadium's idle state (BattleAnim_Dispatch_001, 84113BE8) re-runs 841139D0
-- every frame and only falls back to context 251 (idle) when it selects
-- nothing. 841139D0 reads the battler's snapshot in the current event record
-- (84134A6C) and checks, in this order:
--   +0x12 bit 2 (battle mon +0xF bit 0x40, set by the charge handler
--     8412C47C for move 0x13 Fly)         -> 8411388C: context 262, looping.
--   +0x12 bit 4 (+0xF bit 0x20, move 0x5B Dig):
--     species 50 Diglett / 51 Dugtrio     -> 84112218: context 258 held at
--                                            frame 0x28 / 0x30;
--     any other species                   -> 8411EE74: model hidden.
--   status == 0x20 (frozen)               -> 84112464: context 254 (hit)
--     held at frame 6, or frame 0 for the species in D_84183A50 (checked by
--     8411DC80 over 5 halfwords); species 252 holds context 251 at frame 0.
--   status & 7 (asleep)                   -> 84112324: context 261, looping.
--   HP 0                                  -> 8411EE74 (hosts handle faint).
-- Evidence: US assembly for fragment79_37A6E0/393CA0, fork C 7fc529e5.
-- Only body clips are selected; the context rows' auxiliary clips (byte 1)
-- are not in the model pack.
local RestPose = {}

RestPose.FROZEN_FRAME0_SPECIES = {[35] = true, [73] = true, [252] = true,
  [41] = true, [188] = true}
RestPose.UNDERGROUND_HOLD = {[50] = 0x28, [51] = 0x30}

-- `condition`: flying, underground, frozen, asleep (booleans).
-- Returns {context=, loop=, hold=} or {hidden=true}.
function RestPose.select(condition, species)
  condition = type(condition) == "table" and condition or {}
  species = tonumber(species)
  if condition.flying then
    return {context = "rom_context_262", loop = true}
  end
  if condition.underground then
    local frame = RestPose.UNDERGROUND_HOLD[species]
    if frame then return {context = "rom_context_258", hold = frame} end
    return {hidden = true}
  end
  if condition.frozen then
    if species == 252 then return {context = "idle", hold = 0} end
    return {context = "hit", hold = RestPose.FROZEN_FRAME0_SPECIES[species] and 0 or 6}
  end
  if condition.asleep then
    return {context = "rom_context_261", loop = true}
  end
  return {context = "idle", loop = true}
end

function RestPose.key(pose)
  if pose.hidden then return "hidden" end
  return tostring(pose.context) .. "@" .. tostring(pose.hold or "loop")
end

return RestPose
