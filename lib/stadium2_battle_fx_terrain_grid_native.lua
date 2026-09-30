-- Surf's water (effect family 7, BattleAnim_StartEffect34TerrainGrid),
-- ported from the US assembly (pret/pokestadiumgs c0e10f23,
-- fragment79_3C60B0; still GLOBAL_ASM in michiiik/pokestadiumgs 1b6dc17c)
-- to Lua on Stadium's own memory layout: the 16x16 wave grid (8415A9E4,
-- 8415AD58, 8415A364), its alpha (8415AC64) and the draw builder 8415ADE0
-- with the camera cover (84159D30, 84159FA8). Checked byte for byte against
-- the ROM (tests/stadium2_battle_fx_terrain_grid_native_rom_test.lua).
--
-- Host boundaries (callbacks):
--   signal() -> integer        841094EC (the presentation is complete)
--   alloc(bytes) -> address    80006DEC
-- The camera is Stadium's GeoCamera at *D_80094908 (eye +0xA8, target
-- +0xB4, up +0xC0, FOV +0x2C, aspect +0x30, near +0x34), written by the
-- host into memory.
local f32 = require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_float")
local U = require("mods.STADIUM2_IMPORTER.lib.stadium2_libultra")
local CameraNative = require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_camera_native")
local ffi = require("ffi")
local bit = require("bit")

local W = {}

W.STATE_POINTER = 0x84187330 -- D_84187330: the grid state
W.CORNERS_POINTER = 0x84187334 -- D_84187334: the camera near-plane frame
W.CAMERA_POINTER = 0x80094908 -- D_80094908: the GeoCamera
W.ENDING = 0x841A4D60        -- D_841A4D60: the end has been scheduled
W.SCROLL0, W.SCROLL1 = 0x841A4D62, 0x841A4D64
W.ROWS, W.COLS = 16, 16
W.GRID, W.VERTEX = 0x1010, 0x14 -- state + 0x1010: 16x16 vertices of 0x14
W.ATAN_TABLE = 0x8008CE50

local cell = ffi.new("union { double d; uint32_t u[2]; }")
local function double(mem, address)
  cell.u[1], cell.u[0] = mem:u32(address), mem:u32(address + 4)
  return tonumber(cell.d)
end
local function short(v) return U.toInt(v) % 0x10000 end

function W.state(mem) return mem:u32(W.STATE_POINTER) end
local function vertex(st, row, col) return st + W.GRID + (row * W.COLS + col) * W.VERTEX end

-- 8000B3B0 through the camera port (the arctangent table from main ROM).
local atanCache = setmetatable({}, { __mode = "k" })
local function atan2(mem, x, y)
  local self = atanCache[mem]
  if not self then
    local tbl = {}
    for i = 0, 0x400 do tbl[i] = mem:u16(W.ATAN_TABLE + i * 2) end
    self = setmetatable({ atan = tbl }, { __index = CameraNative })
    atanCache[mem] = self
  end
  return self:atan2(x, y)
end

-- ------------------------------------------------------------ simulation

