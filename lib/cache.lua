-- Sandboxed, playthrough-scoped Stadium model cache.
-- Metadata is stored as data-only records; DSM model packs use the engine's
-- opaque byte storage. Legacy { bytes = ... } records remain readable so an
-- existing valid cache is not invalidated merely by upgrading this mod.
local Cache = {}

Cache.FORMAT = "S2IMP38"
Cache.ROOT = "stadium2_importer"
Cache.NORMAL = Cache.ROOT .. "/normal"
Cache.SHINY = Cache.ROOT .. "/shiny"
Cache.BATTLE = Cache.ROOT .. "/battle"
Cache.MARKER = Cache.ROOT .. "/pack.info"
Cache.ERROR = Cache.ROOT .. "/import_error.log"
Cache.UNOWN_FORMS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"

local modRef

local COMPRESSED_MAGIC = "S2Z1"

local function u32le(v)
  return string.char(v % 256, math.floor(v / 256) % 256,
    math.floor(v / 65536) % 256, math.floor(v / 16777216) % 256)
end

local function readU32le(s, p)
  local a, b, c, d = s:byte(p, p + 3)
  if not d then return nil end
  return a + b * 256 + c * 65536 + d * 16777216
end

-- Storage is an implementation detail of the importer API. Compress DSM
-- payloads before the engine's transactional write (tmp/main/backup plus
-- verification reads), then unwrap them before returning from Cache.read.
-- Existing raw caches and non-DSM test payloads remain valid.
local function encodeBlob(bytes)
  if type(bytes) ~= "string" or #bytes < 1024 or bytes:sub(1, 4) ~= "DSM4" then
    return bytes
  end
  local data = love and love.data
  if not (data and type(data.compress) == "function") then return bytes end
  local ok, packed = pcall(data.compress, "string", "lz4", bytes, 0)
  if ok and type(packed) == "string" and #packed + 8 < #bytes then
    return COMPRESSED_MAGIC .. u32le(#bytes) .. packed
  end
  return bytes
end

local function decodeBlob(bytes)
  if type(bytes) ~= "string" or bytes:sub(1, 4) ~= COMPRESSED_MAGIC then
    return bytes
  end
  local rawLength = readU32le(bytes, 5)
  local data = love and love.data
  if not rawLength or not (data and type(data.decompress) == "function") then
    return nil, "compressed cache payload cannot be decoded"
  end
  local ok, raw = pcall(data.decompress, "string", "lz4", bytes:sub(9))
  if not ok or type(raw) ~= "string" or #raw ~= rawLength
      or raw:sub(1, 4) ~= "DSM4" then
    return nil, "compressed cache payload is corrupt"
  end
  return raw
end

function Cache.bind(mod)
  modRef = mod
  return Cache
end

local function storageContext()
  local storage = modRef and modRef.storage
  local game = modRef and modRef.game
  if not (storage and game) then
    return nil, nil, "storage_unavailable",
      "sandbox storage unavailable before a live game exists"
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

local function callStorage(method, ...)
  if type(method) ~= "function" then
    return nil, "storage_unavailable", "storage method is unavailable"
  end
  local ok, a, b, c = pcall(method, ...)
  if not ok then
    return nil, "storage_exception", tostring(a)
  end
  return a, b, c
end

local function readRecord(path)
  local storage, game, code, message = storageContext()
  if not storage then return nil, code, message end
  local value, readCode, readMessage =
    callStorage(storage.read, storage, game, storageKey(path))
  if value == nil then
    return nil, readCode or "not_found", readMessage or "storage record unavailable"
  end
  if type(value) ~= "table" then
    return nil, "invalid_record", "storage record is not a table"
  end
  return value
end

local function writeRecord(path, value)
  local storage, game, code, message = storageContext()
  if not storage then return false, code, message end
  local wrote, writeCode, writeMessage =
    callStorage(storage.write, storage, game, storageKey(path), value)
  if wrote == true then return true end
  return false, writeCode or "write_failed",
    writeMessage or "storage write failed"
end

local function readBlob(path)
  local storage, game, code, message = storageContext()
  if not storage then return nil, code, message end
  local key = storageKey(path)

  -- Current engine path: exact opaque bytes.
  if type(storage.readBytes) == "function" then
    local bytes, readCode, readMessage =
      callStorage(storage.readBytes, storage, game, key)
    if type(bytes) == "string" then return decodeBlob(bytes) end

    -- A pre-fix Stadium cache stored DSM bytes inside {bytes=...} table
    -- records. A type mismatch is therefore a migration signal, not a bad
    -- cache. Read the legacy record without rewriting it during cache check.
    if readCode ~= "type_mismatch" then
      return nil, readCode or "not_found", readMessage
    end
  end

  local legacy, legacyCode, legacyMessage =
    callStorage(storage.read, storage, game, key)
  if type(legacy) == "table" and type(legacy.bytes) == "string" then
    local bytes, decodeErr = decodeBlob(legacy.bytes)
    if not bytes then return nil, "invalid_record", decodeErr end
    return bytes, "legacy"
  end
  if legacy == nil then
    return nil, legacyCode or "not_found", legacyMessage
  end
  return nil, "invalid_record", "legacy cache record has no byte payload"
end

local function writeBlob(path, bytes)
  local storage, game, code, message = storageContext()
  if not storage then return false, code, message end
  local key = storageKey(path)

  if type(storage.writeBytes) == "function" then
    bytes = encodeBlob(bytes)
    local wrote, writeCode, writeMessage =
      callStorage(storage.writeBytes, storage, game, key, bytes)
    if wrote == true then return true end
    return false, writeCode or "write_failed",
      writeMessage or "opaque storage write failed"
  end

  -- Compatibility only for an older engine than the current required one.
  return writeRecord(path, { bytes = bytes })
end

local function deleteKey(key)
  local storage, game, code, message = storageContext()
  if not storage then return false, code, message end
  local deleted, deleteCode, deleteMessage =
    callStorage(storage.delete, storage, game, key)
  if deleted == true or deleteCode == "not_found" then return true end
  return false, deleteCode or "delete_failed",
    deleteMessage or "storage delete failed"
end

local function deleteRecord(path)
  return deleteKey(storageKey(path))
end

function Cache.path(species, variant)
  local dir = variant == "shiny" and Cache.SHINY or Cache.NORMAL
  return ("%s/%03d.dsm"):format(dir, species)
end

function Cache.specialPath(name)
  return ("%s/%s.dsm"):format(Cache.BATTLE, tostring(name))
end

function Cache.unownPath(letter, variant)
  letter = tostring(letter or "a"):lower()
  local suffix = variant == "shiny" and "_shiny" or ""
  return Cache.specialPath("unown_" .. letter .. suffix)
end

function Cache.context()
  local storage, game, code, message = storageContext()
  if not storage then return nil, code, message end
  local context, contextCode, contextMessage =
    callStorage(storage.context, storage, game)
  if type(context) ~= "table" then
    return nil, contextCode or "storage_unavailable", contextMessage
  end
  return context
end

function Cache.ensureDirectories()
  local context, code, message = Cache.context()
  if not context then return false, message or code end
  return true
end

function Cache.clear(count)
  local context, contextCode, contextMessage = Cache.context()
  if not context then return false, contextMessage or contextCode end

  local storage, game = storageContext()
  if storage and type(storage.list) == "function" then
    local keys, listCode, listMessage =
      callStorage(storage.list, storage, game, "cache")
    if type(keys) == "table" then
      for _, key in ipairs(keys) do
        local ok, code, message = deleteKey(key)
        if not ok then return false, message or code end
      end
      return true
    end
    -- A real enumeration error must not silently fall through and pretend the
    -- cache was cleared. The fallback below is only for engines with no list.
    if listCode and listCode ~= "not_found" then
      return false, listMessage or listCode
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
  for i = 2, #Cache.UNOWN_FORMS do
    local letter = Cache.UNOWN_FORMS:sub(i, i)
    deleteRecord(Cache.unownPath(letter, "normal"))
    deleteRecord(Cache.unownPath(letter, "shiny"))
  end
  return true
end

function Cache.writeSpecial(name, bytes)
  return writeBlob(Cache.specialPath(name), bytes)
end

function Cache.writePair(species, normalBytes, shinyBytes)
  local ok, code, message = writeBlob(Cache.path(species, "normal"), normalBytes)
  if not ok then return false, message or code end
  ok, code, message = writeBlob(Cache.path(species, "shiny"), shinyBytes)
  if not ok then return false, message or code end
  return true
end

function Cache.marker()
  local record, code, message = readRecord(Cache.MARKER)
  if not record then return nil, code, message end
  if type(record.marker) ~= "table" then
    return nil, "invalid_marker", "cache marker record is malformed"
  end
  return record.marker
end

local function listCacheKeys()
  local storage, game, code, message = storageContext()
  if not storage then return nil, code, message end
  if type(storage.list) ~= "function" then return nil, "storage_unavailable", "storage list is unavailable" end
  local keys, listCode, listMessage = callStorage(storage.list, storage, game, "cache")
  if type(keys) ~= "table" then
    return nil, listCode or "storage_unavailable", listMessage
  end
  local set = {}
  for _, key in ipairs(keys) do set[key] = true end
  return set
end

-- Distinguish a genuinely missing/stale cache from a storage access failure.
-- Only the former is a reason for automatic ROM extraction.
function Cache.inspect(count)
  count = math.max(151, math.min(251, tonumber(count) or 151))
  local context, contextCode, contextMessage = Cache.context()
  if not context then
    return {
      state = "error",
      code = contextCode or "storage_unavailable",
      message = contextMessage or "persistent storage is unavailable",
    }
  end

  local marker, code, message = Cache.marker()
  if not marker then
    if code == "not_found" then
      return { state = "missing", code = code, message = message, context = context }
    end
    if code == "invalid_marker" then
      return { state = "stale", code = code, message = message, context = context }
    end
    return {
      state = "error",
      code = code or "storage_unavailable",
      message = message or "could not read cache marker",
      context = context,
    }
  end

  if marker.format ~= Cache.FORMAT then
    return {
      state = "stale",
      code = "format_mismatch",
      message = ("cache format %s != %s"):format(tostring(marker.format), Cache.FORMAT),
      marker = marker,
      context = context,
    }
  end

  local storedCount = tonumber(marker.count) or 0
  if storedCount < count then
    return {
      state = "incomplete",
      code = "count_too_small",
      message = ("cache has %d species; %d required"):format(storedCount, count),
      marker = marker,
      context = context,
    }
  end

  -- The completion marker is written last, but also verify that the logical
  -- payload keys still exist. This catches manually deleted/corrupt cache
  -- trees without reading hundreds of large DSM blobs into memory.
  local keys, listCode, listMessage = listCacheKeys()
  if not keys then
    return {
      state = "error",
      code = listCode or "storage_unavailable",
      message = listMessage or "could not enumerate cache",
      marker = marker,
      context = context,
    }
  end

  for species = 1, count do
    local normal = storageKey(Cache.path(species, "normal"))
    local shiny = storageKey(Cache.path(species, "shiny"))
    if not keys[normal] then
      return {
        state = "incomplete", code = "missing_blob",
        message = "missing " .. normal, marker = marker, context = context,
      }
    end
    if not keys[shiny] then
      return {
        state = "incomplete", code = "missing_blob",
        message = "missing " .. shiny, marker = marker, context = context,
      }
    end
  end
  local substitute = storageKey(Cache.specialPath("substitute"))
  if not keys[substitute] then
    return {
      state = "incomplete", code = "missing_blob",
      message = "missing " .. substitute, marker = marker, context = context,
    }
  end

  return {
    state = "valid",
    code = "ok",
    marker = marker,
    context = context,
  }
end

function Cache.available(count)
  return Cache.inspect(count).state == "valid"
end

function Cache.finish(meta, count)
  local ok, code, message = writeRecord(Cache.MARKER, { marker = {
    format = Cache.FORMAT,
    count = count,
    md5 = meta and meta.md5 or "unknown",
    title = meta and meta.title or "unknown",
    byteOrder = meta and meta.byteOrder or "unknown",
  } })
  if not ok then return false, message or code end
  return true
end

function Cache.writeError(text)
  writeRecord(Cache.ERROR, { text = tostring(text or "unknown error") })
end

function Cache.read(species, variant)
  return readBlob(Cache.path(species, variant))
end

function Cache.readSpecial(name)
  return readBlob(Cache.specialPath(name))
end

return Cache
