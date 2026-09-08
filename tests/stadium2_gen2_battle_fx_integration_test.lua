package.path="./?.lua;./?/init.lua;"..package.path

-- Keep this test presentation-only.  The adapter seam is stubbed so the test
-- proves Gen 2's event/tick contract without requiring a GPU or ROM cache.
local calls={construct=0,trigger={},updates={}}
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

-- This file does not release the adapter: Presentation owns shared scene
-- teardown, which is deliberately tested by the common scene integration.
Importer.betaBattleFxEnabled=oldEnabled
print(("%d checks passed (Gen 2 battle FX presentation integration)"):format(checks))
