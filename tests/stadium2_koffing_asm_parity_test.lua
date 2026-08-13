local Discovery = require("mods.STADIUM2_IMPORTER.lib.discovery")
local Build = require("mods.STADIUM2_IMPORTER.lib.build")
local Handlers = require("mods.STADIUM2_IMPORTER.lib.model_handlers")
local Layout = require("mods.STADIUM2_IMPORTER.lib.layout")
local Pack = require("mods.STADIUM2_IMPORTER.lib.pack")
local Renderer = require("mods.STADIUM2_IMPORTER.lib.renderer")
local Rom = require("mods.STADIUM2_IMPORTER.lib.rom")

local reportPath = os.getenv("STADIUM2_KOFFING_PARITY_TXT") or "stadium2_koffing_asm_parity_test.txt"
local report = assert(io.open(reportPath, "wb"))
local checks, failures = 0, 0

local function emit(fmt, ...)
  local line = select("#", ...) > 0 and string.format(fmt, ...) or tostring(fmt)
  print("[koffing-asm-parity] " .. line)
  report:write(line, "\n")
  report:flush()
end

local function check(ok, fmt, ...)
  checks = checks + 1
  if ok then
    emit("PASS " .. fmt, ...)
  else
    failures = failures + 1
    emit("FAIL " .. fmt, ...)
  end
end

local function u16(data, offset)
  local a, b = data:byte(offset + 1, offset + 2)
  if not b then return nil end
  return a * 256 + b
end

local function s16(data, offset)
  local v = u16(data, offset)
  if not v then return nil end
  return v >= 0x8000 and v - 0x10000 or v
end

local function u32(data, offset)
  local a, b, c, d = data:byte(offset + 1, offset + 4)
  if not d then return nil end
  return ((a * 256 + b) * 256 + c) * 256 + d
end

local function f32word(word)
  if word == nil then return nil end
  local sign = word >= 0x80000000 and -1 or 1
  local exponent = math.floor(word / 0x800000) % 0x100
  local mantissa = word % 0x800000
  if exponent == 0xFF then
    if mantissa == 0 then return sign * math.huge end
    return 0 / 0
  end
  if exponent == 0 then
    if mantissa == 0 then return sign < 0 and -0.0 or 0.0 end
    return sign * (mantissa / 0x800000) * 2 ^ -126
  end
  return sign * (1 + mantissa / 0x800000) * 2 ^ (exponent - 127)
end

local function vramOffset(address)
  return Layout.FRAGMENT26_ROM_START + address - Layout.FRAGMENT26_VRAM
end

local function romU32(data, address)
  return u32(data, vramOffset(address))
end

local function romS16(data, address)
  return s16(data, vramOffset(address))
end

local function romF32(data, address)
  return f32word(romU32(data, address))
end

local function hex(value)
  return value and string.format("0x%08X", value % 0x100000000) or "nil"
end

local function bits(value, shift, width)
  return math.floor((tonumber(value) or 0) / 2 ^ shift) % 2 ^ width
end

local function approx(a, b, epsilon)
  epsilon = epsilon or 0.000001
  return type(a) == "number" and type(b) == "number" and math.abs(a - b) <= epsilon
end

local function activeCount(effect)
  local count = 0
  for i = 1, 10 do
    local p = effect and effect.particles and effect.particles[i]
    if p and (p.active == true or p.active == 1) then count = count + 1 end
  end
  return count
end

local function activeEmitterCount(effect)
  local emitters, active, particles = effect and effect.emitters or {}, 0, 0
  for _, emitter in ipairs(emitters or {}) do
    local count = activeCount(emitter)
    if count > 0 then active = active + 1 end
    particles = particles + count
  end
  return active, particles
end

local function fileExists(path)
  local handle = path and io.open(path, "rb") or nil
  if not handle then return false end
  handle:close()
  return true
end

local function readFile(path)
  local handle = path and io.open(path, "rb") or nil
  if not handle then return nil end
  local bytes = handle:read("*a")
  handle:close()
  return bytes
end

