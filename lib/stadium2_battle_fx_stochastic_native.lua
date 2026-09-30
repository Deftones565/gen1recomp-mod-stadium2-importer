-- Fragment 79's shared twenty-six-slot leaf / petal controller (effect
-- families 3 and 15: Razor Leaf, Petal Dance), ported from the US assembly
-- (pret/pokestadiumgs c0e10f23, fragment79_3C60B0 and fragment79_3D4DA0;
-- still GLOBAL_ASM in michiiik/pokestadiumgs 1b6dc17c) to Lua. It works on
-- Stadium's own memory layout in a stadium2_native_memory, so the draw
-- builder writes the same display list and vertices the ROM does. Checked
-- byte for byte against the ROM (tests/stadium2_battle_fx_stochastic_native_rom_test.lua).
--
-- The effect's host calls are callbacks (the same boundaries the port's
-- other families use):
--   origin() -> {x, y, z}   84109780 (via 841568A0)
--   target() -> {x, y, z}   841098FC
--   scale() -> number       84109544 (via 84156920)
--   signal() -> integer     841094EC
--   random() -> integer     guRandom (8007AFA0), an injected generator
--   alloc(bytes) -> address 80006DEC, the frame's display-list arena
local f32 = require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_float")
local U = require("mods.STADIUM2_IMPORTER.lib.stadium2_libultra")
local ffi = require("ffi")

local N = {}

-- The host hands vectors and the scale over through float memory.
local function vec3(v) return { f32(v[1]), f32(v[2]), f32(v[3]) } end

N.POOL = 0x8419F070        -- D_8419F070: 26 slots of 0x360 bytes
N.SLOT_SIZE, N.SLOTS = 0x360, 26
N.ELEMENT_SIZE, N.ELEMENTS = 0x50, 10 -- slot + 0x40: ten trail elements
N.COUNTER = { [3] = 0x841A4D54, [15] = 0x841A4D56 } -- D_841A4D54 / 56
N.SPAWN_SIZE = { [3] = 0x8418C56C, [15] = 0x8418C570 } -- D_8418C56C / 70
N.FRAME = 0x841A4DB2       -- D_841A4DB2: frames since the effect began
N.PHASE = 0x841A4DB4       -- D_841A4DB4: 0 running, 1 ending, 2 draining
N.END_FRAME = 0x841A4DB0   -- D_841A4DB0
N.TEXTURES = 0x8418CA20    -- D_8418CA20: texture per draw index
N.SPRITE_DL = 0x84187CC0   -- D_84187CC0: the sprite quad's display list
N.TRAIL_DL = 0x84187C30    -- D_84187C30: the trail's material

local cell = ffi.new("union { double d; uint32_t u[2]; }")
local function double(mem, address)
  cell.u[1], cell.u[0] = mem:u32(address), mem:u32(address + 4)
  return tonumber(cell.d)
end

-- (int) of a float, stored as a 16-bit halfword.
local function short(v) return U.toInt(v) % 0x10000 end
local function signedShort(v)
  v = U.toInt(v) % 0x10000
  return v >= 0x8000 and v - 0x10000 or v
end

-- 84166130: empty the pool and reset the phase and frame counters.
function N.initPool(mem)
  mem:setU16(N.PHASE, 0)
  mem:setU16(N.FRAME, 0)
  for i = 0, N.SLOTS - 1 do
    local slot = N.POOL + i * N.SLOT_SIZE
    mem:setU16(slot, 0); mem:setU16(slot + 4, 0); mem:setU16(slot + 6, 0)
    for k = 0, N.ELEMENTS - 1 do
      local e = slot + 0x40 + k * N.ELEMENT_SIZE
      mem:setU8(e, 0)
      mem:setF32(e + 4, 1)
      mem:setF32(e + 8, 0)
      for o = 0x10, 0x24, 4 do mem:setF32(e + o, 0) end
    end
  end
end

-- 84157AB0 / 84157CB0: the family's init (84156BA0 has nothing to do here).
function N.init(mem, family)
  mem:setU16(N.COUNTER[family], 0)
  N.initPool(mem)
end

