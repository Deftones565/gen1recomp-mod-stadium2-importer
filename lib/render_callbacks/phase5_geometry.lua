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
function Phase5Geometry.textureSpecs(fragment, sourceBase, argumentOffset)
  if type(fragment) ~= "string" or type(argumentOffset) ~= "number" then return {} end
  local base = tonumber(sourceBase) or 0x8FF00000
  local item = pointerOffset(fragment, base, u32be(fragment, argumentOffset), 16)
  local config = item and pointerOffset(fragment, base, u32be(fragment, item), 12) or nil
  local pointer = config and u32be(fragment, config) or nil
  local descriptor = config and pointerOffset(fragment, base, u32be(fragment, config + 8), 12) or nil
  if not descriptor or not pointerOffset(fragment, base, pointer, 1) then return {} end
  local format, size = byte(fragment, descriptor), byte(fragment, descriptor + 1)
  local width, height = u16be(fragment, descriptor + 8), u16be(fragment, descriptor + 10)
  if not format or not size or not width or not height or width < 1 or height < 1 then return {} end
  return {{
    pointer = pointer, w = width, h = height, format = format, size = size,
    sampler = {
      cms = byte(fragment, descriptor + 2), cmt = byte(fragment, descriptor + 3),
      masks = byte(fragment, descriptor + 4), maskt = byte(fragment, descriptor + 5),
      shifts = byte(fragment, descriptor + 6), shiftt = byte(fragment, descriptor + 7),
    },
    descriptorOffset = descriptor,
  }}
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
-- live model alpha. The importer renders fully-visible models here, so alpha
-- is one; battle fades remain applied later through sceneTint.
function Phase5Geometry.materialSpec(fragment, sourceBase, argumentOffset)
  if type(fragment) ~= "string" or type(argumentOffset) ~= "number" then return nil end
  local base = tonumber(sourceBase) or 0x8FF00000
  local item = pointerOffset(fragment, base, u32be(fragment, argumentOffset), 16)
  local colors = item and pointerOffset(fragment, base, u32be(fragment, item + 8), 12) or nil
  if not colors then return nil end
  local primitive = colorAt(fragment, base, u32be(fragment, colors + 4), 1)
  local environment = colorAt(fragment, base, u32be(fragment, colors + 8))
  if not primitive and not environment then return nil end
  return {
    primitiveColor = primitive or { 1, 1, 1, 1 },
    environmentColor = environment or { 1, 1, 1, 1 },
    phase5 = true,
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
  local resolved = { operation = result and result.operation }
  if #textures > 0 then
    local frame = math.max(0, math.floor(tonumber(result.geometryIndex) or 0))
    local selected = textures[frame % #textures + 1]
    if selected and tonumber(selected.slot) ~= nil then
      state.textureBySite[site] = selected.slot + 1
      resolved.texture, resolved.pointer = selected.slot + 1, selected.pointer
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
