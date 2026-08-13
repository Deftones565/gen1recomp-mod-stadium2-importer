-- Semantic model-completeness checks shared by the ROM-wide parity audit and
-- focused species investigations. These checks deliberately operate before
-- DSM packing: the source fragment still tells us whether Vtx bytes are
-- normals or colours and which callback/material owns each draw.
local Phase5 = require("mods.STADIUM2_IMPORTER.lib.render_callbacks.phase5_geometry")
local AnimationRouting = require("mods.STADIUM2_IMPORTER.lib.animation_routing")
local HandlerRegistry = require("mods.STADIUM2_IMPORTER.lib.handler_registry")
local VertexSemantics = require("mods.STADIUM2_IMPORTER.lib.vertex_semantics")
local TextureParity = require("mods.STADIUM2_IMPORTER.lib.texture_parity")

local ModelParity = {}

local function count(t)
  local n = 0
  for _ in pairs(t or {}) do n = n + 1 end
  return n
end

local function issue(out, severity, code, message, fields)
  local row = fields or {}
  row.species, row.severity, row.code, row.message = out.species, severity, code, message
  out.issues[#out.issues + 1] = row
  out.counts[severity] = (out.counts[severity] or 0) + 1
  out.rules[code] = (out.rules[code] or 0) + 1
end

local function phase5Routes(model, fragment, sourceBase)
  local textures, materials, sites = 0, 0, {}
  for _, node in ipairs(model.fx or {}) do
    if node.handler == 0x81000140 then
      sites[node.commandOffset] = true
      local specs = Phase5.textureSpecs(fragment, sourceBase, node.argOffset)
      if #specs > 0 then textures = textures + 1 end
      if Phase5.materialSpec(fragment, sourceBase, node.argOffset) then materials = materials + 1 end
    end
  end
  return textures, materials, sites
end

local function textureHasAlpha(texture)
  local rgba = texture and texture.rgba
  if type(rgba) ~= "string" or #rgba < 4 then return false end
  for alpha = 4, #rgba, 4 do
    if rgba:byte(alpha) < 255 then return true end
  end
  return false
end

function ModelParity.auditModel(model, fragment, sourceBase, options)
  options = type(options) == "table" and options or {}
  local out = {
    species = tonumber(model and model.species) or tonumber(options.species) or 0,
    issues = {}, counts = { error = 0, warning = 0 }, rules = {}, families = {},
    metrics = { primitives = #(model and model.prims or {}), triangles = 0 },
  }
  if type(model) ~= "table" then
    issue(out, "error", "MODEL_EXTRACT_FAILED", "model extraction returned no model")
    return out
  end

  local callbackSites, consumers, callbackTextureSites = {}, {}, {}
  for _, node in ipairs(model.fx or {}) do
    local descriptor = tonumber(node.handler or node.callback) or 0
    out.families[descriptor] = (out.families[descriptor] or 0) + 1
    callbackSites[node.commandOffset] = node
    local contract = HandlerRegistry.info(descriptor)
    if not contract or not contract.ownership or not contract.geometry
        or not contract.texturePolicy or not contract.argumentDecoder then
      issue(out, "error", "CALLBACK_CONTRACT_INCOMPLETE",
        ("callback descriptor %08X has no complete family contract"):format(descriptor),
        { descriptor = descriptor, site = node.commandOffset })
    end
    if descriptor == 0x81000140 and node.phase5Geometry ~= "state-only" then
      issue(out, "error", "PHASE5_GEOMETRY_CONTRACT",
        ("callback 0x%X must use following source geometry, got %s")
          :format(node.commandOffset or 0, tostring(node.phase5Geometry)),
        { site = node.commandOffset, descriptor = descriptor })
    end
  end
  for _, texture in ipairs(model.handlerTextures or {}) do
    callbackTextureSites[texture.commandOffset] = true
    local sampler = texture.sampler
    local represented = false
    for _, prim in ipairs(model.prims or {}) do
      if prim.callbackOffset == texture.commandOffset and prim.callbackTextureRequired
          and type(prim.sampler) == "table" then represented = true; break end
    end
    local hasConsumer = false
    for _, prim in ipairs(model.prims or {}) do
      if prim.callbackOffset == texture.commandOffset then hasConsumer = true; break end
    end
    if hasConsumer and not represented and sampler
        and ((sampler.cms or 0) ~= 0 or (sampler.cmt or 0) ~= 0
        or (sampler.masks or 0) ~= 0 or (sampler.maskt or 0) ~= 0
        or (sampler.shifts or 0) ~= 0 or (sampler.shiftt or 0) ~= 0) then
      issue(out, "error", "PACK_SAMPLER_STATE_LOSS",
        ("callback texture at 0x%X requires sampler %d/%d mask %d/%d shift %d/%d, but DSM stores pixels only")
          :format(texture.commandOffset or 0, sampler.cms or 0, sampler.cmt or 0,
            sampler.masks or 0, sampler.maskt or 0, sampler.shifts or 0,
            sampler.shiftt or 0), { site = texture.commandOffset })
    end
  end

  local unlit, alpha, modeLoss, textureGenPrimitives = 0, 0, 0, 0
  for index, prim in ipairs(model.prims or {}) do
    out.metrics.triangles = out.metrics.triangles + math.floor((prim.nidx or 0) / 3)
    if prim.callbackOffset then
      consumers[prim.callbackOffset] = (consumers[prim.callbackOffset] or 0) + 1
      local callback = callbackSites[prim.callbackOffset]
      if callbackTextureSites[prim.callbackOffset]
          and callback and callback.handler == 0x81000140
          and prim.callbackTextureRequired == nil then
        issue(out, "error", "CALLBACK_TEXTURE_OVERRIDES_AUTHORED_TEXTURE",
          ("primitive %d at callback 0x%X already has an authored texture")
            :format(index, prim.callbackOffset), { primitive = index, site = prim.callbackOffset })
      end
    end
    if not prim.generated and not prim.callbackTextureRequired
        and (prim.tex or -1) >= 0 then
      local textures = model.textures or {}
      local expectedDecal = textureHasAlpha(textures[prim.tex + 1])
      for _, slot in pairs(prim.texMap or {}) do
        expectedDecal = expectedDecal or textureHasAlpha(textures[slot + 1])
      end
      if expectedDecal ~= (prim.decal == true) then
        issue(out, "error", "ALPHA_TEXTURE_DECAL_LOSS",
          ("primitive %d alpha-texture decal=%s, expected %s")
            :format(index, tostring(prim.decal == true), tostring(expectedDecal)),
          { primitive = index })
      end
    end
    if prim.vertexSemantics == "color" and not prim.generated then
      unlit = unlit + 1
      for i = 4, #(prim.color or {}), 4 do
        if prim.color[i] ~= 255 then alpha = alpha + 1; break end
      end
    end
    if not prim.generated then
      local inferred, measurement = VertexSemantics.classify(prim.nrm)
      -- Only call this an audit failure at the unambiguous ends.  Mixed
      -- callback batches are classified for rendering but remain visible in
      -- metrics without producing speculative parity failures.
      local mismatch = (prim.vertexSemantics == "color" and measurement.normalRatio >= 0.80)
        or (prim.vertexSemantics == "normal" and measurement.normalRatio <= 0.10)
      if mismatch then
        issue(out, "error", "VERTEX_SEMANTICS_MISMATCH",
          ("primitive %d is tagged %s but its Vtx payload is %.0f%% %s-like")
            :format(index, tostring(prim.vertexSemantics), measurement.normalRatio * 100,
              inferred),
          { primitive = index, inferred = inferred,
            normalRatio = measurement.normalRatio, meanLength = measurement.meanLength })
      end
      local geometryLighting = prim.geometryMode ~= nil
        and math.floor(prim.geometryMode / 0x20000) % 2 == 1
      if prim.vertexSemantics == "normal" and not geometryLighting then
        issue(out, "error", "INHERITED_LIGHTING_STATE_LOSS",
          ("primitive %d contains normals but its geometry mode lost inherited G_LIGHTING")
            :format(index),
          { primitive = index, geometryMode = prim.geometryMode })
      end
    end
    if prim.geometryMode == nil and not prim.generated then modeLoss = modeLoss + 1 end
    if math.floor((prim.geometryMode or 0) / 0x40000) % 2 == 1 then
      textureGenPrimitives = textureGenPrimitives + 1
      if prim.callbackDescriptor == 0x81000140 and not prim.callbackTextureRequired then
        issue(out, "error", "AUTHORED_TEXTURE_TEXGEN_LEAK",
          ("primitive %d applies callback reflection coordinates to an authored texture")
            :format(index), { primitive = index, site = prim.callbackOffset })
      end
    end
  end
  out.metrics.textureGenPrimitives = textureGenPrimitives
  if unlit > 0 and options.packSupportsVertexColor == false then
    issue(out, "error", "PACK_VERTEX_COLOR_LOSS",
      ("%d unlit primitives use Vtx RGBA, but DSM stores those bytes as normals%s")
        :format(unlit, alpha > 0 and " (including source alpha)" or ""),
      { primitives = unlit, alphaPrimitives = alpha })
  end
  if modeLoss > 0 then
    issue(out, "error", "PACK_GEOMETRY_MODE_LOSS",
      ("%d primitives require geometry-mode bits beyond the DSM cull flag"):format(modeLoss),
      { primitives = modeLoss })
  end
  for site, node in pairs(callbackSites) do
    if callbackTextureSites[site] and not consumers[site] then
      local superseded = false
      for otherSite, other in pairs(callbackSites) do
        if otherSite ~= site and other.handler == node.handler and other.bone == node.bone
            and consumers[otherSite] then superseded = true; break end
      end
      if not superseded then
        issue(out, "error", "CALLBACK_WITHOUT_CONSUMER",
          ("texture callback 0x%X has no owned primitive"):format(site or 0),
          { site = site, descriptor = node.handler })
      end
    end
  end

  local auxRoute, routeInfo = AnimationRouting.assign(model.anims, model.auxAnims)
  out.metrics.auxAligned = routeInfo.matches

  for _, warning in ipairs(model.warnings or {}) do
    issue(out, "warning", "SOURCE_PARSE_WARNING", tostring(warning))
  end
  for _, warning in ipairs(model.animationAuditErrors or {}) do
    issue(out, "warning", "POSE_PARSE_WARNING", tostring(warning))
  end

  local textureRoutes, materialRoutes, phase5Sites = phase5Routes(model, fragment, sourceBase)
  out.metrics.phase5Callbacks = count(phase5Sites)
  out.metrics.phase5Textures = textureRoutes
  out.metrics.phase5Materials = materialRoutes
  local textureGenCallbacks = 0
  for _, node in ipairs(model.fx or {}) do
    if node.handler == 0x81000140 then
      local state = Phase5.stateSpec(fragment, sourceBase, node.argOffset or node.arg)
      if state and math.floor((state.geometryMode or 0) / 0x40000) % 2 == 1 then
        textureGenCallbacks = textureGenCallbacks + 1
        for index, prim in ipairs(model.prims or {}) do
          if prim.callbackOffset == node.commandOffset and prim.callbackTextureRequired
              and math.floor((prim.geometryMode or 0) / 0x40000) % 2 ~= 1 then
            issue(out, "error", "CALLBACK_TEXTURE_GEN_LOSS",
              ("primitive %d lost phase-5 G_TEXTURE_GEN at callback 0x%X")
                :format(index, node.commandOffset or 0),
              { primitive = index, site = node.commandOffset })
          end
        end
      end
    end
  end
  out.metrics.textureGenCallbacks = textureGenCallbacks
  local textureReport = TextureParity.audit(model, { indexBase = 0 })
  for key, value in pairs(textureReport.metrics) do out.metrics[key] = value end
  for _, row in ipairs(textureReport.issues) do
    issue(out, "error", row.code, row.message, row)
  end
  if out.species == 159 then
    if out.metrics.textures ~= 12 or out.metrics.referencedTextures ~= 12
        or out.metrics.texturedPrimitives ~= 10 or out.metrics.untexturedPrimitives ~= 1 then
      issue(out, "error", "CROCONAW_TEXTURE_COVERAGE",
        ("reference coverage is 12/12 textures, 10 textured and 1 neutral primitive; got %d/%d, %d/%d")
          :format(out.metrics.referencedTextures or 0, out.metrics.textures or 0,
            out.metrics.texturedPrimitives or 0, out.metrics.untexturedPrimitives or 0))
    end
  end
  if out.species == 200 then
    if out.metrics.primitives ~= 8 or out.metrics.triangles ~= 686 then
      issue(out, "error", "MISDREAVUS_REFERENCE_TOPOLOGY",
        ("reference topology is 8 primitives/686 triangles, got %d/%d")
          :format(out.metrics.primitives, out.metrics.triangles))
    end
    if out.metrics.phase5Callbacks ~= 6 or textureRoutes ~= 4 or materialRoutes ~= 2 then
      issue(out, "error", "MISDREAVUS_PHASE5_ROUTES",
        ("reference routes are 6 callbacks/4 textures/2 materials, got %d/%d/%d")
          :format(out.metrics.phase5Callbacks, textureRoutes, materialRoutes))
    end
    if auxRoute[2] ~= 3 or auxRoute[3] ~= 4 or auxRoute[4] ~= 5 then
      issue(out, "error", "MISDREAVUS_AUX_ROUTES",
        ("reference attack/faint/entrance aux routes are 3/4/5, got %s/%s/%s")
          :format(tostring(auxRoute[2]), tostring(auxRoute[3]), tostring(auxRoute[4])))
    end
  end
  if out.species == 208
      and (textureGenCallbacks ~= 5 or textureGenPrimitives ~= 4) then
    issue(out, "error", "STEELIX_REFLECTION_ROUTES",
      ("reference reflection coverage is 5 callbacks/4 body primitives, got %d/%d")
        :format(textureGenCallbacks, textureGenPrimitives))
  end
  return out
end

function ModelParity.merge(reports)
  local out = { species = 0, issues = {}, counts = { error = 0, warning = 0 },
    rules = {}, families = {}, metrics = {} }
  for _, report in ipairs(reports or {}) do
    for _, row in ipairs(report.issues or {}) do out.issues[#out.issues + 1] = row end
    for severity, n in pairs(report.counts or {}) do out.counts[severity] = (out.counts[severity] or 0) + n end
    for code, n in pairs(report.rules or {}) do out.rules[code] = (out.rules[code] or 0) + n end
    for descriptor, n in pairs(report.families or {}) do out.families[descriptor] = (out.families[descriptor] or 0) + n end
    for key, value in pairs(report.metrics or {}) do
      if type(value) == "number" then out.metrics[key] = (out.metrics[key] or 0) + value end
    end
  end
  return out
end

return ModelParity
