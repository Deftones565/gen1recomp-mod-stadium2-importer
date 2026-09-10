package.path="./?.lua;./?/init.lua;"..package.path

local checks=0
local function ok(value,message)
  checks=checks+1
  if not value then error("FAIL "..message,0) end
end

-- Keep this test independent of the ROM/cache and deliberately provide an
-- importer with no betaBattleFxEnabled method. The Gen 1 scene must delegate
-- construction to the adapter boundary and remain compatible with older
-- importer mocks.
local importer={}
local adapterNew,adapterTrigger,adapterUpdates,finishes=0,{},{},0
local adapter={
  new=function(received,options)
    adapterNew=adapterNew+1
    ok(received==importer,"Gen 1 constructs FX through the adapter boundary")
    return {
      trigger=function(_,moveId,source,alternate)
        adapterTrigger[#adapterTrigger+1]={moveId,source,alternate}
      end,
      update=function(_,dt) adapterUpdates[#adapterUpdates+1]=dt end,
      finish=function() finishes=finishes+1 end,
    }
  end,
}
package.preload["mods.STADIUM2_IMPORTER.lib.importer"] = function() return importer end
package.preload["mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_battle_adapter"] =
  function() return adapter end

local Gen1=require("mods.STADIUM2_IMPORTER.lib.gen1_battle")
local Scene=Gen1.Scene

local function actor()
  return {
    load=function() end,
    update=function() end,
    attack=function() end,
    play=function() end,
    faint=function() end,
  }
end

local battle={
  player={mon={species=25}}, enemy={mon={species=35}},
  data={moves={TACKLE={index=33}}},
  growInScale=function() end, fxHidden=function() return false end,
  fxFaintActive=function() return false end,
  animPlaying=false,
}
local scene=Scene.new(battle)
scene.actors={player=actor(),enemy=actor()}
scene.substituteActors={player=actor(),enemy=actor()}
ok(adapterNew==1,"Gen 1 scene creates one battle FX adapter")

battle.animName="TACKLE"
battle.animAttackerIsPlayer=true
battle.animPlaying=true
scene:syncPresentationState()
ok(#adapterTrigger==1,"move animation rising edge triggers battle FX once")
ok(adapterTrigger[1][1]==33 and adapterTrigger[1][2]=="player"
    and adapterTrigger[1][3]==false,
  "battle FX receives the move ID and attacking side on the primary route")
scene:syncPresentationState()
ok(#adapterTrigger==1,"held move animation does not retrigger battle FX")

scene:update(.025)
ok(#adapterUpdates==1 and adapterUpdates[1]==.025,
  "battle FX advances from the presentation delta")
ok(finishes==0,"active animation keeps lifecycle effects alive")
battle.animPlaying=false
scene:syncPresentationState();scene:syncPresentationState()
ok(finishes==1,"animation falling edge finishes lifecycle effects once")

print(("%d checks passed (Stadium 2 Gen 1 battle FX integration)"):format(checks))