-- 8415A364: one frame of the water. Returns -1 once the state's timer
-- (+4) passes its end (+8). The first 60 frames push the first row up
-- along a sine; after that a 90-frame cycle lowers it by 40 (70 frames)
-- and raises it by 30 (20 frames). Then every vertex moves toward its
-- upper, left and right neighbours at rate +0 (itself ramping up to
-- D_8418C618), clamped at 0.
function W.wave(mem)
  local st = W.state(mem)
  mem:setU16(st + 4, mem:s16(st + 4) + 1)
  local c = mem:s16(st + 4)
  if mem:s16(st + 8) < c then return -1 end
  if c < 0x3C then
    local turn = mem:f32(0x8418C5F8)
    for col = 0, 15 do
      local v = vertex(st, 0, col)
      local t = (mem:s16(st + 4) + col) % 15
      local s = U.sinf(f32(f32(f32(t) * turn) / 15))
      mem:setF32(v + 4, f32(mem:f32(v + 4) + (30 * s + 10)))
    end
    mem:setF32(st, f32(mem:f32(st) + double(mem, 0x8418C600)))
  else
    if (c - 0x3C) % 0x5A < 0x46 then
      for col = 2, 14 do
        local v = vertex(st, 0, col)
        local y = mem:f32(v + 4)
        if 0 < y then
          mem:setF32(v + 4, f32(y - 40))
          if mem:f32(v + 4) < 0 then mem:setF32(v + 4, 0) end
        end
      end
    else
      for col = 2, 14 do
        local v = vertex(st, 0, col)
        mem:setF32(v + 4, f32(mem:f32(v + 4) + 30))
      end
    end
    mem:setF32(st, f32(mem:f32(st) + double(mem, 0x8418C608)))
    if double(mem, 0x8418C610) < mem:f32(st) then mem:setF32(st, mem:f32(0x8418C618)) end
  end
  local rate = mem:f32(st)
  for row = 0, 15 do
    for col = 0, 15 do
      local v = vertex(st, row, col)
      local y = mem:f32(v + 4)
      local pull = 0
      if row > 0 then pull = f32(pull + f32(mem:f32(vertex(st, row - 1, col) + 4) - y)) end
      if col > 0 then pull = f32(pull + f32(mem:f32(vertex(st, row, col - 1) + 4) - y)) end
      if col < 15 then pull = f32(pull + f32(mem:f32(vertex(st, row, col + 1) + 4) - y)) end
      mem:setF32(v + 0xC, f32(f32(rate * pull) + y))
    end
  end
  for row = 0, 15 do
    for col = 0, 15 do
      local v = vertex(st, row, col)
      mem:setF32(v + 4, mem:f32(v + 0xC))
      if mem:f32(v + 4) < 0 then mem:setF32(v + 4, 0) end
    end
  end
  return 0
end

-- 8415A9E4(side, count, _): the flat grid on the defender's side (rows at
-- side x (row x 150 - 1640), columns at column x 200 - 1600), timer 0 of
-- 30000 frames, scrolls 0 and 8; `count` frames are simulated ahead.
function W.init(mem, cb, side, count)
  mem:setU16(W.ENDING, 0)
  local st = W.state(mem)
  mem:setU16(st + 4, 0)
  mem:setF32(st, 0)
  mem:setU16(st + 6, count)
  mem:setU16(st + 8, 0x7530)
  local s = f32(side)
  for row = 0, 15 do
    local x = f32(s * f32(f32(f32(f32(row) * 150) - 1200) - 440))
    for col = 0, 15 do
      local v = vertex(st, row, col)
      mem:setF32(v, x)
      mem:setF32(v + 4, 1)
      mem:setF32(v + 8, f32(f32(f32(col) * 200) - 1600))
      mem:setF32(v + 0xC, 1)
      mem:setU16(v + 0x10, 0)
    end
  end
  mem:setU16(W.SCROLL0, 0)
  mem:setU16(W.SCROLL1, 8)
  if count > 0 then
    for _ = 1, count do W.wave(mem) end
    W.cameraFrame(mem, mem:u32(W.CORNERS_POINTER))
  end
end

-- 8415AD58: the family's update. The host's end signal schedules the end
-- 18,000 frames after now (once); the water steps; the scrolls advance.
function W.update(mem, cb)
  if cb.signal() == 1 and mem:s16(W.ENDING) == 0 then
    local st = W.state(mem)
    mem:setU16(st + 8, mem:s16(st + 4) + 0x463C)
    mem:setU16(W.ENDING, 1)
  end
  local result = W.wave(mem)
  mem:setU16(W.SCROLL0, bit.band(mem:s16(W.SCROLL0) + 2, 0x3FFF))
  mem:setU16(W.SCROLL1, bit.band(mem:s16(W.SCROLL1) - 1, 0x3FFF))
  return result
end

