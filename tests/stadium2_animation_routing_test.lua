package.path = "./?.lua;./?/init.lua;" .. package.path

local Routing = require("mods.STADIUM2_IMPORTER.lib.animation_routing")
local anims = { {frames=47}, {frames=141}, {frames=87}, {frames=125}, {frames=47} }
local aux = { {frames=5}, {frames=3}, {frames=3}, {frames=141}, {frames=87}, {frames=125} }
local route = Routing.assign(anims, aux)
assert(route[1] == 0, "default facial stream routes to idle")
assert(route[2] == 3 and route[3] == 4 and route[4] == 5,
  "ordered duration alignment skips auxiliary-only expressions")
assert(route[5] == -1, "unpaired skeletal clip does not steal an expression stream")
print("3 checks passed (Stadium 2 animation routing)")
