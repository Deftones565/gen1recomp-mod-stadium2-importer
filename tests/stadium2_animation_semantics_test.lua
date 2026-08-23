package.path = "./?.lua;./?/init.lua;" .. package.path

local Semantics = require("mods.STADIUM2_IMPORTER.lib.animation_semantics")
local Build = require("mods.STADIUM2_IMPORTER.lib.build")

local function ok(value, message)
  if not value then error(message or "assertion failed", 2) end
end

local animations = {}
for index = 0, 7 do
  animations[index + 1] = { index = index, aux = index }
end

local dispatch = { n = 271 }
for index = 0, 250 do dispatch[index] = { 2, -1 } end
for index = 251, 270 do dispatch[index] = { 0, -1 } end
dispatch[252] = { 5, 1 } -- ROM entrance entry
dispatch[253] = { 6, 2 } -- ROM faint entry
dispatch[254] = { 7, 3 } -- ROM hit entry
dispatch[263] = { 6, 2 }
dispatch[269] = { 7, 3 }

local rows, contexts = assert(Semantics.apply(animations, {}, Build, nil, dispatch))
ok(animations[1].name == "idle", "ROM idle entry names its routed clip")
ok(animations[2].name == "attack_default", "move-routed clip is identified as an attack")
ok(animations[5].name == "entrance", "ROM entrance entry names its routed clip")
ok(animations[6].name == "faint", "ROM faint entry names its routed clip")
ok(animations[7].name == "hit", "ROM damage entry names its routed clip")
ok(contexts[1] == 0, "idle context")
ok(contexts[2] == 4, "entrance comes from normalized ROM entry 252")
ok(contexts[3] == 5, "faint route comes from normalized ROM entry 253")
ok(contexts[4] == 6, "hit route comes from normalized ROM entry 254")
ok(contexts[13] == 5 and contexts[19] == 6,
  "unclassified ROM tail selectors are retained without invented roles")
ok(#rows == 251, "all Stadium 2 move slots are exposed")
ok(rows[1][1] == 1 and rows[251][1] == 1,
  "move routes normalize runtime selectors to exported clips")
ok(rows[1].romSelector == 2, "raw ROM selector remains available for audits")
ok(#animations[2].moveIds == 251, "move-routed clip retains its metadata")

local minimum = { { index = 0 } }
local _, minimumContexts = assert(Semantics.apply(minimum, {}, Build))
ok(minimum[1].name == "animation_0", "missing dispatch does not invent a role")
ok(minimumContexts[2] == 0xFFFF and minimumContexts[3] == 0xFFFF,
  "missing ROM contexts remain unresolved")

print("stadium2 animation semantics tests passed")