-- 8415AC64(alpha): the alpha of the fourteen-by-fourteen interior vertices.
function W.setAlpha(mem, alpha)
  local st = W.state(mem)
  alpha = alpha % 256
  for row = 1, 14 do
    for col = 1, 14 do mem:setU16(vertex(st, row, col) + 0x10, alpha) end
  end
end

-- 8415ADE0's alpha: fades in over 20 frames and out over the last 20.
function W.alpha(mem)
  local st = W.state(mem)
  local c, d = mem:s16(st + 4), mem:s16(st + 8)
  local v = 255
  if c < 0x14 then v = U.toInt((c * 255) / 20)
  elseif d - 0x14 < c then v = U.toInt(((d - c) * 255) / 20) end
  v = v % 0x10000
  if v >= 0x8000 then v = v - 0x10000 end
  return v % 256
end

-- ------------------------------------------------------------ camera cover

-- 80070BA4: a x b.
local function cross(a, b)
  return f32(f32(a[2] * b[3]) - f32(a[3] * b[2])),
    f32(f32(a[3] * b[1]) - f32(a[1] * b[3])),
    f32(f32(a[1] * b[2]) - f32(a[2] * b[1]))
end

-- 80070C14: normalise in place (unchanged when its length is 0).
local function normalize(v)
  local len = f32(math.sqrt(f32(f32(f32(v[1] * v[1]) + f32(v[2] * v[2])) + f32(v[3] * v[3]))))
  if 0 < len then return { f32(v[1] / len), f32(v[2] / len), f32(v[3] / len) } end
  return v
end

-- 84159D30(out): the camera's near-plane frame: the point 20 past the near
-- plane along the view, then half-width and half-height vectors.
function W.cameraFrame(mem, out)
  local cam = mem:u32(W.CAMERA_POINTER)
  local up = mem:vec(cam + 0xC0)
  local eye, at = mem:vec(cam + 0xA8), mem:vec(cam + 0xB4)
  local fov, aspect, near = mem:f32(cam + 0x2C), mem:f32(cam + 0x30), mem:f32(cam + 0x34)
  local fov30 = f32(fov / 30)
  local d = normalize({ f32(at[1] - eye[1]), f32(at[2] - eye[2]), f32(at[3] - eye[3]) })
  local dist = f32(near + 20)
  for k = 1, 3 do mem:setF32(out + (k - 1) * 4, f32(f32(dist * d[k]) + eye[k])) end
  local half = f32(f32(mem:f32(0x8418C5F0) * fov) / 720)
  local c = U.cosf(half)
  local h = 0
  if c ~= 0 then h = f32(f32(U.sinf(half) * dist) / c) end
  h = math.abs(h)
  local w = f32(f32(f32(aspect * h) * fov30) * mem:f32(0x8418C5F4))
  local right = normalize({ cross(d, up) })
  local upv = { cross(d, { cross(d, up) }) }
  upv = normalize(upv)
  for k = 1, 3 do
    mem:setF32(out + 0xC + (k - 1) * 4, f32(right[k] * w))
    mem:setF32(out + 0x18 + (k - 1) * 4, f32(upv[k] * h))
  end
end

