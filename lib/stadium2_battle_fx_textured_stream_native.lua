-- The six-slot textured stream shared by Ice Beam (effect family 13, US
-- 84158E24 / 84158E58) and Hyper Beam (family 8, 84159C2C / 84159C6C),
-- ported from the US assembly (pret/pokestadiumgs c0e10f23,
-- fragment79_3C60B0 and fragment79_3D7DD0; still GLOBAL_ASM in
-- michiiik/pokestadiumgs 1b6dc17c) to Lua on Stadium's own memory layout:
-- the spawners (84158C4C, 84159A50, 841597AC), the pool (84168540,
-- 84168680, 84169040, 84168CA4) and the draw builder 84169618 (mode 0, with
-- 84168C18). Checked byte for byte against the ROM
-- (tests/stadium2_battle_fx_textured_stream_native_rom_test.lua).
--
-- Host boundaries (callbacks):
--   anchor() -> origin, direction       841569E0
--   origin() -> {x, y, z}               84109780
--   signal() -> integer                 841094EC
--   random() -> integer                 guRandom (injected)
--   alloc(bytes) -> address             80006DEC
--   coreInit()                          84166F60 (Hyper Beam's core beam,
--   coreSpawn(call) -> result            841670A8  stadium2_battle_fx_beam)
--   coreStep() -> result                841677C4
--   combine(dl, slot)                   800710A8 (writes one command)
--   material(dl, slot) -> dl            84169344
--   strip(dl, slot) -> dl               84169214
-- coreSpawn receives the ROM call's registers and stack words:
-- { fa0, fa1, a2, a3 = floats, stack = { [offset] = 32-bit word } }.
local f32 = require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_float")
local U = require("mods.STADIUM2_IMPORTER.lib.stadium2_libultra")
local Memory = require("mods.STADIUM2_IMPORTER.lib.stadium2_native_memory")

local S = {}

S.POOL_POINTER = 0x84187DC0 -- D_84187DC0: the pool is *it + 0x900
S.SLOTS, S.SLOT_SIZE = 6, 0x374
S.NODES, S.NODE_SIZE = 20, 0x24 -- slot + 0xA4
S.FRAME = 0x841A4DC2   -- D_841A4DC2: frames of the pool
S.ENDING = 0x841A4DC4  -- D_841A4DC4: the end has been scheduled
S.END_FRAME = 0x841A4DC0
S.COUNTER = { [13] = 0x841A4D48, [8] = 0x841A4D50 } -- the spawn cadence
S.MATERIAL = 0x84187DD0 -- D_84187DD0

-- 84168CA4 reads its frame's word at sp + 0xA8 without writing it: the
-- stack word left there by the effect's own previous calls. In this call
-- chain that is the last spawner's argument at its sp + 0x50 (0x19) or,
-- after a draw with live slots, 84169618's loop word at its sp + 0xA0
-- (0x5000). The port keeps that one word at the address it has in the
-- ROM's call chain, so the output matches the ROM's.
S.STALE = 0x857FEF90

-- A big-endian double in plain Lua (the mod sandbox refuses ffi at run time).
local wordsToDouble = require("mods.STADIUM2_IMPORTER.lib.stadium2_native_memory").wordsToDouble
local function double(mem, address)
  return wordsToDouble(mem:u32(address), mem:u32(address + 4))
end
local function short(v) return U.toInt(v) % 0x10000 end
local function word(x) return Memory.floatWord(f32(x)) end

function S.pool(mem) return mem:u32(S.POOL_POINTER) + 0x900 end

-- ------------------------------------------------------------ pool

-- 84168540: every slot free; its two five-byte colour blocks from
-- D_84187DC4; each node's width 1, everything else 0.
function S.initPool(mem)
  local tmpl = {}
  for i = 0, 4 do tmpl[i] = mem:u8(0x84187DC4 + i) end
  mem:setU16(S.ENDING, 0)
  mem:setU16(S.FRAME, 0)
  local pool = S.pool(mem)
  for i = 0, S.SLOTS - 1 do
    local slot = pool + i * S.SLOT_SIZE
    mem:setU16(slot, 0); mem:setU16(slot + 4, 0); mem:setU16(slot + 6, 0)
    for k = 0, 4 do mem:setU8(slot + 8 + k, tmpl[k]); mem:setU8(slot + 0xD + k, tmpl[k]) end
    for j = 0, S.NODES - 1 do
      local n = slot + 0xA4 + j * S.NODE_SIZE
      mem:setF32(n, 0); mem:setF32(n + 4, 1)
      for o = 8, 0x20, 4 do mem:setF32(n + o, 0) end
    end
  end
