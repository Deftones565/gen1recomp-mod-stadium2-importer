package.path="./?.lua;./?/init.lua;"..package.path
-- PARTICLES option (non-native extension): OFF drops common particle packets
-- from both the scene and screen builds; ON leaves them untouched.
local Packets=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_draw_packets")
local Player=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_player")
local checks=0
local function ok(v,m) checks=checks+1 if not v then error("FAIL "..m,0) end end
local snapshot={frame=1,particles={{effectId=1,shapeId=0,position={0,0,0},
  event={mode=0},material={}}}}
local off=Packets.build(snapshot,{skipParticles=true})
ok(#off.packets==0 and #off.screenPackets==0,"skipParticles builds no particle packets")
local on=Packets.build(snapshot,{})
ok(#on.packets+#on.screenPackets+#on.diagnostics>0,"particles are still processed when shown")
local shown=true
local player=setmetatable({particlesEnabled=function() return shown end},{__index=Player})
ok(player:_particlesShown()==true,"provider ON shows particles")
shown=false
ok(player:_particlesShown()==false,"provider OFF hides particles")
player.particlesEnabled=nil
ok(player:_particlesShown()==true,"particles default to shown")
-- POKE BALL option: OFF skips only the send-out entry (0x122).
local Adapter=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_battle_adapter")
local Sequence=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_sequence")
local played,ball={},true
local adapter=assert(Adapter.new({betaBattleFxEnabled=function() return true end,
  battleFxSendOutEnabled=function() return ball end,
  newBattleFxPlayer=function() return {playEntry=function(_,id) played[#played+1]=id return {id=id} end} end}))
adapter:signalEffect(Sequence.SEND_OUT_ENTRY,"player")
ok(played[1]==Sequence.SEND_OUT_ENTRY,"POKE BALL ON plays the send-out")
ball=false
adapter:signalEffect(Sequence.SEND_OUT_ENTRY,"player")
ok(#played==1,"POKE BALL OFF skips the send-out")
adapter:signalEffect(Sequence.RECALL_ENTRY,"player")
ok(played[2]==Sequence.RECALL_ENTRY,"POKE BALL OFF leaves other entries alone")
print(("%d checks passed (Stadium 2 FX particles option)"):format(checks))
