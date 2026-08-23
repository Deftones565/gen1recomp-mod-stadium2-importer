-- Dump all Pokemon Stadium 2 battle-field models from the supported US ROM.
--
-- Run from the gen1recomp root:
--   luajit mods/STADIUM2_IMPORTER/tools/dump_stadium2_arenas.lua \
--     mods/STADIUM2_IMPORTER/baseroms/stadium2.z64 \
--     mods/STADIUM2_IMPORTER/stadium2_arena_dump

local Rom = require("mods.STADIUM2_IMPORTER.lib.rom")
local Fragment = require("mods.STADIUM2_IMPORTER.lib.fragment")
local Build = require("mods.STADIUM2_IMPORTER.lib.build")

local ARCHIVE_OFFSET = Rom.STADIUM_MODEL_TABLE_START
local EXPECTED_COUNT = Rom.STADIUM_MODEL_TABLE_RECORDS

local romPath = (arg and arg[1]) or os.getenv("STADIUM2_ROM")
local outputRoot = (arg and arg[2]) or os.getenv("STADIUM2_ARENA_DUMP")
  or "mods/STADIUM2_IMPORTER/stadium2_arena_dump"
assert(romPath, "usage: dump_stadium2_arenas.lua <stadium2.z64> [output-directory]")

local function readFile(path)
  local file = assert(io.open(path, "rb"))
  local bytes = assert(file:read("*a"))
  file:close()
  return bytes
end

local function writeFile(path, bytes)
  local file = assert(io.open(path, "wb"))
  assert(file:write(bytes))
  file:close()
end

local function shellQuote(value)
  return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function mkdir(path)
  assert(os.execute("mkdir -p " .. shellQuote(path)) == 0,
    "could not create " .. tostring(path))
end

local function p16le(value)
  value = math.floor(tonumber(value) or 0) % 0x10000
  return string.char(value % 256, math.floor(value / 256) % 256)
end