-- 84166270(x, y, z, drift, vy, vz, r, g, b, alpha, spin, length, width,
-- life): take the first free slot, place its ten trail elements at the
-- spawn point with the drift velocity, a falling acceleration and a random
-- angle each; alpha fades along the trail. Nothing while the phase is 2.
function N.spawn(mem, cb, a)
  if mem:s16(N.PHASE) == 2 then return end
  local half = f32(f32(cb.scale()) * 0.5)
  local pos = { a.x, f32(f32(80 * half) + a.y), a.z }
  local vel = { a.drift, a.vy, a.vz }
  local acc = { 0, f32(half * -2), 0 }
  local spinStep = mem:f32(0x8418C8E0)
  for i = 0, N.SLOTS - 1 do
    local slot = N.POOL + i * N.SLOT_SIZE
    if mem:s16(slot) == 0 then
      mem:setU16(slot, 1); mem:setU16(slot + 2, 0); mem:setU16(slot + 4, 0)
      mem:setU16(slot + 6, a.life)
      mem:setU8(slot + 0xA, a.r); mem:setU8(slot + 0xB, a.g); mem:setU8(slot + 0xC, a.b)
      mem:setVec(slot + 0x24, pos)
      mem:setF32(slot + 0x18, a.width)
      mem:setF32(slot + 0x14, half)
      mem:setF32(slot + 0x10, a.spin)
      mem:setU16(slot + 8, a.x > 0 and 0xFFFF or 1)
      for k = 0, N.ELEMENTS - 1 do
        local e = slot + 0x40 + k * N.ELEMENT_SIZE
        mem:setF32(e + 4, a.length)
        mem:setU8(e, math.floor(a.alpha * (9 - k) / 10))
        local turn = cb.random() % 120
        mem:setF32(e + 8, f32(f32(f32(turn) * spinStep) / 120))
        mem:setVec(e + 0x10, pos)
        mem:setVec(e + 0x1C, vel)
        mem:setVec(e + 0x28, acc)
      end
      return
    end
  end
end

-- 84157ADC / 84157CDC: the family's update. Every second frame a leaf is
-- spawned near the origin, drifting away from the centre; then the pool
-- steps (8416691C), whose result is returned.
function N.update(mem, cb, family)
  local counter = N.COUNTER[family]
  mem:setU16(counter, mem:s16(counter) + 1)
  if mem:s16(counter) % 2 == 0 then
    local scale = f32(cb.scale())
    local origin = vec3(cb.origin())
    local x = f32(f32(f32((cb.random() % 50) - 25) * scale) + origin[1])
    local y = f32(f32(f32((cb.random() % 60) - 30) * scale) + origin[2])
    local z = f32(f32(f32((cb.random() % 50) - 25) * scale) + origin[3])
    N.spawn(mem, cb, { x = x, y = y, z = z, drift = x > 0 and -10 or 10, vy = 0, vz = 0,
      r = 0xFF, g = 0xFF, b = 0xFF, alpha = 0x64, spin = mem:f32(N.SPAWN_SIZE[family]),
      length = 1, width = 4, life = 0x1E })
  end
  return N.step(mem, cb)
end

