package.path = "./?.lua;./?/init.lua;" .. package.path

local Layout = require("mods.STADIUM2_IMPORTER.lib.layout")
local Rom = require("mods.STADIUM2_IMPORTER.lib.rom")
local Extract = require("mods.STADIUM2_IMPORTER.lib.extract")
local Fragment = require("mods.STADIUM2_IMPORTER.lib.fragment")
local Handlers = require("mods.STADIUM2_IMPORTER.lib.model_handlers")
local Materials = require("mods.STADIUM2_IMPORTER.lib.materials")
local RenderContract = require("mods.STADIUM2_IMPORTER.lib.render_contract")

local path = os.getenv("STADIUM2_ROM") or arg[1]
if not path or path == "" then
  io.stderr:write("usage: STADIUM2_ROM=/path/to/stadium2.z64 lua mods/STADIUM2_IMPORTER/tests/stadium2_render_parity_audit.lua\n")
  os.exit(2)
end

local file = assert(io.open(path, "rb"))
local raw = file:read("*a")
file:close()
local data = assert(Rom.normalise(raw))
local archive = assert(Rom.archiveAt(data, Layout.MODEL_TABLE_START))

local descriptors, callbacks, models, materials, callbackTextures = {}, 0, 0, 0, 0
local phase5Callbacks, phase5Resolved = 0, 0
local materialFxCallbacks, materialFxResolved = 0, 0
local targetPhase5 = { [159] = { total = 0, textures = 0, materials = 0, nonWhite = 0 },
  [200] = { total = 0, textures = 0, materials = 0, nonWhite = 0 } }
local textureHandlers = { [0x81000038] = true, [0x81000048] = true, [0x81000050] = true,
  [0x81000068] = true, [0x81000070] = true }
