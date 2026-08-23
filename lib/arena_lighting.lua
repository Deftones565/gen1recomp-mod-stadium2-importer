-- Stadium 2 field modules mostly store their lighting as vertex RGB. They do
-- not contain a field-local Lights structure: normal-bearing submissions use
-- the battle renderer's shared neutral directional light. Keep that split
-- explicit so a modern shader never lights the already-lit field colours a
-- second time.
local ArenaLighting = {}

-- The direction is the normalized form of the shared Stadium shade vector
-- used by the importer before arena rendering was separated. The intensity
-- split uses the neutral B2 graph colour authored by Stadium's field path as
-- the ambient floor; the remaining range belongs to the directional term.
local AMBIENT = 0xB2 / 0xFF
local DIRECTIONAL = 1 - AMBIENT
local DIRECTION_LENGTH = math.sqrt(0.06 * 0.06 + 0.225 * 0.225 + 0.11 * 0.11)

ArenaLighting.DEFAULT = {
  bands = {{0.008, 0.01, 0.014}},
  -- Battle lighting stores the direction the rays travel. The shader negates
  -- it for Lambert's surface-to-light vector; the shadow camera uses it as-is.
  light = {-0.06 / DIRECTION_LENGTH, -0.225 / DIRECTION_LENGTH,
    -0.11 / DIRECTION_LENGTH},
  ambient = {AMBIENT, AMBIENT, AMBIENT},
  diffuse = {DIRECTIONAL, DIRECTIONAL, DIRECTIONAL},
  modelTint = {1, 1, 1},
  shadowStrength = 0.62,
  modernLighting = true,
  source = "rom-prelit-plus-shared-directional",
}

-- Arena 28 contains its own two-batch, fully opaque sky/horizon cyclorama.
-- Keep a matching clear behind it for viewer cameras that travel outside the
-- fixed Stadium shot volume; this is a modern edge fill, not substitute arena
-- geometry or the classic battle sky.
local BACKDROPS = {
  [28] = {
    bands = {
      {0.55, 0.70, 0.91}, {0.60, 0.75, 0.94}, {0.67, 0.81, 0.96},
      {0.76, 0.87, 0.97}, {0.84, 0.91, 0.98},
    },
    backdrop = true,
    outdoor = true,
    backdropSource = "arena28-rom-cyclorama-edge-fill",
  },
}

local function copy3(value)
  return {value[1], value[2], value[3]}
end

function ArenaLighting.environment(stageIndex)
  local source = ArenaLighting.DEFAULT
  local result = {
    bands = {{source.bands[1][1], source.bands[1][2], source.bands[1][3]}},
    light = copy3(source.light),
    ambient = copy3(source.ambient),
    diffuse = copy3(source.diffuse),
    modelTint = copy3(source.modelTint),
    shadowStrength = source.shadowStrength,
    modernLighting = true,
    source = source.source,
  }
  local backdrop = BACKDROPS[tonumber(stageIndex)]
  if backdrop then
    result.bands = {}
    for index, band in ipairs(backdrop.bands) do result.bands[index] = copy3(band) end
    result.backdrop = true
    result.outdoor = backdrop.outdoor == true
    result.backdropSource = backdrop.backdropSource
  end
  return result
end

-- Retain a ROM-semantics audit on each extracted field. This is useful to API
-- consumers and prevents later renderer work from silently treating baked
-- vertex colours as normals.
function ArenaLighting.analyse(model)
  local result = {
    mode = "hybrid-prelit",
    source = "stadium2-field-display-lists",
    prelitPrimitives = 0,
    directionalPrimitives = 0,
    prelitVertices = 0,
    directionalVertices = 0,
    environment = ArenaLighting.environment(model and model.stageIndex),
  }
  for _, primitive in ipairs(type(model) == "table" and model.prims or {}) do
    local count = tonumber(primitive.nverts)
      or math.floor(#(primitive.pos or {}) / 3)
    if primitive.vertexSemantics == "normal" and primitive.lighting ~= false then
      result.directionalPrimitives = result.directionalPrimitives + 1
      result.directionalVertices = result.directionalVertices + count
    else
      result.prelitPrimitives = result.prelitPrimitives + 1
      result.prelitVertices = result.prelitVertices + count
    end
  end
  return result
end

function ArenaLighting.attach(model)
  if type(model) == "table" then model.arenaLighting = ArenaLighting.analyse(model) end
  return model
end

return ArenaLighting
