-- Stadium 2 battle UI assets, decoded from the player's own ROM.
--
-- Sources (docs/luna/research/stadium2-battle-ui.md):
-- * UI texture sets: archive table entry 1 (ROM 0x437620 -> 0x1898000), files
--   30..36, read by func_8004C990(file, entry) in fragment79_3ADCA0. Each file
--   is a small header plus a Yay0 texture set: u32 count, count pointers
--   relative to 0x8FF00000, and an 8-byte {u16 w, u16 h, u8 fmt, u8 siz}
--   header before each entry's pixels. Odd rows are stored with their 32-bit
--   words swapped (TMEM interleave).
-- * Font: archive D_437750 (src/47580.c func_80047524), file 1: a 0xB0-byte
--   width table, then 16x12 IA8 glyphs from 0xC0, 192 bytes each. Character
--   map D_437670 (ASCII/Latin-1 -> glyph).
--
-- Decoding is pure Lua (tests run without LOVE); `images()` wraps the RGBA
-- strings in LOVE images on demand.
local Rom = require("mods.STADIUM2_IMPORTER.lib.rom")
local Discovery = require("mods.STADIUM2_IMPORTER.lib.discovery")

local Assets = {}

Assets.ARCHIVE_TABLE = 0x437620
Assets.UI_ARCHIVE_INDEX = 1
Assets.UI_FILES = { 30, 31, 32, 33, 34, 35, 36 }
Assets.FONT_ARCHIVE = 0x437750
Assets.FONT_FILE = 1
Assets.CHARMAP = 0x437670
Assets.CHARMAP_SIZE = 0xE0
Assets.GLYPH_W, Assets.GLYPH_H = 16, 12
Assets.GLYPH_START, Assets.GLYPH_BYTES = 0xC0, 192
Assets.WIDTH_TABLE = 0xB0
-- Small font (move descriptions): font archive file 0, same layout with
-- 16x10 IA8 glyphs; advance = width - 1 (checked on the move-info frame).
Assets.SMALL_FONT_FILE = 0
Assets.SMALL_GLYPH_H, Assets.SMALL_GLYPH_BYTES = 10, 160
-- Move descriptions: ROM 0x1D81710, u32 count (251) then offsets from the
-- table start; move m (Stadium/Gen 2 numbering) is entry m.
Assets.DESCRIPTIONS = 0x1D81710
-- Portrait camera records (func_84113014 DMA from D_49B780 + D_5730):
-- 32 bytes per species at 0x4A0EB0, alternate records after them, up to
-- 0x4A40F0. Layout: s16 pitch, s16 yaw, f32 distance, f32 target x,
-- f32 target y, s16 idle start frame, s16 alternate index (0x200 = none).
Assets.PORTRAIT_BASE = 0x49B780 + 0x5730
Assets.PORTRAIT_START, Assets.PORTRAIT_END = 0x4A0EB0, 0x4A40F0

local byte, char, floor = string.byte, string.char, math.floor

local function u16(s, o) local a, b = byte(s, o + 1, o + 2); return a * 256 + b end
local function u32(s, o)
  local a, b, c, d = byte(s, o + 1, o + 4)
  return ((a * 256 + b) * 256 + c) * 256 + d
end

-- A texture-set file: the Yay0 stream follows a short record header.
local function unpackFile(bytes)
  local at = bytes:find("Yay0", 1, true)
  if not at or at > 0x40 then return nil, "texture set has no Yay0 stream" end
  local ok, out = pcall(Rom.yay0, bytes, at - 1)
  if not ok or type(out) ~= "string" then return nil, "texture set Yay0 failed" end
  return out
end

local BPP = { [0] = 0.5, [1] = 1, [2] = 2, [3] = 4 }

