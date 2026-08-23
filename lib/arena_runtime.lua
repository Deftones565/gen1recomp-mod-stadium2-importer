-- Opt-in Stadium field runtime used by the BETA ARENA TEST setting.
-- It deliberately remains separate from ordinary model caching: arenas are
-- decoded only after the option is enabled, one field is retained per battle,
-- and any failure lets the generation adapter fall back to the classic scene.
local Rom = require("mods.STADIUM2_IMPORTER.lib.rom")
local Fragment = require("mods.STADIUM2_IMPORTER.lib.fragment")
local Handlers = require("mods.STADIUM2_IMPORTER.lib.model_handlers")
local Materials = require("mods.STADIUM2_IMPORTER.lib.materials")
local Pack = require("mods.STADIUM2_IMPORTER.lib.pack")
local Discovery = require("mods.STADIUM2_IMPORTER.lib.discovery")

local Arena = {}
Arena.COUNT = Rom.STADIUM_MODEL_TABLE_RECORDS
Arena.SCALE = .05
Arena.GROUND_Y = 0

local packedRecords
local encounterSerial = 0

local function arenaName(index)
  return ("arena_%02d"):format(index)
end

local function sourceRecords()
  if packedRecords then return packedRecords end
  local candidate = Discovery.find()
  if not candidate then return nil, "the engine-managed Stadium 2 ROM is unavailable" end
  local bytes, readError = Discovery.read(candidate)
  if not bytes then return nil, readError end
  local normalized, order = Rom.normalise(bytes)
  if not normalized then return nil, order end
  if #normalized ~= Rom.SIZE or Rom.title(normalized):upper() ~= Rom.US_TITLE then
    return nil, "the configured import is not the supported Stadium 2 US ROM"
  end
  local archive = Rom.archiveAt(normalized, Rom.STADIUM_MODEL_TABLE_START)
  if not archive or archive.count ~= Arena.COUNT then
    return nil, "the Stadium field archive is unavailable"
  end
  local records = {}
  for index = 1, Arena.COUNT do
    records[index] = Rom.recordBytes(normalized, archive.records[index])
    if not records[index] then return nil, "a Stadium field record is unavailable" end
  end
  -- Retain only the small compressed field records, not the 64 MiB ROM.
  packedRecords = records
  return packedRecords
end

local function oneBasedModel(model)
  if type(model.rootScale) == "table" then
    model.rootScaleVector = model.rootScale
    model.rootScale = tonumber(model.rootScale[1]) or 1
  end
  model.staticPose = true
  for _, primitive in ipairs(model.prims or {}) do
    primitive.tex = primitive.tex and primitive.tex >= 0
      and primitive.tex + 1 or 0x10000
    primitive.additive = primitive.blend == "add"
    for i, vertexIndex in ipairs(primitive.idx or {}) do
      primitive.idx[i] = vertexIndex + 1
    end
    for key, textureIndex in pairs(primitive.texMap or {}) do
      primitive.texMap[key] = textureIndex + 1
    end
    for i, textureIndex in ipairs(primitive.fxFrames or {}) do
      primitive.fxFrames[i] = textureIndex + 1
    end
  end
  return model
end

function Arena.build(decoded, index, importer)
  index = math.floor(tonumber(index) or 0) % Arena.COUNT
  if type(decoded) ~= "string" then return nil, "arena fragment is unavailable" end
  if not (importer and type(importer.newRendererFromModel) == "function") then
    return nil, "arena renderer factory is unavailable"
  end
  Fragment.setBase(0x8FF00000)
  local model, extractError = Fragment.extractStage(decoded, arenaName(index), index)
  if not model then return nil, extractError end
  model.handlers = Handlers.readExtension(Handlers.packExtension(
    Handlers.compile(model.fx, decoded, 0x8FF00000), 0x8FF00000, decoded,
    { prims = model.prims, handlerTextures = model.handlerTextures }))
  Materials.attach(model)
  oneBasedModel(model)
  local renderer, rendererError = importer.newRendererFromModel(model, {
    textureFilter = "nearest",
  })
  if not renderer then
    Pack.release(model)
    return nil, rendererError
  end
  local runtime = {
    index = index,
    model = model,
    renderer = renderer,
    scale = Arena.SCALE,
    groundY = Arena.GROUND_Y,
    environment = model.arenaLighting and model.arenaLighting.environment or nil,
  }
  function runtime:release()
    if self.renderer and self.renderer.release then pcall(self.renderer.release, self.renderer) end
    if self.model then Pack.release(self.model) end
    self.renderer, self.model = nil, nil
  end
  return runtime
end

function Arena.load(index, importer)
  local records, sourceError = sourceRecords()
  if not records then return nil, sourceError end
  index = math.floor(tonumber(index) or 0) % Arena.COUNT
  local decoded, decodeError = Rom.decompress(records[index + 1])
  if not decoded then return nil, decodeError end
  return Arena.build(decoded, index, importer)
end

-- Presentation-only pseudo-randomness. Never consume the game's battle RNG.
function Arena.randomIndex(encounter)
  encounterSerial = encounterSerial + 1
  local hash = 2166136261
  local text = tostring(encounter) .. ":" .. tostring(encounterSerial)
  for i = 1, #text do hash = (hash * 16777619 + text:byte(i)) % 0x80000000 end
  local timer = love and love.timer and love.timer.getTime
  if type(timer) == "function" then
    local ok, value = pcall(timer)
    if ok then hash = (hash + math.floor((tonumber(value) or 0) * 1000000)) % 0x80000000 end
  end
  return hash % Arena.COUNT
end

function Arena.random(encounter, importer)
  local index = Arena.randomIndex(encounter)
  return Arena.load(index, importer)
end

function Arena.resetForTests()
  packedRecords = nil
  encounterSerial = 0
end

return Arena
