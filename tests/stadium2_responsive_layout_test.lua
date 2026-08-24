package.path="./?.lua;./?/init.lua;"..package.path

package.loaded["mods.STADIUM2_IMPORTER.lib.battle_viewport"]=nil
local Viewport=require("mods.STADIUM2_IMPORTER.lib.battle_viewport")

local checks=0
local function ok(value,message)
  checks=checks+1
  if not value then error("FAIL "..message,0) end
end

local landscape=Viewport.resolve(1280,720)
local wide=Viewport.statusPanels(landscape,{ly=72},4,
  {8,0,80,32},{72,56,88,40})
ok(landscape.orientation=="landscape" and wide.scale==4,
  "landscape preserves Stadium's established wide HUD scale")
ok(wide.enemyX==0 and wide.playerX==1280-88*4,
  "landscape keeps the established opposing screen edges")

-- Battle Art does not reflow portrait into a dashboard. The engine-fitted
-- 160x144 frame is centred at 6x on 1080x1920 and each status band uses the
-- next smaller 5x rung.
local portrait=Viewport.resolve(1080,1920)
local panels=Viewport.statusPanels(portrait,{ly=528},6,
  {8,0,80,32},{72,56,88,40})
ok(portrait.orientation=="portrait" and panels.scale==5,
  "portrait status HUD is one engine scale rung below its 160x144 frame")
ok(panels.enemyX==10 and panels.playerX==640,
  "portrait uses Battle Art's two-pixel foe inset and flush-right player card")
ok(panels.enemyY==528 and panels.playerY==864,
  "portrait preserves the native enemy/player vertical relationship")

-- On a density-scaled phone, one framebuffer rung becomes 1/dpi LOVE units.
love={graphics={
  getDimensions=function() return 360,640 end,
  getPixelDimensions=function() return 1080,1920 end,
}}
package.loaded["mods.STADIUM2_IMPORTER.lib.battle_viewport"]=nil
Viewport=require("mods.STADIUM2_IMPORTER.lib.battle_viewport")
local dense=Viewport.resolve(360,640)
local densePanels=Viewport.statusPanels(dense,{ly=176},2,
  {8,0,80,32},{72,56,88,40})
ok(math.abs(densePanels.scale-5/3)<.0001,
  "mobile HUD converts Battle Art's physical integer rung into LOVE units")
ok(math.abs(densePanels.enemyX-10/3)<.0001
    and math.abs(densePanels.playerX-(360-88*5/3))<.0001,
  "density conversion retains the same physical edge placement")

print(("%d checks passed (Stadium 2 Battle Art portrait layout)"):format(checks))
