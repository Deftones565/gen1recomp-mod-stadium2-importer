-- Stadium 2 battle camera, ported from the US ROM to Lua (no VM at runtime).
-- Every function names the ROM routine it ports; each is checked bit for bit
-- against that routine run in the MIPS VM (tests/stadium2_battle_fx_camera_*_rom_test.lua).
-- See docs/luna/research/battle-camera.md.
--
-- Values follow the N64: floats are IEEE single precision (every operation
-- rounded), angles are signed 16-bit (0x10000 = one turn).
local f32 = require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_float")
local bit = require("bit")

local Native = {}

-- Main code is stored uncompressed at ROM 0x1000 for VRAM 0x80000400.
local MAIN_VRAM, MAIN_ROM = 0x80000400, 0x1000
Native.SINE_TABLE = 0x80087E50   -- D_80087E50, 0x1400 floats; cosine = +0x400
Native.COSINE_TABLE = 0x80088E50 -- D_80088E50
Native.ATAN_TABLE = 0x8008CE50   -- D_8008CE50, 0x401 u16

local function s16(v)
  v = math.floor(v) % 0x10000
  return v >= 0x8000 and v - 0x10000 or v
end
Native.s16 = s16

local function readFloat(bytes, offset)
  local b1, b2, b3, b4 = bytes:byte(offset + 1, offset + 4)
  local word = ((b1 * 256 + b2) * 256 + b3) * 256 + b4
  local sign = word >= 0x80000000 and -1 or 1
  local exponent = math.floor(word / 0x800000) % 0x100
  local mantissa = word % 0x800000
  if exponent == 0 then return sign * mantissa * 2 ^ -149 end
  if exponent == 0xFF then return mantissa == 0 and sign * math.huge or 0 / 0 end
  return sign * (1 + mantissa / 0x800000) * 2 ^ (exponent - 127)
end

-- Tables from the ROM (bytes = the whole normalised z64 ROM). fragment79 =
-- the decompressed battle fragment at VRAM 0x84100000 (shot rows, lists).
-- options.markerPosition(actorAddress) -> {x, y, z}: 8411DD8C, the actor's
-- marker point in battle units (supplied by the battle scene).
-- options.random() -> the next 32-bit word of 8003570C's LCG, from a private
-- presentation seed (Native.nextRandom), never the battle's RNG.
function Native.load(rom, fragment79, options)
  if type(rom) ~= "string" or #rom < MAIN_ROM + 0xA0000 then
    return nil, "Stadium 2 ROM bytes are required for the camera tables"
  end
  local function offset(vram) return vram - MAIN_VRAM + MAIN_ROM end
  local sine = {}
  local base = offset(Native.SINE_TABLE)
  for i = 0, 0x13FF do sine[i] = readFloat(rom, base + i * 4) end
  local atan = {}
  base = offset(Native.ATAN_TABLE)
  for i = 0, 0x400 do
    local hi, lo = rom:byte(base + i * 2 + 1, base + i * 2 + 2)
    atan[i] = hi * 256 + lo
  end
  local Memory = require("mods.STADIUM2_IMPORTER.lib.stadium2_native_memory")
  local images = { { base = MAIN_VRAM, bytes = rom:sub(MAIN_ROM + 1, MAIN_ROM + 0xA7000) } }
  if type(fragment79) == "string" then images[#images + 1] = { base = 0x84100000, bytes = fragment79 } end
  options = type(options) == "table" and options or {}
  return setmetatable({ rom = rom, introPaths = options.introPaths, speciesShots = options.speciesShots, sine = sine, atan = atan, mem = Memory.new(images),
    markerPosition = options.markerPosition, attachmentPoint = options.attachmentPoint,
    onStatusVisibility = options.onStatusVisibility,
    onActorReset = options.onActorReset, onActorHome = options.onActorHome,
    onEventTimer = options.onEventTimer, warn = options.warn,
    random = options.random }, { __index = Native })
end

-- sin/cos of an s16 angle (table index = (angle & 0xFFFF) >> 4).
function Native:sin(angle) return self.sine[bit.rshift(bit.band(angle, 0xFFFF), 4)] end
function Native:cos(angle) return self.sine[bit.rshift(bit.band(angle, 0xFFFF), 4) + 0x400] end

-- 8000B350(num, den): arctangent table entry for num/den (0..0x2000).
function Native:atanLookup(num, den)
  if den == 0 then return self.atan[0] end
  local index = f32(f32(f32(num / den) * 1024) + 0.5)
  index = index < 0 and math.ceil(index) or math.floor(index)
  return self.atan[index]
end

-- 8000B3B0(fa0 = x, fa1 = y): the s16 angle of (x, y), 0 along +x and
-- 0x4000 along +y, resolved octant by octant as the ROM does.
function Native:atan2(x, y)
  local v
  if y >= 0 then
    if x >= 0 then
      if y <= x then v = self:atanLookup(y, x)
      else v = 0x4000 - self:atanLookup(x, y) end
    else
      local X = -x
      if X < y then v = 0x4000 + self:atanLookup(X, y)
      else v = 0x8000 - self:atanLookup(y, X) end
    end
  else
    local Y = -y
    if x < 0 then
      local X = -x
      if Y <= X then v = 0x8000 + self:atanLookup(Y, X)
      else v = 0xC000 - self:atanLookup(X, Y) end
    else
      if x < Y then v = 0xC000 + self:atanLookup(x, Y)
      else v = -self:atanLookup(Y, x) end
    end
  end
  return s16(v)
end

-- 80037120(from, to): distance, pitch and yaw from `from` to `to`.
function Native:angleTo(from, to)
  local dx = f32(to[1] - from[1])
  local dy = f32(to[2] - from[2])
  local dz = f32(to[3] - from[3])
  local xx = f32(dx * dx)
  local zz = f32(dz * dz)
  local distance = f32(math.sqrt(f32(f32(xx + f32(dy * dy)) + zz)))
  local flat = f32(math.sqrt(f32(xx + zz)))
  return distance, self:atan2(flat, dy), self:atan2(dz, dx)
end

-- 800371B4(center, distance, pitch, yaw): the point at that distance and
-- those angles from `center`.
function Native:placeEye(center, distance, pitch, yaw)
  local horizontal = f32(distance * self:cos(pitch))
  return {
    f32(f32(self:sin(yaw) * horizontal) + center[1]),
    f32(f32(self:sin(pitch) * distance) + center[2]),
    f32(f32(self:cos(yaw) * f32(distance * self:cos(pitch))) + center[3]),
  }
end

-- 841203B4(value, goal, rate): value + (goal - value) * rate, snapped to 0
-- inside (-0.001, 0.001) (D_84189C38 / D_84189C30, compared as doubles).
function Native.ease(value, goal, rate)
  local out = f32(f32(f32(goal - value) * rate) + value)
  if out < 0.001 and out > -0.001 then out = 0 end
  return out
end

-- 8003570C: the game's LCG. The camera takes random choices from an injected
-- presentation RNG, never a shared seed; this is the native sequence for it.
function Native.nextRandom(seed)
  local low = bit.band(seed, 0xFFFF)
  local high = bit.rshift(bit.band(seed, 0xFFFF0000), 16)
  -- seed * 0x19660D mod 2^32, split to stay inside double precision
  local product = (low * 0x19660D + ((high * 0x19660D) % 0x10000) * 0x10000) % 0x100000000
  return (product + 0x3C6EF35F) % 0x100000000
end

-- ------------------------------------------------------------ shot setup

-- Globals (fragment 79 BSS).
Native.CONTROLLER0 = 0x841911E0 -- D_841911E0: controller of GeoCamera 0
Native.CONTROLLER1 = 0x841911E4 -- D_841911E4
Native.CURRENT = 0x841911E8     -- D_841911E8: controller being set up
Native.PLAYER = 0x84191208      -- D_84191208: the player's actor
Native.ENEMY = 0x8419120C       -- D_8419120C
Native.RECORD = 0x84193DD0      -- D_84193DD0: the current battle record
Native.SHOTS = 0x8418455C       -- D_8418455C: 39 shot rows of 0x1C bytes
Native.SHOT_LEAD = 0x84183970   -- D_84183970: shots with a forward lead
Native.KIND_FACING = 0x8418393C -- D_8418393C: actor kinds facing sideways

-- 8410B330: the controller whose GeoCamera is `gc`.
function Native:controllerFor(gc)
  local m = self.mem
  local c0 = m:u32(Native.CONTROLLER0)
  if gc == m:u32(c0) then return c0 end
  return m:u32(Native.CONTROLLER1)
end

-- 8411DC80(value, list, bytes): value in the u16 list of bytes/2 entries.
function Native:inList(value, list, bytes)
  value = value % 0x10000
  for i = 0, math.floor(bytes / 2) - 1 do
    if self.mem:u16(list + i * 2) == value then return true end
  end
  return false
end

-- 8411E1F8: 0 for the player's actor, 1 for the other.
function Native:side(actor)
  return actor == self.mem:u32(Native.PLAYER) and 0 or 1
end

-- 8411E140: the sideways facing of an actor kind in D_8418393C.
function Native:sideFacing(actor)
  return actor == self.mem:u32(Native.PLAYER) and 0x4000 or -0x4000
end

-- 8410B8FC(offset, yaw): the offset rotated by the facing (x and z only).
function Native:rotateOffset(v, yaw)
  local s, c = self:sin(yaw), self:cos(yaw)
  return f32(f32(s * v[3]) + f32(v[1] * c)), f32(f32(c * v[3]) + f32(f32(-v[1]) * s))
end

-- 8411E0A4(actor, out, controller): the marker point (8411DD8C) raised by
-- the controller's height and led along the actor's facing.
function Native:markerPoint(actor, ctrl)
  local m = self.mem
  local p = assert(self.markerPosition, "battle camera needs markerPosition (8411DD8C)")(actor)
  local lead, yaw = m:f32(ctrl + 0x78), m:u16(actor + 0x20)
  return {
    f32(p[1] + f32(lead * self:sin(yaw))),
    f32(p[2] + m:f32(ctrl + 0x7C)),
    f32(p[3] + f32(lead * self:cos(yaw))),
  }
end

-- 8410B974(gc, actor, yaw, shot, withCloseCheck): the controller's anchor
-- (+0x50 look point, +0x5C target), distance and height for a shot on
-- `actor`, and the GeoCamera target (+0xB4).
function Native:anchor(gc, actor, yaw, shot, close)
  local m = self.mem
  local ctrl = self:controllerFor(gc)
  m:setU32(Native.CURRENT, ctrl)
  m:setF32(ctrl + 0x84, m:f32(actor + 0x644))
  m:setF32(ctrl + 0x80, m:f32(actor + 0x640))
  m:setF32(ctrl + 0x7C, m:f32(actor + 0x654))
  m:setF32(ctrl + 0x74, m:f32(actor + 0x64C))
  if self:inList(shot, Native.SHOT_LEAD, 0x18) then
    local factor = m:s16(actor + 0x1A) == 0x5F and m:f32(0x84188E34) or m:f32(0x84188E38)
    m:setF32(ctrl + 0x78, f32(m:f32(actor + 0x64C) * factor))
  else
    m:setF32(ctrl + 0x78, 0)
  end
  local ox, oz = self:rotateOffset(m:vec(actor + 0x634), yaw)
  local x = f32(ox + m:f32(actor + 0x24))
  local z = f32(oz + m:f32(actor + 0x2C))
  x = f32(x + f32(m:f32(ctrl + 0x78) * self:sin(yaw)))
  z = f32(z + f32(m:f32(ctrl + 0x78) * self:cos(yaw)))
  local y = m:f32(actor + 0x638)
  m:setVec(ctrl + 0x5C, { x, y, z })
  m:setVec(ctrl + 0x50, { x, y, z })
  local record = m:u32(Native.RECORD)
  local side = self:side(actor)
  if m:u16(record + side * 16 + 0x12) % 4 >= 2 or m:u16(actor + 0x7F4) % 16 >= 8 then
    local raised = f32(m:f32(actor + 0x638) + 200)
    local species = m:s16(actor + 0x1A)
    local top = raised
    if species == 0xA3 then top = f32(raised + 30) end
    if species == 0x54 then top = f32(raised + 50) end
    if species == 0x55 then top = f32(raised + 50) end
    m:setVec(ctrl + 0x5C, { x, top, z })
    m:setVec(ctrl + 0x50, { x, top, z })
  end
  local code = m:u16(record + 4)
  local flags = m:u16(record + side * 16 + 0x12)
  if code == 8 or code == 4 then
    if flags % 8 >= 4 then m:setF32(ctrl + 0x60, 30); m:setF32(ctrl + 0x54, 30) end
  elseif flags % 8 >= 4 or m:u16(actor + 0x7F4) % 32 >= 16 then
    m:setF32(ctrl + 0x60, 30); m:setF32(ctrl + 0x54, 30)
  end
  if m:u16(record + side * 16 + 0xE) == 0 and close == 1 then
    m:setF32(ctrl + 0x60, 50); m:setF32(ctrl + 0x54, 50)
  end
  m:setVec(gc + 0xB4, m:vec(ctrl + 0x5C))
  if m:s16(actor + 0x7EA) ~= 0 and m:u16(record + side * 16 + 0x10) ~= 0x20 then
    local point = self:markerPoint(actor, ctrl)
    local distance = self:angleTo(point, m:vec(ctrl + 0x50))
    if m:f32(ctrl + 0x80) < distance then
      m:setVec(ctrl + 0x5C, point)
      m:setVec(gc + 0xB4, point)
    end
  end
  return ctrl
end

local function setupShot(self, gc, actor, shot, close)
  local m = self.mem
  local ctrl = self:controllerFor(gc)
  m:setU32(Native.CURRENT, ctrl)
  local yaw
  if self:inList(m:u8(actor + 0x61F), Native.KIND_FACING, 8) then yaw = s16(self:sideFacing(actor))
  else yaw = m:s16(actor + 0x20) end
  local sign = yaw < 0 and -1 or 1
  m:setF32(ctrl + 0x44, 0)
  self:anchor(gc, actor, yaw, shot, close)
  local row = Native.SHOTS + shot * 0x1C
  m:setU16(ctrl + 0x90, m:u16(row))
  m:setU16(ctrl + 0x92, s16(m:s16(row + 2) * sign + yaw) % 0x10000)
  m:setF32(ctrl + 0x74, f32(m:f32(ctrl + 0x74) * m:f32(row + 4)))
  m:setF32(ctrl + 0x88, m:f32(row + 0x10))
  local wide = shot == 0x24 or row == 0x84184968 or row == 0x84184984
  m:setF32(gc + 0x2C, wide and 80 or 45)
  m:setF32(ctrl + 0x88, wide and 80 or 45)
  local eye = self:placeEye(m:vec(ctrl + 0x50), m:f32(ctrl + 0x74), m:s16(ctrl + 0x90), m:s16(ctrl + 0x92))
  m:setVec(gc + 0xA8, eye)
  m:setVec(ctrl + 0x68, eye)
  return ctrl
end

-- 8410C934(gc, actor, shot) / 8410CAE4: set the camera on shot `shot`
-- (D_8418455C row) around `actor`. They differ only in 8410B974's last
-- argument (the fainted-target lift).
function Native:shot(gc, actor, shot) return setupShot(self, gc, actor, shot, 1) end
function Native:shotB(gc, actor, shot) return setupShot(self, gc, actor, shot, 0) end

-- 8410B884(gc, actor, ctrl, yaw): the second half of the controller's shot
-- row (+8..+0x18) into its secondary pose fields +0x3C..+0x4C.
function Native:secondaryPose(actor, ctrl, yaw)
  local m = self.mem
  local sign = yaw < 0 and -1 or 1
  local row = Native.SHOTS + m:s16(ctrl + 0x98) * 0x1C
  m:setU16(ctrl + 0x3C, m:u16(row + 8))
  m:setU16(ctrl + 0x3E, s16(m:s16(row + 0xA) * sign + yaw) % 0x10000)
  m:setF32(ctrl + 0x40, f32(m:f32(actor + 0x64C) * m:f32(row + 0xC)))
  m:setF32(ctrl + 0x4C, m:f32(row + 0x14))
  m:setF32(ctrl + 0x48, m:f32(row + 0x18))
end

-- ------------------------------------------------------------ program 0
-- Reading a ROM float constant (D_84188xxx) keeps every threshold exact.
function Native:const(address) return self.mem:f32(address) end

-- The reframe distance bands of 8410D5CC / 8410DAC8 / 8410D9B8 / 8410DEB4:
-- {T, F}, first match wins: slack * T < distance -> eye at distance * F.
-- T/F are ROM addresses, or plain numbers for the immediates (1.5, 1, 0.5,
-- 0.75); T = 1 compares the slack itself.
local BANDS = {
  [0x8410D5CC] = { {1.5,0x84188E88}, {0x84188E8C,0x84188E90}, {0x84188E94,0x84188E98},
    {0x84188E9C,0x84188EA0}, {0x84188EA4,0x84188EA8}, {1,0.75}, {0x84188EAC,0x84188EB0},
    {0x84188EB4,0x84188EB8}, {0x84188EBC,0x84188EC0}, {0x84188EC4,0x84188EC8},
    {0.5,0x84188ECC}, {0x84188ED0,0x84188ED4} },
  [0x8410DAC8] = { {1.5,0x84188EE8}, {0x84188EEC,0x84188EF0}, {0x84188EF4,0x84188EF8},
    {0x84188EFC,0x84188F00}, {0x84188F04,0x84188F08}, {1,0x84188F0C}, {0x84188F10,0x84188F14},
    {0x84188F18,0x84188F1C}, {0x84188F20,0x84188F24}, {0x84188F28,0x84188F2C},
    {0.5,0.75}, {0x84188F30,0x84188F34} },
  [0x8410D9B8] = { {0x84188ED8,0x84188EDC}, {1.5,0.75}, {0x84188EE0,0x84188EE4} },
  [0x8410DEB4] = { {0x84188F38,0x84188F3C}, {0x84188F40,0.75}, {1.5,0x84188F44} },
}
Native.BANDS = BANDS

function Native:value(v)
  if v > 0x80000000 then return self:const(v) end
  return v
end

-- One of the band helpers: `out` (a vector) is replaced by the eye at the
-- first matching band, or left as it is.
function Native:reframe(helper, ctrl, distance, pitch, yaw, from, out)
  local slack = self.mem:f32(ctrl + 0x80)
  for _, band in ipairs(BANDS[helper]) do
    local T, F = band[1], self:value(band[2])
    local limit = T == 1 and slack or f32(slack * self:value(T))
    if limit < distance then
      local eye = self:placeEye(from, f32(distance * F), pitch, yaw)
      out[1], out[2], out[3] = eye[1], eye[2], eye[3]
      return
    end
  end
end

local SPECIES_REFRAME = {
  [0xE8] = 0x8410D9B8, [0x24] = 0x8410D9B8, [0xE2] = 0x8410D9B8,
  [0x57] = 0x8410DAC8, [0x9C] = 0x8410DAC8, [0x49] = 0x8410DAC8, [0x71] = 0x8410DAC8,
  [0x9B] = 0x8410DEB4,
}

-- 8410DFC4(gc, actor): keep the actor framed. When its marker point is
-- farther than the slack (+0x80) from the look point, move the target
-- toward it by the species band table and ease the target height at a rate
-- set by how far off it is; otherwise draw the target back to the anchor.
function Native:follow(gc, actor)
  local m = self.mem
  local ctrl = self:controllerFor(gc)
  m:setU32(Native.CURRENT, ctrl)
  local record = m:u32(Native.RECORD)
  local side = self:side(actor)
  if m:u16(record + side * 16 + 0x12) % 8 >= 4 then return end
  if m:u16(actor + 0x7F4) % 32 >= 16 then return end
  if m:u16(record + side * 16 + 0x10) == 0x20 then return end
  if m:f32(actor + 0x34) <= self:const(0x84188F48) then return end
  local p
  if m:s16(actor + 0x7EA) == 1 then p = self:markerPoint(actor, ctrl)
  else p = m:vec(ctrl + 0x50) end
  m:setU16(actor + 0x7EA, 1)
  local distance = self:angleTo(p, m:vec(ctrl + 0x50))
  local goal, rate
  if m:f32(ctrl + 0x80) < distance then
    local d, pitch, yaw = self:angleTo(p, m:vec(gc + 0xB4))
    local species = m:s16(actor + 0x1A)
    local height = species == 0xE8 and m:f32(ctrl + 0x54) or p[2]
    local out = { m:f32(ctrl + 0x5C), m:f32(ctrl + 0x54), m:f32(ctrl + 0x64) }
    local from = { p[1], m:f32(ctrl + 0x54), p[3] }
    self:reframe(SPECIES_REFRAME[species] or 0x8410D5CC, ctrl, d, pitch, yaw, from, out)
    m:setF32(ctrl + 0x5C, out[1]); m:setF32(gc + 0xB4, out[1])
    m:setF32(ctrl + 0x64, out[3]); m:setF32(gc + 0xBC, out[3])
    local off = f32(height - m:f32(ctrl + 0x60))
    if off < 0 then off = f32(off * -1) end
    local slack = m:f32(ctrl + 0x80)
    if species == 0x9B then
      if f32(slack * self:const(0x84188F4C)) < off then rate = 0x3D4CCCCD
      elseif f32(slack * self:const(0x84188F50)) < off then rate = 0x3D23D70A end
    elseif slack < off then rate = 0x3E3851EC
    elseif f32(slack * self:const(0x84188F54)) < off then rate = 0x3E19999A
    elseif f32(slack * self:const(0x84188F58)) < off then rate = 0x3E051EB8
    elseif f32(slack * self:const(0x84188F5C)) < off then rate = 0x3DCCCCCD
    elseif f32(slack * self:const(0x84188F60)) < off then rate = 0x3DA3D70A
    elseif f32(slack * 0.5) < off then rate = 0x3D75C28F end
    if rate then
      m:setF32(ctrl + 0x60, Native.ease(m:f32(ctrl + 0x60), height, require("mods.STADIUM2_IMPORTER.lib.stadium2_native_memory").wordFloat(rate)))
    end
    m:setF32(gc + 0xB8, m:f32(ctrl + 0x60))
    return
  end
  local d, pitch, yaw = self:angleTo(m:vec(ctrl + 0x50), m:vec(ctrl + 0x5C))
  goal = m:f32(ctrl + 0x54)
  local eye = self:placeEye(m:vec(ctrl + 0x50), f32(d * self:const(0x84188F64)), pitch, yaw)
  m:setF32(ctrl + 0x5C, eye[1]); m:setF32(gc + 0xB4, eye[1])
  m:setF32(ctrl + 0x64, eye[3]); m:setF32(gc + 0xBC, eye[3])
  m:setF32(ctrl + 0x60, Native.ease(m:f32(ctrl + 0x60), goal,
    require("mods.STADIUM2_IMPORTER.lib.stadium2_native_memory").wordFloat(0x3E19999A)))
  m:setF32(gc + 0xB8, m:f32(ctrl + 0x60))
end

Native.JUMP_SHOTS = 0x84183930   -- D_84183930 (6): the eye jumps to the pose
Native.POSE_SHOTS = 0x84183944   -- D_84183944 (14): pose around the target

-- 8410B704(gc, actor, ctrl, center): move the eye toward the secondary pose
-- around `center`; height kept at 10 or more.
function Native:towardPose(gc, ctrl, center)
  local m = self.mem
  local Memory = require("mods.STADIUM2_IMPORTER.lib.stadium2_native_memory")
  local fraction
  if not self:inList(m:u16(ctrl + 0x98), Native.JUMP_SHOTS, 0xC) then
    m:setF32(ctrl + 0x44, Native.ease(m:f32(ctrl + 0x44), m:f32(ctrl + 0x4C), m:f32(ctrl + 0x48)))
    fraction = m:f32(ctrl + 0x44)
  end
  local goal = self:placeEye(center, m:f32(ctrl + 0x40), m:s16(ctrl + 0x3C), m:s16(ctrl + 0x3E))
  local from = m:vec(gc + 0xA8)
  local d, pitch, yaw = self:angleTo(from, goal)
  if fraction then d = f32(fraction * d) end
  m:setVec(gc + 0xA8, self:placeEye(from, d, pitch, yaw))
  if m:f32(gc + 0xAC) <= 10 then m:setF32(gc + 0xAC, 10) end
end

local function poseYaw(self, actor)
  local m = self.mem
  if self:inList(m:u8(actor + 0x61F), Native.KIND_FACING, 8) then return s16(self:sideFacing(actor)) end
  return m:s16(actor + 0x20)
end

-- 8410E688(gc, actor): the secondary pose around the GeoCamera target.
function Native:poseAroundTarget(gc, actor)
  local m = self.mem
  local ctrl = self:controllerFor(gc)
  m:setU32(Native.CURRENT, ctrl)
  if self:inList(m:u8(actor + 0x61F), Native.KIND_FACING, 8) and m:u8(actor + 0x61F) == 4 then
    self:follow(gc, actor)
  end
  local yaw = poseYaw(self, actor)
  self:secondaryPose(actor, ctrl, yaw)
  self:towardPose(gc, ctrl, m:vec(gc + 0xB4))
end

-- 8410E73C(gc, actor): the secondary pose around the look point (+0x50).
function Native:poseAroundLook(gc, actor)
  local m = self.mem
  local ctrl = self:controllerFor(gc)
  m:setU32(Native.CURRENT, ctrl)
  local yaw = poseYaw(self, actor)
  self:secondaryPose(actor, ctrl, yaw)
  self:towardPose(gc, ctrl, m:vec(ctrl + 0x50))
end

-- 8410E7D0(gc, actor): 8410E73C, skipped while the event code is 0x11 (the
-- defender dodged).
function Native:poseAroundLookUnlessDodged(gc, actor)
  local m = self.mem
  m:setU32(Native.CURRENT, self:controllerFor(gc))
  if m:u16(m:u32(Native.RECORD) + 4) == 0x11 then return end
  local yaw = poseYaw(self, actor)
  local ctrl = m:u32(Native.CURRENT)
  self:secondaryPose(actor, ctrl, yaw)
  self:towardPose(gc, ctrl, m:vec(ctrl + 0x50))
end

-- 84110B2C(gc, actor): the hit jolt (controller 0 only).
function Native:jolt(gc)
  local m = self.mem
  local Memory = require("mods.STADIUM2_IMPORTER.lib.stadium2_native_memory")
  local ctrl = self:controllerFor(gc)
  m:setU32(Native.CURRENT, ctrl)
  if m:u32(Native.CONTROLLER1) == ctrl then return end
  local _, _, yaw = self:angleTo(m:vec(gc + 0xA8), m:vec(gc + 0xB4))
  m:setU16(ctrl + 0x96, (m:s16(ctrl + 0x96) + 0x38E0) % 0x10000)
  m:setF32(ctrl + 0x8C, Native.ease(m:f32(ctrl + 0x8C), 0, Memory.wordFloat(0x3E23D70A)))
  local amount = f32(self:cos(m:u16(ctrl + 0x96)) * m:f32(ctrl + 0x8C))
  local third = f32(amount / 3)
  m:setF32(gc + 0xAC, f32(m:f32(gc + 0xAC) + third))
  m:setF32(gc + 0xB8, f32(m:f32(gc + 0xB8) + third))
  local sideways = self:sin((yaw + 0x4000) % 0x10000)
  m:setF32(gc + 0xA8, f32(m:f32(gc + 0xA8) + f32(amount * sideways)))
  m:setF32(gc + 0xB4, f32(m:f32(gc + 0xB4) + f32(amount * sideways)))
end

-- 84110718(gc, actor): program 0's per-tick handler.
function Native:program0Tick(gc, actor)
  local m = self.mem
  local Memory = require("mods.STADIUM2_IMPORTER.lib.stadium2_native_memory")
  local ctrl = self:controllerFor(gc)
  m:setU32(Native.CURRENT, ctrl)
  m:setF32(gc + 0x2C, Native.ease(m:f32(gc + 0x2C), m:f32(ctrl + 0x88), Memory.wordFloat(0x3D4CCCCD)))
  if not self:inList(m:u8(actor + 0x61F), Native.KIND_FACING, 8) then self:follow(gc, actor) end
  if self:inList(m:u16(m:u32(Native.CURRENT) + 0x98), Native.POSE_SHOTS, 0x1C) then
    self:poseAroundTarget(gc, actor)
  else
    self:poseAroundLook(gc, actor)
  end
  self:jolt(gc)
end

Native.HIT_POSE_SHOTS = 0x84183960 -- D_84183960 (8): the hit state poses these around the target

-- 84110F64(gc, actor): program 1's per-tick handler (the defender's hit
-- state). No FOV ease; the follow stops while the actor's volatile flags
-- (battle record +0x12) have bit 2.
function Native:program1Tick(gc, actor)
  local m = self.mem
  local record = m:u32(Native.RECORD) + self:side(actor) * 16
  if bit.band(m:u16(record + 0x12), 2) == 0 then self:follow(gc, actor) end
  if self:inList(m:u16(m:u32(Native.CURRENT) + 0x98), Native.HIT_POSE_SHOTS, 0x10) then
    self:poseAroundTarget(gc, actor)
  else
    self:poseAroundLookUnlessDodged(gc, actor)
  end
  self:jolt(gc)
