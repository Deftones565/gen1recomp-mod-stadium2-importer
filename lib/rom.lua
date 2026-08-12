local Layout = require("mods.STADIUM2_IMPORTER.lib.layout")

local Rom = {}

Rom.US_MD5 = Layout.US_MD5
Rom.US_TITLE = Layout.US_TITLE
Rom.SIZE = Layout.ROM_SIZE
Rom.ASSET_START = Layout.ASSET_START
Rom.MODEL_TABLE_START = Layout.MODEL_TABLE_START
Rom.MODEL_TABLE_END = Layout.MODEL_TABLE_END
Rom.POSE_TABLE_START = Layout.POSE_TABLE_START
Rom.POSE_TABLE_END = Layout.POSE_TABLE_END
Rom.POST_POSE_TABLE_START = Layout.POST_POSE_TABLE_START
Rom.POST_POSE_TABLE_END = Layout.POST_POSE_TABLE_END
Rom.SPECIES_META_START = Layout.SPECIES_META_START

local byte = string.byte
local char = string.char
local concat = table.concat
local floor = math.floor
local unpack = unpack or table.unpack
local MAGIC_Z64 = "\128\055\018\064"
local MAGIC_V64 = "\055\128\064\018"
local MAGIC_N64 = "\064\018\055\128"
local CHUNK = 4096

local function u32(data, offset)
  local a, b, c, d = byte(data, offset + 1, offset + 4)
  if not d then return nil end
  return ((a * 256 + b) * 256 + c) * 256 + d
end

