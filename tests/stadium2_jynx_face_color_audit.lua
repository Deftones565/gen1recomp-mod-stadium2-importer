package.path = "./?.lua;./?/init.lua;" .. package.path

local Layout = require("mods.STADIUM2_IMPORTER.lib.layout")
local Rom = require("mods.STADIUM2_IMPORTER.lib.rom")
local Extract = require("mods.STADIUM2_IMPORTER.lib.extract")
local Fragment = require("mods.STADIUM2_IMPORTER.lib.fragment")
local Handlers = require("mods.STADIUM2_IMPORTER.lib.model_handlers")
local Materials = require("mods.STADIUM2_IMPORTER.lib.materials")

local path = os.getenv("STADIUM2_ROM") or arg[1]
if not path or path == "" then
  io.stderr:write("usage: STADIUM2_ROM=/path/to/stadium2.z64 lua "
    .. "mods/STADIUM2_IMPORTER/tests/stadium2_jynx_face_color_audit.lua\n")
  os.exit(2)
end

local file = assert(io.open(path, "rb"))
local rom = assert(Rom.normalise(file:read("*a")))
file:close()
local archive = assert(Rom.archiveAt(rom, Layout.MODEL_TABLE_START))
local blob = assert(Rom.recordBytes(rom, assert(archive.records[125])))
local decoded = assert(Rom.decompress(blob))
local info = assert(Extract.fragmentInfo(decoded))
decoded = Extract.runtimeFragmentForSpecies(rom, 124, decoded)
Fragment.setBase(info.sourceBase)
local model = assert(Fragment.extract(decoded, "jynx-face-color-audit"))

local faceIndex, face
for index, primitive in ipairs(model.prims) do
  local color = primitive.nodeColor
  if primitive.tex == 2 and color and color[1] == 0x56
      and color[2] == 0x38 and color[3] == 0x60 and color[4] == 0xFF then
    faceIndex, face = index, primitive
    break
  end
end
assert(face, "Jynx's ROM-authored 56/38/60/FF face draw was merged into the neutral head")
assert(face.nidx == 25 * 3, "Jynx's tinted face draw no longer has the ROM's 25 triangles")

local extensionBytes = Handlers.packExtension({}, info.sourceBase, decoded,
  { prims = model.prims, handlerTextures = {} })
local extension = assert(Handlers.readExtension("DSM4" .. extensionBytes))
local parsed = { handlers = extension, prims = {} }
for index = 1, #model.prims do parsed.prims[index] = {} end
Materials.attach(parsed)
local material = assert(parsed.prims[faceIndex].material,
  "Jynx face material was lost from the cache extension")
local color = material.primitiveColor
assert(math.abs(color[1] - 0x56 / 255) < 1e-8
    and math.abs(color[2] - 0x38 / 255) < 1e-8
    and math.abs(color[3] - 0x60 / 255) < 1e-8 and color[4] == 1,
  "Jynx face tint did not survive the cache roundtrip")

print(("jynx face color audit: primitive=%d triangles=%d rgba=56,38,60,FF")
  :format(faceIndex, face.nidx / 3))