-- 841665D4(slot): one frame of a leaf. The head element carries the motion:
-- mode 0 flutters down (the swing angle advances by +0x10 and pushes the
-- acceleration sideways) and, after 21 frames, turns toward the target with
-- a vertical speed that reaches it; mode 1 flies at it, the sideways speed
-- ramping by 2 toward +-20. Every other element takes the one before it's
-- previous frame, so the trail follows the head.
function N.stepSlot(mem, cb, slot)
  local half = mem:f32(slot + 0x14)
  for k = 0, N.ELEMENTS - 1 do
    local e = slot + 0x40 + k * N.ELEMENT_SIZE
    -- remember this frame's values (+0x34 length, +0xC angle, +0x38 position,
    -- +0x44 velocity) for the element behind
    mem:setF32(e + 0x34, mem:f32(e + 4))
    mem:setF32(e + 0xC, mem:f32(e + 8))
    mem:setVec(e + 0x38, mem:vec(e + 0x10))
    mem:setVec(e + 0x44, mem:vec(e + 0x1C))
    if k == 0 then
      local mode = mem:s16(slot + 2)
      if mode == 0 then
        for c = 0, 2 do mem:setF32(e + 0x10 + c * 4, f32(mem:f32(e + 0x10 + c * 4) + mem:f32(e + 0x28 + c * 4))) end
        mem:setF32(e + 8, f32(mem:f32(e + 8) + mem:f32(slot + 0x10)))
        mem:setF32(e + 0x28, f32(mem:f32(e + 0x28) + f32(U.sinf(mem:f32(e + 8)) * half)))
        mem:setF32(e + 0x30, f32(mem:f32(e + 0x30) + f32(U.cosf(mem:f32(e + 8)) * half)))
        if mem:s16(slot + 4) >= 0x15 then
          mem:setU16(slot + 2, 1); mem:setU16(slot + 4, 0)
          local target = vec3(cb.target())
          local dx = math.abs(f32(target[1] - mem:f32(e + 0x10)))
          local ty = target[2]
          if ty < 0 then ty = 0 end
          local dy = f32(ty - mem:f32(e + 0x14))
          mem:setF32(e + 0x20, f32(f32(dy * 20) / dx))
        end
      elseif mode == 1 then
        local vx = mem:f32(e + 0x1C)
        for c = 0, 2 do mem:setF32(e + 0x10 + c * 4, f32(mem:f32(e + 0x10 + c * 4) + mem:f32(e + 0x1C + c * 4))) end
        mem:setF32(e + 8, f32(mem:f32(e + 8) + mem:f32(slot + 0x10)))
        if mem:s16(slot + 8) > 0 then
          mem:setF32(e + 0x1C, f32(vx + 2))
          if 20 < mem:f32(e + 0x1C) then mem:setF32(e + 0x1C, 20) end
        else
          mem:setF32(e + 0x1C, f32(vx - 2))
          if mem:f32(e + 0x1C) < -20 then mem:setF32(e + 0x1C, -20) end
        end
      end
      mem:setF32(e + 4, f32(mem:f32(e + 4) + 2))
      local width = mem:f32(slot + 0x18)
      if width < mem:f32(e + 4) then mem:setF32(e + 4, width) end
    else
      local prev = e - N.ELEMENT_SIZE
      mem:setVec(e + 0x10, mem:vec(prev + 0x38))
      mem:setF32(e + 8, mem:f32(prev + 0xC))
      mem:setVec(e + 0x1C, mem:vec(prev + 0x44))
      mem:setF32(e + 4, mem:f32(prev + 0x34))
    end
  end
end

-- 8416691C: the pool's frame. Once the host signals the end (841094EC ==
-- 1), the effect runs 20 more frames (phase 1), stops spawning (phase 2)
-- and returns -1 fifty frames after that. Live slots age; a slot that has
-- turned toward the target retires after its life (+6).
function N.step(mem, cb)
  mem:setU16(N.FRAME, mem:s16(N.FRAME) + 1)
  local signal = cb.signal()
  local frame = mem:s16(N.FRAME)
  local phase = mem:s16(N.PHASE)
  if signal == 1 and phase == 0 then
    mem:setU16(N.END_FRAME, frame + 0x46)
    mem:setU16(N.PHASE, 1)
  elseif phase == 1 then
    if mem:s16(N.END_FRAME) - 0x32 < frame then mem:setU16(N.PHASE, 2) end
  elseif phase == 2 then
    if mem:s16(N.END_FRAME) < frame then return -1 end
  end
  for i = 0, N.SLOTS - 1 do
    local slot = N.POOL + i * N.SLOT_SIZE
    if mem:s16(slot) == 1 then
      mem:setU16(slot + 4, mem:s16(slot + 4) + 1)
      if mem:s16(slot + 2) == 1 and mem:s16(slot + 6) < mem:s16(slot + 4) then
        mem:setU16(slot, 0)
      else
        N.stepSlot(mem, cb, slot)
      end
    end
  end
  return 0
end

-- 8416654C(angle, length): the point `length` along the leaf's local Z,
-- turned by guRotateRPYF(90, a, a), a = angle * D_8418C8E8 / D_8418C8F0.
function N.edge(mem, angle, length)
  local a = f32(angle * double(mem, 0x8418C8E8) / double(mem, 0x8418C8F0))
  return { U.mtxXFMF(U.rotateRPYF(90, a, a), 0, 0, length) }
