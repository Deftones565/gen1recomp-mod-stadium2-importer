-- Stadium 2 portrait camera records, decoded from the player's own ROM.
--
-- The Stadium battle UI itself is the Stadium 2 UI mod (STADIUM2_UI, a
-- dependency, painted in Lua). Its live 3D portraits need Stadium's
-- per-species portrait camera: that data is only in the ROM, so the importer
-- provides it here (the UI's lib/stadium_ui_assets.lua reads this module
-- through package.loaded).
--
-- Portrait camera records (func_84113014 DMA from D_49B780 + D_5730):
-- 32 bytes per species at 0x4A0EB0, alternate records after them, up to
-- 0x4A40F0. Layout: s16 pitch, s16 yaw, f32 distance, f32 target x,
-- f32 target y, s16 idle start frame, s16 alternate index (0x200 = none).
-- Research: docs/luna/research/stadium2-battle-ui.md.
local Rom = require("mods.STADIUM2_IMPORTER.lib.rom")
local Discovery = require("mods.STADIUM2_IMPORTER.lib.discovery")

local Data = {}

Data.PORTRAIT_BASE = 0x49B780 + 0x5730
Data.PORTRAIT_START, Data.PORTRAIT_END = 0x4A0EB0, 0x4A40F0

local byte, floor = string.byte, math.floor

local function u16(s, o) local a, b = byte(s, o + 1, o + 2); return a * 256 + b end
local function s16(s, o)
  local v = u16(s, o)
  return v >= 32768 and v - 65536 or v
end
local function f32(s, o)
  local b1, b2, b3, b4 = byte(s, o + 1, o + 4)
  local sign = b1 >= 128 and -1 or 1
  local exp = (b1 % 128) * 2 + floor(b2 / 128)
  local mant = ((b2 % 128) * 256 + b3) * 256 + b4
  if exp == 0 and mant == 0 then return 0.0 end
  return sign * (1 + mant / 8388608) * 2 ^ (exp - 127)
end

local function portraitAt(table0, romOffset)
  local o = romOffset - Data.PORTRAIT_START
  if o < 0 or o + 32 > #table0 then return nil end
  return { pitch = s16(table0, o), yaw = s16(table0, o + 2),
    distance = f32(table0, o + 4), x = f32(table0, o + 8), y = f32(table0, o + 12),
    frame = s16(table0, o + 16), alt = s16(table0, o + 18) }
end

-- func_84113014: species record; for the second battler x and yaw are
-- mirrored, and an alternate index other than 0x200 replaces the record
-- (loaded as authored, not mirrored).
function Data.portraitRecord(loaded, species, opponent)
  local t = loaded and loaded.portraits
  species = tonumber(species)
  if not (t and species and species >= 1) then return nil end
  local rec = portraitAt(t, Data.PORTRAIT_BASE + (species - 1) * 32)
  if not rec or not opponent then return rec end
  rec.x, rec.yaw = -rec.x, -rec.yaw
  if rec.alt ~= 0x200 then
    local alt = portraitAt(t, Data.PORTRAIT_BASE + (rec.alt - 2) * 32)
    if alt then return alt end
  end
  return rec
end

-- The records from normalised ROM bytes (tests pass them directly).
function Data.fromRom(rom)
  return { portraits = rom:sub(Data.PORTRAIT_START + 1, Data.PORTRAIT_END) }
end

local cached, cachedError, failedAt
Data.RETRY_SECONDS = 30

local function now()
  return (love and love.timer and love.timer.getTime and love.timer.getTime()) or os.clock()
end

-- The records for the engine-managed ROM (cached; nil plus a reason when no
-- supported ROM is available, retried at most every RETRY_SECONDS).
function Data.load()
  if cached then return cached end
  if cachedError and failedAt and now() - failedAt < Data.RETRY_SECONDS then
    return nil, cachedError
  end
  cachedError, failedAt = nil, nil
  local candidate = Discovery.find()
  local result, err
  if not candidate then err = "the engine-managed Stadium 2 ROM is unavailable"
  else
    local bytes, readError = Discovery.read(candidate)
    if not bytes then err = readError
    else
      local rom, order = Rom.normalise(bytes)
      if not rom then err = order
      elseif #rom ~= Rom.SIZE or Rom.title(rom):upper() ~= Rom.US_TITLE then
        err = "the configured import is not the supported Stadium 2 US ROM"
      else
        result = Data.fromRom(rom)
      end
    end
  end
  if result then cached = result else cachedError, failedAt = err, now() end
  return result, err
end

function Data.release() cached, cachedError, failedAt = nil, nil, nil end

return Data
