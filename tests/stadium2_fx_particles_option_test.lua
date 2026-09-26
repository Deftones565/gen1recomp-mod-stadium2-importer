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
print(("%d checks passed (Stadium 2 FX particles option)"):format(checks))
