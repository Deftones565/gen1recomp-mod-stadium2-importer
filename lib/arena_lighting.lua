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

local PARK_TIME = {
  MORN = {
    bands={{.63,.76,.93},{.70,.82,.96},{.78,.87,.97},{.86,.92,.98}},
    modelTint={1,.96,.88}, ambient={.74,.71,.65}, diffuse={.26,.24,.20},
    shadowStrength=.50,
    arenaTint={1,.94,.84},
  },
  DAY = {
    bands={{.55,.70,.91},{.60,.75,.94},{.67,.81,.96},{.76,.87,.97},{.84,.91,.98}},
    modelTint={1,1,1}, ambient={AMBIENT,AMBIENT,AMBIENT},
    diffuse={DIRECTIONAL,DIRECTIONAL,DIRECTIONAL}, shadowStrength=.62,
    arenaTint={1,1,1},
  },
  EVE = {
    bands={{.32,.40,.62},{.47,.50,.68},{.66,.59,.69},{.82,.68,.67}},
    modelTint={1,.78,.66}, ambient={.58,.48,.44}, diffuse={.30,.23,.20},
    shadowStrength=.43,
    arenaTint={1,.72,.57},
  },
  NITE = {
    bands={{.055,.075,.15},{.075,.105,.20},{.11,.15,.27},{.16,.21,.34}},
    modelTint={.56,.64,.84}, ambient={.40,.44,.57}, diffuse={.18,.21,.30},
    shadowStrength=.32,
    arenaTint={.42,.50,.70},
  },
  DARK = {
    bands={{.025,.035,.075},{.04,.055,.11},{.065,.085,.15}},
    modelTint={.42,.48,.66}, ambient={.31,.34,.45}, diffuse={.13,.15,.22},
    shadowStrength=.24,
    arenaTint={.31,.36,.52},
  },
}

local function replace3(result,name,source)
  if source[name] then result[name]=copy3(source[name]) end
end

function ArenaLighting.environment(stageIndex,timeOfDay)
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
  local period=tonumber(stageIndex)==28 and PARK_TIME[tostring(timeOfDay or ""):upper()]
  if period then
    result.bands={}
    for index,band in ipairs(period.bands) do result.bands[index]=copy3(band) end
    replace3(result,"ambient",period)
    replace3(result,"diffuse",period)
    replace3(result,"modelTint",period)
    replace3(result,"arenaTint",period)
    result.shadowStrength=period.shadowStrength
    result.timeOfDay=tostring(timeOfDay):upper()
    result.source=result.source.."+beta-gen2-time-of-day"
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
