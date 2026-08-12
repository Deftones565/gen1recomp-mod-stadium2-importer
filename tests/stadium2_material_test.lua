package.path = "./?.lua;./?/init.lua;" .. package.path

local Materials = require("mods.STADIUM2_IMPORTER.lib.materials")

local checks = 0
local function ok(value, message)
  checks = checks + 1
  if not value then error("FAIL " .. message, 0) end
end

local function be32(value)
  return string.char(math.floor(value / 0x1000000) % 256,
    math.floor(value / 0x10000) % 256,
    math.floor(value / 0x100) % 256, value % 256)
end

local function command(w0, w1) return be32(w0) .. be32(w1) end

local fragment = command(0xFA000000, 0x804020FF)
  .. command(0xFB000000, 0x20408080)
  .. command(0xF5000000, 0x00080102) -- T clamp, S mirror, S shift 2
  .. command(0xF2000000, 0x0007C07C)
  .. command(0xDF000000, 0)

local state = assert(Materials.parse({ fragment = fragment, sourceBase = 0x8FF00000 }, 0))
ok(state.complete, "material display list terminates")
ok(state.commandCount == 5, "all material commands retained")
ok(math.abs(state.primitiveColor[1] - 128 / 255) < 0.000001, "primitive colour decoded")
ok(math.abs(state.environmentColor[3] - 128 / 255) < 0.000001, "environment colour decoded")
ok(state.wrapS == "mirroredrepeat" and state.wrapT == "clamp", "sampler wrap modes decoded")
ok(state.activeTile.s.shift == 2, "sampler shift decoded")
ok(next(state.unsupported) == nil, "known material commands supported")

local bad = assert(Materials.parse({ fragment = command(0x12000000, 0) .. command(0xDF000000, 0) }, 0))
ok(bad.unsupported[0x12] == 1, "unsupported material command reported")

print(("%d checks passed (Stadium 2 materials)"):format(checks))
