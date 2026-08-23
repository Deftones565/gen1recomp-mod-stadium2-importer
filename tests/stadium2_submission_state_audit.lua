package.path = "./?.lua;./?/init.lua;" .. package.path

local Layout = require("mods.STADIUM2_IMPORTER.lib.layout")
local Rom = require("mods.STADIUM2_IMPORTER.lib.rom")
local Extract = require("mods.STADIUM2_IMPORTER.lib.extract")
local Fragment = require("mods.STADIUM2_IMPORTER.lib.fragment")
local Renderer = require("mods.STADIUM2_IMPORTER.lib.renderer")

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

-- Pikachu's head shell deliberately leaves an opening for two expression
-- submissions on auxiliary track 4. They contain two culled triangles and
-- one unculled triangle. The battle renderer disables imperfect body culling;
-- treating the first cover as a generic one-sided decal leaves that opening
-- exposed and shows the brown rear assembly through Pikachu's forehead.
local pikachu = modelFor(25)
local headFillTriangles, culledFillTriangles = 0, 0
for _, primitive in ipairs(pikachu.prims) do
  if primitive.decal and primitive.texAnim == 4 then
    local count = primitive.nidx / 3
    headFillTriangles = headFillTriangles + count
    if primitive.cull then culledFillTriangles = culledFillTriangles + count end
    local state = Renderer.primitiveRenderState(pikachu, primitive,
      { disableCulling = true })
    assert(not state.cullEnabled,
      "Pikachu head-fill submission can still be rejected by back-face culling")
  end
end
assert(#pikachu.prims == 17 and headFillTriangles == 3
    and culledFillTriangles == 2,
  ("Pikachu head-fill structure changed: primitives=%d fill=%d culled=%d")
    :format(#pikachu.prims, headFillTriangles, culledFillTriangles))

print("submission-state audit: Ponyta preserves 47 ROM primitive groups and "
  .. "566 triangles without per-list geometry-mode resets; Pikachu preserves "
  .. "all three ROM head-fill triangles without scene culling")