-- 84159FA8(x, z) -> height, slope: the water height under (x, z) on the
-- nearer triangle of its grid cell, and the slope angle (degrees, folded
-- into -90..90) of that triangle's normal.
function W.heightAt(mem, x, z)
  local st = W.state(mem)
  x, z = f32(x), f32(z)
  local r = U.toInt(f32(f32(f32(x + 440) / 150) + 8))
  local cc = U.toInt(f32(f32(z / 200) + 8))
  if r < 0 then r = 0 end
  if r >= 15 then r = 14 end
  if cc < 0 then cc = 0 end
  if cc >= 15 then cc = 14 end
  local p00 = mem:vec(vertex(st, r, cc))
  local p10 = mem:vec(vertex(st, r + 1, cc))
  local p01 = mem:vec(vertex(st, r, cc + 1))
  local p11 = mem:vec(vertex(st, r + 1, cc + 1))
  local a0, a1 = f32(p11[1] - x), f32(p11[3] - z)
  local b0, b1 = f32(p10[1] - x), f32(p10[3] - z)
  local d11 = f32(f32(a0 * a0) + f32(a1 * a1))
  local d10 = f32(f32(b0 * b0) + f32(b1 * b1))
  local base = d10 <= d11 and p00 or p11
  local e1 = { f32(p10[1] - base[1]), f32(p10[2] - base[2]), f32(p10[3] - base[3]) }
  local e2 = { f32(p01[1] - base[1]), f32(p01[2] - base[2]), f32(p01[3] - base[3]) }
  local nx, ny, nz = cross(e1, e2)
  local height
  if ny == 0 then
    height = f32(f32(f32(base[2] + p10[2]) + p01[2]) / 3)
  else
    local t = f32(f32(f32(x - base[1]) * nx) + f32(nz * f32(z - base[3])))
    height = f32(base[2] - f32(t / ny))
  end
  local angle = f32(f32(f32(atan2(mem, ny, nx)) * 360) / 65536)
  if 90 < angle then angle = f32(angle - 180) end
  if angle < -90 then angle = f32(angle + 180) end
  return height, angle
end

-- ------------------------------------------------------------ draw

local function write(mem, at, w0, w1)
  mem:setU32(at, w0 % 4294967296); mem:setU32(at + 4, w1 % 4294967296)
  return at + 8
end

-- The two scrolling tiles, as the grid's material sets them (shift = 12)
-- and as the cover's does (no shift).
local function tiles(mem, dl, textures, grid)
  local shift = grid and 0x1000 or 1
  local s0, s1 = mem:s16(W.SCROLL0), mem:s16(W.SCROLL1)
  local lo = grid and { 0x07014451, 0x00014451, 0x07014050, 0x01014050 }
    or { 0x0701405F, 0x0001405F, 0x0701405E, 0x0101405E }
  dl = write(mem, dl, 0xFD88000F, textures[1])
  dl = write(mem, dl, 0xF5880400, lo[1])
  dl = write(mem, dl, 0xE6000000, 0)
  dl = write(mem, dl, 0xF4000000, 0x0703E07C)
  dl = write(mem, dl, 0xE7000000, 0)
  dl = write(mem, dl, 0xF5800400, lo[2])
  dl = write(mem, dl, 0xF2000000, 0x0007C07C)
  dl = write(mem, dl, 0xF2000000 + bit.band(s0, 0xFFF) * shift,
    bit.band(s0 + 0x1F, 0xFFF) * shift + (grid and 0x1F or 0x1F000))
  dl = write(mem, dl, 0xFD88000F, textures[2])
  dl = write(mem, dl, 0xF5880500, lo[3])
  dl = write(mem, dl, 0xE6000000, 0)
  dl = write(mem, dl, 0xF4000000, 0x0703E07C)
  dl = write(mem, dl, 0xE7000000, 0)
  dl = write(mem, dl, 0xF5800500, lo[4])
  dl = write(mem, dl, 0xF2000000, 0x0107C07C)
  dl = write(mem, dl, 0xF2000000 + bit.band(s1, 0xFFF) * shift,
    bit.band(s1 + 0x1F, 0xFFF) * shift + (grid and 0x0100001F or 0x0101F000))
  return dl
end