end

-- 84168680(mode, x, y, z, stack): the first free slot. `stack` holds the
-- ROM call's stack arguments by offset (vx 0x10, vy 0x14, vz 0x18, the
-- nine colour bytes 0x1C..0x3C, spin 0x40, width 0x44, max width 0x48,
-- life 0x4C, textures 0x50 / 0x54, scroll and shift halves 0x58..0x74,
-- combiner tables 0x78 / 0x7C). Node j waits 2j frames.
function S.spawn(mem, mode, x, y, z, a)
  local pool = S.pool(mem)
  for i = 0, S.SLOTS - 1 do
    local slot = pool + i * S.SLOT_SIZE
    if mem:s16(slot) == 0 then
      mem:setU16(slot, 1); mem:setU16(slot + 2, mode); mem:setU16(slot + 4, 0)
      mem:setU16(slot + 6, a[0x4C])
      mem:setF32(slot + 0x80, a[0x48]); mem:setF32(slot + 0x84, a[0x40])
      mem:setU32(slot + 0x20, a[0x50]); mem:setU32(slot + 0x24, a[0x54])
      for _, h in ipairs({ 0x68, 0x6A, 0x74, 0x76 }) do mem:setU16(slot + h, 0) end
      for k, off in ipairs({ 0x58, 0x5C, 0x60, 0x64 }) do mem:setU16(slot + 0x6A + k * 2, a[off]) end
      for k, off in ipairs({ 0x68, 0x6C, 0x70, 0x74 }) do mem:setU16(slot + 0x76 + k * 2, a[off]) end
      for w = 0, 7 do
        mem:setU32(slot + 0x28 + w * 4, mem:u32(a[0x78] + w * 4))
        mem:setU32(slot + 0x48 + w * 4, mem:u32(a[0x7C] + w * 4))
      end
      mem:setU16(slot + 0x1C, 0x46)
      mem:setF32(slot + 0x14, 1); mem:setF32(slot + 0x18, 1)
      for k = 0, 8 do mem:setU8(slot + 8 + k, a[0x1C + k * 4] % 256) end
      for j = 0, S.NODES - 1 do
        local n = slot + 0xA4 + j * S.NODE_SIZE
        mem:setF32(n, f32(f32(j) + f32(j)))
        mem:setF32(n + 4, a[0x44])
        mem:setF32(n + 8, 0)
        mem:setVec(n + 0xC, { x, y, z })
        mem:setVec(n + 0x18, { a[0x10], a[0x14], a[0x18] })
      end
      return
    end
  end
end

-- 84168CA4(slot): a waiting node follows the origin, offset by a wave of
-- three sines of random periods (phase: the stale word, see S.STALE); a
-- released node moves, widens by 3 up to +0x80 and turns by +0x84.
function S.stepNodes(mem, cb, slot)
  local k = double(mem, 0x8418C928)
  local stale = mem:s32(S.STALE)
  for j = 0, S.NODES - 1 do
    local n = slot + 0xA4 + j * S.NODE_SIZE
    local delay = mem:f32(n)
    if 0 < delay then
      local s3 = cb.random() % 20 + 2
      local s2 = cb.random() % 10 + 4
      local s4 = cb.random() % 20 + 2
      local s1 = cb.random() % 10 + 4
      local a = U.sinf(f32(((stale + s3) % s2) * k / s2))
      local p = stale + s4
      local b = U.sinf(f32((p % (s1 + 20)) * k / (s1 + 20)))
      local c = U.sinf(f32((p % s1) * k / s1))
      local dy = f32(b * (10 * a))
      local dz = f32(c * 10)
      local o = cb.origin()
      mem:setF32(n + 0xC, o[1])
      mem:setF32(n + 0x10, f32(f32(o[2]) + dy))
      mem:setF32(n + 0x14, f32(f32(o[3]) + dz))
      mem:setF32(n, f32(delay - 1))
    else
      for c = 0, 2 do mem:setF32(n + 0xC + c * 4, f32(mem:f32(n + 0xC + c * 4) + mem:f32(n + 0x18 + c * 4))) end
      mem:setF32(n + 4, f32(mem:f32(n + 4) + 3))
      mem:setF32(n + 8, f32(mem:f32(n + 8) + mem:f32(slot + 0x84)))
      if mem:f32(slot + 0x80) < mem:f32(n + 4) then mem:setF32(n + 4, mem:f32(slot + 0x80)) end
    end
  end
