package.path="./?.lua;./?/init.lua;"..package.path

local checks=0
local function ok(value,message)
  checks=checks+1
  if not value then error("FAIL "..message,0) end
end

-- Minimal Gen 1 host presentation surface. Camera-control installation must
-- not replace any battle mechanics; it only wraps the live Game input seams.
local Host={}
Host.isWideBattleLayout=function() return true end
Host.draw=function() end
Host.drawPicsLayer=function() end
Host.drawHUDs=function() end
Host.drawTextArea=function() end
Host.drawAnimLayer=function() end
package.preload["src.battle.BattleState"]=function() return Host end
package.loaded["src.battle.BattleState"]=nil

local calls={key=0,wheel=0,pad=0,axis=0,focus=0}
local game={data={pokemon={PIKACHU={dex=25},CLEFAIRY={dex=35}}}}
function game:keypressed() calls.key=calls.key+1 end
function game:wheelmoved() calls.wheel=calls.wheel+1 end
function game:gamepadpressed() calls.pad=calls.pad+1 end
function game:gamepadaxis() calls.axis=calls.axis+1 end
function game:focus() calls.focus=calls.focus+1 end

local hooks={}
local mod={hooks={wrap=function(_,name,fn) hooks[name]=fn; return fn end}}

local Importer=require("mods.STADIUM2_IMPORTER.lib.importer")
Importer.configure=function() end
Importer.modelsEnabled=function() return true end
Importer.battleEnabled=function() return true end
Importer.available=function() return true end
local function renderer()
  return {
    finished=false,frame=0,
    setContext=function() return true end,
    setHandlerRuntime=function() end,
    step=function() end,
    release=function() end,
  }
end
Importer.newRenderer=function() return renderer() end
Importer.newSpecialRenderer=function() return renderer() end

package.loaded["mods.STADIUM2_IMPORTER.lib.gen1_battle"]=nil
local Gen1=require("mods.STADIUM2_IMPORTER.lib.gen1_battle")
local Camera=require("mods.STADIUM2_IMPORTER.lib.battle_camera")
Camera.recentre()

Gen1.bind(mod)
Gen1.configureGame(game)
ok(Gen1.install(),"Gen 1 camera/control hooks install")
ok(type(hooks["input.pointer"])=="function","Gen 1 installs the public pointer-camera seam")
ok(type(hooks["render.compose"])=="function","render compose hook remains installed")

local battle={
  game=game,data=game.data,
  player={mon={species=25},fainted=false},
  enemy={mon={species=35},fainted=false},
  growInScale=function() end,fxHidden=function() return false end,
  fxFaintActive=function() return false end,
}
ok(Gen1.ensure(battle),"test battle owns a Gen 1 Stadium scene")

local before=Camera.state().zoomGoal
game:wheelmoved(0,1)
ok(Camera.state().zoomGoal~=before and calls.wheel==0,
  "mouse wheel zooms Stadium camera and does not invoke overworld zoom during battle")

local zoom=Camera.state().zoomGoal
game:keypressed("e")
ok(Camera.state().zoomGoal~=zoom and calls.key==0,"E changes Stadium zoom during Gen 1 battle")
game:keypressed("x")
ok(calls.key==1,"unclaimed keyboard input still reaches the Gen 1 engine")

game:gamepadaxis(nil,"rightx",.75)
game:gamepadaxis(nil,"righty",-.5)
local status=Gen1.status()
ok(status.cameraInput and status.cameraInput.stickX==.75 and status.cameraInput.stickY==-.5,
  "controller right stick is captured as presentation camera input")
ok(calls.axis==2,"right-stick axis events still reach the engine input path")

local orbit=Camera.state().orbitGoal
local pitch=Camera.state().pitchGoal
hooks["input.pointer"](function() return false end,game,
  {source="mouse",phase="moved",id="mouse",dx=20,dy=-10,x=100,y=100})
ok(Camera.state().orbitGoal~=orbit and Camera.state().pitchGoal~=pitch,
  "ordinary mouse movement steers Gen 1 orbit and pitch")

local touchOrbit=Camera.state().orbitGoal
local nextCalls=0
local function nextPointer() nextCalls=nextCalls+1; return false end
hooks["input.pointer"](nextPointer,game,
  {source="touch",phase="pressed",id=1,x=100,y=100,dx=0,dy=0})
hooks["input.pointer"](nextPointer,game,
  {source="touch",phase="moved",id=1,x=180,y=120,dx=80,dy=20})
ok(Camera.state().orbitGoal~=touchOrbit,"one free touch drags the Gen 1 camera")
ok(nextCalls==2,"camera pointer handling preserves the mod pointer hook chain")

local pinchZoom=Camera.state().zoomGoal
hooks["input.pointer"](nextPointer,game,
  {source="touch",phase="pressed",id=2,x=260,y=120,dx=0,dy=0})
hooks["input.pointer"](nextPointer,game,
  {source="touch",phase="moved",id=2,x=330,y=120,dx=70,dy=0})
ok(Camera.state().zoomGoal~=pinchZoom,"two free touches pinch-zoom the Gen 1 camera")
hooks["input.pointer"](nextPointer,game,
  {source="touch",phase="released",id=1,x=180,y=120})
hooks["input.pointer"](nextPointer,game,
  {source="touch",phase="released",id=2,x=330,y=120})

game:focus(false)
status=Gen1.status()
ok(status.cameraInput.stickX==0 and status.cameraInput.stickY==0 and calls.focus==1,
  "focus loss clears held camera stick/touch state and preserves engine focus handling")

game:gamepadpressed(nil,"leftstick")
ok(calls.pad==0,"camera stick-click zoom is presentation-owned during battle")
game:gamepadpressed(nil,"a")
ok(calls.pad==1,"ordinary gamepad buttons still reach the battle engine")

game:keypressed("0")
ok(Camera.state().orbitGoal==0 and Camera.state().pitchGoal==0 and Camera.state().zoomGoal==1,
  "0 recentres the Gen 1 Stadium shot")

Gen1.finish(battle)
local wheelCalls=calls.wheel
game:wheelmoved(0,1)
ok(calls.wheel==wheelCalls+1,"camera wrappers fall through after the Stadium battle ends")

print(("%d checks passed (Stadium 2 Gen 1 camera controls)"):format(checks))
