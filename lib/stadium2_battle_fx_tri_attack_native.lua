-- Tri Attack (effect family 20, US 84158840 / 84158874): the ten-slot radial
-- pool in mode 5 and its two spark groups, ported from the US assembly
-- (pret/pokestadiumgs c0e10f23, fragment79_3C60B0, fragment79_3CB430 and
-- fragment79_3D7DD0; still GLOBAL_ASM in michiiik/pokestadiumgs 1b6dc17c)
-- to Lua on Stadium's own memory layout. Checked byte for byte against the
-- ROM (tests/stadium2_battle_fx_tri_attack_native_rom_test.lua).
--
-- Host boundaries (callbacks):
--   anchor() -> origin {x,y,z}, direction {x,y,z}   841569E0
--   origin() -> {x, y, z}                           84109780
--   random() -> integer                             guRandom (injected)
--   alloc(bytes) -> address                         80006DEC
--   sparks(group, dl) -> dl                         8416A050 (the camera-
--                                                    facing spark submit)
local f32 = require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_float")
local U = require("mods.STADIUM2_IMPORTER.lib.stadium2_libultra")

local T = {}

T.POOL_POINTER = 0x84187530 -- D_84187530: the radial pool is *it + 0x3C8
T.SPARK_POINTER = 0x84187E40 -- D_84187E40: the two spark groups
T.SLOTS, T.SLOT_SIZE = 10, 0x5E8
T.ELEMENTS, T.ELEMENT_SIZE = 20, 0x48 -- slot + 0x48
T.GROUPS, T.GROUP_SIZE = 2, 0x1E4
T.SPARKS, T.SPARK_SIZE = 20, 0x18     -- group + 4
T.COUNTER = 0x841A4D06               -- D_841A4D06: frames since the start
T.MATERIAL = 0x841875C0              -- D_841875C0
T.RING_WIDTH = 0x8418761C            -- D_8418761C (3 floats)
T.RING_RED, T.RING_GREEN, T.RING_BLUE = 0x84187610, 0x84187614, 0x84187618

-- A big-endian double in plain Lua (the mod sandbox refuses ffi at run time).
local wordsToDouble = require("mods.STADIUM2_IMPORTER.lib.stadium2_native_memory").wordsToDouble
local function double(mem, address)
  return wordsToDouble(mem:u32(address), mem:u32(address + 4))
end
local function short(v) return U.toInt(v) % 0x10000 end

function T.pool(mem) return mem:u32(T.POOL_POINTER) + 0x3C8 end
local function group(mem, index) return mem:u32(T.SPARK_POINTER) + index * T.GROUP_SIZE end

-- ------------------------------------------------------------ spark groups

-- 84169B80: both spark groups free.
function T.clearGroups(mem)
  for g = 0, T.GROUPS - 1 do mem:setU16(group(mem, g), 0) end
end

-- 84169BA8: take a free group (its twenty sparks reset), or -1.
function T.takeGroup(mem)
  for g = 0, T.GROUPS - 1 do
    local at = group(mem, g)
    if mem:s16(at) == 0 then
      for i = 0, T.SPARKS - 1 do
        local s = at + 4 + i * T.SPARK_SIZE
        mem:setU16(s, 0); mem:setU16(s + 4, 0)
        mem:setF32(s + 8, 1); mem:setVec(s + 0xC, { 0, 0, 0 })
      end
      mem:setU16(at, 1)
      return g
    end
  end
  return -1
end

-- 84169C74(group, x, y, z, life, size): light the group's first free spark.
function T.addSpark(mem, g, x, y, z, life, size)
  local at = group(mem, g)
  if mem:s16(at) == 0 then return end
  for i = 0, T.SPARKS - 1 do
    local s = at + 4 + i * T.SPARK_SIZE
    if mem:s16(s) == 0 then
      mem:setU16(s, 1); mem:setU16(s + 4, 0); mem:setU16(s + 6, life)
      mem:setVec(s + 0xC, { x, y, z })
      mem:setF32(s + 8, size)
      return
    end
  end
end

-- 84169DBC(group): sparks age, retire after their life, and sink 0.75.
function T.stepGroup(mem, g)
  local at = group(mem, g)
  if mem:s16(at) == 0 then return end
  for i = 0, T.SPARKS - 1 do
    local s = at + 4 + i * T.SPARK_SIZE
    if mem:s16(s) == 1 then
      mem:setU16(s + 4, mem:s16(s + 4) + 1)
      if mem:s16(s + 6) < mem:s16(s + 4) then mem:setU16(s, 0) end
      mem:setF32(s + 0x10, f32(mem:f32(s + 0x10) - 0.75))
    end
  end
