-- libultra's gu routines as Stadium 2 (US) links them, ported to Lua from
-- the ultralib sources (pret/pokestadiumgs lib/ultralib/src/gu, commit
-- c0e10f23): sinf.c, cosf.c, mtxutil.c, mtxcatf.c, mtxcatl.c, translate.c,
-- scale.c, rotaterpy.c, rotate.c, normalize.c. Every single-precision operation is rounded to f32
-- as the VR4300 does; the double-precision parts of sinf/cosf stay double.
-- Checked against the ROM's own copies (tests/stadium2_libultra_rom_test.lua).
--
-- Float matrices (MtxF) are Lua tables indexed [i * 4 + j] (0..15). Fixed-
-- point matrices (Mtx) live in a stadium2_native_memory at an address:
-- 16 s16.16 integer halves then 16 fraction halves, as the RSP reads them.
local f32 = require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_float")
local bit = require("bit")

local U = {}

-- ROM addresses (US, linker_scripts/us/symbol_addrs_code.txt).
U.SINF, U.COSF = 0x80073F70, 0x8007E9C0
U.GU_SCALE, U.GU_MTX_XFMF, U.GU_RANDOM = 0x80073EC0, 0x8007AEF0, 0x8007AFA0
U.GU_MTX_CATF, U.GU_MTX_CATL, U.GU_MTX_L2F = 0x8007CF00, 0x8007CFF0, 0x8007D060
U.GU_ROTATE_RPYF, U.GU_ROTATE_RPY = 0x8007D310, 0x8007D454
U.GU_TRANSLATE, U.GU_MTX_F2L = 0x80082A00, 0x80084780
U.SQRTF, U.GU_ROTATE_F, U.GU_NORMALIZE = 0x8007AEC0, 0x8007DB50, 0x8007DF20

-- Plain-Lua bit conversions (the mod sandbox refuses ffi at run time).
local Memory = require("mods.STADIUM2_IMPORTER.lib.stadium2_native_memory")
local double = Memory.wordsToDouble
local floatBits = Memory.floatWord
local function int32(v)
  v = v % 4294967296
  return v >= 2147483648 and v - 4294967296 or v
end
-- (int) of a float or double: truncation toward zero, wrapped to 32 bits
-- as the VM's trunc.w does.
local function toInt(v)
  return int32(v < 0 and math.ceil(v) or math.floor(v))
end
U.toInt = toInt

-- sinf.c / cosf.c constants (du hex words).
local P = {
  double(0x3ff00000, 0x00000000), double(0xbfc55554, 0xbc83656d),
  double(0x3f8110ed, 0x3804c2a0), double(0xbf29f6ff, 0xeea56814),
  double(0x3ec5dbdf, 0x0e314bfe),
}
local RPI = double(0x3fd45f30, 0x6dc9c883)
local PIHI = double(0x400921fb, 0x50000000)
local PILO = double(0x3e6110b4, 0x611a6263)
local function ROUND(d) return toInt(d >= 0 and d + 0.5 or d - 0.5) end
local function poly(xsq)
  return ((P[5] * xsq + P[4]) * xsq + P[3]) * xsq + P[2]
end

-- __sinf (80073F70).
function U.sinf(x)
  x = f32(x)
  local xpt = bit.band(bit.arshift(floatBits(x), 22), 0x1ff)
  if xpt < 0xff then
    if xpt >= 0xe6 then
      local dx = x
      local xsq = dx * dx
      return f32(dx + (dx * xsq) * poly(xsq))
    end
    return x
  end
  if xpt < 0x136 then
    local dx = x
    local n = ROUND(dx * RPI)
    local dn = n
    dx = dx - dn * PIHI
    dx = dx - dn * PILO
    local xsq = dx * dx
    local result = f32(dx + (dx * xsq) * poly(xsq))
    if n % 2 == 0 then return result end
    return -result
  end
  if x ~= x then return x end
  return 0
end

-- __cosf (8007E9C0).
function U.cosf(x)
  x = f32(x)
  local xpt = bit.band(bit.arshift(floatBits(x), 22), 0x1ff)
  if xpt < 0x136 then
    local dx = math.abs(x)
    local n = ROUND(dx * RPI + 0.5)
    local dn = n - 0.5
    dx = dx - dn * PIHI
    dx = dx - dn * PILO
    local xsq = dx * dx
    local result = f32(dx + (dx * xsq) * poly(xsq))
    if n % 2 == 0 then return result end
    return -result
  end
  if x ~= x then return x end
  return 0
end

-- guMtxIdentF.
function U.identF()
  local mf = {}
  for i = 0, 15 do mf[i] = (i % 5 == 0) and 1 or 0 end
  return mf
end

-- guMtxF2L(mf, m): FTOFIX32 is (long)(x * 65536.0f).
function U.mtxF2L(mf, mem, m)
  local ai, af = m, m + 32
  for i = 0, 3 do
    for j = 0, 1 do
      local e1 = toInt(f32(mf[i * 4 + j * 2] * 65536))
      local e2 = toInt(f32(mf[i * 4 + j * 2 + 1] * 65536))
      mem:setU32(ai, bit.bor(bit.band(e1, 0xffff0000), bit.band(bit.rshift(e2, 16), 0xffff)) % 4294967296)
      mem:setU32(af, bit.bor(bit.band(bit.lshift(e1, 16), 0xffff0000), bit.band(e2, 0xffff)) % 4294967296)
      ai, af = ai + 4, af + 4
    end
  end
end

