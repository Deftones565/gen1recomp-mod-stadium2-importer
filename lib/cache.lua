-- Sandboxed, playthrough-scoped Stadium model cache. Binary DSM payloads are
-- stored as strings inside mod.storage records; no raw filesystem path is
-- exposed to this module.
local Cache = {}

Cache.FORMAT = "S2IMP32"
Cache.ROOT = "stadium2_importer"
Cache.NORMAL = Cache.ROOT .. "/normal"
Cache.SHINY = Cache.ROOT .. "/shiny"
Cache.BATTLE = Cache.ROOT .. "/battle"
Cache.MARKER = Cache.ROOT .. "/pack.info"
Cache.ERROR = Cache.ROOT .. "/import_error.log"
Cache.UNOWN_FORMS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"

local modRef

function Cache.bind(mod)
  modRef = mod
  return Cache
end

local function storageContext()
  local storage = modRef and modRef.storage
  local game = modRef and modRef.game
  if not (storage and game) then
    return nil, nil, "sandbox storage unavailable before game.ready"
  end
  return storage, game
end

local function storageKey(path)
  path = tostring(path or "")
  if path == Cache.MARKER then return "cache/marker" end
  if path == Cache.ERROR then return "cache/error" end
  path = path:gsub("^" .. Cache.ROOT .. "/", ""):gsub("%.dsm$", "")
  return "cache/" .. path
end

local function readRecord(path)
  local storage, game = storageContext()
  if not storage then return nil end
  local ok, value = pcall(storage.read, storage, game, storageKey(path))
  if not ok or type(value) ~= "table" then return nil end
  return value
end

local function writeRecord(path, value)
  local storage, game, unavailable = storageContext()
  if not storage then return false, unavailable end
  local ok, wrote, code, message = pcall(storage.write, storage, game,
    storageKey(path), value)
  if not ok then return false, tostring(wrote) end
  if not wrote then return false, tostring(message or code or "storage write failed") end
  return true
end

local function deleteRecord(path)
  local storage, game = storageContext()
  if not storage then return false end
  pcall(storage.delete, storage, game, storageKey(path))
  return true
end

function Cache.path(species, variant)
  local dir = variant == "shiny" and Cache.SHINY or Cache.NORMAL
  return ("%s/%03d.dsm"):format(dir, species)
end

function Cache.specialPath(name)
  return ("%s/%s.dsm"):format(Cache.BATTLE,tostring(name))
end

function Cache.unownPath(letter,variant)
  letter=tostring(letter or "a"):lower()
  local suffix=variant=="shiny" and "_shiny" or ""
  return Cache.specialPath("unown_"..letter..suffix)
end

function Cache.ensureDirectories()
  local storage, game, unavailable = storageContext()
  if not storage then return false, unavailable end
  local ok, context, code, message = pcall(storage.context, storage, game)
  if not ok then return false, tostring(context) end
  if not context then return false, tostring(message or code or "storage unavailable") end
  return true
end

function Cache.clear(count)
  local ok, err = Cache.ensureDirectories()
  if not ok then return false, err end
  local storage,game=storageContext()
  if storage and type(storage.list)=="function" then
    local listed,keys=pcall(storage.list,storage,game,"cache")
    if listed and type(keys)=="table" then
      for _,key in ipairs(keys) do pcall(storage.delete,storage,game,key) end
      return true
    end
  end
  count = math.max(251, tonumber(count) or 251)
  for species = 1, count do
    deleteRecord(Cache.path(species, "normal"))
    deleteRecord(Cache.path(species, "shiny"))
  end
  deleteRecord(Cache.MARKER)
  deleteRecord(Cache.ERROR)
  deleteRecord(Cache.specialPath("substitute"))
  for i=2,#Cache.UNOWN_FORMS do
    local letter=Cache.UNOWN_FORMS:sub(i,i)
    deleteRecord(Cache.unownPath(letter,"normal"))
    deleteRecord(Cache.unownPath(letter,"shiny"))
  end
  return true
end

function Cache.writeSpecial(name,bytes)
  return writeRecord(Cache.specialPath(name), { bytes=bytes })
end

function Cache.writePair(species, normalBytes, shinyBytes)
  local ok, err = writeRecord(Cache.path(species,"normal"), {bytes=normalBytes})
  if not ok then return false, err end
  return writeRecord(Cache.path(species,"shiny"), {bytes=shinyBytes})
end

function Cache.marker()
  local record=readRecord(Cache.MARKER)
  return record and record.marker or nil
end

function Cache.available(count)
  count = tonumber(count) or 151
  local marker = Cache.marker()
  return marker ~= nil and marker.format == Cache.FORMAT
    and (marker.count or 0) >= count
end

function Cache.finish(meta, count)
  return writeRecord(Cache.MARKER, {marker={
    format=Cache.FORMAT,
    count=count,
    md5=meta and meta.md5 or "unknown",
    title=meta and meta.title or "unknown",
    byteOrder=meta and meta.byteOrder or "unknown",
  }})
end

function Cache.writeError(text)
  writeRecord(Cache.ERROR, {text=tostring(text or "unknown error")})
end

function Cache.read(species, variant)
  local record=readRecord(Cache.path(species,variant))
  return record and record.bytes or nil
end

function Cache.readSpecial(name)
  local record=readRecord(Cache.specialPath(name))
  return record and record.bytes or nil
end

return Cache
