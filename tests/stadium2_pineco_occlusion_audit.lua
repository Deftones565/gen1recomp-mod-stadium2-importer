package.path = "./?.lua;./?/init.lua;" .. package.path

local Layout = require("mods.STADIUM2_IMPORTER.lib.layout")
local Rom = require("mods.STADIUM2_IMPORTER.lib.rom")
local Extract = require("mods.STADIUM2_IMPORTER.lib.extract")
local Fragment = require("mods.STADIUM2_IMPORTER.lib.fragment")
local Renderer = require("mods.STADIUM2_IMPORTER.lib.renderer")

local path = os.getenv("STADIUM2_ROM") or arg[1]
if not path or path == "" then
  io.stderr:write("usage: STADIUM2_ROM=/path/to/stadium2.z64 lua "
    .. "mods/STADIUM2_IMPORTER/tests/stadium2_pineco_occlusion_audit.lua\n")
  os.exit(2)
end

local file = assert(io.open(path, "rb"))
local rom = assert(Rom.normalise(file:read("*a")))
file:close()
local archive = assert(Rom.archiveAt(rom, Layout.MODEL_TABLE_START))
local decoded = assert(Rom.decompress(assert(Rom.recordBytes(rom,
  assert(archive.records[205])))))
local info = assert(Extract.fragmentInfo(decoded))
decoded = Extract.runtimeFragmentForSpecies(rom, 204, decoded)
Fragment.setBase(info.sourceBase)
local model = assert(Fragment.extract(decoded, "pineco-occlusion-audit"))

local eyes = {}
for _, primitive in ipairs(model.prims) do
  if primitive.texAnim >= 0 and primitive.nverts == 3
      and primitive.nidx == 3 then
    eyes[#eyes + 1] = primitive
  end
end
assert(#eyes == 2, "Pineco no longer has its two ROM eye triangles")
for _, eye in ipairs(eyes) do
  assert(eye.decal and eye.cull,
    "Pineco eye lost its one-sided ROM decal/culling state")
  local state = Renderer.primitiveRenderState(model, eye,
    { disableCulling = true })
  assert(state.cullEnabled,
    "battle scene override exposes a Pineco eye through the shell")
end
assert(math.abs(Renderer.PINECO_DECAL_DEPTH_BIAS - 4/65535) < 0.000000001,
  "Pineco eye depth pull is large enough to cross the shell")

print("pineco occlusion audit: two one-sided ROM eye decals remain shell-occluded")
