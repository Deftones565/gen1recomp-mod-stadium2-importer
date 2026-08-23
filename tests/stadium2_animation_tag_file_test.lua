package.path = "./?.lua;./?/init.lua;" .. package.path

local TagFile = require("mods.STADIUM2_IMPORTER.lib.animation_tag_file")

local function ok(value, message)
  if not value then error(message or "assertion failed", 2) end
end

local data = TagFile.new()
assert(TagFile.setCount(data, 25, 7))
assert(TagFile.setCount(data, 1, 4))
assert(TagFile.set(data, 25, 6, "hit"))
assert(TagFile.set(data, 25, 0, " idle "))
assert(TagFile.set(data, 1, 2, "attack_custom"))

local encoded = TagFile.encode(data)
ok(encoded:match("^S2ANIMTAG1\n"), "format header is explicit")
ok(encoded:find("C\t1\t4", 1, true) < encoded:find("C\t25\t7", 1, true),
  "species records are deterministic")
ok(encoded:find("T\t25\t0\tidle", 1, true) < encoded:find("T\t25\t6\thit", 1, true),
  "animation records are deterministic and zero based")

local decoded = assert(TagFile.decode(encoded))
ok(decoded.counts[1] == 4 and decoded.counts[25] == 7, "animation counts round trip")
ok(TagFile.get(decoded, 25, 0) == "idle", "tags are trimmed and round trip")
ok(TagFile.get(decoded, 25, 6) == "hit", "terminal tags round trip")

assert(TagFile.set(decoded, 25, 6, ""))
ok(TagFile.get(decoded, 25, 6) == nil, "blank tags clear annotations")
local bad, err = TagFile.decode("OTHER\n")
ok(bad == nil and err:match("unsupported"), "unknown formats are rejected")

print("stadium2 animation tag file tests passed")
