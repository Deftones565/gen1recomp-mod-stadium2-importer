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
-- LITE: small groups are kept whole; big same-shape groups are thinned by a
-- stable per-id choice.
local burst={frame=1,particles={}}
for i=1,40 do burst.particles[i]={id=i,effectId=1,shapeId=5,position={0,0,0},event={mode=0},material={}} end
burst.particles[41]={id=41,effectId=1,shapeId=9,position={0,0,0},event={mode=0},material={}}
local function processed(opts)
  local seen={}
  opts.contextForParticle=function(p) seen[#seen+1]=p.shapeId return {} end
  Packets.build(burst,opts)
  return seen
end
local full,lite,lite2=processed({}),processed({liteParticles=true}),processed({liteParticles=true})
ok(#full==41,"every particle is processed when ON")
ok(#lite<30 and #lite>10,"LITE draws about half of a big burst")
ok(#lite==#lite2,"LITE picks the same particles every frame")
local single=false
for _,shape in ipairs(lite) do if shape==9 then single=true end end
ok(single,"LITE always keeps a lone particle")
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
-- EXTRA EFFECTS off also stops torch/lamp shadows, in every instance.
local TorchShadows=require("mods.STADIUM2_IMPORTER.lib.battle_torch_shadows")
local lamps=TorchShadows.new()
TorchShadows.setEnabled(false)
local g={getDimensions=function() return 1,1 end}
ok(lamps.update(g,{},{},{},{},{})==nil,"torch shadows are not rendered when off")
local sent={}
lamps.send({send=function(_,k,v) sent[k]=v end})
ok(sent.torchShadows==0,"scene shaders are told torch shadows are off")
TorchShadows.setEnabled(true)
ok(TorchShadows.enabled()==true,"torch shadows switch back on")
print(("%d checks passed (Stadium 2 FX particles option)"):format(checks))
