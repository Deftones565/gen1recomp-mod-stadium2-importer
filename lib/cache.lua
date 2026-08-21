-- Sandboxed, playthrough-scoped Stadium model cache.
-- Metadata is stored as data-only records. Independently compressed DSM packs
-- are grouped into small opaque shards so the engine's transactional storage
-- does not rewrite and verify hundreds of separate records during import.
local Cache = {}

Cache.FORMAT = "S2IMP39"
Cache.ROOT = "stadium2_importer"
Cache.NORMAL = Cache.ROOT .. "/normal"
Cache.SHINY = Cache.ROOT .. "/shiny"
Cache.BATTLE = Cache.ROOT .. "/battle"
Cache.MARKER = Cache.ROOT .. "/pack.info"
Cache.ERROR = Cache.ROOT .. "/import_error.log"
Cache.UNOWN_FORMS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
Cache.SHARD_SIZE = 8

local modRef
local buildState

local COMPRESSED_MAGIC = "S2Z1"
local SHARD_MAGIC = "S2B1"
local SHARD_CACHE_LIMIT = 4
local shardCache, shardOrder = {}, {}

local function u16le(v)
  return string.char(v % 256, math.floor(v / 256) % 256)
end

local function u32le(v)
  return string.char(v % 256, math.floor(v / 256) % 256,
    math.floor(v / 65536) % 256, math.floor(v / 16777216) % 256)
end

local function readU32le(s, p)
  local a, b, c, d = s:byte(p, p + 3)
  if not d then return nil end
  return a + b * 256 + c * 65536 + d * 16777216
end

local function readU16le(s, p)
  local a, b = s:byte(p, p + 1)
  if not b then return nil end
  return a + b * 256
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

local function shardPath(index)
  return ("%s/shard_%03d.dsm"):format(Cache.BATTLE, index)
end

local function specialShardPath()
  return Cache.BATTLE .. "/specials.dsm"
end

