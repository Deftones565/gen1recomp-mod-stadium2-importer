-- Texture completeness checks shared by source-model and packed-model audits.
-- Source models use zero-based texture slots; DSM models use one-based slots.
local TextureParity = {}

local function addIssue(out, code, message, fields)
  local row = fields or {}
  row.code, row.message = code, message
  out.issues[#out.issues + 1] = row
  out.rules[code] = (out.rules[code] or 0) + 1
end

function TextureParity.audit(model, options)
  options = type(options) == "table" and options or {}
  local base = options.indexBase == 0 and 0 or 1
  local textures, prims = model and model.textures or {}, model and model.prims or {}
  local out = { issues = {}, rules = {}, metrics = {
    textures = #textures, textureBytes = 0, referencedTextures = 0,
    texturedPrimitives = 0, untexturedPrimitives = 0,
    callbackTexturePrimitives = 0,
  } }
  local valid, referenced = {}, {}
  for index, texture in ipairs(textures) do
    local w, h = tonumber(texture.w), tonumber(texture.h)
    local rgba = texture.rgba
    local expected = w and h and w > 0 and h > 0 and w * h * 4 or nil
    if not expected or type(rgba) ~= "string" or #rgba ~= expected then
      addIssue(out, "TEXTURE_PAYLOAD_INVALID",
        ("texture %d has %s bytes, expected %s for %sx%s RGBA")
          :format(index, type(rgba) == "string" and #rgba or "no",
            tostring(expected), tostring(w), tostring(h)), { texture = index })
    else
      valid[index - 1 + base] = true
      out.metrics.textureBytes = out.metrics.textureBytes + #rgba
    end
  end

  local function use(slot, primitive, route)
    slot = tonumber(slot)
    if slot == nil then
      addIssue(out, "TEXTURE_REFERENCE_INVALID",
        ("primitive %d has a non-numeric %s texture reference"):format(primitive, route),
        { primitive = primitive, route = route })
    elseif not valid[slot] then
      addIssue(out, "TEXTURE_REFERENCE_INVALID",
        ("primitive %d %s texture slot %d does not resolve")
          :format(primitive, route, slot),
        { primitive = primitive, route = route, texture = slot })
    else
      referenced[slot] = true
    end
  end

  for index, prim in ipairs(prims) do
    local sourceUntextured = prim.sourceTextureMissing == true
      or (base == 0 and (tonumber(prim.tex) or -1) < 0)
    if sourceUntextured then
      out.metrics.untexturedPrimitives = out.metrics.untexturedPrimitives + 1
      -- Packed models replace a deliberately untextured draw with a neutral
      -- sampler input; that slot must still be present and valid.
      if base == 1 then use(prim.tex, index, "neutral") end
    else
      out.metrics.texturedPrimitives = out.metrics.texturedPrimitives + 1
      use(prim.tex, index, "base")
    end
    if prim.callbackTextureRequired then
      out.metrics.callbackTexturePrimitives = out.metrics.callbackTexturePrimitives + 1
    end
    for key, slot in pairs(prim.texMap or {}) do use(slot, index, "animation[" .. tostring(key) .. "]") end
    for frame, slot in ipairs(prim.fxFrames or {}) do use(slot, index, "effect[" .. frame .. "]") end
  end
  for _ in pairs(referenced) do out.metrics.referencedTextures = out.metrics.referencedTextures + 1 end
  return out
end

return TextureParity
