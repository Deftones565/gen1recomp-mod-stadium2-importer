-- Per-move actor behaviours that Stadium runs in its attack state, for moves
-- whose look lives in battle code instead of effect data.
--
-- 84114804 stores a behaviour kind at actor+0x61F; the attack state
-- (8411845C) calls the kind's start routine (84123F60) on the hit frame and
-- its update (84124104) on every frame from the hit frame on, start first.
-- Evidence: US assembly for fragment79_38EFE0, fork C 7fc529e5.
--
-- Positions are Stadium world units relative to the battler's home slot
-- (8411EFE4); the scene scales them like the slot itself. Yaw is the battler's
-- facing (8411E140: +0x4000 for the first battler, -0x4000 for the other).
local f = require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_float")

local Special = {}

Special.MINIMIZE, Special.AGILITY, Special.DOUBLE_TEAM = 9, 6, 7
Special.MEDITATE = 13
Special.KINDS = {[57] = 10, [66] = 4, [96] = 13, [97] = 6, [104] = 7, [107] = 9,
  [110] = 12, [127] = 14, [185] = 25, [187] = 26, [194] = 24, [229] = 19}

-- Kind 13 (Meditate, 84114804's kind 0x0D for move 0x60): start 84122A78,
-- update 84122AB8 (US asm). They wobble the battler's scale (+0x30/+0x34/
-- +0x38) around its base (+0x5E4, the X scale at the start): stage 0 a
-- rising sine stretches it tall and thin, stage 1 keeps oscillating while
-- the amplitude decays by 0.8 each time the swing is within 0.01, and ends
-- on the base scale once the amplitude itself is within 0.01.
Special.MEDITATE_AMPLITUDE = f(0.4)    -- D_84189CB8
Special.MEDITATE_SMALL = f(0.01)       -- D_84189CBC
Special.MEDITATE_DECAY = f(0.8)        -- D_84189CC0

-- Kind 6 (Agility): start 841218EC, update 84121920; afterimages 84120E7C
-- (init) and 84120F5C (update).
Special.AGILITY_PEAK, Special.AGILITY_TURN, Special.AGILITY_END = 50, 49, 0.5
Special.AGILITY_RATE, Special.AGILITY_PHASE_STEP = f(0.1), 0xE38
Special.AGILITY_TRAIL = {f(0.3), f(0.45)}       -- D_84183C98
Special.AFTERIMAGE_ALPHA = 0x80                  -- slot +0x1D (materialAlpha)

-- Kind 7 (Double Team): start 84121CAC, update 84121DE8.
Special.DOUBLE_TEAM_PHASE = {0, -0xE38}          -- D_84183CB8 (s16)
Special.DOUBLE_TEAM_SIDE = {1, -1}               -- D_84183CCC[0..1]
Special.DOUBLE_TEAM_SPEED, Special.DOUBLE_TEAM_ACCEL = 0x222, 100
Special.DOUBLE_TEAM_FADE = 15
Special.DOUBLE_TEAM_BLINK = f(0.9)               -- D_84189C84..C90

local function s16(v)
  v = math.floor(v) % 65536
  return v >= 32768 and v - 65536 or v
end

-- 4096-entry sine table D_80087E50 (SINS) and its quarter-turn window
-- D_80088E50 (COSS), as loaded by FxRom.trigTables.
local function sins(trig, angle) return trig.tableA[math.floor((angle % 65536) / 16) + 1] end
local function coss(trig, angle) return trig.tableB[math.floor((angle % 65536) / 16) + 1] end

-- 841203B4: v += (target - v) * rate, snapped to 0 inside (-0.001, 0.001).
function Special.approach(value, target, rate)
  value = f(f(f(target - value) * rate) + value)
  if value < 0.001 and value > -0.001 then value = 0 end
  return value
end

-- 800372CC (Math_StepToS32 shape): step toward target by inc or dec.
function Special.stepTo(value, target, inc, dec)
  if value < target then return math.min(value + inc, target) end
  return math.max(value - dec, target)
end

-- 8412041C: x = COSS(yaw) * s, z = SINS(yaw) * s; y from the zeroed vector.
local function polarXZ(trig, s, yaw)
  return {f(coss(trig, yaw) * s), 0, f(sins(trig, yaw) * s)}
end

local function copy3(v) return {v[1], v[2], v[3]} end

