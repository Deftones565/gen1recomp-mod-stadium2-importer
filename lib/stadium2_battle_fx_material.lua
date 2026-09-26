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

-- _context and _material are set once by Material.init and only read
-- afterwards, so per-tick state copies share them instead of re-copying.
local SHARED_STATE = { _context = true, _material = true }
local function copyState(state)
  local out = {}
  for key, value in pairs(state) do
    out[key] = SHARED_STATE[key] and value or copy(value)
  end
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

local function gateSignal(context,kind,state)
  local value=context[kind=="global" and "nativeAlphaGlobalGate" or "nativeAlphaSignal"]
  local resolve=context.resolveNativeAlphaGate
  if type(resolve)=="function" then
    local ok,result=pcall(resolve,kind,copy(state),copy(context))
    if ok and result~=nil then value=result end
  end
  if value==nil then return nil end
  return present(value)
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
  state.nativeAlphaBaseRamp=copy(material.nativeAlphaBaseRamp)
  if state.nativeMaterialColors or state.nativeAlphaRamp or material.nativeAlphaInitial~=nil then
    state.nativeAlpha=material.nativeAlphaInitial
      or (state.primaryColor and state.primaryColor[4]) or context.attribute or 255
    state.nativeAlpha=state.nativeAlpha%256
    state.nativeFlags=tonumber(context.flags) or 0
    state.nativeFlags2=tonumber(context.flags2) or 0
    state.nativeAlphaSignalAge=0
    local gatedGlobal=math.floor(state.nativeFlags2/4)%2==1
    local gatedSignal=math.floor(state.nativeFlags/0x10)%2==1
    local signalKind=gatedGlobal and "global" or gatedSignal and "signal" or nil
    if state.nativeAlphaRamp and signalKind
        and gateSignal(context,signalKind,state)==nil then
      state.nativeAlphaGateUnresolved=true
      addDiagnostic(state,"unsupported-alpha-gate",
        "native alpha ramp requires its battle signal",{kind="material"})
    end
  end

  local colorResolver = resolver(context,
    {"colorController", "resolveColorController", "colorResolver"})
  if present(state.colorController) and not colorResolver
      and not material.nativeConstantColors
      and not state.nativePrimaryTrack and not state.nativeSecondaryTrack then
    addDiagnostic(state, "unsupported-color-controller",
      "fragment-79 color-controller update requires an explicit resolver", {
        kind = "color-controller",
      })
  end
  local shapeResolver = resolver(context,
    {"selectShape", "shapeSelection", "resolveShape"})
  if present(state.secondaryShapeId) and not shapeResolver
      and material.nativeSecondaryShapeSelection~=false then
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
-- Advances `out` in place; Material.step and Material.advance share it.
local function advance(out, options)
  options = type(options) == "table" and options or {}
  local delta = tonumber(options.delta or options.dt or 1) or 0
  if delta < 0 then
    addDiagnostic(out, "invalid-material-delta", "material step delta is negative", {
      kind = "material",
    })
    delta = 0
  end

  -- Only top-level keys are replaced here; resolvers receive their own copy.
  local merged = {}
  for key, value in pairs(out._context or {}) do merged[key] = value end
  for key, value in pairs(options) do merged[key] = value end
  local colorResolver = resolver(merged,
    {"colorController", "resolveColorController", "colorResolver"})
  if present(out.colorController) and colorResolver then
    local ok, value = pcall(colorResolver, copyState(out), copy(merged))
    local candidate = copyState(out)
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
    local ok, value = pcall(shapeResolver, copyState(out), copy(merged))
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
  local rampApplied=false
  if ramp then
    if delta==1 then
      local age=tonumber(options.age) or out.age
      local gatedGlobal=math.floor((out.nativeFlags2 or 0)/4)%2==1
      local gatedSignal=math.floor((out.nativeFlags or 0)/0x10)%2==1
      local enabled=true
      if gatedGlobal then
        enabled=gateSignal(merged,"global",out)
      elseif gatedSignal then
        local signal=gateSignal(merged,"signal",out)
        if signal==nil then enabled=nil else enabled=false end
        if signal then
          out.nativeAlphaSignalAge=((out.nativeAlphaSignalAge or 0)+1)%256
          enabled=out.nativeAlphaSignalAge>=ramp.startAge
        end
      else
        enabled=age>=ramp.startAge
      end
      if enabled==nil then
        out.nativeAlphaGateUnresolved=true
        addDiagnostic(out,"unsupported-alpha-gate",
          "native alpha ramp requires its battle signal",{kind="material"})
      else
        out.nativeAlphaGateUnresolved=false
      end
      if enabled then
        rampApplied=true
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
  -- 84102648: the initial alpha controller continues while the gated/end
  -- controller is inactive. This is how Roar/Whirlwind fade in before recall.
  local base=out.nativeAlphaBaseRamp
  if not rampApplied and not out.nativeAlphaGateUnresolved and base and delta==1
      and (tonumber(options.age) or out.age)>=base.startAge then
    local alpha=out.nativeAlpha
    if alpha<base.target then alpha=math.min(base.target,alpha+base.step)
    elseif alpha>base.target then alpha=math.max(base.target,alpha-base.step) end
    out.nativeAlpha=alpha
  end
  return out
end

function Material.step(state, options)
  if type(state) ~= "table" then return nil, "material state is required" end
  local out = copyState(state)
  out._diagnosticKeys = copy(state._diagnosticKeys or {})
  out.diagnostics = copy(state.diagnostics or {})
  return advance(out, options)
end

-- In-place Material.step for the runtime, which replaces its state with the
-- result anyway; skips the per-tick state copy. Same result as step.
function Material.advance(state, options)
  if type(state) ~= "table" then return nil, "material state is required" end
  state._diagnosticKeys = state._diagnosticKeys or {}
  state.diagnostics = state.diagnostics or {}
  return advance(state, options)
end

Material.evaluate = Material.step

local SNAPSHOT_SKIP = { _context = true, _material = true, _diagnosticKeys = true }
function Material.snapshot(state)
  if type(state) ~= "table" then return nil end
  local out = {}
  for key, value in pairs(state) do
    if not SNAPSHOT_SKIP[key] then out[key] = copy(value) end
  end
  return out
end
-- Material.snapshot always returns a new, unshared table.
Material.snapshotIsFresh = true

return Material
