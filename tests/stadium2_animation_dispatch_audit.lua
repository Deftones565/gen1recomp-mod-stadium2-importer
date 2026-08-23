package.path = "./?.lua;./?/init.lua;" .. package.path

local Dispatch = require("mods.STADIUM2_IMPORTER.lib.animation_dispatch")

local path = os.getenv("STADIUM2_ROM") or arg[1]
  or "mods/STADIUM2_IMPORTER/baseroms/stadium2.z64"
local file = assert(io.open(path, "rb"), "Stadium 2 ROM is required: " .. path)
local rom = file:read("*a")
file:close()

local names = assert(Dispatch.moveNames(rom))
local lines = {
  "species\troute_kind\tanimation_index\tauxiliary_index\troute_ids\troute_names",
}
for species = 1, 251 do
  local rows = assert(Dispatch.forSpecies(rom, species))
  local groups, order = {}, {}
  for moveId = 1, Dispatch.MOVE_COUNT do
    local row = rows[moveId - 1]
    local key = row[1] .. ":" .. row[2]
    local group = groups[key]
    if not group then
      group = { animation = row[1], auxiliary = row[2], ids = {}, names = {} }
      groups[key] = group
      order[#order + 1] = group
    end
    group.ids[#group.ids + 1] = moveId
    group.names[#group.names + 1] = names[moveId]
  end
  table.sort(order, function(a, b)
    if a.animation ~= b.animation then return a.animation < b.animation end
    return a.auxiliary < b.auxiliary
  end)
  for _, group in ipairs(order) do
    lines[#lines + 1] = table.concat({
      tostring(species), "moves", tostring(group.animation), tostring(group.auxiliary),
      table.concat(group.ids, ","), table.concat(group.names, ","),
    }, "\t")
  end
  for contextIndex, contextName in ipairs(Dispatch.CONTEXTS) do
    local entry = Dispatch.MOVE_COUNT + contextIndex - 1
    local row = rows[entry]
    lines[#lines + 1] = table.concat({
      tostring(species), "context", tostring(row[1]), tostring(row[2]),
      tostring(entry), contextName,
    }, "\t")
  end
end

local output = table.concat(lines, "\n") .. "\n"
local outputPath = os.getenv("STADIUM2_ANIMATION_DISPATCH_OUT") or arg[2]
if outputPath and outputPath ~= "" then
  local out = assert(io.open(outputPath, "wb"))
  out:write(output)
  out:close()
  print(("wrote %d ROM-authored animation-route groups to %s")
    :format(#lines - 1, outputPath))
else
  io.write(output)
end
