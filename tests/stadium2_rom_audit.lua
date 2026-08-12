package.path = "./?.lua;./?/init.lua;" .. package.path

local Layout = require("mods.STADIUM2_IMPORTER.lib.layout")
local Rom = require("mods.STADIUM2_IMPORTER.lib.rom")
local Extract = require("mods.STADIUM2_IMPORTER.lib.extract")
local Fragment = require("mods.STADIUM2_IMPORTER.lib.fragment")
local Fx = require("mods.STADIUM2_IMPORTER.lib.fx")
local Fragment26 = require("mods.STADIUM2_IMPORTER.lib.fragment26")

local path = os.getenv("STADIUM2_ROM") or arg[1]
if not path or path == "" then
  io.stderr:write("usage: STADIUM2_ROM=/path/to/stadium2.z64 luajit mods/STADIUM2_IMPORTER/tests/stadium2_rom_audit.lua\n")
  os.exit(2)
end

local outputPath = os.getenv("STADIUM2_AUDIT_OUT")
local decompRoot = os.getenv("STADIUM2_DECOMP")
local symbolMapPath = os.getenv("STADIUM2_SYMBOL_MAP")
local lines = {}
local failures = 0

local function emit(text)
  text = tostring(text)
  lines[#lines + 1] = text
  print(text)
end

local function fail(text)
  failures = failures + 1
  emit("FAIL: " .. text)
end

local function readFile(name)
  local file, err = io.open(name, "rb")
  if not file then return nil, err end
  local bytes = file:read("*a")
  file:close()
  return bytes
end

local function shellQuote(value)
  return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function rawMd5(name)
  if not io.popen then return nil end
  local pipe = io.popen("md5sum " .. shellQuote(name) .. " 2>/dev/null", "r")
  if not pipe then return nil end
  local text = pipe:read("*l")
  pipe:close()
  return text and text:match("^([0-9a-fA-F]+)") or nil
end

local function signature(blob)
  if type(blob) ~= "string" or #blob == 0 then return "empty" end
  if blob:sub(1, 8) == "PERS-SZP" then return "PERS-SZP" end
  if blob:sub(1, 4) == "Yay0" then return "Yay0" end
  if blob:sub(9, 16) == "FRAGMENT" then return "FRAGMENT" end
  if Rom.archiveAt(blob, 0) then return "archive" end
  return "raw"
end

local function decodeRecord(data, record)
  if not record or record.size <= 0 then return nil, "empty" end
  local blob = Rom.recordBytes(data, record)
  if not blob then return nil, "out-of-range" end
  local inputKind = signature(blob)
  local ok, decoded, err = pcall(Rom.decompress, blob)
  if not ok then return nil, tostring(decoded), inputKind end
  if not decoded then return nil, tostring(err), inputKind end
  return decoded, nil, inputKind
end

local function archiveLine(label, data, offset)
  local archive = Rom.archiveAt(data, offset)
  if not archive then
    emit(("%s: INVALID at 0x%X"):format(label, offset))
    return nil
  end
  emit(("%s: offset=0x%X tag=0x%X size=0x%X records=%d"):format(
    label, archive.offset, archive.tag, archive.total, archive.count))
  return archive
end

local function archiveScan(label, data, first, last)
  local archives = Rom.scanArchives(data, first, last, 8192)
  emit(("%s scan: %d valid archive headers in 0x%X..0x%X"):format(
    label, #archives, first, last))
  local shown = math.min(#archives, 24)
  for i = 1, shown do
    local archive = archives[i]
    emit(("  %02d 0x%X tag=0x%X size=0x%X records=%d"):format(
      i, archive.offset, archive.tag, archive.total, archive.count))
  end
  if #archives > shown then emit(("  ... %d more"):format(#archives - shown)) end
  return archives
end

local function signed16(value)
  if value >= 0x8000 then return value - 0x10000 end
  return value
end

local function metadataRow(data, index)
  local offset = Layout.SPECIES_META_START + index * Layout.SPECIES_META_RECORD_SIZE
  if offset + Layout.SPECIES_META_RECORD_SIZE > #data then return nil end
  local values = {}
  for i = 0, 7 do
    local pos = offset + i * 2
    local a, b = string.byte(data, pos + 1, pos + 2)
    if not b then return nil end
    values[#values + 1] = signed16(a * 256 + b)
  end
  return offset, values
end

local function inspectSpeciesRecord(label, data, archive, dex, recordNumber)
  local record = archive and archive.records[recordNumber + 1]
  if not record then
    emit(("%s dex=%03d record=%d missing"):format(label, dex, recordNumber))
    return
  end
  local decoded, err, inputKind = decodeRecord(data, record)
  if not decoded then
    emit(("%s dex=%03d record=%d rom=0x%X size=0x%X input=%s decode=%s"):format(
      label, dex, recordNumber, record.start, record.size, inputKind or "?", err or "failed"))
    return
  end
  local species, info = Extract.fragmentSpecies(decoded)
  local nested = Rom.archiveAt(decoded, 0)
  emit(("%s dex=%03d record=%d rom=0x%X size=0x%X input=%s decoded=%s fragmentSpecies=%s nestedRecords=%s"):format(
    label, dex, recordNumber, record.start, record.size, inputKind or "?", signature(decoded),
    species and tostring(species) or "-", nested and tostring(nested.count) or "-"))
  if species and info then
    emit(("  fragment root=0x%X sourceBase=0x%X"):format(info.rootOffset, info.sourceBase))
  end
end

local function hex32(value)
  if value == nil then return "-" end
  return ("0x%08X"):format(value % 0x100000000)
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
      if first == last then
        out[#out + 1] = ("%03d"):format(first)
      else
        out[#out + 1] = ("%03d-%03d"):format(first, last)
      end
      first, last = value, value
    end
  end
  return table.concat(out, ",")
end

local function compactPointerSet(set)
  local values = {}
  for value in pairs(set or {}) do values[#values + 1] = value end
  table.sort(values)
  if #values == 0 then return "-" end
  local shown = math.min(#values, 8)
  local out = {}
  for i = 1, shown do out[#out + 1] = hex32(values[i]) end
  if #values > shown then out[#out + 1] = ("+%d more"):format(#values - shown) end
  return table.concat(out, ",")
end

local function loadSymbols()
  local pathFromRoot = nil
  if decompRoot and decompRoot ~= "" then
    pathFromRoot = decompRoot:gsub("/+$", "") .. "/linker_scripts/us/symbol_addrs_code.txt"
  end
  local selected = symbolMapPath and symbolMapPath ~= "" and symbolMapPath or pathFromRoot
  if not selected then
    emit("model FX decomp symbols: not supplied")
    return nil
  end
  local map, err = Fx.loadSymbolMap(selected)
  if not map then
    emit("model FX decomp symbols: unavailable " .. tostring(err))
    return nil
  end
  emit(("model FX decomp symbols: %d symbols from %s"):format(#map.symbols, selected))
  return map
end

local function symbolText(map, callback)
  if not map then return "-" end
  local symbol = Fx.resolveSymbol(map, callback)
  if not symbol then return "-" end
  if symbol.exact then return symbol.name end
  if symbol.delta > 0x1000 then return "-" end
  return ("%s+0x%X"):format(symbol.name, symbol.delta)
end

local function countSet(set)
  local n = 0
  for _ in pairs(set or {}) do n = n + 1 end
  return n
end

local function auditModelFx(data, archive, symbolMap)
  local stats = {
    requested = 251,
    decoded = 0,
    speciesMatches = 0,
    withFx = 0,
    traversals = 0,
    uniqueCommands = 0,
    rawCallbacks = {},
    implementations = {},
    models = {},
  }

  for dex = 1, 251 do
    local modelRow = { dex = dex, nodes = {}, warnings = {} }
    stats.models[dex] = modelRow
    local record = archive and archive.records[dex + 1]
    if not record then
      modelRow.error = "missing model record"
      fail(("model FX dex=%03d record=%d missing"):format(dex, dex))
    else
      modelRow.record = record
      local decoded, err, inputKind = decodeRecord(data, record)
      if not decoded then
        modelRow.error = tostring(err or "decode failed")
        fail(("model FX dex=%03d record=%d rom=0x%X size=0x%X input=%s decode=%s"):format(
          dex, dex, record.start, record.size, inputKind or "?", err or "failed"))
      else
        stats.decoded = stats.decoded + 1
        local species, info = Extract.fragmentSpecies(decoded)
        modelRow.species = species
        modelRow.info = info
        if species == dex then
          stats.speciesMatches = stats.speciesMatches + 1
        else
          fail(("model FX dex=%03d record=%d fragmentSpecies=%s"):format(
            dex, dex, species and tostring(species) or "-"))
        end

        if not info then
          modelRow.error = "no FRAGMENT root"
          fail(("model FX dex=%03d record=%d has no FRAGMENT root"):format(dex, dex))
        else
          local fxInfo, fxErr = Fragment.inspectFx(decoded, ("model-%03d"):format(dex), info.sourceBase)
          if not fxInfo then
            modelRow.error = tostring(fxErr)
            fail(("model FX dex=%03d record=%d scan=%s"):format(dex, dex, tostring(fxErr)))
          else
            modelRow.fxInfo = fxInfo
            modelRow.warnings = fxInfo.warnings or {}
            local physical = {}
            if #(fxInfo.nodes or {}) > 0 then stats.withFx = stats.withFx + 1 end
            stats.traversals = stats.traversals + #(fxInfo.nodes or {})

            for _, node in ipairs(fxInfo.nodes or {}) do
              local handler = node.handler or node.callback
              local probe
              local identity
              if Fragment26.isDescriptor(handler) then
                probe = { origin = "fragment26-descriptor", callback = handler }
                identity = ("fragment26-descriptor:%08X"):format(handler)
              else
                probe = Fx.probe(decoded, handler, info.sourceBase, 0x100)
                identity = Fx.identity(probe, handler)
              end
              local physicalKey = table.concat({
                tostring(node.commandOffset),
                tostring(handler),
                tostring(node.argPointer),
              }, ":")
              local isUnique = not physical[physicalKey]
              if isUnique then
                physical[physicalKey] = true
                stats.uniqueCommands = stats.uniqueCommands + 1
              end

              local impl = stats.implementations[identity]
              if not impl then
                impl = {
                  identity = identity,
                  origin = probe and probe.origin or "unknown",
                  fingerprint = probe and probe.fingerprint or nil,
                  probe = probe,
                  commands = 0,
                  traversals = 0,
                  species = {},
                  callbackAddresses = {},
                  callbackOffsets = {},
                  args = {},
                  samples = {},
                }
                stats.implementations[identity] = impl
              end
              if isUnique then impl.commands = impl.commands + 1 end
              impl.traversals = impl.traversals + 1
              impl.species[dex] = true
              impl.callbackAddresses[handler] = true
              if probe and probe.offset ~= nil then impl.callbackOffsets[probe.offset] = true end
              if node.argPointer ~= nil then impl.args[node.argPointer] = true end
              if #impl.samples < 6 then
                impl.samples[#impl.samples + 1] = {
                  dex = dex,
                  commandOffset = node.commandOffset,
                  callback = handler,
                }
              end

              local raw = stats.rawCallbacks[handler]
              if not raw then
                raw = { traversals = 0, commands = 0, species = {}, implementations = {} }
                stats.rawCallbacks[handler] = raw
              end
              raw.traversals = raw.traversals + 1
              if isUnique then raw.commands = raw.commands + 1 end
              raw.species[dex] = true
              raw.implementations[identity] = true

              modelRow.nodes[#modelRow.nodes + 1] = {
                node = node,
                probe = probe,
                identity = identity,
                handler = handler,
                unique = isUnique,
              }
            end
          end
        end
      end
    end
  end

  local implementations = {}
  for _, row in pairs(stats.implementations) do implementations[#implementations + 1] = row end
  table.sort(implementations, function(a, b)
    if a.origin ~= b.origin then return a.origin < b.origin end
    local aa = 0xFFFFFFFF
    local bb = 0xFFFFFFFF
    for address in pairs(a.callbackAddresses) do if address < aa then aa = address end end
    for address in pairs(b.callbackAddresses) do if address < bb then bb = address end end
    if aa ~= bb then return aa < bb end
    return tostring(a.fingerprint or a.identity) < tostring(b.fingerprint or b.identity)
  end)
  local identityIds = {}
  for index, row in ipairs(implementations) do
    row.id = ("FX%03d"):format(index)
    identityIds[row.identity] = row.id
  end

  emit("model FX callback audit: records 1..251")
  for dex = 1, 251 do
    local modelRow = stats.models[dex]
    if modelRow and modelRow.record and modelRow.fxInfo then
      local fxInfo = modelRow.fxInfo
      local unique = 0
      for _, entry in ipairs(modelRow.nodes) do if entry.unique then unique = unique + 1 end end
      emit(("model dex=%03d record=%d rom=0x%X size=0x%X fragmentSpecies=%s layouts=%d fxNodes=%d uniqueFxCommands=%d warnings=%d"):format(
        dex, dex, modelRow.record.start, modelRow.record.size,
        modelRow.species and tostring(modelRow.species) or "-",
        fxInfo.geometry or 0, #modelRow.nodes, unique, #(modelRow.warnings or {})))
      for index, entry in ipairs(modelRow.nodes) do
        local node = entry.node
        local probe = entry.probe or {}
        local callbackOffset = probe.offset ~= nil and ("0x%X"):format(probe.offset) or "-"
        local handler = entry.handler or node.handler or node.callback
        local symbol = probe.origin == "runtime" and symbolText(symbolMap, handler) or "-"
        emit(("  fx[%02d] impl=%s geo=%d root=0x%X cmd=0x%X bone=%d boneId=%s handler=%s kind=%s cbOff=%s symbol=%s arg=%s argOff=%s"):format(
          index, identityIds[entry.identity] or "FX???", node.layout or -1,
          node.layoutOffset or 0, node.commandOffset or 0, node.bone or -1,
          node.boneId ~= nil and tostring(node.boneId) or "-", hex32(handler),
          probe.origin or "unknown", callbackOffset, symbol, hex32(node.argPointer),
          node.argOffset ~= nil and ("0x%X"):format(node.argOffset) or "-"))
      end
      for _, warning in ipairs(modelRow.warnings or {}) do emit("  warning: " .. tostring(warning)) end
    elseif modelRow then
      emit(("model dex=%03d record=%d ERROR=%s"):format(dex, dex, tostring(modelRow.error or "unknown")))
    end
  end

  local rawKeys = {}
  for callback in pairs(stats.rawCallbacks) do rawKeys[#rawKeys + 1] = callback end
  table.sort(rawKeys)
  emit(("model geometry handler summary: requested=%d decoded=%d speciesMatches=%d modelsWithHandlers=%d traversals=%d uniqueCommands=%d rawHandlerAddresses=%d uniqueHandlerIdentities=%d"):format(
    stats.requested, stats.decoded, stats.speciesMatches, stats.withFx,
    stats.traversals, stats.uniqueCommands, #rawKeys, #implementations))

  emit("model geometry handler identity summary:")
  for _, row in ipairs(implementations) do
    local addressValues = {}
    for value in pairs(row.callbackAddresses) do addressValues[value] = true end
    local offsetValues = {}
    for value in pairs(row.callbackOffsets) do offsetValues[value] = true end
    local firstAddress = nil
    for value in pairs(row.callbackAddresses) do
      if firstAddress == nil or value < firstAddress then firstAddress = value end
    end
    local symbol = row.origin == "runtime" and symbolText(symbolMap, firstAddress) or "-"
    emit(("  %s origin=%s fingerprint=%s commands=%d traversals=%d species=%d dex=%s callbacks=%s cbOffsets=%s symbol=%s args=%s"):format(
      row.id, row.origin, row.fingerprint or "-", row.commands, row.traversals,
      countSet(row.species), compactDexSet(row.species), compactPointerSet(addressValues),
      compactPointerSet(offsetValues), symbol, compactPointerSet(row.args)))
    if row.probe and row.probe.origin == "fragment" then
      emit(("    code reason=%s bytes=0x%X head=%s"):format(
        tostring(row.probe.reason or "-"), row.probe.length or 0, row.probe.head or "-"))
      emit("    words " .. tostring(row.probe.words or "-"))
    end
  end

  emit("model geometry raw-handler summary:")
  for index, callback in ipairs(rawKeys) do
    local row = stats.rawCallbacks[callback]
    emit(("  handler[%02d] %s commands=%d traversals=%d species=%d identities=%d dex=%s symbol=%s"):format(
      index, hex32(callback), row.commands, row.traversals, countSet(row.species),
      countSet(row.implementations), compactDexSet(row.species), symbolText(symbolMap, callback)))
  end

  return stats
end

local function fragment26TargetText(symbolMap, value)
  local kind, info = Fragment26.classifyWord(value)
  if kind == "fragment26-function" then
    if info.exact then return info.name end
    return ("%s+0x%X"):format(info.name, info.delta)
  end
  if kind == "fragment26-data" then
    return ("fragment26+0x%X"):format(info.offset)
  end
  if kind == "descriptor" then return "descriptor:" .. hex32(value) end
  if kind == "runtime" then
    local symbol = symbolText(symbolMap, value)
    if symbol ~= "-" then return symbol end
  end
  return kind
end

local function auditFragment26Descriptors(data, stats, symbolMap)
  local handlers = {}
  for address in pairs((stats and stats.rawCallbacks) or {}) do
    if Fragment26.isDescriptor(address) then handlers[#handlers + 1] = address end
  end
  table.sort(handlers)

  emit(("fragment26 model-handler table: rom=0x%X..0x%X vram=0x%X..0x%X table=0x%X..0x%X codeStart=0x%X usedDescriptors=%d"):format(
    Fragment26.ROM_START, Fragment26.ROM_END, Fragment26.VRAM_BASE, Fragment26.VRAM_END,
    Fragment26.TABLE_START, Fragment26.TABLE_END, Fragment26.CODE_START, #handlers))

  local targets = {}
  for index, address in ipairs(handlers) do
    local descriptor, err = Fragment26.descriptor(data, address)
    if not descriptor then
      fail(("fragment26 descriptor %s: %s"):format(hex32(address), tostring(err)))
    else
      local row = stats.rawCallbacks[address]
      emit(("  descriptor[%02d] ptr=%s tableOff=0x%X rom=0x%X word0=%s (%s) word1=%s (%s) commands=%d traversals=%d species=%d dex=%s"):format(
        index, hex32(address), descriptor.offset, descriptor.romOffset,
        hex32(descriptor.word0), fragment26TargetText(symbolMap, descriptor.word0),
        hex32(descriptor.word1), fragment26TargetText(symbolMap, descriptor.word1),
        row and row.commands or 0, row and row.traversals or 0,
        countSet(row and row.species), compactDexSet(row and row.species)))

      for slot, value in ipairs({ descriptor.word0, descriptor.word1 }) do
        local kind, info = Fragment26.classifyWord(value)
        if kind == "fragment26-function" then
          local start = info.start
          local target = targets[start]
          if not target then
            target = { info = Fragment26.functionInfo(start), descriptors = {}, slots = {} }
            targets[start] = target
          end
          target.descriptors[address] = true
          target.slots[slot - 1] = true
        end
      end
    end
  end

  local targetStarts = {}
  for address in pairs(targets) do targetStarts[#targetStarts + 1] = address end
  table.sort(targetStarts)
  emit(("fragment26 descriptor target functions: %d"):format(#targetStarts))

  for index, start in ipairs(targetStarts) do
    local target = targets[start]
    local code, infoOrErr = Fragment26.functionBytes(data, start)
    if not code then
      fail(("fragment26 function %s: %s"):format(hex32(start), tostring(infoOrErr)))
    else
      local info = infoOrErr
      local descriptorSet = {}
      for address in pairs(target.descriptors) do descriptorSet[address] = true end
      local calls = Fragment26.scanDirectCalls(code, info.start)
      emit(("  function[%02d] %s vram=%s rom=0x%X..0x%X size=0x%X fingerprint=%08X:%X descriptors=%s directCalls=%d"):format(
        index, info.name, hex32(info.start), info.romStart, info.romEnd, #code,
        Fx.crc32(code), #code, compactPointerSet(descriptorSet), #calls))
      emit(("    head=%s"):format(Fx.hexBytes(code, 64)))
      emit(("    words=%s"):format(Fx.wordList(code, 24)))
      local shown = math.min(#calls, 32)
      for callIndex = 1, shown do
        local call = calls[callIndex]
        if call.indirect then
          emit(("    call[%02d] at=%s+0x%X jalr"):format(callIndex, info.name, call.offset))
        else
          emit(("    call[%02d] at=%s+0x%X target=%s (%s)"):format(
            callIndex, info.name, call.offset, hex32(call.target),
            fragment26TargetText(symbolMap, call.target)))
        end
      end
      if #calls > shown then emit(("    ... %d more calls"):format(#calls - shown)) end
    end
  end

  local nonDescriptor = {}
  for address in pairs((stats and stats.rawCallbacks) or {}) do
    if not Fragment26.isDescriptor(address) then nonDescriptor[#nonDescriptor + 1] = address end
  end
  table.sort(nonDescriptor)
  if #nonDescriptor > 0 then
    emit(("fragment26 handler audit: %d model handler address(es) are outside the descriptor table"):format(#nonDescriptor))
    for _, address in ipairs(nonDescriptor) do
      emit(("  outside %s (%s)"):format(hex32(address), fragment26TargetText(symbolMap, address)))
    end
  end
end

local bytes, readErr = readFile(path)
if not bytes then error(readErr, 0) end
local data, order = Rom.normalise(bytes)
if not data then error(order, 0) end

emit("audit version: 0.3.4-full-fragment26")
emit(("ROM: %s"):format(path))
emit(("byte order: %s"):format(order))
emit(("size: 0x%X"):format(#data))
emit(("title: %s"):format(Rom.title(data)))
local hash = rawMd5(path)
emit(("raw MD5: %s"):format(hash or "unavailable"))
emit(("expected US MD5: %s"):format(Layout.US_MD5))
emit(("current decomp commit: %s"):format(Layout.CURRENT_DECOMP_COMMIT))
emit(("opaque asset tail: 0x%X..0x%X"):format(Layout.ASSET_START, Layout.ROM_END))
emit(("pret model region: 0x%X..0x%X"):format(Layout.MODEL_TABLE_START, Layout.MODEL_TABLE_END))
emit(("pret pose region: 0x%X..0x%X"):format(Layout.POSE_TABLE_START, Layout.POSE_TABLE_END))
emit(("post-pose table: 0x%X..0x%X"):format(Layout.POST_POSE_TABLE_START, Layout.POST_POSE_TABLE_END))
emit(("species metadata candidate: 0x%X..0x%X"):format(Layout.SPECIES_META_START, Layout.ROM_END))

if #data ~= Layout.ROM_SIZE then fail(("wrong ROM size 0x%X"):format(#data)) end
if Rom.title(data):upper() ~= Layout.US_TITLE then fail("wrong ROM title") end
if hash and order == "z64" and hash:lower() ~= Layout.US_MD5 then fail("raw z64 MD5 does not match supported US ROM") end

local models = archiveLine("model region root", data, Layout.MODEL_TABLE_START)
local poses = archiveLine("pose region root", data, Layout.POSE_TABLE_START)
local postPose = archiveLine("post-pose region root", data, Layout.POST_POSE_TABLE_START)

archiveScan("model region", data, Layout.MODEL_TABLE_START, Layout.MODEL_TABLE_END - 0x10)
archiveScan("pose region", data, Layout.POSE_TABLE_START, Layout.POSE_TABLE_END - 0x10)
archiveScan("post-pose region", data, Layout.POST_POSE_TABLE_START, Layout.POST_POSE_TABLE_END - 0x10)

if not models then fail("model region does not begin with a verified cattbl archive") end
if not poses then fail("pose region does not begin with a verified cattbl archive") end
if not postPose then fail("post-pose region does not begin with a verified cattbl archive") end

local anchors = { 1, 25, 151, 152, 201, 251 }
if models then
  emit("model species-index probes:")
  for _, dex in ipairs(anchors) do
    inspectSpeciesRecord("model", data, models, dex, dex - 1)
    inspectSpeciesRecord("model", data, models, dex, dex)
  end
end

if poses then
  emit("pose species-index probes:")
  for _, dex in ipairs(anchors) do
    inspectSpeciesRecord("pose", data, poses, dex, dex - 1)
    inspectSpeciesRecord("pose", data, poses, dex, dex)
  end
end

local symbolMap = loadSymbols()
local modelFxStats = nil
if models then
  modelFxStats = auditModelFx(data, models, symbolMap)
  auditFragment26Descriptors(data, modelFxStats, symbolMap)
end

emit(("0x3FED000 fixed-record probe: historicalCount=%d recordSize=0x%X"):format(
  Layout.HISTORICAL_SPECIES_META_RECORDS, Layout.SPECIES_META_RECORD_SIZE))
for _, index in ipairs({ 0, 1, 24, 25, 150, 151, 152, 200, 201, 250, 251, 252 }) do
  local offset, values = metadataRow(data, index)
  if offset then
    emit(("  meta[%03d] 0x%X = %d %d %d %d %d %d %d %d"):format(
      index, offset, values[1], values[2], values[3], values[4],
      values[5], values[6], values[7], values[8]))
  end
end

if outputPath and outputPath ~= "" then
  local out, err = io.open(outputPath, "wb")
  if not out then fail("could not write audit report: " .. tostring(err))
  else
    out:write(table.concat(lines, "\n"), "\n")
    out:close()
    emit("report: " .. outputPath)
  end
end

if failures > 0 then
  emit(("audit completed with %d failure(s)"):format(failures))
  os.exit(1)
end

emit("audit completed")
