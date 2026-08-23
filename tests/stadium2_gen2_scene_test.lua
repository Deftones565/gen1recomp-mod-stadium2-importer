package.path = "./?.lua;./?/init.lua;" .. package.path

local Camera = require("mods.STADIUM2_IMPORTER.lib.battle_camera")
local Stage = require("mods.STADIUM2_IMPORTER.lib.battle_stage")
local Sky = require("mods.STADIUM2_IMPORTER.lib.battle_sky")
local Scene = require("mods.STADIUM2_IMPORTER.lib.battle_scene")
local StadiumBattleLayout = require("mods.STADIUM2_IMPORTER.lib.stadium_battle_layout")

local checks=0
local function ok(value,message)
  checks=checks+1
  if not value then error("FAIL "..message,0) end
end
local function near(got,want,tolerance,message)
  ok(math.abs(got-want)<=tolerance,
    ("%s (got %.3f, want %.3f)"):format(message,got,want))
end

Camera.recentre()
Camera.reset()
ok(Camera.fitScale(1280,720)==4,
  "wide battle scale is solved against the 304x144 composition")
ok(Camera.fitScale(1920,1080)==6,
  "1080p wide battle does not inflate to the classic 160-wide scale")
ok(Camera.fitScale(2560,1600)==8,
  "large 16:10 display keeps HUD blocks proportional to the wide scene")
local ox,oy=Camera.fitOrigin(1920,1080,6)
ok(ox==480 and oy==108,
  "wide scale keeps the native 160x144 coordinate frame centred")
for _,size in ipairs({{160,144},{1280,720},{1920,1080},{900,1200},{3440,1440}}) do
  local frame=Camera.frame(size[1],size[2])
  ok(frame.projection[6]<0,"Gold projection converts GL clip Y to LOVE canvas Y")
  local px,py=Camera.project(frame,size[1],size[2],Stage.positions.player)
  local ex,ey=Camera.project(frame,size[1],size[2],Stage.positions.enemy)
  ok(px>0 and px<size[1] and py>0 and py<size[2],"player anchor remains in viewport")
  ok(ex>0 and ex<size[1] and ey>0 and ey<size[2],"enemy anchor remains in viewport")
  local box=frame.letterbox
  near(px,box.lx+26*box.scale,2.0,"player anchor matches Gold back-pic footing")
  near(py,box.ly+96*box.scale,2.0,"player vertical anchor matches Gold")
  near(ex,box.lx+124*box.scale,2.0,"enemy anchor matches Gold front-pic footing")
  near(ey,box.ly+56*box.scale,2.0,"enemy vertical anchor matches Gold")
end

local tiny={renderer={worldMetrics=function() return {height=52.25,radius=1} end}}
local huge={renderer={worldMetrics=function() return {height=52.25,radius=999} end}}
ok(Stage.radius(tiny)==Stage.MIN_RADIUS,"small model platform uses minimum footprint")
ok(Stage.radius(huge)==Stage.MAX_RADIUS,"large model platform is bounded")

local modelActor={
  renderer={worldMetrics=function()
    return {height=200,floor=-20,radius=50}
  end},
  scale=function() return 1 end,
}
local legacyScene=Scene.new({actors={player=modelActor,enemy=modelActor}})
ok(legacyScene.sceneMode=="classic" and not legacyScene.arenaMode,
  "legacy battle composition remains an explicit classic scene")
local legacyMatrix=legacyScene:modelMatrix("enemy",modelActor)
ok(legacyMatrix[12]==Stage.positions.enemy[3] and legacyMatrix[1]~=.05,
  "legacy battle mode retains normalized presentation placement and scale")
local arenaScene=Scene.new({actors={player=modelActor,enemy=modelActor},
  arenaMode=true,arenaScale=.05,arenaGroundY=2})
ok(arenaScene.sceneMode=="arena" and arenaScene.arenaMode,
  "arena composition is isolated from the classic battle scene")
ok(arenaScene:resolveEnvironment()==Scene.ARENA_ENVIRONMENT,
  "arena composition uses neutral field lighting instead of the classic sky environment")
arenaScene:setSceneMode("classic")
ok(arenaScene.sceneMode=="classic" and not arenaScene.arenaMode,
  "classic scene remains selectable after constructing an arena scene")
