package.path = "./?.lua;./?/init.lua;" .. package.path

local Extract = require("mods.STADIUM2_IMPORTER.lib.extract")
local Pack = require("mods.STADIUM2_IMPORTER.lib.pack")
local Rom = require("mods.STADIUM2_IMPORTER.lib.rom")
local Fragment = require("mods.STADIUM2_IMPORTER.lib.fragment")
local Renderer = require("mods.STADIUM2_IMPORTER.lib.renderer")

local romPath = os.getenv("STADIUM2_ROM")
  or "mods/STADIUM2_IMPORTER/baseroms/stadium2.z64"
local file = io.open(romPath, "rb")
if not file then
  assert(os.getenv("STADIUM2_REQUIRE_ROM") ~= "1",
    "required Stadium 2 ROM unavailable")
  print("SKIP: slime model ROM regression (ROM unavailable)")
  return
end
local rom = assert(Rom.normalise(file:read("*a")))
file:close()

local function check(value, message)
  assert(value, message)
end

-- Retail Muk: a local eye draw followed by a separate, empty callback node.
-- 0x81005DB4 writes the generated DL into that node's +0x18 field.
local archive = assert(Rom.archiveAt(rom, Extract.MODEL_TABLE_START))
local bytes = assert(Rom.decompress(assert(Rom.recordBytes(rom, archive.records[90]))))
local fragment = assert(Fragment.open(bytes))
for offset, word in pairs({
  [0xD7D0] = 0x23010000, [0xD7E0] = 0x22010000, [0xD7E4] = 0x8FF0C0C0,
  [0xD7E8] = 0x22010000, [0xD7EC] = 0, [0xD7F0] = 0x08000000,
  [0xD7F4] = 0x81000048,
}) do
  check(fragment:u32(offset) == word, ("Muk graph changed at 0x%X"):format(offset))
end

local captured = {}
local job = Extract.newJob(rom, function(name, normal, shiny)
  captured[tonumber(name)] = { normal = normal, shiny = shiny }
  return true
end, function() return true end, { species = { 88, 89 }, specials = false })
for _ = 1, 10000000 do
  if not job:step() then break end
end
check(job.phase == "done" and job.success == true,
  "slime model extraction job did not finish successfully")
check(#job.failed == 0, "slime model extraction failed: "
  .. tostring(job.failed[1]))

local function triangleCount(model)
  local total = 0
  for _, prim in ipairs(model.prims or {}) do
    total = total + math.floor((tonumber(prim.nidx) or 0) / 3)
  end
  return total
end

for _, species in ipairs({ 88, 89 }) do
  local pair = captured[species]
  check(type(pair) == "table", ("species %03d pair was not captured"):format(species))
  for _, variant in ipairs({ "normal", "shiny" }) do
    local model = assert(Pack.parse(pair[variant]))
    check(triangleCount(model) == (species == 88 and 700 or 701),
      ("%03d %s triangle count changed"):format(species, variant))
    local rig = assert(Renderer.new(model))
    local descriptors, active = {}, 0
    for _, record in ipairs(model.handlers.records) do
      descriptors[record.commandOffset] = record.descriptor
    end
    for _, prim in ipairs(model.prims) do
      if descriptors[prim.callbackOffset] == 0x81000048 then
        active = active + 1
        check(prim.callbackTextureRequired and not prim.decal,
          "slime surface retained inherited atlas alpha/decal classification")
        check(rig:currentTexture(prim) == rig.handlerState.textureBySite[prim.callbackOffset],
          "slime surface sampled inherited atlas instead of generated tile")
      end
    end
    check(active == (species == 88 and 19 or 26), "generated surface coverage changed")

    -- These lower-body triangles inherited the transparent mouth image.
    local base = model.prims[species == 88 and 3 or 2]
    check(base.nidx == (species == 88 and 13 or 41) * 3
        and base.callbackTextureRequired and not base.decal,
      "lower-body triangles lost their opaque generated material")
    local source, generated = model.textures[base.tex], model.textures[rig:currentTexture(base)]
    local transparentSource = false
    for at = 4, #source.rgba, 4 do
      if source.rgba:byte(at) == 0 then transparentSource = true end
    end
    check(transparentSource, "regression no longer exercises stale mouth transparency")
    for at = 4, #generated.rgba, 4 do
      check(generated.rgba:byte(at) == 255, "generated base tile is not opaque")
    end

    local eyeIndices = species == 88 and {21, 22} or {17}
    for _, index in ipairs(eyeIndices) do
      local eye = model.prims[index]
      check(eye.nverts == 12 and eye.nidx == (species == 88 and 10 or 8) * 3
          and eye.callbackOffset == nil and not eye.callbackTextureRequired,
        "null callback node captured the preceding local eye draw")
      check(not rig:callbackOwnsTexture(eye) and not rig:callbackUsesMaterialFx(eye),
        "slime material leaked into eye rendering")
      local seen = {}
      for expression = 4, 7 do
        local slot = assert(eye.texMap[expression], "eye expression is missing")
        local texture = assert(model.textures[slot])
        check(texture.w == 64 and texture.h == 32 and not seen[slot],
          "eye expressions lost distinct authored atlases")
        seen[slot] = true
      end
      for ai, anim in ipairs(model.anims) do
        rig.animIndex, rig.auxIndex = ai, anim.aux
        for frame = 0, anim.frames - 1 do
          rig.frame = frame
          check(rig:currentTexture(eye) == Pack.textureIndex(model, eye, ai, frame, anim.aux),
            "eye expression stream was replaced during playback")
        end
      end
    end
    rig:release()
  end
end

print("slime model ROM regression: Grimer/Muk geometry, active carriers, "
  .. "local atlases, and Muk eye expressions passed")
