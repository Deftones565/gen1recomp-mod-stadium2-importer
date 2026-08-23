package.path = "./?.lua;./?/init.lua;" .. package.path

local Layout = require("mods.STADIUM2_IMPORTER.lib.layout")
local Rom = require("mods.STADIUM2_IMPORTER.lib.rom")
local Extract = require("mods.STADIUM2_IMPORTER.lib.extract")
local Fragment = require("mods.STADIUM2_IMPORTER.lib.fragment")

local path = os.getenv("STADIUM2_ROM") or arg[1]
if not path or path == "" then
  io.stderr:write("usage: STADIUM2_ROM=/path/to/stadium2.z64 lua "
    .. "mods/STADIUM2_IMPORTER/tests/stadium2_politoed_torso_seam_audit.lua\n")
  os.exit(2)
end

local file = assert(io.open(path, "rb"))
local rom = assert(Rom.normalise(file:read("*a")))
file:close()
local archive = assert(Rom.archiveAt(rom, Layout.MODEL_TABLE_START))
local decoded = assert(Rom.decompress(assert(Rom.recordBytes(rom,
  assert(archive.records[187])))))
local info = assert(Extract.fragmentInfo(decoded))
decoded = Extract.runtimeFragmentForSpecies(rom, 186, decoded)
Fragment.setBase(info.sourceBase)
local model = assert(Fragment.extract(decoded, "politoed-torso-seam-audit"))

assert(#model.bones == 37 and #model.prims == 61 and #model.textures == 19,
  ("Politoed ROM structure changed: bones=%d primitives=%d textures=%d")
    :format(#model.bones, #model.prims, #model.textures))
local vertices, triangles, crossBoneTriangles = 0, 0, 0
for index, primitive in ipairs(model.prims) do
  vertices = vertices + primitive.nverts
  triangles = triangles + primitive.nidx / 3
  assert(primitive.nidx > 0,
    ("Politoed ROM submission %d contains no triangles"):format(index))
  assert(primitive.tex >= 0 and model.textures[primitive.tex + 1],
    ("Politoed primitive %d has no renderable ROM texture"):format(index))
  for vertex = 1, primitive.nverts do
    local skin = primitive.skin[vertex]
    assert(skin and model.bones[skin + 1],
      ("Politoed primitive %d vertex %d has an invalid skin bone")
        :format(index, vertex))
  end
  for triangle = 1, primitive.nidx, 3 do
    local first = primitive.skin[primitive.idx[triangle] + 1]
    local second = primitive.skin[primitive.idx[triangle + 1] + 1]
    local third = primitive.skin[primitive.idx[triangle + 2] + 1]
    if first ~= second or first ~= third then
      crossBoneTriangles = crossBoneTriangles + 1
    end
  end
end
assert(vertices == 787 and triangles == 722,
  ("Politoed geometry loss: vertices=%d/787 triangles=%d/722")
    :format(vertices, triangles))
-- These triangles consume vertices loaded under two adjacent named matrices.
-- Clearing the RSP vertex cache at each 0x1E submission drops all 299 and
-- leaves only 423/722 triangles, which is the incomplete rigid-shell model.
assert(crossBoneTriangles == 299,
  ("Politoed submission cache lost cross-bone triangles: %d/299")
    :format(crossBoneTriangles))

local upper, lower = assert(model.textures[2]), assert(model.textures[3])
assert(upper.w == 64 and upper.h == 32 and lower.w == 64 and lower.h == 32,
  "Politoed torso maps no longer match the ROM's two 64x32 surfaces")
assert(upper.stitchedBoundary == "politoed-torso"
    and lower.stitchedBoundary == "politoed-torso",
  "Politoed torso boundary correction was not applied")
local upperRow = upper.rgba:sub(#upper.rgba - 64 * 4 + 1)
local lowerRow = lower.rgba:sub(1, 64 * 4)
assert(upperRow == lowerRow,
  "Politoed's adjoining torso rows can still produce a visible seam")
local upperRoute, lowerRoute = false, false
for _, primitive in ipairs(model.prims) do
  if primitive.tex == 1 then upperRoute = true end
  if primitive.tex == 2 then lowerRoute = true end
end
assert(upperRoute and lowerRoute, "Politoed's upper/lower torso texture route changed")

print("politoed torso audit: 61 ordered ROM submissions, 787 vertices, 722 triangles, "
  .. "299 persistent-cache cross-bone triangles; 64 shared boundary texels match")
