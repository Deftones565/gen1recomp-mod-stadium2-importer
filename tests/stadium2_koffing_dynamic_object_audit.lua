package.path = "./?.lua;./?/init.lua;" .. package.path

local Pack = require("mods.STADIUM2_IMPORTER.lib.pack")
local Handlers = require("mods.STADIUM2_IMPORTER.lib.model_handlers")
local Fragment26 = require("mods.STADIUM2_IMPORTER.lib.fragment26")
local Discovery = require("mods.STADIUM2_IMPORTER.lib.discovery")
local Rom = require("mods.STADIUM2_IMPORTER.lib.rom")
local Materials = require("mods.STADIUM2_IMPORTER.lib.materials")

local SPECIES = 109
local HANDLER_DESCRIPTOR = 0x81000070
local FUNCTION_ROOT = 0x81005524
local SOURCE_BASE = 0x8FF00000
local REPORT_PREFIX = "[stadium2-koffing-audit] "

local failures = 0
local warnings = 0
local reportHandle

local function fileExists(path)
  local f = io.open(path, "rb")
  if not f then return false end
  f:close()
  return true
end

local function readFile(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local data = f:read("*a")
  f:close()
  return data
end

local function writeFile(path, data)
  local f, err = io.open(path, "wb")
  if not f then return nil, err end
  f:write(data)
  f:close()
  return true
end

local function shellQuote(value)
  return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function mkdir(path)
  local sep = package.config and package.config:sub(1, 1) or "/"
  local ok
  if sep == "\\" then
    ok = os.execute('if not exist "' .. tostring(path):gsub('"', '""') .. '" mkdir "' .. tostring(path):gsub('"', '""') .. '"')
  else
    ok = os.execute("mkdir -p " .. shellQuote(path))
  end
  return ok
end

local function dirname(path)
  return path and path:match("^(.*)[/\\]normal[/\\]109%.dsm$") or nil
end

local function discoverCacheRoot()
  local supplied = arg and arg[1] or nil
  if supplied and fileExists(supplied .. "/normal/109.dsm") then return supplied end
  local env = os.getenv("STADIUM2_CACHE_ROOT")
  if env and fileExists(env .. "/normal/109.dsm") then return env end
  if fileExists("stadium2_importer/normal/109.dsm") then return "stadium2_importer" end
  local home = os.getenv("HOME")
  local xdg = os.getenv("XDG_DATA_HOME")
  local bases = {}
  if xdg and xdg ~= "" then bases[#bases + 1] = xdg .. "/love" end
  if home and home ~= "" then
    bases[#bases + 1] = home .. "/.local/share/love"
    bases[#bases + 1] = home .. "/.local/share"
  end
  if io.popen then
    for _, base in ipairs(bases) do
      local pipe = io.popen("find " .. shellQuote(base) .. " -type f -path '*/stadium2_importer/normal/109.dsm' -print -quit 2>/dev/null", "r")
      if pipe then
        local found = pipe:read("*l")
        pipe:close()
        local root = dirname(found)
        if root then return root end
      end
    end
  end
  return nil
end

local function emit(fmt, ...)
  local line = fmt
  if select("#", ...) > 0 then line = fmt:format(...) end
  io.stdout:write(REPORT_PREFIX .. line .. "\n")
  if reportHandle then reportHandle:write(line .. "\n") end
end

local function fail(fmt, ...)
  failures = failures + 1
  emit("FAIL " .. fmt, ...)
end

local function warn(fmt, ...)
  warnings = warnings + 1
  emit("WARN " .. fmt, ...)
end

local function hex(value, width)
  value = tonumber(value)
  if value == nil then return "-" end
  if value < 0 then value = value + 0x100000000 end
  return ("0x%0" .. tostring(width or 8) .. "X"):format(value % 0x100000000)
end

local function u16be(data, offset)
  local a, b = string.byte(data, offset + 1, offset + 2)
  if not b then return nil end
  return a * 256 + b
end

local function i16be(data, offset)
  local v = u16be(data, offset)
  if v and v >= 0x8000 then v = v - 0x10000 end
  return v
end

local function u32be(data, offset)
  local a, b, c, d = string.byte(data, offset + 1, offset + 4)
  if not d then return nil end
  return ((a * 256 + b) * 256 + c) * 256 + d
end

local function signed32(v)
  if v and v >= 0x80000000 then return v - 0x100000000 end
  return v
end

local function float32(v)
  if not v then return nil end
  local sign = v >= 0x80000000 and -1 or 1
  if sign < 0 then v = v - 0x80000000 end
  local exponent = math.floor(v / 0x800000) % 0x100
  local mantissa = v % 0x800000
  if exponent == 0xFF then
    if mantissa == 0 then return sign * math.huge end
    return 0 / 0
  end
  if exponent == 0 then
    return sign * (mantissa / 0x800000) * 2 ^ -126
  end
  return sign * (1 + mantissa / 0x800000) * 2 ^ (exponent - 127)
end

local function floatText(v)
  local f = float32(v)
  if f ~= f then return "nan" end
  if f == math.huge then return "+inf" end
  if f == -math.huge then return "-inf" end
  if f == 0 then return "0" end
  if math.abs(f) < 1e-12 or math.abs(f) > 1e12 then return ("%.6e"):format(f) end
  return ("%.6f"):format(f)
end

local function classifyWord(extension, value)
  if value == nil then return "invalid" end
  local base = tonumber(extension.sourceBase) or SOURCE_BASE
  local fragment = extension.fragment or ""
  local rel = value - base
  if rel >= 0 and rel < #fragment then return ("model-fragment+0x%X"):format(rel) end
  if Fragment26.isDescriptor(value) then
    return "fragment26-descriptor"
  end
  local fn = Fragment26.functionInfo(value)
  if fn then
    if fn.exact then return "fragment26:" .. fn.name end
    return ("fragment26:%s+0x%X"):format(fn.name, fn.delta)
  end
  if value >= 0x80000000 and value <= 0xBFFFFFFF then
    local runtime = Fragment26.runtimeName(value)
    return runtime and ("runtime:" .. runtime) or "runtime-address"
  end
  return "scalar"
end

local function hexdump(data, base, width)
  width = width or 16
  local lines = {}
  for at = 0, #data - 1, width do
    local hexes, ascii = {}, {}
    for i = 0, width - 1 do
      local b = string.byte(data, at + i + 1)
      if b then
        hexes[#hexes + 1] = ("%02X"):format(b)
        ascii[#ascii + 1] = b >= 32 and b <= 126 and string.char(b) or "."
      else
        hexes[#hexes + 1] = "  "
        ascii[#ascii + 1] = " "
      end
    end
    lines[#lines + 1] = ("%08X  %s  |%s|"):format((base or 0) + at, table.concat(hexes, " "), table.concat(ascii))
  end
  return lines
end

local function p16le(v)
  v = math.floor(tonumber(v) or 0) % 0x10000
  return string.char(v % 256, math.floor(v / 256) % 256)
end

local function writeTga(path, texture)
  if type(texture) ~= "table" or type(texture.rgba) ~= "string" then return nil, "texture has no RGBA data" end
  local w, h = tonumber(texture.w), tonumber(texture.h)
  if not w or not h or #texture.rgba < w * h * 4 then return nil, "invalid texture dimensions" end
  local header = string.char(0, 0, 2) .. string.rep("\0", 9) .. p16le(w) .. p16le(h) .. string.char(32, 0x28)
  local chunks = { header }
  local row = {}
  for i = 1, w * h do
    local at = (i - 1) * 4 + 1
    local r, g, b, a = string.byte(texture.rgba, at, at + 3)
    row[#row + 1] = string.char(b, g, r, a)
    if #row >= 1024 then
      chunks[#chunks + 1] = table.concat(row)
      row = {}
    end
  end
  if #row > 0 then chunks[#chunks + 1] = table.concat(row) end
  return writeFile(path, table.concat(chunks))
end

local function textureStats(texture)
  local rgba = texture and texture.rgba
  local w, h = tonumber(texture and texture.w), tonumber(texture and texture.h)
  if type(rgba) ~= "string" or not w or not h then return nil end
  local nonzero, opaque, translucent = 0, 0, 0
  local sumA, sumR, sumG, sumB = 0, 0, 0, 0
  local minX, minY, maxX, maxY = w, h, -1, -1
  local unique = {}
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      local at = (y * w + x) * 4 + 1
      local r, g, b, a = string.byte(rgba, at, at + 3)
      unique[string.char(r, g, b, a)] = true
      sumA = sumA + a
      if a > 0 then
        nonzero = nonzero + 1
        if a == 255 then opaque = opaque + 1 else translucent = translucent + 1 end
        sumR, sumG, sumB = sumR + r, sumG + g, sumB + b
        minX, minY = math.min(minX, x), math.min(minY, y)
        maxX, maxY = math.max(maxX, x), math.max(maxY, y)
      end
    end
  end
  local uniqueCount = 0
  for _ in pairs(unique) do uniqueCount = uniqueCount + 1 end
  local count = w * h
  return {
    pixels = count,
    nonzero = nonzero,
    opaque = opaque,
    translucent = translucent,
    meanAlpha = count > 0 and sumA / count or 0,
    meanR = nonzero > 0 and sumR / nonzero or 0,
    meanG = nonzero > 0 and sumG / nonzero or 0,
    meanB = nonzero > 0 and sumB / nonzero or 0,
    bbox = nonzero > 0 and { minX, minY, maxX, maxY } or nil,
    unique = uniqueCount,
  }
end

local function textureStatText(texture)
  local s = textureStats(texture)
  if not s then return "invalid" end
  local bbox = s.bbox and ("%d,%d..%d,%d"):format(s.bbox[1], s.bbox[2], s.bbox[3], s.bbox[4]) or "empty"
  return ("pixels=%d alphaNonzero=%d opaque=%d translucent=%d meanAlpha=%.2f meanRGB=%.1f,%.1f,%.1f bbox=%s uniqueRGBA=%d")
    :format(s.pixels, s.nonzero, s.opaque, s.translucent, s.meanAlpha, s.meanR, s.meanG, s.meanB, bbox, s.unique)
end

local REGS = {
  [0] = "zero", "at", "v0", "v1", "a0", "a1", "a2", "a3",
  "t0", "t1", "t2", "t3", "t4", "t5", "t6", "t7",
  "s0", "s1", "s2", "s3", "s4", "s5", "s6", "s7",
  "t8", "t9", "k0", "k1", "gp", "sp", "fp", "ra",
}

local function reg(v) return "$" .. (REGS[v] or tostring(v)) end
local function freg(v) return "$f" .. tostring(v) end
local function field(word, shift, width) return math.floor(word / 2 ^ shift) % 2 ^ width end
local function simm16(word)
  local v = word % 0x10000
  if v >= 0x8000 then v = v - 0x10000 end
  return v
end

local function branchTarget(pc, word)
  return (pc + 4 + simm16(word) * 4) % 0x100000000
end

local function jumpTarget(pc, word)
  local upper = (pc + 4) - ((pc + 4) % 0x10000000)
  return (upper + (word % 0x4000000) * 4) % 0x100000000
end

local function symbolFor(address)
  local runtime = Fragment26.runtimeName(address)
  if runtime then return runtime end
  local fn = Fragment26.functionInfo(address)
  if fn then
    if fn.exact then return fn.name end
    return fn.name .. ("+0x%X"):format(fn.delta)
  end
  return nil
end

local function disassemble(word, pc)
  local op = field(word, 26, 6)
  local rs, rt, rd = field(word, 21, 5), field(word, 16, 5), field(word, 11, 5)
  local sa, fn = field(word, 6, 5), field(word, 0, 6)
  local imm, uimm = simm16(word), word % 0x10000
  local info = {}
  local text
  if word == 0 then
    text = "nop"
  elseif op == 0 then
    local map = {
      [0x00] = "sll", [0x02] = "srl", [0x03] = "sra", [0x04] = "sllv", [0x06] = "srlv", [0x07] = "srav",
      [0x08] = "jr", [0x09] = "jalr", [0x0C] = "syscall", [0x0D] = "break", [0x10] = "mfhi", [0x11] = "mthi",
      [0x12] = "mflo", [0x13] = "mtlo", [0x18] = "mult", [0x19] = "multu", [0x1A] = "div", [0x1B] = "divu",
      [0x20] = "add", [0x21] = "addu", [0x22] = "sub", [0x23] = "subu", [0x24] = "and", [0x25] = "or",
      [0x26] = "xor", [0x27] = "nor", [0x2A] = "slt", [0x2B] = "sltu", [0x2C] = "dadd", [0x2D] = "daddu",
      [0x2E] = "dsub", [0x2F] = "dsubu",
    }
    local name = map[fn]
    if fn == 0x00 or fn == 0x02 or fn == 0x03 then
      text = ("%s %s,%s,%d"):format(name or "special", reg(rd), reg(rt), sa)
    elseif fn == 0x04 or fn == 0x06 or fn == 0x07 then
      text = ("%s %s,%s,%s"):format(name or "special", reg(rd), reg(rt), reg(rs))
    elseif fn == 0x08 then
      text = "jr " .. reg(rs)
      info.indirect = true
    elseif fn == 0x09 then
      text = ("jalr %s,%s"):format(reg(rd), reg(rs))
      info.call = true
      info.indirect = true
    elseif fn == 0x0C or fn == 0x0D then
      text = name
    elseif fn == 0x10 or fn == 0x12 then
      text = ("%s %s"):format(name, reg(rd))
    elseif fn == 0x11 or fn == 0x13 then
      text = ("%s %s"):format(name, reg(rs))
    elseif fn >= 0x18 and fn <= 0x1B then
      text = ("%s %s,%s"):format(name, reg(rs), reg(rt))
    elseif name then
      text = ("%s %s,%s,%s"):format(name, reg(rd), reg(rs), reg(rt))
    else
      text = ("special_%02X %s,%s,%s"):format(fn, reg(rd), reg(rs), reg(rt))
    end
  elseif op == 1 then
    local names = { [0] = "bltz", [1] = "bgez", [16] = "bltzal", [17] = "bgezal" }
    local name = names[rt] or ("regimm_%02X"):format(rt)
    local target = branchTarget(pc, word)
    text = ("%s %s,%s"):format(name, reg(rs), hex(target))
    info.branchTarget = target
  elseif op == 2 or op == 3 then
    local target = jumpTarget(pc, word)
    local name = op == 2 and "j" or "jal"
    local sym = symbolFor(target)
    text = ("%s %s%s"):format(name, hex(target), sym and (" <" .. sym .. ">") or "")
    info.target = target
    info.call = op == 3
  elseif op >= 4 and op <= 7 then
    local names = { [4] = "beq", [5] = "bne", [6] = "blez", [7] = "bgtz" }
    local target = branchTarget(pc, word)
    if op == 4 or op == 5 then
      text = ("%s %s,%s,%s"):format(names[op], reg(rs), reg(rt), hex(target))
    else
      text = ("%s %s,%s"):format(names[op], reg(rs), hex(target))
    end
    info.branchTarget = target
  elseif op == 8 or op == 9 or op == 10 or op == 11 or op == 24 or op == 25 then
    local names = { [8] = "addi", [9] = "addiu", [10] = "slti", [11] = "sltiu", [24] = "daddi", [25] = "daddiu" }
    text = ("%s %s,%s,%d"):format(names[op], reg(rt), reg(rs), imm)
  elseif op == 12 or op == 13 or op == 14 then
    local names = { [12] = "andi", [13] = "ori", [14] = "xori" }
    text = ("%s %s,%s,0x%X"):format(names[op], reg(rt), reg(rs), uimm)
  elseif op == 15 then
    text = ("lui %s,0x%X"):format(reg(rt), uimm)
  elseif op == 16 then
    local coprs = rs
    if coprs == 0 then text = ("mfc0 %s,$%d"):format(reg(rt), rd)
    elseif coprs == 4 then text = ("mtc0 %s,$%d"):format(reg(rt), rd)
    elseif coprs == 16 and fn == 0x18 then text = "eret"
    else text = ("cop0_%02X %s,%s"):format(coprs, reg(rt), reg(rd)) end
  elseif op == 17 then
    local fmt = rs
    local fs, ft, fd = field(word, 11, 5), field(word, 16, 5), field(word, 6, 5)
    if fmt == 0 then text = ("mfc1 %s,%s"):format(reg(rt), freg(fs))
    elseif fmt == 2 then text = ("cfc1 %s,%s"):format(reg(rt), freg(fs))
    elseif fmt == 4 then text = ("mtc1 %s,%s"):format(reg(rt), freg(fs))
    elseif fmt == 6 then text = ("ctc1 %s,%s"):format(reg(rt), freg(fs))
    elseif fmt == 8 then
      local target = branchTarget(pc, word)
      local tf = field(word, 16, 1)
      text = ((tf == 0 and "bc1f " or "bc1t ") .. hex(target))
      info.branchTarget = target
    else
      local suffix = fmt == 16 and ".s" or fmt == 17 and ".d" or fmt == 20 and ".w" or fmt == 21 and ".l" or (".fmt%d"):format(fmt)
      local fmap = { [0] = "add", [1] = "sub", [2] = "mul", [3] = "div", [4] = "sqrt", [5] = "abs", [6] = "mov", [7] = "neg",
        [32] = "cvt.s", [33] = "cvt.d", [36] = "cvt.w", [37] = "cvt.l", [50] = "c.eq", [60] = "c.lt", [62] = "c.le" }
      local name = fmap[fn] or ("cop1_%02X"):format(fn)
      if fn <= 3 then text = ("%s%s %s,%s,%s"):format(name, suffix, freg(fd), freg(fs), freg(ft))
      elseif fn <= 7 then text = ("%s%s %s,%s"):format(name, suffix, freg(fd), freg(fs))
      elseif fn >= 48 then text = ("%s%s %s,%s"):format(name, suffix, freg(fs), freg(ft))
      else text = ("%s%s %s,%s"):format(name, suffix, freg(fd), freg(fs)) end
    end
  else
    local memNames = {
      [0x1A] = "ldl", [0x1B] = "ldr", [0x20] = "lb", [0x21] = "lh", [0x22] = "lwl", [0x23] = "lw",
      [0x24] = "lbu", [0x25] = "lhu", [0x26] = "lwr", [0x27] = "lwu", [0x28] = "sb", [0x29] = "sh",
      [0x2A] = "swl", [0x2B] = "sw", [0x2C] = "sdl", [0x2D] = "sdr", [0x2E] = "swr", [0x30] = "ll",
      [0x31] = "lwc1", [0x32] = "lwc2", [0x35] = "ldc1", [0x37] = "ld", [0x38] = "sc", [0x39] = "swc1",
      [0x3A] = "swc2", [0x3D] = "sdc1", [0x3F] = "sd",
    }
    local name = memNames[op]
    if name then
      local targetReg = (op == 0x31 or op == 0x35 or op == 0x39 or op == 0x3D) and freg(rt) or reg(rt)
      text = ("%s %s,%d(%s)"):format(name, targetReg, imm, reg(rs))
      info.mem = { op = name, base = rs, target = rt, offset = imm }
    else
      text = ("op_%02X %s,%s,0x%04X"):format(op, reg(rt), reg(rs), uimm)
    end
  end
  return text, info
end

local function sortedNumericKeys(map)
  local keys = {}
  for key in pairs(map or {}) do keys[#keys + 1] = key end
  table.sort(keys)
  return keys
end

local function disassembleFunction(code, info)
  local decoded = {}
  local labels = {}
  for offset = 0, #code - 4, 4 do
    local pc = info.start + offset
    local word = u32be(code, offset)
    local text, meta = disassemble(word, pc)
    decoded[#decoded + 1] = { offset = offset, pc = pc, word = word, text = text, meta = meta }
    if meta.branchTarget and meta.branchTarget >= info.start and meta.branchTarget < info.finish then labels[meta.branchTarget] = true end
  end
  return decoded, labels
end

local function materialText(material)
  if type(material) ~= "table" then return "-" end
  local image = material.textureImage or {}
  local tile = material.activeTile or {}
  local s = tile.s or {}
  local t = tile.t or {}
  local scale = material.textureScale or {}
  return ("complete=%s enabled=%s imageFmt=%s imageSiz=%s imageWidth=%s imagePtr=%s tileFmt=%s tileSiz=%s pal=%s s=%s/m%s/sh%s t=%s/m%s/sh%s scale=%.5f,%.5f")
    :format(tostring(material.complete), tostring(material.textureEnabled), tostring(image.format), tostring(image.size), tostring(image.width), hex(image.pointer),
      tostring(tile.format), tostring(tile.size), tostring(tile.palette), tostring(s.wrap), tostring(s.mask), tostring(s.shift),
      tostring(t.wrap), tostring(t.mask), tostring(t.shift), tonumber(scale[1]) or 0, tonumber(scale[2]) or 0)
end

local GFX_NAMES = {
  [0x01] = "G_VTX", [0x04] = "G_BRANCH_Z", [0x05] = "G_TRI1", [0x06] = "G_TRI2", [0xD7] = "G_TEXTURE",
  [0xD8] = "G_POPMTX", [0xD9] = "G_GEOMETRYMODE", [0xDA] = "G_MTX", [0xDB] = "G_MOVEWORD", [0xDC] = "G_MOVEMEM",
  [0xDE] = "G_DL", [0xDF] = "G_ENDDL", [0xE2] = "G_SETOTHERMODE_L", [0xE3] = "G_SETOTHERMODE_H",
  [0xE7] = "G_RDPPIPESYNC", [0xE8] = "G_RDPTILESYNC", [0xE9] = "G_RDPFULLSYNC", [0xEA] = "G_SETKEYGB",
  [0xEB] = "G_SETKEYR", [0xEC] = "G_SETCONVERT", [0xED] = "G_SETSCISSOR", [0xEE] = "G_SETPRIMDEPTH",
  [0xEF] = "G_RDPSETOTHERMODE", [0xF0] = "G_LOADTLUT", [0xF2] = "G_SETTILESIZE", [0xF3] = "G_LOADBLOCK",
  [0xF4] = "G_LOADTILE", [0xF5] = "G_SETTILE", [0xF6] = "G_FILLRECT", [0xF7] = "G_SETFILLCOLOR",
  [0xF8] = "G_SETFOGCOLOR", [0xF9] = "G_SETBLENDCOLOR", [0xFA] = "G_SETPRIMCOLOR", [0xFB] = "G_SETENVCOLOR",
  [0xFC] = "G_SETCOMBINE", [0xFD] = "G_SETTIMG", [0xFE] = "G_SETZIMG", [0xFF] = "G_SETCIMG",
}

local function looksLikeGfx(data, offset)
  local op = string.byte(data, offset + 1)
  return op and GFX_NAMES[op] ~= nil
end

local function dumpGfx(data, offset, limit)
  limit = limit or 64
  for i = 0, limit - 1 do
    local at = offset + i * 8
    if at + 8 > #data then break end
    local w0, w1 = u32be(data, at), u32be(data, at + 4)
    local op = math.floor(w0 / 0x1000000) % 0x100
    emit("GFX at=0x%X index=%d op=0x%02X name=%s w0=%s w1=%s", at, i, op, GFX_NAMES[op] or "UNKNOWN", hex(w0), hex(w1))
    if op == 0xDF then break end
  end
end

local function scanPointerWords(extension, offset, length)
  local fragment = extension.fragment or ""
  local base = tonumber(extension.sourceBase) or SOURCE_BASE
  local result = {}
  local finish = math.min(#fragment, offset + length)
  for at = offset, finish - 4, 4 do
    local value = u32be(fragment, at)
    local rel = value and value - base or -1
    if rel >= 0 and rel < #fragment then
      result[#result + 1] = { source = at, pointer = value, target = rel }
    end
  end
  return result
end

local function xrefsTo(fragment, pointer)
  local result = {}
  for at = 0, #fragment - 4, 4 do
    if u32be(fragment, at) == pointer then result[#result + 1] = at end
  end
  return result
end

local function dumpWordTable(extension, offset, length, label)
  local fragment = extension.fragment or ""
  local finish = math.min(#fragment, offset + length)
  emit("WORD_TABLE_BEGIN label=%s offset=0x%X bytes=0x%X", label, offset, finish - offset)
  for at = offset, finish - 4, 4 do
    local value = u32be(fragment, at)
    local hi, lo = u16be(fragment, at), u16be(fragment, at + 2)
    emit("WORD rel=+0x%03X absolute=0x%X raw=%s signed=%d u16=%04X,%04X i16=%d,%d float=%s class=%s",
      at - offset, at, hex(value), signed32(value), hi or 0, lo or 0, i16be(fragment, at) or 0, i16be(fragment, at + 2) or 0,
      floatText(value), classifyWord(extension, value))
  end
  emit("WORD_TABLE_END label=%s", label)
end

local function boneText(bone, index)
  if type(bone) ~= "table" then return "-" end
  local t, r, s = bone.t or {}, bone.r or {}, bone.s or {}
  return ("index=%d parent=%s t=%s,%s,%s r=%s,%s,%s s=%.6f,%.6f,%.6f")
    :format(index, tostring(bone.parent), tostring(t[1]), tostring(t[2]), tostring(t[3]), tostring(r[1]), tostring(r[2]), tostring(r[3]),
      tonumber(s[1]) or 0, tonumber(s[2]) or 0, tonumber(s[3]) or 0)
end

local function dumpControlledPrimitive(outputDir, model, site)
  for i, prim in ipairs(model.prims or {}) do
    if tonumber(prim.callbackOffset) == site then
      emit("CONTROLLED_PRIMITIVE index=%d baseTexture=%s material=%s vertices=%d indices=%d cull=%s additive=%s",
        i, tostring(prim.tex), hex(prim.materialOffset), tonumber(prim.nverts) or 0, tonumber(prim.nidx) or 0, tostring(prim.cull), tostring(prim.additive))
      local rows = { "vertex\tx\ty\tz\tu\tv\tnx\tny\tnz\tbone" }
      for v = 1, tonumber(prim.nverts) or 0 do
        rows[#rows + 1] = ("%d\t%s\t%s\t%s\t%.9f\t%.9f\t%.9f\t%.9f\t%.9f\t%s"):format(v,
          tostring(prim.pos[v * 3 - 2]), tostring(prim.pos[v * 3 - 1]), tostring(prim.pos[v * 3]),
          tonumber(prim.uv[v * 2 - 1]) or 0, tonumber(prim.uv[v * 2]) or 0,
          tonumber(prim.nrm[v * 3 - 2]) or 0, tonumber(prim.nrm[v * 3 - 1]) or 0, tonumber(prim.nrm[v * 3]) or 0,
          tostring(prim.skin[v]))
      end
      writeFile(outputDir .. ("/controlled_primitive_%02d_vertices.tsv"):format(i), table.concat(rows, "\n") .. "\n")
      local indices = {}
      for k = 1, #(prim.idx or {}) do indices[#indices + 1] = tostring(prim.idx[k]) end
      writeFile(outputDir .. ("/controlled_primitive_%02d_indices.txt"):format(i), table.concat(indices, " ") .. "\n")
    end
  end
end

local function readVramWord(rom, address)
  local offset = Fragment26.romOffset(address)
  if not offset or offset + 4 > #rom then return nil end
  return u32be(rom, offset)
end

local function dumpKoffingJumpTables(rom, outputDir)
  local tables = {
    { name = "spawn", base = 0x810062F4, owner = 0x810045C4 },
    { name = "render", base = 0x81006410, owner = 0x81004818 },
    { name = "update", base = 0x81006528, owner = 0x81004818 },
  }
  local rows = { "species\tindex\ttable\tentryAddress\ttarget\tclassification" }
  for species = 107, 111 do
    local index = species - 77
    for _, tableInfo in ipairs(tables) do
      local entryAddress = tableInfo.base + index * 4
      local target = readVramWord(rom, entryAddress)
      local class = target and Fragment26.describeWord(target) or "invalid"
      emit("JUMP_TABLE species=%d index=%d table=%s entry=%s target=%s class=%s",
        species, index, tableInfo.name, hex(entryAddress), hex(target), tostring(class))
      rows[#rows + 1] = table.concat({ tostring(species), tostring(index), tableInfo.name, hex(entryAddress), hex(target), tostring(class) }, "\t")
      if species == SPECIES then
        if not target then
          fail("could not read Koffing %s jump-table entry at %s", tableInfo.name, hex(entryAddress))
        elseif target < tableInfo.owner or target >= (Fragment26.functionInfo(tableInfo.owner) or {}).finish then
          warn("Koffing %s target %s is outside expected owner function", tableInfo.name, hex(target))
        else
          emit("KOFFING_BRANCH table=%s entry=%s target=%s owner=%s", tableInfo.name, hex(entryAddress), hex(target), hex(tableInfo.owner))
          local ownerCode, ownerInfo = Fragment26.functionBytes(rom, tableInfo.owner)
          if ownerCode and ownerInfo then
            local start = math.max(ownerInfo.start, target - 0x10)
            local finish = math.min(ownerInfo.finish, target + 0x70)
            emit("KOFFING_BLOCK_BEGIN table=%s target=%s range=%s..%s", tableInfo.name, hex(target), hex(start), hex(finish))
            for pc = start, finish - 4, 4 do
              local word = u32be(ownerCode, pc - ownerInfo.start)
              local text = disassemble(word, pc)
              emit("KOFFING_ASM table=%s pc=%s word=%s text=%s", tableInfo.name, hex(pc), hex(word), tostring(text))
            end
            emit("KOFFING_BLOCK_END table=%s target=%s", tableInfo.name, hex(target))
          end
        end
      end
    end
  end
  writeFile(outputDir .. "/koffing_jump_tables.tsv", table.concat(rows, "\n") .. "\n")
end

local function discoverRom()
  local supplied = os.getenv("STADIUM2_ROM")
  if supplied and supplied ~= "" and fileExists(supplied) then return { kind = "host", path = supplied } end
  supplied = arg and (arg[1] or arg[2]) or nil
  if supplied and fileExists(supplied) then return { kind = "host", path = supplied } end
  return Discovery.find()
end

local cacheRoot = discoverCacheRoot()
if not cacheRoot then
  io.stderr:write(REPORT_PREFIX .. "could not locate Stadium 2 cache\n")
  os.exit(2)
end

local outputDir = os.getenv("STADIUM2_AUDIT_DIR") or "stadium2_koffing_dynamic_object_audit_artifacts"
local reportPath = (arg and arg[3]) or os.getenv("STADIUM2_AUDIT_TXT") or "stadium2_koffing_dynamic_object_audit.txt"
mkdir(outputDir)
mkdir(outputDir .. "/textures")
mkdir(outputDir .. "/functions")
mkdir(outputDir .. "/assets")
reportHandle = assert(io.open(reportPath, "wb"))

emit("BEGIN species=%d descriptor=%s target=%s", SPECIES, hex(HANDLER_DESCRIPTOR), hex(FUNCTION_ROOT))
emit("cache=%s", cacheRoot)
emit("report=%s", reportPath)
emit("artifacts=%s", outputDir)

local packPath = ("%s/normal/%03d.dsm"):format(cacheRoot, SPECIES)
local packBytes = readFile(packPath)
if not packBytes then
  fail("could not read pack %s", packPath)
  reportHandle:close()
  os.exit(1)
end
local model, packErr = Pack.parse(packBytes)
if not model then
  fail("pack parse failed: %s", tostring(packErr))
  reportHandle:close()
  os.exit(1)
end
local extension = model.handlers
if type(extension) ~= "table" or type(extension.fragment) ~= "string" then
  fail("pack has no retained handler fragment")
  reportHandle:close()
  os.exit(1)
end

emit("PACK species=%s bones=%d prims=%d textures=%d handlerVersion=%s sourceBase=%s fragmentBytes=%d",
  tostring(model.species), #(model.bones or {}), #(model.prims or {}), #(model.textures or {}), tostring(extension.version), hex(extension.sourceBase), #extension.fragment)
writeFile(outputDir .. "/koffing_model_fragment.bin", extension.fragment)

local record
for _, candidate in ipairs(extension.records or {}) do
  if candidate.descriptor == HANDLER_DESCRIPTOR then
    if record then warn("multiple dynamic-object records found; using site %s", hex(record.commandOffset)) end
    if not record then record = candidate end
  end
end
if not record then
  fail("descriptor %s not present in Koffing pack", hex(HANDLER_DESCRIPTOR))
  reportHandle:close()
  os.exit(1)
end

local site = tonumber(record.commandOffset)
local argOffset = tonumber(record.argOffset)
local argAddress = tonumber(record.argAddress)
local program = record.program or {}
emit("HANDLER site=%s descriptor=%s target=%s family=%s phase=%s bone=%s boneId=%s argOffset=%s argAddress=%s argumentBytes=%d assets=%d textures=%d complete=%s",
  hex(site), hex(record.descriptor), hex(record.target), tostring(record.family), table.concat(record.phases or {}, ","), tostring(record.bone), tostring(record.boneId),
  hex(argOffset), hex(argAddress), #(record.argument or ""), #(program.assets or {}), #(program.textures or {}), tostring(program.complete))

if argOffset == nil then
  fail("handler has no callback argument")
  reportHandle:close()
  os.exit(1)
end

local argumentDumpLength = math.min(0x400, #extension.fragment - argOffset)
local argumentDump = extension.fragment:sub(argOffset + 1, argOffset + argumentDumpLength)
writeFile(outputDir .. "/callback_argument_0x400.bin", argumentDump)
emit("ARG_HEXDUMP_BEGIN")
for _, line in ipairs(hexdump(argumentDump, argOffset)) do emit("%s", line) end
emit("ARG_HEXDUMP_END")
dumpWordTable(extension, argOffset, math.min(0x100, argumentDumpLength), "callback-argument-first-0x100")

local argPointers = scanPointerWords(extension, argOffset, math.min(0x100, argumentDumpLength))
for i, pointer in ipairs(argPointers) do
  emit("ARG_POINTER index=%d sourceRel=+0x%X sourceOffset=0x%X pointer=%s targetOffset=0x%X", i, pointer.source - argOffset, pointer.source, hex(pointer.pointer), pointer.target)
end

if record.bone and record.bone >= 0 then
  local index = record.bone + 1
  local seen = {}
  while index and index >= 1 and not seen[index] do
    seen[index] = true
    local bone = model.bones and model.bones[index]
    if not bone then break end
    emit("HANDLER_BONE %s", boneText(bone, index))
    local parent = tonumber(bone.parent)
    index = parent and parent >= 0 and parent + 1 or nil
  end
end

dumpControlledPrimitive(outputDir, model, site)

for i, texture in ipairs(model.textures or {}) do
  local tag = ""
  for j, ht in ipairs(program.textures or {}) do
    if (tonumber(ht.slot) or -1) + 1 == i then tag = (" handler=%d"):format(j) end
  end
  emit("TEXTURE index=%d size=%dx%d%s %s", i, tonumber(texture.w) or 0, tonumber(texture.h) or 0, tag, textureStatText(texture))
  local ok, err = writeTga(outputDir .. ("/textures/texture_%03d_%dx%d.tga"):format(i, tonumber(texture.w) or 0, tonumber(texture.h) or 0), texture)
  if not ok then warn("could not write texture %d: %s", i, tostring(err)) end
end

for i, ht in ipairs(program.textures or {}) do
  local slot = (tonumber(ht.slot) or -1) + 1
  local tex = model.textures and model.textures[slot]
  local sourceOffset = tonumber(ht.pointer) and tonumber(ht.pointer) - (tonumber(extension.sourceBase) or SOURCE_BASE) or nil
  local bpp = ht.size == 3 and 4 or ht.size == 2 and 2 or ht.size == 1 and 1 or 0.5
  local rawLength = math.ceil((tonumber(ht.w) or 0) * (tonumber(ht.h) or 0) * bpp)
  emit("HANDLER_TEXTURE index=%d slot=%d pointer=%s sourceOffset=%s size=%dx%d fmt=%s siz=%s rawBytes=%d decoded={%s}",
    i, slot, hex(ht.pointer), sourceOffset and ("0x%X"):format(sourceOffset) or "-", tonumber(ht.w) or 0, tonumber(ht.h) or 0,
    tostring(ht.format), tostring(ht.size), rawLength, tex and textureStatText(tex) or "missing")
  if sourceOffset and sourceOffset >= 0 and sourceOffset + rawLength <= #extension.fragment then
    local raw = extension.fragment:sub(sourceOffset + 1, sourceOffset + rawLength)
    writeFile(outputDir .. ("/textures/handler_%02d_slot_%03d_raw.bin"):format(i, slot), raw)
    local refs = xrefsTo(extension.fragment, ht.pointer)
    local refText = {}
    for j = 1, math.min(#refs, 32) do refText[#refText + 1] = ("0x%X"):format(refs[j]) end
    emit("HANDLER_TEXTURE_XREF index=%d count=%d offsets=%s", i, #refs, table.concat(refText, ","))
  else
    warn("handler texture %d source pointer is outside retained fragment", i)
  end
end

local textureRanges = {}
for _, ht in ipairs(program.textures or {}) do
  local start = tonumber(ht.pointer) and tonumber(ht.pointer) - (tonumber(extension.sourceBase) or SOURCE_BASE) or nil
  local bpp = ht.size == 3 and 4 or ht.size == 2 and 2 or ht.size == 1 and 1 or 0.5
  local size = math.ceil((tonumber(ht.w) or 0) * (tonumber(ht.h) or 0) * bpp)
  if start and start >= 0 and size > 0 then textureRanges[#textureRanges + 1] = { start, start + size } end
end

local function insideTextureRange(offset)
  for _, range in ipairs(textureRanges) do
    if offset >= range[1] and offset < range[2] then return true end
  end
  return false
end

local graphQueue = { { offset = argOffset, depth = 0, from = nil } }
local graphSeen = {}
local graphCursor = 1
while graphCursor <= #graphQueue and graphCursor <= 256 do
  local node = graphQueue[graphCursor]
  graphCursor = graphCursor + 1
  if not graphSeen[node.offset] then
    graphSeen[node.offset] = true
    local blockLength = math.min(0x100, #extension.fragment - node.offset)
    emit("POINTER_GRAPH_NODE index=%d depth=%d offset=0x%X from=%s bytes=0x%X textureData=%s", graphCursor - 1, node.depth, node.offset, node.from and ("0x%X"):format(node.from) or "root", blockLength, tostring(insideTextureRange(node.offset)))
    if node.offset ~= argOffset then
      writeFile(outputDir .. ("/assets/graph_depth_%d_at_%06X.bin"):format(node.depth, node.offset), extension.fragment:sub(node.offset + 1, node.offset + blockLength))
    end
    if node.depth < 3 and not insideTextureRange(node.offset) then
      for _, edge in ipairs(scanPointerWords(extension, node.offset, blockLength)) do
        emit("POINTER_GRAPH_EDGE depth=%d source=0x%X sourceRel=+0x%X pointer=%s target=0x%X targetTexture=%s", node.depth, edge.source, edge.source - node.offset, hex(edge.pointer), edge.target, tostring(insideTextureRange(edge.target)))
        if not graphSeen[edge.target] and not insideTextureRange(edge.target) then
          graphQueue[#graphQueue + 1] = { offset = edge.target, depth = node.depth + 1, from = edge.source }
        end
      end
    end
  end
end
if graphCursor > 256 then warn("pointer graph hit 256-node limit") end

local assetSeen = {}
for i, asset in ipairs(program.assets or {}) do
  local target = tonumber(asset.offset)
  if target and not assetSeen[target] then
    assetSeen[target] = true
    local pointer = tonumber(asset.pointer)
    local data = extension.fragment:sub(target + 1, math.min(#extension.fragment, target + 0x100))
    writeFile(outputDir .. ("/assets/asset_%02d_at_%06X.bin"):format(i, target), data)
    local refs = pointer and xrefsTo(extension.fragment, pointer) or {}
    local refText = {}
    for j = 1, math.min(#refs, 32) do refText[#refText + 1] = ("0x%X"):format(refs[j]) end
    local material
    local ok, value = pcall(Materials.parse, extension, target)
    if ok then material = value end
    emit("ASSET index=%d sourceOffset=%s pointer=%s targetOffset=0x%X firstByte=0x%02X xrefs=%d xrefOffsets=%s material={%s}",
      i, hex(asset.sourceOffset), hex(pointer), target, string.byte(extension.fragment, target + 1) or 0, #refs, table.concat(refText, ","), materialText(material))
    emit("ASSET_HEXDUMP_BEGIN index=%d", i)
    for _, line in ipairs(hexdump(data, target)) do emit("%s", line) end
    emit("ASSET_HEXDUMP_END index=%d", i)
    dumpWordTable(extension, target, math.min(0x80, #data), "asset-" .. tostring(i))
    if looksLikeGfx(extension.fragment, target) then
      emit("ASSET_GFX_BEGIN index=%d", i)
      dumpGfx(extension.fragment, target, 64)
      emit("ASSET_GFX_END index=%d", i)
    end
    local nested = scanPointerWords(extension, target, math.min(0x100, #extension.fragment - target))
    for j, p in ipairs(nested) do
      emit("ASSET_POINTER asset=%d index=%d sourceRel=+0x%X pointer=%s targetOffset=0x%X", i, j, p.source - target, hex(p.pointer), p.target)
    end
  end
end

local romCandidate = discoverRom()
if not romCandidate then
  fail("could not locate Stadium 2 ROM; set STADIUM2_ROM or pass the ROM path as the first script argument")
else
  emit("ROM_CANDIDATE kind=%s path=%s", tostring(romCandidate.kind), tostring(romCandidate.path))
  local romBytes, readErr = Discovery.read(romCandidate)
  if not romBytes then
    fail("ROM read failed: %s", tostring(readErr))
  else
    local rom, meta = Rom.validate(romBytes)
    if not rom then
      fail("ROM validation failed: %s", tostring(meta))
    else
      emit("ROM byteOrder=%s title=%s md5=%s bytes=0x%X fragment26Rom=0x%X..0x%X fragment26Vram=%s..%s",
        tostring(meta.byteOrder), tostring(meta.title), tostring(meta.md5), #rom, Fragment26.ROM_START, Fragment26.ROM_END,
        hex(Fragment26.VRAM_BASE), hex(Fragment26.VRAM_END))
      dumpKoffingJumpTables(rom, outputDir)
      writeFile(outputDir .. "/fragment26_overlay.bin", rom:sub(Fragment26.ROM_START + 1, Fragment26.ROM_END))
      writeFile(outputDir .. "/fragment26_descriptor_table.bin", rom:sub(Fragment26.romOffset(Fragment26.TABLE_START) + 1, Fragment26.romOffset(Fragment26.TABLE_END - 1) + 1))
      local descriptor, descriptorErr = Fragment26.descriptor(rom, HANDLER_DESCRIPTOR)
      if not descriptor then
        fail("descriptor decode failed: %s", tostring(descriptorErr))
      else
        emit("DESCRIPTOR address=%s romOffset=%s word0=%s word1=%s target=%s", hex(descriptor.address), hex(descriptor.romOffset), hex(descriptor.word0), hex(descriptor.word1), hex(descriptor.target))
        if descriptor.target ~= FUNCTION_ROOT then fail("descriptor target mismatch expected=%s got=%s", hex(FUNCTION_ROOT), hex(descriptor.target)) end
      end
      local graph, graphErr = Fragment26.callGraph(rom, { FUNCTION_ROOT })
      if not graph then
        fail("call graph failed: %s", tostring(graphErr))
      else
        local functionKeys = sortedNumericKeys(graph.functions)
        local runtimeKeys = sortedNumericKeys(graph.runtimeCalls)
        emit("CALL_GRAPH functions=%d externalTargets=%d", #functionKeys, #runtimeKeys)
        for _, target in ipairs(runtimeKeys) do
          emit("EXTERNAL_CALL target=%s name=%s count=%d", hex(target), tostring(Fragment26.runtimeName(target) or "unknown"), graph.runtimeCalls[target])
        end
        for _, address in ipairs(functionKeys) do
          local row = graph.functions[address]
          local code = row.code
          local info = row.info
          writeFile(outputDir .. ("/functions/%08X.bin"):format(address), code)
          local decoded, labels = disassembleFunction(code, info)
          local callees = sortedNumericKeys(row.callees)
          local calleeText = {}
          for _, callee in ipairs(callees) do calleeText[#calleeText + 1] = hex(callee) end
          emit("FUNCTION_BEGIN name=%s start=%s finish=%s size=0x%X depth=%d callees=%s", info.name, hex(info.start), hex(info.finish), info.size, row.depth, table.concat(calleeText, ","))
          for _, insn in ipairs(decoded) do
            if labels[insn.pc] then emit("LABEL %s", hex(insn.pc)) end
            emit("ASM %s +0x%03X %s  %s", hex(insn.pc), insn.offset, hex(insn.word), insn.text)
            if insn.meta.mem then
              emit("MEM function=%s pc=%s op=%s base=%s offset=%d target=%s", info.name, hex(insn.pc), insn.meta.mem.op,
                reg(insn.meta.mem.base), insn.meta.mem.offset, reg(insn.meta.mem.target))
            end
            if insn.meta.call then
              emit("CALLSITE function=%s pc=%s target=%s name=%s indirect=%s", info.name, hex(insn.pc), hex(insn.meta.target),
                insn.meta.target and tostring(symbolFor(insn.meta.target) or "unknown") or "indirect", tostring(insn.meta.indirect == true))
            end
          end
          emit("FUNCTION_END name=%s", info.name)
        end
      end
    end
  end
end

emit("RESULT failures=%d warnings=%d", failures, warnings)
reportHandle:close()
io.stdout:write(REPORT_PREFIX .. "report=" .. reportPath .. "\n")
io.stdout:write(REPORT_PREFIX .. "send this TXT file; the artifacts directory is optional\n")
os.exit(failures == 0 and 0 or 1)
