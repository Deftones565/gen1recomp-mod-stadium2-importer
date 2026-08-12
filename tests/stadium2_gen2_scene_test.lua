package.path = "./?.lua;./?/init.lua;" .. package.path

local Camera = require("mods.STADIUM2_IMPORTER.lib.battle_camera")
local Stage = require("mods.STADIUM2_IMPORTER.lib.battle_stage")
local Sky = require("mods.STADIUM2_IMPORTER.lib.battle_sky")

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
ok(source:find("local function surfaceDimensions",1,true)~=nil
  and source:find("g.getDimensions",1,true)~=nil,
  "owned battle layout uses LOVE window units rather than framebuffer pixels")
ok(source:find("AA.expand(pixelWidth,pixelHeight)",1,true)~=nil
  and source:find("AA.resolve(self.canvas,pixelWidth,pixelHeight)",1,true)~=nil,
  "HiDPI framebuffer pixels remain confined to 3D render-target resolution")
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
