-- Byte-addressed memory with the ROM's addresses, for Lua ports of native
-- routines that work on Stadium 2's own structs (camera controllers, actors,
-- battle records). Nothing executes here: ported Lua reads and writes typed
-- values at the same addresses the ROM code uses, so a port can be compared
-- byte for byte with the ROM routine run on an identical memory.
-- Reads fall back to read-only images (ROM segments at their VRAM base);
-- writes go to a private overlay.
local ok, ffi = pcall(require, "ffi")
local cell = ok and ffi.new("union { float f; uint32_t u; }") or nil

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

local function toWord(v)
  cell.f = v
  return tonumber(cell.u)
end
local function fromWord(w)
  cell.u = w
  return tonumber(cell.f)
end
Memory.floatWord, Memory.wordFloat = toWord, fromWord

function Memory:f32(a) return fromWord(self:read(a, 4)) end
function Memory:setF32(a, v) self:write(a, toWord(v), 4) end
function Memory:vec(a) return { self:f32(a), self:f32(a + 4), self:f32(a + 8) } end
function Memory:setVec(a, v) for i = 1, 3 do self:setF32(a + (i - 1) * 4, v[i]) end end

-- Addresses written so far (the overlay), for byte-for-byte comparison.
function Memory:written() return self.bytes end

return Memory