end

-- 84169F18's size of a spark: size x sin(age x D_8418C940 / 10).
function T.sparkScale(mem, spark)
  local t = f32(f32(f32(mem:s16(spark + 4)) * mem:f32(0x8418C940)) / 10)
  return f32(mem:f32(spark + 8) * U.sinf(t))
end

-- ------------------------------------------------------------ radial pool

-- 8415C530: every slot free and its twenty elements reset; the slots share
-- one spark group (84169BA8).
function T.initPool(mem)
  local g = T.takeGroup(mem)
  local pool = T.pool(mem)
  for i = 0, T.SLOTS - 1 do
    local slot = pool + i * T.SLOT_SIZE
    mem:setU16(slot, 0); mem:setU16(slot + 4, 0); mem:setU16(slot + 6, 0)
    for k = 0, T.ELEMENTS - 1 do
      local e = slot + 0x48 + k * T.ELEMENT_SIZE
      mem:setF32(e, 0); mem:setU8(e + 4, 0); mem:setF32(e + 8, 1)
      for o = 0xC, 0x24, 4 do mem:setF32(e + o, 0) end
    end
    mem:setU16(slot + 2, g)
  end
end

-- 8415C644(x, y, z, vx, vy, vz, mode, r, g, b, alpha, spin, width,
-- maxWidth, life): the first free slot; element k waits k frames, fades
-- along the ring (the first element fully opaque).
function T.spawn(mem, a)
  local pool = T.pool(mem)
  for i = 0, T.SLOTS - 1 do
    local slot = pool + i * T.SLOT_SIZE
    if mem:s16(slot) == 0 then
      mem:setU16(slot, 1); mem:setU16(slot + 4, 0)
      mem:setU16(slot + 6, a.life); mem:setU16(slot + 8, a.mode)
      mem:setU8(slot + 0xA, a.r); mem:setU8(slot + 0xB, a.g); mem:setU8(slot + 0xC, a.b)
      mem:setU8(slot + 0xD, a.alpha)
      mem:setF32(slot + 0x14, a.maxWidth)
      mem:setF32(slot + 0x18, a.spin)
      mem:setU32(slot + 0x38, 0); mem:setU32(slot + 0x3C, 0); mem:setU32(slot + 0x40, 0)
      for k = 0, T.ELEMENTS - 1 do
        local e = slot + 0x48 + k * T.ELEMENT_SIZE
        mem:setF32(e, k)
        mem:setU8(e + 4, k == 0 and 0xFF or math.floor(a.alpha * (19 - k) / 20))
        mem:setF32(e + 8, a.width)
        mem:setF32(e + 0xC, 0)
        mem:setVec(e + 0x10, { a.x, a.y, a.z })
        mem:setVec(e + 0x1C, { a.vx, a.vy, a.vz })
      end
      return
    end
  end
end

-- 84158768: Tri Attack's ring, from the anchor along six times the
-- direction: mode 5, white, alpha 0xB4, spin D_8418C598, width 2 to 20,
-- life 60.
function T.spawnTriAttack(mem, cb)
  local origin, direction = cb.anchor()
  -- 841569E0 hands them over through float memory
  T.spawn(mem, { x = f32(origin[1]), y = f32(origin[2]), z = f32(origin[3]),
    vx = f32(f32(direction[1]) * 6), vy = f32(f32(direction[2]) * 6), vz = f32(f32(direction[3]) * 6),
    mode = 5, r = 0xFF, g = 0xFF, b = 0xFF, alpha = 0xB4,
    spin = mem:f32(0x8418C598), width = 2, maxWidth = 20, life = 0x3C })
end

-- 84158840 (after 84169B80): the family's init.
function T.init(mem, cb)
  T.clearGroups(mem)
  mem:setU16(T.COUNTER, 0)
  T.initPool(mem)
  T.spawnTriAttack(mem, cb)
end