local function writeTga(path, texture)
  local w, h, rgba = tonumber(texture.w), tonumber(texture.h), texture.rgba
  assert(w and h and type(rgba) == "string" and #rgba >= w * h * 4,
    "invalid decoded texture")
  local chunks = {
    string.char(0, 0, 2) .. string.rep("\0", 9) .. p16le(w) .. p16le(h)
      .. string.char(32, 0x28), -- 32-bit BGRA, top-left origin
  }
  local out = {}
  for i = 1, w * h do
    local at = (i - 1) * 4 + 1
    local r, g, b, a = rgba:byte(at, at + 3)
    out[#out + 1] = string.char(b, g, r, a)
    if #out == 1024 then chunks[#chunks + 1] = table.concat(out); out = {} end
  end
  if #out > 0 then chunks[#chunks + 1] = table.concat(out) end
  writeFile(path, table.concat(chunks))
end

local function jsonString(value)
  return '"' .. tostring(value):gsub('[%z\1-\31\\"]', function(char)
    local escapes = { ['"']='\\"', ['\\']='\\\\', ['\b']='\\b',
      ['\f']='\\f', ['\n']='\\n', ['\r']='\\r', ['\t']='\\t' }
    return escapes[char] or ("\\u%04x"):format(char:byte())
  end) .. '"'
end

local function transformPoint(matrix, x, y, z)
  if not matrix then return x, y, z end
  return matrix[1][1] * x + matrix[1][2] * y + matrix[1][3] * z + matrix[1][4],
    matrix[2][1] * x + matrix[2][2] * y + matrix[2][3] * z + matrix[2][4],
    matrix[3][1] * x + matrix[3][2] * y + matrix[3][3] * z + matrix[3][4]
end

local function transformNormal(matrix, x, y, z)
  if matrix then
    x, y, z = matrix[1][1] * x + matrix[1][2] * y + matrix[1][3] * z,
      matrix[2][1] * x + matrix[2][2] * y + matrix[2][3] * z,
      matrix[3][1] * x + matrix[3][2] * y + matrix[3][3] * z
  end
  local length = math.sqrt(x * x + y * y + z * z)
  if length > 0 then return x / length, y / length, z / length end
  return 0, 1, 0
end

local function exportObj(directory, stem, model)
  local obj, mtl = {}, {}
  local drawMatrices, pivotMatrices = Build.bindMatrices(model.bones or {})
  local root = model.rootScale or { 1, 1, 1 }
  local sx, sy, sz = root[1] or 1, root[2] or root[1] or 1,
    root[3] or root[1] or 1
  local vertexBase, vertices, triangles = 0, 0, 0
  local lo = { math.huge, math.huge, math.huge }
  local hi = { -math.huge, -math.huge, -math.huge }

  obj[#obj + 1] = "# Pokemon Stadium 2 battle-field model"
  obj[#obj + 1] = "# Geometry and textures decoded directly from the supplied ROM"
  obj[#obj + 1] = "mtllib " .. stem .. ".mtl"
  obj[#obj + 1] = "o " .. stem

  for primitiveIndex, primitive in ipairs(model.prims or {}) do
    local material = ("material_%03d"):format(primitiveIndex)
    local texture = tonumber(primitive.tex) or -1
    local color = primitive.nodeColor or { 255, 255, 255, 255 }
    mtl[#mtl + 1] = "newmtl " .. material
    mtl[#mtl + 1] = ("Kd %.6f %.6f %.6f"):format(
      (color[1] or 255) / 255, (color[2] or 255) / 255,
      (color[3] or 255) / 255)
    mtl[#mtl + 1] = "Ka 0 0 0"
    mtl[#mtl + 1] = "Ks 0 0 0"
    mtl[#mtl + 1] = "illum 1"
    if texture >= 0 and model.textures[texture + 1] then
      mtl[#mtl + 1] = ("map_Kd textures/texture_%03d.tga"):format(texture)
      mtl[#mtl + 1] = ("map_d textures/texture_%03d.tga"):format(texture)
    end
    mtl[#mtl + 1] = ""

    obj[#obj + 1] = ("g primitive_%03d"):format(primitiveIndex)
    obj[#obj + 1] = "usemtl " .. material
    for i = 1, primitive.nverts or 0 do
      local at3, at2, at4 = i * 3, i * 2, i * 4
      local bone = tonumber(primitive.skin and primitive.skin[i]) or -1
      local draw = bone >= 0 and drawMatrices[bone + 1] or nil
      local pivot = bone >= 0 and pivotMatrices[bone + 1] or nil
      local x, y, z = transformPoint(draw, primitive.pos[at3 - 2],
        primitive.pos[at3 - 1], primitive.pos[at3])
      x, y, z = x * sx, y * sy, z * sz
      lo[1], lo[2], lo[3] = math.min(lo[1], x), math.min(lo[2], y), math.min(lo[3], z)
      hi[1], hi[2], hi[3] = math.max(hi[1], x), math.max(hi[2], y), math.max(hi[3], z)
      local rgba = primitive.color or {}
      obj[#obj + 1] = ("v %.9g %.9g %.9g %.6f %.6f %.6f"):format(
        x, y, z, (rgba[at4 - 3] or 255) / 255,
        (rgba[at4 - 2] or 255) / 255, (rgba[at4 - 1] or 255) / 255)
      local u = primitive.uv and primitive.uv[at2 - 1] or 0
      local v = primitive.uv and primitive.uv[at2] or 0
      obj[#obj + 1] = ("vt %.9g %.9g"):format(u, 1 - v)
      local nx, ny, nz = transformNormal(pivot,
        primitive.nrm and primitive.nrm[at3 - 2] or 0,
        primitive.nrm and primitive.nrm[at3 - 1] or 1,
        primitive.nrm and primitive.nrm[at3] or 0)
      obj[#obj + 1] = ("vn %.9g %.9g %.9g"):format(nx, ny, nz)
    end
    for i = 1, primitive.nidx or 0, 3 do
      -- Extracted primitive indices are zero-based N64 vertex slots; OBJ is
      -- one-based.
      local a = vertexBase + primitive.idx[i] + 1
      local b = vertexBase + primitive.idx[i + 1] + 1
      local c = vertexBase + primitive.idx[i + 2] + 1
      obj[#obj + 1] = ("f %d/%d/%d %d/%d/%d %d/%d/%d"):format(
        a,a,a, b,b,b, c,c,c)
      triangles = triangles + 1
    end
    vertexBase = vertexBase + (primitive.nverts or 0)
    vertices = vertexBase
  end

  writeFile(directory .. "/" .. stem .. ".obj", table.concat(obj, "\n") .. "\n")
  writeFile(directory .. "/" .. stem .. ".mtl", table.concat(mtl, "\n") .. "\n")
  if vertices == 0 then lo, hi = {0,0,0}, {0,0,0} end
  return vertices, triangles, lo, hi
end

local raw = readFile(romPath)
local rom, order = assert(Rom.normalise(raw))
assert(#rom == Rom.SIZE, ("wrong Stadium 2 ROM size: 0x%X"):format(#rom))
assert(Rom.title(rom):upper() == Rom.US_TITLE, "ROM is not Pokemon Stadium 2 (US)")
local archive = assert(Rom.archiveAt(rom, ARCHIVE_OFFSET),
  ("missing Stadium model archive at 0x%X"):format(ARCHIVE_OFFSET))
assert(archive.count == EXPECTED_COUNT,
  ("unexpected Stadium model count: %d"):format(archive.count))

mkdir(outputRoot)
local manifest, json = {}, {}
manifest[#manifest + 1] = "index\trom_offset\tpacked_bytes\tdecoded_bytes\troot_offset\tbones\tprimitives\tvertices\ttriangles\ttextures\tbounds_min\tbounds_max\tdirectory"

for _, record in ipairs(archive.records) do
  local stem = ("arena_%02d"):format(record.index)
  local directory = outputRoot .. "/" .. stem
  mkdir(directory)
  mkdir(directory .. "/textures")
  local packed = assert(Rom.recordBytes(rom, record))
  local decoded = assert(Rom.decompress(packed))
  local root = assert(Fragment.stageRoot(decoded, stem))
  local model = assert(Fragment.extractStage(decoded, stem, record.index))

  -- Keep both representations for future format research. The PERS-SZP file
  -- is the exact archive record; the fragment is the decompressed stage file.
  writeFile(directory .. "/" .. stem .. ".pers-szp", packed)
  writeFile(directory .. "/" .. stem .. ".fragment", decoded)
  for textureIndex, texture in ipairs(model.textures or {}) do
    writeTga(("%s/textures/texture_%03d.tga"):format(directory, textureIndex - 1), texture)
  end
  local vertices, triangles, lo, hi = exportObj(directory, stem, model)
  local minText = ("%.6g,%.6g,%.6g"):format(lo[1], lo[2], lo[3])
  local maxText = ("%.6g,%.6g,%.6g"):format(hi[1], hi[2], hi[3])
  manifest[#manifest + 1] = table.concat({
    record.index, ("0x%X"):format(record.start), ("0x%X"):format(record.size),
    ("0x%X"):format(#decoded), ("0x%X"):format(root), #(model.bones or {}),
    #(model.prims or {}), vertices, triangles, #(model.textures or {}),
    minText, maxText, stem,
  }, "\t")
  json[#json + 1] = ("  {\"index\":%d,\"romOffset\":%s,\"packedBytes\":%d,\"decodedBytes\":%d,\"rootOffset\":%d,\"bones\":%d,\"primitives\":%d,\"vertices\":%d,\"triangles\":%d,\"textures\":%d,\"boundsMin\":[%.9g,%.9g,%.9g],\"boundsMax\":[%.9g,%.9g,%.9g],\"directory\":%s}"):format(
    record.index, jsonString(("0x%X"):format(record.start)), record.size,
    #decoded, root, #(model.bones or {}), #(model.prims or {}), vertices,
    triangles, #(model.textures or {}), lo[1], lo[2], lo[3], hi[1], hi[2],
    hi[3], jsonString(stem))
  print(("dumped %s: %d vertices, %d triangles, %d textures"):format(
    stem, vertices, triangles, #(model.textures or {})))
end

writeFile(outputRoot .. "/manifest.tsv", table.concat(manifest, "\n") .. "\n")
writeFile(outputRoot .. "/manifest.json", "{\n  \"source\": \"Pokemon Stadium 2 (US) ROM archive 0x01638000\",\n  \"byteOrder\": "
  .. jsonString(order) .. ",\n  \"arenas\": [\n" .. table.concat(json, ",\n") .. "\n  ]\n}\n")
writeFile(outputRoot .. "/README.txt", [[
Pokemon Stadium 2 battle-field model dump

Source: the 30-record Stadium model archive at ROM offset 0x01638000.
Each arena directory contains an OBJ/MTL, decoded TGA textures, the exact
PERS-SZP archive record, and its decompressed FRAGMENT module. Arena numbers
are the game's zero-based archive indices; no unverified names are invented.

OBJ geometry has the ROM graph's static transforms and root scale baked into
its vertices. Vertex RGB is included using the common OBJ vertex-colour
extension. TGA alpha is referenced by both map_Kd and map_d.
]])

print(("completed: %d Stadium battle fields -> %s"):format(
  archive.count, outputRoot))
