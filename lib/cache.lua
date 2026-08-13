local Cache = {}

Cache.FORMAT = "S2IMP28"
Cache.ROOT = "stadium2_importer"
Cache.NORMAL = Cache.ROOT .. "/normal"
Cache.SHINY = Cache.ROOT .. "/shiny"
Cache.BATTLE = Cache.ROOT .. "/battle"
Cache.MARKER = Cache.ROOT .. "/pack.info"
Cache.ERROR = Cache.ROOT .. "/import_error.log"
Cache.UNOWN_FORMS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"

local function fs()
  return love and love.filesystem
end

local function file(path)
  local f = fs()
  if not (f and f.getInfo) then return false end
  local ok, info = pcall(f.getInfo, path, "file")
  return ok and info and true or false
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
  local f = fs()
  if not (f and f.createDirectory) then return false, "filesystem unavailable" end
  for _, path in ipairs({ Cache.ROOT, Cache.NORMAL, Cache.SHINY, Cache.BATTLE }) do
    local ok, err = pcall(f.createDirectory, path)
    if not ok then return false, tostring(err) end
  end
  return true
end

function Cache.clear(count)
  local f = fs()
  if not f then return false, "filesystem unavailable" end
  count = math.max(251, tonumber(count) or 251)
  for species = 1, count do
    if f.remove then
      pcall(f.remove, Cache.path(species, "normal"))
      pcall(f.remove, Cache.path(species, "shiny"))
    end
  end
  if f.remove then pcall(f.remove, Cache.MARKER) end
  if f.remove then pcall(f.remove,Cache.specialPath("substitute")) end
  if f.remove then
    for i=2,#Cache.UNOWN_FORMS do
      local letter=Cache.UNOWN_FORMS:sub(i,i)
      pcall(f.remove,Cache.unownPath(letter,"normal"))
      pcall(f.remove,Cache.unownPath(letter,"shiny"))
    end
  end
  return Cache.ensureDirectories()
end

function Cache.writeSpecial(name,bytes)
  local f=fs()
  if not (f and f.write) then return false,"filesystem unavailable" end
  local ok,err=Cache.ensureDirectories()
  if not ok then return false,err end
  local wrote,writeErr=pcall(f.write,Cache.specialPath(name),bytes)
  return wrote and true or false,wrote and nil or tostring(writeErr)
end

function Cache.writePair(species, normalBytes, shinyBytes)
  local f = fs()
  if not (f and f.write) then return false, "filesystem unavailable" end
  local ok, err = Cache.ensureDirectories()
  if not ok then return false, err end
  local normalPath = Cache.path(species, "normal")
  local shinyPath = Cache.path(species, "shiny")
  local okNormal, normalErr = pcall(f.write, normalPath, normalBytes)
  if not okNormal then return false, tostring(normalErr) end
  local okShiny, shinyErr = pcall(f.write, shinyPath, shinyBytes)
  if not okShiny then return false, tostring(shinyErr) end
  return true
end

local function parseMarker(text)
  if type(text) ~= "string" then return nil end
  local row = {}
  for line in text:gmatch("[^\r\n]+") do
    local key, value = line:match("^([^=]+)=(.*)$")
    if key then row[key] = value end
  end
  row.count = tonumber(row.count)
  return row
end

function Cache.marker()
  local f = fs()
  if not (f and f.read and file(Cache.MARKER)) then return nil end
  local ok, text = pcall(f.read, Cache.MARKER)
  return ok and parseMarker(text) or nil
end

function Cache.available(count)
  count = tonumber(count) or 151
  local marker = Cache.marker()
  if not marker or marker.format ~= Cache.FORMAT or (marker.count or 0) < count then return false end
  for species = 1, count do
    if not file(Cache.path(species, "normal"))
        or not file(Cache.path(species, "shiny")) then return false end
  end
  if not file(Cache.specialPath("substitute")) then return false end
  for i=2,#Cache.UNOWN_FORMS do
    local letter=Cache.UNOWN_FORMS:sub(i,i)
    if not file(Cache.unownPath(letter,"normal"))
        or not file(Cache.unownPath(letter,"shiny")) then return false end
  end
  return true
end

function Cache.finish(meta, count)
  local f = fs()
  if not (f and f.write) then return false, "filesystem unavailable" end
  local text = table.concat({
    "format=" .. Cache.FORMAT,
    "count=" .. tostring(count),
    "md5=" .. tostring(meta and meta.md5 or "unknown"),
    "title=" .. tostring(meta and meta.title or "unknown"),
    "byte_order=" .. tostring(meta and meta.byteOrder or "unknown"),
  }, "\n") .. "\n"
  local ok, err = pcall(f.write, Cache.MARKER, text)
  return ok and true or false, ok and nil or tostring(err)
end

function Cache.writeError(text)
  local f = fs()
  if f and f.createDirectory then pcall(f.createDirectory, Cache.ROOT) end
  if f and f.write then pcall(f.write, Cache.ERROR, tostring(text or "unknown error") .. "\n") end
end

function Cache.read(species, variant)
  local f = fs()
  local path = Cache.path(species, variant)
  if not (f and f.read and file(path)) then return nil end
  local ok, bytes = pcall(f.read, path)
  return ok and bytes or nil
end

function Cache.readSpecial(name)
  local f=fs()
  local path=Cache.specialPath(name)
  if not (f and f.read and file(path)) then return nil end
  local ok,bytes=pcall(f.read,path)
  return ok and bytes or nil
end

return Cache
