package.path = "./?.lua;./?/init.lua;" .. package.path

local checks = 0
local function ok(value, message)
  checks = checks + 1
  if not value then error("FAIL " .. message, 0) end
end

package.loaded["mods.STADIUM2_IMPORTER.lib.importer"] = nil
local Importer = require("mods.STADIUM2_IMPORTER.lib.importer")
local models, battle = true, true
Importer.bind({ options={ get=function(_, key)
  if key == "stadium2_models" then return models end
  if key == "stadium2_battle" then return battle end
end } })
ok(Importer.modelsEnabled(), "Stadium 2 models default/ON state is enabled")
ok(Importer.battleEnabled(), "Stadium 2 carried 3D battle default/ON state is enabled")
models = false
ok(not Importer.modelsEnabled(), "Stadium 2 models OFF disables renderers")
ok(Importer.battleEnabled(), "battle mode remains selected when models are OFF")
local rig, err = Importer.newRenderer(25, "normal")
ok(rig == nil and err == "Stadium 2 models disabled", "renderer creation is blocked while model option is OFF")
models = true
battle = false
ok(Importer.modelsEnabled(), "models can remain ON when the carried 3D battle path is OFF")
ok(not Importer.battleEnabled(), "Stadium 2 battle OFF disables the importer-owned battle presentation")

local main = assert(io.open("mods/STADIUM2_IMPORTER/main.lua", "rb")):read("*a")
ok(main:find('key="stadium2_models"', 1, true) ~= nil, "importer exposes the Stadium 2 models option")
ok(main:find('key="stadium2_battle"', 1, true) ~= nil, "importer exposes the Stadium 2 battle option")
ok(main:find('label="STADIUM 2 BATTLE"', 1, true) ~= nil, "battle option uses the requested Stadium label")
ok(not main:find("lib.battle_stage", 1, true), "stage wiring stays outside the bootstrap")
ok(not main:find("RENDER QUALITY", 1, true) and not main:find("TEXTURE FILTERING", 1, true), "no unrelated Stadium renderer options are exposed")
ok(main:find('render_pipelines:register("stadium2_battle_clock"', 1, true) ~= nil,
  "battle clock uses the real-time presentation update path")
ok(not main:find("Importer.step()\n    Battle.update(dt)", 1, true),
  "speed-scaled input steps do not advance battle models")

print(("%d checks passed (Stadium 2 options)"):format(checks))
