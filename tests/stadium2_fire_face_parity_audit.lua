package.path = "./?.lua;./?/init.lua;" .. package.path

local Extract = require("mods.STADIUM2_IMPORTER.lib.extract")
local Fragment = require("mods.STADIUM2_IMPORTER.lib.fragment")
local Fx = require("mods.STADIUM2_IMPORTER.lib.fx")
local Flame = require("mods.STADIUM2_IMPORTER.lib.render_callbacks.flame")
local Handlers = require("mods.STADIUM2_IMPORTER.lib.model_handlers")
local Layout = require("mods.STADIUM2_IMPORTER.lib.layout")
local Rom = require("mods.STADIUM2_IMPORTER.lib.rom")

local path = os.getenv("STADIUM2_ROM") or arg[1]
if not path or path == "" then
  io.stderr:write("usage: STADIUM2_ROM=/path/to/stadium2.z64 lua "
    .. "mods/STADIUM2_IMPORTER/tests/stadium2_fire_face_parity_audit.lua\n")
  os.exit(2)
end

local failures, checks = {}, 0
local function check(value, message)
  checks = checks + 1
  if not value then failures[#failures + 1] = message end
end
local function same(a, b)
  if #a ~= #b then return false end
  for i = 1, #a do
    if math.abs((a[i] or 0) - (b[i] or 0)) > 0.0001 then return false end
  end
  return true
end

local file = assert(io.open(path, "rb"))
local data = assert(Rom.normalise(file:read("*a")))
file:close()
local archive = assert(Rom.archiveAt(data, Layout.MODEL_TABLE_START))

-- Main-code VROM is VRAM-0x7FFFF400 in this ROM. These landmarks ensure the
-- reusable contract remains tied to the actual shared object instead of a
-- visually tuned stand-in.
local vertexRom = Flame.ROM.vertexAddress - 0x7FFFF400
local dlRom = Flame.ROM.displayListAddress - 0x7FFFF400
check(data:sub(vertexRom + 1, vertexRom + 16)
    == string.char(0xFF,0xCE,0x00,0xC8,0,0,0,0,0,0,0,0,0xFF,0xFF,0,0xFF),
  "shared flame Vtx landmark at 0x8009F228 does not match the ROM")
check(data:sub(dlRom + 1, dlRom + 8)
    == string.char(0x01,0x00,0xA0,0x14,0x0E,0,0,0),
  "shared flame display-list landmark at 0x8009F2E0 does not match the ROM")

local function extract(dex)
  local decoded = assert(Rom.decompress(assert(Rom.recordBytes(data,
    archive.records[dex + 1]))))
  local info = assert(Extract.fragmentInfo(decoded))
  Fragment.setBase(info.sourceBase)
  local runtime = Extract.runtimeFragmentForSpecies(data, dex, decoded)
  return assert(Fragment.extract(runtime, ("fire-face-%03d"):format(dex))),
    runtime, info.sourceBase
end

local sharedFrames
for _, dex in ipairs({4, 5, 6, 146}) do
  local model, runtime, sourceBase = extract(dex)
  local tail = {}
  for _, prim in ipairs(model.prims or {}) do
    if prim.effect == "fire" and prim.callbackDescriptor == 0x81000038 then
      tail[#tail + 1] = prim
    end
  end
  local expected = dex == 146 and 3 or 1
  check(#tail == expected,
      ("dex %03d has %d/%d generated 0x81000038 flame cards")
      :format(dex, #tail, expected))
  local records = Handlers.compile(model.fx, runtime, sourceBase)
  local extension = assert(Handlers.readExtension("DSM4flame-audit"
    .. Handlers.packExtension(records, sourceBase, runtime,
      { prims = model.prims, handlerTextures = model.handlerTextures })))
  local familyCount = 0
  for _, record in ipairs(extension.records or {}) do
    if record.descriptor == Flame.DESCRIPTOR then
      familyCount = familyCount + 1
      check(record.family == "flame-object-renderer"
          and record.program and record.program.complete,
        ("dex %03d flame callback did not survive as a complete shared family")
          :format(dex))
    end
  end
  -- Moltres traverses the same command site on three attachment bones; the
  -- portable program is site-owned once while its exact mesh is instantiated
  -- for each traversal.
  check(familyCount == 1,
    ("dex %03d cached %d/1 shared flame callback programs")
      :format(dex, familyCount))
  local state = select(1, Handlers.runExtension(extension, 2,
    { species = dex, materialFrame = 7 }, {}))
  for _, prim in ipairs(tail) do
    local site = prim.callbackOffset
    check(state.textureBySite[site] ~= nil and state.materialBySite[site]
        and state.materialBySite[site].intensity == true,
      ("dex %03d flame site %s lost runtime texture/material state")
        :format(dex, tostring(site)))
  end
  for _, prim in ipairs(tail) do
    local expectedMesh = Flame.geometry(prim.skin and prim.skin[1] or -1)
    check(prim.nverts == 10 and prim.nidx == 24
        and same(prim.pos or {}, expectedMesh.pos)
        and same(prim.uv or {}, expectedMesh.uv)
        and same(prim.idx or {}, expectedMesh.idx),
      ("dex %03d does not use the shared ROM flame mesh"):format(dex))
    check(prim.vertexSemantics == "color" and same(prim.color or {}, expectedMesh.color),
      ("dex %03d lost the flame object's authored vertex colors"):format(dex))
    check(prim.color and prim.color[1] == 255 and prim.color[3] == 0
        and prim.color[33] == 255 and prim.color[35] == 128,
      ("dex %03d flame colors are not raw N64 RGBA bytes"):format(dex))
    check(prim.blend == "add" and #(prim.fxFrames or {}) == 8,
      ("dex %03d flame lost additive eight-frame animation"):format(dex))
    local frames = {}
    for _, slot in ipairs(prim.fxFrames or {}) do
      local texture = model.textures and model.textures[slot + 1]
      frames[#frames + 1] = texture and Fx.crc32(texture.rgba) or -1
    end
    if not sharedFrames then sharedFrames = table.concat(frames, ",") end
    check(table.concat(frames, ",") == sharedFrames,
      ("dex %03d does not use the shared ROM flame frames"):format(dex))
  end
end

local charmanderMaterial = Flame.material(4, 7)
check(same(charmanderMaterial.primitiveColor, {1,1,1,1})
    and same(charmanderMaterial.environmentColor, {110/255,32/255,0,0}),
  "default flame material no longer matches func_80070A4C frame 7")
local moltresMaterial = Flame.material(146, 7)
check(same(moltresMaterial.primitiveColor, {1,1,1,200/255})
    and same(moltresMaterial.environmentColor, {1,32/255,0,0}),
  "Moltres flame material no longer matches func_80070A4C species branch")

local heracross = extract(214)
local phase5Missing, unownedMissing, inherited = 0, 0, 0
for _, prim in ipairs(heracross.prims or {}) do
  if prim.sourceTextureMissing then
    if prim.callbackDescriptor == 0x81000140 and prim.callbackOffset then
      phase5Missing = phase5Missing + 1
      if prim.nverts > 100 then inherited = inherited + 1 end
    else
      unownedMissing = unownedMissing + 1
    end
  end
end
check(phase5Missing == 8 and inherited == 1 and unownedMissing == 0,
  ("Heracross phase-5 texture ownership=%d inherited=%d unowned=%d expected 8/1/0")
    :format(phase5Missing, inherited, unownedMissing))

print(("fire/face parity audit: checks=%d failures=%d")
  :format(checks, #failures))
for _, message in ipairs(failures) do print("FAIL " .. message) end
if #failures > 0 then os.exit(1) end
