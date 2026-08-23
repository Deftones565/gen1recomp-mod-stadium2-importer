-- Stadium 2's 0x81000140 callback renders model-owned geometry during phase 5.
-- Its first argument selects a texture through the same descriptor consumed by
-- func_8100124C.  Keep that ABI decoding here instead of teaching individual
-- species or the renderer about fragment pointers.
local Phase5Geometry = {}

local function byte(data, offset)
  return type(data) == "string" and string.byte(data, offset + 1) or nil
end

local function u16be(data, offset)
  local a, b = byte(data, offset), byte(data, offset + 1)
  if not b then return nil end
  return a * 256 + b
end

local function s16be(data, offset)
  local value = u16be(data, offset)
  if value and value >= 0x8000 then return value - 0x10000 end
  return value
end

local function u32be(data, offset)
  local a, b, c, d = byte(data, offset), byte(data, offset + 1),
    byte(data, offset + 2), byte(data, offset + 3)
  if not d then return nil end
  return ((a * 256 + b) * 256 + c) * 256 + d
end

local function pointerOffset(data, base, pointer, length)
  local offset = tonumber(pointer) and pointer - base or -1
  length = math.max(1, tonumber(length) or 1)
  if offset < 0 or offset + length > #data then return nil end
  return offset
end

-- Mirrors the non-animated entry path through func_81001F14:
-- arg[0] -> render item, item[0] -> image config, image config[0] -> texels,
-- image config[8] -> the 12-byte format/sampler/size descriptor.
local function textureSpec(fragment, base, item, pointerOverride)
  local field = 0
  local config = pointerOffset(fragment, base, u32be(fragment, item + field), 12)
  local pointer = pointerOverride or (config and u32be(fragment, config) or nil)
  local descriptor = config and pointerOffset(fragment, base,
    u32be(fragment, config + 8), 12) or nil
  if not descriptor or not pointerOffset(fragment, base, pointer, 1) then return nil end
  local format, size = byte(fragment, descriptor), byte(fragment, descriptor + 1)
  local width, height = u16be(fragment, descriptor + 8), u16be(fragment, descriptor + 10)
  if not format or not size or not width or not height or width < 1 or height < 1 then return nil end
  return {
    pointer = pointer, w = width, h = height, format = format, size = size,
    sampler = {
      cms = byte(fragment, descriptor + 2), cmt = byte(fragment, descriptor + 3),
      masks = byte(fragment, descriptor + 4), maskt = byte(fragment, descriptor + 5),
      shifts = byte(fragment, descriptor + 6), shiftt = byte(fragment, descriptor + 7),
    },
    descriptorOffset = descriptor,
  }
end

local function trackSpec(fragment, base, pointer)
  local offset = pointerOffset(fragment, base, pointer, 20)
  if not offset then return nil end
  local kind, frames, keys = s16be(fragment, offset), s16be(fragment, offset + 2),
    s16be(fragment, offset + 4)
  if not kind or not frames or frames <= 0 then return nil end
  local spec = {
    kind = kind, frames = frames, keys = keys or 0,
    timingPointer = u32be(fragment, offset + 8),
    primitivePointer = u32be(fragment, offset + 12),
    environmentPointer = u32be(fragment, offset + 16),
    offset = offset,
  }
  local valueCount = kind == 0 and frames or spec.keys
  local timing = pointerOffset(fragment, base, spec.timingPointer,
    math.max(1, valueCount * 2))
  local primitive = pointerOffset(fragment, base, spec.primitivePointer,
    math.max(1, valueCount * 5))
  local environment = pointerOffset(fragment, base, spec.environmentPointer,
    math.max(1, valueCount * 4))
  if valueCount > 0 and valueCount <= 0x1000 then
    spec.times, spec.primitiveValues, spec.environmentValues = {}, {}, {}
    for index = 0, valueCount - 1 do
      if timing then spec.times[index + 1] = s16be(fragment, timing + index * 2) end
      if primitive then
        local value = {}
        for channel = 0, 4 do value[channel + 1] = byte(fragment, primitive + index * 5 + channel) end
        spec.primitiveValues[index + 1] = value
      end
      if environment then
        local value = {}
        for channel = 0, 3 do value[channel + 1] = byte(fragment, environment + index * 4 + channel) end
        spec.environmentValues[index + 1] = value
      end
    end
  end
  return spec
