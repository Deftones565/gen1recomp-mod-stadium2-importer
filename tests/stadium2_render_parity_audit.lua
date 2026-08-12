package.path = "./?.lua;./?/init.lua;" .. package.path

local Layout = require("mods.STADIUM2_IMPORTER.lib.layout")
local Rom = require("mods.STADIUM2_IMPORTER.lib.rom")
local Extract = require("mods.STADIUM2_IMPORTER.lib.extract")
local Fragment = require("mods.STADIUM2_IMPORTER.lib.fragment")
local Handlers = require("mods.STADIUM2_IMPORTER.lib.model_handlers")
local Materials = require("mods.STADIUM2_IMPORTER.lib.materials")

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
local textureHandlers = { [0x81000038] = true, [0x81000048] = true, [0x81000050] = true,
  [0x81000068] = true, [0x81000070] = true }
local failures = {}
local function fail(text) failures[#failures + 1] = text end

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
      Fragment.setBase(info.sourceBase)
      local model, modelErr = Fragment.extract(decoded, ("dex_%03d"):format(dex))
      if not model then
        fail(("dex %03d extract: %s"):format(dex, tostring(modelErr)))
      else
        models = models + 1
        local callbackConsumers = {}
        for _, prim in ipairs(model.prims or {}) do
          if prim.callbackOffset then callbackConsumers[prim.callbackOffset] = true end
        end
        local records = Handlers.compile(model.fx, decoded, info.sourceBase)
        callbacks = callbacks + #records
        for _, row in ipairs(records) do descriptors[row.descriptor] = true end
        local extension = Handlers.readExtension("DSM3audit"
          .. Handlers.packExtension(records, info.sourceBase, decoded,
            { prims = model.prims, handlerTextures = model.handlerTextures }))
        if not extension or extension.version ~= 4 then
          fail(("dex %03d S2HX v4 roundtrip"):format(dex))
        else
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
if callbacks ~= 551 then fail(("callbacks: %d, expected 551"):format(callbacks)) end

print(("render parity audit: models=%d descriptors=%d callbacks=%d materials=%d callbackTextures=%d failures=%d")
  :format(models, descriptorCount, callbacks, materials, callbackTextures, #failures))
for i = 1, math.min(#failures, 80) do print("FAIL " .. failures[i]) end
if #failures > 80 then print(("... %d more"):format(#failures - 80)) end
if #failures > 0 then os.exit(1) end
