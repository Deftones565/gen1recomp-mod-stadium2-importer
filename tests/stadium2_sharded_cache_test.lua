package.path = "./?.lua;./?/init.lua;" .. package.path

local prefix = "mods.STADIUM2_IMPORTER.lib.cache"
package.loaded[prefix] = nil
local Cache = require(prefix)

local checks = 0
local function ok(value, message)
  checks = checks + 1
  if not value then error("FAIL " .. message, 0) end
end

local records = {}
local storage = {
  context = function() return {} end,
  write = function(_, _, key, value) records[key] = value return true end,
  read = function(_, _, key)
    local value = records[key]
    if type(value) == "table" then return value end
    return nil, value == nil and "not_found" or "type_mismatch"
  end,
  writeBytes = function(_, _, key, value) records[key] = value return true end,
  readBytes = function(_, _, key)
    local value = records[key]
    if type(value) == "string" then return value end
    return nil, value == nil and "not_found" or "type_mismatch"
  end,
  list = function(_, _, prefixValue)
    local out = {}
    for key in pairs(records) do
      if key:sub(1, #prefixValue) == prefixValue then out[#out + 1] = key end
    end
    table.sort(out)
    return out
  end,
  delete = function(_, _, key) records[key] = nil return true end,
}
local mod = { game = {}, storage = storage }
Cache.bind(mod)

ok(Cache.beginBuild(151), "sharded cache begins a complete Gen 1 build")
for species = 1, 151 do
  local normal = "DSM4normal-" .. species
  local shiny = "DSM4shiny-" .. species
  ok(Cache.writePair(species, normal, shiny), "stages species pair " .. species)
end
ok(records["cache/battle/shard_001"] ~= nil
    and records["cache/battle/shard_019"] ~= nil,
  "species pairs persist as nineteen eight-species shards")
ok(records["cache/normal/001"] == nil and records["cache/shiny/001"] == nil,
  "sharded build does not create per-model transactions")

ok(Cache.writeSpecial("substitute", "DSM4substitute"), "stages Substitute")
for byte = string.byte("B"), string.byte("Z") do
  local letter = string.char(byte):lower()
  ok(Cache.writeSpecial("unown_" .. letter, "DSM4normal-unown-" .. letter),
    "stages normal Unown " .. letter)
  ok(Cache.writeSpecial("unown_" .. letter .. "_shiny", "DSM4shiny-unown-" .. letter),
    "stages shiny Unown " .. letter)
end
ok(Cache.finish({ md5 = "test", title = "test", byteOrder = "z64" }, 151),
  "sharded cache commits specials and completion marker")

local recordCount = 0
for _ in pairs(records) do recordCount = recordCount + 1 end
ok(recordCount == 21, "151-model cache uses 21 records instead of 354")
ok(records["cache/battle/specials"]:sub(1, 4) == "S2B1",
  "special models share one deterministic shard")

package.loaded[prefix] = nil
local Fresh = require(prefix).bind(mod)
ok(Fresh.inspect(151).state == "valid", "fresh process recognizes sharded cache")
ok(Fresh.read(1, "normal") == "DSM4normal-1", "fresh process reads first normal model")
ok(Fresh.read(8, "shiny") == "DSM4shiny-8", "fresh process reads shard boundary")
ok(Fresh.read(151, "normal") == "DSM4normal-151", "fresh process reads final partial shard")
ok(Fresh.readSpecial("substitute") == "DSM4substitute", "fresh process reads Substitute")
ok(Fresh.readSpecial("unown_z_shiny") == "DSM4shiny-unown-z",
  "fresh process reads shiny Unown Z")

print(("%d checks passed (Stadium 2 sharded cache)"):format(checks))
