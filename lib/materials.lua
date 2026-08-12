local Materials = {}

local floor = math.floor

local SUPPORTED = {
  [0x00] = true, [0xD7] = true, [0xD8] = true, [0xD9] = true,
  [0xDA] = true, [0xDB] = true, [0xDC] = true, [0xDD] = true,
  [0xDE] = true, [0xDF] = true, [0xE0] = true, [0xE1] = true,
  [0xE2] = true, [0xE3] = true, [0xE4] = true, [0xE5] = true,
  [0xE6] = true, [0xE7] = true, [0xE8] = true, [0xE9] = true,
  [0xEA] = true, [0xEB] = true, [0xEC] = true, [0xED] = true,
  [0xEE] = true, [0xEF] = true, [0xF0] = true, [0xF1] = true,
  [0xF2] = true, [0xF3] = true, [0xF4] = true, [0xF5] = true,
  [0xF6] = true, [0xF7] = true, [0xF8] = true, [0xF9] = true,
  [0xFA] = true, [0xFB] = true, [0xFC] = true, [0xFD] = true,
  [0xFE] = true, [0xFF] = true, [0xB9] = true, [0xBA] = true,
}

local function byte(data, offset)
  return string.byte(data, offset + 1)
end

local function u32(data, offset)
  local a, b, c, d = string.byte(data, offset + 1, offset + 4)
  if not d then return nil end
  return ((a * 256 + b) * 256 + c) * 256 + d
end

local function bits(value, shift, width)
  return floor(value / 2 ^ shift) % 2 ^ width
end

local function replaceBits(current, shift, width, value)
  if width <= 0 or shift < 0 or shift + width > 32 then return current end
  local scale, span = 2 ^ shift, 2 ^ width
  local old = floor(current / scale) % span
  return (current - old * scale + (value % span) * scale) % 0x100000000
end

local function setOtherMode(current, w0, w1)
  local length = bits(w0, 0, 8) + 1
  local encoded = bits(w0, 8, 8)
  local shift = 32 - encoded - length
  return replaceBits(current, shift, length, floor(w1 / 2 ^ math.max(shift, 0)))
end

local function colour(word)
  return {
    bits(word, 24, 8) / 255,
    bits(word, 16, 8) / 255,
    bits(word, 8, 8) / 255,
    bits(word, 0, 8) / 255,
  }
end

local function pointerOffset(extension, pointer)
  if type(pointer) ~= "number" then return nil end
  local base = tonumber(extension and extension.sourceBase) or 0x8FF00000
  local offset = pointer - base
  local fragment = extension and extension.fragment
  if type(fragment) ~= "string" or offset < 0 or offset >= #fragment then return nil end
  return offset
end

local function sampler(mode, mask, shift)
  return {
    wrap = bits(mode, 0, 1) ~= 0 and "mirroredrepeat"
      or (bits(mode, 1, 1) ~= 0 and "clamp" or "repeat"),
    mirror = bits(mode, 0, 1) ~= 0,
    clamp = bits(mode, 1, 1) ~= 0,
    mask = mask,
    shift = shift,
  }
end

