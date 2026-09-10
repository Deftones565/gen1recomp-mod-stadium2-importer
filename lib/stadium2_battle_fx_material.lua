-- Pure fragment-79 common-particle material state.
--
-- The audited preload path (0x84106F34..0x8410716C) copies shape IDs and
-- RGBA bytes only.  Color updates, secondary-shape selection, and drawing are
-- intentionally external resolver decisions rather than guessed formulas.
local Material = {}
local NativeObjects=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_native_objects")

local function copy(value, seen)
  if type(value) ~= "table" then return value end
  seen = seen or {}
  if seen[value] then return seen[value] end
  local out = {}
  seen[value] = out
  for key, child in pairs(value) do out[copy(key, seen)] = copy(child, seen) end
  return out
end

local function number(value)
  value = tonumber(value)
  if value == nil or value ~= math.floor(value) then return nil end
  return value
end

local function validColor(value)
  if type(value) ~= "table" then return nil end
  local out = {}
  for index = 1, 4 do
    local byte = number(value[index])
    if byte == nil or byte < 0 or byte > 255 then return nil end
    out[index] = byte
  end
  return out
end

local function present(value)
  return value ~= nil and value ~= 0 and value ~= false
end

local function resolver(context, names)
  for _, name in ipairs(names) do
    if type(context[name]) == "function" then return context[name] end
  end
  return nil
end

local function addDiagnostic(state, code, message, fields)
  state.diagnostics = state.diagnostics or {}
  state._diagnosticKeys = state._diagnosticKeys or {}
  local address = fields and fields.address or state.address
  local key = table.concat({tostring(code), tostring(address), tostring(message)}, ":")
  if state._diagnosticKeys[key] then return end
  state._diagnosticKeys[key] = true
  state.diagnostics[#state.diagnostics + 1] = {
    code = code, severity = fields and fields.severity or "warning",
    effectId = state.effectId, programId = state.programId,
    address = address, kind = fields and fields.kind or "material",
    message = message,
  }
end

local function validatePreload(state, field, value)
  if value == nil then return nil end
  local out = validColor(value)
  if out then return out end
  addDiagnostic(state, "invalid-rgba", "material " .. field .. " is not four bytes", {
    kind = "material",
  })
  return nil
end

local function colorValue(value, names)
  if type(value) ~= "table" then return nil end
  for _, name in ipairs(names) do
    if value[name] ~= nil then return value[name] end
  end
  return nil
end

-- Create a detached material preload state.  The decoder's `shapeId`,
-- `secondaryShapeId`, `colorController`, and `colors` names are retained;
-- pointer aliases are accepted for small ROM-backed fixtures.
function Material.init(material, context)
  material = type(material) == "table" and material or {}
  context = type(context) == "table" and context or {}
  local state = {
    effectId = context.effectId, programId = context.programId,
    address = context.address or material.address, age = tonumber(context.age) or 0,
    primaryShapeId = material.shapeId or material.primaryShapeId,
    secondaryShapeId = material.secondaryShapeId,
    -- shapeId is the authored primary preload, not a secondary selection.
    shapeId = material.shapeId or material.primaryShapeId,
    selectedShapeId = nil,
    colorController = material.colorController,
    colorTable = material.colors or material.colorTable,
    primaryColor = nil, secondaryColor = nil, constantColor = nil,
    diagnostics = {}, _context = copy(context), _material = copy(material),
  }
  state.primaryColor = validatePreload(state, "primaryColor", material.primaryColor)
  state.secondaryColor = validatePreload(state, "secondaryColor", material.secondaryColor)
  state.constantColor = validatePreload(state, "constantColor", material.constantColor)
  state.nativeMaterialColors=material.nativeMaterialColors
  state.nativePrimaryTrack=copy(material.nativePrimaryTrack)
  state.nativeSecondaryTrack=copy(material.nativeSecondaryTrack)
  state.nativeAlphaRamp=copy(material.nativeAlphaRamp)
  if state.nativeMaterialColors or state.nativeAlphaRamp or material.nativeAlphaInitial~=nil then
    state.nativeAlpha=material.nativeAlphaInitial
      or (state.primaryColor and state.primaryColor[4]) or context.attribute or 255
    state.nativeAlpha=state.nativeAlpha%256
    state.nativeFlags=tonumber(context.flags) or 0
    state.nativeFlags2=tonumber(context.flags2) or 0
    if math.floor(state.nativeFlags/0x10)%2==1 or math.floor(state.nativeFlags2/4)%2==1 then
      state.nativeAlphaGateUnresolved=true
      addDiagnostic(state,"unsupported-alpha-gate",
        "native alpha ramp requires battle-counter/global gate state",{kind="material"})
    end
  end

  local colorResolver = resolver(context,
    {"colorController", "resolveColorController", "colorResolver"})
  if present(state.colorController) and not colorResolver
      and not state.nativePrimaryTrack and not state.nativeSecondaryTrack then
    addDiagnostic(state, "unsupported-color-controller",
      "fragment-79 color-controller update requires an explicit resolver", {
        kind = "color-controller",
      })
  end
  local shapeResolver = resolver(context,
    {"selectShape", "shapeSelection", "resolveShape"})
  if present(state.secondaryShapeId) and not shapeResolver then
    addDiagnostic(state, "unsupported-secondary-shape",
      "secondary shape selection requires an explicit resolver", {
        kind = "shape-selection",
      })
  end
  return state
