local TagFile = {}

TagFile.FORMAT = "S2ANIMTAG1"

local function cleanTag(value)
  value = tostring(value or ""):gsub("[%z\1-\31\127]", " ")
  return value:match("^%s*(.-)%s*$") or ""
end

local function validSpecies(value)
  value = tonumber(value)
  return value and value >= 1 and value <= 251 and value == math.floor(value)
end

local function validIndex(value)
  value = tonumber(value)
  return value and value >= 0 and value == math.floor(value)
end

function TagFile.new()
  return { format = TagFile.FORMAT, counts = {}, species = {} }
end

function TagFile.setCount(data, species, count)
  if not validSpecies(species) then return false, "invalid species" end
  count = tonumber(count)
  if not count or count < 0 or count ~= math.floor(count) then
    return false, "invalid animation count"
  end
  data.counts[species] = count
  data.species[species] = data.species[species] or {}
  return true
end

function TagFile.set(data, species, animationIndex, tag)
  if not validSpecies(species) then return false, "invalid species" end
  if not validIndex(animationIndex) then return false, "invalid animation index" end
  data.species[species] = data.species[species] or {}
  tag = cleanTag(tag)
  data.species[species][animationIndex] = tag ~= "" and tag or nil
  return true
end

function TagFile.get(data, species, animationIndex)
  local rows = data and data.species and data.species[tonumber(species)]
  return rows and rows[tonumber(animationIndex)] or nil
end

function TagFile.encode(data)
  local output = {
    TagFile.FORMAT,
    "# C<TAB>national_dex<TAB>animation_count",
    "# T<TAB>national_dex<TAB>zero_based_animation_index<TAB>semantic_tag",
  }
  for species = 1, 251 do
    local count = data.counts and tonumber(data.counts[species])
    if count and count >= 0 then
      output[#output + 1] = ("C\t%d\t%d"):format(species, math.floor(count))
    end
    local rows = data.species and data.species[species]
    if type(rows) == "table" then
      local indexes = {}
      for index, tag in pairs(rows) do
        if validIndex(index) and cleanTag(tag) ~= "" then indexes[#indexes + 1] = index end
      end
      table.sort(indexes)
      for _, index in ipairs(indexes) do
        output[#output + 1] = ("T\t%d\t%d\t%s")
          :format(species, index, cleanTag(rows[index]))
      end
    end
  end
  return table.concat(output, "\n") .. "\n"
end

function TagFile.decode(bytes)
  if type(bytes) ~= "string" then return nil, "animation tag data is not text" end
  local first = bytes:match("^([^\r\n]+)")
  if first ~= TagFile.FORMAT then return nil, "unsupported animation tag format" end
  local data = TagFile.new()
  local lineNumber = 0
  for line in (bytes .. "\n"):gmatch("([^\r\n]*)[\r\n]+") do
    lineNumber = lineNumber + 1
    if line ~= "" and line:sub(1, 1) ~= "#" and line ~= TagFile.FORMAT then
      local species, count = line:match("^C\t(%d+)\t(%d+)$")
      if species then
        local ok, err = TagFile.setCount(data, tonumber(species), tonumber(count))
        if not ok then return nil, ("line %d: %s"):format(lineNumber, err) end
      else
        local index, tag
        species, index, tag = line:match("^T\t(%d+)\t(%d+)\t(.*)$")
        if not species then return nil, ("line %d: invalid record"):format(lineNumber) end
        local ok, err = TagFile.set(data, tonumber(species), tonumber(index), tag)
        if not ok then return nil, ("line %d: %s"):format(lineNumber, err) end
      end
    end
  end
  return data
end

function TagFile.load(path)
  local file, err = io.open(path, "rb")
  if not file then return nil, err end
  local bytes = file:read("*a")
  file:close()
  return TagFile.decode(bytes)
end

function TagFile.save(path, data)
  local file, err = io.open(path, "wb")
  if not file then return false, err end
  local ok, writeErr = file:write(TagFile.encode(data))
  file:close()
  if not ok then return false, writeErr end
  return true
end

return TagFile