local function agilityStart(state)
  state.phase, state.amp, state.stage = 0, 0, 0
  state.afterimages = {}
  for i = 1, 2 do
    state.afterimages[i] = {offset = copy3(state.offset), alpha = Special.AFTERIMAGE_ALPHA}
  end
end

local function agilityUpdate(state, trig)
  local target = state.stage == 0 and Special.AGILITY_PEAK or 0
  state.amp = Special.approach(state.amp, target, Special.AGILITY_RATE)
  state.phase = s16(state.phase + Special.AGILITY_PHASE_STEP)
  local s = f(sins(trig, state.phase) * state.amp)
  -- 8411EFE4 returns to the home slot, then 800357CC adds the sway.
  state.offset = polarXZ(trig, s, state.yaw)
  if state.stage == 0 then
    if state.amp > Special.AGILITY_TURN then state.stage = 1 end
  elseif state.amp <= Special.AGILITY_END then
    state.offset = {0, 0, 0}
  end
  -- 84120F5C: each slot keeps a fixed fraction of its distance from the
  -- battler (80037120 then 800371B4 with dist * D_84183C98[i]). The ROM goes
  -- through a distance and two table angles; this is the same point without
  -- the 4096-step angle quantisation. Slot yaw steps toward the battler's
  -- (84120310), which never turns here, so it stays equal.
  for i, image in ipairs(state.afterimages) do
    local k, o, p = Special.AGILITY_TRAIL[i], state.offset, image.offset
    image.offset = {f(o[1] + (p[1] - o[1]) * k), f(o[2] + (p[2] - o[2]) * k),
      f(o[3] + (p[3] - o[3]) * k)}
  end
end

local function doubleTeamStart(state)
  state.afterimages = {}
  for i = 1, 2 do
    state.afterimages[i] = {offset = copy3(state.offset), alpha = 0, speed = 0,
      phase = Special.DOUBLE_TEAM_PHASE[i], scale = 1}
  end
end

-- 84121DE8's battler alpha from slot 0's phase. The float is truncated to an
-- int and stored with sb, so values above 255 wrap (ROM behaviour); results
-- at or below 0x80 become 0x80.
function Special.doubleTeamAlpha(trig, phase)
  local wave
  if phase >= 0 and phase < 0x4000 then wave = coss(trig, phase)
  elseif phase >= 0x4000 then wave = coss(trig, phase + 0x8000)
  else wave = sins(trig, phase) end
  local value = f(f(f(wave * Special.DOUBLE_TEAM_BLINK) + 1) * 255)
  local byte = math.floor(value) % 256
  if byte <= 0x80 then byte = 0x80 end
  return byte
end

local function doubleTeamUpdate(state, trig)
  for i, image in ipairs(state.afterimages) do
    image.alpha = Special.stepTo(image.alpha, Special.AFTERIMAGE_ALPHA,
      Special.DOUBLE_TEAM_FADE, Special.DOUBLE_TEAM_FADE)
    image.speed = Special.stepTo(image.speed, Special.DOUBLE_TEAM_SPEED,
      Special.DOUBLE_TEAM_ACCEL, Special.DOUBLE_TEAM_ACCEL)
    image.phase = s16(image.phase + image.speed)
    local s = f(Special.DOUBLE_TEAM_SIDE[i]
      * f(f(sins(trig, image.phase) * state.bodyHeight) / 4))
    local v, o = polarXZ(trig, s, state.yaw), state.offset
    image.offset = {f(o[1] + v[1]), f(o[2] + v[2]), f(o[3] + v[3])}
  end
  state.alpha = Special.doubleTeamAlpha(trig, state.afterimages[1].phase)
end

local function trunc(v) return v < 0 and math.ceil(v) or math.floor(v) end

