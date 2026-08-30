-- ROM-only probe for locating Pokemon Stadium 2 battle-stage assets.
-- Run from the gen1recomp root:
--   luajit mods/STADIUM2_IMPORTER/tools/stadium2_arena_probe.lua ROM.z64

local Rom = require("mods.STADIUM2_IMPORTER.lib.rom")
local Fragment = require("mods.STADIUM2_IMPORTER.lib.fragment")

local path = (arg and arg[1]) or os.getenv("STADIUM2_ROM")
assert(path, "usage: stadium2_arena_probe.lua <stadium2.z64>")

local file = assert(io.open(path, "rb"))
local raw = assert(file:read("*a"))
file:close()
local rom, order = assert(Rom.normalise(raw))
assert(#rom == Rom.SIZE, ("wrong ROM size: 0x%X"):format(#rom))

local function signature(bytes)
  if not bytes or #bytes == 0 then return "empty" end
  if bytes:sub(1, 8) == "PERS-SZP" then
    local decoded, err = Rom.decompress(bytes)
    if not decoded then return "PERS-SZP:error:" .. tostring(err) end
    if decoded:sub(9, 16) == "FRAGMENT" then
      return ("PERS-SZP>FRAGMENT:0x%X"):format(#decoded)
    end
    local nested = Rom.archiveAt(decoded, 0)
    if nested then
      return ("PERS-SZP>archive:%d:0x%X"):format(nested.count, #decoded)
    end
    return ("PERS-SZP>raw:0x%X:%s"):format(#decoded,
      decoded:sub(1, 16):gsub("[^%g ]", "."))
  end
  if bytes:sub(9, 16) == "FRAGMENT" then
    return ("FRAGMENT:0x%X"):format(#bytes)
  end
  local nested = Rom.archiveAt(bytes, 0)
  if nested then return ("archive:%d:0x%X"):format(nested.count, #bytes) end
  return ("raw:0x%X:%s"):format(#bytes,
    bytes:sub(1, 16):gsub("[^%g ]", "."))
end

local archives = Rom.scanArchives(rom, Rom.ASSET_START,
  Rom.MODEL_TABLE_START - 0x10, 16384)
print(("ROM=%s order=%s archives=%d range=0x%X..0x%X"):format(
  path, order, #archives, Rom.ASSET_START, Rom.MODEL_TABLE_START))

for _, archive in ipairs(archives) do
  local counts = {}
  local samples = {}
  for _, record in ipairs(archive.records) do
    local sig = signature(Rom.recordBytes(rom, record))
    counts[sig] = (counts[sig] or 0) + 1
    if #samples < 4 then samples[#samples + 1] = sig end
  end
  local classes = {}
  for sig, count in pairs(counts) do
    classes[#classes + 1] = count .. "x " .. sig
  end
  table.sort(classes)
  print(("0x%08X total=0x%X count=%d :: %s"):format(
    archive.offset, archive.total, archive.count, table.concat(classes, "; ")))
end

local stadium = assert(Rom.archiveAt(rom, 0x1638000),
  "missing Stadium model archive at 0x1638000")
local dumpDir = os.getenv("STADIUM2_ARENA_PROBE_DUMP")
if dumpDir then
  assert(os.execute(("mkdir -p %q"):format(dumpDir)) == 0,
    "could not create probe dump directory")
end
print(("STADIUM_MODELS offset=0x%X total=0x%X count=%d"):format(
  stadium.offset, stadium.total, stadium.count))
local stageCommands = {}
local function scanLayout(data, root)
  local seen = {}
  local function u32(offset)
    local a,b,c,d = data:byte(offset + 1, offset + 4)
    return d and ((a * 256 + b) * 256 + c) * 256 + d or nil
  end
  local function walk(offset, depth)
    if depth > 64 then return end
    while offset and offset >= 0 and offset < #data and not seen[offset] do
      seen[offset] = true
      local command = data:byte(offset + 1)
      local size = Fragment.CMD_SIZES[command]
      if not size then return end
      stageCommands[command] = (stageCommands[command] or 0) + 1
      if command == 0x01 or command == 0x04 then return end
      if command == 0x00 or command == 0x03 then
        local pointer = u32(offset + 4)
        walk(pointer and pointer - 0x8FF00000, depth + 1)
      elseif command == 0x02 then
        local pointer = u32(offset + 4)
        offset = pointer and pointer - 0x8FF00000 or nil
        size = nil
      end
      if size then offset = offset + size end
    end
  end
  walk(root, 0)
end
for _, record in ipairs(stadium.records) do
  local packed = assert(Rom.recordBytes(rom, record))
  local decoded, decodeErr = Rom.decompress(packed)
  if not decoded then
    print(("  record=%02d rom=0x%X packed=0x%X ERROR=%s"):format(
      record.index, record.start, record.size, tostring(decodeErr)))
  else
    if dumpDir then
      local output = assert(io.open(("%s/arena_%02d.fragment.bin"):format(
        dumpDir, record.index), "wb"))
      assert(output:write(decoded))
      output:close()
    end
    local ok, model, modelErr = pcall(Fragment.extractStage, decoded,
      ("stadium_%02d"):format(record.index), record.index)
    local stageRoot = Fragment.stageRoot(decoded, ("stadium_%02d"):format(record.index))
    if stageRoot then scanLayout(decoded, stageRoot) end
    if ok and model then
      print(("  record=%02d rom=0x%X packed=0x%X decoded=0x%X id=%s bones=%d prims=%d textures=%d anims=%d warnings=%d"):format(
        record.index, record.start, record.size, #decoded,
        tostring(model.species), #(model.bones or {}), #(model.prims or {}),
        #(model.textures or {}), #(model.anims or {}), #(model.warnings or {})))
    else
      print(("  record=%02d rom=0x%X packed=0x%X decoded=0x%X EXTRACT_ERROR=%s"):format(
        record.index, record.start, record.size, #decoded,
        tostring(ok and modelErr or model)))
    end
  end
end
local commandText = {}
for command, count in pairs(stageCommands) do
  commandText[#commandText + 1] = ("0x%02X=%d"):format(command, count)
end
table.sort(commandText)
print("STADIUM_GEO_COMMANDS " .. table.concat(commandText, " "))
