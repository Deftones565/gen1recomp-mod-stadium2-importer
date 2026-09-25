package.path="./?.lua;./?/init.lua;"..package.path

-- Keep this test presentation-only.  The adapter seam is stubbed so the test
-- proves Gen 2's event/tick contract without requiring a GPU or ROM cache.
local calls={construct=0,trigger={},updates={},finishes=0}
local adapterName="mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_battle_adapter"
package.preload[adapterName]=function()
  return {
    new=function(importer,options)
      calls.construct=calls.construct+1
      assert(type(importer.betaBattleFxEnabled)=="function",
        "adapter receives the importer boundary")
      assert(type(options.warn)=="function","adapter receives a warning sink")
      return {
        trigger=function(_,moveId,side,alternate)
          calls.trigger[#calls.trigger+1]={moveId=moveId,side=side,
            alternate=alternate}
        end,
        update=function(_,dt) calls.updates[#calls.updates+1]=dt end,
        finish=function() calls.finishes=calls.finishes+1 end,
      }
    end,
  }
end

local Importer=require("mods.STADIUM2_IMPORTER.lib.importer")
local oldEnabled=Importer.betaBattleFxEnabled
Importer.betaBattleFxEnabled=function() return true end
local Gen2=require("mods.STADIUM2_IMPORTER.lib.gen2_battle")

local checks=0
local function ok(value,message)
  checks=checks+1
  if not value then error("FAIL "..message,0) end
end

local battle={volatile=function() return {} end,
  player={hp=20,species="PIKACHU"},enemy={hp=20,species="RATTATA"},
  data={moves={[42]={index=42,name="TEST MOVE"},
    [43]={index=43,name="MISSED MOVE"}}}}
local scene=Gen2.Scene.new(battle)
ok(calls.construct==1 and scene.battleFx~=nil,
  "enabled beta option constructs one Gen 2 battle FX adapter")
scene.readyFrame=true
scene.screen={game={data=battle.data},showPlayerTrainer=false,
  showEnemyTrainer=false}

local event={kind="move",side="enemy",move=42}
scene:handleEvent(event)
scene:handleEvent(event)
ok(#calls.trigger==1,"the presented move event triggers battle FX exactly once")
ok(calls.trigger[1].moveId==42 and calls.trigger[1].side=="enemy",
  "battle FX receives the presented move ID and source side")

scene:handleEvent({kind="move",side="player",move=43,missed=true})
ok(#calls.trigger==1,"a presented missed move does not trigger battle FX")

scene:update(1/30)
ok(#calls.updates==1 and math.abs(calls.updates[1]-1/30)<1e-9,
  "battle FX advances with the presentation delta")
ok(calls.finishes==0,"event waits for the host to start its animation")
local done=false
scene.screen.anim={done=function() return done end}
scene:syncBattleFxAnimation(true)
ok(calls.finishes==0,"running host animation holds its lifecycle")
done=true
scene:syncBattleFxAnimation();scene:syncBattleFxAnimation()
ok(calls.finishes==1,"retained done runner signals completion exactly once")
scene:handleEvent({kind="move",side="player",move=42})
scene.screen.anim={};scene:syncBattleFxAnimation(true)
scene.screen.anim=nil;scene:syncBattleFxAnimation()
ok(calls.finishes==2,"skipped/removed runner finishes the effect")
scene:handleEvent({kind="move",side="player",move=42})
scene:syncBattleFxAnimation(true)
ok(calls.finishes==3,"move without a host animation finishes after queue dispatch")

-- Weather entries (841324EC -> 84119630/84118DD4), matched against Gold's
-- own Strings() tables.
local signals={}
scene.battleFx.signalEffect=function(_,id,owner) signals[#signals+1]={id=id,owner=owner} end
local Effects=require("src.battle.gen2.Effects")
local Strings=require("src.core.Strings")
scene:handleEvent({kind="message",text=Strings(Effects.WEATHER_TURN_TEXT.rain)})
scene:handleEvent({kind="message",text=Strings(Effects.WEATHER_TURN_TEXT.sandstorm)})
scene:handleEvent({kind="weather",weather=nil,text=Strings(Effects.WEATHER_END_TEXT.sun)})
scene:handleEvent({kind="damage",side="enemy",amount=3,hp=10,anim="ANIM_IN_SANDSTORM"})
scene:handleEvent({kind="weather",weather="rain",text=Strings(Effects.WEATHER_START_TEXT.rain)})
scene:handleEvent({kind="message",text="Something else."})
ok(#signals==4,"only ongoing, ended and sandstorm-hit weather events signal FX")
ok(signals[1].id==0x107 and signals[1].owner=="player","rain continues -> entry 0x107")
ok(signals[2].id==0x113,"sandstorm rages -> entry 0x113")
ok(signals[3].id==0x121,"sunlight faded -> entry 0x121")
ok(signals[4].id==0x125 and signals[4].owner=="enemy","sandstorm hit -> entry 0x125 on that side")

-- Resting-pose condition follows presented status events, not live status.
battle.player.status="sleep"
ok(not scene:restCondition("player").asleep,"live status alone does not start the sleep pose")
scene:handleEvent({kind="status",side="player",status="sleep",text="fell asleep"})
ok(scene:restCondition("player").asleep,"a presented sleep status starts the sleep pose")
scene:handleEvent({kind="status",side="player",status=nil,text="woke up"})
ok(not scene:restCondition("player").asleep,"waking up ends it")
scene:handleEvent({kind="status",side="enemy",status="freeze",text="frozen"})
ok(scene:restCondition("enemy").frozen,"a presented freeze holds the frozen pose")

-- Fly/Dig after the departing animation, told apart by the charge move.
local vol={}
scene.actors.player.mon=scene.actors.player.mon or battle.player
battle.volatile=function(_,mon) return mon==scene.actors.player.mon and vol or {} end
vol.vanished,vol.chargeMove=true,"FLY"
ok(scene:restCondition("player").flying,"Fly's charge move is the flying pose")
vol.chargeMove="DIG"
ok(scene:restCondition("player").underground,"Dig's charge move is the underground pose")
scene.vanish.player={active=true,mode="depart"}
ok(not scene:restCondition("player").underground,"not while the departing animation runs")
scene.vanish.player={active=false}
battle.volatile=function() return {} end

-- This file does not release the adapter: Presentation owns shared scene
-- teardown, which is deliberately tested by the common scene integration.
Importer.betaBattleFxEnabled=oldEnabled
print(("%d checks passed (Gen 2 battle FX presentation integration)"):format(checks))