-- 8415D4C4(slot): one frame of a slot's elements. A waiting element counts
-- down its delay; the others move, turn by the slot's spin and widen by 1
-- up to its maximum. Mode 2 also bounces its sideways speed and falls;
-- modes 1 and 3 (and any unknown mode) keep the height and depth at the
-- origin; waiting elements in modes 1-3 sit at the origin.
function T.stepSlot(mem, cb, slot)
  local o = cb.origin() -- 84109780 writes it to float memory
  local origin = { f32(o[1]), f32(o[2]), f32(o[3]) }
  local mode = mem:u16(slot + 8)
  local spin, maxWidth = mem:f32(slot + 0x18), mem:f32(slot + 0x14)
  for k = 0, T.ELEMENTS - 1 do
    local e = slot + 0x48 + k * T.ELEMENT_SIZE
    local delay = mem:f32(e)
    if mode == 2 then
      if 0 < delay then
        mem:setVec(e + 0x10, origin)
        mem:setF32(e, f32(delay - 1))
      else
        local vx = mem:f32(e + 0x1C)
        mem:setF32(e + 0x10, f32(mem:f32(e + 0x10) + vx))
        mem:setF32(e + 0x14, f32(mem:f32(e + 0x14) + mem:f32(e + 0x20)))
        mem:setF32(e + 0x18, f32(mem:f32(e + 0x18) + mem:f32(e + 0x24)))
        mem:setF32(e + 0xC, f32(mem:f32(e + 0xC) + spin))
        local step = double(mem, 0x8418C6B8)
        if 1 < vx then
          mem:setF32(e + 0x1C, f32(vx - step))
          vx = mem:f32(e + 0x1C)
        end
        if vx < -1 then mem:setF32(e + 0x1C, f32(vx + step)) end
        mem:setF32(e + 0x20, f32(mem:f32(e + 0x20) - double(mem, 0x8418C6B0)))
        if mem:f32(e + 0x20) < -1 then mem:setF32(e + 0x20, -1) end
        if mem:f32(e + 0x14) < 0 then mem:setF32(e + 0x14, 0) end
      end
    elseif mode == 0 or mode == 4 or mode == 5 then
      if 0 < delay then
        mem:setF32(e, f32(delay - 1))
      else
        for c = 0, 2 do mem:setF32(e + 0x10 + c * 4, f32(mem:f32(e + 0x10 + c * 4) + mem:f32(e + 0x1C + c * 4))) end
        mem:setF32(e + 0xC, f32(mem:f32(e + 0xC) + spin))
        mem:setF32(e + 8, f32(mem:f32(e + 8) + 1))
        if maxWidth < mem:f32(e + 8) then mem:setF32(e + 8, maxWidth) end
      end
    else
      if 0 < delay then
        mem:setVec(e + 0x10, origin)
        mem:setF32(e, f32(delay - 1))
      else
        mem:setF32(e + 0x10, f32(mem:f32(e + 0x10) + mem:f32(e + 0x1C)))
        mem:setF32(e + 0x14, origin[2])
        mem:setF32(e + 0x18, origin[3])
        mem:setF32(e + 0xC, f32(mem:f32(e + 0xC) + spin))
        mem:setF32(e + 8, f32(mem:f32(e + 8) + 1))
        if maxWidth < mem:f32(e + 8) then mem:setF32(e + 8, maxWidth) end
      end
    end
  end
end

-- 8415DAE4: every live slot ages (retiring after its life) or steps, and
-- its spark group steps. -1 once no slot stepped.
function T.stepPool(mem, cb)
  local pool, stepped = T.pool(mem), 0
  for i = 0, T.SLOTS - 1 do
    local slot = pool + i * T.SLOT_SIZE
    if mem:s16(slot) == 1 then
      mem:setU16(slot + 4, mem:s16(slot + 4) + 1)
      if mem:s16(slot + 6) < mem:s16(slot + 4) then
        mem:setU16(slot, 0)
      else
        T.stepSlot(mem, cb, slot)
        stepped = stepped + 1
      end
      T.stepGroup(mem, mem:s16(slot + 2))
    end
  end
  return stepped > 0 and 0 or -1
end

-- 84158874: the family's update: -1 from frame 181.
function T.update(mem, cb)
  mem:setU16(T.COUNTER, mem:s16(T.COUNTER) + 1)
  if mem:s16(T.COUNTER) >= 0xB5 then return -1 end
  return T.stepPool(mem, cb)
end

-- ------------------------------------------------------------ draw

-- 8415D430(angle, radius): the point `radius` along Z turned about X by
-- angle x D_8418C688 / D_8418C690 degrees (guRotateF, guMtxXFMF).
function T.ring(mem, angle, radius)
  local a = f32(angle * double(mem, 0x8418C688) / double(mem, 0x8418C690))
  return { U.mtxXFMF(U.rotateF(a, 1, 0, 0), 0, 0, radius) }
end

local function write(mem, at, w0, w1)
  mem:setU32(at, w0 % 4294967296); mem:setU32(at + 4, w1 % 4294967296)
  return at + 8
end

