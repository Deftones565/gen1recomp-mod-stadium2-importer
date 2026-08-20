package.path="./?.lua;./?/init.lua;"..package.path

local checks=0
local function ok(value,message)
  checks=checks+1
  if not value then error("FAIL "..message,0) end
end

local Gen1=require("mods.STADIUM2_IMPORTER.lib.gen1_battle")
local Scene=Gen1.Scene

local function actor()
  return {
    renderer={},context="idle",faintFinished=false,flash=0,
    attackCalls={},entranceCalls=0,faintCalls=0,
    attack=function(self,index) self.attackCalls[#self.attackCalls+1]=index; return true end,
    play=function(self,name) if name=="entrance" then self.entranceCalls=self.entranceCalls+1 end; self.context=name; return true end,
    faint=function(self) self.faintCalls=self.faintCalls+1; self.context="faint"; return true end,
  }
end

local player,enemy=actor(),actor()
local subPlayer,subEnemy=actor(),actor()
local battle={
  player={mon={species=25},fainted=false},
  enemy={mon={species=35},fainted=false},
  data={moves={TACKLE={index=33}}},
  introSlide=0,
  growInScale=function(self,b)
    if b==self.player then return self.playerGrow end
    if b==self.enemy then return self.enemyGrow end
  end,
  fxHidden=function(self,b) return b==self.blinkTarget end,
  fxFaintActive=function(self,b) return b==self.faintTarget end,
}
local scene=setmetatable({
  battle=battle,actors={player=player,enemy=enemy},
  substituteActors={player=subPlayer,enemy=subEnemy},
  lastGrow={player=false,enemy=false},lastFainted={player=false,enemy=false},
  lastPicKind={player=nil,enemy=nil},animWasPlaying=false,readyFrame=true,
},Scene)

ok(scene:ownsSlot("player") and scene:ownsSlot("enemy"),
  "normal Gen 1 Pokemon slots are owned by the shared 3D actors")
ok(scene:visualState("player")=="pokemon" and scene:visualState("enemy")=="pokemon",
  "normal battlers resolve to Stadium Pokemon presentation")

battle.showEnemyTrainer=true; battle.trainerPic={}
ok(not scene:ownsSlot("enemy") and scene:visualState("enemy")=="native",
  "enemy trainer portrait remains host-native")
battle.showEnemyTrainer=nil; battle.trainerPic=nil
battle.showPlayerBack=true; battle.playerBackPic={}
ok(not scene:ownsSlot("player") and scene:visualState("player")=="native",
  "player trainer back portrait remains host-native")
battle.showPlayerBack=nil; battle.playerBackPic=nil

battle.enemyHidden=true
ok(scene:visualState("enemy")=="hidden",
  "host capture HIDEPIC state hides only the 3D enemy presentation")
battle.enemyHidden=nil
battle.blinkTarget=battle.enemy
ok(scene:visualState("enemy")=="hidden",
  "host damage blink is reflected by the 3D presentation")
battle.blinkTarget=nil

battle.enemySendingOut=true
ok(scene:visualState("enemy")=="empty",
  "send-out text leaves the enemy slot empty before the host grow begins")
battle.enemyGrow=.5
ok(scene:visualState("enemy")=="pokemon" and scene:picScale("enemy")==.5,
  "host send-out grow directly scales the shared 3D actor")
battle.enemySendingOut=nil; battle.enemyGrow=nil

battle.enemy.substituteHP=1
ok(scene:visualState("enemy")=="substitute",
  "Gen 1 Substitute swaps the Pokemon actor for the owned substitute model")
battle.enemy.substituteHP=nil

battle.enemy.fainted=true
enemy.context="faint"; enemy.faintFinished=false
ok(scene:visualState("enemy")=="pokemon",
  "fainted 3D actor remains owned while its Stadium faint clip is playing")
enemy.faintFinished=true
ok(scene:visualState("enemy")=="empty",
  "fainted slot empties after the Stadium faint clip finishes")
battle.enemy.fainted=false; enemy.context="idle"; enemy.faintFinished=false

battle.animPlaying=true; battle.animName="TACKLE"; battle.animAttackerIsPlayer=true
scene:syncPresentationState()
ok(player.attackCalls[#player.attackCalls]==33,
  "native Gen 1 move row drives the attacker's Stadium move clip by move index")
scene:syncPresentationState()
ok(#player.attackCalls==1,"one native animation rising edge triggers one Stadium attack")
battle.animPlaying=false
scene:syncPresentationState()

battle.enemyGrow=.25
scene:syncPresentationState()
ok(enemy.context=="entrance","host grow rising edge starts the Stadium entrance clip")
battle.enemyGrow=nil
scene:syncPresentationState()

battle.faintTarget=battle.enemy
scene:syncPresentationState()
ok(enemy.faintCalls==1 and enemy.context=="faint",
  "host faint presentation starts the Stadium faint clip without changing battle state")

local p=Gen1._animationProjection({player={40,100},enemy={140,60}})
ok(p and type(p.scale)=="number" and p.scale>0,
  "native Gen 1 effect projection is a rigid translate/scale mapping")

print(("%d checks passed (Stadium 2 Gen 1 state presentation)"):format(checks))
