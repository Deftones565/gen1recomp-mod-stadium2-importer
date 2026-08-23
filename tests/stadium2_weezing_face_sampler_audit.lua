package.path = "./?.lua;./?/init.lua;" .. package.path

local Layout = require("mods.STADIUM2_IMPORTER.lib.layout")
local Rom = require("mods.STADIUM2_IMPORTER.lib.rom")
local Extract = require("mods.STADIUM2_IMPORTER.lib.extract")
local Fragment = require("mods.STADIUM2_IMPORTER.lib.fragment")
local Sampler = require("mods.STADIUM2_IMPORTER.lib.sampler")

local path = os.getenv("STADIUM2_ROM") or arg[1]
if not path or path == "" then
  io.stderr:write("usage: STADIUM2_ROM=/path/to/stadium2.z64 lua "
    .. "mods/STADIUM2_IMPORTER/tests/stadium2_weezing_face_sampler_audit.lua\n")
  os.exit(2)
end

local file = assert(io.open(path, "rb"))
local rom = assert(Rom.normalise(file:read("*a")))
file:close()
local archive = assert(Rom.archiveAt(rom, Layout.MODEL_TABLE_START))

local function extractSpecies(species)
  local decoded = assert(Rom.decompress(assert(Rom.recordBytes(rom,
    assert(archive.records[species + 1])))))
  local info = assert(Extract.fragmentInfo(decoded))
  decoded = Extract.runtimeFragmentForSpecies(rom, species, decoded)
  Fragment.setBase(info.sourceBase)
  return assert(Fragment.extract(decoded, "face-sampler-audit-" .. species))
end

local koffing = extractSpecies(109)
local koffingFace
for _, primitive in ipairs(koffing.prims) do
  if primitive.texAnim == 0 and primitive.nverts == 10
      and primitive.nidx == 24 then
    koffingFace = primitive
    break
  end
end
assert(koffingFace and koffingFace.sampler.cms == 3
    and koffingFace.sampler.cmt == 2,
  "Koffing's mirrored half-face primitive is missing")
local koffingWrapS, koffingWrapT = Sampler.wrap(koffingFace.sampler)
assert(koffingWrapS == "mirrorclamp" and koffingWrapT == "clamp",
  "Koffing no longer mirrors its authored eye exactly once")

local model = extractSpecies(110)

local face
for _, primitive in ipairs(model.prims) do
  if primitive.texAnim == 0 and primitive.nverts == 12
      and primitive.nidx == 36 then
    face = primitive
    break
  end
end
assert(face, "Weezing small-head face primitive is missing")
assert(face.sampler and face.sampler.cms == 3 and face.sampler.cmt == 2,
  "Weezing small-head face no longer has ROM mirror+clamp S / clamp T mode")
local wrapS, wrapT = Sampler.wrap(face.sampler)
assert(wrapS == "mirrorclamp" and wrapT == "clamp",
  "Weezing small-head face no longer preserves one mirrored face span")

local minU, maxU = math.huge, -math.huge
for vertex = 1, face.nverts do
  local u = face.uv[vertex * 2 - 1]
  minU, maxU = math.min(minU, u), math.max(maxU, u)
end
assert(minU < -0.45 and maxU > 2.5,
  "Weezing face fixture no longer exercises both side regions")

print(("weezing face sampler audit: CMS=3 mirrors U once then clamps %.3f..%.3f")
  :format(minU, maxU))