end

-- ------------------------------------------------ attack programs 3, 5, 13, 17

-- An IEEE-754 double from its high and low words, in plain Lua (the game's
-- mod sandbox refuses the ffi library while the game runs; Lua numbers are
-- doubles, so this is exact).
Native.wordsToDouble = require("mods.STADIUM2_IMPORTER.lib.stadium2_native_memory").wordsToDouble

-- A big-endian double constant from the ROM.
function Native:const64(address)
  return Native.wordsToDouble(self.mem:u32(address), self.mem:u32(address + 4))
end

-- 84120CA4(gc, actor): like 84120BB4, but both actors are shown (8411EF08
-- sets bit 0 of +1) and the other actor is put back in its state family 0
-- (841125F4). That state change drives Stadium's battle flow, which the host
-- runs itself; it is not part of the camera and is not ported.
function Native:resetShotBothShown(gc, actor)
  local m = self.mem
  m:setU16(actor + 0x7EA, 0)
  m:setVec(gc + 0xC0, { 0, 1, 0 })
  for _, global in ipairs({ Native.PLAYER, Native.ENEMY }) do
    local a = m:u32(global)
    m:setU8(a + 1, bit.bor(m:u8(a + 1), 1))
  end
  if self.onActorReset then
    self.onActorReset(m:u32(Native.PLAYER))
    self.onActorReset(m:u32(Native.ENEMY))
  end
  self:setJolt(0)
end

-- 8410CC90(gc, actor, shot): hold the eye where it is: +0x44 = 0, FOV 45
-- now and as the goal, +0x68 = the eye. (The shot is not read; 8411E140 is
-- called for sideways kinds and its result is unused.)
function Native:holdEye(gc)
  local m = self.mem
  m:setU32(Native.CURRENT, self:controllerFor(gc))
  local ctrl = m:u32(Native.CURRENT)
  m:setF32(ctrl + 0x44, 0)
  m:setF32(gc + 0x2C, 45)
  m:setF32(ctrl + 0x88, 45)
  m:setVec(ctrl + 0x68, m:vec(gc + 0xA8))
end

-- 841105CC(gc, actor): program 5's setup (Fly).
function Native:program5Setup(gc, actor)
  local m = self.mem
  m:setU32(Native.CURRENT, self:controllerFor(gc))
  self:resetShotBothShown(gc, actor)
  self:holdEye(gc)
  m:setU32(m:u32(Native.CURRENT) + m:u32(Native.SLOT) * 8 + 8, m:u32(0x84184148))
end

-- 84110980(gc, actor): program 13's tick (Surf): FOV ease, then follow and
-- the pose around the target unless the actor's kind faces sideways.
function Native:program13Tick(gc, actor)
  local m = self.mem
  local Memory = require("mods.STADIUM2_IMPORTER.lib.stadium2_native_memory")
  m:setU32(Native.CURRENT, self:controllerFor(gc))
  local ctrl = m:u32(Native.CURRENT)
  m:setF32(gc + 0x2C, Native.ease(m:f32(gc + 0x2C), m:f32(ctrl + 0x88), Memory.wordFloat(0x3D4CCCCD)))
  if self:inList(m:u8(actor + 0x61F), Native.KIND_FACING, 8) then return end
  self:follow(gc, actor)
  self:poseAroundTarget(gc, actor)
end

-- 8410CF80(gc, actor): program 17's tick (Rapid Spin): the look height
-- (+0x60) eases to the marker point's height once the point is farther from
-- the look point than +0x80 x D_84188E50 (compared in double precision).
function Native:riseToMarker(gc, actor)
  local m = self.mem
  local Memory = require("mods.STADIUM2_IMPORTER.lib.stadium2_native_memory")
  m:setU32(Native.CURRENT, self:controllerFor(gc))
  local point = self:markerPoint(actor, m:u32(Native.CURRENT))
  local ctrl = m:u32(Native.CURRENT)
  local distance = self:angleTo(point, m:vec(ctrl + 0x50))
  if m:f32(ctrl + 0x80) * self:const64(0x84188E50) < distance then
    m:setF32(ctrl + 0x60, Native.ease(m:f32(ctrl + 0x60), point[2], Memory.wordFloat(0x3E99999A)))
  end
  m:setF32(gc + 0xB8, m:f32(ctrl + 0x60))
end

-- 84111048(gc, actor): program 3's setup (Waterfall): 84120BB4, the actor's
-- home pose (8411EFE4, options.onActorHome), the controller's shot, then
-- empty its own slot.
function Native:program3Setup(gc, actor)
  local m = self.mem
  m:setU32(Native.CURRENT, self:controllerFor(gc))
  self:resetShot(gc, actor)
  if self.onActorHome then self.onActorHome(actor) end
  self:shot(gc, actor, m:s16(m:u32(Native.CURRENT) + 0x98))
  m:setU32(m:u32(Native.CURRENT) + m:u32(Native.SLOT) * 8 + 8, m:u32(0x84184148))
end

-- 841110C4(gc, actor): program 3's tick: FOV 45, then 8410CF80.
function Native:program3Tick(gc, actor)
  self.mem:setF32(gc + 0x2C, 45)
  self:riseToMarker(gc, actor)
end

-- 8410D040(gc): program 3's third handler: the eye rises toward the target
-- height while it is below it.
function Native:eyeRise(gc)
  local m = self.mem
  local Memory = require("mods.STADIUM2_IMPORTER.lib.stadium2_native_memory")
  if m:f32(gc + 0xB8) <= m:f32(gc + 0xAC) then return end
  m:setF32(gc + 0xAC, Native.ease(m:f32(gc + 0xAC), m:f32(gc + 0xB8), Memory.wordFloat(0x3CA3D70A)))
end

-- ------------------------------------------------ program 10 (turn start)

Native.ORBIT_SHOTS = 0x841844D0 -- D_841844D0: 0x1C-byte pose rows by shot
Native.TURN_SHOTS = 0x84183C60  -- D_84183C60 (5): the turn-start shots

-- 84120AC4(gc, actor): the reset for program 10: like 84120CA4 (both actors
-- shown, 84120700 on both), and an actor whose record flags (+0x12 / +0x22)
-- have bit 3 gets its scale (+0x30) set to D_84189C58 / D_84189C60.
function Native:resetShotScaled(gc, actor, playerScale, enemyScale)
  local m = self.mem
  m:setU16(actor + 0x7EA, 0)
  m:setVec(gc + 0xC0, { 0, 1, 0 })
  for _, global in ipairs({ Native.PLAYER, Native.ENEMY }) do
    local a = m:u32(global)
    m:setU8(a + 1, bit.bor(m:u8(a + 1), 1))
  end
  if self.onActorReset then
    self.onActorReset(m:u32(Native.PLAYER))
    self.onActorReset(m:u32(Native.ENEMY))
  end
  local record = m:u32(Native.RECORD)
  for i, global in ipairs({ Native.PLAYER, Native.ENEMY }) do
    if bit.band(m:u16(record + 0x12 + (i - 1) * 16), 8) ~= 0 then
      local s = m:f32(i == 1 and (playerScale or 0x84189C58) or (enemyScale or 0x84189C60))
      m:setVec(m:u32(global) + 0x30, { s, s, s })
    end
  end
  self:setJolt(0)
end

-- 8410EA58(gc, actor, shot): place the eye on the shot's orbit pose around
-- (0, 40, 0): pitch / yaw (+0x90 / +0x92), distance row +4 x 50 (+0x74),
-- FOV row +0x10 now and as the goal; +0x44 = 0.
function Native:orbitSetup(gc, actor, shot)
  local m = self.mem
  m:setU32(Native.CURRENT, self:controllerFor(gc))
  self:resetShotScaled(gc, actor)
  local ctrl = m:u32(Native.CURRENT)
  local row = Native.ORBIT_SHOTS + shot * 0x1C
  m:setF32(ctrl + 0x44, 0)
  m:setU16(ctrl + 0x90, m:u16(row))
  m:setU16(ctrl + 0x92, m:u16(row + 2))
  m:setF32(ctrl + 0x74, f32(m:f32(row + 4) * 50))
  local fov = m:f32(row + 0x10)
  m:setF32(ctrl + 0x88, fov)
  m:setF32(gc + 0x2C, fov)
  m:setVec(gc + 0xB4, { 0, 40, 0 })
  m:setVec(gc + 0xA8, self:placeEye(m:vec(gc + 0xB4), m:f32(ctrl + 0x74), m:s16(ctrl + 0x90), m:s16(ctrl + 0x92)))
end

-- 841111D8(gc, actor): program 10's setup: 8410EA58 with the controller's
-- shot, then empty its own slot.
function Native:program10Setup(gc, actor)
  local m = self.mem
  m:setU32(Native.CURRENT, self:controllerFor(gc))
  self:orbitSetup(gc, actor, m:s16(m:u32(Native.CURRENT) + 0x98))
  m:setU32(m:u32(Native.CURRENT) + m:u32(Native.SLOT) * 8 + 8, m:u32(0x84184148))
end

-- 8410EB50(gc, actor): ease the eye toward the shot's second orbit pose
-- (row +8 pitch, +0xA yaw, +0xC x 50 distance; fraction +0x44 eased to
-- row +0x14 at rate row +0x18). Returns the distance still to go. The rates
-- are scaled by D_84188F68 / D_84188F6C only on PAL (80001FF0 == 50); the
-- supported US ROM runs on NTSC, so they are used as they are.
function Native:orbitTick(gc)
  local m = self.mem
  m:setU32(Native.CURRENT, self:controllerFor(gc))
  local ctrl = m:u32(Native.CURRENT)
  local row = Native.ORBIT_SHOTS + m:s16(ctrl + 0x98) * 0x1C
  m:setU16(ctrl + 0x3C, m:u16(row + 8))
  m:setU16(ctrl + 0x3E, m:u16(row + 0xA))
  m:setF32(ctrl + 0x40, f32(m:f32(row + 0xC) * 50))
  m:setF32(ctrl + 0x4C, m:f32(row + 0x14))
  m:setF32(ctrl + 0x48, m:f32(row + 0x18))
  m:setF32(ctrl + 0x44, Native.ease(m:f32(ctrl + 0x44), m:f32(ctrl + 0x4C), m:f32(ctrl + 0x48)))
  local goal = self:placeEye(m:vec(gc + 0xB4), m:f32(ctrl + 0x40), m:s16(ctrl + 0x3C), m:s16(ctrl + 0x3E))
  local from = m:vec(gc + 0xA8)
  local d, pitch, yaw = self:angleTo(from, goal)
  m:setVec(gc + 0xA8, self:placeEye(from, f32(m:f32(ctrl + 0x44) * d), s16(pitch), s16(yaw)))
  return d
end

-- 8410ED30(gc, actor): program 10's tick: 8410EB50; once the eye is within
-- 1.75, the event timer is released (8411FEE8(0), options.onEventTimer) and
-- the handler empties its own slot.
function Native:program10Tick(gc, actor)
  local m = self.mem
  if self:orbitTick(gc) <= 1.75 then
    self:setTimer(0)
    m:setU32(m:u32(Native.CURRENT) + m:u32(Native.SLOT) * 8 + 8, m:u32(0x84184148))
  end
end

-- 8411F94C(side, code), camera part (event 0x5A, queued once a turn by the
-- battle loop 841347A0 after both sides chose): a random turn shot of
-- D_84183C60 and program 10 on the side's actor (the event's side is 0, the
-- player). Its other calls put both actors in state family 0 and set the
-- event timer: battle flow, not the camera.
function Native:turnStart(actor)
  local m = self.mem
  m:setU16(m:u32(Native.CONTROLLER0) + 0x98, m:u16(Native.TURN_SHOTS + (self:drawRandom() % 5) * 2))
  self:setProgram(actor, 10)
end

-- ------------------------------------------------ program 18 (the first mover)

-- 8411F9D8(side), camera part (event 0x5B, family 27). 841343FC, the turn
-- body that 841347A0 runs right after queuing 0x5A, queues it on the side
-- that acts first (841320E8's order) before that side's action (84133F10).
-- The timer is 0x12C, record +1 bit 0 is set (84112564), controller 0's
-- shot is 0 and the side's actor gets program 18. Family 27's states
-- (Dispatch_190, Dispatch_002) only play the model's idle animation and
-- hide a Pokemon underground or without HP: not the camera.
function Native:firstMoverState(actor)
  local m = self.mem
  self:setTimer(0x12C)
  local record = m:u32(Native.RECORD)
  m:setU8(record + 1, bit.bor(m:u8(record + 1), 1))
  m:setU16(m:u32(Native.CONTROLLER0) + 0x98, 0)
  self:setProgram(actor, 0x12)
end

-- 8410F1A8(gc, actor) (US asm): program 18's setup. Shot 0x26 when the
-- side's record +0x10 is 0x20, else 0x24; the look point and target (+0x50,
-- +0x5C) at the actor's offset +0x634 turned by its facing (8410B8FC) plus
-- its position, at height +0x638, or at the marker point's height (8411E0A4)
-- while the side's flags have bit 1; height 30 for both when the flags have
-- bit 2 or the actor's +0x7F4 has 0x10. +0x74 / +0x7C / +0x80 / +0x84 from
-- the actor's +0x64C / +0x654 / +0x640 / +0x644, +0x78 = 0, the fraction
-- +0x44 and its rate +0x48 = 0, +0x68 = the eye, FOV goal 80, stage (+0xA2)
-- and counter (+0x94) 0; the slot empties.
function Native:program18Setup(gc, actor)
  local m = self.mem
  local ctrl = self:controllerFor(gc)
  m:setU32(Native.CURRENT, ctrl)
  m:setU16(ctrl + 0x94, 0)
  m:setU16(ctrl + 0xA2, 0)
  local record = m:u32(Native.RECORD) + self:side(actor) * 16
  m:setU16(ctrl + 0x98, m:u16(record + 0x10) == 0x20 and 0x26 or 0x24)
  m:setF32(ctrl + 0x44, 0)
  m:setF32(ctrl + 0x48, 0)
  m:setF32(ctrl + 0x84, m:f32(actor + 0x644))
  m:setF32(ctrl + 0x80, m:f32(actor + 0x640))
  m:setF32(ctrl + 0x7C, m:f32(actor + 0x654))
  m:setF32(ctrl + 0x74, m:f32(actor + 0x64C))
  m:setF32(ctrl + 0x78, 0)
  local x, z = self:rotateOffset(m:vec(actor + 0x634), m:s16(actor + 0x20))
  x, z = f32(x + m:f32(actor + 0x24)), f32(z + m:f32(actor + 0x2C))
  local y = m:f32(actor + 0x638)
  m:setVec(ctrl + 0x5C, { x, y, z })
  m:setVec(ctrl + 0x50, { x, y, z })
  local flags = m:u16(record + 0x12)
  if bit.band(flags, 2) ~= 0 then
    y = self:markerPoint(actor, ctrl)[2]
    m:setVec(ctrl + 0x5C, { x, y, z })
    m:setVec(ctrl + 0x50, { x, y, z })
  end
  if bit.band(flags, 4) ~= 0 or bit.band(m:u16(actor + 0x7F4), 0x10) ~= 0 then
    m:setF32(ctrl + 0x60, 30)
    m:setF32(ctrl + 0x54, 30)
  end
  m:setVec(ctrl + 0x68, m:vec(gc + 0xA8))
  m:setU32(ctrl + m:u32(Native.SLOT) * 8 + 8, m:u32(0x84184148))
  m:setF32(ctrl + 0x88, 80)
