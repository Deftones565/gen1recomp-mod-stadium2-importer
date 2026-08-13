local Registry = require("mods.STADIUM2_IMPORTER.lib.handler_registry")
local DynamicObject = require("mods.STADIUM2_IMPORTER.lib.effects.dynamic_object")
local Phase5Geometry = require("mods.STADIUM2_IMPORTER.lib.render_callbacks.phase5_geometry")
local Handlers = {}

-- Compatibility exports.  New code should require handler_registry directly.
Handlers.BY_DESCRIPTOR = Registry.BY_DESCRIPTOR
Handlers.BY_TARGET = Registry.BY_TARGET
Handlers.FAMILY_IDS = Registry.FAMILY_IDS
Handlers.FAMILY_NAMES = Registry.FAMILY_NAMES
Handlers.CONFIDENCE_IDS = Registry.CONFIDENCE_IDS
Handlers.CONFIDENCE_NAMES = Registry.CONFIDENCE_NAMES

local function byte(data, offset)
  return string.byte(data, offset + 1)
end

local function u16be(data, offset)
  local a, b = string.byte(data, offset + 1, offset + 2)
  if not b then return nil end
  return a * 256 + b
end

local function i16be(data, offset)
  local value = u16be(data, offset)
  if value and value >= 0x8000 then value = value - 0x10000 end
  return value
end

local function u32be(data, offset)
  local a, b, c, d = string.byte(data, offset + 1, offset + 4)
  if not d then return nil end
  return ((a * 256 + b) * 256 + c) * 256 + d
end

local function u16le(data, offset)
  local a, b = string.byte(data, offset + 1, offset + 2)
  if not b then return nil end
  return a + b * 256
end

local function i16le(data, offset)
  local value = u16le(data, offset)
  if value and value >= 0x8000 then value = value - 0x10000 end
  return value
end

local function u32le(data, offset)
  local a, b, c, d = string.byte(data, offset + 1, offset + 4)
  if not d then return nil end
  return a + b * 256 + c * 65536 + d * 16777216
end

local function p16(value)
  value = value % 0x10000
  return string.char(value % 256, math.floor(value / 256) % 256)
end

local function p32(value)
  value = value % 0x100000000
  return string.char(value % 256, math.floor(value / 256) % 256,
    math.floor(value / 65536) % 256, math.floor(value / 16777216) % 256)
end

local function pi16(value)
  return p16((tonumber(value) or -1) % 0x10000)
end

local function phaseMask(phases)
  local mask = 0
  for _, phase in ipairs(phases or {}) do
    if phase >= 0 and phase <= 7 then mask = mask + 2 ^ phase end
  end
  return mask
end

