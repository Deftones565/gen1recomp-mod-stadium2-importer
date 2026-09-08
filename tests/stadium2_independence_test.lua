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
local actor = read(root .. "lib/battle_actor.lua")
local scene = read(root .. "lib/battle_scene.lua")
local presentation = read(root .. "lib/battle_presentation.lua")
local uiOwnership = read(root .. "lib/battle_ui_ownership.lua")

ok(manifest:find('"dependencies": %[%]', 1) ~= nil, "importer has no required mod dependency")
ok(manifest:find('"version": "0.12.1"', 1, true) ~= nil,
  "public API release is pinned to 0.12.1")
ok(main:find('require("mods.STADIUM2_IMPORTER.lib.battle_router")', 1, true) ~= nil,
  "main dispatches battles through the generation router")
ok(main:find('lib.battle_presentation',1,true)~=nil and main:find('mod.exports.presentation',1,true)~=nil,
  "generation-neutral battle presentation is exported")
ok(router:find('lib.gen2_battle', 1, true) ~= nil, "router selects the owned Gen 2 adapter")
ok(router:find('lib.gen1_battle', 1, true) ~= nil, "router selects the owned Gen 1 adapter")
ok(gen1:find('src.battle.BattleState',1,true)~=nil,"Gen 1 attaches to the host BattleState presentation")
ok(gen1:find('originals.drawPicsLayer',1,true)~=nil
   and gen1:find('originals.drawHUDs',1,true)~=nil
   and gen1:find('originals.drawAnimLayer',1,true)~=nil,
  "Gen 1 wraps draw-only seams")
ok(main:find('BattleUIOwnership.bind',1,true)~=nil
   and uiOwnership:find('battle.status_hud_visible',1,true)~=nil
   and uiOwnership:find('battle.bottom_ui_visible',1,true)~=nil
   and uiOwnership:find('function Ownership.claimStatus',1,true)~=nil,
  "battle status UI ownership uses the official cooperative engine hook")
ok(not gen1:find('function BattleState:drawHUDs',1,true),
  "Gen 1 no longer suppresses the native status HUD by monkey patch")
ok(not gen1:find('function BattleState:submit',1,true)
   and not gen1:find('function BattleState:update',1,true)
   and not gen1:find('function BattleState:performMove',1,true)
   and not gen1:find('function BattleState:throwBall',1,true),
  "Gen 1 adapter does not replace battle mechanics")
ok(gen1:find('if active(self) then return false end',1,true)~=nil
   and gen1:find('hooks:wrap("render.compose"',1,true)~=nil,
  "Gen 1 retains Stadium's screen-aware glass-panel compositor")
ok(gen1:find('Scene:composeWorld',1,true)~=nil
   and gen1:find('Hud.panel',1,true)~=nil
   and gen1:find('UIOwnership.claimStatus',1,true)~=nil,
  "Stadium glass panels are drawn only after official per-region ownership")
ok(uiOwnership:find('legacyGen3Enabled',1,true)~=nil,
  "the installed pre-hook Gen 3 UI receives a narrow compatibility yield")
ok(gen1:find('g.newQuad(24,16,48,8,160,144)',1,true)~=nil
   and gen1:find('g.newQuad(88,80,48,8,160,144)',1,true)~=nil,
  "temporary party indicators crop out the native Game Boy HUD underline")
ok(gen1:find('withNativePartyRowsSuppressed',1,true)~=nil,
  "captured party indicators are omitted from the later native host pass")
ok(actor:find('Generation%-neutral Stadium model actor')~=nil,
  "model actor is shared between generations")
ok(scene:find('Shared Stadium battle presentation surface',1,true)~=nil,
  "stage/camera/model scene is shared between generations")
ok(presentation:find('never calculates damage',1,true)~=nil,
  "public presentation API explicitly owns rendering only")
ok(gold:find('Importer.configure({count=maxDex,palettePairs=palettePairs})',1,true)~=nil,
  "Gold still supplies its normal/shiny palette pairs")
ok(gold:find('runner.keepSprites',1,true)~=nil
   and gold:find('self.stadium2ImporterRetainedAnim = runner',1,true)~=nil,
  "0.1.78 retained caught-ball compatibility remains present")
ok(gold:find('PIC_SCALE',1,true)~=nil,"Gold ReturnMon capture scaling remains generation-specific")

local hud = read(root .. "lib/battle_hud.lua")
ok(not hud:find('stadium2_hud_panels',1,true),
  "owned Stadium HUD regions always retain their authored glass backplates")
ok(hud:find('local upper=statusOwned and ((layout.snap and hudLayer) or layer) or layer',
    1,true)~=nil,
  "claimed status bands use Stadium capture while yielded bands stay native")
ok(not hud:find('screen:hudCleared("enemy")',1,true)
   and not hud:find('screen:hudCleared("player")',1,true),
  "detached status cards ignore native temporary HUD clears")

local extractSource = read(root .. "lib/extract.lua")
ok(not extractSource:find("archiveNear", 1, true), "extractor uses exact Stadium 2 archive roots")
ok(not extractSource:find("mappedSpecies", 1, true), "extractor uses exact record=dex species indexing")


print(("%d checks passed (Stadium 2 independence)"):format(checks))
