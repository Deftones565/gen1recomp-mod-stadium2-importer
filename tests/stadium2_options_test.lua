package.path = "./?.lua;./?/init.lua;" .. package.path

local checks = 0
local function ok(value, message)
  checks = checks + 1
  if not value then error("FAIL " .. message, 0) end
end

package.loaded["mods.STADIUM2_IMPORTER.lib.importer"] = nil
local Importer = require("mods.STADIUM2_IMPORTER.lib.importer")
local models, battle, battleHud, shader, rapidashCut = true, true, true, "stadium", true
local betaArena, betaTod = false, false
Importer.bind({ options={ get=function(_, key)
  if key == "stadium2_models" then return models end
  if key == "stadium2_battle" then return battle end
  if key == "stadium2_battle_hud" then return battleHud end
  if key == "stadium2_shader" then return shader end
  if key == "stadium2_rapidash_cut_fx" then return rapidashCut end
  if key == "stadium2_beta_arena_test" then return betaArena end
  if key == "stadium2_beta_arena_tod" then return betaTod end
end } })
ok(Importer.modelsEnabled(), "Stadium 2 models default/ON state is enabled")
ok(Importer.battleEnabled(), "Stadium 2 carried 3D battle default/ON state is enabled")
ok(Importer.battleHudEnabled(), "Stadium 2 battle HUD defaults ON")
ok(Importer.shaderStyle() == "stadium", "Stadium lighting is the default model shader")
rapidashCut=false
ok(not Importer.rapidashCutEffectEnabled(), "cut Rapidash particles follow the OFF mod option")
rapidashCut=true
ok(Importer.rapidashCutEffectEnabled(), "cut Rapidash particles default ON")
ok(not Importer.betaArenaEnabled(), "unfinished Stadium fields remain opt-in")
betaArena=true
ok(Importer.betaArenaEnabled(), "beta arena setting reaches the battle adapters")
betaArena=false
ok(not Importer.betaArenaTimeOfDayEnabled(), "beta Park time-of-day remains independently opt-in")
betaTod=true
ok(Importer.betaArenaTimeOfDayEnabled(), "beta Park time-of-day setting reaches arena lighting")
betaTod=false
shader = "cel"
ok(Importer.shaderStyle() == "cel", "cel-shaded model option reaches the renderer configuration")
shader = "invalid"
ok(Importer.shaderStyle() == "stadium", "unknown shader settings safely use Stadium lighting")
shader = "stadium"
models = false
ok(not Importer.modelsEnabled(), "Stadium 2 models OFF disables renderers")
ok(Importer.battleEnabled(), "battle mode remains selected when models are OFF")
local rig, err = Importer.newRenderer(25, "normal")
ok(rig == nil and err == "Stadium 2 models disabled", "renderer creation is blocked while model option is OFF")
models = true
battle = false
ok(Importer.modelsEnabled(), "models can remain ON when the carried 3D battle path is OFF")
ok(not Importer.battleEnabled(), "Stadium 2 battle OFF disables the importer-owned battle presentation")
battleHud = false
ok(not Importer.battleHudEnabled(), "Stadium battle HUD can be disabled independently")
ok(not Importer.battleEnabled(), "HUD selection does not re-enable a disabled battle scene")

local main = assert(io.open("mods/STADIUM2_IMPORTER/main.lua", "rb")):read("*a")
ok(main:find('key="stadium2_models"', 1, true) ~= nil, "importer exposes the Stadium 2 models option")
ok(main:find('key="stadium2_battle"', 1, true) ~= nil, "importer exposes the Stadium 2 battle option")
ok(main:find('key="stadium2_battle_hud"', 1, true) ~= nil
    and main:find('label="STADIUM 2 BATTLE HUD"', 1, true) ~= nil,
  "importer exposes an independent Stadium battle HUD option")
ok(main:find('key="stadium2_shader"', 1, true) ~= nil
    and main:find('{"WATERCOLOR MANGA","cel"}', 1, true) ~= nil,
  "importer exposes Stadium and watercolor-manga model shader choices")
ok(main:find('key="stadium2_rapidash_cut_fx"',1,true)~=nil
    and main:find('label="RAPIDASH CUT PARTICLES"',1,true)~=nil
    and main:find('type="toggle", default=true',1,true)~=nil,
  "importer exposes the opt-in Rapidash cut-particle option")
ok(main:find('key="stadium2_beta_arena_test"',1,true)~=nil
    and main:find('label="BETA CONTEXT ARENAS"',1,true)~=nil
    and main:find('type="toggle", default=false',1,true)~=nil,
  "importer exposes contextual Gen 2 arenas as a default-OFF beta option")
ok(main:find('key="stadium2_beta_arena_tod"',1,true)~=nil
    and main:find('label="BETA PARK TIME OF DAY"',1,true)~=nil,
  "importer exposes Park time-of-day lighting as a separate beta option")
ok(main:find('label="STADIUM 2 BATTLE"', 1, true) ~= nil, "battle option uses the requested Stadium label")
ok(not main:find("lib.battle_stage", 1, true), "stage wiring stays outside the bootstrap")
ok(not main:find("RENDER QUALITY", 1, true) and not main:find("TEXTURE FILTERING", 1, true), "no unrelated Stadium renderer options are exposed")
ok(main:find('render_pipelines:register("stadium2_battle_clock"', 1, true) ~= nil,
  "battle clock uses the real-time presentation update path")
ok(not main:find("Importer.step()\n    Battle.update(dt)", 1, true),
  "speed-scaled input steps do not advance battle models")

print(("%d checks passed (Stadium 2 options)"):format(checks))