-- 8415DBBC mode 5 vertices: for each element, three rings of three points
-- (ring angle i x D_8418C708 / 3, point angle j x D_8418C70C / 12, radius
-- D_8418761C[j] x width), coloured from the ring tables toward white by
-- the element's alpha. One point in a hundred on the first ring lights a
-- spark there.
local function buildMode5(mem, cb, slot)
  local verts = cb.alloc(0xB40)
  mem:setU32(slot + 0x1C, verts)
  local v = verts
  local ringTurn, pointTurn = mem:f32(0x8418C708), mem:f32(0x8418C70C)
  for k = 0, T.ELEMENTS - 1 do
    local e = slot + 0x48 + k * T.ELEMENT_SIZE
    for i = 0, 2 do
      local ring = f32(f32(ringTurn * f32(i)) / 3)
      for j = 0, 2 do
        local point = f32(f32(pointTurn * f32(j)) / 12)
        local radius = f32(mem:f32(T.RING_WIDTH + j * 4) * mem:f32(e + 8))
        local p = T.ring(mem, f32(f32(mem:f32(e + 0xC) + point) + ring), radius)
        local x = f32(mem:f32(e + 0x10) + p[1])
        local y = f32(mem:f32(e + 0x14) + p[2])
        local z = f32(mem:f32(e + 0x18) + p[3])
        mem:setU16(v, short(x)); mem:setU16(v + 2, short(y)); mem:setU16(v + 4, short(z))
        if j == 0 and cb.random() % 100 == 0 then
          T.addSpark(mem, mem:s16(slot + 2), x, y, z, 10, 0.75)
        end
        local a = mem:u8(e + 4)
        for c, tbl in ipairs({ T.RING_RED, T.RING_GREEN, T.RING_BLUE }) do
          mem:setU8(v + 0xB + c, math.floor((mem:u8(tbl + i) * (255 - a) + a * 255) / 255))
        end
        mem:setU8(v + 0xF, a)
        v = v + 0x10
      end
    end
  end
end

-- One pass of mode 5's ring strip: 19 pairs of rings, each one 18-vertex
-- load and nine triangles, with the given cull mode (0x200 / 0x400).
local function strip(mem, dl, verts, cull)
  local s3 = verts
  for _ = 0, 18 do
    dl = write(mem, dl, 0xDE000000, T.MATERIAL)
    dl = write(mem, dl, 0xD9FFF9FF, 0)
    dl = write(mem, dl, 0xD9FFFFFF, cull)
    dl = write(mem, dl, 0x01012024, s3)
    for v1 = 0, 6, 3 do
      local v0 = 2 * v1
      local a1, t1, ra = v0 % 256, (v0 + 2) % 256, (v0 + 4) % 256
      local a3, t3, s1 = (v0 + 0x12) % 256, (v0 + 0x14) % 256, (v0 + 0x16) % 256
      local function tri(a, b, c) return a * 0x10000 + b * 0x100 + c end
      dl = write(mem, dl, 0x06000000 + tri(a1, a3, t1), tri(t1, a3, t3))
      dl = write(mem, dl, 0x06000000 + tri(t1, t3, ra), tri(ra, t3, s1))
      dl = write(mem, dl, 0x06000000 + tri(ra, s1, a1), tri(a1, s1, a3))
    end
    s3 = s3 + 0x90
  end
  return dl
end

-- 8415DBBC(dl): each live slot's ring (front and back passes and the
-- closing cap), then its spark group (8416A050). Only mode 5 (Tri Attack)
-- is ported; the radial families' other modes draw through
-- stadium2_battle_fx_radial.lua.
function T.draw(mem, cb, dl)
  local pool = T.pool(mem)
  for i = 0, T.SLOTS - 1 do
    local slot = pool + i * T.SLOT_SIZE
    if mem:s16(slot) == 1 then
      local mode = mem:u16(slot + 8)
      if mode ~= 5 then error(("radial draw mode %d is not ported (8415DBBC)"):format(mode), 0) end
      buildMode5(mem, cb, slot)
      local verts = mem:u32(slot + 0x1C)
      dl = strip(mem, dl, verts, 0x200)
      dl = strip(mem, dl, verts, 0x400)
      dl = write(mem, dl, 0xDE000000, T.MATERIAL)
      dl = write(mem, dl, 0xD9FFF9FF, 0)
      dl = write(mem, dl, 0x01009012, verts)
      dl = write(mem, dl, 0x06040200, 0x000A0806)
      dl = write(mem, dl, 0x05100E0C, 0)
      dl = cb.sparks(mem:s16(slot + 2), dl)
    end
  end
  return dl
end

return T
