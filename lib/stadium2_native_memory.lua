-- Byte-addressed memory with the ROM's addresses, for Lua ports of native
-- routines that work on Stadium 2's own structs (camera controllers, actors,
-- battle records). Nothing executes here: ported Lua reads and writes typed
-- values at the same addresses the ROM code uses, so a port can be compared
-- byte for byte with the ROM routine run on an identical memory.
-- Reads fall back to read-only images (ROM segments at their VRAM base);
-- writes go to a private overlay.
-- The game's mod sandbox refuses the ffi library once the game runs, so
-- the conversions below are plain Lua and exact; ffi is only a faster path
-- when this module happens to load where it is allowed.
local ok, ffi = pcall(require, "ffi")
local cell = ok and ffi and ffi.new("union { float f; uint32_t u; }") or nil
local f32 = require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_float")
local floor = math.floor

local Memory = {}
Memory.__index = Memory

function Memory.new(images)
  return setmetatable({ bytes = {}, images = images or {} }, Memory)
end

local function u32(v) return v % 4294967296 end

function Memory:u8(a)
  a = u32(a)
  local v = self.bytes[a]
  if v ~= nil then return v end
  for _, image in ipairs(self.images) do
    local offset = a - image.base
    if offset >= 0 and offset < #image.bytes then return image.bytes:byte(offset + 1) end
  end
  return 0
end

function Memory:read(a, n)
  local v = 0
  for i = 0, n - 1 do v = v * 256 + self:u8(a + i) end
  return v
end

function Memory:write(a, v, n)
  a = u32(a); v = u32(v)
  for i = n - 1, 0, -1 do self.bytes[a + i] = v % 256; v = math.floor(v / 256) end
end

function Memory:u16(a) return self:read(a, 2) end
function Memory:s16(a) local v = self:read(a, 2) return v >= 0x8000 and v - 0x10000 or v end
function Memory:u32(a) return self:read(a, 4) end
function Memory:s32(a) local v = self:read(a, 4) return v >= 0x80000000 and v - 0x100000000 or v end
function Memory:s8(a) local v = self:u8(a) return v >= 0x80 and v - 0x100 or v end
function Memory:setU8(a, v) self:write(a, v, 1) end
function Memory:setU16(a, v) self:write(a, v % 0x10000, 2) end
function Memory:setU32(a, v) self:write(a, v, 4) end

-- IEEE-754 binary32 bits of `v` (rounded to single precision first).
local function toWordLua(v)
  v = f32(v)
  if v ~= v then return 0x7FC00000 end
  local sign = (v < 0 or (v == 0 and 1 / v < 0)) and 0x80000000 or 0
  v = math.abs(v)
  if v == math.huge then return sign + 0x7F800000 end
  if v == 0 then return sign end
  local m, e = math.frexp(v) -- v = m * 2^e, 0.5 <= m < 1
  local exponent = e + 126
  if exponent <= 0 then return sign + floor(v / 2 ^ -149 + 0.5) end
  return sign + exponent * 0x800000 + floor((m * 2 - 1) * 0x800000 + 0.5)
end
-- The value of binary32 bits `w`.
local function fromWordLua(w)
  w = w % 4294967296
  local sign = w >= 0x80000000 and -1 or 1
  local exponent = floor(w / 0x800000) % 0x100
  local mantissa = w % 0x800000
  if exponent == 0 then return sign * mantissa * 2 ^ -149 end
  if exponent == 0xFF then return mantissa == 0 and sign * math.huge or 0 / 0 end
  return sign * (1 + mantissa / 0x800000) * 2 ^ (exponent - 127)
end
-- The value of a big-endian binary64 as its high and low words.
local function wordsToDouble(hi, lo)
  local sign = hi >= 0x80000000 and -1 or 1
  local exponent = floor(hi / 0x100000) % 0x800
  local mantissa = (hi % 0x100000) * 0x100000000 + lo
  if exponent == 0 then return sign * mantissa * 2 ^ -1074 end
  if exponent == 0x7FF then return mantissa == 0 and sign * math.huge or 0 / 0 end
  return sign * (1 + mantissa / 2 ^ 52) * 2 ^ (exponent - 1023)
end
local toWord, fromWord = toWordLua, fromWordLua
if cell then
  toWord = function(v) cell.f = v; return tonumber(cell.u) end
  fromWord = function(w) cell.u = w; return tonumber(cell.f) end
end
Memory.floatWordLua, Memory.wordFloatLua = toWordLua, fromWordLua
Memory.wordsToDouble = wordsToDouble
Memory.floatWord, Memory.wordFloat = toWord, fromWord

function Memory:f32(a) return fromWord(self:read(a, 4)) end
function Memory:setF32(a, v) self:write(a, toWord(v), 4) end
function Memory:vec(a) return { self:f32(a), self:f32(a + 4), self:f32(a + 8) } end
function Memory:setVec(a, v) for i = 1, 3 do self:setF32(a + (i - 1) * 4, v[i]) end end

-- Addresses written so far (the overlay), for byte-for-byte comparison.
function Memory:written() return self.bytes end

return Memory
