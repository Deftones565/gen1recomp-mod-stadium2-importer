-- Compare an independently dumped Stadium 2 OBJ with one exported by this mod.
-- Usage: luajit tools/compare_arena_reference.lua reference.obj exported.obj

local referencePath, exportedPath = arg[1], arg[2]
assert(referencePath and exportedPath,
  "usage: compare_arena_reference.lua <reference.obj> <exported.obj>")

local function readObj(path, rotateExport)
  local vertices, triangles = {}, {}
  for line in assert(io.lines(path)) do
    local x, y, z = line:match("^v%s+([^%s]+)%s+([^%s]+)%s+([^%s]+)")
    if x then
      x, y, z = tonumber(x), tonumber(y), tonumber(z)
      -- The reference dumps use (Z, Y, -X) relative to Stadium's coordinates.
      if rotateExport then x, y, z = z, y - 1, -x end
      vertices[#vertices + 1] = { x, y, z }
    elseif line:match("^f%s+") then
      local face = {}
      for token in line:gmatch("[^%s]+") do
        local index = token:match("^(%d+)")
        if index then face[#face + 1] = tonumber(index) end
      end
      for i = 2, #face - 1 do
        triangles[#triangles + 1] = { face[1], face[i], face[i + 1] }
      end
    end
  end
  return vertices, triangles
end

local function vertexKey(vertex)
  return ("%.2f,%.2f,%.2f"):format(vertex[1], vertex[2], vertex[3])
end

local function triangleKey(vertices, triangle)
  local points = {
    vertexKey(vertices[triangle[1]]),
    vertexKey(vertices[triangle[2]]),
    vertexKey(vertices[triangle[3]]),
  }
  table.sort(points)
  return table.concat(points, "|")
end

local function windingKey(vertices, triangle)
  local points = {
    vertexKey(vertices[triangle[1]]),
    vertexKey(vertices[triangle[2]]),
    vertexKey(vertices[triangle[3]]),
  }
  local first = 1
  if points[2] < points[first] then first = 2 end
  if points[3] < points[first] then first = 3 end
  return points[first] .. "|" .. points[first % 3 + 1] .. "|"
    .. points[(first + 1) % 3 + 1]
end

local referenceVertices, referenceTriangles = readObj(referencePath, false)
local exportedVertices, exportedTriangles = readObj(exportedPath, true)
local reference = {}
for _, triangle in ipairs(referenceTriangles) do
  local key = triangleKey(referenceVertices, triangle)
  reference[key] = reference[key] or {}
  reference[key][windingKey(referenceVertices, triangle)] =
    (reference[key][windingKey(referenceVertices, triangle)] or 0) + 1
end

local matched, reversed, absent = 0, 0, 0
for _, triangle in ipairs(exportedTriangles) do
  local key = triangleKey(exportedVertices, triangle)
  local candidates = reference[key]
  local winding = windingKey(exportedVertices, triangle)
  if not candidates then
    absent = absent + 1
  elseif (candidates[winding] or 0) > 0 then
    candidates[winding] = candidates[winding] - 1
    matched = matched + 1
  else
    reversed = reversed + 1
  end
end

local missing = 0
for _, candidates in pairs(reference) do
  for _, count in pairs(candidates) do missing = missing + count end
end

print(("reference=%d exported=%d matched=%d reversed=%d absent=%d missing=%d")
  :format(#referenceTriangles, #exportedTriangles, matched, reversed, absent, missing))
