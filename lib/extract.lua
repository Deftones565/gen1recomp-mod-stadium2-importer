local Rom = require("mods.STADIUM2_IMPORTER.lib.rom")
local Fragment = require("mods.STADIUM2_IMPORTER.lib.fragment")
local Build = require("mods.STADIUM2_IMPORTER.lib.build")
local Palette = require("mods.STADIUM2_IMPORTER.lib.palette")
local Handlers = require("mods.STADIUM2_IMPORTER.lib.model_handlers")
local Layout = require("mods.STADIUM2_IMPORTER.lib.layout")
local AnimationRouting = require("mods.STADIUM2_IMPORTER.lib.animation_routing")

local Extract = {}
Extract.BASE_COUNT = 151
Extract.MAX_COUNT = 251
Extract.COUNT = 151

local ASSET_START = Rom.ASSET_START
local MODEL_TABLE_START = Rom.MODEL_TABLE_START
local POSE_TABLE_START = Rom.POSE_TABLE_START
local POSE_TABLE_END = Rom.POSE_TABLE_END
local NONE16 = 0xFFFF
local paletteByDex = {}
local standaloneShinyPalettes
local speciesIdByDex = {}

local function u16be(data, offset)
  local a, b = string.byte(data, offset + 1, offset + 2)
  if not b then return nil end
  return a * 256 + b
end

local function s16be(data, offset)
  local value = u16be(data, offset)
  if value == nil then return nil end
  if value >= 0x8000 then return value - 0x10000 end
  return value
end

local function u32be(data, offset)
  return Rom.u32(data, offset)
end

local function clamp(value, low, high)
  if value < low then return low end
  if value > high then return high end
  return value
end

local function fragmentParser(sourceBase)
  Fragment.setBase(sourceBase)
  return Fragment
end

local function normalPaletteForDex(dex)
  local ok, Game = pcall(require, "src.core.Game")
  local data = ok and Game and Game.data or nil
  local pokemon = data and data.pokemon
  local palettes = data and data.palettes
  if type(pokemon) ~= "table" or type(palettes) ~= "table" or type(palettes.palettes) ~= "table" then return nil end
  local species = speciesIdByDex[dex]
  if species == nil then
    species = false
    for id, def in pairs(pokemon) do
      if type(def) == "table" and tonumber(def.dex) == dex then species = id break end
    end
    speciesIdByDex[dex] = species
  end
  if not species then return nil end
  local def = pokemon[species]
  local name = def and def.palette
  if not name and type(palettes.pokemon) == "table" then name = palettes.pokemon[species] end
  return palettes.palettes[name or "MEWMON"]
end

local function palettePairForDex(dex)
  local pair = paletteByDex[dex]
  if pair then return pair end
  local shiny = standaloneShinyPalettes and standaloneShinyPalettes[dex]
  if not shiny then return nil end
  local normal = normalPaletteForDex(dex)
  if not normal then return nil end
  pair = { normal = normal, shiny = shiny }
  paletteByDex[dex] = pair
  return pair
end

local recolourRgba = Palette.recolour
local function rareVariation(data, species)
  local offset = Layout.SPECIES_META_START + (species - 1) * 0x10 + 4
  return Palette.decodeRare(data, offset)
end
local function md5(data)
  local ok, value = pcall(function()
    local digest = love.data.hash("md5", data)
    if type(digest) == "userdata" and digest.getString then
      digest = digest:getString()
    end
    return love.data.encode("string", "hex", digest)
  end)
  return ok and value or nil
end

local IO_CHUNK = 1024 * 1024
local WORK_BUDGET = 0.006

local function workClock()
  if love and love.timer and love.timer.getTime then
    local ok, value = pcall(love.timer.getTime)
    if ok and type(value) == "number" then return value end
  end
  return nil
end

local function romTitle(data)
  if type(data) ~= "string" or #data < 0x34 then return "" end
  local title = data:sub(0x21, 0x34):gsub("%z", ""):gsub("%s+$", "")
  return title
end

