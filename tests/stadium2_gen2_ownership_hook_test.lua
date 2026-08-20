package.path="./?.lua;./?/init.lua;"..package.path

local unownOk=pcall(require,"src.core.gen2.Unown")
if not unownOk then
  package.preload["src.core.gen2.Unown"]=function()
    return {
      index=function(value) return type(value)=="number" and value or nil end,
      letterFromDVs=function() return 1 end,
      name=function(index) return string.char(64+(tonumber(index) or 1)) end,
    }
  end
end

local calls={pic=0,wide=0,mouse=0,wheel=0,objects=0,scene=0,hud=0,modal=0,composite=0,lastRunner=nil}
local BattleState={
  drawPic=function() calls.pic=calls.pic+1 end,
  drawWidescreen=function() calls.wide=calls.wide+1 end,
  drawHud=function() calls.hud=calls.hud+1 end,
  stepAnim=function(self)
    if not self.anim then return end
    local runner=self.anim
    if not runner:step() then self.anim=nil end -- Gen1Recomp 0.1.78 behavior
  end,
  startAnim=function(self,runner) self.anim=runner; return true end,
  advanceQueue=function() end,finishBattle=function() end,
}
local View={present=function() end,drawObjects=function(_,runner) calls.objects=calls.objects+1; calls.lastRunner=runner end}
local Game2={keypressed=function() end,
  wheelmoved=function() calls.wheel=calls.wheel+1 end,
  mousemoved=function() calls.mouse=calls.mouse+1 end,
  gamepadaxis=function() end,gamepadpressed=function() end}
package.loaded["src.ui.gen2.BattleState"]=BattleState
package.loaded["src.ui.gen2.BattleAnimView"]=View
package.loaded["src.core.Game2"]=Game2
package.loaded["src.core.TouchControls"]={hitTest=function() return false end}

love={graphics={
  clear=function() end,setColor=function() end,draw=function() end,rectangle=function() end,
  push=function() end,pop=function() end,translate=function() end,scale=function() end,
}}

local Importer=require("mods.STADIUM2_IMPORTER.lib.importer")
Importer.modelsEnabled=function() return true end
Importer.battleEnabled=function() return true end
Importer.available=function() return true end
Importer.newRenderer=function()
  return {finished=false,frame=0,
    setContext=function() return true end,setMove=function() return true end,
    setHandlerRuntime=function() end,step=function() end,release=function() end}
end

local Hud=require("mods.STADIUM2_IMPORTER.lib.battle_hud")
Hud.layer=function(draw) if draw then draw() end; return {} end
Hud.hudLayer=function(draw) if draw then draw() end; return {} end
Hud.modalLayer=function(draw) calls.modal=calls.modal+1; if draw then draw() end; return {} end
Hud.composite=function() calls.composite=calls.composite+1; return true end

package.loaded["mods.STADIUM2_IMPORTER.lib.gen2_battle"]=nil
local Gen2=require("mods.STADIUM2_IMPORTER.lib.gen2_battle")
Gen2.bind({log={warn=function() end}})
assert(Gen2.install())

local mon={species="PIKACHU",hp=20}
local battle={player=mon,data={pokemon={PIKACHU={dex=25}}},
  volatile=function() return {} end}
assert(Gen2.ensure(battle))
local screen=setmetatable({battle=battle,game={data=battle.data},
  activeMon=function(_,side) return side=="player" and mon or nil end,
  showPlayerTrainer=false,showEnemyTrainer=false,
  picHidden={player=false,enemy=false},animPicState=function() return nil end,
  drawScene=function() calls.scene=calls.scene+1 end,phase="resolving"}, {__index=BattleState})

screen:drawPic(mon,true)
assert(calls.pic==1,"native Pokemon pic did not fail open before the first valid 3D frame")
local ownedScene=Gen2.currentScene()
ownedScene.readyFrame=true
ownedScene.width,ownedScene.height=1280,720
ownedScene.hudBox={lx=0,ly=0,scale=1}
ownedScene.presentCanvas={getWidth=function() return 1280 end,getHeight=function() return 720 end}
screen:drawWidescreen(1280,720)
assert(calls.wide==0,"native widescreen battle ran during an owned session")
screen.anim={}
screen.animView=View
screen:drawWidescreen(1280,720)
assert(calls.objects==1,
  "native animation OBJ layer was not drawn exactly once after HUD compositing")
screen.anim=nil
screen.animView=nil

-- Gen1Recomp 0.1.78 drops self.anim even when the throw script ended with
-- anim_keepsprites.  The importer must retain that finished runner so the
-- caught Pokeball remains visible through Gotcha/nickname instead of vanishing.
local keptRunner={keepSprites=false,step=function(self) self.keepSprites=true; return false end}
screen.anim=keptRunner
screen.animView=View
screen.ballThrow={caught=true}
screen:stepAnim()
assert(screen.anim==nil and screen.stadium2ImporterRetainedAnim==keptRunner,
  "0.1.78 successful catch did not latch the anim_keepsprites runner")
local beforeKeptDraw=calls.objects
screen:drawWidescreen(1280,720)
assert(calls.objects==beforeKeptDraw+1 and calls.lastRunner==keptRunner,
  "latched caught Pokeball OAM was not drawn after the host cleared self.anim")
local replacement={step=function() return true end}
screen:startAnim(replacement)
assert(screen.stadium2ImporterRetainedAnim==nil and screen.anim==replacement,
  "starting a new animation did not clear the retained caught Pokeball")
screen.anim=nil
screen.animView=nil
screen.ballThrow=nil

local composites=calls.composite
local scenes=calls.scene
local hudBefore,modalBefore=calls.hud,calls.modal
screen.phase="ask-nickname"
screen:drawWidescreen(1280,720)
assert(calls.scene==scenes+2 and calls.composite==composites+1
    and calls.hud==hudBefore+1 and calls.modal==modalBefore+1,
  "nickname modal did not keep 3D ownership with separate HUD and clean modal captures")
screen.phase="resolving"

local Camera=require("mods.STADIUM2_IMPORTER.lib.battle_camera")
Camera.recentre()
Game2:mousemoved(100,100,20,-10,false)
assert(Camera.state().orbitGoal>0 and Camera.state().pitchGoal>0,
  "bare mouse motion did not steer the owned battle camera")
assert(calls.mouse==1,"camera hover motion did not continue to the engine pointer seam")
Game2:wheelmoved(0,1)
assert(Camera.state().zoomGoal<1,"battle wheel did not zoom the owned camera")
assert(calls.wheel==0,"claimed battle wheel leaked into the overworld zoom")

Gen2.finish(nil,true)
print("11 checks passed (Stadium 2 permanent Gen 2 hooks and controls)")