end

local function write(mem, at, w0, w1)
  mem:setU32(at, w0); mem:setU32(at + 4, w1)
  return at + 8
end

-- 84166A64(dl, texture): the display list for every live leaf: a sprite
-- (matrix: translate, guRotateRPY(90, a, a), scale) while its head is above
-- the ground, and a twenty-vertex trail strip built from each element's two
-- edge points. Returns the end of the display list.
function N.draw(mem, cb, dl, texture)
  dl = write(mem, dl, 0xFD100000, mem:u32(N.TEXTURES + texture * 4))
  dl = write(mem, dl, 0xF5100000, 0x07094250)
  dl = write(mem, dl, 0xE6000000, 0)
  dl = write(mem, dl, 0xF3000000, 0x073FF100)
  dl = write(mem, dl, 0xE7000000, 0)
  dl = write(mem, dl, 0xF5101000, 0x00094250)
  dl = write(mem, dl, 0xF2000000, 0x0007C07C)
  local turns = double(mem, 0x8418C8F8)
  local edgeTurn = mem:f32(0x8418C900)
  for i = 0, N.SLOTS - 1 do
    local slot = N.POOL + i * N.SLOT_SIZE
    if mem:s16(slot) == 1 then
      local scale = mem:f32(slot + 0x14)
      local head = slot + 0x40
      if 0 < mem:f32(head + 0x14) then
        local a = f32(f32(mem:f32(head + 8) * 360) / turns)
        local mtx = cb.alloc(0x40)
        U.translate(mem, mtx, mem:f32(head + 0x10), mem:f32(head + 0x14), mem:f32(head + 0x18))
        local rotate, scaled = U.rotateRPYF(90, a, a), U.scaleF(scale, scale, scale)
        U.mtxF2L(U.mtxCatF(U.mtxL2F(mem, N.scratch(mem, rotate)), U.mtxL2F(mem, mtx)), mem, mtx)
        U.mtxF2L(U.mtxCatF(U.mtxL2F(mem, N.scratch(mem, scaled)), U.mtxL2F(mem, mtx)), mem, mtx)
        dl = write(mem, dl, 0xDA380000, mtx)
        dl = write(mem, dl, 0xDE000000, N.SPRITE_DL)
        dl = write(mem, dl, 0xD8380002, 0x40)
      end
      local verts = cb.alloc(0x140)
      mem:setU32(N.POOL + i * N.SLOT_SIZE + 0x20, verts)
      local v = verts
      for k = 0, N.ELEMENTS - 1 do
        local e = head + k * N.ELEMENT_SIZE
        for side = 0, 1 do
          local angle = mem:f32(e + 8)
          if side == 1 then angle = f32(angle + edgeTurn) end
          local p = N.edge(mem, angle, f32(mem:f32(e + 4) * scale))
          local y = signedShort(f32(mem:f32(e + 0x14) + p[2]))
          if y < 0 then y = 0 end
          mem:setU16(v + 2, y)
          mem:setU16(v, short(f32(mem:f32(e + 0x10) + p[1])))
          mem:setU16(v + 4, short(f32(mem:f32(e + 0x18) + p[3])))
          mem:setU8(v + 0xC, mem:u8(slot + 0xA))
          mem:setU8(v + 0xD, mem:u8(slot + 0xB))
          mem:setU8(v + 0xE, mem:u8(slot + 0xC))
          mem:setU8(v + 0xF, mem:u8(e))
          v = v + 0x10
        end
      end
      dl = write(mem, dl, 0xDE000000, N.TRAIL_DL)
      for q = 0, 8 do
        dl = write(mem, dl, 0x01004008, verts + q * 0x20)
        dl = write(mem, dl, 0x06000402, 0x00040602)
      end
    end
  end
  return dl
end

-- The fixed-point form of a float matrix, as the ROM's stack Mtx holds it
-- between guRotateRPY / guScale and guMtxCatL (the round trip rounds).
N.SCRATCH = 0x85FFFF00
function N.scratch(mem, mf)
  U.mtxF2L(mf, mem, N.SCRATCH)
  return N.SCRATCH
end

return N
