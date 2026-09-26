package.path = "./?.lua;./?/init.lua;" .. package.path

local Rom = require("mods.STADIUM2_IMPORTER.lib.rom")
local Extract = require("mods.STADIUM2_IMPORTER.lib.extract")
local Pack = require("mods.STADIUM2_IMPORTER.lib.pack")
local Sampler = require("mods.STADIUM2_IMPORTER.lib.sampler")
local TextureParity = require("mods.STADIUM2_IMPORTER.lib.texture_parity")

local path = os.getenv("STADIUM2_ROM") or arg[1]
if not path or path == "" then
  io.stderr:write("usage: STADIUM2_ROM=/path/to/stadium2.z64 lua mods/STADIUM2_IMPORTER/tests/stadium2_dsm4_roundtrip_audit.lua\n")
  os.exit(2)
end
local file = assert(io.open(path, "rb"))
local rom = assert(Rom.normalise(file:read("*a")))
file:close()

Extract.configure({ count = 251 })
local ordinary, special = 0, 0
local modelLayout = {
  [7] = { bones = 30, prims = 11 },
  [8] = { bones = 42, prims = 17 },
  [9] = { bones = 35, prims = 23 },
  [88] = { bones = 48, prims = 24 },
  [89] = { bones = 47, prims = 30 },
  [190] = { bones = 43, prims = 7 },
}

local function assertWrap(model, primitiveIndex, expectedS, expectedT, label)
  local primitive = assert(model.prims[primitiveIndex],
    ("%s primitive %d is missing"):format(label, primitiveIndex))
  local actualS, actualT = Sampler.wrap(primitive.sampler)
  assert(actualS == expectedS and actualT == expectedT,
    ("%s primitive %d sampler is %s/%s, expected %s/%s")
      :format(label, primitiveIndex, actualS, actualT, expectedS, expectedT))
end

local function triangleCount(model)
  local count = 0
  for _, primitive in ipairs(model.prims or {}) do count = count + primitive.nidx / 3 end
  return count
end

local function dualTextureCallbackCount(model)
  local count = 0
  for _, record in ipairs(model.handlers and model.handlers.records or {}) do
    if record.descriptor == 0x81000048 then count = count + 1 end
  end
  return count
end

local function assertTextureMap(primitive, firstTexture)
  return primitive and primitive.texMap
    and primitive.texMap[4] == firstTexture
    and primitive.texMap[5] == firstTexture + 1
    and primitive.texMap[6] == firstTexture + 2
    and primitive.texMap[7] == firstTexture + 3
end

