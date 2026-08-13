package.path = "./?.lua;./?/init.lua;" .. package.path

local Sampler = require("mods.STADIUM2_IMPORTER.lib.sampler")
local s, t = Sampler.wrap({ cms=0, cmt=2 })
assert(s == "repeat" and t == "clamp", "repeat/clamp sampler translation")
s, t = Sampler.wrap({ cms=1, cmt=1 })
assert(s == "mirroredrepeat" and t == "mirroredrepeat", "mirror sampler translation")
local u, v = Sampler.uvScale({ shifts=1, shiftt=15 }, { 0.5, 0.25 })
assert(math.abs(u - 0.25) < 0.00001 and math.abs(v - 0.5) < 0.00001,
  "N64 positive and inverse texture shifts")
u, v = Sampler.textureGenScale({ shifts=1, shiftt=1 },
  { 4500 / 65536, 4500 / 65536 }, 32, 32)
assert(math.abs(u - 1.0986328125) < 0.00001 and math.abs(v - u) < 0.00001,
  "N64 reflection-map scale converts from gSPTexture s10.5 span")
print("4 checks passed (Stadium 2 sampler semantics)")