function Materials.parse(extension, startOffset, options)
  local data = extension and extension.fragment
  if type(data) ~= "string" or type(startOffset) ~= "number" then return nil, "material unavailable" end
  if startOffset < 0 or startOffset + 8 > #data then return nil, "material outside fragment" end
  options = type(options) == "table" and options or {}
  local state = {
    offset = startOffset,
    commands = {},
    primitiveColor = { 1, 1, 1, 1 },
    environmentColor = { 1, 1, 1, 1 },
    blendColor = { 0, 0, 0, 0 },
    fogColor = { 0, 0, 0, 0 },
    textureScale = { 1, 1 },
    textureEnabled = true,
    tiles = {},
    unsupported = {},
    otherModeHigh = 0,
    otherModeLow = 0,
    combine = { 0, 0 },
  }
  local visited = options.visited or {}
  local maxCommands = math.max(1, tonumber(options.maxCommands) or 256)
  local cursor, count = startOffset, 0
  while cursor + 8 <= #data and count < maxCommands do
    if visited[cursor] then break end
    visited[cursor] = true
    count = count + 1
    local w0, w1 = u32(data, cursor), u32(data, cursor + 4)
    local op = bits(w0, 24, 8)
    state.commands[#state.commands + 1] = { offset = cursor, op = op, w0 = w0, w1 = w1 }
    if not SUPPORTED[op] then state.unsupported[op] = (state.unsupported[op] or 0) + 1 end
    cursor = cursor + 8
    if op == 0xDF then
      break
    elseif op == 0xDE then
      local child = pointerOffset(extension, w1)
      if child then
        local nested = Materials.parse(extension, child, { visited = visited, maxCommands = maxCommands - count })
        if nested then
          for _, command in ipairs(nested.commands) do state.commands[#state.commands + 1] = command end
          state.primitiveColor = nested.primitiveColor
          state.environmentColor = nested.environmentColor
          state.blendColor = nested.blendColor
          state.fogColor = nested.fogColor
          state.textureScale = nested.textureScale
          state.textureEnabled = nested.textureEnabled
          state.tiles = nested.tiles
          state.otherModeHigh = nested.otherModeHigh
          state.otherModeLow = nested.otherModeLow
          state.combine = nested.combine
          state.textureImage = nested.textureImage or state.textureImage
          state.tlutImage = nested.tlutImage or state.tlutImage
        end
      end
      if bits(w0, 16, 8) ~= 0 then break end
    elseif op == 0xD7 then
      state.textureEnabled = bits(w0, 1, 7) ~= 0
      state.textureScale = { bits(w1, 16, 16) / 65536, bits(w1, 0, 16) / 65536 }
    elseif op == 0xD9 then
      state.geometryClear, state.geometrySet = bits(w0, 0, 24), w1
    elseif op == 0xE2 then
      state.otherModeLow = setOtherMode(state.otherModeLow, w0, w1)
    elseif op == 0xE3 then
      state.otherModeHigh = setOtherMode(state.otherModeHigh, w0, w1)
    elseif op == 0xB9 then
      state.otherModeLow = w1
    elseif op == 0xBA then
      state.otherModeHigh = w1
    elseif op == 0xF5 then
      local tile = bits(w1, 24, 3)
      state.tiles[tile] = {
        format = bits(w0, 21, 3), size = bits(w0, 19, 2), line = bits(w0, 9, 9),
        tmem = bits(w0, 0, 9), palette = bits(w1, 20, 4),
        t = sampler(bits(w1, 18, 2), bits(w1, 14, 4), bits(w1, 10, 4)),
        s = sampler(bits(w1, 8, 2), bits(w1, 4, 4), bits(w1, 0, 4)),
      }
    elseif op == 0xF2 then
      local tile = bits(w1, 24, 3)
      local row = state.tiles[tile] or {}
      row.uls, row.ult = bits(w0, 12, 12) / 4, bits(w0, 0, 12) / 4
      row.lrs, row.lrt = bits(w1, 12, 12) / 4, bits(w1, 0, 12) / 4
      state.tiles[tile] = row
    elseif op == 0xFD then
      state.textureImage = {
        format = bits(w0, 21, 3), size = bits(w0, 19, 2), width = bits(w0, 0, 12) + 1,
        pointer = w1, offset = pointerOffset(extension, w1),
      }
    elseif op == 0xF0 then
      state.tlutCount = bits(w1, 14, 10) + 1
      if state.textureImage then state.tlutImage = state.textureImage end
    elseif op == 0xFA then
      state.primitiveColor = colour(w1)
      state.lodFraction, state.primitiveLod = bits(w0, 0, 8), bits(w0, 8, 8)
    elseif op == 0xFB then
      state.environmentColor = colour(w1)
    elseif op == 0xF8 then
      state.fogColor = colour(w1)
    elseif op == 0xF9 then
      state.blendColor = colour(w1)
    elseif op == 0xFC then
      state.combine = { bits(w0, 0, 24), w1 }
    end
  end
  state.commandCount = #state.commands
  state.complete = state.commands[#state.commands] and state.commands[#state.commands].op == 0xDF or false
  state.activeTile = state.tiles[0] or state.tiles[1]
  state.cycleType = bits(state.otherModeHigh, 20, 2)
  if state.activeTile then state.wrapS, state.wrapT = state.activeTile.s.wrap, state.activeTile.t.wrap end
  return state
end

function Materials.attach(model)
  local extension = model and model.handlers
  local render = extension and extension.render
  local offsets = render and render.primitiveMaterials
  if not offsets then return model end
  model.materials = {}
  for i, prim in ipairs(model.prims or {}) do
    prim.materialOffset = offsets[i]
    prim.callbackOffset = render.primitiveCallbacks and render.primitiveCallbacks[i] or nil
    if prim.materialOffset then
      prim.material = Materials.parse(extension, prim.materialOffset)
      model.materials[i] = prim.material
    end
  end
  return model
end

Materials.u32be = u32
Materials.pointerOffset = pointerOffset
Materials.SUPPORTED = SUPPORTED

return Materials