local function phasesFromMask(mask)
  local phases = {}
  for phase = 0, 7 do
    if math.floor(mask / 2 ^ phase) % 2 == 1 then phases[#phases + 1] = phase end
  end
  return phases
end

local function hasPhase(phases, phase)
  for _, value in ipairs(phases or {}) do
    if value == phase then return true end
  end
  return false
end

local function flagsFor(row, hasArg)
  local flags = hasArg and 1 or 0
  local family = row.family
  if family ~= "model-context-register" then flags = flags + 2 end
  if family == "model-context-register" then flags = flags + 4 + 64 end
  if family == "display-list-wrapper" or family == "dynamic-material-builder"
      or family == "texture-material-builder" then flags = flags + 8 end
  if family == "render-time-geometry-pipeline" or family == "dynamic-object-renderer" then
    flags = flags + 16
  end
  if family == "visibility-range-enable" or family == "visibility-range-disable" then
    flags = flags + 32
  end
  if row.confidence == "partial" then flags = flags + 128 end
  return flags
end

local function semanticBytes(record)
  if record.gate then
    return p16(record.gate.selector or 0) .. p16(record.gate.minimum or 0)
      .. p16(record.gate.maximum or 0) .. string.char(record.gate.invert and 1 or 0)
  end
  if record.sourcePointers then
    return p32(record.sourcePointers[1] or 0) .. p32(record.sourcePointers[2] or 0)
  end
  return ""
end

local function renderBytes(renderInfo)
  local prims = type(renderInfo) == "table" and (renderInfo.prims or renderInfo) or {}
  local textures = type(renderInfo) == "table" and renderInfo.handlerTextures or nil
  textures = type(textures) == "table" and textures or {}
  local out = { "R4MD", p16(#prims), p16(#textures) }
  for _, prim in ipairs(prims) do
    out[#out + 1] = p32(prim.materialOffset ~= nil and prim.materialOffset or 0xFFFFFFFF)
    out[#out + 1] = p32(prim.callbackOffset ~= nil and prim.callbackOffset or 0xFFFFFFFF)
  end
  for _, row in ipairs(textures) do
    out[#out + 1] = p32(row.commandOffset or 0xFFFFFFFF)
    out[#out + 1] = p32(row.pointer or 0)
    out[#out + 1] = p16(row.slot or 0)
    out[#out + 1] = p16(row.w or 0)
    out[#out + 1] = p16(row.h or 0)
    out[#out + 1] = string.char(row.format or 0, row.size or 0)
  end
  return table.concat(out)
end

local function readRenderBytes(data)
  if type(data) ~= "string" or #data < 8 then return nil end
  local magic = data:sub(1, 4)
  if magic ~= "R3MD" and magic ~= "R4MD" then return nil end
  local stride = magic == "R4MD" and 8 or 4
  local count, textureCount = u16le(data, 4), u16le(data, 6)
  if not count or not textureCount or 8 + count * stride + textureCount * 16 > #data then return nil end
  local out = { primitiveMaterials = {}, primitiveCallbacks = {}, handlerTextures = {} }
  local cursor = 8
  for i = 1, count do
    local offset = u32le(data, cursor)
    out.primitiveMaterials[i] = offset ~= 0xFFFFFFFF and offset or nil
    if stride == 8 then
      local callback = u32le(data, cursor + 4)
      out.primitiveCallbacks[i] = callback ~= 0xFFFFFFFF and callback or nil
    end
    cursor = cursor + stride
  end
  for i = 1, textureCount do
    out.handlerTextures[i] = {
      commandOffset = u32le(data, cursor), pointer = u32le(data, cursor + 4),
      slot = u16le(data, cursor + 8), w = u16le(data, cursor + 10), h = u16le(data, cursor + 12),
      format = byte(data, cursor + 14), size = byte(data, cursor + 15),
    }
    cursor = cursor + 16
  end
  return out
end

local function decodeSemantic(record, semantic)
  if record.family == "visibility-range-enable" or record.family == "visibility-range-disable" then
    if #semantic >= 7 then
      record.gate = {
        selector = u16le(semantic, 0),
        minimum = u16le(semantic, 2),
        maximum = u16le(semantic, 4),
        invert = byte(semantic, 6) ~= 0,
      }
    end
  elseif record.family == "display-list-wrapper" and #semantic >= 8 then
    record.sourcePointers = { u32le(semantic, 0), u32le(semantic, 4) }
  end
end

function Handlers.info(address)
  return Registry.info(address)
end

function Handlers.family(address)
  return Registry.family(address)
end

function Handlers.compile(nodes, fragmentData, sourceBase, maxArgumentBytes)
  local out = {}
  sourceBase = tonumber(sourceBase) or 0x8FF00000
  maxArgumentBytes = math.max(0, math.floor(tonumber(maxArgumentBytes) or 0x100))
  for _, node in ipairs(nodes or {}) do
    local descriptor = tonumber(node.handler or node.callback)
    local row = Handlers.BY_DESCRIPTOR[descriptor]
    if row then
      local argOffset = tonumber(node.argOffset or node.arg)
      local hasArg = argOffset ~= nil and argOffset >= 0 and type(fragmentData) == "string"
        and argOffset < #fragmentData
      local argBlob = ""
      if hasArg and maxArgumentBytes > 0 then
        argBlob = fragmentData:sub(argOffset + 1, math.min(#fragmentData, argOffset + maxArgumentBytes))
      end
      local record = {
        descriptor = descriptor,
        target = row.target,
        family = row.family,
        confidence = row.confidence,
        phases = row.phases,
        bone = tonumber(node.bone) or -1,
        boneId = node.boneId,
        commandOffset = node.commandOffset,
        argOffset = hasArg and argOffset or nil,
        argAddress = hasArg and (sourceBase + argOffset) or nil,
        argument = argBlob,
        noRender = row.family == "model-context-register",
        runtimeDependent = row.family ~= "model-context-register",
      }
      if row.family == "visibility-range-enable" or row.family == "visibility-range-disable" then
        if hasArg and #argBlob >= 6 then
          record.gate = {
            selector = u16be(argBlob, 0),
            minimum = u16be(argBlob, 2),
            maximum = u16be(argBlob, 4),
            invert = row.family == "visibility-range-disable",
          }
        end
      elseif row.family == "display-list-wrapper" and hasArg and #argBlob >= 8 then
        record.sourcePointers = { u32be(argBlob, 0), u32be(argBlob, 4) }
      end
      out[#out + 1] = record
    end
  end
  return out
end

function Handlers.evaluate(record, phase, runtime)
  if type(record) ~= "table" or not hasPhase(record.phases, tonumber(phase)) then return nil end
  if record.family == "model-context-register" then
    return { operation = "register-model-context", ifEmpty = true, noRender = true }
  end
  if record.family == "visibility-range-enable" or record.family == "visibility-range-disable" then
    local gate = record.gate
    runtime = type(runtime) == "table" and runtime or {}
    if not gate then return { operation = "visibility-bit0", unresolved = true } end
    local selector = tonumber(runtime.selector)
    local value = tonumber(runtime.rangeValue or runtime.value)
    if selector == nil or value == nil then
      return { operation = "visibility-bit0", unresolved = true, gate = gate }
    end
    local matched = selector == gate.selector and value >= gate.minimum and value <= gate.maximum
    if gate.invert then matched = not matched end
    return { operation = "visibility-bit0", bit0 = matched, gate = gate }
  end
  runtime = type(runtime) == "table" and runtime or {}
  local frame = math.max(0, math.floor(tonumber(runtime.sourceFrame or runtime.frame) or 0))
  local callbackFrame = math.max(0, math.floor(tonumber(runtime.callbackFrame) or frame))
  local result = {
    operation = record.family, runtimeDependent = record.runtimeDependent,
    argument = record.argument, sourcePointers = record.sourcePointers,
    commandOffset = record.commandOffset, bone = record.bone, boneId = record.boneId,
    sourceFrame = frame, callbackFrame = callbackFrame, program = record.program,
  }
  if record.family == "display-list-wrapper" then
    result.displayLists = record.sourcePointers
    result.enabled = runtime.suppressWrappedLists ~= true
  elseif record.family == "dynamic-material-builder" or record.family == "texture-material-builder" then
    local callbackFrame = math.floor(tonumber(runtime.textureFrame) or frame)
    if record.descriptor == 0x81000050 and tonumber(runtime.species) == 88 then
      local animation, animationFrame = tonumber(runtime.selector) or -1,
        tonumber(runtime.rangeValue) or 0
      result.textureFrame = animation >= 2 and animationFrame >= 66
        and animationFrame < 74 and (animationFrame - 66) or 0
    else
      result.textureFrame = callbackFrame % 8
    end
    result.dualTexture = record.descriptor == 0x81000048
    result.textureScroll = result.dualTexture and {
      { -callbackFrame / 32, callbackFrame / 32 },
      { -callbackFrame / 16, callbackFrame / 16 },
    } or nil
    result.materialPointer = record.argAddress
  elseif record.family == "dynamic-object-renderer" then
    result.emitterPointer = record.argAddress
    result.emitterFrame = frame
    result.objectTransforms = runtime.objectTransformsBySite
      and runtime.objectTransformsBySite[record.commandOffset] or nil
  elseif record.family == "attribute-transform" then
    result.attributePointer = record.argAddress
    result.attributeFrame = frame
    result.color = runtime.attributeColorsBySite
      and runtime.attributeColorsBySite[record.commandOffset] or nil
  elseif record.family == "runtime-dispatch-bridge" then
    result.dispatchIndex = math.max(0, math.floor(tonumber(runtime.dispatchIndex or runtime.formIndex) or 0))
  elseif record.family == "render-time-geometry-pipeline" then
    result.geometryPointer = record.argAddress
    result.geometryIndex = math.max(0, math.floor(tonumber(runtime.geometryIndex) or frame))
  end
  return result
end

function Handlers.resolvePointer(extension, pointer, length)
  if type(extension) ~= "table" or type(extension.fragment) ~= "string" then return nil end
  pointer = tonumber(pointer)
  length = math.max(0, math.floor(tonumber(length) or 1))
  if not pointer then return nil end
  local offset = pointer - (tonumber(extension.sourceBase) or 0x8FF00000)
  if offset < 0 or offset + length > #extension.fragment then return nil end
  return extension.fragment:sub(offset + 1, offset + length), offset
end

local function pointerWords(extension, offset, bytes)
  local out, seen = {}, {}
  local data = extension and extension.fragment
  if type(data) ~= "string" or type(offset) ~= "number" then return out end
  local finish = math.min(#data, offset + (bytes or 0x100))
  for at = offset, finish - 4, 4 do
    local value = u32be(data, at)
    local relative = value and value - (tonumber(extension.sourceBase) or 0x8FF00000) or -1
    if relative >= 0 and relative < #data and not seen[value] then
      seen[value] = true
      out[#out + 1] = { pointer = value, offset = relative, sourceOffset = at }
    end
  end
  return out
end


local function dynamicObjectGeometry(extension, record)
  local data = extension and extension.fragment
  local base = tonumber(extension and extension.sourceBase) or 0x8FF00000
  local arg = tonumber(record and record.argOffset)
  if type(data) ~= "string" or not arg then return nil end
  local dlPointer = u32be(data, arg + 4)
  local dl = dlPointer and (dlPointer - base) or -1
  if dl < 0 or dl + 16 > #data then return nil end
  local vtxWord = u32be(data, dl)
  local vtxPointer = u32be(data, dl + 4)
  local tri0 = u32be(data, dl + 8)
  local tri1 = u32be(data, dl + 12)
  if not vtxWord or math.floor(vtxWord / 0x1000000) ~= 0x01 then return nil end
  local count = math.floor(vtxWord / 0x1000) % 256
  if count ~= 4 then return nil end
  local vtx = vtxPointer and (vtxPointer - base) or -1
  if vtx < 0 or vtx + 64 > #data then return nil end
  local vertices = {}
  for i = 0, 3 do
    local at = vtx + i * 16
    vertices[i + 1] = {
      x = i16be(data, at), y = i16be(data, at + 2), z = i16be(data, at + 4),
      s = i16be(data, at + 8), t = i16be(data, at + 10),
    }
  end
  local function tri(word)
    return {
      math.floor(math.floor(word / 0x10000) % 256 / 2) + 1,
      math.floor(math.floor(word / 0x100) % 256 / 2) + 1,
      math.floor(word % 256 / 2) + 1,
    }
  end
  local a, b = tri(tri0 or 0), tri(tri1 or 0)
  return {
    displayListPointer = dlPointer, vertexPointer = vtxPointer,
    vertices = vertices, indices = {a[1],a[2],a[3],b[1],b[2],b[3]},
  }
end

function Handlers.prepare(extension)
  if type(extension) ~= "table" or type(extension.records) ~= "table" then return extension end
  local Materials = require("mods.STADIUM2_IMPORTER.lib.materials")
  for _, record in ipairs(extension.records) do
    local scanBytes = record.family == "render-time-geometry-pipeline" and 0x400 or 0x100
    local assets = pointerWords(extension, record.argOffset, scanBytes)
    local program = { family = record.family, assets = assets, textures = {}, complete = true }
    if record.family == "dynamic-object-renderer" then
      program.geometry = dynamicObjectGeometry(extension, record)
    elseif record.family == "render-time-geometry-pipeline" then
      program.phase5Material = Phase5Geometry.materialSpec(extension.fragment,
        extension.sourceBase, record.argOffset)
    end
    for _, texture in ipairs(extension.render and extension.render.handlerTextures or {}) do
      if texture.commandOffset == record.commandOffset then program.textures[#program.textures + 1] = texture end
    end
    for _, asset in ipairs(assets) do
      local op = byte(extension.fragment, asset.offset)
      if op == 0xDE or op == 0xDF or op == 0xD9 or op == 0xE7
          or op == 0xF5 or op == 0xFA or op == 0xFB or op == 0xFC or op == 0xFD then
        asset.material = Materials.parse(extension, asset.offset)
      end
    end
    if record.family ~= "model-context-register" and record.family ~= "runtime-dispatch-bridge"
        and record.family ~= "visibility-range-enable" and record.family ~= "visibility-range-disable"
        and record.argOffset == nil then
      program.complete = false
      program.error = "missing callback argument"
    end
    record.program = program
  end
  return extension
end

function Handlers.runExtension(extension, phase, runtime, state)
  if type(extension) ~= "table" or type(extension.records) ~= "table" then return nil, nil end
  local values = {}
  for key, value in pairs(type(runtime) == "table" and runtime or {}) do values[key] = value end
  values.extension = extension
  return Handlers.run(extension.records, phase, values, state)
end

function Handlers.koffingGasSpawnExpected(runtime)
  return DynamicObject.koffingSpawnExpected(type(runtime) == "table" and runtime or {})
end

function Handlers.koffingGasRenderState(age)
  return DynamicObject.koffingRenderState(age)
end

function Handlers.koffingGasInitialize(origin, reference, speed)
  return DynamicObject.koffingInitialize(origin, reference, speed)
end

function Handlers.run(records, phase, runtime, state)
  state = type(state) == "table" and state or {}
  runtime = type(runtime) == "table" and runtime or {}
  state.bit0ByBone = type(state.bit0ByBone) == "table" and state.bit0ByBone or {}
  state.operations = type(state.operations) == "table" and state.operations or {}
  state.renderQueue = type(state.renderQueue) == "table" and state.renderQueue or {}
  state.materialByBone = type(state.materialByBone) == "table" and state.materialByBone or {}
  state.attributesByBone = type(state.attributesByBone) == "table" and state.attributesByBone or {}
  state.textureByBone = type(state.textureByBone) == "table" and state.textureByBone or {}
  state.materialBySite = type(state.materialBySite) == "table" and state.materialBySite or {}
  state.attributesBySite = type(state.attributesBySite) == "table" and state.attributesBySite or {}
  state.textureBySite = type(state.textureBySite) == "table" and state.textureBySite or {}
  state.textureSetBySite = type(state.textureSetBySite) == "table" and state.textureSetBySite or {}
  state.dynamicObjectsBySite = type(state.dynamicObjectsBySite) == "table" and state.dynamicObjectsBySite or {}
  state.renderTimeResolvedBySite = type(state.renderTimeResolvedBySite) == "table"
    and state.renderTimeResolvedBySite or {}
  if tonumber(phase) == 5 then state.renderQueue = {} end
  local deferred = {}
  for _, record in ipairs(records or {}) do
    local result = Handlers.evaluate(record, phase, runtime)
    if result then
      if result.operation == "register-model-context" then
        if state.modelContext == nil then state.modelContext = runtime.modelContext or runtime.node end
      elseif result.operation == "visibility-bit0" and not result.unresolved then
        state.bit0ByBone[record.bone] = result.bit0
      else
        local key = tonumber(record.commandOffset) or (#state.operations + 1)
        local item = { record = record, result = result, extension = runtime.extension }
        state.operations[key] = item
        if result.operation == "display-list-wrapper" or result.operation == "dynamic-material-builder"
            or result.operation == "texture-material-builder" then
          local assets = result.program and result.program.assets or {}
          local selected = #assets > 0
            and assets[result.textureFrame and (result.textureFrame % #assets + 1) or 1] or nil
          state.materialBySite[key] = selected and selected.material or nil
          local textures = result.program and result.program.textures or {}
          if #textures > 0 then
            if result.dualTexture then
              -- The source material always has two texture tiles, but both
              -- tiles may point at the same image (Grimer does this). The
              -- extraction cache deliberately deduplicates identical image
              -- payloads, so one cached texture still represents a complete
              -- two-layer material rather than a single-texture fallback.
              local first = textures[1].slot + 1
              local second = textures[2] and textures[2].slot + 1 or first
              state.textureBySite[key] = first
              state.textureSetBySite[key] = {
                first, second,
                scroll = result.textureScroll, mix = 100 / 255,
              }
            else
              state.textureBySite[key] = textures[(result.textureFrame or 0) % #textures + 1].slot + 1
              state.textureSetBySite[key] = nil
            end
          end
        elseif result.operation == "dynamic-object-renderer" then
          state.textureBySite[key] = nil
          state.textureSetBySite[key] = nil
          DynamicObject.updateState(state, key, result, runtime)
        elseif result.operation == "attribute-transform" then
          state.attributesBySite[key] = result
        elseif result.operation == "render-time-geometry-pipeline" then
          Phase5Geometry.apply(state, key, result)
        end
        if result.operation == "render-time-geometry-pipeline"
            or result.operation == "dynamic-object-renderer" then
          state.renderQueue[#state.renderQueue + 1] = item
        end
      end
    end
  end
  return state, deferred
end

function Handlers.packExtension(records, sourceBase, fragmentData, renderInfo)
  records = type(records) == "table" and records or {}
  fragmentData = type(fragmentData) == "string" and fragmentData or ""
  if #records == 0 and #fragmentData == 0 and type(renderInfo) ~= "table" then return "" end
  local render = renderBytes(renderInfo)
  local parts = { "S2HX", p16(4), p16(#records), p32(tonumber(sourceBase) or 0x8FF00000),
    p32(#fragmentData), p32(#render) }
  for _, record in ipairs(records) do
    local familyId = Handlers.FAMILY_IDS[record.family] or 0
    local confidenceId = Handlers.CONFIDENCE_IDS[record.confidence] or 0
    local argument = type(record.argument) == "string" and record.argument or ""
    local semantic = semanticBytes(record)
    local row = Handlers.BY_DESCRIPTOR[record.descriptor] or record
    parts[#parts + 1] = p32(record.descriptor or 0)
    parts[#parts + 1] = p32(record.target or 0)
    parts[#parts + 1] = pi16(record.bone or -1)
    parts[#parts + 1] = pi16(record.boneId or -1)
    parts[#parts + 1] = string.char(familyId, confidenceId, phaseMask(record.phases),
      flagsFor(row, record.argOffset ~= nil))
    parts[#parts + 1] = p32(record.argOffset ~= nil and record.argOffset or 0xFFFFFFFF)
    parts[#parts + 1] = p32(record.commandOffset ~= nil and record.commandOffset or 0xFFFFFFFF)
    parts[#parts + 1] = p16(#argument)
    parts[#parts + 1] = p16(#semantic)
    parts[#parts + 1] = semantic
    parts[#parts + 1] = argument
  end
  parts[#parts + 1] = render
  parts[#parts + 1] = fragmentData
  local extension = table.concat(parts)
  return extension .. "S2HF" .. p32(#extension)
end

function Handlers.readExtension(packBytes)
  if type(packBytes) ~= "string" or #packBytes < 20 then return nil end
  local footer = #packBytes - 7
  if packBytes:sub(footer, footer + 3) ~= "S2HF" then return nil end
  local length = u32le(packBytes, footer + 3)
  if not length or length < 12 or length > footer - 1 then return nil end
  local start = footer - length
  local extension = packBytes:sub(start, footer - 1)
  if extension:sub(1, 4) ~= "S2HX" then return nil end
  local version = u16le(extension, 4)
  local count = u16le(extension, 6)
  local sourceBase = u32le(extension, 8)
  if (version ~= 1 and version ~= 2 and version ~= 3 and version ~= 4) or not count or not sourceBase then return nil end
  local fragmentLength = version >= 2 and u32le(extension, 12) or 0
  local renderLength = version >= 3 and u32le(extension, 16) or 0
  if fragmentLength == nil or renderLength == nil then return nil end
  local records, cursor = {}, version >= 3 and 20 or (version >= 2 and 16 or 12)
  for _ = 1, count do
    local fixed = version >= 3 and 28 or 22
    if cursor + fixed > #extension then return nil end
    local descriptor = u32le(extension, cursor)
    local target = u32le(extension, cursor + 4)
    local bone = i16le(extension, cursor + 8)
    local boneId = version >= 3 and i16le(extension, cursor + 10) or nil
    local field = version >= 3 and cursor + 12 or cursor + 10
    local familyId = byte(extension, field)
    local confidenceId = byte(extension, field + 1)
    local mask = byte(extension, field + 2)
    local flags = byte(extension, field + 3)
    local argOffset = u32le(extension, field + 4)
    local commandOffset = version >= 3 and u32le(extension, field + 8) or nil
    local lengths = version >= 3 and field + 12 or field + 8
    local argLength = u16le(extension, lengths)
    local semanticLength = u16le(extension, lengths + 2)
    cursor = cursor + fixed
    if cursor + semanticLength + argLength > #extension then return nil end
    local semantic = extension:sub(cursor + 1, cursor + semanticLength)
    cursor = cursor + semanticLength
    local argument = extension:sub(cursor + 1, cursor + argLength)
    cursor = cursor + argLength
    local family = Handlers.FAMILY_NAMES[familyId] or "unknown"
    local record = {
      descriptor = descriptor,
      target = target,
      bone = bone,
      boneId = boneId and boneId >= 0 and boneId or nil,
      commandOffset = commandOffset and commandOffset ~= 0xFFFFFFFF and commandOffset or nil,
      family = family,
      confidence = Handlers.CONFIDENCE_NAMES[confidenceId] or "partial",
      phases = phasesFromMask(mask),
      flags = flags,
      argOffset = argOffset ~= 0xFFFFFFFF and argOffset or nil,
      argAddress = argOffset ~= 0xFFFFFFFF and sourceBase + argOffset or nil,
      argument = argument,
      noRender = math.floor(flags / 4) % 2 == 1,
      runtimeDependent = math.floor(flags / 2) % 2 == 1,
    }
    decodeSemantic(record, semantic)
    records[#records + 1] = record
  end
  if cursor + renderLength + fragmentLength > #extension then return nil end
  local renderData = renderLength > 0 and extension:sub(cursor + 1, cursor + renderLength) or nil
  cursor = cursor + renderLength
  local fragment = fragmentLength > 0 and extension:sub(cursor + 1, cursor + fragmentLength) or nil
  return Handlers.prepare({ version = version, sourceBase = sourceBase, records = records, fragment = fragment,
    render = readRenderBytes(renderData), renderData = renderData })
end

return Handlers