end

-- 84169040: the pool's frame. The host's end signal starts a 50-frame
-- end; live slots age (retiring after their life) or step, and fade over
-- the last 20 frames; -1 at the end or once nothing stepped.
function S.stepPool(mem, cb)
  mem:setU16(S.FRAME, mem:s16(S.FRAME) + 1)
  if cb.signal() == 1 and mem:s16(S.ENDING) == 0 then
    mem:setU16(S.ENDING, 1)
    mem:setU16(S.END_FRAME, mem:s16(S.FRAME) + 0x32)
  end
  local fade = mem:f32(0x8418C930)
  local pool, stepped = S.pool(mem), 0
  for i = 0, S.SLOTS - 1 do
    local slot = pool + i * S.SLOT_SIZE
    if mem:s16(slot) == 1 then
      mem:setU16(slot + 4, mem:s16(slot + 4) + 1)
      if mem:s16(slot + 6) < mem:s16(slot + 4) then
        mem:setU16(slot, 0)
      else
        S.stepNodes(mem, cb, slot)
        stepped = stepped + 1
      end
      if mem:s16(S.ENDING) == 1 then
        local e, f = mem:s16(S.END_FRAME), mem:s16(S.FRAME)
        if e < f then return -1 end
        if e - 0x14 < f then
          local t = (f - e + 0x14) % 0x10000
          if t >= 0x8000 then t = t - 0x10000 end
          local v = f32(f32(t) * fade)
          local alpha = f32(1 - v)
          mem:setF32(slot + 0x14, alpha); mem:setF32(slot + 0x18, alpha)
          if 1 < v then mem:setF32(slot + 0x14, 0) end
          if mem:f32(slot + 0x18) < 0 then mem:setF32(slot + 0x18, 0) end
        end
      end
    end
  end
  return stepped > 0 and 0 or -1
end

-- ------------------------------------------------------------ spawners

-- The drift of a new stream: the anchor's direction, lifted and bent by
-- two random cosines, times 12.
local function drift(mem, cb, kY, kYs, kZ, kZs)
  local origin, direction = cb.anchor()
  local ox, oy, oz = f32(origin[1]), f32(origin[2]), f32(origin[3])
  local dx, dy, dz = f32(direction[1]), f32(direction[2]), f32(direction[3])
  local r = cb.random() % 10
  local c = U.cosf(f32(f32(f32(r) * mem:f32(kY)) / 10))
  dy = f32(dy + f32(mem:f32(kYs) * c))
  r = cb.random() % 10
  c = U.cosf(f32(f32(f32(r) * mem:f32(kZ)) / 10))
  local vz = f32(f32(dz + f32(mem:f32(kZs) * c)) * 12)
  return ox, oy, oz, f32(dx * 12), f32(dy * 12), vz
end

-- 84158C4C: Ice Beam's stream.
function S.spawnIceBeam(mem, cb)
  local x, y, z, vx, vy, vz = drift(mem, cb, 0x8418C5A4, 0x8418C5A8, 0x8418C5AC, 0x8418C5B0)
  mem:setU32(S.STALE, 0x19)
  S.spawn(mem, 0, x, y, z, {
    [0x10] = vx, [0x14] = vy, [0x18] = vz,
    [0x1C] = 0xFF, [0x20] = 0xFF, [0x24] = 0xFF, [0x28] = 0xFF, [0x2C] = 0, [0x30] = 0,
    [0x34] = 0x64, [0x38] = 0xFF, [0x3C] = 0xFF,
    [0x40] = mem:f32(0x8418C5B4), [0x44] = 2, [0x48] = 20, [0x4C] = 0x3C,
    [0x50] = 0x19, [0x54] = 0x19, [0x58] = 0, [0x5C] = 0xA, [0x60] = 0, [0x64] = 0xD,
    [0x68] = 0, [0x6C] = 0, [0x70] = 0, [0x74] = 0,
    [0x78] = 0x841870F0, [0x7C] = 0x84187110 })
