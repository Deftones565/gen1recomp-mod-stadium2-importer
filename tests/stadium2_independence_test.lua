local checks = 0
local function ok(value, message)
  checks = checks + 1
  if not value then error("FAIL " .. message, 0) end
end

local function read(path)
  local file = assert(io.open(path, "rb"))
  local value = file:read("*a")
  file:close()
  return value
end

local root = "mods/STADIUM2_IMPORTER/"
local manifest = read(root .. "manifest.json")
local main = read(root .. "main.lua")
local router = read(root .. "lib/battle_router.lua")
local gen1 = read(root .. "lib/gen1_battle.lua")
local gold = read(root .. "lib/gen2_battle.lua")

ok(manifest:find('"dependencies": %[%]', 1) ~= nil, "importer has no required mod dependency")
ok(manifest:find('"version": "0.9.21"', 1, true) ~= nil, "retained caught-ball compositor version is 0.9.21")
ok(main:find('require("mods.STADIUM2_IMPORTER.lib.battle_router")', 1, true) ~= nil, "main dispatches battles through the generation router")
ok(router:find('lib.gen2_battle', 1, true) ~= nil, "router selects the owned Gold battle")
ok(router:find('lib.gen1_battle', 1, true) ~= nil, "router selects the disabled Gen 1 battle path")
ok(gen1:find('lib.importer', 1, true) ~= nil, "Gen 1 keeps only importer configuration")
ok(gen1:find('Importer.configure({count=maxDex})', 1, true) ~= nil, "Gen 1 preserves model-count configuration")
ok(gen1:find('return false', 1, true) ~= nil, "Gen 1 battle path is inactive")
ok(gold:find('Importer.configure({count=maxDex,palettePairs=palettePairs})',1,true)~=nil,
  "Gold raises the importer boundary and supplies its normal/shiny palettes")

ok(gold:find('self.hudCleared=function() return false end',1,true)~=nil,
  "Gold 3D HUD capture suppresses native per-move HUD clearing")
ok(gold:find('hudLayerOk,hudLayer=pcall(Hud.hudLayer',1,true)~=nil,
  "Gold 3D status HUD is captured as an independent compositor layer")
ok(gold:find('runner.keepSprites',1,true)~=nil
   and gold:find('self.stadium2ImporterRetainedAnim = runner',1,true)~=nil,
  "0.1.78 anim_keepsprites runner is retained after BattleState clears self.anim")
ok(gold:find('objectRunner=self.anim or self.stadium2ImporterRetainedAnim',1,true)~=nil,
  "caught Pokeball final OAM is included in the detached OBJ compositor")

local hud = read(root .. "lib/battle_hud.lua")
ok(hud:find('local upper=(layout.snap and hudLayer) or layer',1,true)~=nil,
  "snapped status bands always use the persistent HUD-only capture")
ok(not hud:find('screen:hudCleared("enemy")',1,true)
   and not hud:find('screen:hudCleared("player")',1,true),
  "detached status cards ignore BattleAnimClearHud visibility")

local extractSource = read(root .. "lib/extract.lua")
ok(not extractSource:find("archiveNear", 1, true), "extractor uses exact Stadium 2 archive roots")
ok(not extractSource:find("mappedSpecies", 1, true), "extractor uses exact record=dex species indexing")

print(("%d checks passed (Stadium 2 independence)"):format(checks))
