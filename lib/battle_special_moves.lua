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
Special.KINDS = {[97] = 6, [104] = 7, [107] = 9}

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

-- `opts`: kind, yaw (binary angle), trig ({tableA, tableB}), bodyHeight
-- (battle profile +04, Stadium units; Double Team only).
-- Returns the state, or nil and a reason when the evidence is missing.
function Special.new(opts)
  opts = type(opts) == "table" and opts or {}
  local kind = opts.kind
  if kind ~= Special.AGILITY and kind ~= Special.DOUBLE_TEAM then
    return nil, "unsupported behaviour kind " .. tostring(kind)
  end
  local trig = opts.trig
  if type(trig) ~= "table" or type(trig.tableA) ~= "table" or type(trig.tableB) ~= "table" then
    return nil, "behaviour kind " .. kind .. " needs the ROM trig tables"
  end
  if kind == Special.DOUBLE_TEAM and not tonumber(opts.bodyHeight) then
    return nil, "Double Team needs the species battle profile (+04)"
  end
  return {kind = kind, trig = trig, yaw = tonumber(opts.yaw) or 0,
    bodyHeight = tonumber(opts.bodyHeight), offset = {0, 0, 0},
    afterimages = {}, alpha = nil, started = false}
end

-- One 30 Hz tick of the attack state from the hit frame on.
function Special.step(state)
  if not state.started then
    state.started = true
    if state.kind == Special.AGILITY then agilityStart(state) else doubleTeamStart(state) end
  end
  if state.kind == Special.AGILITY then agilityUpdate(state, state.trig)
  else doubleTeamUpdate(state, state.trig) end
end

-- Stadium binary angle of each side's facing (8411E140); the player's
-- battler is the first one (x = -150 in 8411EFE4, matching
-- StadiumBattleLayout).
function Special.facing(side)
  return side == "player" and 0x4000 or -0x4000
end

return Special