end

-- 84159A50: Hyper Beam's stream.
function S.spawnHyperBeam(mem, cb)
  local x, y, z, vx, vy, vz = drift(mem, cb, 0x8418C5D4, 0x8418C5D8, 0x8418C5DC, 0x8418C5E0)
  mem:setU32(S.STALE, 0x19)
  S.spawn(mem, 0, x, y, z, {
    [0x10] = vx, [0x14] = vy, [0x18] = vz,
    [0x1C] = 0xFF, [0x20] = 0xFF, [0x24] = 0x64, [0x28] = 0x32, [0x2C] = 0xC8, [0x30] = 0xFF,
    [0x34] = 0x32, [0x38] = 0, [0x3C] = 0xFF,
    [0x40] = mem:f32(0x8418C5E0), [0x44] = 2, [0x48] = 5, [0x4C] = 0x3C,
    [0x50] = 0x19, [0x54] = 0x19, [0x58] = 0, [0x5C] = 0x14, [0x60] = 0, [0x64] = 0xD,
    [0x68] = 0, [0x6C] = 0x19, [0x70] = 0, [0x74] = 0xD,
    [0x78] = 0x841872F0, [0x7C] = 0x84187310 })
end

-- 841597AC: Hyper Beam's two core beams (841670A8, the core-beam port).
function S.spawnHyperBeamCores(mem, cb)
  local origin, direction = cb.anchor()
  local x, y, z = f32(origin[1]), f32(origin[2]), f32(origin[3])
  local vx, vy, vz = f32(f32(direction[1]) * 12), f32(f32(direction[2]) * 12), f32(f32(direction[3]) * 12)
  local function call(stack)
    stack[0x10], stack[0x14] = word(vy), word(vz)
    return cb.coreSpawn({ fa0 = x, fa1 = y, a2 = z, a3 = vx, stack = stack })
  end
  call({ [0x18] = word(0), [0x1C] = word(5), [0x20] = mem:u32(0x8418C5CC), [0x24] = word(2),
    [0x28] = word(10), [0x2C] = 0x14, [0x30] = 0x15, [0x34] = 0x16, [0x38] = 5, [0x3C] = 0x1E,
    [0x40] = 0, [0x44] = 0xD, [0x48] = 0xFFFFFFFB, [0x4C] = 0x1E, [0x50] = 0xF, [0x54] = 0xD,
    [0x58] = 0x84187270, [0x5C] = 0x84187290, [0x60] = 0xFF, [0x64] = 0xFF, [0x68] = 0,
    [0x6C] = 0xFF, [0x70] = 0x96, [0x74] = 0x32, [0x78] = 0, [0x7C] = 0, [0x80] = 0xFF,
    [0x84] = 0xFF, [0x88] = 0xC8, [0x8C] = 0x64, [0x90] = 0xC8 })
  call({ [0x18] = word(0), [0x1C] = word(5), [0x20] = mem:u32(0x8418C5D0), [0x24] = word(3),
    [0x28] = word(15), [0x2C] = 0x14, [0x30] = 0x1B, [0x34] = 0x1A, [0x38] = 6, [0x3C] = 0x14,
    [0x40] = 0xE, [0x44] = 0xF, [0x48] = 0xFFFFFFFD, [0x4C] = 0xA, [0x50] = 0, [0x54] = 0xF,
    [0x58] = 0x841872B0, [0x5C] = 0x841872D0, [0x60] = 0xFF, [0x64] = 0xFF, [0x68] = 0x64,
    [0x6C] = 0x96, [0x70] = 0xFF, [0x74] = 0xFF, [0x78] = 0x64, [0x7C] = 0, [0x80] = 0xC8,
    [0x84] = 0, [0x88] = 0, [0x8C] = 0, [0x90] = 0 })
end

-- ------------------------------------------------------------ families

-- 84158E24 (Ice Beam) / 84159C2C (Hyper Beam): the family's init.
function S.init(mem, cb, family)
  if family == 13 then
    mem:setU16(S.COUNTER[13], 0)
    S.initPool(mem)
    S.spawnIceBeam(mem, cb)
  else
    cb.coreInit()
    S.spawnHyperBeamCores(mem, cb)
    S.initPool(mem)
    S.spawnHyperBeam(mem, cb)
  end
