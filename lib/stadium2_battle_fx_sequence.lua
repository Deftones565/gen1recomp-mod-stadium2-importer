-- Move/impact route selection performed by the battle actor code.
--
-- 84108728 arms route mode 0 (move bank, D_84182A5C+0) when the attacker
-- starts its move. At the hit frame (84117CAC: actor+0x7E8 == actor+0x619,
-- and (D_84193DD0+9)&7 ~= 6) the actor calls 841087B8, which chooses the
-- impact behavior below. 841088CC arms route mode 1 (the +2 half of a
-- side-variant primary; see FxRom.move variantDispatch).
local Sequence = {}

-- 841087B8: when (D_84193DD0+9)&7 == 1 only these moves still reach
-- 8410874C (route mode 2, impact bank). Surf (0x39) reaches 8410878C,
-- which selects mode 2 and the owner without arming a new dispatch.
Sequence.RESULT1_IMPACT_MOVES = {
  [0x2D] = true, [0x2F] = true, [0x30] = true, [0x5F] = true,
  [0x67] = true, [0xAD] = true, [0xC3] = true,
}
Sequence.SURF = 0x39
Sequence.DIG = 0x5B
-- 84108974 signals this entry on the failure path after a Dig mode-1 route.
Sequence.DIG_FAILURE_ENTRY = 0x12D

-- Hit-frame byte of a 20-byte animation-dispatch row (841146D4 copies row
-- +0x0B to actor+0x619).
Sequence.HIT_FRAME_OFFSET = 0x0B

-- `nativeResult` is the raw battle-result byte (D_84193DD0+9); only its low
-- three bits are consulted. Hosts that do not model it pass nil (0).
-- Returns "impact", "none", "owner" or "fail".
function Sequence.impactAction(moveId, nativeResult)
  moveId = tonumber(moveId)
  local result = math.floor(tonumber(nativeResult) or 0) % 8
  if result == 6 then return "none" end
  if result == 1 then
    if Sequence.RESULT1_IMPACT_MOVES[moveId] then return "impact" end
    if moveId == Sequence.SURF then return "owner" end
    return "fail"
  end
  return "impact"
end

-- Returns the dispatch hit frame for `moveId`, or nil when the row is absent.
function Sequence.hitFrame(dispatchBytes, moveId)
  moveId = math.floor(tonumber(moveId) or 0)
  if type(dispatchBytes) ~= "string" or moveId < 1 then return nil end
  local offset = (moveId - 1) * 20 + Sequence.HIT_FRAME_OFFSET
  local value = dispatchBytes:byte(offset + 1)
  if value == nil then return nil end
  -- actor+0x619 is compared as a signed byte (lb in 84117CAC).
  return value >= 0x80 and value - 0x100 or value
end

return Sequence