end

-- 8410F3E8(gc, actor) (US asm): program 18's tick. Stage 0: the FOV eases
-- to the goal at 0.02; the fraction +0x44 eases to +0x4C at +0x48; the
-- target (+0xB4) moves that fraction of the way to the look point; the
-- shot row's secondary pose on the actor's facing (8410B884), with the
-- distance scaled by D_84188F8C and the yaw 0x1555 on the facing's side
-- while the side's flags have bit 1; the eye moves the fraction of the way
-- to that pose around the look point, and within 1.75 of it the stage
-- becomes 1. The rate is scaled by D_84188F88 only on PAL (80001FF0 == 50);
-- the US ROM runs on NTSC. Stage 1: 20 frames later the timer ends and the
-- slot empties.
function Native:program18Tick(gc, actor)
  local m = self.mem
  m:setU32(Native.CURRENT, self:controllerFor(gc))
  local ctrl = m:u32(Native.CURRENT)
  local stage = m:s16(ctrl + 0xA2)
  if stage == 0 then
    m:setF32(gc + 0x2C, Native.ease(m:f32(gc + 0x2C), m:f32(ctrl + 0x88), f32(0.02)))
    local yaw = m:s16(actor + 0x20)
    local sign = yaw < 0 and -1 or 1
    m:setF32(ctrl + 0x44, Native.ease(m:f32(ctrl + 0x44), m:f32(ctrl + 0x4C), m:f32(ctrl + 0x48)))
    local target = m:vec(gc + 0xB4)
    local d, pitch, turn = self:angleTo(target, m:vec(ctrl + 0x50))
    m:setVec(gc + 0xB4, self:placeEye(target, f32(m:f32(ctrl + 0x44) * d), pitch, turn))
    self:secondaryPose(actor, ctrl, yaw)
    local flags = m:u16(m:u32(Native.RECORD) + self:side(actor) * 16 + 0x12)
    if bit.band(flags, 2) ~= 0 then
      m:setF32(ctrl + 0x40, f32(m:f32(ctrl + 0x40) * self:const(0x84188F8C)))
      m:setU16(ctrl + 0x3E, (sign * 0x1555) % 0x10000)
    end
    local goal = self:placeEye(m:vec(ctrl + 0x50), m:f32(ctrl + 0x40), m:s16(ctrl + 0x3C), m:s16(ctrl + 0x3E))
    local from = m:vec(gc + 0xA8)
    d, pitch, turn = self:angleTo(from, goal)
    m:setVec(gc + 0xA8, self:placeEye(from, f32(m:f32(ctrl + 0x44) * d), pitch, turn))
    if d <= 1.75 then m:setU16(ctrl + 0xA2, 1) end
    m:setU16(ctrl + 0x94, 0)
  elseif stage == 1 then
    local count = m:s16(ctrl + 0x94) + 1
    m:setU16(ctrl + 0x94, count % 0x10000)
    if count == 20 then
      self:setTimer(0)
      m:setU32(ctrl + m:u32(Native.SLOT) * 8 + 8, m:u32(0x84184148))
    end
  end
end

-- ------------------------------------------------ program 11 (faint)

Native.FAINT_SHOTS = 0x84183C74       -- D_84183C74 (3): the faint shots
Native.FAINT_FRAME_EXEMPT = 0x84183988 -- D_84183988 (28 species): no reframe

-- 8410D174's bands, first match wins: {T, F, bonus}: slack * T < distance
-- -> target at distance * F (+ 2 for species 0xA1 where bonus is set). T = 1
-- compares the slack itself; below every band the factor is D_84188E60.
local FAINT_BANDS = {
  { 1, 0x84188E5C, true }, { 0x84188E60, 0x84188E64, true },
  { 0x84188E68, 0x84188E6C, true }, { 0x84188E70, 0.5, true },
  { 0x84188E74, 0x84188E74, true }, { 0.5, 0x84188E70, true },
  { 0x84188E78, 0x84188E68, false }, { 0x84188E7C, 0x84188E60, false },
  { 0x84188E80, 0x84188E60, false },
}

-- 8410D174(gc, actor): frame the fainting actor: the target (+0xB4, all
-- three axes) moves toward its marker point by the distance bands.
function Native:faintFrame(gc, actor)
  local m = self.mem
  m:setU32(Native.CURRENT, self:controllerFor(gc))
  local ctrl = m:u32(Native.CURRENT)
  local point
  if m:s16(actor + 0x7EA) == 1 then point = self:markerPoint(actor, ctrl)
  else point = m:vec(ctrl + 0x50) end
  m:setU16(actor + 0x7EA, 1)
  local d, pitch, yaw = self:angleTo(point, m:vec(gc + 0xB4))
  if self:inList(m:u16(actor + 0x1A), Native.FAINT_FRAME_EXEMPT, 0x38) then return end
  local bonus = m:s16(actor + 0x1A) == 0xA1 and 2 or 0
  local slack = m:f32(ctrl + 0x80)
  local distance = f32(d * self:const(0x84188E60))
  for _, band in ipairs(FAINT_BANDS) do
    local limit = band[1] == 1 and slack or f32(slack * self:value(band[1]))
    if limit < d then
      distance = f32(d * self:value(band[2]))
      if band[3] then distance = f32(distance + bonus) end
      break
    end
  end
  m:setVec(gc + 0xB4, self:placeEye(point, distance, pitch, yaw))
end

-- 8410B60C(gc, actor, ctrl, center): like 8410B704, but the fraction (+0x44)
-- eases to 0.15 at 0.03 and the pose distance is +0x40 x D_84188E30.
function Native:towardPoseSlow(gc, ctrl, center)
  local m = self.mem
  local Memory = require("mods.STADIUM2_IMPORTER.lib.stadium2_native_memory")
  m:setF32(ctrl + 0x44, Native.ease(m:f32(ctrl + 0x44), Memory.wordFloat(0x3E19999A), Memory.wordFloat(0x3CF5C28F)))
  local goal = self:placeEye(center, f32(m:f32(ctrl + 0x40) * self:const(0x84188E30)),
    m:s16(ctrl + 0x3C), m:s16(ctrl + 0x3E))
  local from = m:vec(gc + 0xA8)
  local d, pitch, yaw = self:angleTo(from, goal)
  m:setVec(gc + 0xA8, self:placeEye(from, f32(m:f32(ctrl + 0x44) * d), pitch, yaw))
  if m:f32(gc + 0xAC) <= 10 then m:setF32(gc + 0xAC, 10) end
end

-- 84120C20(gc, actor): the reset for program 11: the actor at its home pose
-- (8411EFE4, options.onActorHome), scale 1, shown (8411EF2C), +0x1C = 0.
function Native:resetShotHome(gc, actor)
  local m = self.mem
  m:setU16(actor + 0x7EA, 0)
  m:setVec(gc + 0xC0, { 0, 1, 0 })
  if self.onActorHome then self.onActorHome(actor) end
  m:setVec(actor + 0x30, { 1, 1, 1 })
  if self.onStatusVisibility then self.onStatusVisibility(actor) end
  m:setU8(actor + 0x1C, 0)
  self:setJolt(0)
end

-- 84110408(gc, actor): program 11's setup: 84120C20, 8410CAE4 with the
-- controller's shot, then empty its own slot.
function Native:program11Setup(gc, actor)
  local m = self.mem
  m:setU32(Native.CURRENT, self:controllerFor(gc))
  self:resetShotHome(gc, actor)
  self:shotB(gc, actor, m:s16(m:u32(Native.CURRENT) + 0x98))
  m:setU32(m:u32(Native.CURRENT) + m:u32(Native.SLOT) * 8 + 8, m:u32(0x84184148))
end

-- 841107D8(gc, actor): program 11's tick: FOV ease, 8410D174, the secondary
-- pose at the actor's own facing, then 8410B60C around the target.
function Native:program11Tick(gc, actor)
  local m = self.mem
  local Memory = require("mods.STADIUM2_IMPORTER.lib.stadium2_native_memory")
  m:setU32(Native.CURRENT, self:controllerFor(gc))
  local ctrl = m:u32(Native.CURRENT)
  m:setF32(gc + 0x2C, Native.ease(m:f32(gc + 0x2C), m:f32(ctrl + 0x88), Memory.wordFloat(0x3D4CCCCD)))
  self:faintFrame(gc, actor)
  ctrl = m:u32(Native.CURRENT)
  self:secondaryPose(actor, ctrl, m:s16(actor + 0x20))
  self:towardPoseSlow(gc, ctrl, m:vec(gc + 0xB4))
end

-- 8411A544(actor), camera part (the faint state, family 5, event 0x1C):
-- +0x7F4 = 0; 8411A3D4 picks a faint shot of D_84183C74 unless +0x7EC bit
-- 0 is set; program 11 on the actor unless the shot is 0x21; +0x7EA = 0.
-- (8411A3D4 also copies three dispatch-row bytes for the model animation
-- layer; not ported here.)
function Native:faintState(actor)
  local m = self.mem
  m:setU16(actor + 0x7F4, 0)
  local ctrl = m:u32(Native.CONTROLLER0)
  if bit.band(m:u16(actor + 0x7EC), 1) == 0 then
    m:setU16(ctrl + 0x98, m:u16(Native.FAINT_SHOTS + (self:drawRandom() % 3) * 2))
  end
  if m:s16(ctrl + 0x98) ~= 0x21 then self:setProgram(actor, 11) end
  m:setU16(actor + 0x7EA, 0)
end

-- ------------------------------------------------ status and residual (family 9)

-- 84118C08's event-code table (jtbl_8418911C, codes 0x3C..0x59; code 6
-- also sets shot 0): shot 0, a new shot of selector 0x28 different from
-- the current one, or the shot kept.
local RESIDUAL_SHOT = {}
for _, c in ipairs({ 0x3C, 0x3D, 0x49, 0x55, 0x57, 0x58, 0x59 }) do RESIDUAL_SHOT[c] = "zero" end
for c = 0x3E, 0x56 do RESIDUAL_SHOT[c] = RESIDUAL_SHOT[c] or "reroll" end
RESIDUAL_SHOT[0x47], RESIDUAL_SHOT[0x4B] = "keep", "keep"
Native.RESIDUAL_SHOT = RESIDUAL_SHOT

-- 84118C08(actor), camera part (family 9, events 0x06 and 0x3C-0x59:
-- poison, burn, Leech Seed, stat changes, healing...): the shot by event
-- code, then program 0 on the actor. Skipped while +0x7F6 is 1.
function Native:residualState(actor)
  local m = self.mem
  if m:s8(actor + 0x7F6) == 1 then return end
  local ctrl = m:u32(Native.CONTROLLER0)
  local code = m:u16(m:u32(Native.RECORD) + 4)
  local rule = code == 6 and "zero" or (code >= 0x3C and code <= 0x59 and RESIDUAL_SHOT[code]) or "keep"
  if rule == "zero" then
    m:setU16(ctrl + 0x98, 0)
  elseif rule == "reroll" then
    local old = m:s16(ctrl + 0x98)
    repeat
      self:chooseShot(ctrl, 0x28)
      ctrl = m:u32(Native.CONTROLLER0)
    until m:s16(ctrl + 0x98) ~= old
  end
  self:setProgram(actor, 0)
end

-- ------------------------------------------------ turn check (family 17)

