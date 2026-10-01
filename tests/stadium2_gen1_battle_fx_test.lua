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
-- environmentStyle/betaArenaEnabled: the scene's environment selection
-- (main's battle environments) calls them unconditionally.
local importer={environmentStyle=function() return "classic" end,
  betaArenaEnabled=function() return false end,
  modelsEnabled=function() return true end}
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
-- The host assigns pendingHit only after AnimPlayer:start, so both rows
-- start with it nil; the move's own row (moveAnimRow, just dequeued) tells
-- them apart.
battle.pendingHit=nil
battle.queue={}
battle.moveAnimRow={anim="ABSORB",attackerIsPlayer=true}
triggers=#adapterTrigger
local signalCount=#signals
battle.animName,battle.animAttackerIsPlayer,battle.animPlaying="ABSORB",true,true
scene:syncPresentationState()
ok(#adapterTrigger==triggers+1 and adapterTrigger[#adapterTrigger][1]==71 and #signals==signalCount,
  "the move Absorb's own row plays Absorb's FX, not Leech Seed's, before pendingHit is set")
battle.animPlaying=false;scene:syncPresentationState()
battle.animName,battle.animAttackerIsPlayer,battle.animPlaying="ABSORB",true,true
scene:syncPresentationState()
ok(signals[#signals].id==0x103 and #adapterTrigger==triggers+1,
  "a later Leech Seed ABSORB row from the same side is the residual")
battle.animPlaying=false;scene:syncPresentationState()
battle.moveAnimRow=nil

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

-- Hosts with the AnimPlayer:start hook present each start through it and
-- the edge detector stands down; the hooked start must still play FX.
local before=#adapterTrigger
scene.moveStartHooked=true
battle.animName,battle.animAttackerIsPlayer,battle.animPlaying="TACKLE",false,true
scene:syncPresentationState()
ok(#adapterTrigger==before,"the edge detector stands down once the start hook is active")
scene:presentAnimStart("TACKLE",false)
ok(#adapterTrigger==before+1 and adapterTrigger[#adapterTrigger][1]==33
    and adapterTrigger[#adapterTrigger][2]=="enemy",
  "a hooked move start triggers battle FX for the attacking side")
battle.animPlaying=false;scene:syncPresentationState()

-- the trainer AI's switch line (_AIBattleWithdrawText) is the foe's recall,
-- with the outgoing mon's status kept at the switch
do
  local S=Gen1.Scene
  local recalled
  local fake=setmetatable({stadiumCameraRecall=function(_,side,condition) recalled={side,condition} end,
    stadiumCameraSelfHit=function() end,stadiumCameraTurnCheck=function() end},{__index=S})
  local battle={trainer={name="BUG CATCHER"},
    romText=function(_,label,fmt,...) return string.format(fmt,...) end}
  fake.stadiumWithdrawn={asleep=true,frozen=false}
  S.stadiumCameraTurnText(fake,battle,{text="BUG CATCHER with-\ndrew WEEDLE!"})
  ok(recalled and recalled[1]=="enemy" and recalled[2].asleep==true,"the AI's withdraw line recalls the foe with its own status")
  recalled=nil
  S.stadiumCameraTurnText(fake,battle,{text="BUG CATCHER sent\nout KAKUNA!"})
  ok(recalled==nil,"other trainer lines do not")
end

-- Red's stat lines and Rage's line -> Stadium's 0x41 / 0x42 entries
do
  local S=Gen1.Scene
  local got={}
  local fake=setmetatable({stadiumCameraEntry=function(_,id,side) got[#got+1]={"cam",id,side} end,
    battleFx={signalEffect=function(_,id,side) got[#got+1]={"fx",id,side} end},
    stadiumCameraSelfHit=function() end,stadiumCameraTurnCheck=function() end},{__index=S})
  local b={player={name="MANKEY"},enemy={name="ODDISH"},
    romText=function(_,label,fmt,...) return string.format(fmt,...) end}
  package.loaded["src.core.Strings"]=setmetatable({},{__call=function(_,fmt,...) return string.format(fmt,...) end})
  package.loaded["src.battle.EffectRegistry"]={displayName=function(x) return x==b.enemy and "Enemy "..x.name or x.name end}
  fake.stadiumPresentedMove={side="player",moveId=96}
  S.stadiumCameraTurnText(fake,b,{text="MANKEY's\nATTACK rose!"})
  ok(#got==2 and got[1][2]==0xFC and got[1][3]=="player" and got[2][1]=="fx" and got[2][2]==0xFC,
    "Meditate's ATTACK rose -> 0xFC on the user")
  got={}
  S.stadiumCameraTurnText(fake,b,{text="Enemy ODDISH's\nATTACK\ngreatly rose!"})
  ok(#got==0,"a raised foe stat signals nothing")
  fake.stadiumPresentedMove={side="enemy",moveId=45}
  S.stadiumCameraTurnText(fake,b,{text="MANKEY's\nATTACK fell!"})
  ok(#got==2 and got[1][2]==0xFD and got[1][3]=="player","Growl's ATTACK fell -> 0xFD on the target")
  got={}
  fake.stadiumPresentedMove={side="player",moveId=99}
  S.stadiumCameraTurnText(fake,b,{text="MANKEY's\nRAGE is building!"})
  ok(#got==2 and got[1][2]==0xFC and got[1][3]=="player","Rage building -> 0xFC on the raging mon")
  got={}
  S.stadiumCameraTurnText(fake,b,{text="MANKEY's\nattack missed!"})
  ok(#got==0,"other lines do not match")
  package.loaded["src.core.Strings"]=nil;package.loaded["src.battle.EffectRegistry"]=nil
end

-- USER-REQUESTED EXTENSION: "used <MOVE>!" waits for A/B before "It doesn't
-- affect ..." (the used line is an auto row queued earlier in the action)
do
  local S=Gen1.Scene
  local romText=function(_,label,fmt,...) return string.format(fmt,...) end
  local used={text="PIKACHU used\nTHUNDERBOLT!",auto=true,autoDelay=0}
  local b={romText=romText,queue={used,{wait=30},{text="It doesn't affect\nEnemy GEODUDE!"}},nextInsert=3}
  S.noEffectPrompt(b,"It doesn't affect\nEnemy GEODUDE!")
  ok(used.auto==nil,"the used line becomes an A/B prompt before the no-effect line")
  local other={text="PIKACHU used\nTHUNDERBOLT!",auto=true}
  local b2={romText=romText,queue={other,{text="Enemy GEODUDE's\nATTACK fell!"}},nextInsert=2}
  S.noEffectPrompt(b2,"Enemy GEODUDE's\nATTACK fell!")
  ok(other.auto==true,"other lines leave the used line automatic")
end

-- A battler's shadow follows its model's opacity: the send-out (0x122, P311
-- mode 5) keeps the model at opacity 0 until age 97, so no shadow until then.
do
  local S=Gen1.Scene
  local colors={player={opacity=0}}
  local fake=setmetatable({battleFx={modelColors=function() return colors end}},{__index=S})
  ok(S.battlerOpacity(fake,"player",{})<S.SHADOW_MIN_OPACITY,"a model still inside the ball casts no shadow")
  colors.player.opacity=255
  ok(S.battlerOpacity(fake,"player",{})>=S.SHADOW_MIN_OPACITY,"once it is out, it does")
  ok(S.battlerOpacity(fake,"player",{modelAlphaByte=0x40})<S.SHADOW_MIN_OPACITY,"a faded model (materialAlpha) casts none")
  ok(S.battlerOpacity(setmetatable({},{__index=S}),"enemy",{})==1,"no effects: fully visible")
end

-- USER-REQUESTED EXTENSION: a missed / no-effect move still shows its
-- attempt: the attacker's clip, the camera's attack and the move bank with
-- the missed result (1, so the effect is cut at the hit frame)
do
  local S=Gen1.Scene
  local attacked,camera,played
  local fake=setmetatable({actors={player={attack=function(_,id) attacked=id end},enemy={}},
    stadiumCameraAttack=function(_,side,id) camera={side,id} end,
    battleFx={playMoveAndImpact=function(_,id,side,_,result) played={id,side,result} end}},{__index=S})
  ok(S.stadiumPresentAttempt(fake,"player",101) and attacked==101,"the attacker plays its attack clip")
  ok(camera and camera[1]=="player" and camera[2]==101,"the camera films the attempt")
  ok(played and played[1]==101 and played[3]==1,"the move bank plays with the missed result")
  -- Red: the cancelled row's placeholder is armed only by a miss / no-effect line
  local romText=function(_,label,fmt,...) return string.format(fmt,...) end
  local placeholder={fn=function() end,stadiumAttempt={anim="NIGHT_SHADE",attackerIsPlayer=true}}
  local b={romText=romText,stadiumAttemptRow=placeholder,data={moves={NIGHT_SHADE={index=101}}}}
  local before=placeholder.fn
  S.armAttempt(b,"Enemy UNOWN's\nATTACK fell!")
  ok(placeholder.fn==before and b.stadiumAttemptRow==placeholder,"other lines leave the placeholder empty")
  S.armAttempt(b,"It doesn't affect\nEnemy UNOWN!")
  ok(placeholder.fn~=before and b.stadiumAttemptRow==nil,"a no-effect line arms the attempt")
  local p2={fn=before,stadiumAttempt={anim="NIGHT_SHADE",attackerIsPlayer=true}}
  local b2={romText=romText,stadiumAttemptRow=p2,data=b.data}
  S.armAttempt(b2,"GENGAR's\nattack missed!")
  ok(p2.fn~=before,"a miss line arms it too")
end

print(("%d checks passed (Stadium 2 Gen 1 battle FX integration)"):format(checks))