arenaScene:setSceneMode("arena")
local enemyArenaMatrix=arenaScene:modelMatrix("enemy",modelActor)
local playerArenaMatrix=arenaScene:modelMatrix("player",modelActor)
near(enemyArenaMatrix[3],-.05,1e-6,
  "arena mode uses the field's ROM-to-world scale for Pokemon")
near(enemyArenaMatrix[8],3,1e-6,
  "arena mode grounds the Pokemon's real model floor")
near(enemyArenaMatrix[4],7.5,1e-6,
  "arena mode places the opponent at Stadium's +150 X field slot")
near(playerArenaMatrix[4],-7.5,1e-6,
  "arena mode places the player at Stadium's -150 X field slot")
near(enemyArenaMatrix[12],0,1e-6,
  "Stadium battle slots remain on the arena's Z centre line")
local arenaEnemyPosition=arenaScene:actorPosition("enemy")
near(arenaEnemyPosition[1],7.5,1e-6,
  "arena camera and extension marks use the rendered opponent slot")
near(arenaEnemyPosition[2],2,1e-6,
  "arena camera and extension marks use the rendered field ground")

Camera.recentre()
local arenaFrame=Camera.arenaFrame(1280,720,{
  scale=.05,groundY=2,actors={player=modelActor,enemy=modelActor},
})
near(arenaFrame.stadium.fov,math.rad(45),1e-8,
  "arena mode uses Stadium 2's ROM battle-camera field of view")
near(arenaFrame.stadium.near,1,1e-8,
  "arena mode converts Stadium's 20-unit near plane with the field scale")
near(arenaFrame.stadium.far,320,1e-8,
  "arena mode converts Stadium's 6400-unit far plane with the field scale")
near(arenaFrame.focus[2],5.52,1e-6,
  "arena camera derives its vertical target from loaded model bounds")
Camera.setArenaTarget("enemy")
Camera.setArenaMode(1)
local stadiumShot=Camera.arenaFrame(1280,720,{
  scale=.05,groundY=2,actors={player=modelActor,enemy=modelActor},
})
ok(stadiumShot.stadium.preset==0 and stadiumShot.stadium.variant=="A"
    and stadiumShot.stadium.target=="enemy",
  "viewer can select the ROM's first opponent camera variant")
Camera.setArenaMode(9)
local wideStadiumShot=Camera.arenaFrame(1280,720,{
  scale=.05,groundY=2,actors={player=modelActor,enemy=modelActor},
})
near(wideStadiumShot.stadium.fov,math.rad(60),1e-8,
  "camera mode cycling preserves each ROM preset's authored FOV")
Camera.setArenaMode(0)
local legacyAfterArena=Camera.frame(1280,720)
near(legacyAfterArena.focus[1],Camera.RIG.lookX,1e-8,
  "arena camera construction does not replace the legacy Gold camera rig")

local steelixActor={dex=208,renderer=modelActor.renderer,scale=modelActor.scale}
local steelixMatrix=arenaScene:modelMatrix("enemy",steelixActor)
near(steelixMatrix[4],0,1e-6,
  "arena mode preserves Stadium's zero-origin Steelix placement override")
for species,distance in pairs({[3]=185,[95]=225,[130]=200,[249]=200,[250]=185}) do
  local playerSlot,playerYaw=StadiumBattleLayout.slot("player",species)
  local enemySlot,enemyYaw=StadiumBattleLayout.slot("enemy",species)
  ok(playerSlot[1]==-distance and enemySlot[1]==distance
      and playerSlot[3]==0 and enemySlot[3]==0,
    ("species %03d uses its fragment-79 X slot"):format(species))
  near(playerYaw,math.pi*.5,1e-6,
    ("species %03d player faces inward"):format(species))
  near(enemyYaw,-math.pi*.5,1e-6,
    ("species %03d opponent faces inward"):format(species))
end

local day=Sky.resolve({world={hour=function() return 12 end,daytime="DAY",map={def={environment="ROUTE"}}}})
ok(day.outdoor and day.daytime=="DAY","route battle follows Gold daytime")
local night=Sky.resolve({world={hour=function() return 22 end,daytime="NITE",map={def={environment="TOWN"}}}})
ok(night.outdoor and night.orbKind=="moon","night battle selects moon lighting")
local dawnA=Sky.resolve({world={hour=function() return 6 end,minute=function() return 15 end,
  daytime="MORN",map={def={environment="ROUTE"}}}})