end

-- 84158E58 / 84159C6C: a new stream every ten frames, then the pool steps;
-- Hyper Beam's result is its core beam's (841677C4).
function S.update(mem, cb, family)
  local counter = S.COUNTER[family]
  mem:setU16(counter, mem:s16(counter) + 1)
  if mem:s16(counter) % 10 == 0 then
    if family == 13 then S.spawnIceBeam(mem, cb) else S.spawnHyperBeam(mem, cb) end
  end
  local result = S.stepPool(mem, cb)
  if family == 8 then return cb.coreStep() end
  return result
end

-- ------------------------------------------------------------ draw

-- 84168C18(angle, radius): the point `radius` along Z turned about X by
-- 360 x angle / D_8418C920 degrees.
function S.ring(mem, angle, radius)
  local a = f32(f32(360 * angle) / mem:f32(0x8418C920))
  return { U.mtxXFMF(U.rotateF(a, 1, 0, 0), 0, 0, radius) }
end

local function write(mem, at, w0, w1)
  mem:setU32(at, w0 % 4294967296); mem:setU32(at + 4, w1 % 4294967296)
  return at + 8
end

-- A colour's alpha byte: the slot's alpha byte x its fade (cvt.w.s with
-- round-toward-zero).
local function alphaByte(byte, fade) return U.toInt(f32(f32(byte) * fade)) % 256 end

-- 84169618(dl): for each live slot, 40 vertices (two ring points per node;
-- a node still waiting reuses the last point), then the material, the
-- combiner (800710A8), primitive and environment colours faded by +0x14 /
-- +0x18, the material and strip sub-lists (84169344, 84169214).
function S.draw(mem, cb, dl)
  local pool = S.pool(mem)
  local turn = mem:f32(0x8418C934)
  local point = { 0, 0, 0 }
  for i = 0, S.SLOTS - 1 do
    local slot = pool + i * S.SLOT_SIZE
    if mem:s16(slot) == 1 then
      local verts = cb.alloc(0x280)
      mem:setU32(slot + 0x88, verts)
      local v = verts
      for j = 0, S.NODES - 1 do
        local n = slot + 0xA4 + j * S.NODE_SIZE
        local t = math.floor(j * 0x400 / 20)
        for side = 0, 1 do
          local mode = mem:s16(slot + 2)
          if mode == 1 then error("stream draw mode 1 (84168B00) is not ported", 0) end
          if mode == 0 and mem:f32(n) <= 0 then
            point = S.ring(mem, f32(mem:f32(n + 8) + f32(f32(side) * turn)), mem:f32(n + 4))
          end
          mem:setU16(v, short(f32(mem:f32(n + 0xC) + point[1])))
          mem:setU16(v + 2, short(f32(mem:f32(n + 0x10) + point[2])))
          mem:setU16(v + 4, short(f32(mem:f32(n + 0x14) + point[3])))
          mem:setU16(v + 8, side * 0x400); mem:setU16(v + 0xA, t)
          mem:setU8(v + 0xC, 0xFF); mem:setU8(v + 0xD, 0xFF); mem:setU8(v + 0xE, 0xFF)
          mem:setU8(v + 0xF, 0x40)
          v = v + 0x10
        end
      end
      dl = write(mem, dl, 0xDE000000, S.MATERIAL)
      cb.combine(dl, slot)
      dl = dl + 8
      dl = write(mem, dl, 0xFA000000 + mem:u8(slot + 0xC),
        mem:u8(slot + 8) * 0x1000000 + mem:u8(slot + 9) * 0x10000 + mem:u8(slot + 0xA) * 0x100
        + alphaByte(mem:u8(slot + 0xB), mem:f32(slot + 0x14)))
      dl = write(mem, dl, 0xFB000000,
        mem:u8(slot + 0xD) * 0x1000000 + mem:u8(slot + 0xE) * 0x10000 + mem:u8(slot + 0xF) * 0x100
        + alphaByte(mem:u8(slot + 0x10), mem:f32(slot + 0x18)))
      dl = cb.material(dl, slot)
      dl = write(mem, dl, 0xE7000000, 0)
      dl = cb.strip(dl, slot)
      mem:setU32(S.STALE, 0x5000)
    end
  end
  return dl
end

return S
