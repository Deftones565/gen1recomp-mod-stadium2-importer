package.path = "./?.lua;./?/init.lua;" .. package.path

local Layout = require("mods.STADIUM2_IMPORTER.lib.layout")
local Rom = require("mods.STADIUM2_IMPORTER.lib.rom")
local Extract = require("mods.STADIUM2_IMPORTER.lib.extract")
local Fragment = require("mods.STADIUM2_IMPORTER.lib.fragment")
local Renderer = require("mods.STADIUM2_IMPORTER.lib.renderer")

local path = os.getenv("STADIUM2_ROM") or arg[1]
if not path or path == "" then
  io.stderr:write("usage: STADIUM2_ROM=/path/to/stadium2.z64 lua "
    .. "mods/STADIUM2_IMPORTER/tests/stadium2_eye_culling_audit.lua\n")
  os.exit(2)
end

local file = assert(io.open(path, "rb"))
local rom = assert(Rom.normalise(file:read("*a")))
file:close()
local archive = assert(Rom.archiveAt(rom, Layout.MODEL_TABLE_START))

local function modelFor(species)
  local decoded = assert(Rom.decompress(assert(Rom.recordBytes(rom,
    assert(archive.records[species + 1])))))
  local info = assert(Extract.fragmentInfo(decoded))
  decoded = Extract.runtimeFragmentForSpecies(rom, species, decoded)
  Fragment.setBase(info.sourceBase)
  return assert(Fragment.extract(decoded, ("eye-culling-%03d"):format(species)))
end

local affected = { 197, 198, 200, 205, 212, 214, 215, 227, 228, 229, 233 }
local submissions, triangles = 0, 0
for _, species in ipairs(affected) do
  local model = modelFor(species)
  local found = 0
  for _, primitive in ipairs(model.prims) do
    if primitive.texAnim >= 0 then
      found = found + 1
      submissions = submissions + 1
      triangles = triangles + primitive.nidx / 3
      local state = Renderer.primitiveRenderState(model, primitive,
        { disableCulling = true })
      assert(not state.cullEnabled,
        ("species %03d animated face submission is still culled"):format(species))
    end
  end
  assert(found > 0,
    ("species %03d lost its ROM animated face submissions"):format(species))
end

local pineco = modelFor(204)
local pinecoEyes = 0
for _, primitive in ipairs(pineco.prims) do
  if primitive.decal and primitive.texAnim >= 0
      and primitive.nverts == 3 and primitive.nidx == 3 then
    pinecoEyes = pinecoEyes + 1
    assert(Renderer.primitiveRenderState(pineco, primitive,
      { disableCulling = true }).cullEnabled,
      "Pineco eye card no longer remains shell-occluded")
  end
end
assert(pinecoEyes == 2, "Pineco ROM eye-card structure changed")

print(("eye culling audit: %d face submissions/%d triangles are two-sided "
  .. "across 11 affected species; Pineco's two eye cards remain one-sided")
  :format(submissions, triangles))
