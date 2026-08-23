package.path = "./?.lua;./?/init.lua;" .. package.path

local Layout = require("mods.STADIUM2_IMPORTER.lib.layout")
local Rom = require("mods.STADIUM2_IMPORTER.lib.rom")
local Extract = require("mods.STADIUM2_IMPORTER.lib.extract")
local Fragment = require("mods.STADIUM2_IMPORTER.lib.fragment")

local path = os.getenv("STADIUM2_ROM") or arg[1]
if not path or path == "" then
  io.stderr:write("usage: STADIUM2_ROM=/path/to/stadium2.z64 lua "
    .. "mods/STADIUM2_IMPORTER/tests/stadium2_submission_state_audit.lua\n")
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
  return assert(Fragment.extract(decoded,
    ("submission-state-%03d"):format(species)))
end

-- Ponyta's ROM lists deliberately leave geometry mode at zero across a run of
-- sibling submissions. Resetting it for each Lua call invents alternating
-- 0x000400 primitives and splits the native 47 primitive groups into 54.
local ponyta = modelFor(77)
assert(#ponyta.prims == 47,
  ("Ponyta submission grouping changed: %d/47 primitives"):format(#ponyta.prims))
local triangles = 0
for index, primitive in ipairs(ponyta.prims) do
  triangles = triangles + primitive.nidx / 3
  assert(primitive.geometryMode ~= 0x000400,
    ("Ponyta primitive %d restarted with fabricated back-cull state")
      :format(index))
end
assert(triangles == 566,
  ("Ponyta submission geometry changed: %d/566 triangles"):format(triangles))

print("submission-state audit: Ponyta preserves 47 ROM primitive groups and "
  .. "566 triangles without per-list geometry-mode resets")
