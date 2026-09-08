package.path = "./?.lua;./?/init.lua;" .. package.path

local Layout = require("mods.STADIUM2_IMPORTER.lib.layout")
local Rom = require("mods.STADIUM2_IMPORTER.lib.rom")
local Extract = require("mods.STADIUM2_IMPORTER.lib.extract")
local Fragment = require("mods.STADIUM2_IMPORTER.lib.fragment")
local Renderer = require("mods.STADIUM2_IMPORTER.lib.renderer")
local Handlers = require("mods.STADIUM2_IMPORTER.lib.model_handlers")

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
  local model = assert(Fragment.extract(decoded,
    ("eye-culling-%03d"):format(species)))
  model.handlers = { records = Handlers.compile(model.fx, decoded, info.sourceBase) }
  return model
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

local phase5EyeSpecies = { 201, 208, 218, 219 }
local localEyes, callbackSurfaces = 0, 0
for _, species in ipairs(phase5EyeSpecies) do
  local model = modelFor(species)
  local rig = setmetatable({ model = model, handlerState = {
    materialBySite = {}, textureSetBySite = {},
  } }, Renderer)
  local sites = {}
  for _, record in ipairs(model.handlers.records) do
    if record.descriptor == 0x81000140 or record.descriptor == 0x81000148 then
      sites[record.commandOffset] = true
      rig.handlerState.materialBySite[record.commandOffset] = { generated = true }
      rig.handlerState.textureSetBySite[record.commandOffset] = { 1, 1 }
    end
  end
  local speciesEyes, speciesSurfaces = 0, 0
  for _, primitive in ipairs(model.prims) do
    if sites[primitive.callbackOffset] and primitive.texAnim >= 0
        and primitive.tex >= 0 then
      speciesEyes = speciesEyes + 1
      assert(not rig:callbackUsesMaterialFx(primitive),
        ("species %03d local eye atlas inherited phase-5 material FX")
          :format(species))
      assert(rig:currentMaterial(primitive) == primitive.material,
        ("species %03d local eye atlas lost its display-list material")
          :format(species))
    elseif sites[primitive.callbackOffset]
        and primitive.callbackTextureRequired == true then
      speciesSurfaces = speciesSurfaces + 1
      assert(rig:callbackUsesMaterialFx(primitive),
        ("species %03d callback-owned phase-5 surface lost its FX")
          :format(species))
    end
  end
  assert(speciesEyes > 0 and speciesSurfaces > 0,
    ("species %03d phase-5 eye/surface ownership structure changed")
      :format(species))
  localEyes, callbackSurfaces = localEyes + speciesEyes,
    callbackSurfaces + speciesSurfaces
end

print(("eye culling audit: %d face submissions/%d triangles are two-sided "
  .. "across 11 affected species; Pineco's two eye cards remain one-sided; "
  .. "%d local eyes remain separate from %d phase-5 FX surfaces")
  :format(submissions, triangles, localEyes, callbackSurfaces))
