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
local signals={}
local charges={}
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
      signalEffect=function(_,id,owner) signals[#signals+1]={id=id,owner=owner} end,
      playCharge=function(_,moveId,side) charges[#charges+1]={moveId=moveId,side=side} return true end,
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

-- Red's residual rows -> Stadium entries on the suffering side.
battle.data.moves.ABSORB={index=71}
battle.player.mon.status="PSN"
battle.animName,battle.animAttackerIsPlayer,battle.animPlaying="BURN_PSN_ANIM",true,true
scene:syncPresentationState()
ok(signals[#signals].id==0x101 and signals[#signals].owner=="player","BURN_PSN_ANIM on a poisoned mon -> 0x101")
battle.animPlaying=false;scene:syncPresentationState()
battle.enemy.mon.status="BRN"
battle.animName,battle.animAttackerIsPlayer,battle.animPlaying="BURN_PSN_ANIM",false,true
scene:syncPresentationState()
ok(signals[#signals].id==0x102 and signals[#signals].owner=="enemy","BURN_PSN_ANIM on a burned mon -> 0x102")
battle.animPlaying=false;scene:syncPresentationState()
local triggers=#adapterTrigger
battle.pendingHit=nil
battle.animName,battle.animAttackerIsPlayer,battle.animPlaying="ABSORB",true,true
scene:syncPresentationState()
ok(signals[#signals].id==0x103 and signals[#signals].owner=="enemy" and #adapterTrigger==triggers,
  "Leech Seed's ABSORB row -> 0x103 on the seeded side, no Absorb move FX")
battle.animPlaying=false;scene:syncPresentationState()
battle.pendingHit={animType=4}
battle.animName,battle.animAttackerIsPlayer,battle.animPlaying="ABSORB",true,true
scene:syncPresentationState()
ok(#adapterTrigger==triggers+1 and adapterTrigger[#adapterTrigger][1]==71,
  "a real Absorb (with hit data) still plays its move FX")
battle.animPlaying=false;scene:syncPresentationState()

-- Charge rows: Fly's TELEPORT row is its charge, not Teleport's move FX.
battle.data.moves.FLY={index=19}
battle.data.moves.TELEPORT={index=100}
battle.data.moves.SOLARBEAM={index=76}
local charged={}
scene.actors.player.charge=function(_,entry) charged[#charged+1]=entry return true end
battle.player.charging={id="FLY"}
local before=#adapterTrigger
battle.animName,battle.animAttackerIsPlayer,battle.animPlaying="TELEPORT",true,true
scene:syncPresentationState()
ok(#adapterTrigger==before and charges[#charges].moveId==19 and charged[#charged]==256,
  "Fly's charge row plays the charge clip and variant, not Teleport's FX")
battle.animPlaying=false;scene:syncPresentationState()
battle.player.charging={id="SOLARBEAM"}
battle.animName,battle.animPlaying="XSTATITEM_ANIM",true
scene:syncPresentationState()
ok(charges[#charges].moveId==76 and charged[#charged]==257,"SolarBeam's charge row -> row 257")
battle.animPlaying=false;scene:syncPresentationState()
battle.player.charging=nil
local count=#charges
battle.animName,battle.animPlaying="XSTATITEM_ANIM",true
scene:syncPresentationState()
ok(#charges==count,"an X item's XSTATITEM_ANIM (no charging move) is not a charge turn")
battle.animPlaying=false;scene:syncPresentationState()

-- RetreatMon's shrink (host shrinkOut) is the recall cue: 0x126 once.
count=#signals
battle.shrinkOut={battler=battle.player,frame=0}
scene:syncPresentationState()
ok(#signals==count+1 and signals[#signals].id==0x126 and signals[#signals].owner=="player",
  "the player's retreat signals recall 0x126")
battle.shrinkOut.frame=3;scene:syncPresentationState()
ok(#signals==count+1,"a running retreat does not signal again")
battle.shrinkOut=nil;scene:syncPresentationState()

print(("%d checks passed (Stadium 2 Gen 1 battle FX integration)"):format(checks))
