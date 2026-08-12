package.path = "./?.lua;./?/init.lua;" .. package.path

local Fragment = require("mods.STADIUM2_IMPORTER.lib.fragment")
local Fx = require("mods.STADIUM2_IMPORTER.lib.fx")

local checks = 0
local function ok(value, message)
  checks = checks + 1
  if not value then error("FAIL " .. message, 0) end
end

local bytes = {}
for i = 1, 0x300 do bytes[i] = 0 end

local function put8(offset, value)
  bytes[offset + 1] = value % 0x100
end

local function put16(offset, value)
  put8(offset, math.floor(value / 0x100))
  put8(offset + 1, value)
end

local function put32(offset, value)
  put8(offset, math.floor(value / 0x1000000))
  put8(offset + 1, math.floor(value / 0x10000))
  put8(offset + 2, math.floor(value / 0x100))
  put8(offset + 3, value)
end

local function putText(offset, text)
  for i = 1, #text do put8(offset + i - 1, text:byte(i)) end
end

local BASE = 0x8FF00000
putText(0x08, "FRAGMENT")
put32(0x20, 0x3C088FF0)
put32(0x24, 0x25080100)
put16(0x100, 25)
put32(0x108, BASE + 0x140)
put32(0x10C, 0)
put32(0x110, 0)
put32(0x140, BASE + 0x180)
put32(0x144, BASE + 0x1C0)
put32(0x148, 0)

put8(0x180, 0x05)
put8(0x184, 0x1D)
put8(0x185, 7)
put8(0x1A0, 0x05)
put8(0x1A4, 0x08)
put32(0x1A8, 0x80123456)
put32(0x1AC, BASE + 0x220)
put8(0x1B0, 0x01)

put8(0x1C0, 0x08)
put32(0x1C4, 0x80ABCDEF)
put32(0x1C8, 0)
put8(0x1CC, 0x01)

put32(0x240, 0x27BDFFE0)
put32(0x244, 0xAFBF001C)
put32(0x248, 0x03E00008)
put32(0x24C, 0x27BD0020)

local chars = {}
for i = 1, #bytes do chars[i] = string.char(bytes[i]) end
local data = table.concat(chars)

local result, err = Fragment.inspectFx(data, "synthetic-fx", BASE)
ok(result ~= nil, err or "inspect FX result")
ok(result.species == 25, "species decoded")
ok(result.geometry == 2, "all geo roots discovered")
ok(#result.nodes == 2, "all FX nodes discovered")
ok(result.nodes[1].callback == 0x80123456, "first callback")
ok(result.nodes[1].argPointer == BASE + 0x220, "first raw argument pointer")
ok(result.nodes[1].argOffset == 0x220, "first argument offset")
ok(result.nodes[1].bone == 0 and result.nodes[1].boneId == 7, "first bone context")
ok(result.nodes[2].layout == 2, "second geo root scanned")
ok(result.nodes[2].callback == 0x80ABCDEF, "second callback")

local deduped = Fragment.dedupeFx({
  { bone = 2, callback = 0x81000068, handler = 0x81000068, arg = 0x120, commandOffset = 0x200 },
  { bone = 2, callback = 0x81000068, handler = 0x81000068, arg = 0x120, commandOffset = 0x220 },
  { bone = 2, callback = 0x81000068, handler = 0x81000068, arg = 0x120, commandOffset = 0x200 },
})
ok(#deduped == 2, "distinct physical handler commands survive dedupe")
ok(deduped[1].commandOffset == 0x200 and deduped[2].commandOffset == 0x220, "handler command offsets preserved")
ok(result.nodes[2].argPointer == 0, "null argument pointer preserved")
ok(result.nodes[2].argOffset == nil, "null argument offset")
ok(#result.warnings == 0, "no FX scan warnings")

local localProbe = Fx.probe(data, BASE + 0x240, BASE, 0x100)
ok(localProbe.origin == "fragment", "fragment callback classified")
ok(localProbe.offset == 0x240, "fragment callback offset")
ok(localProbe.reason == "jr_ra", "fragment callback return detected")
ok(localProbe.length == 0x10, "fragment callback probe length")
ok(type(localProbe.fingerprint) == "string" and #localProbe.fingerprint > 0, "fragment callback fingerprint")
ok(localProbe.words == "27BDFFE0 AFBF001C 03E00008 27BD0020", "fragment callback words")

local runtimeProbe = Fx.probe(data, 0x80123456, BASE, 0x100)
ok(runtimeProbe.origin == "runtime", "runtime callback classified")
ok(runtimeProbe.offset == nil, "runtime callback has no fragment offset")

local symbols = assert(Fx.parseSymbolMap("func_test = 0x80123456; // type:func\nfunc_next = 0x80123500; // type:func\n"))
local exact = Fx.resolveSymbol(symbols, 0x80123456)
ok(exact and exact.exact and exact.name == "func_test", "exact callback symbol")
local nearest = Fx.resolveSymbol(symbols, 0x80123460)
ok(nearest and not nearest.exact and nearest.name == "func_test" and nearest.delta == 0xA, "nearest callback symbol")

print(("%d checks passed (Stadium 2 model FX)"):format(checks))