local function n64Title(header)
  if type(header) ~= "string" or #header < 0x34 then return "" end
  local magic = header:sub(1, 4)
  local mode
  if magic == "\128\055\018\064" then mode = "z64"
  elseif magic == "\055\128\064\018" then mode = "v64"
  elseif magic == "\064\018\055\128" then mode = "n64"
  else return "" end
  local out = {}
  for offset = 0x20, 0x33 do
    local source = offset
    if mode == "v64" then
      source = offset - offset % 2 + (1 - offset % 2)
    elseif mode == "n64" then
      source = offset - offset % 4 + (3 - offset % 4)
    end
    out[#out + 1] = header:sub(source + 1, source + 1)
  end
  return table.concat(out):gsub("%z", ""):gsub("%s+$", "")
end

local archiveAt = Rom.archiveAt

local function findRootPair(data)
  if type(data) ~= "string" or #data < 0x80 then return nil end
  for offset = 0x20, 0x7C, 4 do
    local first = u32be(data, offset)
    local second = u32be(data, offset + 4)
    if first and second and math.floor(first / 0x4000000) == 0x0F then
      local register = math.floor(first / 0x10000) % 0x20
      if math.floor(second / 0x4000000) == 0x09
          and math.floor(second / 0x200000) % 0x20 == register
          and math.floor(second / 0x10000) % 0x20 == register then
        local address = u16be(data, offset + 2) * 0x10000
          + s16be(data, offset + 6)
        return offset, address
      end
    end
  end
  return nil
end

local function fragmentInfo(data)
  if type(data) ~= "string" or #data < 0x80 then
    return nil, "fragment is too short"
  end
  if data:sub(9, 16) ~= "FRAGMENT" then
    return nil, "not a FRAGMENT module"
  end
  local pair, rootAddress = findRootPair(data)
  if not pair then return nil, "could not locate fragment root" end
  local sourceBase = math.floor(rootAddress / 0x100000) * 0x100000
  local rootOffset = rootAddress - sourceBase
  if rootOffset < 0 or rootOffset + 0x14 > #data then
    return nil, "fragment root is outside the module"
  end
  return {
    sourceBase = sourceBase,
    rootOffset = rootOffset,
    rootAddress = rootAddress,
    pair = pair,
  }
end

local function fragmentSpecies(data)
  local info = fragmentInfo(data)
  if not info then return nil end
  return u16be(data, info.rootOffset), info
end


local function fallbackTexture(species)
  local palettes = palettePairForDex(species)
  local colours = palettes and palettes.normal
  local colour = colours and (colours[2] or colours[3] or colours[1])
  local r, g, b = 255, 255, 255
  if type(colour) == "table" then
    r = clamp(math.floor((tonumber(colour[1]) or r) + 0.5), 0, 255)
    g = clamp(math.floor((tonumber(colour[2]) or g) + 0.5), 0, 255)
    b = clamp(math.floor((tonumber(colour[3]) or b) + 0.5), 0, 255)
  end
  return {
    index = -1,
    w = 1,
    h = 1,
    generated = true,
    stadium2Fallback = true,
    rgba = string.char(r, g, b, 255),
  }
end

local function fxCallbacks(model)
  local values, seen = {}, {}
  for _, effect in ipairs((model and model.fx) or {}) do
    local handler = tonumber(effect.handler or effect.callback or effect.cb or effect.address)
    local label = handler and ("0x%08X"):format(handler) or tostring(
      effect.handler or effect.callback or effect.cb or effect.address or "?")
    if not seen[label] then
      seen[label] = true
      values[#values + 1] = label
    end
  end
  return #values > 0 and table.concat(values, ",") or "none"
end

local function normaliseDrawableModel(model, species, Fx)
  model.bones = type(model.bones) == "table" and model.bones or {}
  model.prims = type(model.prims) == "table" and model.prims or {}
  model.textures = type(model.textures) == "table" and model.textures or {}

  local attached, attachError = 0, nil
  if Fx and type(Fx.attach) == "function" then
    local ok, value = pcall(Fx.attach, model, species)
    if ok then
      attached = tonumber(value) or 0
    else
      attachError = tostring(value)
    end
  end

  local fallbackIndex = nil
  local function ensureFallback()
    if fallbackIndex == nil then
      fallbackIndex = #model.textures 
      model.textures[#model.textures + 1] = fallbackTexture(species)
    end
    return fallbackIndex
  end

  for _, prim in ipairs(model.prims) do
    local texture = tonumber(prim.tex)
    if not texture or texture < 0 or texture >= #model.textures then
      prim.tex = ensureFallback()
      prim.texAnim = -1
      prim.texMap = nil
    elseif type(prim.texMap) == "table" then
      for key, mapped in pairs(prim.texMap) do
        mapped = tonumber(mapped)
        if not mapped or mapped < 0 or mapped >= #model.textures then
          prim.texMap[key] = ensureFallback()
        end
      end
    end
    if type(prim.fxFrames) == "table" then
      for index, mapped in ipairs(prim.fxFrames) do
        mapped = tonumber(mapped)
        if not mapped or mapped < 0 or mapped >= #model.textures then
          prim.fxFrames[index] = ensureFallback()
        end
      end
    end
  end

  local bones, prims, textures = #model.bones, #model.prims, #model.textures
  if bones == 0 or prims == 0 or textures == 0 then
    local extra = attachError and ("; effect attach error=" .. attachError) or ""
    return nil, ("species %d has no drawable geometry "
      .. "(bones=%d prims=%d textures=%d effects-added=%d callbacks=%s)%s")
      :format(species, bones, prims, textures, attached, fxCallbacks(model), extra)
  end
  return true, {
    bones = bones,
    prims = prims,
    textures = textures,
    effectsAdded = attached,
    fallbackTexture = fallbackIndex,
  }
end

local function matrixPoseSignature(matrices)
  if type(matrices) ~= "table" or #matrices == 0 then return nil end
  local loX, loY, loZ = math.huge, math.huge, math.huge
  local hiX, hiY, hiZ = -math.huge, -math.huge, -math.huge
  local maxAxis = 0
  for _, matrix in ipairs(matrices) do
    if type(matrix) ~= "table" or type(matrix[1]) ~= "table"
        or type(matrix[2]) ~= "table" or type(matrix[3]) ~= "table" then
      return nil
    end
    for row = 1, 3 do
      for column = 1, 4 do
        local value = tonumber(matrix[row][column])
        if not value or value ~= value or value == math.huge or value == -math.huge then
          return nil
        end
      end
    end
    local x, y, z = matrix[1][4], matrix[2][4], matrix[3][4]
    if x < loX then loX = x end
    if y < loY then loY = y end
    if z < loZ then loZ = z end
    if x > hiX then hiX = x end
    if y > hiY then hiY = y end
    if z > hiZ then hiZ = z end
    for column = 1, 3 do
      local a, b, c = matrix[1][column], matrix[2][column], matrix[3][column]
      local axis = math.sqrt(a * a + b * b + c * c)
      if axis > maxAxis then maxAxis = axis end
    end
  end
  local dx, dy, dz = hiX - loX, hiY - loY, hiZ - loZ
  return math.sqrt(dx * dx + dy * dy + dz * dz), maxAxis
end

local function animationLooksExplosive(data, animation, Build)
  if type(animation) ~= "table" or type(data) ~= "table" then return false end
  if type(data.bones) ~= "table" or #data.bones == 0 then return false end
  if not (Build and type(Build.bindMatrices) == "function"
      and type(Build.animSample) == "function") then
    return false
  end
  local frames = math.max(1, math.floor(tonumber(animation.frames) or 1))
  if frames > 600 then return true, "implausible frame count" end

  local okBind, bindMatrices = pcall(Build.bindMatrices, data.bones)
  if not okBind then return false end
  local bindSpread, bindAxis = matrixPoseSignature(bindMatrices)
  if not bindSpread or not bindAxis then return false end
  bindSpread = math.max(bindSpread, 1e-6)
  bindAxis = math.max(bindAxis, 1e-6)

  for frame = 0, frames - 1 do
    local okSample, sample = pcall(Build.animSample, data.bones, animation, frame)
    if not okSample then return true, "pose sample failed" end
    local okPose, matrices = pcall(Build.bindMatrices, data.bones, sample)
    if not okPose then return true, "pose matrix failed" end
    local spread, axis = matrixPoseSignature(matrices)
    if not spread or not axis then return true, "non-finite pose" end
    if spread / bindSpread > 8.0 then return true, "bone spread" end
    if axis / bindAxis > 8.0 then return true, "bone scale" end
  end
  return false
end

local function genericAnimationTable(data, Build)
  local animations = data.anims or {}
  if #animations == 0 then
    animations[1] = {
      index = 0,
      frames = 1,
      flags = 0,
      channels = 0,
      loopStart = 0,
      tracks = {},
      syntheticBindPose = true,
    }
    data.anims = animations
  end

  local sourceCount = #animations
  local idle = 0
  local attack = sourceCount > 1 and 1 or idle
  local faint = sourceCount > 2 and 2 or idle
  local entrance = sourceCount > 3 and 3 or idle

  local faintRejected, faintReason = false, nil
  if faint ~= idle then
    faintRejected, faintReason = animationLooksExplosive(data,
      animations[faint + 1], Build)
    if faintRejected then faint = idle end
  end
  data.stadium2FaintRejected = faintRejected or nil
  data.stadium2FaintRejectReason = faintRejected and faintReason or nil

  local auxiliary = data.auxAnims or {}
  AnimationRouting.apply(animations, auxiliary)
  for index, animation in ipairs(animations) do
    if index == 1 then
      animation.name = "idle"
    elseif index == 2 then
      animation.name = "attack_default"
    elseif index == 3 then
      animation.name = faintRejected and "faint_rejected" or "faint"
    elseif index == 4 then
      animation.name = "entrance"
    else
      animation.name = "anim" .. tostring(index - 1)
    end
  end

  local rows = {}
  local attackAux = animations[attack + 1] and animations[attack + 1].aux or -1
  for move = 1, 165 do rows[move] = { attack, attackAux } end
  local contexts = {}
  for index = 1, #Build.CONTEXTS do contexts[index] = NONE16 end
  contexts[1], contexts[2], contexts[3], contexts[4] = idle, attack, faint, entrance
  contexts[12], contexts[13], contexts[19], contexts[20] = idle, faint, entrance, idle
  return rows, contexts
end

local function decompressedFragment(data, record, StadiumRom)
  local blob = data:sub(record.start + 1, record.start + record.size)
  local ok, decoded, err = pcall(StadiumRom.decompress, blob)
  if not ok then return nil, tostring(decoded) end
  if type(decoded) ~= "string" then return nil, tostring(err or "decompression failed") end
  local info, infoErr = fragmentInfo(decoded)
  if not info then return nil, infoErr end
  return decoded, info
end

local function inspectFragment(data, record, StadiumRom, V, name)
  local decoded, infoOrErr = decompressedFragment(data, record, StadiumRom)
  if not decoded then return nil, infoOrErr end
  local parser = fragmentParser(infoOrErr.sourceBase)
  local inspect = parser.inspectAny or parser.inspect
  local ok, summary, summaryErr = pcall(inspect, decoded, name)
  if not ok then return nil, tostring(summary) end
  if not summary then return nil, summaryErr end
  return summary, {
    record = record,
    sourceBase = infoOrErr.sourceBase,
  }
end

local function inspectModelFragment(data, record, StadiumRom, V, name)
  local decoded, infoOrErr = decompressedFragment(data, record, StadiumRom)
  if not decoded then return nil, infoOrErr end
  local parser = fragmentParser(infoOrErr.sourceBase)
  local ok, summary, summaryErr = pcall(parser.inspect, decoded, name)
  if not ok then return nil, tostring(summary) end
  if not summary then return nil, summaryErr end
  return summary, {
    record = record,
    sourceBase = infoOrErr.sourceBase,
  }
end

local function nextArchive(data, cursor)
  cursor = cursor or ASSET_START
  if cursor <= MODEL_TABLE_START then
    local archive = archiveAt(data, MODEL_TABLE_START)
    if archive and archive.offset == MODEL_TABLE_START
        and archive.count == (Layout.MODEL_TABLE_RECORDS or 282) then
      archive.role = "model"
      return archive, MODEL_TABLE_START + 1, false
    end
    return nil, MODEL_TABLE_START + 1, false,
      ("Pokemon model table is not the expected %d-record archive at 0x%X")
        :format(Layout.MODEL_TABLE_RECORDS or 282, MODEL_TABLE_START)
  end
  if cursor <= POSE_TABLE_START then
    local archive = archiveAt(data, POSE_TABLE_START)
    if archive and archive.offset == POSE_TABLE_START
        and archive.count == (Layout.POSE_TABLE_RECORDS or 282) then
      archive.role = "pose"
      return archive, POSE_TABLE_START + 1, false
    end
    return nil, POSE_TABLE_END, true,
      ("Pokemon pose table is not the expected %d-record archive at 0x%X")
        :format(Layout.POSE_TABLE_RECORDS or 282, POSE_TABLE_START)
  end
  return nil, #data + 1, true
end


local function recordBytes(container, record)
  if type(container) ~= "string" or not record or (record.size or 0) <= 0 then
    return nil, "empty archive record"
  end
  local last = record.start + record.size
  if record.start < 0 or last > #container then return nil, "archive record is out of bounds" end
  return container:sub(record.start + 1, last)
end

local function decodedPayload(container, record, StadiumRom)
  local blob, blobErr = recordBytes(container, record)
  if not blob then return nil, blobErr end
  local ok, decoded, err = pcall(StadiumRom.decompress, blob)
  if ok and type(decoded) == "string" then return decoded end
  if archiveAt(blob, 0) or fragmentInfo(blob) then return blob end
  return nil, tostring(ok and err or decoded or "decompression failed")
end

local function applyDedicatedRareTextures(data, species, model, StadiumRom)
  local archive = archiveAt(data, Layout.POST_POSE_TABLE_START)
  local record = archive and archive.records and archive.records[species + 1]
  if not record then
    return nil, ("species %d has no dedicated rare-texture record"):format(species)
  end
  local payload, payloadErr = decodedPayload(data, record, StadiumRom)
  if not payload then return nil, payloadErr end

  local groupsByIndex = {}
  local groups = {}
  local duplicateBytes = 0
  for _, texture in ipairs(model.textures or {}) do
    local sourceIndex = tonumber(texture.index)
    if not texture.callback and sourceIndex and sourceIndex >= 0 then
      sourceIndex = math.floor(sourceIndex)
      local w = math.floor(tonumber(texture.w) or 0)
      local h = math.floor(tonumber(texture.h) or 0)
      local format = math.floor(tonumber(texture.format) or -1)
      local size = math.floor(tonumber(texture.size) or -1)
      local nativeBytes = Palette.nativeTextureBytes(w, h, size)
      if not nativeBytes then
        return nil, ("species %d source texture %d has unsupported N64 size %s")
          :format(species, sourceIndex, tostring(texture.size))
      end
      local group = groupsByIndex[sourceIndex]
      if group then
        if group.w ~= w or group.h ~= h or group.format ~= format or group.size ~= size then
          return nil, ("species %d source texture %d has inconsistent render variants")
            :format(species, sourceIndex)
        end
        duplicateBytes = duplicateBytes + nativeBytes
      else
        group = {
          index = sourceIndex, w = w, h = h, format = format, size = size,
          texels = texture.texels, nativeBytes = nativeBytes, textures = {},
        }
        groupsByIndex[sourceIndex] = group
        groups[#groups + 1] = group
      end
      group.textures[#group.textures + 1] = texture
    end
  end
  table.sort(groups, function(a, b) return a.index < b.index end)

  local expected = 0
  local metadata = {}
  for _, group in ipairs(groups) do
    expected = expected + group.nativeBytes
    metadata[#metadata + 1] = ("%d:%dx%d/f%d/s%d/b%d/t%s")
      :format(group.index, group.w, group.h, group.format, group.size,
        group.nativeBytes, tostring(group.texels))
  end
  if #payload ~= expected then
    return nil, ("species %d dedicated rare texture: native record has %d bytes; expected %d; duplicate-render-bytes=%d textures=[%s]")
      :format(species, #payload, expected, duplicateBytes, table.concat(metadata, ","))
  end

  local cursor = 1
  for _, group in ipairs(groups) do
    local last = cursor + group.nativeBytes - 1
    local raw = payload:sub(cursor, last)
    local rgba, decodeErr = Palette.decodeNativeTexture(raw, group.w, group.h,
      group.format, group.size)
    if not rgba then
      return nil, ("species %d dedicated rare texture %d: %s")
        :format(species, group.index, tostring(decodeErr))
    end
    for _, texture in ipairs(group.textures) do texture.rgba = rgba end
    cursor = last + 1
  end
  return true
end

local function archivesInPayload(payload)
  local archives, seen = {}, {}
  local function add(offset)
    if seen[offset] then return end
    local archive = archiveAt(payload, offset)
    if archive then
      seen[offset] = true
      archives[#archives + 1] = archive
      return archive
    end
  end
  local root = add(0)
  if root then return archives end
  local offset = 0x10
  while offset <= #payload - 0x10 do
    local archive = add(offset)
    if archive then offset = offset + archive.total else offset = offset + 0x10 end
  end
  return archives
end

local function inspectDecodedMotion(decoded, V, name)
  local info, infoErr = fragmentInfo(decoded)
  local parser
  if info then
    parser = fragmentParser(info.sourceBase)
    local inspect = parser.inspectAny or parser.inspect
    local ok, summary, summaryErr = pcall(inspect, decoded, name)
    if not ok then return nil, tostring(summary) end
    if not summary then return nil, summaryErr end
    if (summary.animations or 0) <= 0 and (summary.auxiliary or 0) <= 0 then
      return nil, "FRAGMENT contains no animation banks"
    end
    return {
      decoded = decoded,
      sourceBase = info.sourceBase,
      animations = summary.animations or 0,
      auxiliary = summary.auxiliary or 0,
      rootKind = summary.rootKind,
      explicitSpecies = tonumber(summary.species),
    }
  end

  parser = fragmentParser(0x8FF00000)
  local inspectRaw = parser.inspectRawAnimations
  if not inspectRaw then return nil, infoErr end
  local ok, summary, rawErr = pcall(inspectRaw, decoded, name)
  if not ok then return nil, tostring(summary) end
  if not summary then return nil, tostring(rawErr or infoErr) end
  return {
    decoded = decoded,
    sourceBase = 0x8FF00000,
    animations = summary.animations or 0,
    auxiliary = summary.auxiliary or 0,
    rootKind = summary.rootKind or "raw-pose",
    rawPose = true,
  }
end

local function collectPosePayload(payload, dependencies, label, depth, out, errors, stats)
  depth = depth or 0
  out, errors = out or {}, errors or {}
  stats = stats or { archives = 0, fragments = 0 }

  local isFragment = fragmentInfo(payload) ~= nil
  if isFragment then
    local motion, motionErr = inspectDecodedMotion(payload, dependencies.V, label)
    if motion then
      motion.path = label
      out[#out + 1] = motion
      stats.fragments = stats.fragments + 1
      return out, errors, stats
    end
    if #errors < 24 then errors[#errors + 1] = label .. ": " .. tostring(motionErr) end
    return out, errors, stats
  end

  if depth < 4 then
    local archives = archivesInPayload(payload)
    if #archives > 0 then
      for archiveIndex, archive in ipairs(archives) do
        stats.archives = stats.archives + 1
        for recordIndex, record in ipairs(archive.records) do
          if record.size > 0 then
            local child, childErr = decodedPayload(payload, record, dependencies.StadiumRom)
            local childLabel = ("%s/archive%d/file%d"):format(label, archiveIndex,
              recordIndex - 1)
            if child then
              collectPosePayload(child, dependencies, childLabel, depth + 1,
                out, errors, stats)
            elseif #errors < 24 then
              errors[#errors + 1] = childLabel .. ": " .. tostring(childErr)
            end
          end
        end
      end
      return out, errors, stats
    end
  end

  local motion, motionErr = inspectDecodedMotion(payload, dependencies.V, label)
  if motion then
    motion.path = label
    out[#out + 1] = motion
    stats.fragments = stats.fragments + 1
    return out, errors, stats
  end
  if #errors < 24 then
    errors[#errors + 1] = label .. ": "
      .. tostring(motionErr or (depth >= 4 and "nesting limit" or "no nested archive"))
  end
  return out, errors, stats
end

local function poseSourcesForRecord(data, record, dependencies, label)
  local payload, payloadErr = decodedPayload(data, record, dependencies.StadiumRom)
  if not payload then return {}, { label .. ": " .. tostring(payloadErr) },
    { archives = 0, fragments = 0 } end
  return collectPosePayload(payload, dependencies, label, 0)
end

-- FRAGMENT bytes at relocationStart..fileEnd are loader relocation records,
-- not runtime data. The loader consumes that table, then zero-initializes the
-- same address range through memoryEnd. Grimer deliberately points two
-- callback textures into this scratch/BSS region, so audits and extraction
-- must reproduce the loaded memory image rather than decode relocation words
-- as RGBA16 or append unrelated pose data.
local function runtimeModelFragment(decoded)
  if type(decoded) ~= "string" or decoded:sub(9, 16) ~= "FRAGMENT" then
    return decoded
  end
  local relocationStart = u32be(decoded, 0x14)
  local fileEnd = u32be(decoded, 0x18)
  local memoryEnd = u32be(decoded, 0x1C)
  if not relocationStart or not fileEnd or not memoryEnd
      or fileEnd ~= #decoded or relocationStart > fileEnd
      or memoryEnd < relocationStart then
    return decoded
  end
  return decoded:sub(1, relocationStart)
    .. string.rep("\0", memoryEnd - relocationStart)
end

local function appendSource(bucket, species, source)
  local list = bucket[species]
  if not list then list = {}; bucket[species] = list end
  list[#list + 1] = source
end

local function sourceLabel(source)
  if source.path then return source.path end
  return ("archive=0x%X file=%s"):format(source.archiveOffset or 0,
    tostring(source.fileIndex or "?"))
end

local function decodeAnimationSources(data, sources, bones, dependencies)
  local anims, aux = {}, {}
  local errors = {}
  for _, source in ipairs(sources or {}) do
    local decoded, infoOrErr
    if type(source.decoded) == "string" then
      decoded = source.decoded
      infoOrErr = { sourceBase = source.sourceBase }
    else
      decoded, infoOrErr = decompressedFragment(data, source.record,
        dependencies.StadiumRom)
    end
    if decoded then
      local parser = fragmentParser(infoOrErr.sourceBase)
      local extract
      if source.rawPose then
        extract = parser.extractRawAnimations
      else
        extract = parser.extractAnimationsAny or parser.extractAnimations
      end
      local debugName = source.path or ("stadium2_anim_%s_%s.bin")
        :format(tostring(source.archiveOffset or 0), tostring(source.fileIndex or 0))
      local ok, bank, bankErr = pcall(extract, decoded, bones, debugName)
      if ok and bank then
        for _, animation in ipairs(bank.anims or {}) do
          animation.index = #anims
          animation.source = sourceLabel(source)
          anims[#anims + 1] = animation
        end
        for _, animation in ipairs(bank.auxAnims or {}) do
          animation.index = #aux
          animation.source = sourceLabel(source)
          aux[#aux + 1] = animation
        end
      else
        errors[#errors + 1] = sourceLabel(source) .. ": "
          .. tostring(ok and bankErr or bank)
      end
    else
      errors[#errors + 1] = sourceLabel(source) .. ": " .. tostring(infoOrErr)
    end
  end
  return anims, aux, errors
end

local SUBSTITUTE_RECORD = 253
local UNOWN_SPECIES = 201
local UNOWN_FIRST_FORM_RECORD = 254 -- B; species record 201 is A
local UNOWN_LAST_FORM_RECORD = 278  -- Z
local UNOWN_EXTRA_FORMS = UNOWN_LAST_FORM_RECORD-UNOWN_FIRST_FORM_RECORD+1

local function unownLetter(record)
  if record<UNOWN_FIRST_FORM_RECORD or record>UNOWN_LAST_FORM_RECORD then return nil end
  return string.char(string.byte("B")+record-UNOWN_FIRST_FORM_RECORD)
end

-- Build two ordinary variant packs while allowing newer builders to reuse
-- their identical geometry/animation byte ranges. The fallback deliberately
-- preserves compatibility with test doubles and older embedded builders.
local function packVariants(Build, model, species, rows, contexts, makeShiny)
  if type(Build.packPair) == "function" then
    return Build.packPair(model, species, rows, contexts, makeShiny)
  end
  local normal = Build.pack(model, species, rows, contexts)
  if makeShiny then
    local ok, err = makeShiny()
    if ok == false or ok == nil then return nil, err or "shiny texture build failed" end
  end
  return normal, Build.pack(model, species, rows, contexts)
end

local function newBuildJob(data, dependencies, writePack, writeSpecial, options)
  options = type(options) == "table" and options or {}
  local speciesList, speciesSet = {}, {}
  if type(options.species) == "table" then
    for _, value in ipairs(options.species) do
      local species = math.floor(tonumber(value) or 0)
      if species >= 1 and species <= Extract.COUNT and not speciesSet[species] then
        speciesSet[species] = true
        speciesList[#speciesList + 1] = species
      end
    end
  else
    for species = 1, Extract.COUNT do
      speciesSet[species] = true
      speciesList[#speciesList + 1] = species
    end
  end
  local includeSpecials = options.specials ~= false
  local expectedCount = #speciesList
  local StadiumRom = dependencies.StadiumRom
  local Build = dependencies.Build
  local Fx = dependencies.Fx
  local job = {
    phase = "scan", cursor = ASSET_START,
    total = expectedCount+(includeSpecials and (1+UNOWN_EXTRA_FORMS) or 0), done = 0, species = nil,
    built = {}, builtCount = 0, failed = {}, bytes = 0,
    errorSamples = {}, modelSources = {}, animationSources = {},
    modelSpecies = 0, animatedSpecies = 0, animationClips = 0,
    motionFiles = 0, emptyPoseBundles = 0,
    nestedPoseArchives = 0, modelTableCount = 0, poseTableCount = 0,
    specialAnimationSources={},specialBuilt=not includeSpecials,
    unownModelSources={},unownAnimationSources={},unownBuilt=0,
  }

  local function countSource(bucket, species)
    if not bucket[species] then return true end
    return false
  end

  local function finish()
    if job.builtCount == expectedCount and job.specialBuilt
        and (not includeSpecials or job.unownBuilt == UNOWN_EXTRA_FORMS) then
      job.success = true
      job.animationIncomplete = (job.animatedBuilt or 0) < expectedCount
    else
      local detail = job.lastError and ("; last error: " .. job.lastError) or ""
      if job.lastScanError then detail = detail .. "; scan: " .. job.lastScanError end
      job.error = ("built %d/%d models; real animation banks=%d/%d; "
        .. "model-table-records=%d pose-table-records=%d "
        .. "indexed geometry=%d animation-species=%d motion-files=%d "
        .. "nested-pose-archives=%d empty-pose-bundles=%d substitute=%s "
        .. "unown-forms=%d/%d%s")
        :format(job.builtCount, expectedCount, job.animatedBuilt or 0,
          expectedCount, job.modelTableCount or 0, job.poseTableCount or 0,
          job.modelSpecies or 0, job.animatedSpecies or 0,
          job.motionFiles or 0, job.nestedPoseArchives or 0,
          job.emptyPoseBundles or 0,tostring(job.specialBuilt),
          job.unownBuilt or 0,includeSpecials and UNOWN_EXTRA_FORMS or 0,detail)
    end
    job.phase = "done"
    return false
  end

  function job:step()
    if self.phase == "done" then return false end

    if self.phase == "scan" then
      local archive, cursor, exhausted, scanErr = nextArchive(data, self.cursor)
      self.cursor = cursor
      if archive then
        self.archive = archive
        self.archiveRole = archive.role
        self.archiveOffset = archive.offset
        if archive.role == "model" then self.modelTableCount = archive.count
        elseif archive.role == "pose" then self.poseTableCount = archive.count end
        self.phase = "index"
        self.index = 1
        self.archives = (self.archives or 0) + 1
        return true
      end
      if scanErr then self.lastScanError = scanErr end
      if exhausted then
        self.phase = "build"
        self.speciesIndex = 1
        self.animatedBuilt = 0
        return true
      end
      return true
    end

    if self.phase == "index" then
      local record = self.archive.records[self.index]
      if not record then
        self.archive = nil
        self.archiveRole = nil
        self.index = nil
        self.phase = "scan"
        return true
      end
      local fileIndex = self.index - 1
      self.fileIndex = fileIndex
      self.index = self.index + 1
      if self.archiveRole == "model" and fileIndex >= 1
          and fileIndex <= Extract.COUNT and speciesSet[fileIndex] then
        local species = fileIndex
        local summary, sourceOrErr = inspectModelFragment(data, record, StadiumRom,
          dependencies.V, ("stadium2_model_index_%d.bin"):format(fileIndex))
        if summary and tonumber(summary.species) == species and (summary.geometry or 0) > 0 then
          local source = sourceOrErr
          source.archiveOffset = self.archiveOffset
          source.fileIndex = fileIndex
          source.geometry = summary.geometry or 0
          if countSource(self.modelSources, species) then
            self.modelSpecies = self.modelSpecies + 1
          end
          appendSource(self.modelSources, species, source)
        elseif #self.errorSamples < 12 then
          self.errorSamples[#self.errorSamples + 1] = {
            archive = self.archiveOffset, file = fileIndex,
            reason = summary and ("fragment species mismatch: expected %d got %s")
              :format(species, tostring(summary.species)) or tostring(sourceOrErr),
          }
        end
      elseif includeSpecials and self.archiveRole=="model" and fileIndex==SUBSTITUTE_RECORD then
        local summary,sourceOrErr=inspectModelFragment(data,record,StadiumRom,
          dependencies.V,"stadium2_substitute.bin")
        if summary and tonumber(summary.species)==SUBSTITUTE_RECORD
            and (summary.geometry or 0)>0 then
          self.specialModelSource=sourceOrErr
          self.specialModelSource.archiveOffset=self.archiveOffset
          self.specialModelSource.fileIndex=fileIndex
        else
          self.lastError="substitute model record: "..tostring(sourceOrErr)
        end
      elseif includeSpecials and self.archiveRole=="model" and fileIndex>=UNOWN_FIRST_FORM_RECORD
          and fileIndex<=UNOWN_LAST_FORM_RECORD then
        local summary,sourceOrErr=inspectModelFragment(data,record,StadiumRom,
          dependencies.V,("stadium2_unown_%s.bin"):format(unownLetter(fileIndex)))
        if summary and tonumber(summary.species)==fileIndex
            and (summary.geometry or 0)>0 then
          sourceOrErr.archiveOffset=self.archiveOffset
          sourceOrErr.fileIndex=fileIndex
          self.unownModelSources[fileIndex]=sourceOrErr
        else
          self.lastError=("Unown %s model record: %s")
            :format(tostring(unownLetter(fileIndex)),tostring(sourceOrErr))
        end
      elseif self.archiveRole == "pose" and fileIndex >= 1
          and fileIndex <= Extract.COUNT and speciesSet[fileIndex] then
        local species = fileIndex
        local label = ("pose-table=0x%X species=%d file=%d")
          :format(self.archiveOffset, species, fileIndex)
        local sources, poseErrors, poseStats = poseSourcesForRecord(data, record,
          dependencies, label)
        self.nestedPoseArchives = self.nestedPoseArchives
          + (poseStats.archives or 0)
        if #sources > 0 then
          if countSource(self.animationSources, species) then
            self.animatedSpecies = self.animatedSpecies + 1
          end
          for _, source in ipairs(sources) do
            source.archiveOffset = self.archiveOffset
            source.fileIndex = fileIndex
            appendSource(self.animationSources, species, source)
            self.motionFiles = self.motionFiles + 1
            self.animationClips = self.animationClips + (source.animations or 0)
          end
        else
          self.emptyPoseBundles = self.emptyPoseBundles + 1
          if #self.errorSamples < 12 then
            self.errorSamples[#self.errorSamples + 1] = {
              archive = self.archiveOffset, file = fileIndex,
              reason = table.concat(poseErrors or {}, " | "),
            }
          end
        end
      elseif includeSpecials and self.archiveRole=="pose" and fileIndex==SUBSTITUTE_RECORD then
        local label=("pose-table=0x%X substitute file=%d")
          :format(self.archiveOffset,fileIndex)
        local sources,poseErrors=poseSourcesForRecord(data,record,dependencies,label)
        self.specialAnimationSources=sources or {}
        if #self.specialAnimationSources==0 then
          self.lastAnimationError=table.concat(poseErrors or {}," | ")
        end
      elseif includeSpecials and self.archiveRole=="pose" and fileIndex>=UNOWN_FIRST_FORM_RECORD
          and fileIndex<=UNOWN_LAST_FORM_RECORD then
        local label=("pose-table=0x%X Unown %s file=%d")
          :format(self.archiveOffset,unownLetter(fileIndex),fileIndex)
        local sources,poseErrors=poseSourcesForRecord(data,record,dependencies,label)
        self.unownAnimationSources[fileIndex]=sources or {}
        if #self.unownAnimationSources[fileIndex]==0 then
          self.lastAnimationError=table.concat(poseErrors or {}," | ")
        end
      end
      return true
    end

    if self.specialWorker then
      local ok,result,reason=coroutine.resume(self.specialWorker)
      if ok and coroutine.status(self.specialWorker)~="dead" then
        self.buildStage=result
        return true
      end
      self.specialWorker=nil
      self.buildStage=nil
      if not ok then reason,result=result,nil end
      if result then
        if result.kind=="substitute" then self.specialBuilt=true
        elseif result.kind=="unown" then self.unownBuilt=self.unownBuilt+1 end
        self.specialBytes=(self.specialBytes or 0)+(result.bytes or 0)
        self.done=self.builtCount+(self.specialBuilt and 1 or 0)+self.unownBuilt
      else
        self.lastError=tostring(reason or "unknown special-model build error")
      end
      return true
    end

    if self.speciesWorker then
      local modelSource = self.speciesModelSource
      local species = self.species
      local ok, result, reason = coroutine.resume(self.speciesWorker)
      if ok and coroutine.status(self.speciesWorker) ~= "dead" then
        self.buildStage = result
        return true
      end
      self.speciesWorker = nil
      self.speciesModelSource = nil
      self.buildStage = nil
      if not ok then reason, result = result, nil end
      if result then
        self.built[result.species] = true
        self.builtCount = self.builtCount + 1
        if (result.animations or 0) > 0 then
          self.animatedBuilt = self.animatedBuilt + 1
        else
          self.fallbackBuilt = (self.fallbackBuilt or 0) + 1
          if result.animationError then self.lastAnimationError = result.animationError end
        end
        self.done = self.builtCount
        self.bytes = self.bytes + result.bytes
        self.lastAnimationCount = result.animations
      else
        self.failed[#self.failed + 1] = species
        self.lastError = tostring(reason or "unknown Stadium 2 build error")
        if #self.errorSamples < 12 then
          self.errorSamples[#self.errorSamples + 1] = {
            archive = modelSource.archiveOffset,
            file = modelSource.fileIndex,
            reason = self.lastError,
          }
        end
      end
      return true
    end

    local species = speciesList[self.speciesIndex]
    if not species then
      if not includeSpecials then return finish() end
      if not self.specialQueue then
        self.specialQueue={{kind="substitute",record=SUBSTITUTE_RECORD,
          name="substitute",source=self.specialModelSource,
          animations=self.specialAnimationSources}}
        for record=UNOWN_FIRST_FORM_RECORD,UNOWN_LAST_FORM_RECORD do
          local letter=unownLetter(record):lower()
          self.specialQueue[#self.specialQueue+1]={kind="unown",record=record,
            name="unown_"..letter,source=self.unownModelSources[record],
            animations=self.unownAnimationSources[record]}
        end
        self.specialIndex=1
      end
      local special=self.specialQueue[self.specialIndex]
      if not special then return finish() end
      self.specialIndex=self.specialIndex+1
      local source=special.source
      if not source then
        self.lastError=("Stadium 2 model-table record %d (%s) is missing")
          :format(special.record,special.name)
        return true
      end
      self.specialWorker=coroutine.create(function()
        local decoded,infoOrErr=decompressedFragment(data,source.record,StadiumRom)
        if not decoded then return nil,infoOrErr end
        local runtimeDecoded=runtimeModelFragment(decoded)
        local parser=fragmentParser(infoOrErr.sourceBase)
        local model,extractErr=parser.extract(runtimeDecoded,"stadium2_"..special.name..".bin")
        if not model then return nil,extractErr end
        model.species=special.record
        model.handlerOps=Handlers.compile(model.fx,runtimeDecoded,infoOrErr.sourceBase)
        model.handlerSourceBase=infoOrErr.sourceBase
        model.handlerFragment=runtimeDecoded
        local drawable,drawableErr=normaliseDrawableModel(model,
          special.record,dependencies.Fx)
        if not drawable then return nil,drawableErr end
        coroutine.yield(special.name.."-model")
        local animations,auxiliary=decodeAnimationSources(data,
          special.animations,model.bones,dependencies)
        model.anims=animations
        if #auxiliary>0 then model.auxAnims=auxiliary end
        local rows,contexts,animationErr=genericAnimationTable(model,dependencies.Build)
        if not rows then return nil,animationErr end
        local bytes,shinyBytes
        if special.kind=="unown" then
          local rare=rareVariation(data,UNOWN_SPECIES)
          bytes,shinyBytes=packVariants(dependencies.Build,model,special.record,
            rows,contexts,function()
              if rare and not rare.specialTexture then
                for _,texture in ipairs(model.textures) do
                  texture.rgba=Palette.applyRare(texture.rgba,rare)
                end
              end
              return true
            end)
          if not bytes then return nil,shinyBytes end
        else
          bytes=dependencies.Build.pack(model,special.record,rows,contexts)
        end
        coroutine.yield(special.name.."-pack")
        if type(writeSpecial)~="function" then
          return nil,"special pack writer unavailable"
        end
        local wrote,writeErr=writeSpecial(special.name,bytes)
        if not wrote then return nil,writeErr end
        local byteCount=#bytes
        if special.kind=="unown" then
          coroutine.yield(special.name.."-shiny-pack")
          local shinyWrote,shinyErr=writeSpecial(special.name.."_shiny",shinyBytes)
          if not shinyWrote then return nil,shinyErr end
          byteCount=byteCount+#shinyBytes
        end
        return {bytes=byteCount,kind=special.kind}
      end)
      return true
    end
    self.speciesIndex = self.speciesIndex + 1
    self.species = species

    local modelSource = self.modelSources[species]
      and self.modelSources[species][1]
    if not modelSource then
      self.lastError = ("species %d has no geometry source"):format(species)
      self.failed[#self.failed + 1] = species
      return true
    end

    self.speciesModelSource = modelSource
    self.speciesWorker = coroutine.create(function()
      local decoded, infoOrErr = decompressedFragment(data, modelSource.record,
        StadiumRom)
      if not decoded then return nil, infoOrErr end
      local runtimeDecoded = runtimeModelFragment(decoded)
      local parser = fragmentParser(infoOrErr.sourceBase)
      local model, extractErr = parser.extract(runtimeDecoded,
        ("stadium2_model_%d.bin"):format(species))
      if not model then return nil, extractErr end
      model.species = species
      model.handlerOps = Handlers.compile(model.fx, runtimeDecoded,
        infoOrErr.sourceBase)
      model.handlerSourceBase = infoOrErr.sourceBase
      model.handlerFragment = runtimeDecoded
      local drawable, drawableErr = normaliseDrawableModel(model, species, Fx)
      if not drawable then return nil, drawableErr end
      coroutine.yield("model")

      local animations, auxiliary, animationErrors = decodeAnimationSources(data,
        self.animationSources[species], model.bones, dependencies)
      local realAnimationCount = #animations
      model.anims = animations
      if #auxiliary > 0 then model.auxAnims = auxiliary end
      if realAnimationCount == 0 then
        model.stadium2AnimationFallback = true
        model.stadium2AnimationError = #animationErrors > 0
          and table.concat(animationErrors, " | ")
          or "no decodable Stadium 2 skeletal animation record"
      end
      local rows, contexts, animationErr = genericAnimationTable(model, Build)
      if not rows then return nil, animationErr end
      coroutine.yield("animations")

      local rare = rareVariation(data, species)
      local normalBytes, shinyBytes = packVariants(Build, model, species, rows,
        contexts, function()
          if rare then
            if rare.specialTexture then
              local applied, rareErr = applyDedicatedRareTextures(
                data, species, model, StadiumRom)
              if not applied then return nil, rareErr end
            else
              for _, texture in ipairs(model.textures) do
                texture.rgba = Palette.applyRare(texture.rgba, rare)
              end
            end
          end
          return true
        end)
      if not normalBytes then return nil, shinyBytes end
      coroutine.yield("normal")
      coroutine.yield("shiny")
      local wrote, writeErr = writePack(species, normalBytes, shinyBytes)
      if not wrote then return nil, writeErr end
      return {
        species = species,
        bytes = #normalBytes + #shinyBytes,
        animations = realAnimationCount,
        fallback = realAnimationCount == 0,
        animationError = model.stadium2AnimationError,
      }
    end)
    return true
  end

  function job:progress()
    if self.phase == "scan" then
      local position = self.cursor or ASSET_START
      local span = math.max(1, POSE_TABLE_START - MODEL_TABLE_START)
      return 0.25 * math.min(1,
        math.max(0, position - MODEL_TABLE_START) / span)
    elseif self.phase == "index" then
      local indexed = (self.index or 1) - 1
      local count = self.archive and self.archive.count or 1
      return 0.25 + 0.10 * math.min(1, indexed / math.max(1, count))
    elseif self.phase == "build" then
      return 0.35 + 0.65 * (self.done / self.total)
    end
    return self.success and 1 or (self.done / self.total)
  end

  return job
end


function Extract.configure(options)
  options = type(options) == "table" and options or {}
  local requested = math.floor(tonumber(options.count) or Extract.COUNT)
  if requested < Extract.BASE_COUNT then requested = Extract.BASE_COUNT end
  if requested > Extract.MAX_COUNT then requested = Extract.MAX_COUNT end
  Extract.COUNT = math.max(Extract.COUNT, requested)
  if type(options.shinyPalettes) == "table" then
    standaloneShinyPalettes = options.shinyPalettes
    speciesIdByDex = {}
  end
  if type(options.palettePairs)=="table" then
    for rawDex,pair in pairs(options.palettePairs) do
      local dex=tonumber(rawDex)
      if dex and type(pair)=="table" and type(pair.normal)=="table"
          and type(pair.shiny)=="table" then
        paletteByDex[dex]={normal=pair.normal,shiny=pair.shiny}
      end
    end
  end
  local species = options.cache and options.cache.species
  if type(species) == "table" then
    for _, row in ipairs(species) do
      if row.dex and row.paletteColors and row.shinyPaletteColors then
        paletteByDex[row.dex] = { normal = row.paletteColors, shiny = row.shinyPaletteColors }
      end
    end
  end
  return Extract
end

function Extract.newJob(data, writePack, writeSpecial, options)
  return newBuildJob(data, { StadiumRom = Rom, Build = Build, Fx = nil },
    writePack,writeSpecial or function() return true end,options)
end

-- Read the authored pose bundle without running the cache-writing build job.
-- Audits and inspection tools need the same nested-archive traversal as the
-- importer so model completeness includes skeletal/auxiliary animation data.
function Extract.animationBankForSpecies(data, species, bones)
  species = math.floor(tonumber(species) or 0)
  local archive = archiveAt(data, POSE_TABLE_START)
  local record = archive and archive.records and archive.records[species + 1]
  if not record then return nil, nil, { "missing pose-table record" } end
  local label = ("pose-table=0x%X species=%d file=%d")
    :format(POSE_TABLE_START, species, species)
  local dependencies = { StadiumRom = Rom }
  local sources, errors, stats = poseSourcesForRecord(data, record, dependencies, label)
  local anims, aux, decodeErrors = decodeAnimationSources(data, sources, bones or {}, dependencies)
  for _, value in ipairs(decodeErrors or {}) do errors[#errors + 1] = value end
  return anims, aux, errors, stats
end

-- Audit/inspection entry point for recreating the same contiguous model+pose
-- memory image used by the importer and by the original game.
function Extract.runtimeFragmentForSpecies(data, species, decoded)
  return runtimeModelFragment(decoded), {}, nil
end

Extract.runtimeModelFragment = runtimeModelFragment

Extract.fragmentInfo = fragmentInfo
Extract.fragmentSpecies = fragmentSpecies
Extract.archiveAt = archiveAt
Extract.MODEL_TABLE_START = MODEL_TABLE_START
Extract.POSE_TABLE_START = POSE_TABLE_START
Extract.POSE_TABLE_END = POSE_TABLE_END
Extract.UNOWN_FORM_FIRST = UNOWN_FIRST_FORM_RECORD
Extract.UNOWN_FORM_LAST = UNOWN_LAST_FORM_RECORD
Extract.UNOWN_EXTRA_FORMS = UNOWN_EXTRA_FORMS
Extract.unownLetter = unownLetter

return Extract
