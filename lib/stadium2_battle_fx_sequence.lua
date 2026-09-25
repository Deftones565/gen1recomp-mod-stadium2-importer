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

-- Result byte low bits as the Gen 2 battle engine in fragment79_393CA0
-- writes them (84134E30 into queued event +9):
--   841246AC sets 1 when the move is used; 84128298/84130E04 keep 1 when
--   the attack missed (D_841951D2, which is cleared only for effect 0x2D).
--   84124A7C, after damage: 4 when D_841951E4 (critical hit 1 / OHKO 2) is
--   set, else by D_841951E5 (type modifier, 10 = neutral): >10 -> 3,
--   <10 -> 2, 10 -> 0; then 5 for moves 0x14/0x23/0x84 (Bind, Wrap,
--   Constrict) or move effect 0x75 (80062D20; EFFECT_ROLLOUT in pokecrystal
--   constants/move_effect_constants.asm, which also names 0x2D
--   EFFECT_JUMP_KICK).
-- Other move-effect handlers write 5 or 6 themselves and are not decoded,
-- so only damaging hits and misses are built here. `facts`:
--   missed, damaging (bool), critical, ohko (bool), typeModifier (number),
--   moveId, moveEffect (80062D20 value, optional).
-- Returns the byte, or nil plus a reason when it cannot be derived.
Sequence.RESULT_NEUTRAL, Sequence.RESULT_MISSED = 0, 1
Sequence.RESULT_NOT_VERY, Sequence.RESULT_SUPER = 2, 3
Sequence.RESULT_CRITICAL, Sequence.RESULT_HELD = 4, 5
Sequence.HELD_MOVES = {[0x14] = true, [0x23] = true, [0x84] = true}
Sequence.HELD_EFFECT = 0x75
function Sequence.resultByte(facts)
  if type(facts) ~= "table" then return nil, "battle facts are unavailable" end
  if facts.missed == true then return Sequence.RESULT_MISSED end
  if facts.damaging ~= true then
    return nil, "non-damaging results are written by undecoded effect handlers"
  end
  local result
  if facts.critical == true or facts.ohko == true then
    result = Sequence.RESULT_CRITICAL
  else
    local modifier = tonumber(facts.typeModifier)
    if modifier == nil then return nil, "type modifier is unavailable" end
    result = modifier > 10 and Sequence.RESULT_SUPER
      or modifier < 10 and Sequence.RESULT_NOT_VERY or Sequence.RESULT_NEUTRAL
  end
  if Sequence.HELD_MOVES[tonumber(facts.moveId)]
      or tonumber(facts.moveEffect) == Sequence.HELD_EFFECT then
    result = Sequence.RESULT_HELD
  end
  return result
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
