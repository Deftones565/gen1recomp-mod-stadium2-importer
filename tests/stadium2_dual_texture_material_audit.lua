package.path = "./?.lua;./?/init.lua;" .. package.path

local Layout = require("mods.STADIUM2_IMPORTER.lib.layout")
local Rom = require("mods.STADIUM2_IMPORTER.lib.rom")
local Extract = require("mods.STADIUM2_IMPORTER.lib.extract")
local Fragment = require("mods.STADIUM2_IMPORTER.lib.fragment")
local Fragment26 = require("mods.STADIUM2_IMPORTER.lib.fragment26")
local Handlers = require("mods.STADIUM2_IMPORTER.lib.model_handlers")
local DualTexture = require("mods.STADIUM2_IMPORTER.lib.render_callbacks.dual_texture_material")

local path = os.getenv("STADIUM2_ROM") or arg[1]
if not path or path == "" then
  io.stderr:write("usage: STADIUM2_ROM=/path/to/stadium2.z64 lua "
    .. "mods/STADIUM2_IMPORTER/tests/stadium2_dual_texture_material_audit.lua\n")
  os.exit(2)
end

local failures = {}
local function fail(message) failures[#failures + 1] = message end
local function check(value, message) if not value then fail(message) end end
local function u32(data, offset)
  local a, b, c, d = data:byte(offset + 1, offset + 4)
  return d and ((a * 256 + b) * 256 + c) * 256 + d or nil
end
local function wordAt(data, address)
  local offset = Fragment26.romOffset(address)
  return offset and u32(data, offset) or nil
end
local function close(a, b)
  return type(a) == "number" and type(b) == "number" and math.abs(a - b) < 0.0000001
end

local file = assert(io.open(path, "rb"))
local data = assert(Rom.normalise(file:read("*a")))
file:close()

-- These are semantic landmarks, not merely a callback-address check. They
-- lock allocation size, both argument loads, the two independent scroll
-- calculations, and the fixed two-cycle material used by the ROM builder.
local romWords = {
  [0x81005DCC] = 0x240400F0, -- allocate 0xF0 bytes
  [0x81005DE4] = 0x0C4016D4, -- jal func_81005B50
  [0x81005B74] = 0x95084904, -- global display-frame counter
  [0x81005BA4] = 0x8DF80000, -- arg[0]
  [0x81005BFC] = 0x00084023, -- negate global frame
  [0x81005C00] = 0x00084100, -- tile 0: frame * 16
  [0x81005CC4] = 0x8F2F0004, -- arg[1]
  [0x81005D40] = 0x0008C0C3, -- tile 1: twice tile-0 rate
  [0x810061B0] = 0xE7000000,
  [0x810061B8] = 0xFC262A04,
  [0x810061BC] = 0x1F1893FF,
  [0x810061C0] = 0xFB000000,
  [0x810061C4] = 0xFFFFFF64,
  [0x810061C8] = 0xDF000000,
}
for address, expected in pairs(romWords) do
  local actual = wordAt(data, address)
  check(actual == expected, ("ROM word 0x%08X=%08X expected %08X")
    :format(address, actual or 0, expected))
end
local descriptor = assert(Fragment26.descriptor(data, DualTexture.DESCRIPTOR))
check(descriptor.target == DualTexture.TARGET, "descriptor target differs from shared contract")
check(DualTexture.BUILDER == 0x81005B50 and DualTexture.MATERIAL == 0x810061B0
    and DualTexture.ALLOCATION_BYTES == 0xF0,
  "shared callback constants differ from ROM landmarks")
check(DualTexture.COMBINE[1] == 0x262A04
    and DualTexture.COMBINE[2] == 0x1F1893FF
    and close(DualTexture.ENVIRONMENT_ALPHA, 100 / 255),
  "shared two-cycle combiner differs from ROM material")

local reference = DualTexture.state(37)
check(reference.tileOrigins[1][1] == 4059 and reference.tileOrigins[1][2] == 37
    and reference.tileOrigins[2][1] == 37 and reference.tileOrigins[2][2] == 74,
  "shared tile-origin math differs from func_81005B50")

local archive = assert(Rom.archiveAt(data, Layout.MODEL_TABLE_START))
local callbacks, consumers, bodyPrims, decalPrims, routes = 0, 0, 0, 0, 0
local missingPayloads = {}
local missingCachePairs = {}
local targets = {
  [88] = { callbacks = 0, consumers = 0, body = 0, decals = 0, textureKinds = {} },
  [89] = { callbacks = 0, consumers = 0, body = 0, decals = 0, textureKinds = {} },
}

for dex = 1, 251 do
  local decoded = assert(Rom.decompress(assert(Rom.recordBytes(data, archive.records[dex + 1]))))
  local info = assert(Extract.fragmentInfo(decoded))
  local runtimeDecoded = Extract.runtimeFragmentForSpecies(data, dex, decoded)
  Fragment.setBase(info.sourceBase)
  local model = assert(Fragment.extract(runtimeDecoded, ("dual-texture-%03d"):format(dex)))
  local records = Handlers.compile(model.fx, runtimeDecoded, info.sourceBase)
  local extension = assert(Handlers.readExtension("DSM4audit"
    .. Handlers.packExtension(records, info.sourceBase, runtimeDecoded,
      { prims = model.prims, handlerTextures = model.handlerTextures })))
  local state = select(1, Handlers.runExtension(extension, 2,
    { species = dex, materialFrame = 37, sourceFrame = 3 }, {})) or {}
  local primsBySite = {}
  for _, prim in ipairs(model.prims or {}) do
    if prim.callbackDescriptor == DualTexture.DESCRIPTOR then
      primsBySite[prim.callbackOffset] = true
      if DualTexture.ownsPrimitive(prim) then bodyPrims = bodyPrims + 1
      else decalPrims = decalPrims + 1 end
      local target = targets[dex]
      if target then
        if DualTexture.ownsPrimitive(prim) then target.body = target.body + 1
        else target.decals = target.decals + 1 end
      end
    end
  end
  for _, record in ipairs(extension.records or {}) do
    if record.descriptor == DualTexture.DESCRIPTOR then
      callbacks = callbacks + 1
      local target = targets[dex]
      if target then target.callbacks = target.callbacks + 1 end
      local arg0, arg1 = u32(runtimeDecoded, record.argOffset), u32(runtimeDecoded, record.argOffset + 4)
      check(arg0 ~= nil and arg1 ~= nil,
        ("dex %03d callback 0x%X lacks two ROM texture pointers")
          :format(dex, record.commandOffset or 0))
      local uniquePointers = arg0 == arg1 and 1 or 2
      for _, pointer in ipairs({ arg0, arg1 }) do
        local offset = pointer and pointer - info.sourceBase or -1
        if offset < 0 or offset + 0x800 > #runtimeDecoded then
          local key = ("%03d:%08X"):format(dex, pointer or 0)
          if not missingPayloads[key] then
            missingPayloads[key] = true
            fail(("dex %03d ROM texture %08X needs [0x%X,0x%X), fragment ends at 0x%X; importer is missing 0x%X source bytes")
              :format(dex, pointer or 0, math.max(0, offset), math.max(0, offset) + 0x800,
                #runtimeDecoded, math.max(0, offset + 0x800 - #runtimeDecoded)))
          end
        end
      end
      if #(record.program and record.program.textures or {}) ~= uniquePointers then
        local key = ("%03d:%08X:%08X"):format(dex, arg0 or 0, arg1 or 0)
        if not missingCachePairs[key] then
          missingCachePairs[key] = true
          fail(("dex %03d callbacks cache %d textures for ROM pair %08X/%08X, which requires %d distinct payloads")
            :format(dex, #(record.program and record.program.textures or {}),
              arg0 or 0, arg1 or 0, uniquePointers))
        end
      end
      if target then target.textureKinds[uniquePointers] = true end
      if primsBySite[record.commandOffset] then
        consumers = consumers + 1
        if target then target.consumers = target.consumers + 1 end
        local set = state.textureSetBySite and state.textureSetBySite[record.commandOffset]
        if set then routes = routes + 1 end
        check(set and set[1] and set[2],
          ("dex %03d callback 0x%X lacks both runtime texture tiles")
            :format(dex, record.commandOffset or 0))
        check(set and set.wrap == "repeat" and set.combineMode == "lerp-then-shade"
            and set.combine and set.combine[1] == 0x262A04
            and set.combine[2] == 0x1F1893FF and close(set.mix, 100 / 255),
          ("dex %03d callback 0x%X lost ROM sampler/combiner state")
            :format(dex, record.commandOffset or 0))
        local material = state.materialBySite and state.materialBySite[record.commandOffset]
        check(material and material.primitiveColor and material.primitiveColor[1] == 1
            and material.environmentColor and material.environmentColor[4] == 1
            and material.combine and material.combine[1] == 0 and material.combine[2] == 0,
          ("dex %03d callback 0x%X incorrectly inherits authored material state")
            :format(dex, record.commandOffset or 0))
        check(set and set.tileOrigins
            and set.tileOrigins[1][1] == 4059 and set.tileOrigins[1][2] == 37
            and set.tileOrigins[2][1] == 37 and set.tileOrigins[2][2] == 74,
          ("dex %03d callback 0x%X uses incorrect ROM scroll math")
            :format(dex, record.commandOffset or 0))
      end
    end
  end
end

check(callbacks == 36 and consumers == 35 and routes == 35,
  ("family coverage callbacks/consumers/routes=%d/%d/%d expected 36/35/35")
    :format(callbacks, consumers, routes))
check(targets[88].callbacks == 16 and targets[88].consumers == 16
    and targets[88].body == 21 and targets[88].decals == 1
    and targets[88].textureKinds[2],
  "Grimer callback topology or distinct-pointer dual-tile contract changed")
check(targets[89].callbacks == 20 and targets[89].consumers == 19
    and targets[89].body == 23 and targets[89].decals == 1
    and targets[89].textureKinds[2],
  "Muk callback topology or distinct-image dual-tile contract changed")

print(("dual-texture material audit: callbacks=%d consumers=%d routes=%d body=%d decals=%d failures=%d")
  :format(callbacks, consumers, routes, bodyPrims, decalPrims, #failures))
for _, message in ipairs(failures) do print("FAIL " .. message) end
if #failures > 0 then os.exit(1) end
