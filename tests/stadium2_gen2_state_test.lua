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

local Gen2=require("mods.STADIUM2_IMPORTER.lib.gen2_battle")
local checks=0
local function ok(value,message)
  checks=checks+1
  if not value then error("FAIL "..message,0) end
end

local volatile={}
local battle={volatile=function(_,mon) return volatile[mon] or {} end}
local scene=Gen2.Scene.new(battle)
scene.readyFrame=true
local mon={hp=20,species="PIKACHU",name="PIKACHU"}
battle.player=mon
local rig={finished=false,frame=0,
  setMove=function() return true end,
  setContext=function() return true end,
  setHandlerRuntime=function() end,step=function() end,
  release=function() end}
local actor=scene.actors.player
actor.mon,actor.renderer,actor.dex=mon,rig,25
scene.screen={
  showPlayerTrainer=false,showEnemyTrainer=false,
  picHidden={player=false,enemy=false},
  animPicState=function() return nil end,
  game={data={moves={SUBSTITUTE={effect="EFFECT_SUBSTITUTE",index=164},
    FLY={effect="EFFECT_FLY",index=19},DIG={effect="EFFECT_FLY",index=91}}}},
  name=function(_,value) return value.name end,
}

ok(scene:ownsSlot("player"),"ordinary Pokemon slot is owned")
ok(scene:visualState("player")=="pokemon","ordinary Pokemon model is visible")

scene.screen.showPlayerTrainer=true
ok(not scene:ownsSlot("player") and scene:visualState("player")=="trainer",
  "native trainer art is the only pic allowed through")
scene.screen.showPlayerTrainer=false

scene.screen.animPicState=function() return {hidden=true} end
ok(scene:ownsSlot("player") and scene:visualState("player")=="hidden",
  "animation hide never surrenders the slot")
scene.screen.animPicState=function() return nil end

volatile[mon]={vanished=true}
ok(scene:visualState("player")=="hidden",
  "Fly and Dig remain hidden between animation scripts")
volatile[mon]={}

volatile[mon]={vanished=true,chargeMove="FLY"}
scene:handleEvent({kind="move",side="player",move="FLY"})
scene.screen.anim={}
scene.screen.animPicState=function() return {hidden=false} end
ok(scene:visualState("player")=="pokemon",
  "Fly departure keeps the model until the authored hide point")
scene.screen.animPicState=function() return {hidden=true} end
ok(scene:visualState("player")=="hidden","Fly departure latches its hidden state")
scene.screen.anim=nil
ok(scene:visualState("player")=="hidden","Fly remains hidden between turns")

volatile[mon]={}
scene:handleEvent({kind="move",side="player",move="FLY"})
scene.screen.anim={}
scene.screen.animPicState=function() return {hidden=false} end
ok(scene:visualState("player")=="hidden",
  "Fly return does not reveal the model at animation initialization")
scene.screen.animPicState=function() return {hidden=true} end
ok(scene:visualState("player")=="hidden","Fly return observes the hidden phase")
scene.screen.animPicState=function() return {hidden=false} end
ok(scene:visualState("player")=="pokemon","Fly returns at the authored show point")
scene.screen.anim=nil
scene.screen.animPicState=function() return nil end

volatile[mon]={vanished=true,chargeMove="DIG"}
scene:handleEvent({kind="move",side="player",move="DIG"})
scene.screen.anim={}
scene.screen.animPicState=function() return {hidden=false} end
ok(scene:visualState("player")=="pokemon","Dig begins with its burrow visible")
scene.screen.animPicState=function() return {hidden=true} end
ok(scene:visualState("player")=="hidden","Dig latches underground at its hide point")
scene.vanish.player={active=false}
volatile[mon]={}
scene.screen.anim=nil
scene.screen.animPicState=function() return nil end

scene.screen.picHidden.player=true
ok(scene:visualState("player")=="empty" and scene:ownsSlot("player"),
  "capture/removal leaves an empty owned slot")
scene.screen.picHidden.player=false

mon.hp=0
ok(scene:visualState("player")=="pokemon",
  "live zero HP cannot hide a model before its presented faint event")
actor.pendingFaint=true
ok(scene:visualState("player")=="pokemon","pending faint keeps the model visible")
actor.pendingFaint=false;actor.context="faint";actor.faintFinished=false
ok(scene:visualState("player")=="pokemon","authored faint remains visible to completion")
actor.faintFinished=true
ok(scene:visualState("player")=="empty" and scene:ownsSlot("player"),
  "completed faint leaves an empty owned platform")
mon.hp=20;actor.context="idle";actor.faintFinished=false

scene:handleEvent({kind="move",side="player",move="SUBSTITUTE"})
ok(scene:visualState("player")=="substitute" and scene:ownsSlot("player"),
  "Substitute replaces the Pokemon without enabling its sprite")
scene:handleEvent({kind="message",text="PIKACHU's SUBSTITUTE broke!"})
ok(scene:visualState("player")=="pokemon",
  "breaking Substitute restores the model directly")

-- A successful catch sets picHidden before the ball animation starts.  The
-- model must still be present while ReturnMon shrinks it, then disappear at
-- the authored hidden step and remain absent after the animation.
local enemy={hp=18,species="RATTATA",name="RATTATA"}
battle.enemy=enemy
local enemyActor=scene.actors.enemy
enemyActor.mon,enemyActor.renderer,enemyActor.dex=enemy,rig,19
scene.screen.picHidden.enemy=true
scene.screen.ballThrow={caught=true}
scene.screen.anim={}
scene.screen.animPicState=function(_,side)
  if side=="enemy" then return {hidden=false,size=4,slide=0} end
  return nil
end
ok(scene:visualState("enemy")=="pokemon",
  "caught foe remains visible while the Pokeball animation owns ReturnMon")
ok(math.abs(scene:picScale("enemy")-5/7)<0.0001,
  "caught foe follows Gold's 7x7 to 5x5 ReturnMon scale")
scene.screen.animPicState=function(_,side)
  if side=="enemy" then return {hidden=false,size=5,slide=0} end
  return nil
end
ok(math.abs(scene:picScale("enemy")-3/7)<0.0001,
  "caught foe follows Gold's final 3x3 ReturnMon scale")
scene.screen.animPicState=function(_,side)
  if side=="enemy" then return {hidden=true,size=nil,slide=0} end
  return nil
end
ok(scene:visualState("enemy")=="hidden",
  "caught foe disappears at the animation's authored hidden step")
scene.screen.anim=nil
scene.screen.animPicState=function() return nil end
ok(scene:visualState("enemy")=="empty",
  "capture latch keeps the foe slot empty after the ball animation")
scene.screen.picHidden.enemy=false
scene.screen.ballThrow=nil

local projection=Gen2._animationProjection({player={30,92},enemy={118,60}})
ok(projection and projection.scale and projection.angle==nil,
  "native battle OBJ projection is translate/scale only and carries no rotation")

actor.renderer=nil
ok(scene:ownsSlot("player") and scene:visualState("player")=="defect",
  "renderer defects never authorize native Pokemon sprites")

print(("%d checks passed (Stadium 2 Gen 2 state ownership)"):format(checks))
