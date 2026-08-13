package.path = "./?.lua;./?/init.lua;" .. package.path

local Layout = require("mods.STADIUM2_IMPORTER.lib.layout")
local Rom = require("mods.STADIUM2_IMPORTER.lib.rom")
local Extract = require("mods.STADIUM2_IMPORTER.lib.extract")
local Fragment = require("mods.STADIUM2_IMPORTER.lib.fragment")
local Parity = require("mods.STADIUM2_IMPORTER.lib.model_parity")

local path = os.getenv("STADIUM2_ROM")
local speciesText = os.getenv("STADIUM2_PARITY_SPECIES")
local reportOnly, limit = false, 120
for _, value in ipairs(arg or {}) do
  if value == "--report" then reportOnly = true
  elseif value:match("^%-%-species=") then speciesText = value:match("=(.*)$")
  elseif value:match("^%-%-limit=") then limit = tonumber(value:match("=(.*)$")) or limit
  elseif value:sub(1, 2) ~= "--" and not path then path = value end
end
if not path or path == "" then
  io.stderr:write("usage: STADIUM2_ROM=/path/to/stadium2.z64 lua mods/STADIUM2_IMPORTER/tests/stadium2_model_parity_audit.lua [--species=200,181] [--report]\n")
  os.exit(2)
end

local selected = {}
if speciesText and speciesText ~= "" then
  for token in speciesText:gmatch("[^,%s]+") do
    local dex = tonumber(token)
    if dex and dex >= 1 and dex <= 251 then selected[dex] = true end
  end
end
local function wanted(dex) return next(selected) == nil or selected[dex] end

local file = assert(io.open(path, "rb"))
local data = assert(Rom.normalise(file:read("*a")))
file:close()
local archive = assert(Rom.archiveAt(data, Layout.MODEL_TABLE_START))
local reports = {}

for dex = 1, 251 do
  if wanted(dex) then
    local record = archive.records[dex + 1]
    local blob = record and Rom.recordBytes(data, record)
    local decoded, decodeErr = blob and Rom.decompress(blob)
    if not decoded then
      reports[#reports + 1] = {
        species = dex,
        issues = {{ species = dex, severity = "error", code = "MODEL_DECOMPRESS_FAILED",
          message = tostring(decodeErr) }},
        counts = { error = 1, warning = 0 }, rules = { MODEL_DECOMPRESS_FAILED = 1 }, families = {},
      }
    else
      local info, infoErr = Extract.fragmentInfo(decoded)
      if not info then
        reports[#reports + 1] = {
          species = dex,
          issues = {{ species = dex, severity = "error", code = "FRAGMENT_INFO_FAILED",
            message = tostring(infoErr) }},
          counts = { error = 1, warning = 0 }, rules = { FRAGMENT_INFO_FAILED = 1 }, families = {},
        }
      else
        local runtimeDecoded = Extract.runtimeFragmentForSpecies(data, dex, decoded)
        Fragment.setBase(info.sourceBase)
        local model, modelErr = Fragment.extract(runtimeDecoded, ("dex_%03d"):format(dex))
        if model then
          local anims, aux, animationErrors = Extract.animationBankForSpecies(data, dex, model.bones)
          if anims and #anims > 0 then model.anims = anims end
          if aux and #aux > 0 then model.auxAnims = aux end
          model.animationAuditErrors = animationErrors
          reports[#reports + 1] = Parity.auditModel(model, runtimeDecoded, info.sourceBase, { species = dex })
        else
          reports[#reports + 1] = {
            species = dex,
            issues = {{ species = dex, severity = "error", code = "MODEL_EXTRACT_FAILED",
              message = tostring(modelErr) }},
            counts = { error = 1, warning = 0 }, rules = { MODEL_EXTRACT_FAILED = 1 }, families = {},
          }
        end
      end
    end
  end
end

local total = Parity.merge(reports)
local ruleRows = {}
for code, n in pairs(total.rules) do ruleRows[#ruleRows + 1] = { code, n } end
table.sort(ruleRows, function(a, b) return a[1] < b[1] end)
local familyRows = {}
for descriptor, n in pairs(total.families) do familyRows[#familyRows + 1] = { descriptor, n } end
table.sort(familyRows, function(a, b) return a[1] < b[1] end)

print(("model parity audit: species=%d errors=%d warnings=%d issues=%d")
  :format(#reports, total.counts.error or 0, total.counts.warning or 0, #total.issues))
print(("texture parity: payloads=%d referenced=%d bytes=%d texturedPrimitives=%d neutralPrimitives=%d callbackPrimitives=%d")
  :format(total.metrics.textures or 0, total.metrics.referencedTextures or 0,
    total.metrics.textureBytes or 0, total.metrics.texturedPrimitives or 0,
    total.metrics.untexturedPrimitives or 0,
    total.metrics.callbackTexturePrimitives or 0))
print(("reflection parity: callbacks=%d primitives=%d")
  :format(total.metrics.textureGenCallbacks or 0,
    total.metrics.textureGenPrimitives or 0))
for _, row in ipairs(ruleRows) do print(("RULE %-44s %d"):format(row[1], row[2])) end
for _, row in ipairs(familyRows) do print(("FAMILY %08X callbacks=%d"):format(row[1], row[2])) end
for i = 1, math.min(#total.issues, limit) do
  local row = total.issues[i]
  print(("%s dex=%03d %-44s %s"):format(row.severity:upper(), row.species, row.code, row.message))
end
if #total.issues > limit then print(("... %d more issues (use --limit=N)"):format(#total.issues - limit)) end
if (total.counts.error or 0) > 0 and not reportOnly then os.exit(1) end