local dawnB=Sky.resolve({world={hour=function() return 6 end,minute=function() return 45 end,
  daytime="MORN",map={def={environment="ROUTE"}}}})
ok(dawnA.bands[3][1]~=dawnB.bands[3][1],
  "outdoor battle lighting changes continuously within a Gold clock phase")
local cave=Sky.resolve({world={hour=function() return 12 end,daytime="DAY",map={def={environment="CAVE"}}}})
ok(cave.indoor and not cave.outdoor,"cave battle selects neutral void")

Camera.recentre()
Camera.mouseOrbit(40)
Camera.mousePitch(40)
Camera.stepZoom(-1)
local goal=Camera.state()
ok(goal.orbitGoal>0 and goal.pitchGoal>0,
  "ordinary mouse deltas steer both camera axes")
ok(goal.zoomGoal<1,"wheel-in step narrows the battle lens")
ok(goal.orbit==0 and goal.pitch==0 and goal.zoom==1,
  "camera input eases instead of cutting to its goal")
Camera.update(.25)
ok(goal.orbit>0 and goal.pitch>0 and goal.zoom<1,
  "camera catches mouse and wheel goals on presented-frame time")

Camera.orbit(99);Camera.pitch(99);Camera.zoom(99);Camera.update(1)
local steered=Camera.frame(1280,720)
for side,point in pairs(Stage.positions) do
  local x,y,visible=Camera.project(steered,1280,720,point)
  ok(visible and x>=0 and x<=1280 and y>=0 and y<=720,
    side.." anchor remains visible at the camera limits")
end
Camera.recentre()

local sourceFile=assert(io.open("mods/STADIUM2_IMPORTER/lib/gen2_battle.lua","rb"))
local source=sourceFile:read("*a")
sourceFile:close()
local sharedFile=assert(io.open("mods/STADIUM2_IMPORTER/lib/battle_scene.lua","rb"))
local shared=sharedFile:read("*a")
sharedFile:close()
ok(shared:find("function Scene.surfaceDimensions",1,true)~=nil
  and shared:find("g.getDimensions",1,true)~=nil,
  "shared battle layout uses LOVE window units rather than framebuffer pixels")
ok(shared:find("AA.expand(pixelWidth,pixelHeight)",1,true)~=nil
  and shared:find("AA.resolve(self.canvas,pixelWidth,pixelHeight)",1,true)~=nil,
  "HiDPI framebuffer pixels remain confined to shared 3D render-target resolution")
ok(source:find('lib.battle_actor',1,true)~=nil
  and source:find('lib.battle_scene',1,true)~=nil,
  "Gold adapter consumes the generation-neutral Actor and Scene")
ok(source:find("scene.width~=width or scene.height~=height",1,true)~=nil
  and source:find("scene:render(width,height)",1,true)~=nil,
  "widescreen presentation rebuilds HUD layout immediately after resize/orientation changes")
ok(source:find("drawNicknameModal",1,true)==nil
  and source:find('nicknameModal=self.phase=="ask-nickname"',1,true)~=nil
  and source:find("Hud.hudLayer",1,true)~=nil
  and source:find("Hud.modalLayer",1,true)~=nil
  and source:find("self.drawHud=function() end",1,true)~=nil
  and source:find("Hud.composite(scene,self,layer,hudLayer,modalLayer)",1,true)~=nil,
  "nickname prompt separates snapped HUD and clean modal-only captures")

ok(source:find('self.hudCleared=function() return false end',1,true)~=nil
  and source:find('hudLayerOk,hudLayer=pcall(Hud.hudLayer',1,true)~=nil,
  "detached Stadium HUD capture ignores Gold's per-move BattleAnimClearHud")

ok(source:find("scene.deferAnimationObjects",1,true)~=nil
  and source:find("self.animView.drawObjects",1,true)~=nil,
  "native battle OBJs are composited once after the split widescreen HUD")
ok(source:find("g.rotate(angle)",1,true)==nil
  and source:find("animationProjection",1,true)~=nil,
  "native Pokeball and hit-sprite layer is never rotated with the 3D battler axis")
ok(source:find("caughtInFlight",1,true)~=nil
  and source:find("PIC_SCALE",1,true)~=nil,
  "capture keeps the foe until ReturnMon shrinks and hides it")

print(("%d checks passed (Stadium 2 owned Gen 2 scene)"):format(checks))
