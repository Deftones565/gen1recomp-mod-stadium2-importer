package.path = "./?.lua;./?/init.lua;" .. package.path

local Sampler = require("mods.STADIUM2_IMPORTER.lib.sampler")
local Fragment = require("mods.STADIUM2_IMPORTER.lib.fragment")
local s, t = Sampler.wrap({ cms=0, cmt=2 })
assert(s == "repeat" and t == "clamp", "repeat/clamp sampler translation")
s, t = Sampler.wrap({ cms=1, cmt=1 })
assert(s == "mirroredrepeat" and t == "mirroredrepeat", "mirror sampler translation")
s, t = Sampler.wrap({ cms=3, cmt=3 })
assert(s == "mirrorclamp" and t == "mirrorclamp",
  "combined N64 mirror/clamp mode preserves one mirrored span")
assert(Sampler.wrapCode(s) == 3,
  "combined N64 mirror/clamp mode reaches the shader")
assert(Sampler.foldCoordinate(-0.5, s) == 0
    and Sampler.foldCoordinate(0.5, s) == 0.5
    and Sampler.foldCoordinate(1, s) == 1
    and Sampler.foldCoordinate(1.5, s) == 0.5
    and Sampler.foldCoordinate(2.5, s) == 0,
  "combined mode mirrors exactly once and clamps both outer regions")
local u, v = Sampler.uvScale({ shifts=1, shiftt=15 }, { 0.5, 0.25 })
assert(math.abs(u - 0.25) < 0.00001 and math.abs(v - 0.5) < 0.00001,
  "N64 positive and inverse texture shifts")
u, v = Sampler.textureGenScale({ shifts=1, shiftt=1 },
  { 4500 / 65536, 4500 / 65536 }, 32, 32)
assert(math.abs(u - 1.0986328125) < 0.00001 and math.abs(v - u) < 0.00001,
  "N64 reflection-map scale converts from gSPTexture s10.5 span")
local pineco = Fragment.decodeTileSampler(0x00094260)
assert(pineco.cms == 2 and pineco.cmt == 2,
  "Pineco eye render tile clamps both axes")
assert(pineco.masks == 6 and pineco.maskt == 5,
  "Pineco eye render tile keeps its ROM-authored 64x32 masks")
assert(pineco.shifts == 0 and pineco.shiftt == 0,
  "Pineco eye render tile has no coordinate shift")
-- RDP 3-point filter: continuous across each texel's diagonal and exact
-- at the four texel centres.
local Renderer = require("mods.STADIUM2_IMPORTER.lib.renderer")
local tp = Renderer.threePoint
local t00, t10, t01, t11 = 0.1, 0.9, 0.3, 0.6
for _, fx in ipairs({ 0, 0.25, 0.5, 0.7, 1 }) do
  local fy = 1 - fx
  local lower = t00 * (1 - fx - fy) + t10 * fx + t01 * fy
  assert(math.abs(tp(t00, t10, t01, t11, fx, fy) - lower) < 1e-9,
    "3-point filter is continuous on the texel diagonal at fx=" .. fx)
end
assert(tp(t00, t10, t01, t11, 1, 0) == t10 and tp(t00, t10, t01, t11, 0, 1) == t01
    and tp(t00, t10, t01, t11, 1, 1) == t11,
  "3-point filter hits the neighbouring texel centres")
local source = io.open("mods/STADIUM2_IMPORTER/lib/renderer.lua"):read("*a")
assert(source:find("o - vec2(texel.x,0.0)) * (1.0-f.x)", 1, true)
    and source:find("o - vec2(0.0,texel.y)) * (1.0-f.y)", 1, true),
  "the shader's sample3 uses the reference weights")
print("13 checks passed (Stadium 2 sampler semantics)")
