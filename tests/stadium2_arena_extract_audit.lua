package.path = "./?.lua;./?/init.lua;" .. package.path

local Rom = require("mods.STADIUM2_IMPORTER.lib.rom")
local Fragment = require("mods.STADIUM2_IMPORTER.lib.fragment")
local Renderer = require("mods.STADIUM2_IMPORTER.lib.renderer")
local Materials = require("mods.STADIUM2_IMPORTER.lib.materials")
local Phase5 = require("mods.STADIUM2_IMPORTER.lib.render_callbacks.phase5_geometry")

local function u32be(data, offset)
  local a, b, c, d = data:byte(offset + 1, offset + 4)
  assert(d, ("u32 read outside decoded fragment at 0x%X"):format(offset))
  return ((a * 0x100 + b) * 0x100 + c) * 0x100 + d
end

local function s16be(data, offset)
  local a, b = data:byte(offset + 1, offset + 2)
  assert(b, ("s16 read outside decoded fragment at 0x%X"):format(offset))
  local value = a * 0x100 + b
  return value >= 0x8000 and value - 0x10000 or value
end

local path = os.getenv("STADIUM2_ROM") or arg[1]
if not path or path == "" then
  io.stderr:write("usage: STADIUM2_ROM=/path/to/stadium2.z64 luajit mods/STADIUM2_IMPORTER/tests/stadium2_arena_extract_audit.lua\n")
  os.exit(2)
end

local file = assert(io.open(path, "rb"))
local rom = assert(Rom.normalise(assert(file:read("*a"))))
file:close()

