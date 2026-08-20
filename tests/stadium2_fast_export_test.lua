package.path = "./?.lua;./?/init.lua;" .. package.path

local Build = require("mods.STADIUM2_IMPORTER.lib.build")
local Pack = require("mods.STADIUM2_IMPORTER.lib.pack")

local checks = 0
local function ok(value, message)
  checks = checks + 1
  if not value then error("FAIL " .. message, 0) end
end

local rows = {}
for i = 1, 165 do rows[i] = { 0xFFFF, -1 } end
rows.n = 165
local contexts = {}
for i = 1, #Build.CONTEXTS do contexts[i] = 0xFFFF end

local function fixture()
  return {
    rootScale = { 1, 1, 1 },
    bones = {
      { parent = -1, t = { 0, 0, 0 }, r = { 0, 0, 0 }, s = { 1, 1, 1 } },
    },
    prims = {
      {
        tex = 0, cull = 1, pos = { 0, 0, 0, 10, 0, 0, 0, 10, 0 },
        uv = { 0, 0, 1, 0, 0, 1 }, nrm = { 0, 0, 1, 0, 0, 1, 0, 0, 1 },
        skin = { 0, 0, 0 }, nverts = 3, idx = { 0, 1, 2 }, nidx = 3,
      },
    },
    textures = { { w = 1, h = 1, rgba = "\255\0\0\255" } },
    anims = {}, auxAnims = {}, handlerOps = {}, handlerFragment = "",
  }
end

local old = fixture()
local expectedNormal = Build.pack(old, 25, rows, contexts)
old.textures[1].rgba = "\0\0\255\255"
local expectedShiny = Build.pack(old, 25, rows, contexts)

local fast = fixture()
local normal, shiny = Build.packPair(fast, 25, rows, contexts, function()
  fast.textures[1].rgba = "\0\0\255\255"
  return true
end)
ok(normal == expectedNormal, "fast normal export is byte-identical to DSM4 pack")
ok(shiny == expectedShiny, "fast shiny export is byte-identical to DSM4 pack")
ok(assert(Pack.parse(normal)).textures[1].rgba == "\255\0\0\255",
  "fast normal export remains independently parseable")
ok(assert(Pack.parse(shiny)).textures[1].rgba == "\0\0\255\255",
  "fast shiny export remains independently parseable")

local savedLove = love
local raw
love = { data = {
  compress = function(_, _, bytes)
    raw = bytes
    return "lz4"
  end,
  decompress = function(_, _, packed)
    if packed == "lz4" then return raw end
  end,
} }
package.loaded["mods.STADIUM2_IMPORTER.lib.cache"] = nil
local Cache = require("mods.STADIUM2_IMPORTER.lib.cache")
local records = {}
local mod = { game = {} }
mod.storage = {
  context = function() return {} end,
  writeBytes = function(_, _, key, bytes) records[key] = bytes return true end,
  readBytes = function(_, _, key)
    local value = records[key]
    if value then return value end
    return nil, "not_found"
  end,
}
Cache.bind(mod)
local large = "DSM4" .. string.rep("A", 4096)
ok(Cache.beginBuild(1), "compressed cache begins a one-species build")
ok(Cache.writePair(1, large, large), "compressed cache accepts ordinary DSM4 pair")
ok(records["cache/battle/shard_001"]:sub(1, 4) == "S2B1"
    and records["cache/battle/shard_001"]:find("S2Z1", 1, true),
  "export storage shards independently compressed DSM payloads")
ok(Cache.read(1, "normal") == large and Cache.read(1, "shiny") == large,
  "cache API returns original DSM4 bytes after transparent decompression")
love = savedLove

print(("%d checks passed (Stadium 2 fast export/API parity)"):format(checks))
