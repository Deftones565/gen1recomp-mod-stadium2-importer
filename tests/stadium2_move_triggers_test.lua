package.path="./?.lua;./?/init.lua;"..package.path

local Host={};Host.__index=Host
for _,name in ipairs({"draw","drawPicsLayer","drawHUDs","drawTextArea","drawAnimLayer"}) do
  Host[name]=function() end
end
Host.isWideBattleLayout=function() return true end
Host.applyHitFx=function(self,hit) self.lastHostHit=hit;return "hit",nil,7 end
Host.applyDamage=function(self,target,amount)
  target.substituteHP=nil
  self.nextInsert=1;self.queue={{text="localized break message"}}
  return amount
end
Host.startMessage=function(self,item) self.current=item end
local sprites={}
Host.speciesSprite=function(_,species)
  sprites[species]=sprites[species] or {};return sprites[species]
end
package.loaded["src.battle.BattleState"]=Host
local Player={start=function() return "started",nil,9 end}
package.loaded["src.battle.AnimPlayer"]=Player
local Gen1=require("mods.STADIUM2_IMPORTER.lib.gen1_battle")
local Importer=require("mods.STADIUM2_IMPORTER.lib.importer")
Importer.modelsEnabled=function() return true end
Importer.battleEnabled=function() return true end
Importer.available=function() return true end
local function actor()
  return {attacks={},hits=0,load=function(self,_,mon,dex) self.mon=mon;self.dex=dex end,
    attack=function(self,move) self.attacks[#self.attacks+1]=move end,
    hit=function(self) self.hits=self.hits+1 end,release=function() end}
end
local scene
Gen1.Scene.new=function(battle)
  scene=setmetatable({battle=battle,actors={player=actor(),enemy=actor()},
    substituteActors={player=actor(),enemy=actor()},release=function() end},Gen1.Scene)
  return scene
end
Gen1.bind({hooks={wrap=function() end}})
assert(Gen1.install())
local battle=setmetatable({data={moves={SURF={index=57},TRANSFORM={index=144}},
    pokemon={DITTO={dex=132},PIKACHU={dex=25}}},
  player={mon={species="DITTO"},sprite={}},enemy={mon={species="PIKACHU"},sprite={}},
  animPlayer=setmetatable({},{__index=Player})},Host)
assert(Gen1.ensure(battle))
local p,e=scene.actors.player,scene.actors.enemy
local a,b,c=battle.animPlayer:start("SURF",true)
assert(a=="started" and b==nil and c==9,"host return values changed")
battle.animPlayer:start("SURF",true)
assert(#p.attacks==2 and p.attacks[1]==57 and p.attacks[2]==57,
  "consecutive Surf starts must each select the species move row")
battle.animPlayer:start("SURF",false)
assert(#e.attacks==1 and e.attacks[1]==57,"enemy move targeted the wrong actor")
battle.animPlayer:start("POOF_ANIM",true)
assert(#p.attacks==2,"sendout incorrectly started an attack")
local unrelated=setmetatable({},{__index=Player})
unrelated:start("SURF",true)
assert(#p.attacks==2,"unrelated animation player affected battle")
battle.data.moves.FLY={index=19};battle.data.moves.DIG={index=91}
battle.data.moves.TELEPORT={index=100}
battle.player.charging={id="FLY"}
battle.animPlayer:start("TELEPORT",true)
assert(p.attacks[#p.attacks]==19,"Fly charge incorrectly selected the Teleport clip")
battle.player.charging={id="DIG"}
battle.animPlayer:start("SLIDE_DOWN_ANIM",true)
assert(p.attacks[#p.attacks]==91,"Dig charge failed to select the burrowing clip")
battle.player.charging=nil
local hit={blink=battle.enemy}
local h,_,n=battle:applyHitFx(hit)
assert(h=="hit" and n==7 and battle.lastHostHit==hit and e.hits==1)
battle:applyHitFx(hit)
assert(e.hits==2,"multi-hit impact must restart its reaction")
battle.enemy.substituteHP=10
scene.substituteActors.enemy.renderer={}
battle:applyHitFx(hit)
assert(e.hits==2,"substitute damage must not hit the hidden Pokemon")
assert(scene.substituteActors.enemy.hits==1,"substitute impact did not reach the doll")
assert(battle:applyDamage(battle.enemy,10)==10)
assert(scene:substituteVisible("enemy"),"breaking hit removed the doll before its impact")
battle:applyHitFx(hit)
assert(e.hits==2 and scene.substituteActors.enemy.hits==2,
  "breaking hit incorrectly struck the Pokemon behind the doll")
battle:startMessage(battle.queue[1])
assert(not scene:substituteVisible("enemy"),"break presentation did not restore Pokemon")
battle.enemy.substituteHP=10;battle.enemy.substitutePending=true
assert(not scene:substituteVisible("enemy"),"pending creation displayed the doll early")
battle.enemy.substitutePending=nil
assert(scene:substituteVisible("enemy"),"creation boundary did not reveal the doll")
local pic=battle:speciesSprite("PIKACHU",true)
scene:sync()
assert(p.dex==132,"Transform changed model before host committed its sprite")
battle.player.sprite=pic
scene:sync()
assert(p.dex==25 and battle.player.mon.species=="DITTO",
  "Transform must copy presentation without rewriting the battler")
battle.player={mon={species="DITTO"},sprite={}}
scene:sync()
assert(p.dex==132,"switching back in retained transformed appearance")
Gen1.finish(battle)
print("Move triggers: repeated Surf, attacker side, hit routing, Transform timing and switch reset passed")