-- 84119CF0(actor), camera part (family 17: events 2-9 and 0x2C, the turn
-- check's frozen solid / fast asleep / defrosted and 84124594's reactions
-- (recharge, flinch, disabled...), and 84124BA0's 7-9): shot 0, program 0
-- on the actor, kind 0xFF; then event 7 takes shot 0x25 when the actor's
-- flags (record +0x12) have bit 1 (else 0x24), 8 shot 0x24, 9 shot 0x26.
function Native:turnCheckState(actor)
  local m = self.mem
  m:setU16(m:u32(Native.CONTROLLER0) + 0x98, 0)
  self:setProgram(actor, 0)
  m:setU8(actor + 0x61F, 0xFF)
  local code = m:u16(m:u32(Native.RECORD) + 4)
  local ctrl = m:u32(Native.CONTROLLER0)
  if code == 7 then
    local flags = m:u16(m:u32(Native.RECORD) + self:side(actor) * 16 + 0x12)
    m:setU16(ctrl + 0x98, bit.band(flags, 2) ~= 0 and 0x25 or 0x24)
  elseif code == 8 then
    m:setU16(ctrl + 0x98, 0x24)
  elseif code == 9 then
    m:setU16(ctrl + 0x98, 0x26)
  end
end

-- ------------------------------------------------ woke up / confused (families 19, 20)

-- 8410E8E4(gc, actor): program 7, one handler that runs every frame (its
-- slot is never emptied): 84120BB4, FOV 80, the target at the actor's
-- position plus its species offset (+0x678 -> D_84193DF8 + side * 0x20,
-- archive 0x49B780 + 0, 0x20 bytes per species) turned by the actor's
-- yaw (x and z mirrored by 8411E1D4's side sign), and the eye at the offset's
-- distance (+0xC), pitch (+0x10) and signed yaw (+0x12) from it (800371B4).
function Native:program7Tick(gc, actor)
  local m = self.mem
  self:resetShot(gc, actor)
  m:setF32(gc + 0x2C, 80)
  local d = m:u32(actor + 0x678)
  local y = f32(m:f32(actor + 0x28) + m:f32(d + 4))
  local sign = actor == m:u32(Native.PLAYER) and 1 or -1
  local yaw = m:u16(actor + 0x20)
  local sin, cos = self:sin(yaw), self:cos(yaw)
  local d0, d8 = m:f32(d), m:f32(d + 8)
  local x = f32(f32(m:f32(actor + 0x24) + f32(f32(d0 * sign) * cos)) - f32(sin * d8))
  local z = f32(f32(cos * d8) + f32(m:f32(actor + 0x2C) + f32(f32(d0 * sign) * sin)))
  m:setVec(gc + 0xB4, { x, y, z })
  local turn = s16((sign * m:s16(d + 0x12)) % 0x10000)
  m:setVec(gc + 0xA8, self:placeEye(m:vec(gc + 0xB4), m:f32(d + 0xC), m:s16(d + 0x10), turn))
end

-- 84119908(actor), camera part (family 19: event 0x1D, woke up): the frame
-- counter and substate 0, the timer 0x258; when the side's flags (record
-- +0x12) have bit 2 (underground), shot 0 and program 0, +0x7F4 loses bits
-- 0 and 6, substate 4 and record +1 bits 0 and 2 (84112564 / 84112580);
-- otherwise program 7. (84111C44, the FX queue, and the model animation
-- calls are not the camera's.)
function Native:wakeState(actor)
  local m = self.mem
  local record = m:u32(Native.RECORD)
  m:setU16(actor + 0x7E8, 0)
  m:setU8(actor + 0x7F6, 0)
  self:setTimer(0x258)
  local flags = m:u16(record + self:side(actor) * 16 + 0x12)
  if bit.band(flags, 4) ~= 0 then
    m:setU16(m:u32(Native.CONTROLLER0) + 0x98, 0)
    self:setProgram(actor, 0)
    m:setU16(actor + 0x7F4, bit.band(m:u16(actor + 0x7F4), 0xFFBE))
    m:setU8(actor + 0x7F6, 4)
    m:setU8(record + 1, bit.bor(m:u8(record + 1), 5))
  else
    self:setProgram(actor, 7)
  end
end

-- 84119AB4(actor) (US asm), the wake-up's tail, on the actor's frame
-- counter: 0: at frame 0x14 +0x7F4 loses bits 0 and 6 (1); 1: once the
-- model's wake animation has finished (8003EC34, or 84111FA4 when
-- 84111C8C picks no wake clip; `finished`), frame 0, record +1 bits 0 and
-- 2 (2); 2: at frame 0x1E, 84111BEC (the counter 0, the timer 0, the kind
-- reset) (3); 4 (underground): at frame 0x3C, 84111BEC (5). Returns the
-- next substate; 3 and 5 are the end.
function Native:wakeFrame(actor, substate, finished)
  local m = self.mem
  local frame = m:s16(actor + 0x7E8)
  local function finish(next)
    m:setU16(actor + 0x7E8, 0)
    self:setTimer(0)
    self:kindReset(actor)
    m:setU8(actor + 0x7F6, next)
    return next
  end
  if substate == 0 then
    if frame ~= 0x14 then return 0 end
    m:setU16(actor + 0x7F4, bit.band(m:u16(actor + 0x7F4), 0xFFBE))
    m:setU8(actor + 0x7F6, 1)
    return 1
  elseif substate == 1 then
    if not finished then return 1 end
    local record = m:u32(Native.RECORD)
    m:setU16(actor + 0x7E8, 0)
    m:setU8(actor + 0x7F6, 2)
    m:setU8(record + 1, bit.bor(m:u8(record + 1), 5))
    return 2
  elseif substate == 2 then
    if frame ~= 0x1E then return 2 end
    return finish(3)
  elseif substate == 4 then
    if frame ~= 0x3C then return 4 end
    return finish(5)
  end
  return substate
end

-- BattleAnim_Dispatch_142 (8411A19C, fork C), camera part (family 20:
-- event 0x26, confused), once 84113430 lets it run: shot 0x24 when the
-- side's flags have bit 1, else 0, and program 0 on the actor.
function Native:confusedState(actor)
  local m = self.mem
  local flags = m:u16(m:u32(Native.RECORD) + self:side(actor) * 16 + 0x12)
  m:setU16(m:u32(Native.CONTROLLER0) + 0x98, bit.band(flags, 2) ~= 0 and 0x24 or 0)
  self:setProgram(actor, 0)
end

-- 841206D0(actor), camera part (fork C): the actor's kind back to 0xFF.
-- (It also clears model flags: +2 bit 1 and +0x2D9 bit 0 of both parts.)
function Native:kindReset(actor)
  self.mem:setU8(actor + 0x61F, 0xFF)
end

-- ------------------------------------------------ Dig (family 15), Substitute (family 11)

-- 84115E28(actor), camera part (Dig's second state, once 84113430 lets it
-- run): 84115D4C (unless +0x7EC bit 0: shot 0x0E and kind 0xFF; its
-- 841146D4 dispatch row is the model's), then program 6 unless the shot is
-- 0x21.
function Native:digState(actor)
  local m = self.mem
  if bit.band(m:u16(actor + 0x7EC), 1) == 0 then
    m:setU16(m:u32(Native.CONTROLLER0) + 0x98, 0x0E)
    m:setU8(actor + 0x61F, 0xFF)
  end
  if m:s16(m:u32(Native.CONTROLLER0) + 0x98) ~= 0x21 then self:setProgram(actor, 6) end
end

-- 84120D34(gc, actor) (fork C): program 6's reset: both actors home
-- (8411EFE4) and shown (8411EF08), 84120700 on both, the up vector, and
-- unless the actor is Diglett or Dugtrio (+0x1A 0x32 / 0x33) it is hidden
-- (+1 bit 0 clear) at height 30; the jolt ends. (841125F4 puts the other
-- actor in state family 0: Stadium's battle flow, not the camera's.)
function Native:resetShotDig(gc, actor)
  local m = self.mem
  m:setU16(actor + 0x7EA, 0)
  if self.onActorHome then
    self.onActorHome(m:u32(Native.PLAYER))
    self.onActorHome(m:u32(Native.ENEMY))
  end
  for _, global in ipairs({ Native.PLAYER, Native.ENEMY }) do
    local a = m:u32(global)
    m:setU8(a + 1, bit.bor(m:u8(a + 1), 1))
  end
  if self.onActorReset then
    self.onActorReset(m:u32(Native.PLAYER))
    self.onActorReset(m:u32(Native.ENEMY))
  end
  m:setVec(gc + 0xC0, { 0, 1, 0 })
  local species = m:s16(actor + 0x1A)
  if species ~= 0x32 and species ~= 0x33 then
    m:setU8(actor + 1, bit.band(m:u8(actor + 1), 0xFE))
    m:setF32(actor + 0x28, 30)
  end
  self:setJolt(0)
end

-- 84110640(gc, actor): program 6's setup: 84120D34, 8410CC90 (hold the
-- eye), then empty its own slot.
function Native:program6Setup(gc, actor)
  local m = self.mem
  m:setU32(Native.CURRENT, self:controllerFor(gc))
  self:resetShotDig(gc, actor)
  self:holdEye(gc)
  m:setU32(m:u32(Native.CURRENT) + m:u32(Native.SLOT) * 8 + 8, m:u32(0x84184148))
end

-- 841111B0(gc, actor): program 6's tick: FOV 45, then 8410E73C.
function Native:program6Tick(gc, actor)
  self.mem:setF32(gc + 0x2C, 45)
  self:poseAroundLook(gc, actor)
end

-- BattleAnim_Dispatch_079 (8411B304, fork C), camera part (Substitute's
-- second state, once 84113430 lets it run): 841119CC with the move's attack
-- selector (D_841849B6[+0x618 * 8]; Dispatch_078 set +0x618 = 0xA4), then
-- program 0 whatever the shot.
function Native:substituteState(actor)
  local m = self.mem
  self:chooseShot(m:u32(Native.CONTROLLER0), m:u16(Native.MOVE_SHOTS + m:u8(actor + 0x618) * 8))
  self:setProgram(actor, 0)
end

-- 8411B3B8(actor) substate 2, camera part (a tick after its frame 0x1E):
-- after 84112B64 (the doll swap, the controller's) the actor's home pose
-- (8411EFE4), shot 0, program 0 and +0x7EA = 0.
function Native:substituteDollState(actor)
  local m = self.mem
  if self.onActorHome then self.onActorHome(actor) end
  m:setU16(m:u32(Native.CONTROLLER0) + 0x98, 0)
  self:setProgram(actor, 0)
  m:setU16(actor + 0x7EA, 0)
end

-- ------------------------------------------------ Transform (family 13), Beat Up (family 22)

-- 8411B070(actor) (fork C), camera part (Transform's second state, once
-- 84113430 lets it run): 8411AF6C (unless +0x7EC bit 0: shot 0 and kind
-- 0xFF; its dispatch-row copies are the model's), 841119CC with the move's
-- attack selector (+0x618, the record's move, from Dispatch_092), program 0.
-- Its later substates (8411B160's FOV goal 60 on shot 4, 8411AEA8's shot 0
-- and program 0 after the model swap, the kind reset at frame 0x28) wait on
-- the model animation and are not ported.
function Native:transformState(actor)
  local m = self.mem
  if bit.band(m:u16(actor + 0x7EC), 1) == 0 then
    m:setU16(m:u32(Native.CONTROLLER0) + 0x98, 0)
    -- 8411AF6C's copy of the move's motion row (this actor only)
    local at = m:u32(actor + 0x2D4) + (m:u8(actor + 0x618) - 1) * 0x14
    local function b(i) return m:u8(at + i) end
    m:setU8(actor + 0x616, b(0)); m:setU8(actor + 0x61F, 0xFF)
    m:setU8(actor + 0x617, b(1)); m:setU8(actor + 0x619, b(0xB))
    m:setU8(actor + 0x61A, b(0xA)); m:setU8(actor + 0x61B, b(6))
    m:setU8(actor + 0x620, b(9)); m:setU8(actor + 0x61C, b(2)); m:setU8(actor + 0x61D, b(3))
    m:setU16(actor + 0x628, b(0xC)); m:setU16(actor + 0x62A, b(0xD)); m:setU16(actor + 0x62C, b(0xE))
    m:setU8(actor + 0x661, b(0xF))
  end
  self:chooseShot(m:u32(Native.CONTROLLER0), m:u16(Native.MOVE_SHOTS + m:u8(actor + 0x618) * 8))
  self:setProgram(actor, 0)
  -- the frame counter from +0x61B (less one when +0x61A is 0), timer 500
  local start = m:u8(actor + 0x61B)
  if m:u8(actor + 0x61A) == 0 then start = start - 1 end
  m:setU16(actor + 0x7E8, start % 0x10000)
  self:setTimer(500)
end

-- 8411B1F4(actor)'s substates, camera part, on the actor's frame counter:
-- 1 (8411B160): at frame +0x619 the FOV goal 60 on shot 4 (2). 2 (8411AE08):
-- the display model changes (3). 3 (8411AEA8): once the new model is loaded
-- (`modelReady`, 800427B8), the row's +0xC..+0xF again, shot 0 and program 0
-- (frame 0, 4). 4: at frame 0x28 the kind resets and the timer ends (5).
function Native:transformFrame(actor, substate, modelReady)
  local m = self.mem
  local ctrl = m:u32(Native.CONTROLLER0)
  if substate == 1 then
    if m:u8(actor + 0x619) == m:s16(actor + 0x7E8) then
      if m:s16(ctrl + 0x98) == 4 then m:setF32(ctrl + 0x88, 60) end
      return 2
    end
    return 1
  elseif substate == 2 then
    return 3
  elseif substate == 3 then
    if not modelReady then return 3 end
    local at = m:u32(actor + 0x2D4) + (m:u8(actor + 0x618) - 1) * 0x14
    m:setU16(actor + 0x628, m:u8(at + 0xC)); m:setU16(actor + 0x62A, m:u8(at + 0xD))
    m:setU16(actor + 0x62C, m:u8(at + 0xE)); m:setU8(actor + 0x661, m:u8(at + 0xF))
    m:setU16(actor + 0x7E8, 0)
    m:setU16(ctrl + 0x98, 0)
    self:setProgram(actor, 0)
    return 4
  elseif substate == 4 then
    if m:s16(actor + 0x7E8) == 0x28 then
      self:kindReset(actor)
      self:setTimer(0)
      return 5
    end
    return 4
  end
  return substate
end

-- BattleAnim_Dispatch_156 (84116548, fork C), camera part (Beat Up's second
-- state, once the model is ready, 800427B8): 841119CC with the move's attack
-- selector, program 0. 84116808's per-hit substates (841166C4: FOV goal 60
-- on shot 4, the jolt's end, the kind reset) follow the model animation and
-- are not ported.
function Native:beatUpState(actor)
  local m = self.mem
  -- 84116410: the move's motion row
  if bit.band(m:u16(actor + 0x7EC), 1) == 0 then
    local row = m:u8(actor + 0x618) - 1
    m:setU8(actor + 0x616, m:u8(m:u32(actor + 0x2D4) + row * 0x14))
    self:copyMotionRow(actor, row)
  end
  m:setU16(actor + 0x7E8, 0)
  self:chooseShot(m:u32(Native.CONTROLLER0), m:u16(Native.MOVE_SHOTS + m:u8(actor + 0x618) * 8))
  self:setProgram(actor, 0)
end

-- ------------------------------------------------ the motion row

-- 841146D4(actor, row): the actor's motion record (+0x2D4, 0x14 bytes a
-- row) row into +0x616 / 617 / 619 / 61A / 61B / 620 / 61C / 61D, +0x628 /
-- 62A / 62C (u16) and +0x661; then the other actor's +0x628 / 62A / 62C /
-- 661 from row bytes 0x10-0x13 of the other's own record.
function Native:copyMotionRow(actor, row)
  local m = self.mem
  local at = m:u32(actor + 0x2D4) + row * 0x14
  local function b(i) return m:u8(at + i) end
  m:setU8(actor + 0x616, b(0)); m:setU8(actor + 0x617, b(1))
  m:setU8(actor + 0x619, b(0xB)); m:setU8(actor + 0x61A, b(0xA))
  m:setU8(actor + 0x61B, b(6)); m:setU8(actor + 0x620, b(9))
  m:setU8(actor + 0x61C, b(2)); m:setU8(actor + 0x61D, b(3))
  m:setU16(actor + 0x628, b(0xC)); m:setU16(actor + 0x62A, b(0xD)); m:setU16(actor + 0x62C, b(0xE))
  m:setU8(actor + 0x661, b(0xF))
  local other = actor == m:u32(Native.PLAYER) and m:u32(Native.ENEMY) or m:u32(Native.PLAYER)
  local oat = m:u32(other + 0x2D4) + row * 0x14
  m:setU16(other + 0x628, m:u8(oat + 0x10)); m:setU16(other + 0x62A, m:u8(oat + 0x11))
  m:setU16(other + 0x62C, m:u8(oat + 0x12)); m:setU8(other + 0x661, m:u8(oat + 0x13))
end

-- ------------------------------------------------ charge turns (families 6, 7, 8)

-- 841155E8(actor), camera part (family 6: event 0x1A, "flew up high!",
-- once 84113430 lets it run): 841155B0 (unless +0x7EC bit 0: kind 3), then
-- unless the shot is 0x21, shot 0 and program 3.
function Native:flyUpState(actor)
  local m = self.mem
  if bit.band(m:u16(actor + 0x7EC), 1) == 0 then
    m:setU8(actor + 0x61F, 3)
    self:copyMotionRow(actor, 0x100)
  end
  self:setTimer(0x258) -- 841155E8: 8411FEE8(0x258)
  local ctrl = m:u32(Native.CONTROLLER0)
  if m:s16(ctrl + 0x98) ~= 0x21 then
    m:setU16(ctrl + 0x98, 0)
    self:setProgram(actor, 3)
  end
end

-- 841157D8(actor) at its frame 1 (fork C; family 6's third state, substate
-- 1, reached when 841156D0 sees the actor 200 above its home height):
-- shot 8 and program 15.
function Native:flyHighShot(actor)
  self.mem:setU16(self.mem:u32(Native.CONTROLLER0) + 0x98, 8)
  self:setProgram(actor, 0xF)
end

-- 84115A64(actor), camera part (family 7: event 0x1B, "dug a hole!", once
-- 84113430 lets it run): 84115940 (unless +0x7EC bit 0: shot 0x10, kind 5),
-- then unless the shot is 0x21, shot 0 and program 0.
function Native:digHoleState(actor)
  local m = self.mem
  local ctrl = m:u32(Native.CONTROLLER0)
  if bit.band(m:u16(actor + 0x7EC), 1) == 0 then
    m:setU16(ctrl + 0x98, 0x10)
    m:setU8(actor + 0x61F, 5)
  end
  if m:s16(ctrl + 0x98) ~= 0x21 then
    m:setU16(ctrl + 0x98, 0)
    self:setProgram(actor, 0)
  end
end

-- 84115B34(actor) substate 1, camera part (the tick after its frame 0x19):
-- unless the shot is 0x21, shot 0x10 and program 2.
function Native:digHoleShot(actor)
  local m = self.mem
  local ctrl = m:u32(Native.CONTROLLER0)
  if m:s16(ctrl + 0x98) ~= 0x21 then
    m:setU16(ctrl + 0x98, 0x10)
    self:setProgram(actor, 2)
  end
  -- +0x7F4 bit 4 (read by 8410B974 for the camera height)
  m:setU16(actor + 0x7F4, bit.bor(m:u16(actor + 0x7F4), 0x10))
end

-- 84115B34(actor) substates 2 / 3, camera part: 2: Diglett / Dugtrio
-- (84115A24) wait for the animation's end, other species (84115988) until
-- they have sunk (+0x28 <= -3 x +0x648; `sunk`), hidden then (8411EE74); frame
-- 0 (3). 3: at frame 0x1E the kind resets (84111BEC) and the actor faces its
-- side (+0x20 = 8411E140).
function Native:digHoleFrame(actor, substate, sunk, finished)
  local m = self.mem
  if substate == 2 then
    local species = m:s16(actor + 0x1A)
    if species == 0x32 or species == 0x33 then
      if not finished then return 2 end
    else
      if not sunk then return 2 end
      m:setU8(actor + 1, bit.band(m:u8(actor + 1), 0xFE))
    end
    m:setU16(actor + 0x7E8, 0)
    return 3
  elseif substate == 3 then
    if m:s16(actor + 0x7E8) == 0x1E then
      m:setU16(actor + 0x7E8, 0)
      self:kindReset(actor)
      m:setU16(actor + 0x20, s16(self:sideFacing(actor)) % 0x10000)
    end
    return 3
  end
  return substate
end

-- 84116138(actor), camera part (family 8: events 0x16-0x19, the charge
-- turn of Razor Wind, Solar Beam, Skull Bash and Sky Attack, once 84113430
-- lets it run): 84116010 (unless +0x7EC bit 0: 841119CC with the code's
-- selector D_84185196 / 8418519E / 841851A6 / 841851AE, kind 0xFF), then
-- program 0 unless the shot is 0x21.
Native.CHARGE_SELECTORS = { [0x16] = 0x84185196, [0x17] = 0x8418519E, [0x18] = 0x841851A6, [0x19] = 0x841851AE }
function Native:chargeState(actor)
  local m = self.mem
  local ctrl = m:u32(Native.CONTROLLER0)
  local code = m:u16(m:u32(Native.RECORD) + 4)
  if bit.band(m:u16(actor + 0x7EC), 1) == 0 then
    local at = Native.CHARGE_SELECTORS[code]
    if at then self:chooseShot(ctrl, m:u16(at)) end
    m:setU8(actor + 0x61F, 0xFF)
    local row = Native.CHARGE_ROWS[code]
    if row then self:copyMotionRow(actor, row) end
  end
  if m:s16(ctrl + 0x98) ~= 0x21 then self:setProgram(actor, 0) end
  -- 84116138: the timer 0x258; the frame counter starts at +0x61B (less
  -- one when +0x61A is 0)
  self:setTimer(0x258)
  local start = m:u8(actor + 0x61B)
  if m:u8(actor + 0x61A) == 0 then start = start - 1 end
  m:setU16(actor + 0x7E8, start % 0x10000)
end
Native.CHARGE_ROWS = { [0x16] = 0xFF, [0x17] = 0x101, [0x18] = 0x103, [0x19] = 0x104 } -- 84116010

-- 84116248(actor) with Dispatch_059's substate (the charge's follow-up), on
-- the actor's frame counter; `finished` is 8003EC34 (the model animation
-- has ended). 0: at frame +0x619 the FOV goal 60 on shot 4 and the jolt ends
-- (45 when the record's move is 0x59); then with +0x61A 0 the animation's
-- end, else frame +0x61A, resets the kind and ends the timer (1).
function Native:chargeFollowFrame(actor, substate, finished)
  local m = self.mem
  if substate ~= 0 then return substate end
  local frame = m:s16(actor + 0x7E8)
  if m:u8(actor + 0x619) == frame then
    local ctrl = m:u32(Native.CONTROLLER0)
    if m:s16(ctrl + 0x98) == 4 then m:setF32(ctrl + 0x88, 60) end
    self:setJolt(0)
    if m:u8(m:u32(Native.RECORD) + 8) == 0x59 then self:setJolt(45) end
  end
  local limit = m:u8(actor + 0x61A)
  if (limit == 0 and finished) or (limit ~= 0 and limit == m:s16(actor + 0x7E8)) then
    self:setTimer(0)
    self:kindReset(actor)
    m:setU16(actor + 0x7E8, 0)
    return 1
  end
  return 0
end

-- 841156D0(actor) (Dispatch_045 substate 0, Fly's rise): once the actor is
-- 200 above its home height (`high`: +0x28 - +0x650 >= 200), +0x28 = home +
-- 200, the kind resets and substate 1 starts; 841157D8 (substate 1) takes
-- shot 8 / program 15 at frame 1 and ends the timer at frame 0x1E.
function Native:flyRiseFrame(actor, substate, high)
  local m = self.mem
  if substate == 0 then
    if not high then return 0 end
    m:setF32(actor + 0x28, f32(m:f32(actor + 0x650) + 200))
    self:kindReset(actor)
    m:setU16(actor + 0x7E8, 0)
    return 1
  elseif substate == 1 then
    local frame = m:s16(actor + 0x7E8)
    if frame == 1 then self:flyHighShot(actor) end
    if m:s16(actor + 0x7E8) == 0x1E then self:setTimer(0) end
    return 1
  end
  return substate
end

-- 8410D088(gc, actor): while the controller's height (+0x60) is above 0,
-- the target (+0x5C) is pulled toward the marker point when the look point
-- (+0x50) is farther than +0x80: at +0x84 x D_84188E58 of that distance.
-- The GeoCamera's target height follows +0x60.
function Native:pullTarget(gc, actor)
  local m = self.mem
  local ctrl = self:controllerFor(gc)
  m:setU32(Native.CURRENT, ctrl)
  if m:f32(ctrl + 0x60) <= 0 then return end
  local point = self:markerPoint(actor, ctrl)
  local distance, pitch, yaw = self:angleTo(point, m:vec(ctrl + 0x50))
  ctrl = m:u32(Native.CURRENT)
  if not (m:f32(ctrl + 0x80) < distance) then return end
  local d = f32(f32(m:f32(ctrl + 0x84) * m:f32(0x84188E58)) * distance)
  m:setVec(ctrl + 0x5C, self:placeEye(point, d, pitch, yaw))
  m:setF32(gc + 0xB8, m:f32(m:u32(Native.CURRENT) + 0x60))
end

-- 8410E878(gc, actor) (fork C): the secondary pose at the side's facing
-- (8411E1D4 << 14), then 8410B704 toward the look point.
function Native:poseSideways(gc, actor)
  local m = self.mem
  local ctrl = self:controllerFor(gc)
  m:setU32(Native.CURRENT, ctrl)
  local sign = actor == m:u32(Native.PLAYER) and 1 or -1
  self:secondaryPose(actor, ctrl, s16((sign * 0x4000) % 0x10000))
  self:towardPose(gc, ctrl, m:vec(ctrl + 0x50))
end

-- 841110EC(gc, actor): program 2's setup: 84120BB4, 8410C934 with the
-- controller's shot, the actor's home pose (8411EFE4) and shown (8411EF08),
-- then empty its own slot.
function Native:program2Setup(gc, actor)
  local m = self.mem
  m:setU32(Native.CURRENT, self:controllerFor(gc))
  self:resetShot(gc, actor)
  self:shot(gc, actor, m:s16(m:u32(Native.CURRENT) + 0x98))
  if self.onActorHome then self.onActorHome(actor) end
  m:setU8(actor + 1, bit.bor(m:u8(actor + 1), 1))
  m:setU32(m:u32(Native.CURRENT) + m:u32(Native.SLOT) * 8 + 8, m:u32(0x84184148))
end

-- 84111170(gc, actor): program 2's tick: FOV 45, 8410D088, 8410E878.
function Native:program2Tick(gc, actor)
  self.mem:setF32(gc + 0x2C, 45)
  self:pullTarget(gc, actor)
  self:poseSideways(gc, actor)
end

-- 84120A50(gc, actor) (fork C): +0x7EA = 0, the up vector, both actors
-- shown (8411EF08), 84120700 on the other actor, jolt 0.
function Native:resetShotOther(gc, actor)
  local m = self.mem
  m:setU16(actor + 0x7EA, 0)
  m:setVec(gc + 0xC0, { 0, 1, 0 })
  for _, global in ipairs({ Native.PLAYER, Native.ENEMY }) do
    local a = m:u32(global)
    m:setU8(a + 1, bit.bor(m:u8(a + 1), 1))
  end
  if self.onActorReset then
    local other = actor == m:u32(Native.PLAYER) and m:u32(Native.ENEMY) or m:u32(Native.PLAYER)
    self.onActorReset(other)
  end
  self:setJolt(0)
end

-- 8410CD3C(gc, actor, shot): the shot (D_8418455C row) around the marker
-- point: the controller's distances from the actor's record, the look
-- point and target at the marker point (8411E0A4), pitch and signed yaw
-- from the row, distance x row +4, FOV 45 now and as the goal, the eye from
-- the look point (800371B4) and +0x68 = the eye.
function Native:markerShot(gc, actor, shot)
  local m = self.mem
  local ctrl = self:controllerFor(gc)
  m:setU32(Native.CURRENT, ctrl)
  local yaw = poseYaw(self, actor)
  local sign = yaw < 0 and -1 or 1
  m:setF32(ctrl + 0x78, 0)
  m:setF32(ctrl + 0x44, 0)
  m:setF32(ctrl + 0x84, m:f32(actor + 0x644))
  m:setF32(ctrl + 0x80, m:f32(actor + 0x640))
  m:setF32(ctrl + 0x7C, m:f32(actor + 0x654))
  m:setF32(ctrl + 0x74, m:f32(actor + 0x64C))
  local ox, oz = self:rotateOffset(m:vec(actor + 0x634), yaw)
  local x, z = f32(ox + m:f32(actor + 0x24)), f32(oz + m:f32(actor + 0x2C))
  local y = m:f32(actor + 0x638)
  m:setVec(ctrl + 0x5C, { x, y, z })
  m:setVec(ctrl + 0x50, { x, y, z })
  local point = self:markerPoint(actor, ctrl)
  m:setVec(ctrl + 0x5C, point)
  m:setVec(ctrl + 0x50, point)
  m:setVec(gc + 0xB4, point)
  local row = Native.SHOTS + shot * 0x1C
  m:setU16(ctrl + 0x90, m:u16(row))
  m:setU16(ctrl + 0x92, (m:s16(row + 2) * sign + yaw) % 0x10000)
  m:setF32(ctrl + 0x74, f32(m:f32(ctrl + 0x74) * m:f32(row + 4)))
  m:setF32(ctrl + 0x88, m:f32(row + 0x10))
  m:setF32(gc + 0x2C, 45)
  m:setF32(ctrl + 0x88, 45)
  m:setVec(gc + 0xA8, self:placeEye(m:vec(ctrl + 0x50), m:f32(ctrl + 0x74), m:s16(ctrl + 0x90), m:s16(ctrl + 0x92)))
  m:setVec(ctrl + 0x68, m:vec(gc + 0xA8))
end

-- 84110558(gc, actor): program 15's setup: 84120A50, 8410CD3C with the
-- controller's shot, then empty its own slot.
function Native:program15Setup(gc, actor)
  local m = self.mem
  m:setU32(Native.CURRENT, self:controllerFor(gc))
  self:resetShotOther(gc, actor)
  self:markerShot(gc, actor, m:s16(m:u32(Native.CURRENT) + 0x98))
  m:setU32(m:u32(Native.CURRENT) + m:u32(Native.SLOT) * 8 + 8, m:u32(0x84184148))
end

-- ------------------------------------------------ confusion self-hit (family 16)

-- BattleAnim_Dispatch_114 (84116980, fork C), camera part (event 1, "It hurt
-- itself in its confusion!", once 84113430 lets it run): 841168A0 (unless
-- +0x7EC bit 0: a random shot of D_84183BDC, 8003570C % 6, and kind 0xFF),
-- then program 0. 84116AC4's kind reset (84116A3C) waits on the model
-- animation and is not ported.
function Native:selfHitState(actor)
  local m = self.mem
  if bit.band(m:u16(actor + 0x7EC), 1) == 0 then
    m:setU16(m:u32(Native.CONTROLLER0) + 0x98, m:u16(0x84183BDC + (self:drawRandom() % 6) * 2))
    m:setU8(actor + 0x61F, 0xFF)
    self:copyMotionRow(actor, m:u8(actor + 0x618) - 1)
  end
  self:setProgram(actor, 0)
  -- the frame counter from +0x61B, timer 0x258
  m:setU16(actor + 0x7E8, m:u8(actor + 0x61B))
  self:setTimer(0x258)
end

-- 84116AC4 / 84116A3C(actor) (substate 0), camera part: with +0x61A 0 the
-- animation's end, else frame +0x61A, ends the timer and resets the kind (1).
function Native:selfHitFrame(actor, substate, finished)
  local m = self.mem
  if substate ~= 0 then return substate end
  local limit = m:u8(actor + 0x61A)
  if (limit == 0 and finished) or (limit ~= 0 and limit == m:s16(actor + 0x7E8)) then
    self:setTimer(0)
    self:kindReset(actor)
    m:setU16(actor + 0x7E8, 0)
    return 1
  end
  return 0
end

-- ------------------------------------------------ Substitute faded (21), dragged out (25)

-- BattleAnim_Dispatch_149 (8411B518, fork C), camera part (event 0x27,
-- "SUBSTITUTE faded!", once 84113430 lets it run): shot 0 and program 0.
function Native:substituteFadedState(actor)
  self.mem:setU16(self.mem:u32(Native.CONTROLLER0) + 0x98, 0)
  self:setProgram(actor, 0)
end

-- 8411B5A8(actor) substate 2, camera part (the tick after its frame 0x1E):
-- after 84112C98 (the swap back from the doll: species reload is the
-- controller's; its home pose 8411EFE4 and +0x7EA = 0 are here), shot 0,
-- program 0 and +0x7EA = 0.
function Native:substituteFadedShot(actor)
  local m = self.mem
  if self.onActorHome then self.onActorHome(actor) end
  m:setU16(actor + 0x7EA, 0)
  m:setU16(m:u32(Native.CONTROLLER0) + 0x98, 0)
  self:setProgram(actor, 0)
  m:setU16(actor + 0x7EA, 0)
end

-- 8411B898(actor) substate 1, camera part (family 25: events 0x2D-0x2F,
-- the tick after Dispatch_177 finds the new model ready): unless the shot is
-- 0x21, +0x7EA = 0, shot 0 and program 0.
function Native:dragOutShot(actor)
  local m = self.mem
  local ctrl = m:u32(Native.CONTROLLER0)
  if m:s16(ctrl + 0x98) == 0x21 then return end
  m:setU16(actor + 0x7EA, 0)
  m:setU16(ctrl + 0x98, 0)
  self:setProgram(actor, 0)
end

-- ------------------------------------------------ split-screen intro views

-- The GeoCamera (S1_unk_D_86002F34_00C, 0xF0 bytes): graph-node flags at +1
-- (bit 0x10: the view is drawn), viewport x / y / w / h at +0x1C..+0x22,
-- projection fovy / aspect / near / far / scale at +0x2C..+0x3C, ortho
-- l / r / b / t / n / f / scale at +0x44..+0x5C, eye / at / up at +0xA8 /
-- +0xB4 / +0xC0. D_84190428 and D_841910E0 are the two GeoCameras
-- (84111868 passes them to the camera tick 84111774).
Native.VIEW_DRAWN = 0x10
Native.VIEW0 = 0x84190428 -- D_84190428: controller 0's GeoCamera
Native.VIEW1 = 0x841910E0 -- D_841910E0: controller 1's GeoCamera

-- 80038E14(gc, eye, at, roll): eye and at stored, up from the roll and the
-- flat direction (x / z) to the target: (sin r * uz, cos r, -sin r * ux),
-- with u = (at - eye) / -|flat| computed in double.
function Native:lookAt(gc, eye, at, roll)
  local m = self.mem
  local dx, dz = f32(at[1] - eye[1]), f32(at[3] - eye[3])
  local len = f32(math.sqrt(f32(f32(dx * dx) + f32(dz * dz))))
  local inv = f32(-1.0 / len)
  local ux, uz = f32(dx * inv), f32(dz * inv)
  m:setVec(gc + 0xA8, eye)
  m:setVec(gc + 0xB4, at)
  local sn = self:sin(roll)
  m:setVec(gc + 0xC0, { f32(sn * uz), self:cos(roll), f32(f32(-sn) * ux) })
end

-- 8410AE8C(gc, x, y, w, h): GeoCamera_SetViewport (80038D0C),
-- GeoCamera_SetPerspective (80038DC8) with the GeoCamera's FOV, near 20,
-- far 6400, and 80038E14 with its own eye and target, roll 0.
function Native:applyView(gc, x, y, w, h)
  local m = self.mem
  x, y, w, h = s16(x), s16(y), s16(w), s16(h)
  m:setU16(gc + 0x1C, x % 0x10000); m:setU16(gc + 0x1E, y % 0x10000)
  m:setU16(gc + 0x20, w % 0x10000); m:setU16(gc + 0x22, h % 0x10000)
  m:setF32(gc + 0x44, f32(-w * 0.5)); m:setF32(gc + 0x48, f32(w * 0.5))
  m:setF32(gc + 0x50, f32(h * 0.5)); m:setF32(gc + 0x4C, f32(-h * 0.5))
  m:setF32(gc + 0x54, -2); m:setF32(gc + 0x58, 2); m:setF32(gc + 0x5C, 1)
  m:setF32(gc + 0x30, f32(w / h))
  m:setF32(gc + 0x34, 20); m:setF32(gc + 0x38, 6400); m:setF32(gc + 0x3C, 1)
  self:lookAt(gc, m:vec(gc + 0xA8), m:vec(gc + 0xB4), 0)
end

local function rect(self, ctrl)
  local m = self.mem
  return m:s16(ctrl + 0x9A), m:s16(ctrl + 0x9C), m:s16(ctrl + 0x9E), m:s16(ctrl + 0xA0)
end
local function setRect(self, ctrl, x, y, w, h)
  local m = self.mem
  m:setU16(ctrl + 0x9A, x % 0x10000); m:setU16(ctrl + 0x9C, y % 0x10000)
  m:setU16(ctrl + 0x9E, w % 0x10000); m:setU16(ctrl + 0xA0, h % 0x10000)
end
local function drawn(self, gc, on)
  local m = self.mem
  m:setU8(gc + 1, on and bit.bor(m:u8(gc + 1), 0x10) or bit.band(m:u8(gc + 1), 0xEF))
end

-- 8410AF1C (fork C): controller 0 takes the top half (0, 0, 320, 120) and
-- controller 1 the bottom (0, 120, 320, 120); the second view is drawn.
function Native:splitViews()
  local m = self.mem
  local c0, c1 = m:u32(Native.CONTROLLER0), m:u32(Native.CONTROLLER1)
  setRect(self, c0, 0, 0, 0x140, 0x78); self:applyView(Native.VIEW0, rect(self, c0))
  setRect(self, c1, 0, 0x78, 0x140, 0x78); self:applyView(Native.VIEW1, rect(self, c1))
  drawn(self, Native.VIEW1, true)
end

-- 8410B08C (fork C): both controllers' rectangles applied; the second view
-- is drawn.
function Native:applyViews()
  local m = self.mem
  local c0, c1 = m:u32(Native.CONTROLLER0), m:u32(Native.CONTROLLER1)
  self:applyView(Native.VIEW0, rect(self, c0))
  self:applyView(Native.VIEW1, rect(self, c1))
  drawn(self, Native.VIEW1, true)
end

-- 8410B224 (fork C): controller 0's rectangle applied, the second view no
-- longer drawn, controller 1's program cleared.
function Native:closeSecondView()
  local m = self.mem
  local c0 = m:u32(Native.CONTROLLER0)
  self:applyView(Native.VIEW0, rect(self, c0))
  drawn(self, Native.VIEW1, false)
  self:clearProgram1()
end

-- 8410B104 (fork C): while the second view is drawn, controller 0 goes full
-- screen (0, 0, 320, 240), the second view stops and the first is drawn;
-- then controller 1's program is cleared and both actors' +0x18 = 0.
function Native:endSplit()
  local m = self.mem
  local c0, c1 = m:u32(Native.CONTROLLER0), m:u32(Native.CONTROLLER1)
  if bit.band(m:u8(Native.VIEW1 + 1), 0x10) ~= 0 then
    setRect(self, c0, 0, 0, 0x140, 0xF0)
    self:applyView(Native.VIEW0, rect(self, c0))
    drawn(self, Native.VIEW1, false)
    drawn(self, Native.VIEW0, true)
  end
  self:clearProgram1()
  m:setU16(m:u32(Native.PLAYER) + 0x18, 0)
  m:setU16(m:u32(Native.ENEMY) + 0x18, 0)
end

-- ------------------------------------------------ the arena intro path

Native.INTRO_ROWS = 0x841851BC  -- D_841851BC: 13 s16 per path (6 maxima, 6 curve starts, the data size)
Native.INTRO_CURVES = 0x84190520 -- D_84190520: the path's s16 curves (84113590)
Native.INTRO_TABLE = 0x84183A90  -- D_84183A90: the path data's archive offsets
Native.INTRO_PATH = 0x841911F9   -- D_841911F9: the path index
Native.ARCHIVE = 0x49B780

-- 84113590(index), camera part: the path index and its curves copied from
-- the ROM archive (80003F74). The game-mode adjustments (D_841910D8 0x14 /
-- 0x19) are the caller's.
function Native:loadIntroPath(index)
  local m = self.mem
  m:setU8(Native.INTRO_PATH, index)
  local bytes = self.introPaths and self.introPaths[index]
  if not bytes then
    local size = m:s16(Native.INTRO_ROWS + index * 0x1A + 0x18)
    local src = Native.ARCHIVE + bit.band(m:u32(Native.INTRO_TABLE + index * 4), 0xFFFFFF)
    bytes = assert(self.rom, "battle camera: the intro path needs the ROM"):sub(src + 1, src + size)
  end
  for i = 1, #bytes do m:setU8(Native.INTRO_CURVES + i - 1, bytes:byte(i)) end
end

-- The six intro paths' curve bytes (84113590's copies), for a caller that
-- keeps only part of the ROM.
function Native.introPathBytes(rom, fragment79)
  local function frag(address, n)
    local o = address - 0x84100000
    local v = 0
    for i = 1, n do v = v * 256 + fragment79:byte(o + i) end
    return v
  end
  local out = {}
  for index = 0, 5 do
    local size = frag(Native.INTRO_ROWS + index * 0x1A + 0x18, 2)
    if size >= 0x8000 then size = size - 0x10000 end
    local src = Native.ARCHIVE + bit.band(frag(Native.INTRO_TABLE + index * 4, 4), 0xFFFFFF)
    out[index] = rom:sub(src + 1, src + math.max(0, size))
  end
  return out
end

-- 8410BDA0(gc, actor): the keyframed path. Six counters (controller +0x68,
-- +0x6C, +0x70, +0x5C, +0x60, +0x64) each step by 1 up to the path row's
-- maximum and index their curve; the side sign mirrors x and the actor's
-- facing (yaw + 0x4000) turns z. Scale D_84188E3C on path 5, else
-- D_84188E40; heights by D_84188E44 (eye) and D_84188E48 (target).
function Native:introPath(gc, actor)
  local m = self.mem
  local ctrl = self:controllerFor(gc)
  m:setU32(Native.CURRENT, ctrl)
  local sign = actor == m:u32(Native.PLAYER) and 1 or -1
  local path = m:u8(Native.INTRO_PATH)
  local scale = m:f32(path == 5 and 0x84188E3C or 0x84188E40)
  local row = Native.INTRO_ROWS + path * 0x1A
  local function channel(counter, k)
    local c = f32(m:f32(ctrl + counter) + 1)
    m:setF32(ctrl + counter, c)
    local max = m:s16(row + k * 2)
    if max <= c then m:setF32(ctrl + counter, max); c = max end
    local index = s16(math.floor(c >= 0 and c or -math.floor(-c)) % 0x10000)
    return m:s16(Native.INTRO_CURVES + m:s16(row + 0xC + k * 2) * 2 + index * 2)
  end
  local turn = self:cos((m:s16(actor + 0x20) + 0x4000) % 0x10000)
  local signed = f32(turn * sign)
  local offset = f32(-150 * sign)
  m:setF32(gc + 0xB0, f32(signed * f32(channel(0x68, 0) * scale)))
  m:setF32(gc + 0xAC, f32(channel(0x6C, 1) * m:f32(0x84188E44)))
  m:setF32(gc + 0xA8, f32(f32(f32(channel(0x70, 2) * scale) * sign) + offset))
  local tz = channel(0x5C, 3)
  m:setF32(gc + 0xBC, f32(signed * f32(tz * scale)))
  m:setF32(gc + 0xB8, f32(channel(0x60, 4) * m:f32(0x84188E48)))
  m:setF32(gc + 0xB4, f32(f32(f32(channel(0x64, 5) * scale) * sign) + offset))
end

-- 8410C304(gc, actor, shot) (fork C): 84120BB4, the look point (-150 x
-- side, 20, 0), distance 180, FOV 45 now and as the goal, the path counters
-- (+0x68 and +0x5C triples) at -1, then 8410BDA0.
function Native:introSetup(gc, actor)
  local m = self.mem
  local ctrl = self:controllerFor(gc)
  m:setU32(Native.CURRENT, ctrl)
  self:resetShot(gc, actor)
  ctrl = m:u32(Native.CURRENT)
  local sign = actor == m:u32(Native.PLAYER) and 1 or -1
  m:setF32(ctrl + 0x50, f32(sign * -150)); m:setF32(ctrl + 0x54, 20); m:setF32(ctrl + 0x58, 0)
  m:setF32(ctrl + 0x74, 180)
  m:setF32(gc + 0x2C, 45); m:setF32(ctrl + 0x88, 45)
  m:setVec(ctrl + 0x68, { -1, -1, -1 }); m:setVec(ctrl + 0x5C, { -1, -1, -1 })
  self:introPath(gc, actor)
end

-- 8410C400(gc, actor, distance, height, fraction, pitch): with fraction 0,
-- 8410BDA0. Otherwise the secondary pitch (+0x3C) steps toward -4004 by
-- `pitch` (84120310), +0x44 eases to 0.15 at 0.03, the target height eases to `height` at
-- +0x44 x fraction (and +0x54 follows it), and the eye moves +0x44 of the
-- way toward the pose at `distance` from the look point.
function Native:introBlend(gc, actor, distance, height, fraction, pitch)
  local m = self.mem
  local Memory = require("mods.STADIUM2_IMPORTER.lib.stadium2_native_memory")
  local ctrl = self:controllerFor(gc)
  m:setU32(Native.CURRENT, ctrl)
  if fraction == 0 then return self:introPath(gc, actor) end
  self:stepToS16(ctrl + 0x3C, -0xFA4, pitch)
  m:setF32(ctrl + 0x44, Native.ease(m:f32(ctrl + 0x44), Memory.wordFloat(0x3E19999A), Memory.wordFloat(0x3CF5C28F)))
  m:setF32(gc + 0xB8, Native.ease(m:f32(gc + 0xB8), height, f32(m:f32(ctrl + 0x44) * fraction)))
  m:setF32(ctrl + 0x54, m:f32(gc + 0xB8))
  local goal = self:placeEye(m:vec(ctrl + 0x50), distance, m:s16(ctrl + 0x3C), m:s16(ctrl + 0x3E))
  local eye = m:vec(gc + 0xA8)
  local d, p, y = self:angleTo(eye, goal)
  m:setVec(gc + 0xA8, self:placeEye(eye, f32(m:f32(ctrl + 0x44) * d), p, y))
end

-- 8411C7B8(actor, ctrl, turnAt) (fork C): shot 0; at the player's frame 1
-- the secondary pose from the actor's facing with pitch 0; at `turnAt` the
-- fraction +0x44 restarts; before `turnAt` the path (8410C400 with fraction
-- 0), from it on the blend (80, 30, 0.5, pitch 0x1C71).
function Native:introStep(actor, ctrl, turnAt)
  local m = self.mem
  local Memory = require("mods.STADIUM2_IMPORTER.lib.stadium2_native_memory")
  m:setU16(ctrl + 0x98, 0)
  local frame = m:s16(m:u32(Native.PLAYER) + 0x7E8)
  if frame == 1 then
    self:secondaryPose(actor, ctrl, m:s16(actor + 0x20))
    m:setU16(ctrl + 0x3C, 0)
  end
  if turnAt == frame then m:setF32(ctrl + 0x44, 0) end
  if frame < turnAt then
    self:introBlend(m:u32(ctrl), actor, 50, 30, 0, 0)
  else
    self:introBlend(m:u32(ctrl), actor, 80, 30, Memory.wordFloat(0x3F000000), 0x1C71)
  end
end

-- 8411C8A0 (fork C), camera part (family 26, event 0x65: the arena intro):
-- the split views (8410AF1C), controller 0's program cleared (84111248) and
-- 8410C304 on the player, controller 1's cleared and 8410C304 on the foe,
-- both actors hidden (+1 bit 0).
function Native:arenaIntroSetup()
  local m = self.mem
  local c0, c1 = m:u32(Native.CONTROLLER0), m:u32(Native.CONTROLLER1)
  self:splitViews()
  self:clearProgram()
  self:introSetup(m:u32(c0), m:u32(Native.PLAYER))
  self:clearProgram1()
  self:introSetup(m:u32(c1), m:u32(Native.ENEMY))
  for _, global in ipairs({ Native.PLAYER, Native.ENEMY }) do
    local a = m:u32(global)
    m:setU8(a + 1, bit.band(m:u8(a + 1), 0xFE))
  end
end

-- 8411C9DC (fork C), camera part, on the player's frame counter: substate
-- 1 steps both paths (turn at 0x78); from frame 0x3C controller 0's height
-- grows 4 lines a frame to 240 while controller 1 takes the rest below it
-- (8410B08C), and at 240 the second view closes (8410B224, substate 2).
-- Substate 2 keeps stepping and ends the split at frame 0xA0 (8410B104,
-- substate 3). Returns the next substate.
function Native:arenaIntroFrame(substate)
  local m = self.mem
  local c0, c1 = m:u32(Native.CONTROLLER0), m:u32(Native.CONTROLLER1)
  local player, enemy = m:u32(Native.PLAYER), m:u32(Native.ENEMY)
  local frame = m:s16(player + 0x7E8)
  if substate == 1 then
    self:introStep(player, c0, 0x78)
    self:introStep(enemy, c1, 0x78)
    if frame >= 0x3C then
      local h = m:s16(c0 + 0xA0)
      if h < 0xF0 then h = math.min(h + 4, 0xF0) else h = math.max(h - 4, 0xF0) end
      m:setU16(c0 + 0xA0, h)
      m:setU16(c1 + 0x9C, h)
      m:setU16(c1 + 0xA0, (0xF0 - h) % 0x10000)
      if h == 0xF0 then self:closeSecondView(); return 2 end
      self:applyViews()
    end
    return 1
  elseif substate == 2 then
    self:introStep(player, c0, 0x78)
    self:introStep(enemy, c1, 0x78)
    if frame == 0xA0 then self:endSplit(); return 3 end
    return 2
  end
  return substate
end

-- ------------------------------------------------ the opening send-out (family 24)

-- 8410B1CC (fork C): controller 1's rectangle applied, the first view no
-- longer drawn, controller 0's program cleared (84111248).
function Native:keepSecondView()
  local m = self.mem
  local c1 = m:u32(Native.CONTROLLER1)
  self:applyView(Native.VIEW1, rect(self, c1))
  drawn(self, Native.VIEW0, false)
  self:clearProgram()
end

-- 8410F6AC(gc, actor): program 21's setup: the controller's distance,
-- pitch and yaw (+0x74 / +0x90 / +0x92) from the eye to the target
-- (80037120); its slot empties.
function Native:program21Setup(gc)
  local m = self.mem
  local ctrl = self:controllerFor(gc)
  m:setU32(Native.CURRENT, ctrl)
  local d, pitch, yaw = self:angleTo(m:vec(gc + 0xA8), m:vec(gc + 0xB4))
  m:setF32(ctrl + 0x74, d); m:setU16(ctrl + 0x90, pitch % 0x10000); m:setU16(ctrl + 0x92, yaw % 0x10000)
  m:setU32(m:u32(Native.CURRENT) + m:u32(Native.SLOT) * 8 + 8, m:u32(0x84184148))
end

-- 8410F724 / 8410F844(gc): programs 21 / 22's tick: the yaw steps toward
-- -0x8000 / 0x4000 by 0x71C and the target turns around the eye (800371B4
-- from the eye).
local function panTick(self, gc, goal)
  local m = self.mem
  local ctrl = self:controllerFor(gc)
  m:setU32(Native.CURRENT, ctrl)
  self:stepToS16(ctrl + 0x92, goal, 0x71C)
  m:setVec(gc + 0xB4, self:placeEye(m:vec(gc + 0xA8), m:f32(ctrl + 0x74), m:s16(ctrl + 0x90), m:s16(ctrl + 0x92)))
end
function Native:program21Tick(gc) panTick(self, gc, -0x8000) end
function Native:program22Tick(gc) panTick(self, gc, 0x4000) end

-- 8410F78C(gc, actor): program 22's setup: as program 21's, then the yaw
-- turned by 0x5555 and the target placed there; its slot empties.
function Native:program22Setup(gc)
  local m = self.mem
  local ctrl = self:controllerFor(gc)
  m:setU32(Native.CURRENT, ctrl)
  local d, pitch, yaw = self:angleTo(m:vec(gc + 0xA8), m:vec(gc + 0xB4))
  m:setF32(ctrl + 0x74, d); m:setU16(ctrl + 0x90, pitch % 0x10000); m:setU16(ctrl + 0x92, yaw % 0x10000)
  ctrl = m:u32(Native.CURRENT)
  m:setU16(ctrl + 0x92, (m:s16(ctrl + 0x92) + 0x5555) % 0x10000)
  m:setVec(gc + 0xB4, self:placeEye(m:vec(gc + 0xA8), m:f32(ctrl + 0x74), m:s16(ctrl + 0x90), m:s16(ctrl + 0x92)))
  m:setU32(m:u32(Native.CURRENT) + m:u32(Native.SLOT) * 8 + 8, m:u32(0x84184148))
end

-- 8411C1D4(actor, ctrl, turnAt): 8411C7B8's twin for the send-out: shot
-- 0; at the player's frame 1 the secondary pose from the actor's facing;
-- at turnAt - 0x23 the fraction +0x44 restarts; before it 8410C720 (50, 70,
-- 0, 0), from it (75, 30, 0.5, 0x1C71).
function Native:openingFoeStep(actor, ctrl, turnAt)
  local m = self.mem
  local Memory = require("mods.STADIUM2_IMPORTER.lib.stadium2_native_memory")
  m:setU16(ctrl + 0x98, 0)
  local frame = m:s16(m:u32(Native.PLAYER) + 0x7E8)
  if frame == 1 then
    self:secondaryPose(actor, ctrl, m:s16(actor + 0x20))
    frame = m:s16(m:u32(Native.PLAYER) + 0x7E8)
  end
  local at = turnAt - 0x23
  if at == frame then
    m:setF32(ctrl + 0x44, 0)
    frame = m:s16(m:u32(Native.PLAYER) + 0x7E8)
  end
  if frame < at then
    self:sendOutPose(m:u32(ctrl), 50, 70, 0, 0)
  else
    self:sendOutPose(m:u32(ctrl), 75, 30, Memory.wordFloat(0x3F000000), 0x1C71)
  end
end

-- 8411C310, camera part (family 24's second state, event 0x22: the
-- opening send-out): +0x7EA = 0 on both actors, program 26 on the player
-- (controller 0, shot 0), 8410C544 on controller 1 for the foe (shot 0), the
-- player shown, the foe hidden (8411EE74) with +0x18 = 3 (8411EF20).
function Native:openingSetup()
  local m = self.mem
  local player, enemy = m:u32(Native.PLAYER), m:u32(Native.ENEMY)
  m:setU16(player + 0x7EA, 0); m:setU16(enemy + 0x7EA, 0)
  m:setU8(player + 0x7F6, 1)
  m:setU16(m:u32(Native.CONTROLLER0) + 0x98, 0)
  self:setProgram(player, 0x1A)
  local c1 = m:u32(Native.CONTROLLER1)
  m:setU16(c1 + 0x98, 0)
  self:sendOutShot(m:u32(c1), enemy, m:s16(c1 + 0x98))
  m:setU8(player + 1, bit.bor(m:u8(player + 1), 1))
  m:setU8(player + 0x1D, 0)
  m:setU16(enemy + 0x18, 3)
  m:setU8(enemy + 1, bit.band(m:u8(enemy + 1), 0xFE))
end

-- 8411C418(substate), camera part, on the player's frame counter
-- (`playerReady` / `foeReady`: 8003EC34, the actor's model animation has
-- finished). 1: once the player's entrance ends, controller 0 full screen and
-- controller 1 a zero-width rectangle at the right edge; program 21 on the
-- player, program 22 on controller 1 for the foe. 2: controller 1's width
-- steps 30 a frame to 320 as its left edge slides in (8410B08C); at 320 it
-- becomes the only view (8410B1CC) on 8410C544's shot of the foe. 3 / 4:
-- 8411C1D4 on the foe for 0x28 frames, then program 26 for the foe on both
-- controllers. 5: once the foe's animation ends, done (6). Returns the
-- next substate.
function Native:openingFrame(substate, playerReady, foeReady)
  local m = self.mem
  local c0, c1 = m:u32(Native.CONTROLLER0), m:u32(Native.CONTROLLER1)
  local player, enemy = m:u32(Native.PLAYER), m:u32(Native.ENEMY)
  if substate == 1 then
    if not playerReady then return 1 end
    setRect(self, c0, 0, 0, 0x140, 0xF0)
    setRect(self, c1, 0x140, 0, 0, 0xF0)
    self:setProgram(player, 0x15)
    self:setProgram1(enemy, 0x16)
    return 2
  elseif substate == 2 then
    local w = m:s16(c1 + 0x9E)
    if w < 0x140 then w = math.min(w + 30, 0x140) else w = math.max(w - 30, 0x140) end
    m:setU16(c1 + 0x9E, w)
    m:setU16(c1 + 0x9A, 0x140 - w)
    m:setU16(c0 + 0x9E, 0x140 - w)
    if w == 0x140 then
      self:clearProgram1()
      self:clearProgram()
      m:setU16(c1 + 0x98, 0)
      self:sendOutShot(m:u32(c1), enemy, 0)
      m:setU8(enemy + 1, bit.band(m:u8(enemy + 1), 0xFE))
      self:keepSecondView()
      m:setU8(player + 1, bit.band(m:u8(player + 1), 0xFE))
      m:setU8(enemy + 1, bit.bor(m:u8(enemy + 1), 1))
      m:setU8(enemy + 0x1D, 0)
      m:setU16(player + 0x7E8, 0)
      return 3
    end
    self:applyViews()
    return 2
  elseif substate == 3 then
    m:setU16(player + 0x7E8, 0)
    self:openingFoeStep(enemy, c1, 0x28)
    return 4
  elseif substate == 4 then
    self:openingFoeStep(enemy, c1, 0x28)
    if m:s16(player + 0x7E8) == 0x28 then
      self:setProgram1(enemy, 0x1A)
      m:setU16(c0 + 0x98, 0)
      self:setProgram(enemy, 0x1A)
      return 5
    end
    return 4
  elseif substate == 5 then
    if not foeReady then return 5 end
    m:setU16(player + 0x7E8, 0)
    return 6
  end
  return substate
end

-- ------------------------------------------------ the idle camera (family 31)

Native.TIMER = 6 -- record +6: the event timer (8411FEE8 sets it, 8411FEFC counts it down)
function Native:setTimer(frames)
  self.mem:setU16(self.mem:u32(Native.RECORD) + Native.TIMER, frames)
  if self.onEventTimer then self.onEventTimer(frames) end
end

-- 8411F794 / 8411F7E0 / 8411F82C / 8411F878 / 8411F8C4 (fork C): the idle
-- skips, each ending the timer when true: flags bit 1, flags bit 2, +0x10 ==
-- 0x20, +0x10 == 7, no HP.
local function skips(self, actor, which)
  local m = self.mem
  local row = m:u32(Native.RECORD) + self:side(actor) * 16
  local tests = {
    flag2 = bit.band(m:u16(row + 0x12), 2) ~= 0,
    flag4 = bit.band(m:u16(row + 0x12), 4) ~= 0,
    kind20 = m:u16(row + 0x10) == 0x20,
    kind7 = m:u16(row + 0x10) == 7,
    fainted = m:u16(row + 0xE) == 0,
  }
  local any = false
  for _, name in ipairs(which) do
    if tests[name] then self:setTimer(0); any = true end
  end
  return any
end

-- 84113658(actor): the species' own shot (archive 0x49B780 + 0xE0A0, 0x10
-- bytes per species) into shot row 0x27 of D_8418455C.
Native.SPECIES_SHOTS = 0xE0A0
function Native:loadSpeciesShot(actor)
  local m = self.mem
  local species = m:s16(actor + 0x1A)
  local bytes = self.speciesShots and self.speciesShots:sub((species - 1) * 0x10 + 1, species * 0x10)
  if not bytes or #bytes < 0x10 then
    local src = Native.ARCHIVE + bit.band((species - 1) * 0x10 + Native.SPECIES_SHOTS, 0xFFFFFF)
    bytes = assert(self.rom, "battle camera: the species shot needs the ROM"):sub(src + 1, src + 0x10)
  end
  local function b(i) return bytes:byte(i + 1) end
  local row = Native.SHOTS + 0x27 * 0x1C
  for i = 0, 3 do m:setU8(row + i, b(i)) end         -- +0 / +2
  for i = 4, 7 do m:setU8(row + i, b(i)) end         -- +4 (f32)
  for i = 8, 11 do m:setU8(row + 8 + i - 8, b(i)) end -- +8 / +0xA
  for i = 12, 15 do m:setU8(row + 0xC + i - 12, b(i)) end -- +0xC (f32)
end

-- 84113E7C(actor) after its 84113430 gate, camera part: by the idle code
-- (record +4, 0x5C-0x69), the timer (8411FEE8) and the program; the skip
-- checks end the timer instead. Returns the family the actor is given at the
-- end (0 or 1; family 1's 0x12C timer and its end are the controller's), or
-- nil.
function Native:idleState(actor)
  local m = self.mem
  local code = m:u16(m:u32(Native.RECORD) + 4)
  local ctrl = m:u32(Native.CONTROLLER0)
  if code == 0x68 or code == 0x69 then
    self:setTimer(0x96); self:setProgram(actor, 4); return 0
  elseif code == 0x5C then
    self:setTimer(0x12C); self:setProgram(actor, 4); return 0
  elseif code == 0x5D then
    self:setTimer(0x12C); self:setProgram(actor, 8); return 0
  elseif code == 0x5E then
    self:setTimer(0x12C); self:setProgram(actor, 9); return 0
  elseif code == 0x5F then
    if skips(self, actor, { "kind20", "flag4", "fainted" }) then return nil end
    self:setTimer(0x2D)
    m:setU16(ctrl + 0x98, m:u16(0x84183C44 + (self:drawRandom() % 7) * 2))
    self:setProgram(actor, m:s16(ctrl + 0x98) == 5 and 0xC or 0)
    local row = m:u32(Native.RECORD) + self:side(actor) * 16
    local stay = m:u16(row + 0x10) == 0x20 or m:u16(row + 0x10) == 7
    if stay then self:setTimer(0) end
    return stay and 0 or 1
  elseif code == 0x60 then
    if skips(self, actor, { "flag2", "flag4", "fainted" }) then return nil end
    self:setTimer(0x3D)
    m:setU16(ctrl + 0x98, m:u16(0x84183C54 + (self:drawRandom() % 6) * 2))
    self:setProgram(actor, 0)
    return 0
  elseif code == 0x61 then
    if skips(self, actor, { "flag2", "flag4", "fainted", "kind20" }) then return nil end
    self:setTimer(0x3D); self:setProgram(actor, 7); return 0
  elseif code == 0x62 then
    if skips(self, actor, { "flag2", "flag4", "fainted", "kind7", "kind20" }) then return nil end
    self:setTimer(0x64); self:setProgram(actor, 0xE); return nil
  elseif code == 0x63 then
    if skips(self, actor, { "flag2", "flag4", "fainted", "kind7", "kind20" }) then return nil end
    self:loadSpeciesShot(actor)
    self:setTimer(0x32)
    m:setU16(ctrl + 0x98, 0x27)
    self:setProgram(actor, 0xC)
    return 0
  elseif code == 0x64 then
    self:setTimer(0x50); self:setProgram(actor, 0x1C); return 0
  end
  return nil
end

-- 8410FC28 / 8410FDEC / 8410FF6C (programs 4, 8, 9's setups): FOV 45,
-- 84120960, the orbit pose (pitch, yaw 0, distance) around (0, 40, 0), or
-- (0, 180, 0) when either side's flags have bit 1 (with `flagPitch` when
-- given), the eye placed from the target; the slot empties.
local function arenaOrbit(self, gc, actor, pitch, flagPitch, distance)
  local m = self.mem
  m:setU32(Native.CURRENT, self:controllerFor(gc))
  m:setF32(gc + 0x2C, 45)
  self:resetShotScaled(gc, actor, 0x84189C4C, 0x84189C54)
  local ctrl = m:u32(Native.CURRENT)
  m:setU16(ctrl + 0x90, pitch % 0x10000)
  m:setU16(ctrl + 0x92, 0)
  m:setF32(ctrl + 0x74, distance)
  local record = m:u32(Native.RECORD)
  if bit.band(m:u16(record + 0x12), 2) ~= 0 or bit.band(m:u16(record + 0x22), 2) ~= 0 then
    m:setVec(gc + 0xB4, { 0, 180, 0 })
    if flagPitch then m:setU16(ctrl + 0x90, flagPitch % 0x10000) end
  else
    m:setVec(gc + 0xB4, { 0, 40, 0 })
  end
  m:setVec(gc + 0xA8, self:placeEye(m:vec(gc + 0xB4), m:f32(ctrl + 0x74), m:s16(ctrl + 0x90), m:s16(ctrl + 0x92)))
  m:setU32(m:u32(Native.CURRENT) + m:u32(Native.SLOT) * 8 + 8, m:u32(0x84184148))
end
-- 8410FD54 / 8410FF0C / 84110098: the yaw turns 0xE8 a frame and the eye is
-- placed again; program 4 keeps the eye at height 10 or more (a double
-- compare), program 9 scales the eye's z by D_84188F98 (a double).
local function arenaOrbitTick(self, gc)
  local m = self.mem
  local ctrl = self:controllerFor(gc)
  m:setU32(Native.CURRENT, ctrl)
  m:setU16(ctrl + 0x92, (m:s16(ctrl + 0x92) + 0xE8) % 0x10000)
  m:setVec(gc + 0xA8, self:placeEye(m:vec(gc + 0xB4), m:f32(ctrl + 0x74), m:s16(ctrl + 0x90), m:s16(ctrl + 0x92)))
end
function Native:program4Setup(gc, actor) arenaOrbit(self, gc, actor, 0x222, -0x888, 500) end
function Native:program4Tick(gc)
  arenaOrbitTick(self, gc)
  if self.mem:f32(gc + 0xAC) <= 10 then self.mem:setF32(gc + 0xAC, 10) end
end
function Native:program8Setup(gc, actor) arenaOrbit(self, gc, actor, 0x1C70, nil, self.mem:f32(0x84188F90)) end
function Native:program8Tick(gc) arenaOrbitTick(self, gc) end
function Native:program9Setup(gc, actor) arenaOrbit(self, gc, actor, 0x9F4, -0x9F4, self.mem:f32(0x84188F94)) end
function Native:program9Tick(gc)
  arenaOrbitTick(self, gc)
  local m = self.mem
  local scale = self:const64(0x84188F98)
  m:setF32(gc + 0xB0, f32(m:f32(gc + 0xB0) * scale))
end

-- 841104E4(gc, actor): program 12's setup: 84120960, then 8410C934 with the
-- controller's shot; the slot empties.
function Native:program12Setup(gc, actor)
  local m = self.mem
  m:setU32(Native.CURRENT, self:controllerFor(gc))
  self:resetShotScaled(gc, actor, 0x84189C4C, 0x84189C54)
  self:shot(gc, actor, m:s16(m:u32(Native.CURRENT) + 0x98))
  m:setU32(m:u32(Native.CURRENT) + m:u32(Native.SLOT) * 8 + 8, m:u32(0x84184148))
end

-- 84120E14(actor) (fork C): +0x7EA = 0, the other actor home and shown and
-- reset (84120700), this actor hidden (8411EE74), the jolt ends.
function Native:resetOverShoulder(actor)
  local m = self.mem
  local other = actor == m:u32(Native.PLAYER) and m:u32(Native.ENEMY) or m:u32(Native.PLAYER)
  m:setU16(actor + 0x7EA, 0)
  if self.onActorHome then self.onActorHome(other) end
  m:setU8(actor + 1, bit.band(m:u8(actor + 1), 0xFE))
  m:setU8(other + 1, bit.bor(m:u8(other + 1), 1))
  if self.onActorReset then self.onActorReset(other) end
  self:setJolt(0)
end

-- 8410ED98(gc, actor): the over-the-shoulder pose: goal FOV 35 (now too),
-- fraction 0; the eye 160 behind the actor's side at its height; the target
-- at the actor's offset turned by the other's facing, over the other; the
-- target height by how the two heights compare (+-20 apart); the look point
-- = target; the secondary pose from the eye to it (80037120).
function Native:overShoulder(gc, actor)
  local m = self.mem
  local Memory = require("mods.STADIUM2_IMPORTER.lib.stadium2_native_memory")
  local other = actor == m:u32(Native.PLAYER) and m:u32(Native.ENEMY) or m:u32(Native.PLAYER)
  local ctrl = self:controllerFor(gc)
  m:setU32(Native.CURRENT, ctrl)
  m:setF32(ctrl + 0x88, 35)
  m:setF32(gc + 0x2C, m:f32(ctrl + 0x88))
  m:setF32(ctrl + 0x44, 0)
  local sign = actor == m:u32(Native.PLAYER) and 1 or -1
  local ex = f32(sign * -160)
  m:setVec(gc + 0xA8, { ex, m:f32(actor + 0x638), 0 })
  local ox, oz = self:rotateOffset(m:vec(actor + 0x634), m:s16(other + 0x20))
  local tx = f32(ox + m:f32(other + 0x24))
  local tz = f32(oz + m:f32(other + 0x2C))
  local hA = f32(m:f32(actor + 0x638) + m:f32(actor + 0x28))
  local hB = f32(m:f32(other + 0x638) + m:f32(other + 0x28))
  local otherFlags = m:u16(m:u32(Native.RECORD) + self:side(other) * 16 + 0x12)
  if bit.band(otherFlags, 4) ~= 0 then hB = 0 end
  local d = f32(hA - hB)
  local ty
  if d <= -20 then
    ty = f32(m:f32(actor + 0x28) - m:f32(actor + 0x638))
    if ty < 10 then ty = 10 end
    m:setVec(gc + 0xB4, { tx, ty, tz })
    local o638 = m:f32(other + 0x638)
    ty = f32(f32(f32(m:f32(other + 0x28) + o638) + f32(o638 * m:f32(0x84188F70))) - m:f32(other + 0x650))
  elseif 20 <= d then
    ty = f32(m:f32(actor + 0x28) + f32(m:f32(actor + 0x638) * 1.5))
    m:setVec(gc + 0xB4, { tx, ty, tz })
    local o638 = m:f32(other + 0x638)
    ty = f32(f32(f32(m:f32(other + 0x28) + o638) - f32(o638 * m:f32(0x84188F74))) - m:f32(other + 0x650))
    if m:s16(actor + 0x1A) == 0xD0 then ty = f32(f32(o638 * m:f32(0x84188F78)) + ty) end
  else
    ty = f32(f32(m:f32(other + 0x28) + m:f32(other + 0x638)) - m:f32(other + 0x650))
    m:setVec(gc + 0xB4, { tx, ty, tz })
  end
  if bit.band(otherFlags, 4) ~= 0 then ty = 10 end
  ctrl = m:u32(Native.CURRENT)
  m:setVec(ctrl + 0x50, { tx, ty, tz })
  local dist, pitch, yaw = self:angleTo(m:vec(gc + 0xA8), { tx, ty, tz })
  m:setF32(ctrl + 0x40, dist); m:setU16(ctrl + 0x3C, pitch % 0x10000); m:setU16(ctrl + 0x3E, yaw % 0x10000)
end

-- 8411047C(gc, actor): program 14's setup: 84120E14, 8410ED98; the slot
-- empties.
function Native:program14Setup(gc, actor)
  local m = self.mem
  m:setU32(Native.CURRENT, self:controllerFor(gc))
  self:resetOverShoulder(actor)
  self:overShoulder(gc, actor)
  m:setU32(m:u32(Native.CURRENT) + m:u32(Native.SLOT) * 8 + 8, m:u32(0x84184148))
end

-- 8410F0D0(gc): program 14's tick: +0x44 eases to 0.3 at 0.005, the target
-- height eases to the look point's (+0x54) at +0x44; with the event timer
-- under 0x29 and the height within D_84188F80 (a double) of it, the timer
-- ends and the slot empties.
function Native:program14Tick(gc)
  local m = self.mem
  local Memory = require("mods.STADIUM2_IMPORTER.lib.stadium2_native_memory")
  local ctrl = self:controllerFor(gc)
  m:setU32(Native.CURRENT, ctrl)
  m:setF32(ctrl + 0x44, Native.ease(m:f32(ctrl + 0x44), Memory.wordFloat(0x3E99999A), Memory.wordFloat(0x3BA3D70A)))
  ctrl = m:u32(Native.CURRENT)
  m:setF32(gc + 0xB8, Native.ease(m:f32(gc + 0xB8), m:f32(ctrl + 0x54), m:f32(ctrl + 0x44)))
  ctrl = m:u32(Native.CURRENT)
  local diff = f32(m:f32(gc + 0xB8) - m:f32(ctrl + 0x54))
  if m:u16(m:u32(Native.RECORD) + Native.TIMER) < 0x29 then
    if diff < self:const64(0x84188F80) then
      self:setTimer(0)
      m:setU32(m:u32(Native.CURRENT) + m:u32(Native.SLOT) * 8 + 8, m:u32(0x84184148))
    end
  end
end

-- ------------------------------------------------ the victory (family 30)

-- 8411D2E4(actor), camera part (event 0x67 on the winner, 8413D2E4): the
-- timer 0x154, the winner shown and the other hidden, +0x7EA = 0, program 24.
function Native:victoryState(actor)
  local m = self.mem
  local other = actor == m:u32(Native.PLAYER) and m:u32(Native.ENEMY) or m:u32(Native.PLAYER)
  self:setTimer(0x154)
  m:setU8(actor + 1, bit.bor(m:u8(actor + 1), 1))
  m:setU8(other + 1, bit.band(m:u8(other + 1), 0xFE))
  m:setU16(actor + 0x7EA, 0)
  self:setProgram(actor, 0x18)
end

-- 8411D388(actor) (fork C), on the actor's frame counter: 0: once the eye
-- is within 1.75 of the secondary pose around the target (800371B4 from
-- D_841904DC with +0x40 / +0x3C / +0x3E) and the frame is 6 or more,
-- program 7 (frame 0, substate 1); 1: at frame 50 the timer ends (2).
function Native:victoryFrame(actor, substate)
  local m = self.mem
  local ctrl = m:u32(Native.CONTROLLER0)
  if substate == 0 then
    local p = self:placeEye(m:vec(Native.VIEW0 + 0xB4), m:f32(ctrl + 0x40), m:s16(ctrl + 0x3C), m:s16(ctrl + 0x3E))
    local d = self:angleTo(m:vec(Native.VIEW0 + 0xA8), p)
    if d <= 1.75 and m:s16(actor + 0x7E8) >= 6 then
      m:setU16(actor + 0x7E8, 0)
      self:setProgram(actor, 7)
      return 1
    end
    return 0
  elseif substate == 1 then
    if m:s16(actor + 0x7E8) == 50 then self:setTimer(0); return 2 end
    return 1
  end
  return substate
end

-- 8410F9FC(gc, actor): program 24's setup: shot 0x23 for species 0x5F and
-- 0xF9, else 0x22 (8410C934), FOV 70; the slot empties.
function Native:program24Setup(gc, actor)
  local m = self.mem
  local ctrl = self:controllerFor(gc)
  m:setU32(Native.CURRENT, ctrl)
  local species = m:s16(actor + 0x1A)
  m:setU16(ctrl + 0x98, (species == 0x5F or species == 0xF9) and 0x23 or 0x22)
  self:shot(gc, actor, m:s16(m:u32(Native.CURRENT) + 0x98))
  m:setF32(gc + 0x2C, 70)
  m:setU32(m:u32(Native.CURRENT) + m:u32(Native.SLOT) * 8 + 8, m:u32(0x84184148))
end

-- 8410FABC(gc, actor): program 24's tick: the FOV eases to 45 at 0.02, then
-- 8410E73C.
function Native:program24Tick(gc, actor)
  local Memory = require("mods.STADIUM2_IMPORTER.lib.stadium2_native_memory")
  self.mem:setU32(Native.CURRENT, self:controllerFor(gc))
  self.mem:setF32(gc + 0x2C, Native.ease(self.mem:f32(gc + 0x2C), 45, Memory.wordFloat(0x3CA3D70A)))
  self:poseAroundLook(gc, actor)
end

-- 84116808(actor)'s substates, camera part (Beat Up), on the actor's frame
-- counter: 1: +0x618 = the record's move, +0x7EA = 0 (2). 2 (84116604, once
-- 84113430 lets it run): the frame counter from +0x61B (less one when
-- +0x61A is 0), timer 0x258 (3). 3 (841166C4): at frame +0x619 the FOV goal
-- 60 on shot 4 and the jolt ends; with +0x61A 0 the animation's end, else
-- frame +0x61A, resets the kind and ends the timer (4).
function Native:beatUpFrame(actor, substate, finished)
  local m = self.mem
  if substate == 1 then
    m:setU8(actor + 0x618, m:u8(m:u32(Native.RECORD) + 8))
    m:setU16(actor + 0x7EA, 0)
    return 2
  elseif substate == 2 then
    local start = m:u8(actor + 0x61B)
    if m:u8(actor + 0x61A) == 0 then start = start - 1 end
    m:setU16(actor + 0x7E8, start % 0x10000)
    self:setTimer(0x258)
    return 3
  elseif substate == 3 then
    local ctrl = m:u32(Native.CONTROLLER0)
    if m:u8(actor + 0x619) == m:s16(actor + 0x7E8) then
      if m:s16(ctrl + 0x98) == 4 then m:setF32(ctrl + 0x88, 60) end
      self:setJolt(0)
    end
    local limit = m:u8(actor + 0x61A)
    if (limit == 0 and finished) or (limit ~= 0 and limit == m:s16(actor + 0x7E8)) then
      self:kindReset(actor)
      m:setU16(actor + 0x7E8, 0)
      self:setTimer(0)
      return 4
    end
    return 3
  end
  return substate
end

-- ------------------------------------------------ weather (family 28)

-- 8410FB0C(gc, actor): program 29 (weather), one shot: FOV 45, 84120960
-- (84120AC4's reset with the scales D_84189C4C / D_84189C54), the pose
-- 0x222 / 0 at distance 500, the target at height 180 when either side's
-- flags have bit 1 (else 40), the eye at (-323, 394, 268); its slot empties.
function Native:program29Setup(gc, actor)
  local m = self.mem
  m:setU32(Native.CURRENT, self:controllerFor(gc))
  m:setF32(gc + 0x2C, 45)
  self:resetShotScaled(gc, actor, 0x84189C4C, 0x84189C54)
  local ctrl = m:u32(Native.CURRENT)
  m:setU16(ctrl + 0x90, 0x222)
  m:setU16(ctrl + 0x92, 0)
  m:setF32(ctrl + 0x74, 500)
  local record = m:u32(Native.RECORD)
  local high = bit.band(m:u16(record + 0x12), 2) ~= 0 or bit.band(m:u16(record + 0x22), 2) ~= 0
  m:setVec(gc + 0xB4, { 0, high and 180 or 40, 0 })
  m:setVec(gc + 0xA8, { -323, 394, 268 })
  m:setU32(m:u32(Native.CURRENT) + m:u32(Native.SLOT) * 8 + 8, m:u32(0x84184148))
end

-- 841193E0(actor), camera part (weather, events 0x30-0x35 on battler 0):
-- from the state's frame 2, program 29 on the actor unless the shot is 0x21.
function Native:weatherState(actor)
  local m = self.mem
  local code = m:u16(m:u32(Native.RECORD) + 4)
  if code < 0x30 or code > 0x35 then return end
  if m:s16(m:u32(Native.CONTROLLER0) + 0x98) ~= 0x21 then self:setProgram(actor, 0x1D) end
end

-- 8411957C(actor), camera part (fork C, BattleAnim_Dispatch_199; event 0x36,
-- fully paralysed): shot 0 and program 0 on the actor. Skipped while +0x7F6
-- is 1.
function Native:paralysisState(actor)
  local m = self.mem
  if m:s8(actor + 0x7F6) == 1 then return end
  if m:u16(m:u32(Native.RECORD) + 4) ~= 0x36 then return end
  m:setU16(m:u32(Native.CONTROLLER0) + 0x98, 0)
  self:setProgram(actor, 0)
end

-- ------------------------------------------------ recall (family 18)

Native.RECALL_SHOTS = 0x84183C7C -- D_84183C7C (4): the recall shots

-- 8411ABAC(actor), camera part (fork C; events 0x1E / 0x1F asleep / 0x20
-- frozen, queued by 84124C10 on a switch-out): a random recall shot and
-- program 27 on the outgoing actor; a frozen one gets shot 0x11 instead.
function Native:recallState(actor)
  local m = self.mem
  local ctrl = m:u32(Native.CONTROLLER0)
  m:setU16(ctrl + 0x98, m:u16(Native.RECALL_SHOTS + (self:drawRandom() % 4) * 2))
  self:setProgram(actor, 0x1B)
  if m:u16(m:u32(Native.RECORD) + 4) == 0x20 then
    m:setU16(m:u32(Native.CONTROLLER0) + 0x98, 0x11)
  end
end

-- 84110320(gc, actor): program 27's setup: 84120BB4, the eye held
-- (8410CC90); then its slot empties.
function Native:program27Setup(gc, actor)
  local m = self.mem
  m:setU32(Native.CURRENT, self:controllerFor(gc))
  self:resetShot(gc, actor)
  self:holdEye(gc)
  m:setU32(m:u32(Native.CURRENT) + m:u32(Native.SLOT) * 8 + 8, m:u32(0x84184148))
end

-- 84110860(gc, actor): program 27's tick: FOV ease; the follow while the
-- target is above height 10 (else it is held at 10); the secondary pose at
-- the actor's facing; 8410B60C around the target.
function Native:program27Tick(gc, actor)
  local m = self.mem
  local Memory = require("mods.STADIUM2_IMPORTER.lib.stadium2_native_memory")
  m:setU32(Native.CURRENT, self:controllerFor(gc))
  local ctrl = m:u32(Native.CURRENT)
  m:setF32(gc + 0x2C, Native.ease(m:f32(gc + 0x2C), m:f32(ctrl + 0x88), Memory.wordFloat(0x3D4CCCCD)))
  if 10 < m:f32(gc + 0xB8) then self:follow(gc, actor) else m:setF32(gc + 0xB8, 10) end
  self:secondaryPose(actor, m:u32(Native.CURRENT), m:s16(actor + 0x20))
  self:towardPoseSlow(gc, m:u32(Native.CURRENT), m:vec(gc + 0xB4))
end

-- ------------------------------------------------ send-out (family 12)

Native.SEND_OUT_SHOTS = 0x84183AA8 -- D_84183AA8 (2): the send-out shots

-- 84120310 (BattleAnim_StepToS16): step the s16 at `address` toward
-- `goal` by |step|, landing on it exactly.
function Native:stepToS16(address, goal, step)
  local m = self.mem
  goal, step = s16(goal), s16(step)
  if step < 0 then step = s16(-step) end
  local d = s16(goal - m:s16(address))
  if d > 0 then
    d = s16(d - step)
    m:setU16(address, d >= 0 and goal - d or goal)
  else
    d = s16(d + step)
    m:setU16(address, d > 0 and goal or goal - d)
  end
end

-- 8410C544(gc, actor, shot): the send-out's opening shot: 84120BB4, the
-- shot's anchor (8410B974), then the eye 50 from (+-150, 20, 0) on the
-- actor's side at the shot's pitch and turned yaw; FOV 45.
function Native:sendOutShot(gc, actor, shot)
  local m = self.mem
  local sign = 1
  m:setU32(Native.CURRENT, self:controllerFor(gc))
  self:resetShot(gc, actor)
  local yaw
  if self:inList(m:u8(actor + 0x61F), Native.KIND_FACING, 8) then yaw = s16(self:sideFacing(actor))
  else yaw = m:s16(actor + 0x20) end
  if yaw < 0 then sign = -1 end
  local ctrl = m:u32(Native.CURRENT)
  m:setF32(ctrl + 0x44, 0)
  self:anchor(gc, actor, yaw, shot, 1)
  ctrl = m:u32(Native.CURRENT)
  local row = Native.SHOTS + shot * 0x1C
  m:setU16(ctrl + 0x90, m:u16(row))
  m:setU16(ctrl + 0x92, (m:s16(row + 2) * sign + yaw) % 0x10000)
  m:setF32(ctrl + 0x74, f32(m:f32(ctrl + 0x74) * m:f32(row + 4)))
  m:setF32(ctrl + 0x88, m:f32(row + 0x10))
  m:setF32(gc + 0x2C, 45)
  m:setF32(ctrl + 0x88, 45)
  local center = { f32(f32(sign) * -150), 20, 0 }
  m:setVec(gc + 0xB4, center)
  m:setVec(ctrl + 0x50, center)
  m:setF32(ctrl + 0x74, 50)
  m:setVec(gc + 0xA8, self:placeEye(center, 50, m:s16(ctrl + 0x90), m:s16(ctrl + 0x92)))
  m:setVec(ctrl + 0x68, m:vec(gc + 0xA8))
end

-- 8410C720(gc, actor, distance, height, rate, pitchStep): the send-out's
-- per-frame move: the pitch steps toward -0xE38, the target height eases
-- to `height`, and the eye closes on the pose `distance` from the look
-- point (+0x44 easing to 0.15 at 0.03).
function Native:sendOutPose(gc, distance, height, rate, pitchStep)
  local m = self.mem
  local Memory = require("mods.STADIUM2_IMPORTER.lib.stadium2_native_memory")
  m:setU32(Native.CURRENT, self:controllerFor(gc))
  local ctrl = m:u32(Native.CURRENT)
  self:stepToS16(ctrl + 0x3C, -0xE38, pitchStep)
  m:setF32(gc + 0xB8, Native.ease(m:f32(gc + 0xB8), height, f32(m:f32(ctrl + 0x44) * rate)))
  m:setF32(ctrl + 0x54, m:f32(gc + 0xB8))
  m:setF32(ctrl + 0x44, Native.ease(m:f32(ctrl + 0x44), Memory.wordFloat(0x3E19999A), Memory.wordFloat(0x3CF5C28F)))
  local goal = self:placeEye(m:vec(ctrl + 0x50), distance, m:s16(ctrl + 0x3C), m:s16(ctrl + 0x3E))
  local from = m:vec(gc + 0xA8)
  local d, pitch, yaw = self:angleTo(from, goal)
  m:setVec(gc + 0xA8, self:placeEye(from, f32(m:f32(ctrl + 0x44) * d), pitch, yaw))
end

-- 8411BB04(actor), camera part (the send-out's first state): unless the
-- shot is 0x21, controller 0 is emptied and the opening shot (0 or 6 at
-- random) placed.
function Native:sendOutStart(actor)
  local m = self.mem
  local ctrl = m:u32(Native.CONTROLLER0)
  if m:s16(ctrl + 0x98) == 0x21 then return end
  self:clearProgram()
  local shot = m:u16(Native.SEND_OUT_SHOTS + (self:drawRandom() % 2) * 2)
  m:setU16(ctrl + 0x98, shot)
  self:sendOutShot(m:u32(ctrl), actor, s16(shot))
end

-- 8411BCC8's substate 2, camera part: one frame of the send-out camera at
-- the actor's frame counter `frame` (+0x7E8, 1 on the first frame). The
-- shot is swapped (0 <-> 6) for the frame's work: the secondary pose on
-- frame 1, the rise toward (50, 70) and from frame 0x3E the pull back to
-- (75, 30). From frame 0x61 the swap stays, program 26 takes over (unless
-- the shot is 0x21) and true is returned.
function Native:sendOutFrame(actor, frame)
  local m = self.mem
  local ctrl = m:u32(Native.CONTROLLER0)
  local gc = m:u32(ctrl)
  local saved = m:s16(ctrl + 0x98)
  m:setU16(ctrl + 0x98, saved == 0 and 6 or 0)
  if frame == 1 then
    self:secondaryPose(actor, ctrl, m:s16(actor + 0x20))
    m:setU16(m:u32(Native.CONTROLLER0) + 0x3C, 0)
  end
  if frame == 0x3E then m:setF32(m:u32(Native.CONTROLLER0) + 0x44, 0) end
  if frame < 0x3E then self:sendOutPose(gc, 50, 70, 0, 0)
  else self:sendOutPose(gc, 75, 30, 0.5, 0x1C71) end
  ctrl = m:u32(Native.CONTROLLER0)
  m:setU16(ctrl + 0x98, saved)
  if frame < 0x61 then return false end
  if m:s16(ctrl + 0x98) ~= 0x21 then
    m:setU16(actor + 0x7EA, 0)
    m:setU16(ctrl + 0x98, m:s16(ctrl + 0x98) ~= 0 and 0 or 6)
    self:setProgram(actor, 0x1A)
  end
  m:setU16(actor + 0x7F4, 0)
  return true
end

-- 84110264(gc, actor): program 26's setup: the controller's shot
-- (8410C934), the secondary pose at the actor's facing, the eye at half
-- the distance level with the look point, pitch 0; then its slot empties.
function Native:program26Setup(gc, actor)
  local m = self.mem
  m:setU32(Native.CURRENT, self:controllerFor(gc))
  self:shot(gc, actor, m:s16(m:u32(Native.CURRENT) + 0x98))
  local ctrl = m:u32(Native.CURRENT)
  self:secondaryPose(actor, ctrl, m:s16(actor + 0x20))
  ctrl = m:u32(Native.CURRENT)
  m:setVec(gc + 0xA8, self:placeEye(m:vec(ctrl + 0x50), f32(m:f32(ctrl + 0x74) / 2), 0, m:s16(ctrl + 0x92)))
  m:setU16(m:u32(Native.CURRENT) + 0x3C, 0)
  m:setU32(m:u32(Native.CURRENT) + m:u32(Native.SLOT) * 8 + 8, m:u32(0x84184148))
end

-- 8410C840(gc, actor, ctrl, center): the pitch steps toward 0xAAA by 0x64,
-- +0x44 eases to 0.2 at 0.06, and the eye closes on the pose around
-- `center`; it stays at height 5 or more.
function Native:towardPoseRising(gc, ctrl, center)
  local m = self.mem
  local Memory = require("mods.STADIUM2_IMPORTER.lib.stadium2_native_memory")
  self:stepToS16(ctrl + 0x3C, 0xAAA, 0x64)
  m:setF32(ctrl + 0x44, Native.ease(m:f32(ctrl + 0x44), Memory.wordFloat(0x3E4CCCCD), Memory.wordFloat(0x3D75C28F)))
  local goal = self:placeEye(center, m:f32(ctrl + 0x40), m:s16(ctrl + 0x3C), m:s16(ctrl + 0x3E))
  local from = m:vec(gc + 0xA8)
  local d, pitch, yaw = self:angleTo(from, goal)
  m:setVec(gc + 0xA8, self:placeEye(from, f32(m:f32(ctrl + 0x44) * d), pitch, yaw))
  if m:f32(gc + 0xAC) <= 5 then m:setF32(gc + 0xAC, 5) end
end

-- 84110910(gc, actor): program 26's tick: FOV ease, follow, 8410C840.
function Native:program26Tick(gc, actor)
  local m = self.mem
  local Memory = require("mods.STADIUM2_IMPORTER.lib.stadium2_native_memory")
  m:setU32(Native.CURRENT, self:controllerFor(gc))
  local ctrl = m:u32(Native.CURRENT)
  m:setF32(gc + 0x2C, Native.ease(m:f32(gc + 0x2C), m:f32(ctrl + 0x88), Memory.wordFloat(0x3D4CCCCD)))
  self:follow(gc, actor)
  self:towardPoseRising(gc, m:u32(Native.CURRENT), m:vec(gc + 0xB4))
end

-- 8410B578(amount): start (or stop) the hit jolt on controller 0.
function Native:setJolt(amount)
  local c0 = self.mem:u32(Native.CONTROLLER0)
  self.mem:setF32(c0 + 0x8C, amount)
  self.mem:setU16(c0 + 0x96, 0)
end

-- 84120BB4(gc, actor): the camera reset of a new shot. Actor presentation
-- (8411EF2C status visibility, 84120700 home pose and status particles) is
-- the battle scene's, through callbacks.
function Native:resetShot(gc, actor)
  local m = self.mem
  m:setU16(actor + 0x7EA, 0)
  m:setVec(gc + 0xC0, { 0, 1, 0 })
  if self.onStatusVisibility then self.onStatusVisibility(actor) end
  if self.onActorReset then
    self.onActorReset(m:u32(Native.PLAYER))
    self.onActorReset(m:u32(Native.ENEMY))
  end
  self:setJolt(0)
end

Native.SLOT = 0x841911EC -- D_841911EC: the handler slot being run
Native.NOOP = 0x8411123C -- the empty handler (D_84184148)

-- 84110394(gc, actor): program 0's one-shot handler: reset, set up the
-- controller's shot, then empty its own slot.
function Native:program0Setup(gc, actor)
  local m = self.mem
  local ctrl = self:controllerFor(gc)
  m:setU32(Native.CURRENT, ctrl)
  self:resetShot(gc, actor)
  self:shot(gc, actor, m:s16(m:u32(Native.CURRENT) + 0x98))
  m:setU32(m:u32(Native.CURRENT) + m:u32(Native.SLOT) * 8 + 8, m:u32(0x84184148))
end

-- ------------------------------------------------------------ programs

Native.PROGRAMS = 0x8418414C -- D_8418414C: 32 programs of seven handlers

-- Ported handlers by ROM address: handler(self, gc, owner).
Native.HANDLERS = {
  [0x8411123C] = function() end,
  [0x84110394] = function(self, gc, owner) return self:program0Setup(gc, owner) end,
  [0x84110718] = function(self, gc, owner) return self:program0Tick(gc, owner) end,
  [0x84110F64] = function(self, gc, owner) return self:program1Tick(gc, owner) end,
  [0x84111048] = function(self, gc, owner) return self:program3Setup(gc, owner) end,
  [0x841110C4] = function(self, gc, owner) return self:program3Tick(gc, owner) end,
  [0x8410D040] = function(self, gc) return self:eyeRise(gc) end,
  [0x841105CC] = function(self, gc, owner) return self:program5Setup(gc, owner) end,
  [0x84110980] = function(self, gc, owner) return self:program13Tick(gc, owner) end,
  [0x8410CF80] = function(self, gc, owner) return self:riseToMarker(gc, owner) end,
  [0x841111D8] = function(self, gc, owner) return self:program10Setup(gc, owner) end,
  [0x8410ED30] = function(self, gc, owner) return self:program10Tick(gc, owner) end,
  [0x84110408] = function(self, gc, owner) return self:program11Setup(gc, owner) end,
  [0x841107D8] = function(self, gc, owner) return self:program11Tick(gc, owner) end,
  [0x84110264] = function(self, gc, owner) return self:program26Setup(gc, owner) end,
  [0x84110910] = function(self, gc, owner) return self:program26Tick(gc, owner) end,
  [0x84110320] = function(self, gc, owner) return self:program27Setup(gc, owner) end,
  [0x84110860] = function(self, gc, owner) return self:program27Tick(gc, owner) end,
  [0x8410FB0C] = function(self, gc, owner) return self:program29Setup(gc, owner) end,
  [0x8410E8E4] = function(self, gc, owner) return self:program7Tick(gc, owner) end,
  [0x84110640] = function(self, gc, owner) return self:program6Setup(gc, owner) end,
  [0x841110EC] = function(self, gc, owner) return self:program2Setup(gc, owner) end,
  [0x84111170] = function(self, gc, owner) return self:program2Tick(gc, owner) end,
  [0x84110558] = function(self, gc, owner) return self:program15Setup(gc, owner) end,
  [0x8410F9FC] = function(self, gc, owner) return self:program24Setup(gc, owner) end,
  [0x8410FABC] = function(self, gc, owner) return self:program24Tick(gc, owner) end,
  [0x8410FC28] = function(self, gc, owner) return self:program4Setup(gc, owner) end,
  [0x8410FD54] = function(self, gc, owner) return self:program4Tick(gc, owner) end,
  [0x8410FDEC] = function(self, gc, owner) return self:program8Setup(gc, owner) end,
  [0x8410FF0C] = function(self, gc, owner) return self:program8Tick(gc, owner) end,
  [0x8410FF6C] = function(self, gc, owner) return self:program9Setup(gc, owner) end,
  [0x84110098] = function(self, gc, owner) return self:program9Tick(gc, owner) end,
  [0x841104E4] = function(self, gc, owner) return self:program12Setup(gc, owner) end,
  [0x8411047C] = function(self, gc, owner) return self:program14Setup(gc, owner) end,
  [0x8410F0D0] = function(self, gc, owner) return self:program14Tick(gc, owner) end,
  [0x8410F6AC] = function(self, gc, owner) return self:program21Setup(gc, owner) end,
  [0x8410F724] = function(self, gc, owner) return self:program21Tick(gc, owner) end,
  [0x8410F78C] = function(self, gc, owner) return self:program22Setup(gc, owner) end,
  [0x8410F844] = function(self, gc, owner) return self:program22Tick(gc, owner) end,
  [0x841111B0] = function(self, gc, owner) return self:program6Tick(gc, owner) end,
  [0x8410F1A8] = function(self, gc, owner) return self:program18Setup(gc, owner) end,
  [0x8410F3E8] = function(self, gc, owner) return self:program18Tick(gc, owner) end,
  [0x8411100C] = function(self, gc) return self:program25Tick(gc) end,
}

local function loadProgram(self, global, owner, program)
  local m = self.mem
  local ctrl = m:u32(global)
  local row = Native.PROGRAMS + program * 0x1C
  for i = 0, 6 do m:setU32(ctrl + 8 + i * 8, m:u32(row + i * 4)) end
  for i = 0, 6 do m:setU32(ctrl + 4 + i * 8, owner) end
end

-- 84111348(owner, program) / 841113F8: give controller 0 / 1 a program.
function Native:setProgram(owner, program) loadProgram(self, Native.CONTROLLER0, owner, program) end
function Native:setProgram1(owner, program) loadProgram(self, Native.CONTROLLER1, owner, program) end

-- 84111248 / 841112C8: empty every slot of controller 0 / 1.
local function clear(self, global)
  local m = self.mem
  local ctrl = m:u32(global)
  for i = 0, 6 do m:setU32(ctrl + 8 + i * 8, m:u32(0x84184148)) end
end
function Native:clearProgram() clear(self, Native.CONTROLLER0) end
function Native:clearProgram1() clear(self, Native.CONTROLLER1) end

-- A handler that is not ported yet is reported once and skipped: an
-- unsupported native callback never becomes a guessed camera move.
function Native:runHandler(handler, gc, owner)
  local fn = Native.HANDLERS[handler]
  if fn then return fn(self, gc, owner) end
  self.missing = self.missing or {}
  if not self.missing[handler] then
    self.missing[handler] = true
    if self.warn then pcall(self.warn, ("battle camera handler %08X is not ported yet"):format(handler)) end
  end
end

-- ------------------------------------------------------------ director

-- 841119CC(ctrl, selector): selectors 0x28..0x32 pick a random shot from
-- their list (jtbl_84188FC0; 8003570C, then mod the list length, or & 3 for
-- the lists of four); any other value is the shot itself.
Native.SHOT_LISTS = {
  [0x28] = { 0x84183BDC, 6 }, [0x29] = { 0x84183BE8, 4 }, [0x2A] = { 0x84183BF0, 6 },
  [0x2B] = { 0x84183BFC, 4 }, [0x2C] = { 0x84183C04, 3 }, [0x2D] = { 0x84183C0C, 3 },
  [0x2E] = { 0x84183C14, 3 }, [0x2F] = { 0x84183C1C, 3 }, [0x30] = { 0x84183C24, 3 },
  [0x31] = { 0x84183C2C, 4 }, [0x32] = { 0x84183C34, 3 },
}
function Native:chooseShot(ctrl, selector)
  local m = self.mem
  selector = selector % 0x10000
  local list = Native.SHOT_LISTS[selector]
  if list then
    selector = m:u16(list[1] + (self:drawRandom() % list[2]) * 2)
  end
  m:setU16(ctrl + 0x98, selector)
end

-- 8003570C through the injected source (options.random, returning the next
-- 32-bit LCG word): the camera never draws from the battle's RNG.
function Native:drawRandom()
  if not self.random then error("battle camera: no random source was injected", 2) end
  return self.random() % 0x100000000
end

-- D_841849B6: eight bytes per move: +0 the attack shot selector, +4 the
-- defender's hit shot selector.
Native.MOVE_SHOTS = 0x841849B6
Native.ATTACK_KIND_EXEMPT = 0x841839EC -- D_841839EC (3 species): no kind 0xC for move 0x6E
Native.HIT_KIND_MOVES = 0x84183A0C     -- D_84183A0C (5 moves): kind 0x10 when hit
local ATTACK_KINDS = { [0x39] = 0x0A, [0x42] = 0x04, [0x45] = 0x08, [0x60] = 0x0D,
  [0x61] = 0x06, [0x68] = 0x07, [0x7F] = 0x0E, [0xB9] = 0x19, [0xE5] = 0x13,
  [0x6B] = 0x09, [0xBB] = 0x1A, [0xC2] = 0x18 }

-- 84114804(actor), camera part: the attacker's shot from its move and the
-- actor kind (+0x61F). Skipped while +0x7EC bit 0 is set. (Its tail,
-- 841146D4, copies the move's dispatch-row bytes for the model animation
-- layer and is not part of the camera.)
function Native:attackShot(actor)
  local m = self.mem
  if bit.band(m:u16(actor + 0x7EC), 1) ~= 0 then return end
  local move = m:u8(actor + 0x618)
  self:chooseShot(m:u32(Native.CONTROLLER0), m:u16(Native.MOVE_SHOTS + move * 8))
  local kind = ATTACK_KINDS[move]
  if not kind and move == 0x6E and not self:inList(m:u16(actor + 0x1A), Native.ATTACK_KIND_EXEMPT, 6) then
    kind = 0x0C
  end
  m:setU8(actor + 0x61F, kind or 0xFF)
end

-- 84114A04(actor), camera part (fork C): after 84114804, load the attack
-- program on controller 0 unless the shot is 0x21: Fly (0x13) shot 14 with
-- program 5, Surf (0x39) 13, Waterfall (0x7F) 3, Rapid Spin (0xE5) 17,
-- otherwise 0.
local ATTACK_PROGRAMS = { [0x39] = 13, [0x7F] = 3, [0xE5] = 17 }
function Native:attackState(actor)
  local m = self.mem
  self:attackShot(actor)
  local ctrl = m:u32(Native.CONTROLLER0)
  if m:s16(ctrl + 0x98) == 0x21 then return end
  local move = m:u8(actor + 0x618)
  if move == 0x13 then
    m:setU16(ctrl + 0x98, 14)
    self:setProgram(actor, 5)
  else
    self:setProgram(actor, ATTACK_PROGRAMS[move] or 0)
  end
end

-- 84116BC0(actor): the defender's own motion row for the received move
-- (+0x2D4 + (move - 1) * 0x14: +7 the hit frame +0x619, +0xA the state's
-- length +0x61A, +8 +0x620, +0x10..+0x13 into +0x628 / +0x62A / +0x62C /
-- +0x661; +0x61C / +0x61D from the record's +0x13DA / +0x13DB), then the
-- actor kind and hit shot by the event code (u16 battle record +4).
-- Skipped while +0x7EC bit 0 is set.
function Native:hitShot(actor)
  local m = self.mem
  if bit.band(m:u16(actor + 0x7EC), 1) ~= 0 then return end
  local move = m:u8(actor + 0x618)
  local motion = m:u32(actor + 0x2D4)
  local row = motion + move * 0x14
  m:setU8(actor + 0x619, m:u8(row - 0xD))
  m:setU8(actor + 0x61A, m:u8(row - 0xA))
  m:setU8(actor + 0x620, m:u8(row - 0xC))
  m:setU8(actor + 0x61C, m:u8(motion + 0x13DA))
  m:setU8(actor + 0x61D, m:u8(motion + 0x13DB))
  m:setU16(actor + 0x628, m:u8(row - 4))
  m:setU16(actor + 0x62A, m:u8(row - 3))
  m:setU16(actor + 0x62C, m:u8(row - 2))
  m:setU8(actor + 0x661, m:u8(row - 1))
  local kind
  if move == 0x17 or move == 0x22 then kind = 0x0F
  elseif move == 0xCD then kind = 0x12
  elseif self:inList(move, Native.HIT_KIND_MOVES, 0xA) then kind = 0x10
  elseif move == 0x12 or move == 0x2E then kind = 0x15
  else kind = 0xFF end
  m:setU8(actor + 0x61F, kind)
  local ctrl = m:u32(Native.CONTROLLER0)
  local code = m:u16(m:u32(Native.RECORD) + 4)
  if code == 0x10 or code == 0x14 or code == 0x4B then
    self:chooseShot(ctrl, 0x28)
  elseif code == 0x11 then
    m:setU16(ctrl + 0x98, m:u16(0x84183BDC + (self:drawRandom() % 6) * 2))
  elseif code == 0x12 or code == 0x15 then
    m:setU16(ctrl + 0x98, 3)
  elseif code == 0x13 then
    m:setU16(ctrl + 0x98, 0x16)
  else
    self:chooseShot(ctrl, m:u16(Native.MOVE_SHOTS + 4 + move * 8))
  end
end

-- 841170A0(actor), camera part: 84116BC0, then program 1 on controller 0
-- unless the shot is 0x21 (8411744C).
function Native:hitState(actor)
  self:hitShot(actor)
  if self.mem:s16(self.mem:u32(Native.CONTROLLER0) + 0x98) ~= 0x21 then self:setProgram(actor, 1) end
end

-- ------------------------------------------------ the hit's follow-up (family 4)

-- 841170A0 (US asm), after 84116BC0: the frame counter and substate 0, then
-- the state's length +0x61A by event code, set through 84116B40:
--   0x0A: 0x3C while the side's flags have bit 1 or 2, else 84116EB4: the
--         model's hit animation length (0xFE, model +0x44 -> +0xA), at
--         least 0x50, or 0x3C for results 2 and 5;
--   0x0C, 0x0E: the hit animation's length; 0x0B, 0x0D, 0x0F, 0x11-0x13,
--   0x15, 0x3B: 0x3C; every other code (0x10, 0x14, ...): 0x46.
-- 84116B40 stores it as a byte, adds up to 40 frames past +0x620 when the
-- result (record +9) has bit 0x10, starts the counter at +0x619 - 1 when
-- +0x619 <= 0, sets the timer 0x258 and clears D_841911F8. A hit that is not
-- the last of a multi-hit move (record +0xB ~= +0xA for move effects 0x1D /
-- 0x4D (80062D20) or moves 0xFB / 0xA7) ends at 0x28. `frames` is the hit
-- animation's length; nil when unknown, and then a code that needs it
-- returns false (nothing is set).
Native.HIT_LENGTH_3C = { [0x0B] = true, [0x0D] = true, [0x0F] = true, [0x11] = true,
  [0x12] = true, [0x13] = true, [0x15] = true, [0x3B] = true }
function Native:hitLength(actor, frames)
  local m = self.mem
  local record = m:u32(Native.RECORD)
  local code = m:u16(record + 4)
  local flags = m:u16(record + self:side(actor) * 16 + 0x12)
  local result = m:u8(record + 9)
  local length
  if code == 0x0A then
    if bit.band(flags, 6) ~= 0 then length = 0x3C
    else
      if frames == nil then return false end
      length = frames < 0x50 and 0x50 or frames
      if bit.band(result, 7) == 2 or bit.band(result, 7) == 5 then length = 0x3C end
    end
  elseif code == 0x0C or code == 0x0E then
    if frames == nil then return false end
    length = frames
  elseif Native.HIT_LENGTH_3C[code] then length = 0x3C
  else length = 0x46 end
  m:setU8(actor + 0x7F6, 0)
  m:setU16(actor + 0x7E8, 0)
  -- 84116B40
  m:setU8(actor + 0x61A, length % 0x100)
  if bit.band(result, 0x10) ~= 0 then
    local over = m:u8(actor + 0x61A) - m:u8(actor + 0x620)
    if over < 40 then m:setU8(actor + 0x61A, (m:u8(actor + 0x61A) + 40 - over) % 0x100) end
  end
  local hitFrame = m:s8(actor + 0x619)
  if hitFrame <= 0 then m:setU16(actor + 0x7E8, (hitFrame - 1) % 0x10000) end
  self:setTimer(0x258)
  self.hpSettled = false -- D_841911F8
  return true
end

-- 80062D20(move) (fork C): the move's effect, D_8009782A[move * 6] for
-- moves 1..0xFB, else 0.
function Native:moveEffect(move)
  if move > 0 and move < 0xFC then return self.mem:u8(0x8009782A + move * 6) end
  return 0
end

-- 841170A0's tail (after program 1): a hit that is not the last of a
-- multi-hit move (effects 0x1D / 0x4D, moves 0xFB / 0xA7; record +0xB, the
-- hit, differs from +0xA, the count) ends at 0x28.
function Native:hitMultiLength(actor)
  local m = self.mem
  local record = m:u32(Native.RECORD)
  local move = m:u8(record + 8)
  local effect = self:moveEffect(move)
  if effect == 0x4D or effect == 0x1D or move == 0xFB or move == 0xA7 then
    if m:u8(record + 0xB) ~= m:u8(record + 0xA) then m:setU8(actor + 0x61A, 0x28) end
  end
end

-- 841175D4 (fork C): once the side's HP bar has nothing left to drain
-- (8413D358: D_8419521C[side * 24] == 0; `settled` is the host's bar) and
-- D_841911F8 is clear, the state ends 0x32 frames later if that is sooner.
function Native:hpSettledEnd(actor, settled)
  local m = self.mem
  if settled and not self.hpSettled then
    local at = m:s16(actor + 0x7E8) + 0x32
    if at < m:u8(actor + 0x61A) then m:setU8(actor + 0x61A, at % 0x100) end
    self.hpSettled = true
  end
end

-- 841170A0's camera part: 84116BC0 (row, kind, shot), the length, then
-- program 1 on the defender unless the shot is 0x21. Returns whether the
-- length was set (false: the hit animation's length is unknown).
function Native:hitStart(actor, frames)
  self:hitShot(actor)
  local known = self:hitLength(actor, frames)
  if self.mem:s16(self.mem:u32(Native.CONTROLLER0) + 0x98) ~= 0x21 then self:setProgram(actor, 1) end
  if known then self:hitMultiLength(actor) end
  return known
end

-- 84117648 (fork C): 841175D4, then at frame +0x61A (0xF: only +0x7F4
-- kept) +0x7F4 loses bits 0 and 1, and 84111BEC ends the state: the frame
-- counter 0, the timer 0, the kind reset (841206D0); then the counter
-- 0x12C and substate 1.
function Native:hitEnd(actor, settled)
  local m = self.mem
  self:hpSettledEnd(actor, settled)
  local length = m:u8(actor + 0x61A)
  if m:s16(actor + 0x7E8) ~= length then return end
  if length ~= 0xF then m:setU16(actor + 0x7F4, bit.band(m:u16(actor + 0x7F4), 0xFFFC)) end
  m:setU16(actor + 0x7E8, 0)
  self:setTimer(0)
  self:kindReset(actor)
  m:setU16(actor + 0x7E8, 0x12C)
  m:setU8(actor + 0x7F6, 1)
end

-- 84117744 (US asm): per-move lengths (Lock-On 0xC7: 0x78, Rollout 0xCD:
-- 0x5A, Whirlwind 0x12 / Roar 0x2E: 0x32, Spite 0xB4: 0x78); Foresight
-- (0xC1): 0x50, +0x619 = 0, and every 12 frames below 0x25 controller 0
-- takes shot D_84183C6C[frame / 12] with program 1.
function Native:hitMoveFrame(actor)
  local m = self.mem
  local move = m:u8(actor + 0x618)
  if move == 0xC7 then m:setU8(actor + 0x61A, 0x78) end
  if move == 0xCD then m:setU8(actor + 0x61A, 0x5A) end
  if move == 0x12 or move == 0x2E then m:setU8(actor + 0x61A, 0x32) end
  if move == 0xB4 then m:setU8(actor + 0x61A, 0x78) end
  if move == 0xC1 then
    m:setU8(actor + 0x61A, 0x50)
    m:setU8(actor + 0x619, 0)
    local frame = m:s16(actor + 0x7E8)
    if math.fmod(frame, 12) == 0 and frame < 0x25 then
      local index = frame >= 0 and math.floor(frame / 12) or -math.floor(-frame / 12)
      m:setU16(m:u32(Native.CONTROLLER0) + 0x98, m:u16(0x84183C6C + index * 2))
      self:setProgram(actor, 1)
    end
  end
end

-- 84117880 (fork C): the frame after the hit (+0x619 + 1), the camera jolt
-- by the result (record +9 & 7): 2 -> 10, 0 -> 15, 3 -> 20, 4 -> 25.
Native.HIT_JOLT = { [2] = 10, [0] = 15, [3] = 20, [4] = 25 }
function Native:hitJolt(actor)
  local m = self.mem
  if m:s8(actor + 0x619) + 1 ~= m:s16(actor + 0x7E8) then return end
  local amount = Native.HIT_JOLT[bit.band(m:u8(m:u32(Native.RECORD) + 9), 7)]
  if amount then self:setJolt(amount) end
end

-- 84117A24 (fork C): Lock-On (0xC7), two frames after the hit: 84120BB4 and
-- 8410C934 on controller 0's GeoCamera with its shot, then program 25.
function Native:hitLockOn(actor)
  local m = self.mem
  if m:s8(actor + 0x619) + 2 ~= m:s16(actor + 0x7E8) or m:u8(actor + 0x618) ~= 0xC7 then return end
  local ctrl = m:u32(Native.CONTROLLER0)
  local gc = m:u32(ctrl)
  m:setU32(Native.CURRENT, ctrl)
  self:resetShot(gc, actor)
  self:shot(gc, actor, m:s16(ctrl + 0x98))
  self:setProgram(actor, 0x19)
end

-- 8411100C (BattleAnim_ModelDispatch_176): program 25's only handler (its
-- slot is never emptied): the target (+0xB4) is D_8418C958's row 0
-- (84108940). That table is filled while particles are placed (8003C9B8,
-- called by 84102750 / 84104A00: an attachment point of the model), so it is
-- asked of `options.attachmentPoint(index)` (the battle FX player's port of
-- that table); without it the step is reported once and skipped rather than
-- aimed at a guessed point.
function Native:program25Tick(gc)
  local m = self.mem
  m:setU32(Native.CURRENT, self:controllerFor(gc))
  local point = self.attachmentPoint and self.attachmentPoint(0)
  if point then m:setVec(gc + 0xB4, point); return end
  if not self.attachmentReported then
    self.attachmentReported = true
    if self.warn then pcall(self.warn, "battle camera: program 25 (Lock-On) aims at D_8418C958's point 0, which only MOVE EFFECTS fills; the target is held") end
  end
end

-- 841187E4 (US asm): each frame while substate (+0x7F6) is 0, the handler
-- by event code (jtbl_84189084); their camera parts in ROM order:
--   0x0A with side flag 4 (84117CEC) or 2 (84117DC4): 84117744, the jolt,
--        Lock-On; at +0x61A only the kind reset and the timer 0;
--   0x0C (8411862C), 0x0E (84118138): 84117744, the jolt, 84117648;
--   0x0D (8411845C): 84117744, the jolt, Lock-On, 84117648;
--   0x0F / 0x15 (8411854C): the jolt, 84117648;
--   0x11-0x13 (84118704 / 84118754 / 84118794), 0x3B (841182E0): 84117648;
--   any other code (84117E94): 84117744, Lock-On, the jolt, 84117648.
-- 841133EC (the busy gate) is taken as clear. `settled`: the host's HP bar
-- for this side has nothing left to drain (841175D4). `jolt` false skips the
-- jolt when the result is unknown. Returns true once the substate is 1.
function Native:hitFollowFrame(actor, settled, jolt)
  local m = self.mem
  if m:u8(actor + 0x7F6) ~= 0 then return true end
  local record = m:u32(Native.RECORD)
  local code = m:u16(record + 4)
  local function shake() if jolt ~= false then self:hitJolt(actor) end end
  if code == 0x0A and bit.band(m:u16(record + self:side(actor) * 16 + 0x12), 6) ~= 0 then
    self:hitMoveFrame(actor)
    shake()
    self:hitLockOn(actor)
    if m:u8(actor + 0x61A) == m:s16(actor + 0x7E8) then
      self:kindReset(actor)
      self:setTimer(0)
    end
    return false
  elseif code == 0x0C or code == 0x0E then
    self:hitMoveFrame(actor); shake()
  elseif code == 0x0D then
    self:hitMoveFrame(actor); shake(); self:hitLockOn(actor)
  elseif code == 0x0F or code == 0x15 then
    -- 8411854C at the hit frame (84117CAC: not for result 6) also clears
    -- +0x7F4 bit 1, which 84117648 clears too
    if m:s8(actor + 0x619) == m:s16(actor + 0x7E8) and bit.band(m:u8(record + 9), 7) ~= 6 then
      m:setU16(actor + 0x7F4, bit.band(m:u16(actor + 0x7F4), 0xFFFD))
    end
    shake()
  elseif code == 0x11 or code == 0x12 or code == 0x13 or code == 0x3B then
    -- 84117648 only
  else
    self:hitMoveFrame(actor); self:hitLockOn(actor); shake()
  end
  self:hitEnd(actor, settled)
  return m:u8(actor + 0x7F6) ~= 0
end

-- 84111774(gc0, gc1): one camera tick: controller 0's seven handlers on
-- GeoCamera 0, then controller 1's on GeoCamera 1. (Its tail, 841114A8,
-- only sets 3D sound panning and is not part of the camera.)
function Native:tick(gc0, gc1)
  local m = self.mem
  for pass = 1, 2 do
    local global, gc = pass == 1 and Native.CONTROLLER0 or Native.CONTROLLER1, pass == 1 and gc0 or gc1
    m:setU32(Native.SLOT, 0)
    local i = 0
    while i < 7 do
      local ctrl = m:u32(global)
      self:runHandler(m:u32(ctrl + i * 8 + 8), gc, m:u32(ctrl + i * 8 + 4))
      i = m:u32(Native.SLOT) + 1
      m:setU32(Native.SLOT, i)
    end
    if pass == 1 then m:setU32(Native.SLOT, 0) end
  end
end

return Native