end

local function itemControllerSpec(fragment, base, item)
  local controller = pointerOffset(fragment, base, u32be(fragment, item + 4), 16)
  if not controller then return nil end
  local period, mode = s16be(fragment, controller), s16be(fragment, controller + 2)
  if not period or period == 0 or not mode then return nil end
  local textureTable = pointerOffset(fragment, base,
    u32be(fragment, controller + 12), 8)
  local texturePointers = {}
  if textureTable then
    local count = u32be(fragment, textureTable) or 0
    local pointers = pointerOffset(fragment, base,
      u32be(fragment, textureTable + 4), math.max(1, count * 4))
    if count > 0 and count <= 0x1000 and pointers then
      for index = 0, count - 1 do
        local pointer = u32be(fragment, pointers + index * 4)
        if pointerOffset(fragment, base, pointer, 1) then
          texturePointers[#texturePointers + 1] = pointer
        end
      end
    end
  end
  local tileOffset = pointerOffset(fragment, base,
    u32be(fragment, controller + 4), 12)
  local tileScroll
  if tileOffset then
    -- func_81001F14 passes these six halfwords to func_810001D4 (TEXEL0)
    -- or func_81000248 (TEXEL1). The first four are the tile origin and its
    -- per-frame delta. RDP tile origins use 10.2 fixed-point coordinates.
    tileScroll = {
      baseS = s16be(fragment, tileOffset),
      baseT = s16be(fragment, tileOffset + 2),
      speedS = s16be(fragment, tileOffset + 4),
      speedT = s16be(fragment, tileOffset + 6),
      width = u16be(fragment, tileOffset + 8),
      height = u16be(fragment, tileOffset + 10),
      offset = tileOffset,
    }
  end
  return {
    period = math.abs(period), mode = mode, offset = controller,
    colorTrack = trackSpec(fragment, base, u32be(fragment, controller + 8)),
    texturePointers = texturePointers,
    tileScroll = tileScroll,
  }
end

function Phase5Geometry.controllerSpec(fragment, sourceBase, argumentOffset)
  if type(fragment) ~= "string" or type(argumentOffset) ~= "number" then return nil end
  local base = tonumber(sourceBase) or 0x8FF00000
  local out = { items = {} }
  for argument = 0, 4, 4 do
    local item = pointerOffset(fragment, base,
      u32be(fragment, argumentOffset + argument), 20)
    if item then
      local staticTexture = textureSpec(fragment, base, item)
      out.items[#out.items + 1] = {
        itemOffset = item,
        textureUnit = argument == 0 and 0 or 1,
        texturePointer = staticTexture and staticTexture.pointer or nil,
        textureWidth = staticTexture and staticTexture.w or nil,
        textureHeight = staticTexture and staticTexture.h or nil,
        sampler = staticTexture and staticTexture.sampler or nil,
        controller = itemControllerSpec(fragment, base, item),
      }
    end
  end
  local first = out.items[1]
  out.colorController = first and first.controller or nil
  return #out.items > 0 and out or nil
end

local function controllerFrame(controller, frame, count)
  count = math.max(1, math.floor(tonumber(count) or 1))
  local index = math.floor(math.max(0, tonumber(frame) or 0)
    / math.max(1, tonumber(controller and controller.period) or 1))
  if controller and controller.mode == 1 then return math.min(index, count - 1) end
  return index % count
end

local function roundedByte(value)
  value = math.max(0, math.min(255, tonumber(value) or 0))
  -- The source uses MIPS cvt.w.s. Arena tracks are positive; nearest integer
  -- is the intended result and the half-way cases in these tracks are even.
  return math.floor(value + 0.5)
end

local function linearValue(track, values, frame)
  local count = math.min(track.keys or 0, #(track.times or {}), #(values or {}))
  if count < 2 then return values and values[1] end
  local interval = count - 1
  for index = 1, count - 1 do
    if frame >= track.times[index] and frame < track.times[index + 1] then
      interval = index
      break
    end
  end
  local x0, x1 = track.times[interval], track.times[interval + 1]
  local first, second = values[interval], values[interval + 1]
  if not first or not second then return first or second end
  local out = {}
  for channel = 1, #first do
    if frame == x0 or x1 == x0 then out[channel] = first[channel]
    else
      out[channel] = roundedByte(first[channel]
        + (second[channel] - first[channel]) * (frame - x0) / (x1 - x0))
    end
  end
  return out
end

local function polynomialValue(track, values, frame)
  local count = math.min(track.keys or 0, #(track.times or {}), #(values or {}))
  if count < 2 then return values and values[1] end
  local out = {}
  frame = frame % 256
  for channel = 1, #(values[1] or {}) do
    local total = 0
    for i = 1, count do
      local xi = track.times[i] % 256
      local weight = 1
      for j = 1, count do
        if i ~= j then
          local xj = track.times[j] % 256
          local denominator = xi - xj
          if denominator == 0 then weight = 0; break end
          weight = weight * (frame - xj) / denominator
        end
      end
      total = total + (values[i][channel] or 0) * weight
    end
    out[channel] = roundedByte(total)
  end
  return out
end

local function trackValue(track, values, frame)
  if not track or type(values) ~= "table" or #values == 0 then return nil end
  if track.kind == 0 then return values[frame % #values + 1] end
  if track.kind == 1 then return linearValue(track, values, frame) end
  if track.kind == 2 then return polynomialValue(track, values, frame) end
  return nil
end

function Phase5Geometry.evaluateController(spec, material, frame)
  if type(spec) ~= "table" then return material, {} end
  local evaluated = material
  local controller = spec.colorController
  local track = controller and controller.colorTrack
  if track then
    local trackFrame = controllerFrame(controller, frame, track.frames)
    local primitive = trackValue(track, track.primitiveValues, trackFrame)
    local environment = trackValue(track, track.environmentValues, trackFrame)
    if primitive or environment then
      evaluated = {}
      for key, value in pairs(material or {}) do evaluated[key] = value end
      if primitive then
        evaluated.primitiveColor = {
          (primitive[1] or 255) / 255, (primitive[2] or 255) / 255,
          (primitive[3] or 255) / 255, (primitive[4] or 255) / 255,
        }
        evaluated.primitiveLodFraction = (primitive[5] or 0) / 255
      end
      if environment then
        evaluated.environmentColor = {
          (environment[1] or 255) / 255, (environment[2] or 255) / 255,
          (environment[3] or 255) / 255, (environment[4] or 255) / 255,
        }
      end
      evaluated.phase5ControllerFrame = trackFrame
    end
  end
  local selected, scrolls = {}, {}
  for _, item in ipairs(spec.items or {}) do
    local itemController = item.controller
    local pointers = itemController and itemController.texturePointers or {}
    selected[item.textureUnit + 1] = #pointers > 0
      and pointers[controllerFrame(itemController, frame, #pointers) + 1]
      or item.texturePointer
    local tile = itemController and itemController.tileScroll
    if tile then
      -- The source counter is an unsigned byte at model-context +0x7F.
      local counter = math.floor(math.max(0, tonumber(frame) or 0)) % 256
      local tileFrame = math.floor(counter
        / math.max(1, tonumber(itemController.period) or 1))
      local width = math.max(1, tonumber(item.textureWidth) or tile.width or 1)
      local height = math.max(1, tonumber(item.textureHeight) or tile.height or 1)
      scrolls[item.textureUnit + 1] = {
        (tile.baseS + tile.speedS * tileFrame) / (4 * width),
        (tile.baseT - tile.speedT * tileFrame) / (4 * height),
      }
    end
  end
  return evaluated, selected, scrolls
end

function Phase5Geometry.textureSpecs(fragment, sourceBase, argumentOffset)
  if type(fragment) ~= "string" or type(argumentOffset) ~= "number" then return {} end
  local base = tonumber(sourceBase) or 0x8FF00000
  local out = {}
  -- func_810024E0 receives an argument containing two independent item
  -- pointers. It submits arg[0] first and, when arg[1] is present, submits
  -- that item as TEXEL1. item+0x10 is a dynamic environment-colour track,
  -- not another image config.
  for argument = 0, 4, 4 do
    local item = pointerOffset(fragment, base,
      u32be(fragment, argumentOffset + argument), 20)
    local controller = item and itemControllerSpec(fragment, base, item) or nil
    local pointers = controller and controller.texturePointers or {}
    local function append(pointer, frame, animated)
      local spec = item and textureSpec(fragment, base, item, pointer) or nil
      if spec then
        spec.phase5Texture = argument == 0 and 0 or 1
        spec.phase5Frame = frame
        spec.phase5Animated = animated
        out[#out + 1] = spec
      end
    end
    if #pointers == 0 then
      append(nil, 0, false)
    else
      for frame, pointer in ipairs(pointers) do append(pointer, frame - 1, true) end
    end
  end
  return out
end

local function colorAt(fragment, base, pointer, alphaOverride)
  local offset = pointerOffset(fragment, base, pointer, 4)
  if not offset then return nil end
  return {
    byte(fragment, offset) / 255,
    byte(fragment, offset + 1) / 255,
    byte(fragment, offset + 2) / 255,
    alphaOverride or byte(fragment, offset + 3) / 255,
  }
end

-- Mode 1 in func_810024E0 sources RGB from the callback color block and the
-- live model alpha. Mode 2, used by Stadium fields, submits all four authored
-- color bytes directly. Battle/field fades remain applied later through
-- sceneTint, independently of the source material alpha.
function Phase5Geometry.materialSpec(fragment, sourceBase, argumentOffset, submissionMode)
  if type(fragment) ~= "string" or type(argumentOffset) ~= "number" then return nil end
  local base = tonumber(sourceBase) or 0x8FF00000
  local item = pointerOffset(fragment, base, u32be(fragment, argumentOffset), 16)
  local colors = item and pointerOffset(fragment, base, u32be(fragment, item + 8), 12) or nil
  if not colors then return nil end
  submissionMode = tonumber(submissionMode) or 1
  local primitive = colorAt(fragment, base, u32be(fragment, colors + 4),
    submissionMode == 1 and 1 or nil)
  local primitiveOffset = pointerOffset(fragment, base, u32be(fragment, colors + 4), 5)
  local environment = colorAt(fragment, base, u32be(fragment, colors + 8))
  local combinerOffset = pointerOffset(fragment, base, u32be(fragment, colors), 16)
  local combiner
  if combinerOffset then
    local mux = {}
    for index = 0, 15 do mux[index + 1] = byte(fragment, combinerOffset + index) end
    -- func_810020E0 packs these sixteen selectors into gDPSetCombineLERP.
    -- Preserve the ROM's two cycle equations instead of approximating them
    -- as texture * primitive colour.
    combiner = {
      color0 = { mux[1], mux[2], mux[3], mux[4] },
      alpha0 = { mux[5], mux[6], mux[7], mux[8] },
      color1 = { mux[9], mux[10], mux[11], mux[12] },
      alpha1 = { mux[13], mux[14], mux[15], mux[16] },
      selectors = mux,
      offset = combinerOffset,
    }
    local function colorZero(selector, role)
      if role == 3 then return selector == 31 or selector == 7 end
      return selector == 31 or selector >= 7
    end
    local function alphaZero(selector) return selector == 7 or selector == 31 end
    combiner.cycles = colorZero(combiner.color1[1], 1)
      and colorZero(combiner.color1[2], 2)
      and colorZero(combiner.color1[3], 3)
      and colorZero(combiner.color1[4], 4)
      and alphaZero(combiner.alpha1[1]) and alphaZero(combiner.alpha1[2])
      and alphaZero(combiner.alpha1[3]) and alphaZero(combiner.alpha1[4])
      and 1 or 2
    local finalAlpha = combiner.cycles == 1 and combiner.alpha0
      or combiner.alpha1
    -- Opaque field submissions commonly leave the combiner's alpha equation
    -- as (0 - 0) * 0 + 0. The N64 opaque blender ignores that value and still
    -- writes RGB; a host alpha blend would instead discard the entire surface.
    -- Retain this fact separately from the colour-cycle classification so the
    -- renderer can restore texture/vertex coverage only for opaque/cutout
    -- queues. Translucent and shadow queues must keep the authored equation.
    combiner.alphaOutputZero = alphaZero(finalAlpha[1])
      and alphaZero(finalAlpha[2]) and alphaZero(finalAlpha[3])
      and alphaZero(finalAlpha[4])
    local function uses(eq, selector)
      return eq[1] == selector or eq[2] == selector
        or eq[3] == selector or eq[4] == selector
    end
    combiner.alphaUsesPrimitive = uses(finalAlpha, 3)
      or (combiner.cycles == 2 and uses(finalAlpha, 0)
        and uses(combiner.alpha0, 3))
    combiner.coverage = colorZero(combiner.color1[1], 1)
      and colorZero(combiner.color1[2], 2)
      and colorZero(combiner.color1[3], 3)
      and colorZero(combiner.color1[4], 4)
  end
  if not primitive and not environment and not combiner then return nil end
  return {
    primitiveColor = primitive or { 1, 1, 1, 1 },
    environmentColor = environment or { 1, 1, 1, 1 },
    phase5 = true,
    combiner = combiner,
    primitiveLodFraction = primitiveOffset and byte(fragment, primitiveOffset + 4) / 255 or 0,
    submissionMode = submissionMode,
  }
end

function Phase5Geometry.stateSpec(fragment, sourceBase, argumentOffset)
  if type(fragment) ~= "string" or type(argumentOffset) ~= "number" then return nil end
  local base = tonumber(sourceBase) or 0x8FF00000
  local item = pointerOffset(fragment, base, u32be(fragment, argumentOffset), 16)
  local state = item and pointerOffset(fragment, base, u32be(fragment, item + 12), 8) or nil
  if not state then return nil end
  local mode, scales = u32be(fragment, state), u32be(fragment, state + 4)
  if not mode or not scales then return nil end
  return {
    geometryMode = mode,
    textureScale = { math.floor(scales / 0x10000) / 65536, (scales % 0x10000) / 65536 },
    stateOffset = state,
  }
end

function Phase5Geometry.apply(state, site, result)
  local textures = result and result.program and result.program.textures or {}
  local material = result and result.program and result.program.phase5Material
  local controller = result and result.program and result.program.phase5Controller
  local selectedPointers, scrolls
  material, selectedPointers, scrolls = Phase5Geometry.evaluateController(controller, material,
    result and (result.phase5Frame or result.geometryIndex) or 0)
  local resolved = { operation = result and result.operation }
  if #textures > 0 then
    local byPointer = {}
    for _, texture in ipairs(textures) do byPointer[texture.pointer] = texture end
    local selected = selectedPointers and byPointer[selectedPointers[1]]
      or textures[1]
    if selected and tonumber(selected.slot) ~= nil then
      state.textureBySite[site] = selected.slot + 1
      resolved.texture, resolved.pointer = selected.slot + 1, selected.pointer
      local second = controller and selectedPointers and byPointer[selectedPointers[2]]
        or (not controller and textures[2] or nil)
      state.textureSetBySite = state.textureSetBySite or {}
      state.textureSetBySite[site] = {
        selected.slot + 1, second and second.slot + 1 or nil,
        phase5 = true, scroll = scrolls,
        formats = { selected.format, second and second.format or nil },
        sizes = { selected.size, second and second.size or nil },
        samplers = {
          controller and controller.items[1] and controller.items[1].sampler or nil,
          controller and controller.items[2] and controller.items[2].sampler or nil,
        },
      }
    end
  end
  if material then
    state.materialBySite[site] = material
    resolved.material = material
  end
  if not resolved.texture and not resolved.material then return false end
  state.renderTimeResolvedBySite[site] = resolved
  return true
end

return Phase5Geometry