-- 8415ADE0(dl): the grid's 256 vertices (from the previous frame's alpha),
-- this frame's alpha (8415AC64), the material and the 15x15 quads; then,
-- when the camera's near plane dips below the water, the cover quad
-- (textured by D_8418CAA4, scaled by D_8418C61C). The 16-bit state
-- counters are read as the ROM reads them.
function W.draw(mem, cb, dl)
  local st = W.state(mem)
  local verts = cb.alloc(0x1000)
  mem:setU32(st + 0xC, verts)
  for row = 0, 15 do
    for col = 0, 15 do
      local v, p = verts + (row * 16 + col) * 0x10, vertex(st, row, col)
      mem:setU16(v, short(mem:f32(p))); mem:setU16(v + 2, short(mem:f32(p + 4)))
      mem:setU16(v + 4, short(mem:f32(p + 8)))
      mem:setU16(v + 8, math.floor(row * 0x800 / 3)); mem:setU16(v + 0xA, math.floor(col * 0x800 / 3))
      mem:setU8(v + 0xF, mem:u8(p + 0x11))
    end
  end
  dl = write(mem, dl, 0xDE000000, 0x84187338)
  dl = write(mem, dl, 0xE7000000, 0)
  W.setAlpha(mem, W.alpha(mem))
  dl = write(mem, dl, 0xFA00007D, 0xAFFFFFFF)
  dl = write(mem, dl, 0xFB000000, 0x0028AF37)
  dl = write(mem, dl, 0xF9000000, 0xFFFFFFFF)
  dl = tiles(mem, dl, { mem:u32(0x8418CA9C), mem:u32(0x8418CAA0) }, true)
  for row = 0, 14 do
    for col = 0, 14 do
      local a = verts + (row * 16 + col) * 0x10
      dl = write(mem, dl, 0x01001002, a)
      dl = write(mem, dl, 0x01001004, a + 0x10)
      dl = write(mem, dl, 0x01001006, a + 0x100)
      dl = write(mem, dl, 0x01001008, a + 0x110)
      dl = write(mem, dl, 0x06000402, 0x00040602)
    end
  end
  -- the cover
  local frame = mem:u32(W.CORNERS_POINTER)
  W.cameraFrame(mem, frame)
  local c = {}
  for i = 0, 8 do c[i] = f32(mem:f32(frame + i * 4) * 10) end
  local lx = f32(c[0] - c[3])                -- P - R
  local lz = f32(c[2] - c[5])
  local x1, z1 = f32(lx + c[6]), f32(lz + c[8]) -- P - R + U
  local h1 = W.heightAt(mem, f32(x1 / 10), f32(z1 / 10))
  h1 = f32(h1 * 10)
  local rx = f32(c[0] + c[3])                -- P + R
  local rz = f32(c[2] + c[5])
  local x2, z2 = f32(rx + c[6]), f32(rz + c[8])
  local h2 = W.heightAt(mem, f32(x2 / 10), f32(z2 / 10))
  h2 = f32(h2 * 10)
  local y1 = f32(f32(c[1] - c[4]) + c[7])
  local y2 = f32(f32(c[1] + c[4]) + c[7])
  if not (y1 < h1 or y2 < h2) then return dl end
  local q = cb.alloc(0x40)
  local function put(at, x, y, z, s, t)
    mem:setU16(at, short(x)); mem:setU16(at + 2, short(y)); mem:setU16(at + 4, short(z))
    mem:setU16(at + 8, s); mem:setU16(at + 0xA, t)
  end
  put(q, f32(lx - c[6]), h1, f32(lz - c[8]), 0, 0)
  put(q + 0x10, f32(rx - c[6]), h2, f32(rz - c[8]), 0x3E0, 0)
  put(q + 0x20, x1, y1, z1, 0, 0x3E0)
  put(q + 0x30, x2, y2, z2, 0x3E0, 0x3E0)
  dl = write(mem, dl, 0xDE000000, 0x841873B0)
  dl = tiles(mem, dl, { mem:u32(0x8418CAA4), mem:u32(0x8418CAA4) }, false)
  local mtx = cb.alloc(0x40)
  local s = mem:f32(0x8418C61C)
  U.scale(mem, mtx, s, s, s)
  dl = write(mem, dl, 0xDA380001, mtx)
  dl = write(mem, dl, 0x01004008, q)
  dl = write(mem, dl, 0x06000402, 0x00040602)
  return dl
end

return W
