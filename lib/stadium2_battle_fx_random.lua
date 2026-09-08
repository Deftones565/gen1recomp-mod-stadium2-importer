-- Deterministic, renderer-neutral implementation of fragment-79 random motion.
--
-- The ROM owns this state at main addresses 0x800A1430 and 0x80138C00.  A
-- caller supplies their initial values explicitly here; this module never
-- reads or mutates host globals and never calls math.random().  The optional
-- trig tables are also caller-owned because the paired TB table is populated
-- by the game at runtime.
local Random = {}
Random.__index = Random

local U16 = 0x10000
local U32 = 0x100000000
local U31 = 0x80000000

local function copy(value, seen)
  if type(value) ~= "table" then return value end
  seen = seen or {}
  if seen[value] then return seen[value] end
  local out = {}
  seen[value] = out
  for key, child in pairs(value) do
    out[copy(key, seen)] = copy(child, seen)
  end
  return out
end

local function integer(value)
  value = tonumber(value)
  if value == nil or value ~= value or value ~= math.floor(value) then return nil end
  return value
end

local function u32(value)
  value = tonumber(value) or 0
  value = value % U32
  return value < 0 and value + U32 or value
end

local function u16(value)
  return u32(value) % U16
end

local function sign16(value)
  value = u16(value)
  return value >= 0x8000 and value - U16 or value
end

local function add32(a, b)
  return (u32(a) + u32(b)) % U32
end

-- Lua numbers are exact for the 16-bit partial products below.  This is the
-- low-32-bit equivalent of MIPS `multu`, without depending on Lua 5.3 bitops
-- or losing low bits in a 64-bit-sized product represented as a double.
local function mul32(a, b)
  a, b = u32(a), u32(b)
  local a0, a1 = a % U16, math.floor(a / U16)
  local b0, b1 = b % U16, math.floor(b / U16)
  local cross = (a0 * b1 + a1 * b0) % U16
  return (a0 * b0 + cross * U16) % U32
end

local function single(value)
  -- The bundled Lua is 5.3+, but retain a scalar fallback for LuaJIT hosts.
  if string.pack and string.unpack then
    local packed = string.pack("<f", value)
    return string.unpack("<f", packed)
  end
  return value
end

local function number(value)
  value = tonumber(value)
  return value == nil and 0 or value
end

local function fmul(a, b) return single(single(a) * single(b)) end
local function fadd(a, b) return single(single(a) + single(b)) end
local function fsub(a, b) return single(single(a) - single(b)) end
local function fneg(a) return single(-single(a)) end

-- MIPS `cvt.s.w` treats the register as signed, then the fragment adds
-- 2147483648.0 when its sign bit is set to obtain an unsigned float.
local function unsignedFloat(value)
  value = u32(value)
  if value < U31 then return single(value) end
  return single(single(value - U32) + single(2147483648.0))
end

local function optionTables(options)
  local tables = type(options.tables) == "table" and options.tables or {}
  return options.tableA or tables.a or tables.A or tables.TA
    or tables[1], options.tableB or tables.b or tables.B or tables.TB
    or tables[2]
end

function Random.new(seedOrOptions, maybeOptions)
  local options
  if type(seedOrOptions) == "table" then
    options = copy(seedOrOptions)
  else
    options = type(maybeOptions) == "table" and copy(maybeOptions) or {}
    if seedOrOptions ~= nil then options.seed = seedOrOptions end
  end
  local seed = options.state
  if seed == nil then seed = options.seed end
  seed = integer(seed or 0)
  if seed == nil then seed = 0 end
  local offset = integer(options.offset)
  if offset == nil then offset = integer(options.globalOffset) end
  if offset == nil then offset = 0 end
  local tableA, tableB = optionTables(options)
  return setmetatable({
    state = u32(seed),
    offset = u32(offset),
    seed = u32(seed),
    tableA = tableA,
    tableB = tableB,
    diagnostics = {},
  }, Random)
end

Random.create = Random.new
Random.init = Random.new