-- 84122A78: +0x5FC 0x16C, phase +0x5FE 0, speed +0x600 0, amplitude 0.4,
-- base = the X scale (taken as 1.0, the battler's own scale), stage 0.
local function meditateStart(state)
  state.meditate = {speedPhase = 0x16C, phase = 0, speed = 0,
    amplitude = Special.MEDITATE_AMPLITUDE, base = 1, stage = 0}
  state.axisScale = {1, 1, 1}
end

-- 84122AB8, one tick.
local function meditateUpdate(state, trig)
  local m = state.meditate
  local base = m.base
  if m.stage == 0 then
    if m.speedPhase >= 0 then m.speedPhase = s16(m.speedPhase + 0x2D) end
    m.speed = s16(trunc(f(f(sins(trig, m.speedPhase) * 182) * 15)))
    if m.phase >= 0 and m.phase < 0x4001 then m.phase = s16(m.phase + m.speed) end
    local swing = f(sins(trig, m.phase) * m.amplitude)
    state.axisScale = {f(base - swing), f(swing + base), f(base - swing)}
    if m.phase >= 0x4000 then m.speed, m.stage = 0x1554, 1 end
  elseif m.stage == 1 then
    local speed = m.speed
    m.phase = s16(m.phase + speed)
    local s = sins(trig, m.phase)
    local swing = f(s * m.amplitude)
    if swing <= Special.MEDITATE_SMALL then
      m.speed = s16(speed + 0x444)
      m.amplitude = f(m.amplitude * Special.MEDITATE_DECAY)
      swing = f(s * m.amplitude)
    end
    local other = f(s * m.amplitude)
    state.axisScale = {f(base - swing), f(other + base), f(base - other)}
    if m.amplitude <= Special.MEDITATE_SMALL then state.axisScale = {base, base, base} end
  end
end

-- Math_StepToF (800372xx, src/229E0.c): one step toward target.
local function stepToF(current, target, inc, dec)
  if current < target then
    current = f(current + inc)
    if current > target then current = target end
  else
    current = f(current - dec)
    if current < target then current = target end
  end
  return current
end
Special.stepToF = stepToF

-- Kind 12 (Withdraw, move 0x6E, not for D_841839EC's Squirtle, Wartortle,
-- Blastoise): start 84123914 is empty; update 8412391C steps each scale
-- axis (+0x30/+0x34/+0x38) toward 0 by 0.05 (D_84189D14/18/1C) and, once
-- the Y scale is at most 0.1 (D_84189D20, a double), sets all three to
-- 0.001 (D_84189D28): the Pokemon draws into itself.
Special.WITHDRAW = 12
Special.WITHDRAW_STEP = {f(0.05), f(0.05), f(0.05)}
Special.WITHDRAW_LIMIT = 0.1
Special.WITHDRAW_FLOOR = f(0.001)
Special.WITHDRAW_SPECIES_EXCEPT = {[7] = true, [8] = true, [9] = true}
local function withdrawStart(state) state.axisScale = {1, 1, 1} end
local function withdrawUpdate(state)
  local s = state.axisScale
  for axis = 1, 3 do s[axis] = stepToF(s[axis], 0, Special.WITHDRAW_STEP[axis], Special.WITHDRAW_STEP[axis]) end
  if s[2] <= Special.WITHDRAW_LIMIT then
    local v = Special.WITHDRAW_FLOOR
    state.axisScale = {v, v, v}
  end
end

-- Kind 26 (Belly Drum, move 0xBB): start 84122C94 (phase 0, speed 0xAAA,
-- amplitude 0.2 = D_84189CC4, base = the X scale), update 84122CCC: phase
-- += speed, speed += 0x4FA, amplitude *= 0.85 (D_84189CC8); scale =
-- (base - s, base + s, base - s) with s = SINS(phase) * amplitude, back to
-- the base once the amplitude is at most 0.01 (D_84189CCC). Fork C 15201a6.
Special.BELLY_DRUM = 26
Special.BELLY_DRUM_AMPLITUDE = f(0.2)
Special.BELLY_DRUM_DECAY = f(0.85)
Special.BELLY_DRUM_SMALL = f(0.01)
local function bellyDrumStart(state)
  state.drum = {phase = 0, speed = 0xAAA, amplitude = Special.BELLY_DRUM_AMPLITUDE, base = 1}
  state.axisScale = {1, 1, 1}
end
local function bellyDrumUpdate(state, trig)
  local d = state.drum
  local speed = d.speed
  d.phase = s16(d.phase + speed)
  d.speed = s16(speed + 0x4FA)
  local s = sins(trig, d.phase)
  d.amplitude = f(d.amplitude * Special.BELLY_DRUM_DECAY)
  local amp, base = d.amplitude, d.base
  local swing = f(s * amp)
  state.axisScale = {f(base - swing), f(swing + base), f(base - swing)}
  if amp <= Special.BELLY_DRUM_SMALL then state.axisScale = {base, base, base} end
end

-- Ballistic motion (84120464 / 841204BC, US asm), used by Waterfall. Start:
-- speed +0x608, its split along `angle` into +0x5F8 (horizontal, COSS) and
-- +0x5F4 (vertical, SINS), drag +0x610 = 0.01 (D_84189C40). Each update:
-- the speed steps toward `target` (Math_StepToF), counts as 0 once it has
-- reached it; c, s = its split; vx += c - drag * (old * vx + c) * 0.05
-- (D_84189C44), vy += s + (-gravity - drag * (old * vy + s)) * 0.05
-- (D_84189C48); the battler moves by (COSS(yaw + 0x4000) * vx, vy,
-- SINS(yaw + 0x4000) * vx) (8412041C writes x / z only, 800357CC adds).
Special.BALLISTIC_DRAG = f(0.01)
Special.BALLISTIC_FACTOR = f(0.05)
local function ballisticStart(state, speed, angle)
  local trig = state.trig
  state.ballistic = {speed = f(speed), drag = Special.BALLISTIC_DRAG,
    vx = f(coss(trig, angle) * speed), vy = f(sins(trig, angle) * speed)}
end
local function ballisticStep(state, target, step, angle, gravity)
  local trig, b = state.trig, state.ballistic
  local old = b.speed
  local new = stepToF(old, target, step, step)
  b.speed = new
  local mag = target <= new and 0 or new
  local c, s = f(coss(trig, angle) * mag), f(sins(trig, angle) * mag)
  local vx, vy, drag = b.vx, b.vy, b.drag
  local pushX = f(f(-drag) * f(f(old * vx) + c))
  local pushY = f(f(-gravity) - f(drag * f(f(old * vy) + s)))
  b.vx = f(f(vx + c) + f(pushX * Special.BALLISTIC_FACTOR))
  b.vy = f(f(vy + s) + f(pushY * Special.BALLISTIC_FACTOR))
  local d = polarXZ(trig, b.vx, state.yaw + 0x4000)
  local o = state.offset
  o[1], o[2], o[3] = f(o[1] + d[1]), f(o[2] + b.vy), f(o[3] + d[3])
end

-- Kind 14 (Waterfall, move 0x7F): start 84122D74 (84120464 with speed 1.0
-- = D_84183C90, angle 0x4000: straight up); update 84122DD8 rises with
-- 841204BC(2.0, 0.002, 0x4000, 18.0) and holds at 90 above the battler's
-- origin height (+0x650). Fork C 15201a6 / US asm.
Special.WATERFALL = 14
Special.WATERFALL_SPEED = f(1.0)
Special.WATERFALL_TOP = 90
local function waterfallStart(state)
  state.offset = {0, 0, 0}
  ballisticStart(state, Special.WATERFALL_SPEED, 0x4000)
end
local function waterfallUpdate(state)
  local o = state.offset
  if o[2] >= Special.WATERFALL_TOP then o[2] = Special.WATERFALL_TOP; return end
  ballisticStep(state, f(2.0), f(0.002), 0x4000, f(18.0))
  if o[2] >= Special.WATERFALL_TOP then o[2] = Special.WATERFALL_TOP end
end

-- Kind 10 (Surf, move 0x39): start 84122A04 (+0x623 = 0); update 84122A0C
-- puts the battler at its origin height + 84159FA8(x, z), the water height
-- of Surf's terrain grid under it, and its X rotation (+0x1E) at the
-- returned slope (degrees, truncated) * 182. The height is ported (offset
-- Y, from `state.terrainHeightAt`, the battler at its slot X, Z = 0); the
-- tilt (`surfTilt`, s16 binary angle) is applied by Scene:modelMatrix in
-- 8003614C's order. Without a running grid the battler stays where it is.
Special.SURF = 10
local function surfStart(state) state.offset = {0, 0, 0} end
local function surfUpdate(state)
  local query = state.terrainHeightAt
  if type(query) ~= "function" then return end
  local ok, height, slope = pcall(query, f(state.slotX or 0), 0)
  if ok and height then
    state.offset[2] = f(height)
    -- trunc.w.s: toward zero
    state.surfTilt = slope and s16((slope >= 0 and math.floor(slope) or -math.floor(-slope)) * 182) or nil
  end
end

-- Kind 24 (Destiny Bond, move 0xC2): start 84123E74 (US asm) sets the
-- targets X * 0.3, Y * 2, Z * 0.3 (D_84189D34), speed +0x60C = 0, counter
-- +0x623 = 0; update 84123EB0 (fork C 15201a6): from the 15th tick the
-- speed steps toward 0.2 (D_84189D3C) by 0.0017 (D_84189D38) and each
-- scale axis steps toward its target at that speed: tall and thin.
Special.DESTINY_BOND = 24
Special.DESTINY_BOND_THIN = f(0.3)
Special.DESTINY_BOND_ACCEL = f(0.0017)
Special.DESTINY_BOND_SPEED = f(0.2)
local function destinyBondStart(state)
  state.axisScale = {1, 1, 1}
  local s = state.axisScale
  state.bond = {count = 0, speed = 0,
    target = {f(s[1] * Special.DESTINY_BOND_THIN), f(s[2] + s[2]), f(s[3] * Special.DESTINY_BOND_THIN)}}
end
local function destinyBondUpdate(state)
  local b, s = state.bond, state.axisScale
  b.count = b.count + 1
  if b.count < 0xF then return end
  b.speed = stepToF(b.speed, Special.DESTINY_BOND_SPEED, Special.DESTINY_BOND_ACCEL, Special.DESTINY_BOND_ACCEL)
  s[2] = stepToF(s[2], b.target[2], b.speed, b.speed)
  s[3] = stepToF(s[3], b.target[3], b.speed, b.speed)
  s[1] = stepToF(s[1], b.target[1], b.speed, b.speed)
end

-- Kind 15 (the defender of Stomp 0x17 / Body Slam 0x22, set by 84116BC0):
-- start 84123828 (phase +0x600 = 0x71C, amplitude 0.4 = D_84189D0C);
-- update 84123858 (US asm): phase += 0xCCC, the amplitude steps toward 0
-- by 0.02 (D_84189D10); s = SINS(-|phase|) * amplitude; scale = (1 - s,
-- s + 1, 1 - s): the Pokemon is squashed flat and bounces back. Its base is
-- the constant 1.0.
Special.SQUASHED = 15
Special.SQUASH_AMPLITUDE = f(0.4)
Special.SQUASH_DECAY = f(0.02)
Special.DEFENDER_KINDS = {[23] = 15, [34] = 15}
local function squashStart(state)
  state.squash = {phase = 0x71C, amplitude = Special.SQUASH_AMPLITUDE}
  state.axisScale = {1, 1, 1}
end
local function squashUpdate(state, trig)
  local q = state.squash
  q.phase = s16(q.phase + 0xCCC)
  q.amplitude = stepToF(q.amplitude, 0, Special.SQUASH_DECAY, Special.SQUASH_DECAY)
  local angle = q.phase > 0 and s16(-q.phase) or q.phase
  local s = sins(trig, angle)
  local amp = q.amplitude
  state.axisScale = {f(1 - f(s * amp)), f(f(s * amp) + 1), f(1 - f(s * amp))}
end

-- 8411E1D4: +1 for the first battler (the player's), -1 for the other.
local function sideSign(state) return state.yaw == Special.facing("player") and 1 or -1 end

-- 841211CC(actor, speed, target): the spin yaw (+0x604) turns back by
-- `speed`; the target is negated for the second battler. Returns whether
-- this step passed the target (US asm).
local function spinStep(state, speed, target)
  if sideSign(state) < 0 then target = s16(-target) end
  local yaw = s16(state.spin.yaw - speed)
  state.spin.yaw = yaw
  if speed > 0 then
    if target < yaw then return false end
    return target - speed < yaw
  end
  if yaw < target then return false end
  return yaw < target - speed
end

-- The spins' wind-down speed (841212A0 / 841214C0): the current speed
-- scaled by the turn left, (0x20000 - (0x4000 - yaw)) / 0x20000 in double,
-- minus 1 when >= 1, times `factor` (a double), truncated; at least `min`.
local function windDownSpeed(sp, factor, min)
  local left = f(0x4000 - sp.yaw)
  local fraction = f((131072.0 - left) / 131072.0)
  if 1.0 <= fraction then fraction = f(fraction - 1.0) end
  local speed = f(sp.speed * fraction) * factor
  speed = s16(speed < 0 and math.ceil(speed) or math.floor(speed))
  if speed < min then speed = min end
  return speed
end

-- Kind 3 (Fly's rise, the charge turn): 841155B0 sets it with row 0x100;
-- Dispatch_045 (841156D0) starts it at the row's hit frame (+0x619).
-- Start 841210CC (fork C 15201a6): 84120464 with D_84183C90 (1.0) at
-- 0x4000, straight up. Update 84121130: once 200 above the origin height
-- (+0x650) the battler is held there, else 841204BC(1.45, 0.015, 0x4000,
-- 18.0), held at 200 if it got there. 841156D0 then ends the kind
-- (841206D0 keeps the height).
Special.FLY = 3
Special.FLY_SPEED = f(1.0)
Special.FLY_TOP = 200
local function flyStart(state)
  state.offset = {0, 0, 0}
  ballisticStart(state, Special.FLY_SPEED, 0x4000)
end
local function flyUpdate(state)
  local o = state.offset
  if o[2] >= Special.FLY_TOP then o[2] = Special.FLY_TOP; return end
  ballisticStep(state, f(1.45), f(0.015), 0x4000, f(18.0))
  if o[2] >= Special.FLY_TOP then o[2] = Special.FLY_TOP end
end
function Special.flyRisen(state)
  return state and state.offset and state.offset[2] >= Special.FLY_TOP or false
end

-- Kind 4 (Submission, move 0x42): start 84121260 (spin yaw +0x604 = the
-- facing; 84120464's velocity is set but never used), update 841212A0 (US
-- asm): while fewer than 3 passes, the speed (+0x5FE) steps toward 0x3330
-- by 0x16C (800372CC) and turns the yaw, counting each pass of the side's
-- facing (+-0x4000, 841211CC); then the speed is scaled by the turn left
-- ((0x20000 - (0x4000 - yaw)) / 0x20000, minus 1 when >= 1, * 0.8 =
-- D_84189C68, a double; at least 0xE38) until the facing is passed once
-- more, when the yaw is the facing again. The battler faces the yaw (+0x20).
Special.SUBMISSION = 4
local function submissionStart(state)
  state.spin = {speed = 0, yaw = state.yaw, passes = 0, landed = false}
  state.nativeYaw = state.yaw
end
local function submissionUpdate(state)
  local sp = state.spin
  local side = sideSign(state)
  if sp.passes < 3 then
    sp.speed = s16(Special.stepTo(sp.speed, 0x3330, 0x16C, 0x16C))
    if spinStep(state, sp.speed, s16(side * 0x4000)) then sp.passes = sp.passes + 1 end
  end
  if sp.passes >= 3 and not sp.landed then
    sp.landed = spinStep(state, windDownSpeed(sp, 0.8, 0xE38), s16(side * 0x4000))
    if sp.landed then sp.yaw = side > 0 and 0x4000 or -0x4000 end
  end
  state.nativeYaw = sp.yaw
end

-- Kind 5 (Dig's hole, the charge turn): 84115940 sets it with row 0x102;
-- 84115B34 starts it in substate 1 (the tick after frame 0x19) and
-- updates it in substate 2, not for Diglett / Dugtrio (+0x1A 0x32 / 0x33).
-- Start 841217C8 (fork C 15201a6): speed +0x5FE 0, passes +0x623 0, spin
-- yaw +0x604 = the facing. Update 841217E4: before 3 passes the speed
-- steps toward 0x3FFC by 0x16C and turns the yaw (841211CC, counting
-- passes of the side's facing); from then on it keeps turning at that
-- speed and Y (+0x28) steps toward (s32)(-(+0x648) * 3.5) by 5 on its
-- truncated value. The battler faces the yaw. +0x648 is profile +0x14
-- (`centerY`), Y is absolute: the origin height (`groundY`) + offset.
Special.DIG = 5
local function digStart(state)
  state.spin = {speed = 0, yaw = state.yaw, passes = 0}
  state.offset = {0, 0, 0}
  state.nativeYaw = state.yaw
end
local function digUpdate(state)
  local sp = state.spin
  local side = sideSign(state)
  if sp.passes < 3 then
    sp.speed = s16(Special.stepTo(sp.speed, 0x3FFC, 0x16C, 0x16C))
    if spinStep(state, sp.speed, s16(side * 0x4000)) then sp.passes = sp.passes + 1 end
  end
  if sp.passes >= 3 then
    spinStep(state, sp.speed, s16(side * 0x4000))
    local ground = f(state.groundY or 0)
    local y = f(ground + state.offset[2])
    local truncated = y < 0 and math.ceil(y) or math.floor(y)
    local depth = -(state.centerY or 0) * 3.5
    local goal = depth < 0 and math.ceil(depth) or math.floor(depth)
    y = Special.stepTo(truncated, goal, 5, 5)
    state.offset[2] = f(f(y) - ground)
  end
  state.nativeYaw = sp.yaw
end
-- 84115988: sunk (and hidden by 8411EE74) once Y <= -(+0x648) * 3.0.
function Special.digSunk(state)
  if not (state and state.offset) then return false end
  local y = f(f(state.groundY or 0) + state.offset[2])
  return y <= f(-f(state.centerY or 0) * f(3.0))
end

-- Kind 19 (Rapid Spin, move 0xE5): start 8412142C (spin yaw = the facing,
-- target Y scale +0x60C = Y * 1.3 (D_84189C70), 84120464(1.0, 0x4000)),
-- update 841214C0 (US asm): from the 4th pass a hop (841204BC(1.24, 0.009,
-- 0x4000, 18), never below the origin height); before the 13th pass the Y
-- scale approaches the target (841203B4, 0.2) from the 4th pass, the speed
-- steps toward 0x3A4C by 0x2D8 and turns the yaw the other way (-speed),
-- counting passes; then the Y scale approaches target / 1.3 (D_84189C74)
-- and the speed winds down (0.7 = D_84189C78, at least 0x1554) until the
-- facing is passed, when the yaw is the facing and Y = target / 1.3
-- (D_84189C80).
Special.RAPID_SPIN = 19
local function rapidSpinStart(state)
  state.spin = {speed = 0, yaw = state.yaw, passes = 0, landed = false}
  state.axisScale = {1, 1, 1}
  state.spinTargetY = f(1 * f(1.3))
  state.offset = {0, 0, 0}
  ballisticStart(state, f(1.0), 0x4000)
  state.nativeYaw = state.yaw
end
local function rapidSpinUpdate(state)
  local sp, s = state.spin, state.axisScale
  local side = sideSign(state)
  if sp.passes >= 4 then
    ballisticStep(state, f(1.24), f(0.009), 0x4000, f(18.0))
    if state.offset[2] < 0 then state.offset[2] = 0 end
  end
  if sp.passes < 0xD then
    if sp.passes >= 4 then s[2] = Special.approach(s[2], state.spinTargetY, f(0.2)) end
    sp.speed = s16(Special.stepTo(sp.speed, 0x3A4C, 0x2D8, 0x2D8))
    if spinStep(state, s16(-sp.speed), s16(side * 0x4000)) then sp.passes = sp.passes + 1 end
  end
  if sp.passes >= 0xD and not sp.landed then
    s[2] = Special.approach(s[2], f(state.spinTargetY / f(1.3)), f(0.2))
    sp.landed = spinStep(state, s16(-windDownSpeed(sp, 0.7, 0x1554)), s16(side * 0x4000))
    if sp.landed then
      sp.yaw = side > 0 and 0x4000 or -0x4000
      s[2] = f(state.spinTargetY / f(1.3))
    end
  end
  state.nativeYaw = sp.yaw
end

-- Kind 25 (Faint Attack, move 0xB9, counter-0 start): start 8412230C
-- enables both copy slots (+0x2D8, stride 0x170) with phase +0x442 from
-- D_84183CDC (0, 0), speed +0x444 0, alpha +0x2F5 0, the battler's pose and
-- scale 1. Update 84122448 (US asm), per copy i: alpha steps toward 0x80 by
-- 0xF, speed toward 0x222 by 0x64, phase += speed (held at 0x3F46 once it
-- reaches 0x4000); the copy stands at the battler + (COSS(yaw) * d,
-- D_84183CE4.y = 0, SINS(yaw) * d) with d = SINS(phase) * body height
-- (profile +04) / 4 * D_84183CF0[i] (1, -1). The battler's alpha follows
-- copy 0's phase like Double Team's (D_84189C94..CA0 = 0.9; at least 0x80).
Special.FAINT_ATTACK = 25
Special.FAINT_ATTACK_SIDE = {f(1), f(-1)}
local function faintAttackStart(state)
  state.afterimages = {}
  for i = 1, 2 do
    state.afterimages[i] = {offset = {0, 0, 0}, alpha = 0, speed = 0, phase = 0, scale = 1}
  end
end
local function faintAttackUpdate(state, trig)
  for i, image in ipairs(state.afterimages) do
    image.alpha = Special.stepTo(image.alpha, 0x80, 0xF, 0xF)
    image.speed = s16(Special.stepTo(image.speed, 0x222, 0x64, 0x64))
    image.phase = s16(image.phase + image.speed)
    if image.phase >= 0x4000 then image.phase = 0x3F46 end
    local d = f(Special.FAINT_ATTACK_SIDE[i] * f(f(sins(trig, image.phase) * state.bodyHeight) / f(4)))
    image.offset = {f(state.offset[1] + f(coss(trig, state.yaw) * d)), state.offset[2],
      f(state.offset[3] + f(sins(trig, state.yaw) * d))}
  end
  state.alpha = Special.doubleTeamAlpha(trig, state.afterimages[1].phase)
end

-- The ported kinds: start (84123F60's case) and update (84124104's case).
-- Agility / Double Team / Meditate are defined above.
Special.ROUTINES = {
  [Special.AGILITY] = {start = agilityStart, update = agilityUpdate},
  [Special.DOUBLE_TEAM] = {start = doubleTeamStart, update = doubleTeamUpdate},
  [Special.MEDITATE] = {start = meditateStart, update = meditateUpdate},
  [Special.WITHDRAW] = {start = withdrawStart, update = withdrawUpdate},
  [Special.BELLY_DRUM] = {start = bellyDrumStart, update = bellyDrumUpdate},
  [Special.WATERFALL] = {start = waterfallStart, update = waterfallUpdate},
  [Special.SURF] = {start = surfStart, update = surfUpdate},
  [Special.DESTINY_BOND] = {start = destinyBondStart, update = destinyBondUpdate},
  [Special.SQUASHED] = {start = squashStart, update = squashUpdate},
  [Special.SUBMISSION] = {start = submissionStart, update = submissionUpdate},
  [Special.RAPID_SPIN] = {start = rapidSpinStart, update = rapidSpinUpdate},
  [Special.FAINT_ATTACK] = {start = faintAttackStart, update = faintAttackUpdate},
  [Special.FLY] = {start = flyStart, update = flyUpdate},
  [Special.DIG] = {start = digStart, update = digUpdate},
}

-- 84114804: whether `species` runs this move's kind (Withdraw's exception).
function Special.kindFor(moveId, species)
  local kind = Special.KINDS[tonumber(moveId)]
  if kind == Special.WITHDRAW and Special.WITHDRAW_SPECIES_EXCEPT[tonumber(species)] then return nil end
  return kind
end

-- `opts`: kind, yaw (binary angle), trig ({tableA, tableB}), bodyHeight
-- (battle profile +04, Stadium units; Double Team only).
-- Returns the state, or nil and a reason when the evidence is missing.
function Special.new(opts)
  opts = type(opts) == "table" and opts or {}
  local kind = opts.kind
  if not Special.ROUTINES[kind] then
    return nil, "unsupported behaviour kind " .. tostring(kind)
  end
  local trig = opts.trig
  if type(trig) ~= "table" or type(trig.tableA) ~= "table" or type(trig.tableB) ~= "table" then
    return nil, "behaviour kind " .. kind .. " needs the ROM trig tables"
  end
  if (kind == Special.DOUBLE_TEAM or kind == Special.FAINT_ATTACK) and not tonumber(opts.bodyHeight) then
    return nil, "this behaviour kind needs the species battle profile (+04)"
  end
  if kind == Special.DIG and not (tonumber(opts.groundY) and tonumber(opts.centerY)) then
    return nil, "Dig needs the species battle profile (+08, +14)"
  end
  return {kind = kind, trig = trig, yaw = tonumber(opts.yaw) or 0,
    slotX = tonumber(opts.slotX), terrainHeightAt = opts.terrainHeightAt,
    bodyHeight = tonumber(opts.bodyHeight), offset = {0, 0, 0},
    groundY = tonumber(opts.groundY), centerY = tonumber(opts.centerY),
    afterimages = {}, alpha = nil, started = false}
end

-- One 30 Hz tick of the attack state from the hit frame on.
function Special.step(state)
  local routine = Special.ROUTINES[state.kind]
  if not state.started then
    state.started = true
    routine.start(state)
  end
  routine.update(state, state.trig)
end

-- Stadium binary angle of each side's facing (8411E140); the player's
-- battler is the first one (x = -150 in 8411EFE4, matching
-- StadiumBattleLayout).
function Special.facing(side)
  return side == "player" and 0x4000 or -0x4000
end

return Special