-- guMtxL2F(mf, m): FIX32TOF is (float)q * (1.0f / 65536).
function U.mtxL2F(mem, m)
  local mf = {}
  local ai, af = m, m + 32
  local scale = f32(1 / 65536)
  for i = 0, 3 do
    for j = 0, 1 do
      local a, f = mem:u32(ai), mem:u32(af)
      local e1 = bit.bor(bit.band(a, 0xffff0000), bit.band(bit.rshift(f, 16), 0xffff))
      local e2 = bit.bor(bit.band(bit.lshift(a, 16), 0xffff0000), bit.band(f, 0xffff))
      mf[i * 4 + j * 2] = f32(f32(e1) * scale)
      mf[i * 4 + j * 2 + 1] = f32(f32(e2) * scale)
      ai, af = ai + 4, af + 4
    end
  end
  return mf
end

-- guMtxCatF(mf, nf) -> res = mf x nf.
function U.mtxCatF(mf, nf)
  local res = {}
  for i = 0, 3 do
    for j = 0, 3 do
      local t = 0
      for k = 0, 3 do t = f32(t + f32(mf[i * 4 + k] * nf[k * 4 + j])) end
      res[i * 4 + j] = t
    end
  end
  return res
end

-- guMtxCatL(m, n, res) on fixed-point matrices in memory.
function U.mtxCatL(mem, m, n, res)
  U.mtxF2L(U.mtxCatF(U.mtxL2F(mem, m), U.mtxL2F(mem, n)), mem, res)
end

-- guMtxXFMF(mf, x, y, z) -> ox, oy, oz.
function U.mtxXFMF(mf, x, y, z)
  local out = {}
  for c = 0, 2 do
    out[c + 1] = f32(f32(f32(f32(mf[c] * x) + f32(mf[4 + c] * y)) + f32(mf[8 + c] * z)) + mf[12 + c])
  end
  return out[1], out[2], out[3]
end

-- guTranslateF / guTranslate.
function U.translateF(x, y, z)
  local mf = U.identF()
  mf[12], mf[13], mf[14] = f32(x), f32(y), f32(z)
  return mf
end
function U.translate(mem, m, x, y, z) U.mtxF2L(U.translateF(x, y, z), mem, m) end

-- guScaleF / guScale.
function U.scaleF(x, y, z)
  local mf = U.identF()
  mf[0], mf[5], mf[10], mf[15] = f32(x), f32(y), f32(z), 1
  return mf
end
function U.scale(mem, m, x, y, z) U.mtxF2L(U.scaleF(x, y, z), mem, m) end

-- guRotateRPYF / guRotateRPY (degrees; dtor = (float)(3.1415926 / 180.0)).
U.DTOR = f32(3.1415926 / 180.0)
function U.rotateRPYF(r, p, h)
  r, p, h = f32(f32(r) * U.DTOR), f32(f32(p) * U.DTOR), f32(f32(h) * U.DTOR)
  local sinr, cosr = U.sinf(r), U.cosf(r)
  local sinp, cosp = U.sinf(p), U.cosf(p)
  local sinh, cosh = U.sinf(h), U.cosf(h)
  local mf = U.identF()
  mf[0] = f32(cosp * cosh)
  mf[1] = f32(cosp * sinh)
  mf[2] = -sinp
  mf[4] = f32(f32(f32(sinr * sinp) * cosh) - f32(cosr * sinh))
  mf[5] = f32(f32(f32(sinr * sinp) * sinh) + f32(cosr * cosh))
  mf[6] = f32(sinr * cosp)
  mf[8] = f32(f32(f32(cosr * sinp) * cosh) + f32(sinr * sinh))
  mf[9] = f32(f32(f32(cosr * sinp) * sinh) - f32(sinr * cosh))
  mf[10] = f32(cosr * cosp)
  return mf
end
function U.rotateRPY(mem, m, r, p, h) U.mtxF2L(U.rotateRPYF(r, p, h), mem, m) end

-- sqrtf (8007AEC0: sqrt.s).
function U.sqrtf(x) return f32(math.sqrt(f32(x))) end

-- guNormalize(&x, &y, &z).
function U.normalize(x, y, z)
  local m = f32(1 / U.sqrtf(f32(f32(f32(x * x) + f32(y * y)) + f32(z * z))))
  return f32(x * m), f32(y * m), f32(z * m)
end

-- guRotateF(mf, a, x, y, z): a degrees about the (normalised) axis.
function U.rotateF(a, x, y, z)
  x, y, z = U.normalize(f32(x), f32(y), f32(z))
  a = f32(f32(a) * U.DTOR)
  local sine, cosine = U.sinf(a), U.cosf(a)
  local t = f32(1 - cosine)
  local ab = f32(f32(x * y) * t)
  local bc = f32(f32(y * z) * t)
  local ca = f32(f32(z * x) * t)
  local mf = U.identF()
  local xs, ys, zs = f32(x * sine), f32(y * sine), f32(z * sine)
  t = f32(x * x)
  mf[0] = f32(t + f32(cosine * f32(1 - t)))
  mf[9] = f32(bc - xs)
  mf[6] = f32(bc + xs)
  t = f32(y * y)
  mf[5] = f32(t + f32(cosine * f32(1 - t)))
  mf[8] = f32(ca + ys)
  mf[2] = f32(ca - ys)
  t = f32(z * z)
  mf[10] = f32(t + f32(cosine * f32(1 - t)))
  mf[4] = f32(ab - zs)
  mf[1] = f32(ab + zs)
  return mf
end

return U