local function shellQuote(value)
  return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function discoverCacheRoot()
  local env = os.getenv("STADIUM2_CACHE_ROOT")
  if env and fileExists(env .. "/normal/109.dsm") then return env end
  if fileExists("stadium2_importer/normal/109.dsm") then return "stadium2_importer" end
  local home = os.getenv("HOME")
  local xdg = os.getenv("XDG_DATA_HOME")
  local candidates = {}
  if xdg and xdg ~= "" then
    candidates[#candidates + 1] = xdg .. "/love/pokemon-love2d/stadium2_importer"
  end
  if home and home ~= "" then
    candidates[#candidates + 1] = home .. "/.local/share/love/pokemon-love2d/stadium2_importer"
    candidates[#candidates + 1] = home .. "/.local/share/stadium2_importer"
  end
  for _, root in ipairs(candidates) do
    if fileExists(root .. "/normal/109.dsm") then return root end
  end
  if io.popen and home and home ~= "" then
    local command = "find " .. shellQuote(home .. "/.local/share")
      .. " -type f -path '*/stadium2_importer/normal/109.dsm' -print -quit 2>/dev/null"
    local pipe = io.popen(command, "r")
    if pipe then
      local found = pipe:read("*l")
      pipe:close()
      if found then return found:match("^(.*)/normal/109%.dsm$") end
    end
  end
  return nil
end

local function fragmentOffset(extension, pointer)
  pointer = tonumber(pointer)
  if not pointer then return nil end
  local offset = pointer - (tonumber(extension and extension.sourceBase) or 0x8FF00000)
  if offset < 0 or not extension or type(extension.fragment) ~= "string" or offset >= #extension.fragment then return nil end
  return offset
end

local function decodeTriangleWord(word)
  return {
    math.floor(math.floor(word / 0x10000) % 256 / 2) + 1,
    math.floor(math.floor(word / 0x100) % 256 / 2) + 1,
    math.floor(word % 256 / 2) + 1,
  }
end

local function identity4()
  return {1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1}
end

local candidate = Discovery.find()
if not candidate then
  emit("FAIL could not locate Stadium 2 ROM")
  report:close()
  os.exit(2)
end

local raw, readErr = Discovery.read(candidate)
if not raw then
  emit("FAIL could not read Stadium 2 ROM: %s", tostring(readErr))
  report:close()
  os.exit(2)
end

local rom, info = Rom.validate(raw)
if not rom then
  emit("FAIL ROM validation failed: %s", tostring(info))
  report:close()
  os.exit(2)
end

emit("BEGIN rom=%s byteOrder=%s title=%s", tostring(candidate.path), tostring(info.byteOrder), tostring(info.title))

local descriptorWord = romU32(rom, 0x81000070)
local descriptorTarget = descriptorWord and ((descriptorWord % 0x04000000) * 4 + 0x80000000) or nil
check(descriptorTarget == 0x81005524, "descriptor 0x81000070 target=%s expected=0x81005524", hex(descriptorTarget))

local function jumpTarget(tableBase, species)
  return romU32(rom, tableBase + (species - 77) * 4)
end

local routes = {
  spawn = { base = 0x810062F4, expected = 0x81004620 },
  render = { base = 0x81006410, expected = 0x81004A38 },
  update = { base = 0x81006528, expected = 0x8100512C },
}

for name, route in pairs(routes) do
  local koffing = jumpTarget(route.base, 109)
  local weezing = jumpTarget(route.base, 110)
  check(koffing == route.expected, "Koffing %s route=%s expected=%s", name, hex(koffing), hex(route.expected))
  check(weezing == koffing, "Weezing shares Koffing %s route=%s", name, hex(weezing))
end

local initializerKoffing = jumpTarget(0x810061D0, 109)
local initializerWeezing = jumpTarget(0x810061D0, 110)
emit("INITIALIZER Koffing=%s Weezing=%s", hex(initializerKoffing), hex(initializerWeezing))

local growth = romF32(rom, 0x81006640)
local damping = romF32(rom, 0x81006650)
local renderScale = romF32(rom, 0x8100640C)
emit("CONSTANT growth@0x81006640=%.9g damping@0x81006650=%.9g renderScale@0x8100640C=%.9g", growth, damping, renderScale)

local criticalWords = {
  [0x81004A44] = 0x86380028,
  [0x81004A54] = 0x0018C843,
  [0x81004B18] = 0x241800C8,
  [0x81004B30] = 0x030FC823,
  [0x81005130] = 0xC4206640,
  [0x81005150] = 0x25580001,
  [0x81005160] = 0x29E10010,
  [0x8100518C] = 0xA6200000,
  [0x8100542C] = 0xE6280004,
  [0x81005438] = 0xE62A0008,
  [0x8100544C] = 0xE6320010,
  [0x81005450] = 0xE6280014,
  [0x81005454] = 0xE626000C,
  [0x81005458] = 0xE62A0018,
  [0x8100404C] = 0x3C013F80,
  [0x81004054] = 0x3C013F00,
  [0x8100405C] = 0x2403000A,
  [0x81004554] = 0xE60A0010,
  [0x81004558] = 0xE6060014,
  [0x81004564] = 0xE6040018,
  [0x8100456C] = 0xAE090004,
  [0x81004574] = 0xAE080008,
  [0x8100457C] = 0xAE09000C,
  [0x81004584] = 0xAE0C001C,
  [0x8100458C] = 0xAE0B0020,
  [0x81004594] = 0xA6000028,
  [0x81004598] = 0xA60D0000,
  [0x810045A0] = 0xAE0C0024,
  [0x810048BC] = 0xC626001C,
  [0x810048C4] = 0xC4640030,
  [0x810048C8] = 0xC420640C,
  [0x810048CC] = 0xC4720034,
  [0x810048D4] = 0xC6240020,
  [0x810048E8] = 0xC6320024,
  [0x810048F0] = 0xC46A0038,
  [0x8100490C] = 0x0C01CFB0,
  [0x810049A0] = 0x8E250004,
  [0x810049A4] = 0x8E260008,
  [0x810049A8] = 0x0C020A80,
  [0x810049AC] = 0x8E27000C,
  [0x810049B0] = 0x27A40268,
  [0x810049B4] = 0x27A50228,
  [0x810049B8] = 0x0C01F3FC,
  [0x810049C4] = 0x27A401E8,
  [0x810049C8] = 0x0C01F3FC,
  [0x81004A3C] = 0x3C0FFD90,
  [0x81004A70] = 0x3C0CF590,
  [0x81004A74] = 0x3C0D0708,
  [0x81004AA4] = 0x3C18070F,
  [0x81004AA8] = 0x3718F400,
  [0x81004AB0] = 0x3C0FF300,
  [0x81004AD8] = 0x3C09F580,
  [0x81004ADC] = 0x35290400,
  [0x81004AE0] = 0x354A0200,
  [0x81004AF8] = 0x26100008,
  [0x81004AFC] = 0x3C0BF200,
  [0x81004B04] = 0xAC6C0004,
}

for address, expected in pairs(criticalWords) do
  local actual = romU32(rom, address)
  check(actual == expected, "ASM word %s actual=%s expected=%s", hex(address), hex(actual), hex(expected))
end

emit("TEXTURE_PIPELINE_ORACLE_BEGIN")
local loadSetTileW0 = 0xF5900000
local loadSetTileW1 = 0x07080200
local loadBlockW1 = 0x070FF400
local renderSetTileW0 = 0xF5800400
local renderSetTileW1 = 0x00080200
local tileSizeW1 = 0x0007C07C
local loadFormat = bits(loadSetTileW0, 21, 3)
local loadSize = bits(loadSetTileW0, 19, 2)
local loadTexels = bits(loadBlockW1, 12, 12) + 1
local renderFormat = bits(renderSetTileW0, 21, 3)
local renderSize = bits(renderSetTileW0, 19, 2)
local tileWidth = bits(tileSizeW1, 12, 12) / 4 + 1
local tileHeight = bits(tileSizeW1, 0, 12) / 4 + 1
local frameBytes = loadTexels * 2
check(loadFormat == 4 and loadSize == 2, "Koffing load tile is I/16-bit load format fmt=%d siz=%d", loadFormat, loadSize)
check(loadTexels == 256, "Koffing G_LOADBLOCK texels=%d expected=256", loadTexels)
check(frameBytes == 0x200, "Koffing callback frame bytes=0x%X expected=0x200", frameBytes)
check(renderFormat == 4 and renderSize == 0, "Koffing render tile is I4 fmt=%d siz=%d", renderFormat, renderSize)
check(tileWidth == 32 and tileHeight == 32, "Koffing render tile dimensions=%.0fx%.0f expected=32x32", tileWidth, tileHeight)
check(loadSetTileW1 == 0x07080200 and renderSetTileW1 == 0x00080200, "Koffing load/render tile words match ASM")
emit("TEXTURE_PIPELINE fmt=%d siz=%d width=%.0f height=%.0f frameBytes=0x%X", renderFormat, renderSize, tileWidth, tileHeight, frameBytes)
emit("TEXTURE_PIPELINE_ORACLE_END")

emit("COMBINER_ORACLE_BEGIN")
local combineW0, combineW1 = 0xFC3097FF, 0x5FFEFE38
local a0 = bits(combineW0, 20, 4)
local c0 = bits(combineW0, 15, 5)
local aa0 = bits(combineW0, 12, 3)
local ac0 = bits(combineW0, 9, 3)
local b0 = bits(combineW1, 28, 4)
local d0 = bits(combineW1, 15, 3)
local ab0 = bits(combineW1, 12, 3)
local ad0 = bits(combineW1, 9, 3)
local a1 = bits(combineW0, 5, 4)
local c1 = bits(combineW0, 0, 5)
local b1 = bits(combineW1, 24, 4)
local d1 = bits(combineW1, 6, 3)
local aa1 = bits(combineW1, 21, 3)
local ac1 = bits(combineW1, 18, 3)
local ab1 = bits(combineW1, 3, 3)
local ad1 = bits(combineW1, 0, 3)
check(a0 == 3 and b0 == 5 and c0 == 1 and d0 == 5,
  "Koffing cycle0 color=(PRIMITIVE-ENVIRONMENT)*TEXEL0+ENVIRONMENT mux=%d,%d,%d,%d", a0,b0,c0,d0)
check(aa0 == 1 and ab0 == 7 and ac0 == 3 and ad0 == 7,
  "Koffing cycle0 alpha=TEXEL0*PRIMITIVE mux=%d,%d,%d,%d", aa0,ab0,ac0,ad0)
check(a1 == 15 and b1 == 15 and c1 == 31 and d1 == 0,
  "Koffing cycle1 color passes COMBINED mux=%d,%d,%d,%d", a1,b1,c1,d1)
check(aa1 == 7 and ab1 == 7 and ac1 == 7 and ad1 == 0,
  "Koffing cycle1 alpha passes COMBINED mux=%d,%d,%d,%d", aa1,ab1,ac1,ad1)
emit("COMBINER_ORACLE_END")

local frameExpected = { 1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8 }
local alphaExpected = { 200,187,174,161,148,135,122,109,96,83,70,57,44,31,18,5 }
emit("RENDER_ORACLE_BEGIN")
for age = 0, 15 do
  local frame = math.floor(age / 2) + 1
  local alpha = (200 - 13 * age) % 256
  check(frame == frameExpected[age + 1], "age=%d textureFrame=%d expected=%d", age, frame, frameExpected[age + 1])
  check(alpha == alphaExpected[age + 1], "age=%d alphaByte=%d expected=%d", age, alpha, alphaExpected[age + 1])
  emit("RENDER age=%d textureFrame=%d alphaByte=%d alpha=%.9g", age, frame, alpha, alpha / 255)
end
emit("RENDER_ORACLE_END")

check(type(Handlers.koffingGasRenderState) == "function", "implementation exposes Koffing render-state oracle")
if type(Handlers.koffingGasRenderState) == "function" then
  for age = 0, 15 do
    local frame, alphaByte, alpha = Handlers.koffingGasRenderState(age)
    check(frame == frameExpected[age + 1], "implementation age=%d textureFrame=%s expected=%d", age, tostring(frame), frameExpected[age + 1])
    check(alphaByte == alphaExpected[age + 1], "implementation age=%d alphaByte=%s expected=%d", age, tostring(alphaByte), alphaExpected[age + 1])
    check(approx(alpha, alphaExpected[age + 1] / 255), "implementation age=%d alpha=%s expected=%.9g", age, tostring(alpha), alphaExpected[age + 1] / 255)
  end
end

check(type(Handlers.koffingGasInitialize) == "function", "implementation exposes Koffing initializer")
if type(Handlers.koffingGasInitialize) == "function" then
  local origin = {4, 6, 8}
  local reference = {1, 2, 4}
  local particle = Handlers.koffingGasInitialize(origin, reference, 0.5)
  local length = math.sqrt(3 * 3 + 4 * 4 + 4 * 4)
  check(particle.active == true or particle.active == 1, "initializer active=%s expected=true", tostring(particle.active))
  check(particle.age == 0, "initializer age=%s expected=0", tostring(particle.age))
  check(approx(particle.x, 4) and approx(particle.y, 6) and approx(particle.z, 8),
    "initializer position=%s,%s,%s expected=4,6,8", tostring(particle.x), tostring(particle.y), tostring(particle.z))
  check(approx(particle.vx, 0.5 * 3 / length), "initializer vx=%s expected=%.9g", tostring(particle.vx), 0.5 * 3 / length)
  check(approx(particle.vy, 0.5 * 4 / length), "initializer vy=%s expected=%.9g", tostring(particle.vy), 0.5 * 4 / length)
  check(approx(particle.vz, 0.5 * 4 / length), "initializer vz=%s expected=%.9g", tostring(particle.vz), 0.5 * 4 / length)
  check(approx(particle.sx, 1) and approx(particle.sy, 1) and approx(particle.sz, 1),
    "initializer scale=%s,%s,%s expected=1,1,1", tostring(particle.sx), tostring(particle.sy), tostring(particle.sz))
end

local schedule = {}
emit("SPAWN_SCHEDULE_BEGIN")
for runtimeIndex = 0, 17 do
  local rowIndex = romS16(rom, 0x810060F8 + runtimeIndex * 2)
  local rowAddress = 0x81006020 + rowIndex * 12
  local row = {}
  for i = 0, 5 do row[i + 1] = romS16(rom, rowAddress + i * 2) end
  schedule[runtimeIndex] = { index = rowIndex, values = row }
  emit("SPAWN runtimeIndex=%d row=%d stateOther=%d state4=%d state3=%d,%d,%d state2=%d",
    runtimeIndex, rowIndex, row[1], row[2], row[3], row[4], row[5], row[6])
end
emit("SPAWN_SCHEDULE_END")

local function asmSpawnExpected(runtimeIndex, animationState, animationFrame, enabled)
  if not enabled or runtimeIndex < 0 or runtimeIndex >= 18 then return false end
  local row = schedule[runtimeIndex] and schedule[runtimeIndex].values
  if not row then return false end
  if animationState == 2 then return animationFrame == row[6] end
  if animationState == 3 then return animationFrame == row[3] or animationFrame == row[4] or animationFrame == row[5] end
  if animationState == 4 then return animationFrame == row[2] end
  return animationFrame == row[1]
end

local site = 0x1118
local record = {
  descriptor = 0x81000070,
  target = 0x81005524,
  phases = { 2 },
  family = "dynamic-object-renderer",
  runtimeDependent = true,
  commandOffset = site,
  bone = 5,
  boneId = 34,
  program = { textures = {} },
}
for i = 1, 8 do record.program.textures[i] = { slot = 20 + i } end

local function runHandler(state, runtime)
  local input = state or {}
  local ok, result = pcall(function()
    return select(1, Handlers.run({ record }, 2, runtime, input))
  end)
  if not ok then
    check(false, "implementation handler raised error: %s", tostring(result))
    return input
  end
  return result or input
end

local nonMatchFrame = 32767
check(not asmSpawnExpected(0, 2, nonMatchFrame, true), "ASM spawn oracle rejects nonmatching animation frame")
local nonMatchState = runHandler({}, {
  species = 109,
  callbackFrame = 0,
  sourceFrame = 0,
  dynamicObjectIndex = 0,
  dynamicObjectEnabled = true,
  animationState = 2,
  animationFrame = nonMatchFrame,
  dynamicObjectUpdateEnabled = true,
})
local nonMatchEffect = nonMatchState.dynamicObjectsBySite and nonMatchState.dynamicObjectsBySite[site]
check(activeCount(nonMatchEffect) == 0,
  "implementation nonmatching spawn active=%d expected=0", activeCount(nonMatchEffect))

local matchingFrame = schedule[0].values[6]
check(asmSpawnExpected(0, 2, matchingFrame, true), "ASM spawn oracle accepts matching state-2 frame=%d", matchingFrame)
local matchState = runHandler({}, {
  species = 109,
  callbackFrame = 0,
  sourceFrame = 0,
  dynamicObjectIndex = 0,
  dynamicObjectEnabled = true,
  animationState = 2,
  animationFrame = matchingFrame,
  dynamicObjectUpdateEnabled = true,
})
local matchEffect = matchState.dynamicObjectsBySite and matchState.dynamicObjectsBySite[site]
check(activeCount(matchEffect) == 1,
  "implementation matching spawn active=%d expected=1", activeCount(matchEffect))

local emitterSpecs = {}
for runtimeIndex = 0, 17 do
  emitterSpecs[runtimeIndex + 1] = {
    index = runtimeIndex, bone = runtimeIndex * 2 + 5,
    origin = {runtimeIndex + 1, runtimeIndex + 2, runtimeIndex + 3},
    reference = {0,0,0},
  }
end
local allState2 = runHandler({}, {
  callbackFrame = 0, sourceFrame = 0, frame = 0, species = 109,
  dynamicObjectEmitters = emitterSpecs, dynamicObjectEnabled = true,
  animationState = 2, animationFrame = matchingFrame,
})
local allEffect = allState2.dynamicObjectsBySite[site]
local activeEmitters, activeParticles = activeEmitterCount(allEffect)
check(type(allEffect.emitters) == "table" and #allEffect.emitters == 18,
  "production creates 18 Koffing emitter pools")
check(activeEmitters == 18 and activeParticles == 18,
  "state-2 frame=%d emits once from all 18 holes", matchingFrame)
local independentPools = true
for i = 1, 18 do
  local emitter = allEffect.emitters[i]
  local particle = emitter and emitter.particles and emitter.particles[1]
  if not (particle and particle.x == i and emitter.particles ~= allEffect.emitters[1 == i and 2 or 1].particles) then
    independentPools = false
    break
  end
end
check(independentPools, "all 18 emitters retain distinct origins and particle pools")

local staggerState = runHandler({}, {
  callbackFrame = 0, sourceFrame = 0, frame = 0, species = 109,
  dynamicObjectEmitters = emitterSpecs, dynamicObjectEnabled = true,
  animationState = 0, animationFrame = 32,
})
local staggerEmitters, staggerParticles = activeEmitterCount(staggerState.dynamicObjectsBySite[site])
check(staggerEmitters == 6 and staggerParticles == 6,
  "default frame=32 emits from scheduled 6/18 holes")

local outOfRangeState = runHandler({}, {
  species = 109,
  callbackFrame = 0,
  sourceFrame = 0,
  dynamicObjectIndex = 18,
  dynamicObjectEnabled = true,
  animationState = 2,
  animationFrame = matchingFrame,
  dynamicObjectUpdateEnabled = true,
})
local outOfRangeEffect = outOfRangeState.dynamicObjectsBySite and outOfRangeState.dynamicObjectsBySite[site]
check(activeCount(outOfRangeEffect) == 0,
  "implementation runtimeIndex=18 spawn active=%d expected=0", activeCount(outOfRangeEffect))

local disabledState = {
  dynamicObjectsBySite = {
    [site] = {
      family = "koffing-gas",
      species = 109,
      particles = {
        [1] = { active = true, age = 4, x = 1, y = 2, z = 3, vx = 0.1, vy = 0.2, vz = 0.3, sx = 0.4, sy = 0.5, sz = 0.6, scale = 0.4 },
      },
      lastFrame = 0,
      textureSlots = {},
      seed = 1,
    },
  },
}
local before = disabledState.dynamicObjectsBySite[site].particles[1]
local beforeSnapshot = { age = before.age, x = before.x, y = before.y, z = before.z, vx = before.vx, vy = before.vy, vz = before.vz, sx = before.sx, sy = before.sy, sz = before.sz }
disabledState = runHandler(disabledState, {
  species = 109,
  callbackFrame = 1,
  sourceFrame = 1,
  dynamicObjectIndex = 0,
  dynamicObjectEnabled = true,
  animationState = 2,
  animationFrame = nonMatchFrame,
  dynamicObjectUpdateEnabled = false,
  modelScaleY = 2,
})
local disabledParticle = disabledState.dynamicObjectsBySite[site].particles[1]
local disabledUnchanged = disabledParticle.age == beforeSnapshot.age
  and disabledParticle.x == beforeSnapshot.x and disabledParticle.y == beforeSnapshot.y and disabledParticle.z == beforeSnapshot.z
  and disabledParticle.vx == beforeSnapshot.vx and disabledParticle.vy == beforeSnapshot.vy and disabledParticle.vz == beforeSnapshot.vz
  and disabledParticle.sx == beforeSnapshot.sx and disabledParticle.sy == beforeSnapshot.sy and disabledParticle.sz == beforeSnapshot.sz
check(disabledUnchanged, "implementation leaves particle unchanged when ASM update gate is disabled")

local updateState = {
  dynamicObjectsBySite = {
    [site] = {
      family = "koffing-gas",
      species = 109,
      particles = {
        [1] = { active = true, age = 14, x = 1, y = 2, z = 3, vx = 0.1, vy = 0.2, vz = 0.3, sx = 0.4, sy = 0.5, sz = 0.6, scale = 0.4 },
      },
      lastFrame = 0,
      textureSlots = {},
      seed = 1,
    },
  },
}
local modelScaleY = 2
local expected = {
  active = true,
  age = 15,
  x = 1 + 0.1,
  y = 2 + 0.5 * modelScaleY + 0.2,
  z = 3 + 0.3,
  vx = 0.1 * damping,
  vy = 0.2 * damping,
  vz = 0.3 * damping,
  sx = 0.4 + growth,
  sy = 0.5 + growth,
  sz = 0.6 + growth,
}
updateState = runHandler(updateState, {
  species = 109,
  callbackFrame = 1,
  sourceFrame = 1,
  dynamicObjectIndex = 0,
  dynamicObjectEnabled = true,
  animationState = 2,
  animationFrame = nonMatchFrame,
  dynamicObjectUpdateEnabled = true,
  modelScaleY = modelScaleY,
  dynamicObjectGrowth = growth,
  dynamicObjectDamping = damping,
})
local actual = updateState.dynamicObjectsBySite[site].particles[1]
check(actual.age == expected.age, "update age=%s expected=%d", tostring(actual.age), expected.age)
check((actual.active == true or actual.active == 1) == expected.active, "update active=%s expected=true", tostring(actual.active))
check(approx(actual.x, expected.x), "update x=%s expected=%.9g", tostring(actual.x), expected.x)
check(approx(actual.y, expected.y), "update y=%s expected=%.9g", tostring(actual.y), expected.y)
check(approx(actual.z, expected.z), "update z=%s expected=%.9g", tostring(actual.z), expected.z)
check(approx(actual.vx, expected.vx), "update vx=%s expected=%.9g", tostring(actual.vx), expected.vx)
check(approx(actual.vy, expected.vy), "update vy=%s expected=%.9g", tostring(actual.vy), expected.vy)
check(approx(actual.vz, expected.vz), "update vz=%s expected=%.9g", tostring(actual.vz), expected.vz)
check(approx(actual.sx, expected.sx), "update sx=%s expected=%.9g", tostring(actual.sx), expected.sx)
check(approx(actual.sy, expected.sy), "update sy=%s expected=%.9g", tostring(actual.sy), expected.sy)
check(approx(actual.sz, expected.sz), "update sz=%s expected=%.9g", tostring(actual.sz), expected.sz)

local expireState = {
  dynamicObjectsBySite = {
    [site] = {
      family = "koffing-gas",
      species = 109,
      particles = {
        [1] = { active = true, age = 15, x = 1, y = 2, z = 3, vx = 0.1, vy = 0.2, vz = 0.3, sx = 0.4, sy = 0.5, sz = 0.6, scale = 0.4 },
      },
      lastFrame = 0,
      textureSlots = {},
      seed = 1,
    },
  },
}
expireState = runHandler(expireState, {
  species = 109,
  callbackFrame = 1,
  sourceFrame = 1,
  dynamicObjectIndex = 0,
  dynamicObjectEnabled = true,
  animationState = 2,
  animationFrame = nonMatchFrame,
  dynamicObjectUpdateEnabled = true,
  modelScaleY = modelScaleY,
  dynamicObjectGrowth = growth,
  dynamicObjectDamping = damping,
})
local expired = expireState.dynamicObjectsBySite[site].particles[1]
check(expired.age == 16, "expiry age=%s expected=16", tostring(expired.age))
check(not (expired.active == true or expired.active == 1), "expiry active=%s expected=false", tostring(expired.active))
check(approx(expired.y, 2 + 0.5 * modelScaleY + 0.2), "expiry still performs final ASM movement y=%s expected=%.9g", tostring(expired.y), 2 + 0.5 * modelScaleY + 0.2)
check(approx(expired.sx, 0.4 + growth), "expiry still performs final ASM growth sx=%s expected=%.9g", tostring(expired.sx), 0.4 + growth)

emit("GEOMETRY_ORACLE_BEGIN")
local cacheRoot = discoverCacheRoot()
check(cacheRoot ~= nil, "Koffing cache root found=%s", tostring(cacheRoot))
local model
if cacheRoot then
  local marker = readFile(cacheRoot .. "/pack.info") or ""
  check(marker:find("format=S2IMP28", 1, true) ~= nil, "Koffing cache format is S2IMP28; stale caches must be re-imported")
  local packBytes = readFile(cacheRoot .. "/normal/109.dsm")
  check(type(packBytes) == "string", "Koffing DSM pack readable")
  if packBytes then
    local parseErr
    model, parseErr = Pack.parse(packBytes)
    check(type(model) == "table", "Koffing DSM pack parses err=%s", tostring(parseErr))
  end
end

if model and model.handlers and type(model.handlers.fragment) == "string" then
  local extension = model.handlers
  local record
  for _, candidateRecord in ipairs(extension.records or {}) do
    if candidateRecord.descriptor == 0x81000070 then record = candidateRecord break end
  end
  check(record ~= nil, "Koffing dynamic-object record exists")
  if record then
    local fragment = extension.fragment
    local argOffset = tonumber(record.argOffset)
    check(argOffset ~= nil, "Koffing callback argument offset exists")
    if argOffset then
      local setupPointer = u32(fragment, argOffset)
      local geometryPointer = u32(fragment, argOffset + 4)
      check(setupPointer == 0x8FF01080, "callback setup DL pointer=%s expected=0x8FF01080", hex(setupPointer))
      check(geometryPointer == 0x8FF010B8, "callback geometry DL pointer=%s expected=0x8FF010B8", hex(geometryPointer))
      local setupOffset = fragmentOffset(extension, setupPointer)
      check(setupOffset ~= nil, "callback setup DL resolves")
      if setupOffset then
        check(u32(fragment, setupOffset + 0x10) == 0xD9FDFFFF and u32(fragment, setupOffset + 0x14) == 0,
          "callback setup clears G_LIGHTING before dynamic billboard draw")
        check(u32(fragment, setupOffset + 0x18) == 0xFC3097FF and u32(fragment, setupOffset + 0x1C) == 0x5FFEFE38,
          "callback setup combine words=FC3097FF/5FFEFE38")
        check(u32(fragment, setupOffset + 0x20) == 0xFB000000 and u32(fragment, setupOffset + 0x24) == 0x80000000,
          "callback setup environment color=0x80000000")
      end
      local geometryOffset = fragmentOffset(extension, geometryPointer)
      check(geometryOffset ~= nil, "callback geometry DL resolves")
      if geometryOffset then
        local vtxWord = u32(fragment, geometryOffset)
        local vtxPointer = u32(fragment, geometryOffset + 4)
        local triWord0 = u32(fragment, geometryOffset + 8)
        local triWord1 = u32(fragment, geometryOffset + 12)
        local op = vtxWord and math.floor(vtxWord / 0x1000000) or -1
        local count = vtxWord and math.floor(vtxWord / 0x1000) % 256 or -1
        local first = vtxWord and (math.floor((vtxWord % 0x1000) / 2) - count) or -1
        check(op == 0x01, "callback geometry first opcode=0x%02X expected=G_VTX", op)
        check(count == 4, "callback geometry vertex count=%d expected=4", count)
        check(first == 0, "callback geometry first vertex=%d expected=0", first)
        check(vtxPointer == 0x8FF01040, "callback Vtx pointer=%s expected=0x8FF01040", hex(vtxPointer))
        local vtxOffset = fragmentOffset(extension, vtxPointer)
        check(vtxOffset ~= nil, "callback Vtx data resolves")
        local sourceVertices = {}
        if vtxOffset then
          for i = 0, 3 do
            local at = vtxOffset + i * 16
            sourceVertices[i + 1] = {
              x = s16(fragment, at), y = s16(fragment, at + 2), z = s16(fragment, at + 4),
              s = s16(fragment, at + 8), t = s16(fragment, at + 10),
            }
            local v = sourceVertices[i + 1]
            emit("SOURCE_VTX index=%d xyz=%d,%d,%d st=%d,%d", i, v.x, v.y, v.z, v.s, v.t)
          end
        end
        local tri1 = decodeTriangleWord(triWord0 or 0)
        local tri2 = decodeTriangleWord(triWord1 or 0)
        local expectedIndices = {tri1[1],tri1[2],tri1[3],tri2[1],tri2[2],tri2[3]}
        emit("SOURCE_TRI indices=%d,%d,%d,%d,%d,%d", (table.unpack or unpack)(expectedIndices))
        local controlled
        check(u32(fragment, geometryOffset + 0x18) == 0xD9FFFFFF
            and u32(fragment, geometryOffset + 0x1C) == 0x00020000,
          "callback geometry restores G_LIGHTING after dynamic billboard draw")
        for _, prim in ipairs(model.prims or {}) do
          if tonumber(prim.callbackOffset) == tonumber(record.commandOffset) then
            controlled = prim
            break
          end
        end
        check(controlled ~= nil, "Koffing dynamic billboard carrier resolves from callback site")
        if controlled then
          local renderState = Renderer.primitiveRenderState(model, controlled,
            { disableCulling = true })
          check(controlled.cull == true,
            "Koffing dynamic billboard carrier preserves ASM back-face culling")
          check(controlled.nverts == 72 and controlled.nidx == 108,
            "extractor merged 18 callback billboard copies into the carrier primitive")
          check(renderState.dynamicObjectCarrier == true,
            "production classifies callback geometry as a dynamic-object carrier")
          check(renderState.drawStatic == false,
            "production excludes callback billboard copies from Koffing static geometry")
          check(renderState.cullEnabled == true,
            "production keeps carrier culling enabled despite scene-wide culling override")
          check(renderState.lightingEnabled == false,
            "production treats carrier 0xFFFFFFFF vertices as unlit white color")
          check(renderState.castsShadow == false,
            "production excludes carrier cards from the model shadow silhouette")
          local emitterRuntime = Renderer.dynamicObjectEmitters(model,
            Build.bindMatrices(model.bones))
          check(#emitterRuntime == 18,
            "production derives 18 emitters from callback carrier bones")
          local orderedBones, distinctOrigins = true, {}
          for i, emitter in ipairs(emitterRuntime) do
            if emitter.index ~= i - 1 or emitter.bone ~= i * 2 + 3 then orderedBones = false end
            local origin = emitter.origin or {}
            distinctOrigins[string.format("%.6f,%.6f,%.6f",
              origin[1] or 0, origin[2] or 0, origin[3] or 0)] = true
          end
          local originCount = 0
          for _ in pairs(distinctOrigins) do originCount = originCount + 1 end
          check(orderedBones, "emitter indices 0..17 follow callback bones 5,7,..,39")
          check(originCount == 18, "all callback emitters have distinct posed origins")
          local rig, rigErr = Renderer.new(model)
          check(rig ~= nil, "production Koffing renderer constructs for emitter audit err=%s",
            tostring(rigErr))
          if rig then
            rig:setHandlerRuntime({
              species = 109, callbackFrame = 32,
              animationState = 0, animationFrame = 32,
              dynamicObjectEnabled = true, dynamicObjectUpdateEnabled = true,
            }, true)
            rig:updatePose(true)
            local integrated = rig.handlerState.dynamicObjectsBySite[record.commandOffset]
            local integratedEmitters, integratedParticles = activeEmitterCount(integrated)
            check(#(integrated and integrated.emitters or {}) == 18
                and integratedEmitters == 6 and integratedParticles == 6,
              "renderer lifecycle wires 18 pools and default frame=32 emits from 6 holes")
            rig:release()
          end
        end
        check(type(Renderer.koffingGasGeometryState) == "function", "renderer exposes production Koffing geometry state")
        check(type(Renderer.koffingGasMaterialState) == "function", "renderer exposes production Koffing material state")
        if type(Renderer.koffingGasMaterialState) == "function" then
          local material0 = Renderer.koffingGasMaterialState(0)
          local material15 = Renderer.koffingGasMaterialState(15)
          check(material0.combine and material0.combine[1] == 0x3097FF and material0.combine[2] == 0x5FFEFE38,
            "production Koffing combine words match callback setup DL")
          check(approx(material0.primitiveColor[1], 10 / 255) and material0.primitiveColor[2] == 0 and material0.primitiveColor[3] == 0 and material0.alphaByte == 200,
            "production Koffing age=0 primitive RGBA matches ASM 0x0A0000C8")
          check(approx(material15.primitiveColor[4], 5 / 255) and material15.alphaByte == 5,
            "production Koffing age=15 primitive alpha matches ASM")
          check(approx(material0.environmentColor[1], 128 / 255) and material0.environmentColor[2] == 0 and material0.environmentColor[3] == 0 and material0.environmentColor[4] == 0,
            "production Koffing environment RGBA matches setup DL 0x80000000")
        end
        if #sourceVertices == 4 and type(Renderer.koffingGasGeometryState) == "function" then
          local particle = { active=true, absolute=true, age=0, x=4, y=6, z=8, sx=1, sy=1, sz=1, scale=1 }
          local textureRow = record.program and record.program.textures and record.program.textures[1]
          local textureIndex = textureRow and ((tonumber(textureRow.slot) or -1) + 1) or nil
          local texture = textureIndex and model.textures and model.textures[textureIndex] or nil
          local tw, th = texture and texture.w or 0, texture and texture.h or 0
          check(tw == 32 and th == 32, "Koffing gas texture dimensions=%dx%d expected=32x32 I4", tw, th)
          local rgba = texture and texture.rgba or nil
          check(type(rgba) == "string" and #rgba == 32 * 32 * 4,
            "Koffing decoded gas texture bytes=%s expected=4096 RGBA8", tostring(type(rgba) == "string" and #rgba or nil))
          if type(rgba) == "string" and #rgba == 32 * 32 * 4 then
            local grayscale, opaque, minI, maxI = true, true, 255, 0
            for pi = 1, #rgba, 4 do
              local r, g, b, a = rgba:byte(pi, pi + 3)
              if r ~= g or r ~= b then grayscale = false end
              if a ~= 255 then opaque = false end
              if r < minI then minI = r end
              if r > maxI then maxI = r end
            end
            check(grayscale, "Koffing decoded I4 frame is grayscale")
            check(opaque, "Koffing decoded I4 carrier texture keeps opaque alpha for shader intensity")
            check(maxI > minI, "Koffing decoded I4 frame has intensity range min=%d max=%d", minI, maxI)
          end
          local handlerTextures = record.program and record.program.textures or {}
          check(#handlerTextures == 8, "Koffing handler texture frames=%d expected=8", #handlerTextures)
          for ti = 1, #handlerTextures do
            local row = handlerTextures[ti]
            check(row.w == 32 and row.h == 32 and row.format == 4 and row.size == 0,
              "Koffing handler frame=%d metadata=%sx%s fmt=%s siz=%s expected=32x32 I4", ti, tostring(row.w), tostring(row.h), tostring(row.format), tostring(row.size))
            if ti > 1 then
              local delta = (tonumber(row.pointer) or 0) - (tonumber(handlerTextures[ti - 1].pointer) or 0)
              check(delta == 0x200, "Koffing handler frame=%d pointer stride=0x%X expected=0x200", ti, delta)
            end
          end
          if #handlerTextures == 8 then
            local firstPointer = tonumber(handlerTextures[1].pointer) or 0
            local lastPointer = tonumber(handlerTextures[8].pointer) or 0
            check(firstPointer == 0x8FF00040 and lastPointer == 0x8FF00E40,
              "Koffing handler texture pointer range=%s..%s expected=0x8FF00040..0x8FF00E40", hex(firstPointer), hex(lastPointer))
            check(lastPointer + frameBytes == vtxPointer,
              "Koffing final I4 frame ends exactly at callback Vtx data: %s + 0x%X = %s", hex(lastPointer), frameBytes, hex(vtxPointer))
          end
          check(type(record.program and record.program.geometry) == "table", "handler program exposes callback geometry")
          local geometry = Renderer.koffingGasGeometryState(particle, {100,200,300}, record.program and record.program.geometry, tw, th)
          check(approx(geometry.center[1],4) and approx(geometry.center[2],6) and approx(geometry.center[3],8),
            "production geometry center=%s,%s,%s expected=4,6,8", tostring(geometry.center[1]), tostring(geometry.center[2]), tostring(geometry.center[3]))
          for i = 1, 4 do
            local source = sourceVertices[i]
            local expectedX = 4 + source.x * renderScale
            local expectedY = 6 + source.y * renderScale
            local expectedZ = 8 + source.z * renderScale
            local expectedU = (source.s / 32) / tw
            local expectedV = (source.t / 32) / th
            local actualVertex = geometry.vertices[i] or {}
            emit("GEOMETRY index=%d actual=%.9g,%.9g,%.9g uv=%.9g,%.9g expected=%.9g,%.9g,%.9g uv=%.9g,%.9g",
              i, tonumber(actualVertex[1]) or 0, tonumber(actualVertex[2]) or 0, tonumber(actualVertex[3]) or 0,
              tonumber(actualVertex[4]) or 0, tonumber(actualVertex[5]) or 0, expectedX, expectedY, expectedZ, expectedU, expectedV)
            check(approx(actualVertex[1], expectedX) and approx(actualVertex[2], expectedY) and approx(actualVertex[3], expectedZ),
              "production vertex=%d position matches ASM scale->translate source Vtx", i)
            check(approx(actualVertex[4], expectedU) and approx(actualVertex[5], expectedV),
              "production vertex=%d UV matches callback Vtx", i)
          end
          local actualIndices = geometry.indices or {}
          local indexMatch = #actualIndices == 6
          for i = 1, 6 do if actualIndices[i] ~= expectedIndices[i] then indexMatch = false end end
          check(indexMatch, "production triangle indices match callback G_TRI2")
          local scaled = Renderer.koffingGasGeometryState(
            {active=true,absolute=true,age=0,x=-3,y=5,z=7,sx=1.25,sy=0.75,sz=2},
            {400,500,600}, record.program and record.program.geometry, tw, th)
          check(approx(scaled.vertices[1][1], -3 + sourceVertices[1].x * renderScale * 1.25),
            "production asymmetric X scale follows ASM particle.sx")
          check(approx(scaled.vertices[1][2], 5 + sourceVertices[1].y * renderScale * 0.75),
            "production asymmetric Y scale follows ASM particle.sy")
          check(approx(scaled.vertices[1][3], 7 + sourceVertices[1].z * renderScale * 2),
            "production asymmetric Z scale follows ASM particle.sz")
          check(approx(scaled.vertices[2][4], (sourceVertices[2].s / 32) / tw) and
            approx(scaled.vertices[2][5], (sourceVertices[2].t / 32) / th),
            "production asymmetric geometry keeps callback UVs")
        end
      end
    end
  end
else
  check(false, "Koffing handler fragment is present in DSM pack")
end
emit("GEOMETRY_ORACLE_END")

emit("RESULT checks=%d failures=%d", checks, failures)
report:close()
os.exit(failures == 0 and 0 or 1)
