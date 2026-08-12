package.path = "./?.lua;./?/init.lua;" .. package.path

local Hud = require("mods.STADIUM2_IMPORTER.lib.battle_hud")

local checks = 0
local function ok(value, message)
  checks = checks + 1
  if not value then error("FAIL " .. message, 0) end
end

ok(Hud.isGaugePaper(8, 8, 1, 1, 1, 1),
  "caught-marker paper is transparent on the enemy HUD glass")
ok(Hud.isGaugePaper(15, 15, 1, 1, 1, 1),
  "caught-marker paper key covers the whole native tile")
ok(Hud.isGaugePaper(16, 16, 1, 1, 1, 1),
  "enemy HP paper is transparent")
ok(Hud.isGaugePaper(87, 23, 1, 1, 1, 1),
  "enemy HP end cap paper is transparent")
ok(Hud.isGaugePaper(80, 72, 1, 1, 1, 1),
  "player HP paper is transparent")
ok(Hud.isGaugePaper(143, 95, 1, 1, 1, 1),
  "player EXP paper is transparent")
ok(not Hud.isGaugePaper(7, 8, 1, 1, 1, 1),
  "caught-marker key does not bleed left of its native tile")
ok(not Hud.isGaugePaper(15, 16, 1, 1, 1, 1),
  "paper outside the HUD paper-key rows stays opaque")
ok(not Hud.isGaugePaper(88, 24, 1, 1, 1, 1),
  "enemy gauge key does not bleed past its end")
ok(not Hud.isGaugePaper(40, 16, 0, 0, 0, 1),
  "black HP label and frame pixels remain visible")
ok(not Hud.isGaugePaper(40, 16, 0.1, 0.8, 0.1, 1),
  "coloured HP fill remains visible")
ok(not Hud.isGaugePaper(100, 90, 0.3, 0.55, 0.95, 1),
  "blue EXP fill remains visible")

local clean={name="clean",getDimensions=function() return 1280,720 end}
local scene={width=1280,height=720,hudBox={lx=320,ly=72,scale=4},presentCanvas=clean}
local screen={showEnemyTrainer=false,showPlayerTrainer=false,phase="menu",messageTimer=0}
local layout=Hud.layout(scene,screen)
ok(layout.snap and layout.enemyX==-32 and layout.playerX==672,
  "ordinary widescreen battle snaps native HUD rects to the two screen edges")
ok(layout.enemyPanelX==0 and layout.playerPanelX==960,
  "frost panels touch the same edges as their native HUD rectangles")
-- AskNickname follows the detached wide compositor: the status
-- HUDs stay snapped, while the Yes/No modal remains in the centred GB frame.
screen.phase="ask-nickname"
screen.messageTimer=0
layout=Hud.layout(scene,screen)
ok(layout.asking and layout.modal and layout.nicknameModal and layout.snap,
  "nickname prompt keeps the wide snapped HUD geometry")
ok(layout.enemyX==-32 and layout.playerX==672,
  "nickname prompt does not pull either HUD band back into the centre")
ok(layout.enemyPanelX==0 and layout.playerPanelX==960,
  "nickname frost panels stay attached to the wide HUD edges")
ok(Hud.NICKNAME_MODAL_RECT[1]==112 and Hud.NICKNAME_MODAL_RECT[2]==56
    and Hud.NICKNAME_MODAL_RECT[3]==48 and Hud.NICKNAME_MODAL_RECT[4]==40,
  "nickname Yes/No modal keeps Gold's native centred rectangle")
ok(Hud.keysPaperRect(112,56,48,40),
  "nickname Yes/No paper is keyed for the same glass compositor as the HUD")
ok(Hud.keysPaperRect(8,56,48,40),
  "shift Yes/No paper uses the same glass treatment")
-- Other in-battle Yes/No boxes still use the centred upper-band fallback.
screen.phase="ask-shift"
layout=Hud.layout(scene,screen)
ok(layout.modal and not layout.snap,
  "shift Yes/No still becomes a centred native-width overlay")
ok(layout.enemyX==320 and layout.playerX==320,
  "centred Yes/No fallback keeps both upper UI bands together")
ok(layout.enemyPanelX==352 and layout.playerPanelX==608,
  "centred fallback preserves Gold's native HUD insets")
-- Functional compositor regression: AskNickname must source the two snapped
-- upper bands from the HUD-only capture, the bottom box from the full scene,
-- and the Yes/No window from the full scene at its centred native position.
local draws={}
love={graphics={
  setColor=function() end,
  rectangle=function() end,
  getShader=function() return nil end,
  setShader=function() end,
  newShader=function() return {send=function() end} end,
  newQuad=function(x,y,w,h,tw,th) return {x=x,y=y,w=w,h=h,tw=tw,th=th} end,
  draw=function(tex,quad,x,y,rot,sx,sy)
    draws[#draws+1]={tex=tex,quad=quad,x=x,y=y,sx=sx,sy=sy}
  end,
}}
local full={name="full"}
local hudOnly={name="hud"}
local modalOnly={name="modal"}
local compositeScreen={showEnemyTrainer=false,showPlayerTrainer=false,
  showEnemyHud=true,showPlayerHud=true,tutorial=false,phase="ask-nickname",
  messageTimer=0,hudCleared=function() return false end}
assert(Hud.composite(scene,compositeScreen,full,hudOnly,modalOnly))
ok(draws[1].tex==hudOnly and draws[1].quad.y==0 and draws[1].x==-32,
  "nickname enemy band comes from the HUD-only snapped capture")
ok(draws[2].tex==hudOnly and draws[2].quad.y==48 and draws[2].x==672,
  "nickname player band comes from the HUD-only snapped capture")
ok(draws[3].tex==full and draws[3].quad.y==96 and draws[3].x==320,
  "nickname message box remains in the centred full battle layer")
ok(draws[4].tex==clean and draws[4].x==768 and draws[4].y==296,
  "nickname modal first restores the clean 3D scene over the snapped HUD")
ok(draws[5].tex==modalOnly and draws[5].quad.x==112 and draws[5].quad.y==56
    and draws[5].x==768 and draws[5].y==296,
  "nickname Yes/No redraw uses a modal-only source with no native HUD behind it")
ok(draws[5].tex~=full,
  "transparent nickname modal never reuses the dirty full battle capture")

-- Attack animation regression: Gold's native BattleAnimClearHud is an
-- animation-layer concern.  A detached snapped Stadium status HUD must remain
-- present even while the native state reports that both sides are cleared.
draws={}
local attackScreen={showEnemyTrainer=false,showPlayerTrainer=false,
  showEnemyHud=true,showPlayerHud=true,tutorial=false,phase="menu",
  messageTimer=0,hudCleared=function() return true end}
assert(Hud.composite(scene,attackScreen,full,hudOnly,nil))
ok(draws[1].tex==hudOnly and draws[1].quad.y==0,
  "attack frame enemy status comes from persistent HUD-only capture")
ok(draws[2].tex==hudOnly and draws[2].quad.y==48,
  "attack frame player status comes from persistent HUD-only capture")

print(("%d checks passed (Stadium 2 battle HUD paper key)"):format(checks))