local function bytesToString(out, n)
  local parts = {}
  local i = 1
  while i <= n do
    local j = math.min(n, i + CHUNK - 1)
    parts[#parts + 1] = char(unpack(out, i, j))
    i = j + 1
  end
  return concat(parts)
end

function Rom.normalise(bytes)
  if type(bytes) ~= "string" or #bytes < 0x1000 then return nil, "ROM is too short" end
  local magic = bytes:sub(1, 4)
  if magic == MAGIC_Z64 then return bytes, "z64" end
  if magic == MAGIC_V64 then return (bytes:gsub("(.)(.)", "%2%1")), "v64" end
  if magic == MAGIC_N64 then
    return (bytes:gsub("(.)(.)(.)(.)", "%4%3%2%1")), "n64"
  end
  return nil, "unrecognized N64 byte order"
end

function Rom.title(data)
  if type(data) ~= "string" or #data < 0x40 then return "" end
  return data:sub(0x21, 0x34):gsub("%z", ""):gsub("%s+$", "")
end

function Rom.md5(data)
  if not (love and love.data and love.data.hash and love.data.encode) then return nil end
  local ok, value = pcall(function()
    local digest = love.data.hash("md5", data)
    if type(digest) == "userdata" and digest.getString then digest = digest:getString() end
    return love.data.encode("string", "hex", digest)
  end)
  return ok and value or nil
end

function Rom.validate(data)
  local normalized, order = Rom.normalise(data)
  if not normalized then return nil, order end
  if #normalized ~= Rom.SIZE then
    return nil, ("wrong Stadium 2 ROM size: 0x%X"):format(#normalized)
  end
  local title = Rom.title(normalized)
  if title:upper() ~= Rom.US_TITLE then
    return nil, ("wrong ROM title: %s"):format(title ~= "" and title or "unknown")
  end
  local hash = Rom.md5(normalized)
  if hash and hash:lower() ~= Rom.US_MD5 then
    return nil, ("unsupported Stadium 2 revision: MD5 %s"):format(hash)
  end
  return normalized, { byteOrder = order, title = title, md5 = hash }
end

function Rom.yay0(src, base)
  base = base or 0
  if src:sub(base + 1, base + 4) ~= "Yay0" then return nil, "not Yay0" end
  local function be32(o)
    local value = u32(src, base + o)
    if value == nil then error("truncated Yay0 header") end
    return value
  end
  local size = be32(4)
  local maskP = base + 0x11
  local linkP = base + be32(8) + 1
  local chunkP = base + be32(12) + 1
  local out = {}
  local pos, mask, bits = 0, 0, 0
  while pos < size do
    if bits == 0 then
      local a, b, c, d = byte(src, maskP, maskP + 3)
      if not d then return nil, "truncated Yay0 mask stream" end
      mask = ((a * 256 + b) * 256 + c) * 256 + d
      maskP = maskP + 4
      bits = 32
    end
    if mask >= 0x80000000 then
      local value = byte(src, chunkP)
      if value == nil then return nil, "truncated Yay0 literal stream" end
      pos = pos + 1
      out[pos] = value
      chunkP = chunkP + 1
    else
      local a, b = byte(src, linkP, linkP + 1)
      if not b then return nil, "truncated Yay0 link stream" end
      linkP = linkP + 2
      local link = a * 256 + b
      local dist = link % 0x1000
      local count = floor(link / 0x1000)
      if count == 0 then
        local value = byte(src, chunkP)
        if value == nil then return nil, "truncated Yay0 count stream" end
        count = value + 0x12
        chunkP = chunkP + 1
      else
        count = count + 2
      end
      local copy = pos - dist
      if copy < 1 then return nil, "invalid Yay0 back-reference" end
      for _ = 1, count do
        pos = pos + 1
        out[pos] = out[copy]
        if out[pos] == nil then return nil, "invalid Yay0 overlap" end
        copy = copy + 1
        if pos >= size then break end
      end
    end
    mask = (mask * 2) % 0x100000000
    bits = bits - 1
  end
  return bytesToString(out, size)
end

function Rom.decompress(blob)
  if type(blob) ~= "string" then return nil, "asset is not bytes" end
  if blob:sub(1, 8) == "PERS-SZP" then
    local header = u32(blob, 8)
    if not header then return nil, "truncated PERS-SZP header" end
    return Rom.yay0(blob, header)
  end
  if blob:sub(1, 4) == "Yay0" then return Rom.yay0(blob, 0) end
  return blob
end

function Rom.archiveAt(data, offset)
  if type(data) ~= "string" or offset < 0 or offset + 0x10 > #data then return nil end
  local tag = u32(data, offset)
  local zero = u32(data, offset + 4)
  local total = u32(data, offset + 8)
  local count = u32(data, offset + 12)
  if tag == nil or zero == nil or total == nil or count == nil then return nil end
  if tag ~= 0 and tag ~= 0xEF then return nil end
  if zero ~= 0 then return nil end
  if count <= 0 or count >= 4096 then return nil end
  local tableEnd = 0x10 + count * 0x10
  if total < tableEnd or total % 0x10 ~= 0 or offset + total > #data then return nil end
  local records = {}
  for i = 0, count - 1 do
    local row = offset + 0x10 + i * 0x10
    local relative = u32(data, row)
    local size = u32(data, row + 4)
    local reserved1 = u32(data, row + 8)
    local reserved2 = u32(data, row + 12)
    if relative == nil or size == nil or reserved1 == nil or reserved2 == nil then return nil end
    if reserved1 ~= 0 or reserved2 ~= 0 then return nil end
    if size == 0 then
      records[i + 1] = { index = i, offset = relative, start = offset + relative, size = 0 }
    else
      if relative < tableEnd or relative % 0x10 ~= 0 or size % 0x10 ~= 0 then return nil end
      if relative + size > total then return nil end
      records[i + 1] = { index = i, offset = relative, start = offset + relative, size = size }
    end
  end
  return { offset = offset, tag = tag, total = total, count = count, records = records }
end

function Rom.scanArchives(data, first, last, limit)
  if type(data) ~= "string" then return {} end
  first = math.max(0, tonumber(first) or 0)
  last = math.min(#data - 0x10, tonumber(last) or (#data - 0x10))
  limit = math.max(1, tonumber(limit) or 4096)
  local out = {}
  local offset = first - first % 0x10
  if offset < first then offset = offset + 0x10 end
  while offset <= last and #out < limit do
    local archive = Rom.archiveAt(data, offset)
    if archive then out[#out + 1] = archive end
    offset = offset + 0x10
  end
  return out
end

function Rom.recordBytes(data, record)
  if not record then return nil end
  local first = record.start + 1
  local last = record.start + record.size
  if first < 1 or last > #data then return nil end
  return data:sub(first, last)
end

Rom.u32 = u32

return Rom