-- Undo the TMEM interleave: odd rows hold their 32-bit words swapped.
local function unswap(data, p, rowBytes, h)
  local rows = {}
  for y = 0, h - 1 do
    local row = data:sub(p + y * rowBytes + 1, p + (y + 1) * rowBytes)
    if y % 2 == 1 and rowBytes >= 8 then
      local parts = {}
      for q = 1, #row, 8 do
        parts[#parts + 1] = row:sub(q + 4, q + 7) .. row:sub(q, q + 3)
      end
      row = table.concat(parts)
    end
    rows[#rows + 1] = row
  end
  return table.concat(rows)
end

local function expand4(v) return v * 17 end

-- Decode one texture to an RGBA8 string (w*h*4 bytes).
function Assets.decodeTexture(raw, w, h, fmt, siz)
  local out = {}
  local n = w * h
  for i = 0, n - 1 do
    local r, g, b, a
    if siz == 0 then
      local v = byte(raw, floor(i / 2) + 1) or 0
      v = (i % 2 == 0) and floor(v / 16) or v % 16
      if fmt == 3 then -- IA4: 3-bit intensity, 1-bit alpha
        local c = floor(floor(v / 2) * 255 / 7)
        r, g, b, a = c, c, c, (v % 2 == 1) and 255 or 0
      else -- I4
        r = expand4(v); g, b, a = r, r, r
      end
    elseif siz == 1 then
      local v = byte(raw, i + 1) or 0
      if fmt == 3 then -- IA8
        local c = expand4(floor(v / 16))
        r, g, b, a = c, c, c, expand4(v % 16)
      else
        r, g, b, a = v, v, v, v
      end
    elseif siz == 2 then
      local v = u16(raw, i * 2)
      if fmt == 3 then -- IA16
        local c = floor(v / 256)
        r, g, b, a = c, c, c, v % 256
      else -- RGBA16
        r = floor(floor(v / 2048) % 32 * 255 / 31)
        g = floor(floor(v / 64) % 32 * 255 / 31)
        b = floor(floor(v / 2) % 32 * 255 / 31)
        a = (v % 2 == 1) and 255 or 0
      end
    else
      r, g, b, a = byte(raw, i * 4 + 1, i * 4 + 4)
    end
    out[#out + 1] = char(r, g, b, a)
  end
  return table.concat(out)
end

-- Parse a decompressed texture set into {w, h, fmt, siz, rgba} entries.
function Assets.parseSet(data)
  local count = u32(data, 0)
  if count < 1 or count > 256 then return nil, "bad texture set count" end
  local entries = {}
  for i = 0, count - 1 do
    local p = u32(data, 4 + i * 4) - 0x8FF00000
    if p < 8 or p > #data then return nil, "bad texture set pointer" end
    local w, h = u16(data, p - 8), u16(data, p - 6)
    local fmt, siz = byte(data, p - 3), byte(data, p - 2)
    if w < 1 or h < 1 or w > 512 or h > 512 or not BPP[siz] then
      return nil, "bad texture set entry"
    end
    local rowBytes = floor(w * BPP[siz] + 0.5)
    local raw = unswap(data, p, rowBytes, h)
    entries[i] = { w = w, h = h, fmt = fmt, siz = siz,
      rgba = Assets.decodeTexture(raw, w, h, fmt, siz) }
  end
  return entries
end

-- Font: widths, glyph RGBA (IA8, not interleaved) and the character map.
function Assets.parseFont(data, charmap, glyphH, glyphBytes)
  glyphH, glyphBytes = glyphH or Assets.GLYPH_H, glyphBytes or Assets.GLYPH_BYTES
  local count = floor((#data - Assets.GLYPH_START) / glyphBytes)
  local glyphs, widths = {}, {}
  for i = 0, count - 1 do
    local p = Assets.GLYPH_START + i * glyphBytes
    glyphs[i] = Assets.decodeTexture(data:sub(p + 1, p + glyphBytes),
      Assets.GLYPH_W, glyphH, 3, 1)
    widths[i] = i < Assets.WIDTH_TABLE and byte(data, i + 1) or Assets.GLYPH_W
  end
  return { glyphs = glyphs, widths = widths, count = count, charmap = charmap,
    glyphH = glyphH }
end

-- Move descriptions (nil entries when the table does not check out).
function Assets.parseDescriptions(rom)
  local base = Assets.DESCRIPTIONS
  if u32(rom, base) ~= 251 or u32(rom, base + 4) ~= 0x3F0 then return nil end
  local out = {}
  for m = 1, 251 do
    local off = u32(rom, base + 4 * m)
    local first = base + off + 1
    local last = rom:find("\0", first, true)
    if last then out[m] = rom:sub(first, last - 1) end
  end
  return out
end

-- The character map places 'A' (0x41) at glyph 0x1A; locate its base from the
-- A..Z run so the table's starting code does not have to be assumed.
function Assets.charmapBase(map)
  local run = char(0x1A, 0x1B, 0x1C, 0x1D, 0x1E)
  local at = map:find(run, 1, true)
  if not at then return nil end
  return (at - 1) - 0x41
end

-- D_437670: a 16-byte header, then two ranges: codes 0x20..0x7F at offset
-- 0x10 and codes 0x90..0xFF at offset 0x70 (Latin-1 "é" 0xE9 -> offset 0xC9
-- -> glyph 118, the font's é; ASCII "A" -> offset 0x31 -> glyph 0x1A).
function Assets.glyphFor(font, code)
  local map = font.charmap
  if not map then return nil end
  local offset
  if code >= 0x20 and code <= 0x7F then offset = code - 0x10
  elseif code >= 0x90 and code <= 0xFF then offset = code - 0x20
  else return nil end
  if offset >= #map then return nil end
  local glyph = byte(map, offset + 1)
  if glyph == 0 and code ~= 0x20 then return nil end
  return glyph
end

-- Advance of a glyph in pixels. The width table holds glyph widths; drawn
-- text advances by width - 2 (measured on the ROM's own message frame:
-- "PIKACHU's" advances 5,5,..,2 for the apostrophe, 4 for a space).
function Assets.advance(font, glyph)
  local w = font.widths[glyph] or 7
  return math.max(1, w - 2)
end

local function f32(s, o)
  local b1, b2, b3, b4 = byte(s, o + 1, o + 4)
  local sign = b1 >= 128 and -1 or 1
  local exp = (b1 % 128) * 2 + floor(b2 / 128)
  local mant = ((b2 % 128) * 256 + b3) * 256 + b4
  if exp == 0 and mant == 0 then return 0.0 end
  return sign * (1 + mant / 8388608) * 2 ^ (exp - 127)
end
local function s16(s, o)
  local v = u16(s, o)
  return v >= 32768 and v - 65536 or v
end

local function portraitAt(table0, romOffset)
  local o = romOffset - Assets.PORTRAIT_START
  if o < 0 or o + 32 > #table0 then return nil end
  return { pitch = s16(table0, o), yaw = s16(table0, o + 2),
    distance = f32(table0, o + 4), x = f32(table0, o + 8), y = f32(table0, o + 12),
    frame = s16(table0, o + 16), alt = s16(table0, o + 18) }
end

-- func_84113014: species record; for the second battler x and yaw are
-- mirrored, and an alternate index other than 0x200 replaces the record
-- (loaded as authored, not mirrored).
function Assets.portraitRecord(assets, species, opponent)
  local t = assets and assets.portraits
  species = tonumber(species)
  if not (t and species and species >= 1) then return nil end
  local rec = portraitAt(t, Assets.PORTRAIT_BASE + (species - 1) * 32)
  if not rec or not opponent then return rec end
  rec.x, rec.yaw = -rec.x, -rec.yaw
  if rec.alt ~= 0x200 then
    local alt = portraitAt(t, Assets.PORTRAIT_BASE + (rec.alt - 2) * 32)
    if alt then return alt end
  end
  return rec
end

-- Read everything from the normalised ROM bytes (tests pass them directly).
function Assets.fromRom(rom)
  local table0 = u32(rom, Assets.ARCHIVE_TABLE + Assets.UI_ARCHIVE_INDEX * 4)
  local archive = Rom.archiveAt(rom, table0)
  if not archive then return nil, "Stadium UI archive is unavailable" end
  local sets = {}
  for _, file in ipairs(Assets.UI_FILES) do
    local bytes = Rom.recordBytes(rom, archive.records[file + 1])
    if not bytes then return nil, ("Stadium UI file %d is missing"):format(file) end
    local data, err = unpackFile(bytes)
    if not data then return nil, err end
    local set, setErr = Assets.parseSet(data)
    if not set then return nil, ("UI file %d: %s"):format(file, setErr) end
    sets[file] = set
  end
  local fontArchive = Rom.archiveAt(rom, Assets.FONT_ARCHIVE)
  if not fontArchive then return nil, "Stadium font archive is unavailable" end
  local fontBytes = Rom.recordBytes(rom, fontArchive.records[Assets.FONT_FILE + 1])
  local fontData, fontErr = unpackFile(fontBytes or "")
  if not fontData then return nil, fontErr end
  local charmap = rom:sub(Assets.CHARMAP + 1, Assets.CHARMAP + Assets.CHARMAP_SIZE)
  local font = Assets.parseFont(fontData, charmap)
  font.charmapBase = Assets.charmapBase(charmap)
  if not font.charmapBase then return nil, "Stadium character map is unavailable" end
  local smallBytes = Rom.recordBytes(rom, fontArchive.records[Assets.SMALL_FONT_FILE + 1])
  local smallData = unpackFile(smallBytes or "")
  local small = smallData and Assets.parseFont(smallData, charmap,
    Assets.SMALL_GLYPH_H, Assets.SMALL_GLYPH_BYTES) or nil
  return { sets = sets, font = font, small = small,
    descriptions = Assets.parseDescriptions(rom),
    portraits = rom:sub(Assets.PORTRAIT_START + 1, Assets.PORTRAIT_END) }
end

local cached, cachedError, failedAt
Assets.RETRY_SECONDS = 30

local function now()
  return (love and love.timer and love.timer.getTime and love.timer.getTime()) or os.clock()
end

-- Decoded assets for the engine-managed ROM (cached; nil plus a reason when
-- no supported ROM is available). A failure (for example before the ROM
-- import finishes) is retried at most every RETRY_SECONDS.
function Assets.load()
  if cached then return cached end
  if cachedError and failedAt and now() - failedAt < Assets.RETRY_SECONDS then
    return nil, cachedError
  end
  cachedError, failedAt = nil, nil
  local result, err = Assets.loadNow()
  if not result then cachedError, failedAt = err, now() end
  return result, err
end

function Assets.loadNow()
  local candidate = Discovery.find()
  if not candidate then
    return nil, "the engine-managed Stadium 2 ROM is unavailable"
  end
  local bytes, readError = Discovery.read(candidate)
  if not bytes then return nil, readError end
  local rom, order = Rom.normalise(bytes)
  if not rom then return nil, order end
  if #rom ~= Rom.SIZE or Rom.title(rom):upper() ~= Rom.US_TITLE then
    return nil, "the configured import is not the supported Stadium 2 US ROM"
  end
  local assets, err = Assets.fromRom(rom)
  if not assets then return nil, err end
  cached = assets
  return cached
end

-- LOVE images for the decoded assets, built once per detail level.
-- HD UI (port extension, requested by the user 2026-09-28; not ROM
-- behaviour): the ROM textures and font glyphs are enlarged 4x by bilinear
-- interpolation with edge restoration: where the four source texels around
-- an output texel differ strongly (a letter or icon outline), the blend is
-- re-sharpened with a smoothstep, so outlines become smooth curves and
-- diagonals instead of square steps; soft gradients (the card strips) keep
-- the plain interpolation, which removes their banding. The art is the
-- ROM's own; NATIVE keeps the 1x nearest-filtered textures.
Assets.HD_SCALE = 4
Assets.HD_EDGE = 0.12   -- neighbourhood contrast above which edges sharpen
local detail = "hd"

function Assets.setDetail(value)
  detail = value == "native" and "native" or "hd"
end

function Assets.detail() return detail end

local floor, min, max, char = math.floor, math.min, math.max, string.char
local byte = string.byte

local function sharpen(t)
  -- smoothstep over the middle 60% of the blend
  t = (t - 0.2) / 0.6
  if t <= 0 then return 0 elseif t >= 1 then return 1 end
  return t * t * (3 - 2 * t)
end

function Assets.upscale(rgba, w, h, k)
  -- premultiplied channels, 0..1
  local R, G, B, A = {}, {}, {}, {}
  for i = 0, w * h - 1 do
    local r, g, b, a = byte(rgba, i * 4 + 1, i * 4 + 4)
    a = a / 255
    R[i], G[i], B[i], A[i] = r / 255 * a, g / 255 * a, b / 255 * a, a
  end
  local edge = Assets.HD_EDGE
  local W, H = w * k, h * k
  local out = {}
  local function channel(C, i00, i10, i01, i11, fx, fy)
    local c00, c10, c01, c11 = C[i00], C[i10], C[i01], C[i11]
    local v = (c00 * (1 - fx) + c10 * fx) * (1 - fy) + (c01 * (1 - fx) + c11 * fx) * fy
    local lo, hi = min(c00, c10, c01, c11), max(c00, c10, c01, c11)
    if hi - lo > edge then v = lo + (hi - lo) * sharpen((v - lo) / (hi - lo)) end
    return v
  end
  for oy = 0, H - 1 do
    local sy = (oy + 0.5) / k - 0.5
    local y0 = floor(sy)
    local fy = sy - y0
    local ya, yb = max(0, min(h - 1, y0)), max(0, min(h - 1, y0 + 1))
    for ox = 0, W - 1 do
      local sx = (ox + 0.5) / k - 0.5
      local x0 = floor(sx)
      local fx = sx - x0
      local xa, xb = max(0, min(w - 1, x0)), max(0, min(w - 1, x0 + 1))
      local i00, i10, i01, i11 = ya * w + xa, ya * w + xb, yb * w + xa, yb * w + xb
      local a = channel(A, i00, i10, i01, i11, fx, fy)
      local r, g, b = 0, 0, 0
      if a > 0.002 then
        r = channel(R, i00, i10, i01, i11, fx, fy) / a
        g = channel(G, i00, i10, i01, i11, fx, fy) / a
        b = channel(B, i00, i10, i01, i11, fx, fy) / a
      else
        -- transparent: keep the neighbours' colour so filtering has no fringe
        -- (the 3x3 source texels around, so every texel next to art has it)
        local s = 0
        for dy = -1, 1 do
          local yy = max(0, min(h - 1, floor(sy + 0.5) + dy))
          for dx = -1, 1 do
            local xx = max(0, min(w - 1, floor(sx + 0.5) + dx))
            local i = yy * w + xx
            local ai = A[i]
            if ai > 0 then s = s + ai; r = r + R[i]; g = g + G[i]; b = b + B[i] end
          end
        end
        if s > 0 then r, g, b = r / s, g / s, b / s end
        a = 0
      end
      out[oy * W + ox + 1] = char(floor(min(1, r) * 255 + 0.5), floor(min(1, g) * 255 + 0.5),
        floor(min(1, b) * 255 + 0.5), floor(min(1, a) * 255 + 0.5))
    end
  end
  return table.concat(out), W, H
end

local imagesBy = {}

function Assets.images()
  if imagesBy[detail] then return imagesBy[detail] end
  local assets, err = Assets.load()
  if not assets then return nil, err end
  if not (love and love.image and love.graphics) then return nil, "LOVE graphics unavailable" end
  local k = detail == "hd" and Assets.HD_SCALE or 1
  local function image(w, h, rgba)
    if k > 1 then rgba = Assets.upscale(rgba, w, h, k) end
    local data = love.image.newImageData(w * k, h * k, "rgba8", rgba)
    local img = love.graphics.newImage(data)
    if k > 1 then img:setFilter("linear", "linear") else img:setFilter("nearest", "nearest") end
    return img
  end
  -- k: texels per Stadium pixel (drawers scale by 1/k)
  local out = { sets = {}, glyphs = {}, k = k }
  local Buttons = k > 1 and require("mods.STADIUM2_IMPORTER.lib.stadium_n64_buttons")
  for file, set in pairs(assets.sets) do
    out.sets[file] = {}
    for i, e in pairs(set) do
      -- HD: file 30's N64 button icons are redrawn as vector art
      local hd = Buttons and file == 30 and Buttons.image(i, e.w, e.h)
      if hd then
        out.sets[file][i] = { image = hd, w = e.w, h = e.h, k = Buttons.SCALE }
      else
        out.sets[file][i] = { image = image(e.w, e.h, e.rgba), w = e.w, h = e.h, k = k }
      end
    end
  end
  for i, rgba in pairs(assets.font.glyphs) do
    out.glyphs[i] = image(Assets.GLYPH_W, Assets.GLYPH_H, rgba)
  end
  out.font = assets.font
  if assets.small then
    out.smallGlyphs = {}
    for i, rgba in pairs(assets.small.glyphs) do
      out.smallGlyphs[i] = image(Assets.GLYPH_W, Assets.SMALL_GLYPH_H, rgba)
    end
    out.small = assets.small
  end
  out.descriptions = assets.descriptions
  out.portraits = assets.portraits
  imagesBy[detail] = out
  return out
end

function Assets.release()
  imagesBy, cached, cachedError, failedAt = {}, nil, nil, nil
end

return Assets
