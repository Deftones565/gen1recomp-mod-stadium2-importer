package.path = "./?.lua;./?/init.lua;" .. package.path

local Layout = require("mods.STADIUM2_IMPORTER.lib.layout")
local Rom = require("mods.STADIUM2_IMPORTER.lib.rom")
local Extract = require("mods.STADIUM2_IMPORTER.lib.extract")
local Fragment = require("mods.STADIUM2_IMPORTER.lib.fragment")
local Fx = require("mods.STADIUM2_IMPORTER.lib.fx")
local Handlers = require("mods.STADIUM2_IMPORTER.lib.model_handlers")
local Fragment26 = require("mods.STADIUM2_IMPORTER.lib.fragment26")

local AUDIT_VERSION = "0.3.9-standalone-renderer"
local path = os.getenv("STADIUM2_ROM") or arg[1]
local outputPath = os.getenv("STADIUM2_FRAGMENT26_OUT") or os.getenv("STADIUM2_AUDIT_OUT")

if not path or path == "" then
  io.stderr:write("usage: STADIUM2_ROM=/path/to/stadium2.z64 luajit mods/STADIUM2_IMPORTER/tests/stadium2_fragment26_audit.lua\n")
  os.exit(2)
end

local lines = {}
local failures = 0

local function emit(text)
  text = tostring(text)
  lines[#lines + 1] = text
  print(text)
end

local function fail(text)
  failures = failures + 1
  emit("FAIL: " .. tostring(text))
end

local function readFile(name)
  local file, err = io.open(name, "rb")
  if not file then return nil, err end
  local bytes = file:read("*a")
  file:close()
  return bytes
end

local function hex32(value)
  if value == nil then return "-" end
  return ("0x%08X"):format(value % 0x100000000)
end

local function countSet(set)
  local n = 0
  for _ in pairs(set or {}) do n = n + 1 end
  return n
end

local function compactDexSet(set)
  local values = {}
  for dex in pairs(set or {}) do values[#values + 1] = dex end
  table.sort(values)
  if #values == 0 then return "-" end
  local out = {}
  local first, last = values[1], values[1]
  for i = 2, #values + 1 do
    local value = values[i]
    if value == last + 1 then
      last = value
    else
      if first == last then out[#out + 1] = ("%03d"):format(first)
      else out[#out + 1] = ("%03d-%03d"):format(first, last) end
      first, last = value, value
    end
  end
  return table.concat(out, ",")
end

local function compactPointerSet(set, limit)
  local values = {}
  for value in pairs(set or {}) do values[#values + 1] = value end
  table.sort(values)
  if #values == 0 then return "-" end
  limit = limit or 12
  local out = {}
  local shown = math.min(#values, limit)
  for i = 1, shown do out[#out + 1] = hex32(values[i]) end
  if #values > shown then out[#out + 1] = ("+%d more"):format(#values - shown) end
  return table.concat(out, ",")
end

local function phaseText(address)
  local phases = Fragment26.phaseList(address)
  if not phases then return "-" end
  local out = {}
  for i = 1, #phases do out[i] = tostring(phases[i]) end
  return table.concat(out, ",")
end

local function decodeRecord(data, record)
  local blob = Rom.recordBytes(data, record)
  if not blob then return nil, "record is outside ROM" end
  local ok, decoded, err = pcall(Rom.decompress, blob)
  if not ok then return nil, tostring(decoded) end
  if not decoded then return nil, tostring(err) end
  return decoded
end

local function classify(value)
  local kind, info = Fragment26.classifyWord(value)
  if kind == "fragment26-function" then
    if info.exact then return info.name end
    return ("%s+0x%X"):format(info.name, info.delta)
  end
  if kind == "fragment26-data" then return ("fragment26+0x%X"):format(info.offset) end
  if kind == "descriptor" then return "descriptor:" .. hex32(value) end
  if kind == "runtime" then return "runtime" end
  return kind
end

local raw, readErr = readFile(path)
if not raw then error(readErr, 0) end
local data, order = Rom.normalise(raw)
if not data then error(order, 0) end

emit("Stadium 2 fragment26 model-handler audit")
emit("audit version: " .. AUDIT_VERSION)
emit("ROM: " .. path)
emit("byte order: " .. tostring(order))
emit(("size: 0x%X"):format(#data))
emit("title: " .. tostring(Rom.title(data)))
emit(("fragment26 ROM: 0x%X..0x%X"):format(Fragment26.ROM_START, Fragment26.ROM_END))
emit(("fragment26 VRAM: 0x%X..0x%X"):format(Fragment26.VRAM_BASE, Fragment26.VRAM_END))
emit(("descriptor table: 0x%X..0x%X descriptorSize=0x%X"):format(Fragment26.TABLE_START, Fragment26.TABLE_END, Fragment26.DESCRIPTOR_SIZE))
emit(("code start: 0x%X"):format(Fragment26.CODE_START))

if #data ~= Layout.ROM_SIZE then fail(("wrong ROM size 0x%X"):format(#data)) end
if Rom.title(data):upper() ~= Layout.US_TITLE then fail("wrong ROM title") end

local archive = Rom.archiveAt(data, Layout.MODEL_TABLE_START)
if not archive then
  fail("model archive root is invalid")
else
  emit(("model archive: offset=0x%X records=%d size=0x%X"):format(archive.offset, archive.count, archive.total))
end

local handlers = {}
local decodedCount = 0
local speciesMatches = 0
local totalTraversals = 0
local uniqueCommands = 0

if archive then
  for dex = 1, 251 do
    local record = archive.records[dex + 1]
    if not record then
      fail(("dex=%03d missing model record %d"):format(dex, dex))
    else
      local decoded, decodeErr = decodeRecord(data, record)
      if not decoded then
        fail(("dex=%03d decode=%s"):format(dex, tostring(decodeErr)))
      else
        decodedCount = decodedCount + 1
        local species, info = Extract.fragmentSpecies(decoded)
        if species == dex then speciesMatches = speciesMatches + 1
        else fail(("dex=%03d fragmentSpecies=%s"):format(dex, tostring(species))) end
        if not info then
          fail(("dex=%03d no FRAGMENT root"):format(dex))
        else
          local fxInfo, fxErr = Fragment.inspectFx(decoded, ("model-%03d"):format(dex), info.sourceBase)
          if not fxInfo then
            fail(("dex=%03d handler scan=%s"):format(dex, tostring(fxErr)))
          else
            local physical = {}
            for _, node in ipairs(fxInfo.nodes or {}) do
              totalTraversals = totalTraversals + 1
              local handler = node.handler or node.callback
              if Fragment26.isDescriptor(handler) then
                local key = table.concat({ tostring(node.commandOffset), tostring(handler), tostring(node.argPointer) }, ":")
                local unique = not physical[key]
                if unique then
                  physical[key] = true
                  uniqueCommands = uniqueCommands + 1
                end
                local row = handlers[handler]
                if not row then
                  row = { commands = 0, traversals = 0, species = {}, args = {}, samples = {}, argPatterns = {} }
                  handlers[handler] = row
                end
                if unique then row.commands = row.commands + 1 end
                row.traversals = row.traversals + 1
                row.species[dex] = true
                if node.argPointer ~= nil then row.args[node.argPointer] = true end
                if node.argOffset ~= nil then
                  local argBlock = decoded:sub(node.argOffset + 1, math.min(#decoded, node.argOffset + 0x40))
                  local fingerprint = ("%08X:%X"):format(Fx.crc32(argBlock), #argBlock)
                  local pattern = row.argPatterns[fingerprint]
                  if not pattern then
                    pattern = { count = 0, species = {}, pointer = node.argPointer, offset = node.argOffset, head = Fx.hexBytes(argBlock, 64) }
                    row.argPatterns[fingerprint] = pattern
                  end
                  pattern.count = pattern.count + 1
                  pattern.species[dex] = true
                end
                if #row.samples < 8 then
                  row.samples[#row.samples + 1] = {
                    dex = dex,
                    commandOffset = node.commandOffset,
                    bone = node.bone,
                    boneId = node.boneId,
                    argPointer = node.argPointer,
                  }
                end
              end
            end
          end
        end
      end
    end
  end
end

local handlerAddresses = {}
for address in pairs(handlers) do handlerAddresses[#handlerAddresses + 1] = address end
table.sort(handlerAddresses)

emit(("model scan: decoded=%d speciesMatches=%d handlerTraversals=%d uniqueHandlerCommands=%d usedDescriptors=%d"):format(
  decodedCount, speciesMatches, totalTraversals, uniqueCommands, #handlerAddresses))

local functionMap = {}
emit("used fragment26 descriptors:")
for index, address in ipairs(handlerAddresses) do
  local row = handlers[address]
  local descriptor, descriptorErr = Fragment26.descriptor(data, address)
  if not descriptor then
    fail(("descriptor %s: %s"):format(hex32(address), tostring(descriptorErr)))
  else
    local targetInfo, targetErr = Fragment26.descriptorTarget(descriptor)
    local targetText = targetInfo and (targetInfo.name .. "@" .. hex32(targetInfo.start)) or ("unresolved:" .. tostring(targetErr))
    local semantic = Handlers.info(address)
    emit(("  descriptor[%02d] ptr=%s tableOff=0x%X rom=0x%X word0=%s word1=%s stub=%s target=%s phases=%s family=%s confidence=%s commands=%d traversals=%d species=%d dex=%s args=%s"):format(
      index, hex32(address), descriptor.offset, descriptor.romOffset,
      hex32(descriptor.word0), hex32(descriptor.word1),
      descriptor.jump and descriptor.jump.kind or "-", targetText, targetInfo and phaseText(targetInfo.start) or "-",
      semantic and semantic.family or "unknown", semantic and semantic.confidence or "unknown",
      row.commands, row.traversals, countSet(row.species), compactDexSet(row.species), compactPointerSet(row.args)))
    if targetInfo then
      local target = functionMap[targetInfo.start]
      if not target then
        target = { descriptors = {}, slots = {} }
        functionMap[targetInfo.start] = target
      end
      target.descriptors[address] = true
      target.slots[0] = true
    end
    for sampleIndex, sample in ipairs(row.samples) do
      emit(("    sample[%02d] dex=%03d cmd=0x%X bone=%s boneId=%s arg=%s"):format(
        sampleIndex, sample.dex, sample.commandOffset or 0,
        sample.bone ~= nil and tostring(sample.bone) or "-",
        sample.boneId ~= nil and tostring(sample.boneId) or "-",
        hex32(sample.argPointer)))
    end
    local patterns = {}
    for fingerprint, pattern in pairs(row.argPatterns or {}) do
      patterns[#patterns + 1] = { fingerprint = fingerprint, value = pattern }
    end
    table.sort(patterns, function(a, b)
      if a.value.count == b.value.count then return a.fingerprint < b.fingerprint end
      return a.value.count > b.value.count
    end)
    local patternShown = math.min(#patterns, 16)
    emit(("    argument patterns: %d"):format(#patterns))
    for patternIndex = 1, patternShown do
      local entry = patterns[patternIndex]
      local pattern = entry.value
      emit(("      argPattern[%02d] fingerprint=%s uses=%d species=%s ptr=%s off=0x%X head=%s"):format(
        patternIndex, entry.fingerprint, pattern.count, compactDexSet(pattern.species),
        hex32(pattern.pointer), pattern.offset or 0, pattern.head or ""))
    end
    if #patterns > patternShown then emit(("      ... %d more argument patterns"):format(#patterns - patternShown)) end
  end
end

local functionStarts = {}
for start in pairs(functionMap) do functionStarts[#functionStarts + 1] = start end
table.sort(functionStarts)

emit(("resolved descriptor target functions: %d"):format(#functionStarts))
local graph, graphErr = Fragment26.callGraph(data, functionStarts)
if not graph then
  fail("fragment26 call graph: " .. tostring(graphErr))
else
  local graphStarts = {}
  for functionStart in pairs(graph.functions) do graphStarts[#graphStarts + 1] = functionStart end
  table.sort(graphStarts, function(a, b)
    local da = graph.functions[a].depth or 0
    local db = graph.functions[b].depth or 0
    if da == db then return a < b end
    return da < db
  end)
  emit(("reachable fragment26 functions: %d"):format(#graphStarts))
  for index, functionStart in ipairs(graphStarts) do
    local row = graph.functions[functionStart]
    local info = row.info
    local descriptors = functionMap[functionStart] and functionMap[functionStart].descriptors or {}
    emit(("  function[%02d] depth=%d root=%s %s vram=%s rom=0x%X..0x%X size=0x%X fingerprint=%08X:%X phases=%s descriptors=%s directCalls=%d"):format(
      index, row.depth or 0, next(descriptors) and "yes" or "no", info.name, hex32(info.start),
      info.romStart, info.romEnd, #row.code, Fx.crc32(row.code), #row.code,
      phaseText(info.start), compactPointerSet(descriptors), #row.calls))
    emit("    head=" .. Fx.hexBytes(row.code, 96))
    emit("    words=" .. Fx.wordList(row.code, 48))
    local shown = math.min(#row.calls, 64)
    for callIndex = 1, shown do
      local call = row.calls[callIndex]
      if call.indirect then
        emit(("    call[%02d] at=%s+0x%X jalr"):format(callIndex, info.name, call.offset))
      else
        emit(("    call[%02d] at=%s+0x%X target=%s (%s)"):format(
          callIndex, info.name, call.offset, hex32(call.target), classify(call.target)))
      end
    end
    if #row.calls > shown then emit(("    ... %d more calls"):format(#row.calls - shown)) end
  end
  local runtimeTargets = {}
  for target, uses in pairs(graph.runtimeCalls or {}) do runtimeTargets[#runtimeTargets + 1] = { target = target, uses = uses } end
  table.sort(runtimeTargets, function(a, b)
    if a.uses == b.uses then return a.target < b.target end
    return a.uses > b.uses
  end)
  emit(("external runtime targets from reachable fragment26 graph: %d"):format(#runtimeTargets))
  for index, entry in ipairs(runtimeTargets) do
    local runtimeName = Fragment26.runtimeName(entry.target)
    emit(("  runtime[%02d] target=%s name=%s uses=%d"):format(index, hex32(entry.target), runtimeName or "unknown", entry.uses))
  end
end

if outputPath and outputPath ~= "" then
  local out, err = io.open(outputPath, "wb")
  if not out then fail("could not write report: " .. tostring(err))
  else
    out:write(table.concat(lines, "\n"), "\n")
    out:close()
    emit("report: " .. outputPath)
  end
end

if failures > 0 then
  emit(("fragment26 audit completed with %d failure(s)"):format(failures))
  os.exit(1)
end

emit("fragment26 audit completed")
