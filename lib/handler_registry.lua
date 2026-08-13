-- Fragment 26 callback catalogue.  Keep this file declarative: extraction,
-- cache codecs, runtime simulation and rendering live in their own modules.
local Registry = {}

Registry.BY_DESCRIPTOR = {
  [0x81000030] = { target = 0x810039CC, phases = { 2 }, family = "display-list-wrapper", confidence = "verified-structure" },
  [0x81000038] = { target = 0x81005AC0, phases = { 2 }, family = "flame-object-renderer", confidence = "verified-behavior",
    implementation = "render_callbacks.flame" },
  [0x81000040] = { target = 0x81003A74, phases = { 2 }, family = "display-list-wrapper", confidence = "verified-structure" },
  [0x81000048] = { target = 0x81005DB4, phases = { 2 }, family = "dynamic-material-builder", confidence = "verified-structure" },
  [0x81000050] = { target = 0x81003B78, phases = { 2 }, family = "texture-material-builder", confidence = "verified-structure" },
  [0x81000058] = { target = 0x81003C30, phases = { 2 }, family = "visibility-range-enable", confidence = "verified-behavior" },
  [0x81000060] = { target = 0x81003CC0, phases = { 2 }, family = "visibility-range-disable", confidence = "verified-behavior" },
  [0x81000068] = { target = 0x81005F38, phases = { 2 }, family = "dynamic-material-builder", confidence = "verified-structure" },
  [0x81000070] = { target = 0x81005524, phases = { 2 }, family = "dynamic-object-renderer", confidence = "verified-structure",
    implementation = "effects.dynamic_object" },
  [0x81000078] = { target = 0x81003680, phases = { 2 }, family = "attribute-transform", confidence = "partial" },
  [0x81000080] = { target = 0x81005F80, phases = { 0 }, family = "model-context-register", confidence = "verified-behavior" },
  [0x81000088] = { target = 0x81003DAC, phases = { 0, 2 }, family = "runtime-dispatch-bridge", confidence = "partial" },
  [0x81000140] = { target = 0x810033DC, phases = { 5 }, family = "render-time-geometry-pipeline", confidence = "verified-structure" },
}

local CONTRACTS = {
  ["display-list-wrapper"] = { ownership="preceding", geometry="wrapped-display-list",
    texturePolicy="material", argumentDecoder="model_handlers.pointerWords" },
  ["dynamic-material-builder"] = { ownership="preceding", geometry="source",
    texturePolicy="replace-owned", argumentDecoder="model_handlers.dynamicMaterial" },
  ["flame-object-renderer"] = { ownership="none", geometry="generated-runtime",
    texturePolicy="generated-only", argumentDecoder="render_callbacks.flame" },
  ["texture-material-builder"] = { ownership="preceding", geometry="source",
    texturePolicy="replace-owned", argumentDecoder="model_handlers.textureMaterial" },
  ["visibility-range-enable"] = { ownership="preceding", geometry="source",
    texturePolicy="preserve", argumentDecoder="model_handlers.visibilityGate" },
  ["visibility-range-disable"] = { ownership="preceding", geometry="source",
    texturePolicy="preserve", argumentDecoder="model_handlers.visibilityGate" },
  ["dynamic-object-renderer"] = { ownership="preceding", geometry="generated-runtime",
    texturePolicy="generated-only", argumentDecoder="effects.dynamic_object" },
  ["attribute-transform"] = { ownership="preceding", geometry="source",
    texturePolicy="preserve", argumentDecoder="model_handlers.attributeTransform" },
  ["model-context-register"] = { ownership="none", geometry="none",
    texturePolicy="preserve", argumentDecoder="model_handlers.modelContext" },
  ["runtime-dispatch-bridge"] = { ownership="preceding", geometry="source",
    texturePolicy="preserve", argumentDecoder="model_handlers.runtimeDispatch" },
  ["render-time-geometry-pipeline"] = { ownership="following", geometry="state-only",
    texturePolicy="replace-untextured", argumentDecoder="render_callbacks.phase5_geometry" },
}
for _, row in pairs(Registry.BY_DESCRIPTOR) do
  local contract = CONTRACTS[row.family]
  for key, value in pairs(contract or {}) do row[key] = value end
end

Registry.FAMILY_IDS = {
  ["display-list-wrapper"] = 1, ["dynamic-material-builder"] = 2,
  ["texture-material-builder"] = 3, ["visibility-range-enable"] = 4,
  ["visibility-range-disable"] = 5, ["dynamic-object-renderer"] = 6,
  ["attribute-transform"] = 7, ["model-context-register"] = 8,
  ["runtime-dispatch-bridge"] = 9, ["render-time-geometry-pipeline"] = 10,
  ["flame-object-renderer"] = 11,
}

Registry.FAMILY_NAMES = {}
for name, id in pairs(Registry.FAMILY_IDS) do Registry.FAMILY_NAMES[id] = name end

Registry.CONFIDENCE_IDS = {
  partial = 0, strong = 1, ["verified-structure"] = 2, ["verified-behavior"] = 3,
}
Registry.CONFIDENCE_NAMES = {}
for name, id in pairs(Registry.CONFIDENCE_IDS) do Registry.CONFIDENCE_NAMES[id] = name end

Registry.BY_TARGET = {}
for descriptor, row in pairs(Registry.BY_DESCRIPTOR) do
  row.descriptor = descriptor
  Registry.BY_TARGET[row.target] = row
end

function Registry.info(address)
  address = tonumber(address)
  return address and (Registry.BY_DESCRIPTOR[address] or Registry.BY_TARGET[address]) or nil
end

function Registry.family(address)
  local row = Registry.info(address)
  return row and row.family or nil
end

return Registry
