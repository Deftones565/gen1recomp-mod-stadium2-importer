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

-- Weather FX entries. The Gen 2 engine's HandleWeather (841324EC) queues,
-- for battler 0, code 0x32/0x31/0x30 while rain/sun/sandstorm continues and
-- 0x35/0x34/0x33 when it ends (D_841951F0+0x9C4 is the weather, 1..3 as in
-- pokecrystal WEATHER_RAIN/SUN/SANDSTORM; +0x9C5 the turn count), and code
-- 0x48 for each battler the sandstorm hurts. The actor state 84119630 turns
-- 0x30..0x36 and 84118DD4 turns 0x48 into these 8410890C entries.
Sequence.WEATHER_ENTRIES = {
  rain = {turn = 0x107, ended = 0x11F},
  sun = {turn = 0x106, ended = 0x121},
  sandstorm = {turn = 0x113, ended = 0x120},
}
Sequence.WEATHER_OWNER = "player"
Sequence.SANDSTORM_HIT_ENTRY = 0x125
-- 84127194 (the turn check): paralysis (status bit 0x40) with a random roll
-- below 0x3F queues code 0x36 for the battler -> entry 0x10C.
Sequence.FULLY_PARALYZED_ENTRY = 0x10C

-- Non-move entries for battle events, from the event-code tables of
-- 84118DD4 (family 9) and the battle-engine call sites that queue each code
-- (fragment79_393CA0; see docs/luna/research/battle-event-effects.md).
-- 84131AF8 residual damage: poison/toxic 0x3C/0x3D, burn 0x3E, Leech Seed
-- 0x3F (on the seeded mon), Nightmare 0x40, Curse 0x43.
Sequence.RESIDUAL_ENTRIES = {
  poison = 0x101, toxic = 0x101, burn = 0x102, leechSeed = 0x103,
  nightmare = 0x10A, curse = 0x109,
}
Sequence.SPIKES_ENTRY = 0x10B        -- 84131EAC, code 0x46
Sequence.ATTRACT_ENTRY = 0x108       -- 84127194, code 6 (in love)
Sequence.HEAL_ENTRY = 0x10D          -- code 0x4A: drain, Leftovers, berries
-- 84129180: the drain heal picks a per-move code.
Sequence.DRAIN_ENTRIES = {[71] = 0x114, [72] = 0x115, [141] = 0x117, [202] = 0x116}
Sequence.STAT_UP_ENTRY = 0xFC        -- code 0x41
Sequence.STAT_DOWN_ENTRY = 0xFD      -- code 0x42
-- 8412FD24 queues 0x42 only for these moves (Sand-Attack, Growl, String
-- Shot, Screech, Smokescreen, Flash, Cotton Spore, Charm, Sweet Scent).
Sequence.STAT_DOWN_MOVES = {[28] = true, [45] = true, [81] = true, [103] = true,
  [108] = true, [148] = true, [178] = true, [204] = true, [230] = true}
Sequence.SEND_OUT_ENTRY = 0x122      -- 8411BCC8 (family 12) at state start
Sequence.FAINT_ENTRIES = {first = 0x119, second = 0x11A} -- 8411A620

-- 84124DEC / 84128CB8: a raised stat signals 0xFC when it belongs to the
-- side using the move (8412FC9C) or comes from Rage; raising the foe's stat
-- (Swagger, Flatter) signals nothing. A lowered stat signals 0xFD only for
-- STAT_DOWN_MOVES. `change`: side, stages, moveSide, moveId, rage.
function Sequence.statChangeEntry(change)
  change = type(change) == "table" and change or {}
  local stages = tonumber(change.stages) or 0
  if stages > 0 then
    if change.rage or (change.side ~= nil and change.side == change.moveSide) then
      return Sequence.STAT_UP_ENTRY
    end
  elseif stages < 0 then
    if Sequence.STAT_DOWN_MOVES[tonumber(change.moveId)] then return Sequence.STAT_DOWN_ENTRY end
  end
  return nil
end

-- 8411A3D4 copies context 253's row bytes 0x0B/0x0A to actor+0x619/+0x61A;
-- 8411A620 signals 0x119 when the faint counter reaches +0x619 (unless the
-- species' 8411E244 marker for 0x119 is 0xFF) and 0x11A at +0x61A.
function Sequence.faintFrames(dispatchBytes)
  if type(dispatchBytes) ~= "string" then return nil end
  local base = 253 * 20
  local first, second = dispatchBytes:byte(base + 0x0B + 1), dispatchBytes:byte(base + 0x0A + 1)
  if not first or not second then return nil end
  return first, second
end

-- Charge turn of two-turn moves. 8412C47C queues 0x16 Razor Wind, 0x17
-- SolarBeam, 0x18 Skull Bash, 0x19 Sky Attack (family 8), 0x1A Fly
-- (family 6), 0x1B Dig (family 7). Their setup states copy a charge row
-- through 841146D4 (84116010: 0xFF/0x101/0x103/0x104; 841155B0: 0x100;
-- 84115940: 0x102), play its body clip from row byte 6 (+0x61B), and at the
-- row's byte 0x0B (+0x619) call 841088CC: the variant (route mode 1) FX.
Sequence.CHARGE_ENTRIES = {[13] = 255, [19] = 256, [76] = 257, [91] = 258,
  [130] = 259, [143] = 260}

-- Returns entry, start frame (row byte 6), variant frame (row byte 0x0B).
function Sequence.chargeFrames(dispatchBytes, moveId)
  local entry = Sequence.CHARGE_ENTRIES[tonumber(moveId)]
  if not entry or type(dispatchBytes) ~= "string" then return entry end
  local base = entry * 20
  local start, frame = dispatchBytes:byte(base + 6 + 1), dispatchBytes:byte(base + 0x0B + 1)
  if not start or not frame then return entry end
  return entry, start, frame
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