function Random:_diagnostic(code, message)
  local item = {code = code, severity = "warning", kind = "random-motion",
    message = message}
  self.diagnostics[#self.diagnostics + 1] = item
  return nil, message
end

function Random:clearDiagnostics()
  self.diagnostics = {}
  return self
end

function Random:setSeed(value)
  value = integer(value)
  if value == nil then return self:_diagnostic("invalid-seed", "seed must be an integer") end
  self.seed, self.state = u32(value), u32(value)
  return self
end

function Random:setOffset(value)
  value = integer(value)
  if value == nil then return self:_diagnostic("invalid-offset", "offset must be an integer") end
  self.offset = u32(value)
  return self
end

function Random:next()
  local state = u32(self.state)
  local four = (state * 4) % U32
  local left = (four + 2) % U32
  local right = (four + 3) % U32
  local product = mul32(left, right)
  self.state = math.floor(product / 4)
  return self.state
end

Random.nextU32 = Random.next
Random.next_u32 = Random.next

-- Raw imported 0x81100094 semantics.  Unlike the fragment-79 wrapper this
-- does not mask the bound or apply the 0xffff -> 0x10000 sentinel.
function Random:bounded(bound)
  bound = integer(bound)
  if bound == nil then return self:_diagnostic("invalid-bound", "bound must be an integer") end
  bound = u32(bound)
  if bound == 0 then return 0 end
  local value = add32(self:next(), self.offset)
  local quotient = math.floor(value / 10)
  return quotient % bound
end

Random.randomBounded = Random.bounded
Random.random_bounded = Random.bounded

-- Raw imported 0x811000F8 semantics.
function Random:centered(bound)
  bound = integer(bound)
  if bound == nil then return self:_diagnostic("invalid-bound", "bound must be an integer") end
  bound = u32(bound)
  if bound == 0 then return 0 end
  return self:bounded(mul32(bound, 2)) - bound
end

Random.randomCentered = Random.centered
Random.random_centered = Random.centered

local function wrapperBound(value)
  value = integer(value)
  if value == nil then return nil end
  value = u16(value)
  return value == 0xFFFF and 0x10000 or value
end

-- Exact 0x84105E9C wrapper: mask bound to 16 bits, choose raw/centered
-- variant, and narrow the result back to signed 16 bits.
function Random:scalar(variant, bound)
  bound = wrapperBound(bound)
  if bound == nil then return self:_diagnostic("invalid-bound", "bound must be an integer") end
  if bound == 0 then return 0 end
  local value
  if number(variant) == 0 then value = self:bounded(bound)
  else value = self:centered(bound) end
  return sign16(value)
end

Random.randomScalar = Random.scalar
Random.random_scalar = Random.scalar

function Random:indexForAngle(angle)
  angle = integer(angle)
  if angle == nil then return self:_diagnostic("invalid-angle", "angle must be an integer") end
  return math.floor(u16(angle) / 16)
end

local function tableValue(source, index, address)
  if type(source) == "function" then
    local ok, value = pcall(source, index, address)
    if not ok then return nil end
    return tonumber(value)
  end
  if type(source) ~= "table" then return nil end
  -- Accept either a ROM-shaped 0-based table or an ordinary Lua 1-based
  -- fixture.  Presence of [0] disambiguates the two layouts.
  local value
  if source[0] ~= nil then value = source[index]
  else value = source[index + 1] end
  return tonumber(value)
end

function Random:setTables(tableA, tableB)
  self.tableA, self.tableB = tableA, tableB
  return self
end

function Random:trigAt(index)
  index = integer(index)
  if index == nil or index < 0 or index > 4095 then
    return self:_diagnostic("invalid-trig-index", "trig index must be in 0..4095")
  end
  local a = tableValue(self.tableA, index, 0x80087E50 + index * 4)
  local b = tableValue(self.tableB, index, 0x80098E50 + index * 4)
  if a == nil or b == nil then
    return self:_diagnostic("unresolved-trig-tables",
      "fragment-79 trig tables TA/TB require explicit runtime data")
  end
  return single(a), single(b)
end

Random.trig_at = Random.trigAt

local function angleValue(angles, names, index)
  if type(angles) ~= "table" then return nil end
  for _, name in ipairs(names) do
    if angles[name] ~= nil then return angles[name] end
  end
  return angles[index]
end

local function vectorAngles(angles)
  local p = angleValue(angles, {"p", "P", "angleP", "angle_p", "x"}, 1)
  local q = angleValue(angles, {"q", "Q", "angleQ", "angle_q", "y"}, 2)
  local r = angleValue(angles, {"r", "R", "angleR", "angle_r", "z"}, 3)
  return p, q, r
end

local function specParts(bound, offset, angles)
  if type(bound) ~= "table" then return bound, offset, angles end
  local spec = bound
  return spec.bound or spec.radius or spec[1],
    spec.offset or spec.origin or spec[2],
    angles or spec.angles or spec.context or spec.angleContext
end

-- Modes 2, 3, and 5 are the fragment-79 inline angle-table paths.  For
-- convenience modes 0 and 1 are also supported when `bound` is a 3-element
-- table, using the exact scalar wrapper component order.
function Random:vector(mode, bound, offset, angles)
  mode = integer(mode)
  if mode == nil then return self:_diagnostic("invalid-random-mode", "mode must be an integer") end

  if mode == 0 or mode == 1 then
    if type(bound) ~= "table" then
      return self:_diagnostic("invalid-random-vector", "mode 0/1 requires three bounds")
    end
    return {self:scalar(mode, bound[1]), self:scalar(mode, bound[2]),
      self:scalar(mode, bound[3])}
  end
  if mode ~= 2 and mode ~= 3 and mode ~= 5 then
    return self:_diagnostic("unsupported-random-mode", "only modes 0, 1, 2, 3, and 5 are proven")
  end
  bound, offset, angles = specParts(bound, offset, angles)

  local n, delta = integer(bound), integer(offset or 0)
  if n == nil or delta == nil then
    return self:_diagnostic("invalid-random-vector", "bound and offset must be integers")
  end
  n, delta = u16(n), u16(delta)
  local p, q, r = vectorAngles(angles)
  p = self:indexForAngle(p)
  if p == nil then return nil, "invalid P angle" end
  if mode ~= 5 then
    q, r = self:indexForAngle(q), self:indexForAngle(r)
    if q == nil or r == nil then
      return self:_diagnostic("invalid-random-vector", "modes 2/3 require P, Q, and R angles")
    end
  end

  -- The native code consumes the random value before loading the context
  -- angles, so preserve that state transition even if table data is missing.
  local magnitude = unsignedFloat(add32(self:bounded(n), delta))
  local ap, bp = self:trigAt(p)
  if ap == nil then return nil, bp end
  if mode == 5 then
    return {fmul(magnitude, ap), fmul(magnitude, bp), single(0)}
  end
  local aq, bq = self:trigAt(q)
  local ar, br = self:trigAt(r)
  if aq == nil or ar == nil then
    return self:_diagnostic("unresolved-trig-tables",
      "fragment-79 modes 2/3 require TA/TB for all three angles")
  end

  local x = fadd(fmul(aq, bp), fmul(fmul(ap, bq), ar))
  local y = fmul(fmul(fneg(magnitude), ap), br)
  local z = fsub(fmul(bp, bq), fmul(fmul(ar, ap), aq))
  return {fmul(magnitude, x), fmul(magnitude, y), fmul(magnitude, z)}
end

Random.randomVector = Random.vector
Random.random_vector = Random.vector

function Random:snapshot()
  return {
    seed = self.seed,
    state = self.state,
    offset = self.offset,
    diagnostics = copy(self.diagnostics),
  }
end

Random.stateSnapshot = Random.snapshot
Random.state_snapshot = Random.snapshot

function Random:restore(snapshot)
  if type(snapshot) ~= "table" then
    return self:_diagnostic("invalid-random-snapshot", "snapshot must be a table")
  end
  local state, offset = integer(snapshot.state), integer(snapshot.offset or 0)
  if state == nil or offset == nil then
    return self:_diagnostic("invalid-random-snapshot", "snapshot state and offset must be integers")
  end
  self.seed = u32(integer(snapshot.seed or state) or state)
  self.state, self.offset = u32(state), u32(offset)
  self.diagnostics = copy(snapshot.diagnostics or {})
  return self
end

function Random.fromSnapshot(snapshot, options)
  if type(snapshot) ~= "table" then return nil end
  options = type(options) == "table" and copy(options) or {}
  options.state, options.offset, options.seed = snapshot.state,
    snapshot.offset, snapshot.seed
  local out = Random.new(options)
  out.diagnostics = copy(snapshot.diagnostics or {})
  return out
end

Random.from_snapshot = Random.fromSnapshot

function Random:clone()
  return Random.fromSnapshot(self:snapshot(), {
    tableA = self.tableA, tableB = self.tableB,
  })
end

return Random
