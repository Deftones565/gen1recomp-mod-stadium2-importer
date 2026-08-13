package.path = "./?.lua;./?/init.lua;" .. package.path

local Rom = require("mods.STADIUM2_IMPORTER.lib.rom")
local Extract = require("mods.STADIUM2_IMPORTER.lib.extract")
local Pack = require("mods.STADIUM2_IMPORTER.lib.pack")
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
local function parse(bytes, label)
  assert(type(bytes) == "string" and bytes:sub(1, 4) == "DSM4", label .. ": not DSM4")
  local model, err = Pack.parse(bytes)
  assert(model, label .. ": " .. tostring(err))
  for index, prim in ipairs(model.prims or {}) do
    assert(prim.geometryMode ~= nil, ("%s primitive %d lost geometry mode"):format(label,index))
    assert(prim.vertexSemantics == "normal" or prim.vertexSemantics == "color",
      ("%s primitive %d lost vertex semantics"):format(label,index))
  end
  if model.species == 208 then
    local reflected = 0
    for _, prim in ipairs(model.prims or {}) do
      if math.floor((prim.geometryMode or 0) / 0x40000) % 2 == 1 then
        reflected = reflected + 1
      end
    end
    assert(reflected == 4,
      ("%s Steelix reflection routes: %d, expected 4"):format(label, reflected))
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
  if steps > 200000 then error("DSM4 import audit exceeded step budget") end
end
assert(job.success, job.error)
assert(ordinary == 502, ("ordinary pack count %d, expected 502"):format(ordinary))
assert(special == 51, ("special pack count %d, expected 51"):format(special))
print(("DSM4 roundtrip audit: ordinary=%d special=%d steps=%d failures=0")
  :format(ordinary, special, steps))