end

local function applyColors(out, value)
  local fields = {
    {"primaryColor", {"primaryColor", "primary"}},
    {"secondaryColor", {"secondaryColor", "secondary"}},
    {"constantColor", {"constantColor", "constant"}},
  }
  local changed = false
  for _, item in ipairs(fields) do
    local authored = colorValue(value, item[2])
    if authored ~= nil then
      local validated = validColor(authored)
      if not validated then return false end
      out[item[1]] = validated
      changed = true
    end
  end
  return changed
end

-- Advance material state.  No color interpolation or shape policy is hidden
-- here: only explicit resolver return values may alter preloaded state.
function Material.step(state, options)
  if type(state) ~= "table" then return nil, "material state is required" end
  options = type(options) == "table" and options or {}
  local out = copy(state)
  out._diagnosticKeys = copy(state._diagnosticKeys or {})
  out.diagnostics = copy(state.diagnostics or {})
  local delta = tonumber(options.delta or options.dt or 1) or 0
  if delta < 0 then
    addDiagnostic(out, "invalid-material-delta", "material step delta is negative", {
      kind = "material",
    })
    delta = 0
  end

  local merged = copy(state._context or {})
  for key, value in pairs(options) do merged[key] = value end
  local colorResolver = resolver(merged,
    {"colorController", "resolveColorController", "colorResolver"})
  if present(out.colorController) and colorResolver then
    local ok, value = pcall(colorResolver, copy(out), copy(merged))
    local candidate = copy(out)
    if ok and type(value) == "table" and applyColors(candidate, value) then
      out.primaryColor = candidate.primaryColor
      out.secondaryColor = candidate.secondaryColor
      out.constantColor = candidate.constantColor
    else
      addDiagnostic(out, "invalid-color-controller-resolver",
        "color-controller resolver returned invalid colors", {
          kind = "color-controller",
        })
    end
  end

  local shapeResolver = resolver(merged,
    {"selectShape", "shapeSelection", "resolveShape"})
  if present(out.secondaryShapeId) and shapeResolver then
    local ok, value = pcall(shapeResolver, copy(out), copy(merged))
    local selected = type(value) == "table" and (value.shapeId or value.selectedShapeId)
      or value
    selected = number(selected)
    if ok and selected ~= nil and selected >= 0 then
      out.selectedShapeId = selected
    else
      addDiagnostic(out, "invalid-secondary-shape-resolver",
        "shape-selection resolver returned no valid shape ID", {
          kind = "shape-selection",
        })
    end
  end
  out.age = out.age + delta
  -- 84102380 clamps at period-1; particle color tracks hold their last
  -- sample, unlike mode-2 background controllers which terminate.
  for _,entry in ipairs({{"nativePrimaryTrack","primaryColor"},
      {"nativeSecondaryTrack","secondaryColor"}}) do
    local track=out[entry[1]]
    if track and not colorResolver then
      local age=math.min(tonumber(options.age) or out.age,track.period-1)
      local rgba=NativeObjects.colorAt(track,age)
      if rgba then
        out[entry[2]]=rgba
        if entry[2]=="primaryColor" then out.nativeAlpha=rgba[4] end
      end
    end
  end
  -- 84102534/84102598: post-increment age enables a byte alpha ramp.
  -- The target is approached by an unsigned byte step with saturation.
  local ramp=out.nativeAlphaRamp
  if ramp and not out.nativeAlphaGateUnresolved then
    if delta==1 then
      local age=tonumber(options.age) or out.age
      if age>=ramp.startAge then
        local alpha=out.nativeAlpha
        if alpha<ramp.target then alpha=math.min(ramp.target,alpha+ramp.step)
        elseif alpha>ramp.target then alpha=math.max(ramp.target,alpha-ramp.step) end
        out.nativeAlpha=alpha
        -- 841025F8: descriptor bit 30 kills the particle at the target.
        if alpha==ramp.target and math.floor(out.nativeFlags/0x40000000)%2==1 then
          out.nativeAlphaFinished=true
        end
      end
    else
      addDiagnostic(out,"unsupported-alpha-step","native alpha requires individual 30 Hz ticks")
    end
  end
  return out
end

Material.evaluate = Material.step

function Material.snapshot(state)
  if type(state) ~= "table" then return nil end
  local out = copy(state)
  out._context, out._material, out._diagnosticKeys = nil, nil, nil
  return out
end

return Material