local failures = {}
local function fail(text) failures[#failures + 1] = text end
local reportedMaterialPayload = {}
local reportedMaterialRoute = {}
local function u32be(bytes, offset)
  local a, b, c, d = bytes:byte(offset + 1, offset + 4)
  return d and ((a * 256 + b) * 256 + c) * 256 + d or nil
end

if not RenderContract.supportsCoplanarDecals() then
  fail("model depth contract lacks strict body occlusion plus non-writing eye/face decals")
end

for dex = 1, 251 do
  local record = archive.records[dex + 1]
  local blob = record and Rom.recordBytes(data, record)
  local decoded, decodeErr = blob and Rom.decompress(blob)
  if not decoded then
    fail(("dex %03d decompress: %s"):format(dex, tostring(decodeErr)))
  else
    local info, infoErr = Extract.fragmentInfo(decoded)
    if not info then
      fail(("dex %03d fragment: %s"):format(dex, tostring(infoErr)))
    else
      local runtimeDecoded = Extract.runtimeFragmentForSpecies(data, dex, decoded)
      Fragment.setBase(info.sourceBase)
      local model, modelErr = Fragment.extract(runtimeDecoded, ("dex_%03d"):format(dex))
      if not model then
        fail(("dex %03d extract: %s"):format(dex, tostring(modelErr)))
      else
        models = models + 1
        local callbackConsumers = {}
        for _, prim in ipairs(model.prims or {}) do
          if prim.callbackOffset then callbackConsumers[prim.callbackOffset] = true end
        end
        local records = Handlers.compile(model.fx, runtimeDecoded, info.sourceBase)
        callbacks = callbacks + #records
        for _, row in ipairs(records) do descriptors[row.descriptor] = true end
        local extension = Handlers.readExtension("DSM4audit"
          .. Handlers.packExtension(records, info.sourceBase, runtimeDecoded,
            { prims = model.prims, handlerTextures = model.handlerTextures }))
        if not extension or extension.version ~= 4 then
          fail(("dex %03d S2HX v4 roundtrip"):format(dex))
        else
          local phase5State = select(1, Handlers.runExtension(extension, 5, {
            species = dex, sourceFrame = 0, geometryIndex = 0,
          }, {})) or {}
          local materialState = select(1, Handlers.runExtension(extension, 2, {
            species = dex, sourceFrame = 0, materialFrame = 37,
          }, {})) or {}
          for _, row in ipairs(extension.records) do
            if not row.program or not row.program.complete then
              fail(("dex %03d callback %08X incomplete"):format(dex, row.descriptor or 0))
            end
            if textureHandlers[row.descriptor] and #(row.program and row.program.textures or {}) == 0 then
              fail(("dex %03d callback %08X has no cached textures"):format(dex, row.descriptor or 0))
            end
            if textureHandlers[row.descriptor] and not callbackConsumers[row.commandOffset] then
              -- A callback may be deliberately superseded by another site
              -- on the same node before that node emits geometry (Muk has
              -- one such three-layer material sequence). Require a sibling
              -- consumer rather than silently accepting an orphan.
              local sibling = false
              for _, candidate in ipairs(extension.records) do
                if candidate ~= row and candidate.descriptor == row.descriptor
                    and candidate.bone == row.bone
                    and callbackConsumers[candidate.commandOffset] then
                  sibling = true
                  break
                end
              end
              if not sibling then
                fail(("dex %03d callback %08X has no consuming primitive"):format(dex, row.descriptor or 0))
              end
            end
            if row.family == "render-time-geometry-pipeline" then
              phase5Callbacks = phase5Callbacks + 1
              local resolved = phase5State.renderTimeResolvedBySite
                and phase5State.renderTimeResolvedBySite[row.commandOffset]
              if resolved then
                phase5Resolved = phase5Resolved + 1
              else
                fail(("dex %03d phase-5 callback %08X has no runtime texture/material consumer")
                  :format(dex, row.descriptor or 0))
              end
              local target = targetPhase5[dex]
              if target then
                target.total = target.total + 1
                if resolved and resolved.texture then
                  target.textures = target.textures + 1
                  local texture = model.textures and model.textures[resolved.texture]
                  local rgba = texture and texture.rgba
                  if type(rgba) == "string" and rgba:find("[^\255]", 1) then
                    target.nonWhite = target.nonWhite + 1
                  end
                end
                if resolved and resolved.material then target.materials = target.materials + 1 end
              end
            end
            if row.descriptor == 0x81000048 and callbackConsumers[row.commandOffset] then
              materialFxCallbacks = materialFxCallbacks + 1
              local set = materialState.textureSetBySite
                and materialState.textureSetBySite[row.commandOffset]
              local callbackMaterial = materialState.materialBySite
                and materialState.materialBySite[row.commandOffset]
              local first = row.argOffset and u32be(runtimeDecoded, row.argOffset)
              local second = row.argOffset and u32be(runtimeDecoded, row.argOffset + 4)
              local expectedTextures = first == second and 1 or 2
              local payloadComplete = #(row.program and row.program.textures or {})
                == expectedTextures
              if not payloadComplete then
                local key = ("%03d:%08X:%08X"):format(dex, first or 0, second or 0)
                if not reportedMaterialPayload[key] then
                  reportedMaterialPayload[key] = true
                  fail(("dex %03d slime callbacks cache %d/%d ROM texture payloads for %08X/%08X")
                    :format(dex, #(row.program and row.program.textures or {}),
                      expectedTextures, first or 0, second or 0))
                end
              end
              if payloadComplete and set and set[1] and set[2] and set.scroll
                  and set.wrap == "repeat" and set.combineMode == "lerp-then-shade"
                  and set.combine and set.combine[1] == 0x262A04
                  and set.combine[2] == 0x1F1893FF
                  and set.tileOrigins and set.tileOrigins[1][1] == 4059
                  and set.tileOrigins[1][2] == 37
                  and set.tileOrigins[2][1] == 37
                  and set.tileOrigins[2][2] == 74
                  and callbackMaterial and callbackMaterial.primitiveColor
                  and callbackMaterial.primitiveColor[1] == 1
                  and callbackMaterial.environmentColor
                  and callbackMaterial.environmentColor[4] == 1
                  and callbackMaterial.combine and callbackMaterial.combine[1] == 0
                  and callbackMaterial.combine[2] == 0 then
                materialFxResolved = materialFxResolved + 1
              else
                local key = ("%03d:%08X:%08X"):format(dex, first or 0, second or 0)
                if not reportedMaterialRoute[key] then
                  reportedMaterialRoute[key] = true
                  fail(("dex %03d slime family has no complete ROM two-layer material FX route for %08X/%08X")
                    :format(dex, first or 0, second or 0))
                end
              end
            end
          end
          callbackTextures = callbackTextures + #(extension.render and extension.render.handlerTextures or {})
          local offsets = extension.render and extension.render.primitiveMaterials or {}
          for _, offset in ipairs(offsets) do
            if offset then
              materials = materials + 1
              local state, materialErr = Materials.parse(extension, offset)
              if not state then
                fail(("dex %03d material 0x%X: %s"):format(dex, offset, tostring(materialErr)))
              else
                if not state.complete then
                  fail(("dex %03d material 0x%X has no display-list terminator"):format(dex, offset))
                end
                for op in pairs(state.unsupported) do
                  fail(("dex %03d material 0x%X unsupported opcode %02X"):format(dex, offset, op))
                end
              end
            end
          end
        end
      end
    end
  end
end

local descriptorCount = 0
for _ in pairs(descriptors) do descriptorCount = descriptorCount + 1 end
if models ~= 251 then fail(("decoded models: %d, expected 251"):format(models)) end
if descriptorCount ~= 13 then fail(("descriptors: %d, expected 13"):format(descriptorCount)) end
if callbacks ~= 559 then fail(("callbacks: %d, expected 559"):format(callbacks)) end
if targetPhase5[159].total ~= 0 then
  fail(("dex 159 phase-5 callbacks: %d, expected 0"):format(targetPhase5[159].total))
end
local misdreavus = targetPhase5[200]
if misdreavus.total ~= 6 or misdreavus.textures ~= 4 or misdreavus.materials ~= 2
    or misdreavus.nonWhite ~= 4 then
  fail(("dex 200 phase-5 routes: total=%d textures=%d materials=%d nonWhite=%d expected 6/4/2/4")
    :format(misdreavus.total, misdreavus.textures, misdreavus.materials,
      misdreavus.nonWhite))
end

print(("render parity audit: models=%d descriptors=%d callbacks=%d materials=%d callbackTextures=%d phase5=%d/%d materialFx=%d/%d failures=%d")
  :format(models, descriptorCount, callbacks, materials, callbackTextures,
    phase5Resolved, phase5Callbacks, materialFxResolved, materialFxCallbacks,
    #failures))
for i = 1, math.min(#failures, 80) do print("FAIL " .. failures[i]) end
if #failures > 80 then print(("... %d more"):format(#failures - 80)) end
if #failures > 0 then os.exit(1) end