assert(#rom == Rom.SIZE, "unexpected ROM size")
assert(Rom.title(rom):upper() == Rom.US_TITLE, "unexpected ROM title")
local archive = assert(Rom.archiveAt(rom, Rom.STADIUM_MODEL_TABLE_START),
  "Stadium field archive is missing")
assert(archive.count == Rom.STADIUM_MODEL_TABLE_RECORDS,
  "Stadium field archive record count changed")
assert(archive.total == 0xC3090, "Stadium field archive size changed")
assert(archive.offset + archive.total <= Rom.STADIUM_MODEL_TABLE_END,
  "Stadium field archive exceeds its ROM region")

local totals = { bones = 0, primitives = 0, vertices = 0,
  triangles = 0, textures = 0, warnings = 0, handlerTextures = 0,
  callbackTexturePrimitives = 0, phase5 = 0, stageTransformColor = 0,
  opaque = 0, cutout = 0, blend = 0, prelit = 0, directional = 0,
  renderProfiles = 0, submissionLayers = 0, stateResets = 0,
  opaqueZeroAlpha = 0 }

-- These fields share Stadium's dual-texture centre treatment: TEXEL0 carries
-- the gravel/ground material and TEXEL1 applies the Poké Ball mask/detail.
-- Arena 11 contains two independently transformed copies of the battle area.
local centreMaterials = {
  [1] = {{16, 0xDA14}},
  [2] = {{13, 0xC374}},
  [4] = {{17, 0xDEA8}},
  [9] = {{12, 0xE134}},
  [10] = {{13, 0xD77C}},
  [11] = {{15, 0xDD6C}, {22, 0xDF20}},
  [12] = {{26, 0xDA30}},
  [13] = {{21, 0xD834}},
}

for _, record in ipairs(archive.records) do
  assert(record.size > 0, ("arena %d is empty"):format(record.index))
  local packed = assert(Rom.recordBytes(rom, record))
  assert(packed:sub(1, 8) == "PERS-SZP",
    ("arena %d is not PERS-SZP"):format(record.index))
  local decoded = assert(Rom.decompress(packed))
  assert(decoded:sub(9, 16) == "FRAGMENT",
    ("arena %d is not a FRAGMENT"):format(record.index))
  local root = assert(Fragment.stageRoot(decoded, ("arena_%02d"):format(record.index)))
  assert(root >= 0 and root < #decoded, "stage root is out of range")
  local model = assert(Fragment.extractStage(decoded,
    ("arena_%02d"):format(record.index), record.index))
  assert(#model.prims > 0, ("arena %d has no geometry"):format(record.index))
  assert(model.arenaLighting and model.arenaLighting.mode == "hybrid-prelit",
    ("arena %d has no ROM lighting audit"):format(record.index))
  totals.prelit = totals.prelit + model.arenaLighting.prelitPrimitives
  totals.directional = totals.directional
    + model.arenaLighting.directionalPrimitives
  local phase5MaterialBySite = {}
  for _, node in ipairs(model.fx) do
    if node.handler == 0x81000148 then
      phase5MaterialBySite[node.commandOffset] = Phase5.materialSpec(
        decoded, 0x8FF00000, node.arg, 2)
    end
  end

  for _, expected in ipairs(centreMaterials[record.index] or {}) do
    local primitive = assert(model.prims[expected[1]])
    local node
    for _, candidate in ipairs(model.fx) do
      if candidate.commandOffset == expected[2] then node = candidate end
    end
    local textures = Phase5.textureSpecs(decoded, 0x8FF00000,
      assert(node, ("arena %02d centre callback is missing"):format(record.index)).arg)
    local primary, secondary = assert(textures[1]), assert(textures[2])
    local sampler = assert(primitive.sampler)
    assert(primitive.callbackOffset == expected[2]
      and primitive.callbackTextureRequired == true
      and primary.w == 32 and primary.h == 32
      and secondary.w == 64 and secondary.h == 64
      and primary.format == 0 and primary.size == 2
      and secondary.format == 4 and secondary.size == 0
      and sampler.cms == primary.sampler.cms
      and sampler.cmt == primary.sampler.cmt
      and sampler.masks == primary.sampler.masks
      and sampler.maskt == primary.sampler.maskt
      and sampler.shifts == primary.sampler.shifts
      and sampler.shiftt == primary.sampler.shiftt
      and primitive.textureScale == nil,
      ("arena %02d centre collapsed TEXEL0/TEXEL1 sampler state")
        :format(record.index))
  end

  if centreMaterials[record.index] then
    local orderedParts, bySource = {}, {}
    for primitiveIndex, primitive in ipairs(model.prims) do
      local copy = {}
      for key, value in pairs(primitive) do copy[key] = value end
      copy.arenaSubmissionLayer = select(2, Materials.rootRenderMode(
        primitive.arenaRenderProfile, primitive.arenaSubmissionClass))
      local part = { prim = copy, rows = {}, sourcePartIndex = primitiveIndex }
      orderedParts[#orderedParts + 1], bySource[primitiveIndex] = part, part
    end
    Renderer.resolveArenaCoplanarLayers(model, orderedParts)
    local previousLayer = -1
    for _, part in ipairs(orderedParts) do
      local layer = tonumber(part.prim.arenaSubmissionLayer) or -1
      assert(layer >= previousLayer,
        ("arena %02d lost ROM graph submission order"):format(record.index))
      previousLayer = layer
    end
    for _, expected in ipairs(centreMaterials[record.index]) do
      local primitive = assert(bySource[expected[1]]).prim
      assert(primitive.arenaAuthoredSubmissionOrder == true
          and (tonumber(primitive.coplanarLayer) or 0) > 0,
        ("arena %02d centre is not ranked above its ROM floor layer")
          :format(record.index))
    end
  end

  if record.index == 0 then
    local parts = {}
    for primitiveIndex, primitive in ipairs(model.prims) do
      local rows, indices = {}, {}
      for vertex = 1, primitive.nverts do
        rows[vertex] = {
          primitive.pos[vertex * 3 - 2],
          primitive.pos[vertex * 3 - 1],
          primitive.pos[vertex * 3],
        }
      end
      for index, value in ipairs(primitive.idx) do indices[index] = value + 1 end
      local copy = {}
      for key, value in pairs(primitive) do copy[key] = value end
      copy.idx = indices
      parts[#parts + 1] = {
        prim = copy, rows = rows, sourcePrimitive = primitiveIndex,
      }
    end
    assert(Renderer.resolveArenaCoplanarLayers(model, parts) == 2,
      "arena 00 centre artwork lost its ROM-authored layer stack")
    local layers = {}
    for _, part in ipairs(parts) do
      if part.prim.coplanarLayer then
        layers[part.sourcePrimitive] = part.prim.coplanarLayer
      end
    end
    assert(layers[17] == 1 and layers[16] == 2,
      "arena 00 centre artwork has the wrong depth order")
  end

  if record.index == 1 then
    assert(root == 0xDB18 and u32be(decoded, 0x20) == 0x10800006
      and u32be(decoded, 0x30) == 0x24030001,
      "arena 01 entrypoint or field identifier changed")
    assert(#model.bones == 4 and #model.prims == 20 and #model.fx == 24
      and #model.textures == 23 and #model.handlerTextures == 11,
      "arena 01 graph, primitive, or texture inventory changed")
    local vertices, triangles = 0, 0
    for _, primitive in ipairs(model.prims) do
      vertices = vertices + primitive.nverts
      triangles = triangles + math.floor(primitive.nidx / 3)
    end
    assert(vertices == 628 and triangles == 423,
      "arena 01 geometry inventory changed")
    local floorPrimitive = assert(model.prims[1])
    local gravelMark, outlineMark = assert(model.prims[16]), assert(model.prims[17])
    local _, floorLayer = Materials.rootRenderMode(
      floorPrimitive.arenaRenderProfile, floorPrimitive.arenaSubmissionClass)
    local _, gravelLayer = Materials.rootRenderMode(
      gravelMark.arenaRenderProfile, gravelMark.arenaSubmissionClass)
    local _, outlineLayer = Materials.rootRenderMode(
      outlineMark.arenaRenderProfile, outlineMark.arenaSubmissionClass)
    assert(floorPrimitive.callbackOffset == 0xD6A4
      and floorPrimitive.nverts == 13 and floorPrimitive.nidx == 36
      and floorPrimitive.sourceTextureMissing == true
      and floorPrimitive.sampler.shifts == 2
      and floorPrimitive.sampler.shiftt == 2
      and floorLayer == 5
      and gravelMark.callbackOffset == 0xDA14 and gravelLayer == 6
      and outlineMark.callbackOffset == 0xDA3C and outlineLayer == 6,
      "arena 01 floor or centre-marking provenance changed")
    local floorNode
    for _, node in ipairs(model.fx) do
      if node.commandOffset == 0xD6A4 then floorNode = node end
    end
    local floorTextures = Phase5.textureSpecs(decoded, 0x8FF00000,
      assert(floorNode).arg)
    assert(#floorTextures == 2
      and floorTextures[1].pointer == 0x8FF07050
      and floorTextures[2].pointer == 0x8FF07850
      and floorTextures[1].w == 32 and floorTextures[1].h == 32
      and floorTextures[2].w == 32 and floorTextures[2].h == 32
      and floorTextures[1].sampler.cms == 1
      and floorTextures[1].sampler.cmt == 1
      and floorTextures[1].sampler.shifts == 2
      and floorTextures[1].sampler.shiftt == 2
      and floorTextures[2].sampler.shifts == 15
      and floorTextures[2].sampler.shiftt == 15,
      "arena 01 log-mask and gravel tile state changed")
    local parts = {}
    for primitiveIndex, primitive in ipairs(model.prims) do
      local rows, indices, copy = {}, {}, {}
      for key, value in pairs(primitive) do copy[key] = value end
      copy.arenaSubmissionLayer = select(2, Materials.rootRenderMode(
        primitive.arenaRenderProfile, primitive.arenaSubmissionClass))
      for vertex = 1, primitive.nverts do
        rows[vertex] = {
          primitive.pos[vertex * 3 - 2], primitive.pos[vertex * 3 - 1],
          primitive.pos[vertex * 3],
        }
      end
      for index, value in ipairs(primitive.idx) do indices[index] = value + 1 end
      copy.idx = indices
      parts[#parts + 1] = {
        prim = copy, rows = rows, sourcePrimitive = primitiveIndex,
      }
    end
    local coplanarCount = Renderer.resolveArenaCoplanarLayers(model, parts)
    local centreLayers = {}
    for _, part in ipairs(parts) do
      if part.prim.coplanarLayer then
        centreLayers[part.sourcePrimitive] = part.prim.coplanarLayer
      end
    end
    assert(coplanarCount == 8
      and centreLayers[16] == 1 and centreLayers[17] == 1,
      ("arena 01 gravel Poké Ball marking lost its floor overlay order (%s/%s/%s)")
        :format(tostring(coplanarCount),
          tostring(centreLayers[16]), tostring(centreLayers[17])))
  end

  if record.index == 3 then
    assert(root == 0xBF40 and u32be(decoded, 0x20) == 0x10800006
      and u32be(decoded, 0x30) == 0x24030001,
      "arena 03 entrypoint or field identifier changed")
    assert(#model.bones == 5 and #model.prims == 16 and #model.fx == 21
      and #model.textures == 14 and #model.handlerTextures == 7,
      "arena 03 graph, primitive, or texture inventory changed")
    local vertices, triangles = 0, 0
    for _, primitive in ipairs(model.prims) do
      vertices = vertices + primitive.nverts
      triangles = triangles + math.floor(primitive.nidx / 3)
    end
    assert(vertices == 479 and triangles == 338,
      "arena 03 geometry inventory changed")
    local floorPrimitive = assert(model.prims[3])
    local glowLeft, glowRight = assert(model.prims[7]), assert(model.prims[8])
    local _, floorLayer = Materials.rootRenderMode(
      floorPrimitive.arenaRenderProfile, floorPrimitive.arenaSubmissionClass)
    local _, leftLayer = Materials.rootRenderMode(
      glowLeft.arenaRenderProfile, glowLeft.arenaSubmissionClass)
    local _, rightLayer = Materials.rootRenderMode(
      glowRight.arenaRenderProfile, glowRight.arenaSubmissionClass)
    assert(floorLayer == 5 and leftLayer == 6 and rightLayer == 6
      and floorPrimitive.callbackOffset == 0xBC28
      and glowLeft.callbackOffset == 0xBD14
      and glowRight.callbackOffset == 0xBD3C
      and floorPrimitive.nverts == 37 and floorPrimitive.nidx == 108
      and glowLeft.nverts == 6 and glowLeft.nidx == 12
      and glowRight.nverts == 6 and glowRight.nidx == 12,
      "arena 03 floor/glow layer provenance changed")
    local function arenaPart(primitive, source)
      local copy, rows, indices = {}, {}, {}
      for key, value in pairs(primitive) do copy[key] = value end
      copy.arenaSubmissionLayer = select(2, Materials.rootRenderMode(
        primitive.arenaRenderProfile, primitive.arenaSubmissionClass))
      for vertex = 1, primitive.nverts do
        rows[vertex] = {
          primitive.pos[vertex * 3 - 2], primitive.pos[vertex * 3 - 1],
          primitive.pos[vertex * 3],
        }
      end
      for index, value in ipairs(primitive.idx) do indices[index] = value + 1 end
      copy.idx = indices
      return { prim = copy, rows = rows, sourcePrimitive = source }
    end
    local floorPart = arenaPart(floorPrimitive, 3)
    local leftPart, rightPart = arenaPart(glowLeft, 7), arenaPart(glowRight, 8)
    local layerParts = { floorPart, leftPart, rightPart }
    assert(Renderer.resolveArenaCoplanarLayers(model, layerParts) == 2,
      "arena 03 callback glow halves were not ranked above the floor")
    local glowLayers = {}
    for _, part in ipairs(layerParts) do
      if part.prim.coplanarLayer then
        glowLayers[part.sourcePrimitive] = part.prim.coplanarLayer
      end
    end
    assert(glowLayers[7] == 1 and glowLayers[8] == 1
      and floorPart.prim.coplanarLayer == nil,
      "arena 03 glow has the wrong modern depth separation")
    local leftNode, rightNode
    for _, node in ipairs(model.fx) do
      if node.commandOffset == 0xBD14 then leftNode = node end
      if node.commandOffset == 0xBD3C then rightNode = node end
    end
    local leftTextures = Phase5.textureSpecs(decoded, 0x8FF00000,
      assert(leftNode).arg)
    local rightTextures = Phase5.textureSpecs(decoded, 0x8FF00000,
      assert(rightNode).arg)
    assert(#leftTextures == 2 and #rightTextures == 2
      and leftTextures[1].pointer == 0x8FF06C50
      and leftTextures[2].pointer == 0x8FF06C50
      and rightTextures[1].pointer == 0x8FF07C50
      and rightTextures[2].pointer == 0x8FF07C50
      and leftTextures[1].w == 64 and leftTextures[1].h == 64
      and leftTextures[1].format == 4 and leftTextures[1].size == 1
      and leftTextures[1].sampler.cms == 1
      and leftTextures[1].sampler.cmt == 1,
      "arena 03 dual-I8 glow texture state changed")
    local leftController = Phase5.controllerSpec(decoded, 0x8FF00000,
      leftNode.arg)
    local rightController = Phase5.controllerSpec(decoded, 0x8FF00000,
      rightNode.arg)
    assert(leftController.colorController.offset == 0xBA58
      and rightController.colorController.offset == 0xBA58,
      "arena 03 glow halves no longer share their ROM colour pulse")
    local leftMaterial = assert(phase5MaterialBySite[0xBD14])
    local atStart = Phase5.evaluateController(leftController, leftMaterial, 0)
    local atPeak = Phase5.evaluateController(leftController, leftMaterial, 30)
    local intensity0, intensity1 = Renderer.phase5IntensityAlpha(leftMaterial,
      { formats = { 4, 4 } }, model, -1)
    assert(math.abs(atStart.primitiveColor[1] - 200 / 255) < 0.000001
      and math.abs(atStart.primitiveColor[2] - 230 / 255) < 0.000001
      and atStart.primitiveColor[3] == 1
      and math.abs(atStart.primitiveColor[4] - 100 / 255) < 0.000001
      and math.abs(atPeak.primitiveColor[1] - 250 / 255) < 0.000001
      and math.abs(atPeak.primitiveColor[2] - 250 / 255) < 0.000001
      and atPeak.primitiveColor[3] == 1 and atPeak.primitiveColor[4] == 1
      and intensity0 and intensity1,
      "arena 03 glow pulse or I8 coverage changed")
  end

  if record.index == 13 then
    -- This field combines ordinary I4 glow/shadow masks with a dual-RGBA32
    -- animated flame. Both are phase-5 inputs even though only the flame is
    -- sourced from callback-owned texture slots.
    assert(root == 0xD940 and u32be(decoded, 0x20) == 0x10800006
      and u32be(decoded, 0x30) == 0x24030045,
      "arena 13 entrypoint or field identifier changed")
    assert(#model.bones == 5 and #model.prims == 25 and #model.fx == 30
      and #model.textures == 19 and #model.handlerTextures == 10,
      "arena 13 graph, primitive, or texture inventory changed")
    local vertices, triangles, phase5Count, transformCount = 0, 0, 0, 0
    local dynamicCount, dualTextureCount, flameController = 0, 0
    for _, primitive in ipairs(model.prims) do
      vertices = vertices + primitive.nverts
      triangles = triangles + math.floor(primitive.nidx / 3)
    end
    for _, node in ipairs(model.fx) do
      if node.handler == 0x81000148 then
        phase5Count = phase5Count + 1
        local controller = Phase5.controllerSpec(decoded, 0x8FF00000, node.arg)
        local dynamic = false
        for _, item in ipairs(controller and controller.items or {}) do
          if item.controller then dynamic = true end
        end
        if dynamic then dynamicCount = dynamicCount + 1 end
        if node.commandOffset == 0xD660 then flameController = controller end
        local units = {}
        for _, texture in ipairs(Phase5.textureSpecs(
            decoded, 0x8FF00000, node.arg)) do
          units[texture.phase5Texture] = true
        end
        if units[0] and units[1] then dualTextureCount = dualTextureCount + 1 end
      elseif node.handler == 0x81000150 then
        transformCount = transformCount + 1
      end
    end
    assert(vertices == 1264 and triangles == 846 and phase5Count == 25
      and transformCount == 5 and dynamicCount == 1 and dualTextureCount == 5,
      "arena 13 geometry or phase-5 inventory changed")
    assert(model.textures[1].w == 32 and model.textures[1].h == 32
      and model.textures[1].format == 4 and model.textures[1].size == 0
      and model.textures[12].w == 64 and model.textures[12].h == 16
      and model.textures[12].format == 4 and model.textures[12].size == 0
      and model.textures[13].w == 16 and model.textures[13].h == 16
      and model.textures[13].format == 4 and model.textures[13].size == 0,
      "arena 13 ordinary I4 mask inventory changed")
    local skyGlow = assert(phase5MaterialBySite[0xD39C])
    assert(math.abs(skyGlow.primitiveColor[1] - 200 / 255) < 0.000001
      and math.abs(skyGlow.primitiveColor[2] - 150 / 255) < 0.000001
      and math.abs(skyGlow.primitiveColor[4] - 150 / 255) < 0.000001
      and skyGlow.combiner.alphaUsesPrimitive == true
      and table.concat(skyGlow.combiner.selectors, ",")
        == "3,4,1,4,1,7,4,7,31,31,31,0,0,7,3,7",
      "arena 13 radial glow material changed")
    local intensityPrimary, intensitySecondary =
      Renderer.phase5IntensityAlpha(skyGlow, nil, model, 1)
    assert(intensityPrimary and not intensitySecondary,
      "arena 13 ordinary I4 glow no longer supplies phase-5 alpha")
    local flameSecond = assert(flameController and flameController.items[2]
      and flameController.items[2].controller
      and flameController.items[2].controller.tileScroll,
      "arena 13 animated flame controller is missing")
    assert(flameController.items[1].textureWidth == 16
      and flameController.items[1].textureHeight == 32
      and flameController.items[1].sampler.cms == 0
      and flameController.items[1].sampler.cmt == 0
      and flameController.items[2].textureWidth == 16
      and flameController.items[2].textureHeight == 32
      and flameSecond.baseS == 0 and flameSecond.baseT == 0
      and flameSecond.speedS == 0 and flameSecond.speedT == 8
      and flameSecond.width == 16 and flameSecond.height == 32,
      "arena 13 animated flame texture state changed")
    local flameMaterial, _, flameScroll = Phase5.evaluateController(
      flameController, phase5MaterialBySite[0xD660], 30)
    assert(math.abs(flameMaterial.primitiveColor[1] - 40 / 255) < 0.000001
      and math.abs(flameMaterial.primitiveColor[2] - 80 / 255) < 0.000001
      and math.abs(flameMaterial.primitiveColor[3] - 120 / 255) < 0.000001
      and flameMaterial.primitiveColor[4] == 1
      and flameScroll[1] == nil
      and math.abs(flameScroll[2][1]) < 0.000001
      and math.abs(flameScroll[2][2] + 1.875) < 0.000001,
      "arena 13 flame tint or vertical tile animation changed")
    local glowPrimitive = {}
    for key, value in pairs(model.prims[1]) do glowPrimitive[key] = value end
    local glowQueue = Renderer.prepareArenaRenderQueues(model,
      {{ prim = glowPrimitive }}, function() return skyGlow end,
      function() return 1 end)
    assert(glowQueue.blend == 1 and glowPrimitive.arenaQueue == "translucent",
      "arena 13 radial glow is not using its ROM primitive alpha")
    local overlayPrimitive = {}
    for key, value in pairs(model.prims[14]) do overlayPrimitive[key] = value end
    local overlayQueue = Renderer.prepareArenaRenderQueues(model,
      {{ prim = overlayPrimitive }}, function()
        return phase5MaterialBySite[0xD6A8]
      end, function() return 14 end)
    assert(overlayQueue.blend == 1
      and overlayPrimitive.arenaAlphaMode == "blend",
      "arena 13 callback texture erased an authored translucent layer")
    for _, primitiveIndex in ipairs({ 6, 15 }) do
      local primitive = {}
      for key, value in pairs(model.prims[primitiveIndex]) do primitive[key] = value end
      local material = phase5MaterialBySite[primitive.callbackOffset]
      local queue = Renderer.prepareArenaRenderQueues(model,
        {{ prim = primitive }}, function() return material end,
        function() return primitive.tex end)
      assert(queue.opaque == 1 and primitive.arenaAlphaMode == "opaque"
        and Renderer.arenaCombinerCoveragePassthrough(model, primitive, material),
        ("arena 13 primitive %d is discarded by unused combiner alpha")
          :format(primitiveIndex))
    end
    local profiles, classes = {}, {}
    for _, primitive in ipairs(model.prims) do
      profiles[primitive.arenaRenderProfile] =
        (profiles[primitive.arenaRenderProfile] or 0) + 1
      classes[primitive.arenaSubmissionClass] =
        (classes[primitive.arenaSubmissionClass] or 0) + 1
    end
    assert(profiles[0] == 1 and profiles[2] == 24
      and classes[1] == 8 and classes[4] == 9 and classes[6] == 8
      and model.arenaLighting.prelitPrimitives == 23
      and model.arenaLighting.directionalPrimitives == 2,
      "arena 13 render-profile, layer, or lighting split changed")
  end

  if record.index == 27 then
    -- The two Classroom triangles that differ in an independent OBJ are not
    -- absent from Stadium. Primitive 17's ROM display list loads eight
    -- vertices from 0x9CB0 and submits all four triangles. The reference OBJ
    -- lifts two of those source vertices by two units, a manual overlap fix
    -- which must not be mistaken for authored ROM geometry.
    local primitive = assert(model.prims[17],
      "Classroom overlap primitive is missing")
    assert(primitive.materialOffset == 0x8168
      and primitive.callbackOffset == 0xC0C0,
      "Classroom overlap primitive provenance changed")
    assert(primitive.arenaRenderProfile == 2
      and primitive.arenaSubmissionClass == 6
      and primitive.arenaResetAfterDraw == true,
      "Classroom overlap primitive lost its authored render state")
    assert(u32be(decoded, 0xB318) == 0xD9FDFFFF
      and u32be(decoded, 0xB31C) == 0
      and u32be(decoded, 0xB320) == 0x01008010
      and u32be(decoded, 0xB324) == 0x8FF09CB0,
      "Classroom overlap display list no longer loads the expected vertices")
    assert(u32be(decoded, 0xB330) == 0x06000204
      and u32be(decoded, 0xB334) == 0x00000602
      and u32be(decoded, 0xB338) == 0x06080A0C
      and u32be(decoded, 0xB33C) == 0x00080E0A,
      "Classroom overlap display list no longer submits all four triangles")
    assert(s16be(decoded, 0x9CC0) == -546
      and s16be(decoded, 0x9CC2) == -3
      and s16be(decoded, 0x9CC4) == -1768
      and s16be(decoded, 0x9CD0) == -1186
      and s16be(decoded, 0x9CD2) == -3
      and s16be(decoded, 0x9CD4) == -1768,
      "Classroom overlap vertices no longer match the ROM-authored positions")
  end

  if record.index == 28 then
    -- Academy park stores its complete sky/horizon cyclorama in the field
    -- fragment. The entrypoint has no second model branch: mode 0 returns the
    -- four-root layout and mode 1 returns only field identifier 0x6CB5.
    assert(root == 0xE318 and u32be(decoded, 0x20) == 0x10800006
      and u32be(decoded, 0x30) == 0x24036CB5,
      "arena 28 entrypoint or field identifier changed")
    assert(#model.bones == 4 and #model.prims == 25 and #model.fx == 29
      and #model.textures == 22 and #model.handlerTextures == 10,
      "arena 28 lost a graph root, primitive, or texture")
    local phase5Count, transformCount, dynamicCount, dualTextureCount = 0, 0, 0, 0
    local waterController, fountainController
    for _, node in ipairs(model.fx) do
      if node.handler == 0x81000148 then
        phase5Count = phase5Count + 1
        local controller = Phase5.controllerSpec(decoded, 0x8FF00000, node.arg)
        if node.commandOffset == 0xDE08 then waterController = controller end
        if node.commandOffset == 0xE0A4 then fountainController = controller end
        local dynamic = false
        for _, item in ipairs(controller and controller.items or {}) do
          if item.controller then dynamic = true end
        end
        if dynamic then dynamicCount = dynamicCount + 1 end
        local units = {}
        for _, texture in ipairs(Phase5.textureSpecs(
            decoded, 0x8FF00000, node.arg)) do
          units[texture.phase5Texture] = true
        end
        if units[0] and units[1] then dualTextureCount = dualTextureCount + 1 end
      elseif node.handler == 0x81000150 then
        transformCount = transformCount + 1
      end
    end
    assert(phase5Count == 25 and transformCount == 4
      and dynamicCount == 2 and dualTextureCount == 6,
      "arena 28 callback/controller inventory changed")
    local water0 = assert(waterController and waterController.items[1]
      and waterController.items[1].controller
      and waterController.items[1].controller.tileScroll,
      "arena 28 water TEXEL0 scroll controller is missing")
    local water1 = assert(waterController.items[2]
      and waterController.items[2].controller
      and waterController.items[2].controller.tileScroll,
      "arena 28 water TEXEL1 scroll controller is missing")
    local fountain1 = assert(fountainController and fountainController.items[2]
      and fountainController.items[2].controller
      and fountainController.items[2].controller.tileScroll,
      "arena 28 fountain scroll controller is missing")
    assert(water0.baseS == 0 and water0.baseT == 0
      and water0.speedS == 1 and water0.speedT == -1
      and water0.width == 32 and water0.height == 32
      and water1.baseS == 0 and water1.baseT == 0
      and water1.speedS == 1 and water1.speedT == 1
      and waterController.items[1].sampler.cms == 0
      and waterController.items[1].sampler.cmt == 0
      and waterController.items[2].sampler.cms == 1
      and waterController.items[2].sampler.cmt == 1,
      "arena 28 opposing water tile-scroll values changed")
    assert(fountain1.baseS == 0 and fountain1.baseT == 0
      and fountain1.speedS == 0 and fountain1.speedT == -6
      and fountain1.width == 32 and fountain1.height == 32
      and fountainController.items[1].sampler.cms == 2
      and fountainController.items[1].sampler.cmt == 2
      and fountainController.items[2].sampler.cms == 0
      and fountainController.items[2].sampler.cmt == 0,
      "arena 28 fountain tile-scroll values changed")
    local waterMaterial = assert(phase5MaterialBySite[0xDE08])
    local animatedWater, _, waterScroll = Phase5.evaluateController(
      waterController, waterMaterial, 16)
    local _, _, fountainScroll = Phase5.evaluateController(
      fountainController, phase5MaterialBySite[0xE0A4], 1)
    assert(math.abs(animatedWater.primitiveColor[4] - 130 / 255) < 0.000001
      and waterMaterial.combiner.alphaUsesPrimitive == true
      and math.abs(waterScroll[1][1] - 0.125) < 0.000001
      and math.abs(waterScroll[1][2] - 0.125) < 0.000001
      and math.abs(waterScroll[2][1] - 0.125) < 0.000001
      and math.abs(waterScroll[2][2] + 0.125) < 0.000001,
      "arena 28 water color/alpha or opposing animated UVs changed")
    assert(fountainScroll[1] == nil
      and math.abs(fountainScroll[2][1]) < 0.000001
      and math.abs(fountainScroll[2][2] - 6 / 128) < 0.000001,
      "arena 28 fountain animated UV changed")
    local left, right = assert(model.prims[1]), assert(model.prims[2])
    assert(left.nverts == 23 and left.nidx == 54 and left.tex == 0
      and left.callbackOffset == 0xDDA0
      and right.nverts == 21 and right.nidx == 54 and right.tex == 1
      and right.callbackOffset == 0xDDD0,
      "arena 28 sky/horizon batches changed")
    local minX, maxX, minY, maxY, minZ, maxZ = math.huge, -math.huge,
      math.huge, -math.huge, math.huge, -math.huge
    for _, primitive in ipairs({left, right}) do
      for at = 1, #primitive.pos, 3 do
        minX, maxX = math.min(minX, primitive.pos[at]),
          math.max(maxX, primitive.pos[at])
        minY, maxY = math.min(minY, primitive.pos[at + 1]),
          math.max(maxY, primitive.pos[at + 1])
        minZ, maxZ = math.min(minZ, primitive.pos[at + 2]),
          math.max(maxZ, primitive.pos[at + 2])
      end
    end
    assert(minX == -9939 and maxX == 9939 and minY == 0 and maxY == 4410
      and minZ == -9939 and maxZ == 9939,
      "arena 28 sky/horizon extent changed")
    for textureIndex = 1, 2 do
      local texture = assert(model.textures[textureIndex])
      assert(texture.w == 64 and texture.h == 32 and texture.format == 0
        and texture.size == 2,
        "arena 28 sky texture metadata changed")
      for alpha = 4, #texture.rgba, 4 do
        assert(texture.rgba:byte(alpha) == 255,
          "arena 28 sky texture unexpectedly contains transparency")
      end
    end
    local skyMaterial = assert(phase5MaterialBySite[0xDDA0])
    local rightSkyMaterial = assert(phase5MaterialBySite[0xDDD0])
    assert(skyMaterial.combiner and skyMaterial.combiner.cycles == 2
      and skyMaterial.combiner.alphaOutputZero == true
      and table.concat(skyMaterial.combiner.selectors, ",")
        == "1,3,4,5,7,7,7,7,31,31,31,0,7,7,7,7",
      "arena 28 opaque sky combiner changed")
    assert(table.concat(rightSkyMaterial.combiner.selectors, ",")
        == table.concat(skyMaterial.combiner.selectors, ",")
      and rightSkyMaterial.combiner.alphaOutputZero == true,
      "arena 28 second sky batch lost its shared opaque combiner")
    assert(Renderer.arenaCombinerCoveragePassthrough(model,
      { arenaAlphaMode = left.alphaMode }, skyMaterial),
      "arena 28 opaque sky would be discarded as zero-alpha geometry")
    local waterPrimitive = {}
    for key, value in pairs(assert(model.prims[3])) do waterPrimitive[key] = value end
    local waterQueue = Renderer.prepareArenaRenderQueues(model,
      {{ prim = waterPrimitive }}, function() return animatedWater end,
      function() return 1 end)
    assert(waterPrimitive.arenaAlphaMode == "blend"
      and waterPrimitive.arenaQueue == "translucent",
      "arena 28 water plane is not using its ROM animated alpha")
    local opaque, cutout, blend, unusedZeroAlpha = 0, 0, 0, 0
    for _, primitive in ipairs(model.prims) do
      local mode = primitive.alphaMode or "opaque"
      if mode == "opaque" then opaque = opaque + 1
      elseif mode == "cutout" then cutout = cutout + 1
      elseif mode == "blend" then blend = blend + 1 end
      local material = phase5MaterialBySite[primitive.callbackOffset]
      if material and material.combiner and material.combiner.alphaOutputZero
          and mode ~= "blend" then unusedZeroAlpha = unusedZeroAlpha + 1 end
    end
    assert(opaque == 12 and cutout == 7 and blend == 6
      and unusedZeroAlpha == 8
      and model.arenaLighting.prelitPrimitives == 25
      and model.arenaLighting.directionalPrimitives == 0,
      "arena 28 alpha or lighting inventory changed")
  end

  totals.bones = totals.bones + #model.bones
  totals.primitives = totals.primitives + #model.prims
  totals.textures = totals.textures + #model.textures
  totals.handlerTextures = totals.handlerTextures + #model.handlerTextures
  local handlerTextureSites = {}
  for _, texture in ipairs(model.handlerTextures) do
    handlerTextureSites[texture.commandOffset] = true
  end
  totals.warnings = totals.warnings + #model.warnings
  for _, node in ipairs(model.fx) do
    if node.handler == 0x81000148 then totals.phase5 = totals.phase5 + 1 end
    if node.handler == 0x81000150 then
      totals.stageTransformColor = totals.stageTransformColor + 1
    end
  end
  for _, primitive in ipairs(model.prims) do
    local phase5Material = phase5MaterialBySite[primitive.callbackOffset]
    if phase5Material and phase5Material.combiner
        and phase5Material.combiner.alphaOutputZero
        and primitive.alphaMode ~= "blend" then
      totals.opaqueZeroAlpha = totals.opaqueZeroAlpha + 1
    end
    if primitive.arenaRenderProfile ~= nil then
      totals.renderProfiles = totals.renderProfiles + 1
    end
    if primitive.arenaSubmissionClass ~= nil then
      totals.submissionLayers = totals.submissionLayers + 1
    end
    if primitive.arenaResetAfterDraw then
      totals.stateResets = totals.stateResets + 1
    end
    totals[primitive.alphaMode or "opaque"] =
      totals[primitive.alphaMode or "opaque"] + 1
    totals.vertices = totals.vertices + (primitive.nverts or 0)
    totals.triangles = totals.triangles + math.floor((primitive.nidx or 0) / 3)
    if primitive.callbackTextureRequired then
      totals.callbackTexturePrimitives = totals.callbackTexturePrimitives + 1
      assert(primitive.callbackDescriptor == 0x81000148,
        ("arena %d callback texture has the wrong owner"):format(record.index))
      assert(handlerTextureSites[primitive.callbackOffset],
        ("arena %d callback texture was not decoded"):format(record.index))
    end
    for i = 1, primitive.nidx or 0 do
      local index = primitive.idx[i]
      assert(index >= 0 and index < primitive.nverts,
        ("arena %d has an out-of-range vertex index"):format(record.index))
    end
  end
end

-- Exact totals make changes to traversal, display-list state, or the known US
-- archive visible instead of silently producing incomplete exports.
print(("arena extraction totals: textures=%d handlerTextures=%d callbackPrimitives=%d alpha=%d/%d/%d")
  :format(totals.textures, totals.handlerTextures, totals.callbackTexturePrimitives,
    totals.opaque, totals.cutout, totals.blend))
assert(totals.bones == 122, "unexpected stage transform count")
assert(totals.primitives == 537, "unexpected stage primitive count")
assert(totals.vertices == 22033, "unexpected stage vertex count")
assert(totals.triangles == 15136, "unexpected stage triangle count")
-- Three arena images are reachable only through phase-5 controller tables;
-- retaining the old 479/164 totals silently froze those animated materials.
assert(totals.textures == 482, "unexpected stage texture count")
assert(totals.handlerTextures == 167, "unexpected stage callback texture count")
assert(totals.callbackTexturePrimitives == 94,
  "unexpected callback-owned stage primitive count")
assert(totals.phase5 == 533, "unexpected stage phase-5 callback count")
assert(totals.renderProfiles == 537 and totals.submissionLayers == 537,
  "arena graph render profile/submission metadata was not retained")
-- 534 flagged display-list nodes cover every one of the 537 material-split
-- output primitives (three nodes emit two primitive batches).
assert(totals.stateResets == 537,
  "arena graph post-submission reset flags were not retained")
assert(totals.stageTransformColor == 122,
  "unexpected stage transform/color callback count")
assert(totals.opaque == 295 and totals.cutout == 118 and totals.blend == 124,
  "unexpected Stadium field alpha queue classification")
assert(totals.opaqueZeroAlpha == 220,
  "unexpected count of opaque/cutout zero-alpha RDP submissions")
assert(totals.prelit == 507 and totals.directional == 30,
  ("unexpected Stadium field prelit/directional lighting split: %d/%d")
    :format(totals.prelit, totals.directional))
assert(totals.warnings == 0, "stage extraction emitted warnings")

print(("30 arenas passed: %d vertices, %d triangles, %d textures")
  :format(totals.vertices, totals.triangles, totals.textures))