local function packShard(entries)
  local keys = {}
  for key in pairs(entries) do keys[#keys + 1] = key end
  table.sort(keys)
  local out = { SHARD_MAGIC, u16le(#keys) }
  for _, key in ipairs(keys) do
    local bytes = entries[key]
    if #key > 65535 then return nil, "cache shard key is too long" end
    out[#out + 1] = u16le(#key)
    out[#out + 1] = u32le(#bytes)
    out[#out + 1] = key
    out[#out + 1] = bytes
  end
  return table.concat(out)
end

local function unpackShard(bytes)
  if type(bytes) ~= "string" or bytes:sub(1, 4) ~= SHARD_MAGIC then
    return nil, "cache shard header is invalid"
  end
  local count = readU16le(bytes, 5)
  if not count then return nil, "cache shard entry count is missing" end
  local entries, cursor = {}, 7
  for _ = 1, count do
    local keyLength = readU16le(bytes, cursor)
    local byteLength = readU32le(bytes, cursor + 2)
    if not keyLength or not byteLength then return nil, "cache shard index is truncated" end
    cursor = cursor + 6
    local key = bytes:sub(cursor, cursor + keyLength - 1)
    cursor = cursor + keyLength
    local last = cursor + byteLength - 1
    if #key ~= keyLength or last > #bytes then return nil, "cache shard payload is truncated" end
    entries[key] = bytes:sub(cursor, last)
    cursor = last + 1
  end
  if cursor ~= #bytes + 1 then return nil, "cache shard has trailing data" end
  return entries
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

local function readStoredBlob(path)
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

local function touchShard(path, entries)
  for i = #shardOrder, 1, -1 do
    if shardOrder[i] == path then table.remove(shardOrder, i) end
  end
  shardCache[path] = entries
  shardOrder[#shardOrder + 1] = path
  while #shardOrder > SHARD_CACHE_LIMIT do
    shardCache[table.remove(shardOrder, 1)] = nil
  end
end

local function readShard(path)
  local entries = shardCache[path]
  if entries then
    touchShard(path, entries)
    return entries
  end
  local bytes, code, message = readStoredBlob(path)
  if not bytes then return nil, code, message end
  entries, message = unpackShard(bytes)
  if not entries then return nil, "invalid_record", message end
  touchShard(path, entries)
  return entries
end

local function logicalShard(path)
  local text = tostring(path)
  local species = tonumber(text:match("/normal/(%d+)%.dsm$")
    or text:match("/shiny/(%d+)%.dsm$"))
  if species then
    return shardPath(math.floor((species - 1) / Cache.SHARD_SIZE) + 1)
  end
  if tostring(path):find("/battle/", 1, true) then return specialShardPath() end
  return nil
end

local function readBlob(path)
  if buildState then
    local container = logicalShard(path)
    local staged
    if container == specialShardPath() then
      staged = buildState.specials[path]
    else
      local species = tonumber(tostring(path):match("/(%d+)%.dsm$"))
      local index = species and math.floor((species - 1) / Cache.SHARD_SIZE) + 1
      staged = index and buildState.shards[index] and buildState.shards[index][path]
    end
    if staged then
      local decoded, decodeErr = decodeBlob(staged)
      if not decoded then return nil, "invalid_record", decodeErr end
      return decoded
    end
  end
  local container = logicalShard(path)
  if not container then return nil, "not_found", "cache path has no shard" end
  local entries, code, message = readShard(container)
  if not entries then return nil, code, message end
  local bytes = entries[path]
  if not bytes then return nil, "not_found", "cache shard entry is unavailable" end
  local decoded, decodeErr = decodeBlob(bytes)
  if not decoded then return nil, "invalid_record", decodeErr end
  return decoded
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
  buildState = nil
  shardCache, shardOrder = {}, {}
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
    -- Portable persistence deliberately exposes read/write/delete without
    -- directory enumeration. Fall through to the deterministic key list in
    -- that case; other storage errors must still abort the rebuild.
    if listCode and listCode ~= "not_found" and listCode ~= "storage_unavailable" then
      return false, listMessage or listCode
    end
  end

  count = math.max(251, tonumber(count) or 251)
  local function removeKnown(path)
    local ok, code, message = deleteRecord(path)
    if ok then return true end
    return false, message or code
  end
  -- Portable validation uses this last-written marker as its completeness
  -- contract, so invalidate it before removing any payload. A terminated
  -- rebuild can then only look missing, never valid-but-partially-deleted.
  local ok, err = removeKnown(Cache.MARKER)
  if not ok then return false, err end
  for index = 1, math.ceil(count / Cache.SHARD_SIZE) do
    ok, err = removeKnown(shardPath(index))
    if not ok then return false, err end
  end
  ok, err = removeKnown(specialShardPath())
  if not ok then return false, err end
  for species = 1, count do
    ok, err = removeKnown(Cache.path(species, "normal"))
    if not ok then return false, err end
    ok, err = removeKnown(Cache.path(species, "shiny"))
    if not ok then return false, err end
  end
  ok, err = removeKnown(Cache.ERROR)
  if not ok then return false, err end
  ok, err = removeKnown(Cache.specialPath("substitute"))
  if not ok then return false, err end
  for i = 2, #Cache.UNOWN_FORMS do
    local letter = Cache.UNOWN_FORMS:sub(i, i)
    ok, err = removeKnown(Cache.unownPath(letter, "normal"))
    if not ok then return false, err end
    ok, err = removeKnown(Cache.unownPath(letter, "shiny"))
    if not ok then return false, err end
  end
  return true
end

local function entryCount(entries)
  local count = 0
  for _ in pairs(entries) do count = count + 1 end
  return count
end

local function persistShard(path, entries)
  local bytes, packErr = packShard(entries)
  if not bytes then return false, packErr end
  local ok, code, message = writeBlob(path, bytes)
  if not ok then return false, message or code end
  touchShard(path, entries)
  return true
end

local function flushSpeciesShard(index)
  local entries = buildState and buildState.shards[index]
  if not entries then return true end
  local ok, err = persistShard(shardPath(index), entries)
  if not ok then return false, err end
  buildState.shards[index] = nil
  return true
end

function Cache.beginBuild(count)
  count = math.max(1, math.floor(tonumber(count) or 251))
  buildState = { count = count, pairs = 0, seenPairs = {}, shards = {}, specials = {} }
  shardCache, shardOrder = {}, {}
  return true
end

function Cache.writeSpecial(name, bytes)
  if not buildState then Cache.beginBuild(251) end
  local path = Cache.specialPath(name)
  buildState.specials[path] = encodeBlob(bytes)
  return true
end

function Cache.writePair(species, normalBytes, shinyBytes)
  if not buildState then Cache.beginBuild(251) end
  species = math.floor(tonumber(species) or 0)
  if species < 1 or species > buildState.count then
    return false, "cache species is outside the active build"
  end
  local index = math.floor((species - 1) / Cache.SHARD_SIZE) + 1
  local entries = buildState.shards[index]
  if not entries then entries = {}; buildState.shards[index] = entries end
  entries[Cache.path(species, "normal")] = encodeBlob(normalBytes)
  entries[Cache.path(species, "shiny")] = encodeBlob(shinyBytes)
  if not buildState.seenPairs[species] then
    buildState.seenPairs[species] = true
    buildState.pairs = buildState.pairs + 1
  end

  local first = (index - 1) * Cache.SHARD_SIZE + 1
  local expected = (math.min(buildState.count, first + Cache.SHARD_SIZE - 1) - first + 1) * 2
  if entryCount(entries) == expected then return flushSpeciesShard(index) end
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
    -- A completion marker is committed only after every shard. Portable mode
    -- cannot enumerate its io-backed directory, so the marker is the durable
    -- completeness contract there. Individual reads still validate shard and
    -- DSM envelopes when a model is requested.
    if listCode == "storage_unavailable" then
      return {
        state = "valid",
        code = "ok",
        marker = marker,
        context = context,
      }
    end
    return {
      state = "error",
      code = listCode or "storage_unavailable",
      message = listMessage or "could not enumerate cache",
      marker = marker,
      context = context,
    }
  end

  local shardCount = math.ceil(count / Cache.SHARD_SIZE)
  for index = 1, shardCount do
    local key = storageKey(shardPath(index))
    if not keys[key] then
      return {
        state = "incomplete", code = "missing_blob",
        message = "missing " .. key, marker = marker, context = context,
      }
    end
  end
  local specials = storageKey(specialShardPath())
  if not keys[specials] then
    return {
      state = "incomplete", code = "missing_blob",
      message = "missing " .. specials, marker = marker, context = context,
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
  if not buildState then return false, "cache build has not begun" end
  count = math.max(1, math.floor(tonumber(count) or buildState.count))
  if buildState.pairs ~= count then
    return false, ("cache staged %d/%d species pairs"):format(buildState.pairs, count)
  end
  for index = 1, math.ceil(count / Cache.SHARD_SIZE) do
    local ok, err = flushSpeciesShard(index)
    if not ok then return false, err end
  end
  local specialsOk, specialsErr = persistShard(specialShardPath(), buildState.specials)
  if not specialsOk then return false, specialsErr end
  local ok, code, message = writeRecord(Cache.MARKER, { marker = {
    format = Cache.FORMAT,
    count = count,
    md5 = meta and meta.md5 or "unknown",
    title = meta and meta.title or "unknown",
    byteOrder = meta and meta.byteOrder or "unknown",
  } })
  if not ok then return false, message or code end
  buildState = nil
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