local function parse(bytes, label)
  assert(type(bytes) == "string" and bytes:sub(1, 4) == "DSM5", label .. ": not DSM5")
  local model, err = Pack.parse(bytes)
  assert(model, label .. ": " .. tostring(err))
  for index, prim in ipairs(model.prims or {}) do
    assert(prim.geometryMode ~= nil, ("%s primitive %d lost geometry mode"):format(label,index))
    assert(prim.vertexSemantics == "normal" or prim.vertexSemantics == "color",
      ("%s primitive %d lost vertex semantics"):format(label,index))
  end
  local expected = modelLayout[model.species]
  if expected then
    assert(#model.bones == expected.bones and #model.prims == expected.prims,
      ("%s model layout is bones=%d prims=%d, expected %d/%d")
        :format(label, #model.bones, #model.prims, expected.bones, expected.prims))
    for index, prim in ipairs(model.prims) do
      assert((prim.tex or -1) >= 0,
        ("%s model primitive %d lost its ROM texture"):format(label, index))
    end
  end
  if model.species == 7 then
    assertWrap(model, 2, "mirrorclamp", "clamp", label)
  elseif model.species == 8 then
    assertWrap(model, 1, "mirrorclamp", "clamp", label)
    assertWrap(model, 2, "mirrorclamp", "clamp", label)
    assertWrap(model, 10, "clamp", "clamp", label)
  elseif model.species == 9 then
    assertWrap(model, 1, "mirrorclamp", "clamp", label)
    assertWrap(model, 2, "mirrorclamp", "clamp", label)
    assertWrap(model, 14, "mirrorclamp", "clamp", label)
    -- The supplied rip's two cannon meshes are these exact ROM draws.
    assert(model.prims[22].nidx == 64 * 3 and model.prims[23].nidx == 8 * 3,
      label .. " Blastoise cannon geometry was lost")
  elseif model.species == 88 then
    local leftEye, rightEye = model.prims[21], model.prims[22]
    assert(triangleCount(model) == 700,
      label .. " Grimer geometry no longer matches the supplied rip")
    assert(model.prims[1].nidx == 2 * 3 and model.prims[1].decal
        and model.prims[2].nidx + model.prims[3].nidx == 17 * 3
        and model.prims[2].decal and not model.prims[3].decal
        and model.prims[3].callbackTextureRequired,
      label .. " Grimer mouth cutout or opaque generated base was lost")
    assert(leftEye.nidx + rightEye.nidx == 20 * 3
        and leftEye.tex == 3 and rightEye.tex == 3
        and assertTextureMap(leftEye, 3) and assertTextureMap(rightEye, 3),
      label .. " Grimer four-expression eye route was lost")
    for textureIndex = 3, 6 do
      local texture = model.textures[textureIndex]
      assert(texture and texture.w == 64 and texture.h == 32,
        ("%s Grimer expression texture %d is missing"):format(label, textureIndex))
    end
    local render = model.handlers and model.handlers.render
    assert(dualTextureCallbackCount(model) == 16
        and render and #(render.handlerTextures or {}) == 40,
      label .. " Grimer dual-texture body payloads were lost")
  elseif model.species == 89 then
    local eyes = model.prims[17]
    assert(triangleCount(model) == 701,
      label .. " Muk geometry no longer matches the supplied rip")
    assert(model.prims[1].nidx == 2 * 3 and model.prims[1].decal,
      label .. " Muk mouth cutout was lost")
    assert(eyes.nverts == 12 and eyes.nidx == 8 * 3
        and eyes.callbackOffset == nil
        and eyes.tex == 6 and eyes.texAnim == 0
        and assertTextureMap(eyes, 6),
      label .. " Muk authored eye/pupil atlas route was lost")
    for textureIndex = 6, 9 do
      local texture = model.textures[textureIndex]
      assert(texture and texture.w == 64 and texture.h == 32,
        ("%s Muk expression texture %d is missing"):format(label, textureIndex))
    end
    local tongue = model.textures[5]
    local render = model.handlers and model.handlers.render
    assert(tongue and tongue.w == 32 and tongue.h == 64,
      label .. " Muk tongue atlas was lost")
    assert(dualTextureCallbackCount(model) == 20
        and render and #(render.handlerTextures or {}) == 40,
      label .. " Muk dual-texture body payloads were lost")
  elseif model.species == 190 then
    local face = model.prims[7]
    assert(triangleCount(model) == 700 and face.nidx == 170 * 3,
      label .. " Aipom face/body atlas geometry was lost")
    assertWrap(model, 7, "mirrorclamp", "clamp", label)
    assert(face.texAnim == 0 and face.tex == 5 and face.texMap
        and face.texMap[1] == 5 and face.texMap[2] == 6
        and face.texMap[3] == 7 and face.texMap[4] == 8,
      label .. " Aipom facial-expression texture route was lost")
    assert(Pack.textureIndex(model, face, 1, 0) == 5
        and Pack.textureIndex(model, face, 1, 1) == 6
        and Pack.textureIndex(model, face, 1, 2) == 7,
      label .. " Aipom idle animation no longer selects its facial textures")
    for textureIndex = 5, 8 do
      local texture = model.textures[textureIndex]
      assert(texture and texture.w == 32 and texture.h == 64
          and type(texture.rgba) == "string" and #texture.rgba == 32 * 64 * 4,
        ("%s Aipom facial texture %d is missing"):format(label, textureIndex))
    end
  end
  if model.species == 111 then
    assert(#model.anims == 5 and model.anims[1].name == "idle"
        and model.anims[1].frames == 75,
      label .. " Rhyhorn exposed the runtime bind pose as animation zero")
    assert(model.anims[4].name == "faint" and model.anims[5].name == "hit"
        and Pack.contextSelector(model, "entrance") == 1
        and Pack.contextSelector(model, "faint") == 3
        and Pack.contextSelector(model, "hit") == 4,
      label .. " Rhyhorn ROM animation selectors were not normalized")
  end
  if model.species == 19 then
    assert(#model.anims == 6 and model.anims[2].name == "sleep"
        and model.anims[5].name == "faint"
        and model.anims[6].name == "hit"
        and Pack.contextSelector(model, "entrance") == 2
        and Pack.contextSelector(model, "sleep") == 1
        and Pack.contextSelector(model, "faint") == 4
        and Pack.contextSelector(model, "hit") == 5,
      label .. " Rattata direct ROM animation selectors were shifted")
  end
  if model.species == 208 then
    local reflected = 0
    for _, prim in ipairs(model.prims or {}) do
      if math.floor((prim.geometryMode or 0) / 0x40000) % 2 == 1 then
        reflected = reflected + 1
      end
    end
    assert(reflected == 7,
      ("%s Steelix reflected submission groups: %d, expected 7")
        :format(label, reflected))
  end
  if model.species == 198 then
    assert(model.prims[7] and model.prims[7].decal,
      label .. " Murkrow eye decal contract was lost")
  elseif model.species == 229 then
    assert(model.prims[34] and model.prims[34].decal,
      label .. " Houndoom facial decal contract was lost")
  end
  local textureReport = TextureParity.audit(model, { indexBase = 1 })
  assert(#textureReport.issues == 0,
    ("%s texture roundtrip: %s"):format(label,
      textureReport.issues[1] and textureReport.issues[1].message or "unknown loss"))
end
local function writePack(species, normal, shiny)
  parse(normal, ("normal/%03d"):format(species))
  parse(shiny, ("shiny/%03d"):format(species))
  ordinary = ordinary + 2
  return true
end
local function writeSpecial(name, bytes)
  parse(bytes, "battle/" .. name)
  special = special + 1
  return true
end

local job = Extract.newJob(rom, writePack, writeSpecial)
local steps = 0
while job:step() do
  steps = steps + 1
  if steps > 200000 then error("DSM5 import audit exceeded step budget") end
end
assert(job.success, job.error)
assert(ordinary == 502, ("ordinary pack count %d, expected 502"):format(ordinary))
assert(special == 52, ("special pack count %d, expected 52"):format(special))
print(("DSM5 roundtrip audit: ordinary=%d special=%d steps=%d failures=0")
  :format(ordinary, special, steps))
