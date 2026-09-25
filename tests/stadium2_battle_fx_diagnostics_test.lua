package.path="./?.lua;./?/init.lua;"..package.path
local prefix="mods.STADIUM2_IMPORTER.lib."
local Native=require(prefix.."stadium2_battle_fx_native")
local Runtime=require(prefix.."stadium2_battle_fx_runtime")
local Player=require(prefix.."stadium2_battle_fx_player")
local Lifecycle=require(prefix.."stadium2_battle_fx_lifecycle")
local Packets=require(prefix.."stadium2_battle_fx_draw_packets")
local Adapter=require(prefix.."stadium2_battle_fx_battle_adapter")
local Motion=require(prefix.."stadium2_battle_fx_motion")
local function has(rows,code)
  for _,d in ipairs(rows)do if d.code==code then return d end end
end
local p={id=1,records={{opcode=16,address=0x84100010},{opcode=12,
  address=0x84100020,argument=0x84109999},{opcode=0}}}
local execution=Native.execute(p,{condition=0})
assert(has(execution.diagnostics,"unsupported-native-condition"))
assert(has(execution.diagnostics,"unsupported-native-program-call"))
local resolved=Native.execute(p,{conditionForMove=function()return 1 end})
assert(resolved.condition==1 and not has(resolved.diagnostics,"unsupported-native-condition"))
local failed=Native.execute(p,{conditionForMove=function()error("missing battle state")end})
assert(has(failed.diagnostics,"invalid-native-condition"))
local unknown=Native.execute({records={{opcode=99},{opcode=0}}})
assert(has(unknown.diagnostics,"unsupported-native-opcode"))
local runtime=Runtime.new({catalog={programs={[1]=p},moves={[1]={
  primaryDispatch={{kind="program",programId=1}},alternateDispatch={}}}}})
assert(runtime:trigger({moveId=1}))
local d=assert(has(runtime:snapshot().diagnostics,"unsupported-native-condition"))
assert(d.effectId==1 and d.programId==1 and d.address==0x84100010)
local materialRuntime=Runtime.new({material={},catalog={programs={[1]={id=1,
  records={{opcode=4,emitter={descriptorKind="particle",particleCount=1,
    material={shapeId=47}}},{opcode=0}}}},moves={[1]={
  primaryDispatch={{kind="program",programId=1}},alternateDispatch={}}}}})
assert(materialRuntime:trigger({moveId=1}))
materialRuntime:step(1)
assert(has(materialRuntime:snapshot().diagnostics,"material-initialization"))
assert(has(materialRuntime:snapshot().diagnostics,"material-evaluation"))
local ribbon=Lifecycle.new();assert(ribbon:spawn(23,{effectId=1}))
local hidden=Motion.init({event={flags=2},material={nativeEndAge=16}})
assert(not has(hidden.diagnostics,"unsupported-native-hide-transition"))
for i=1,16 do hidden=Motion.step(hidden,1) end
assert(hidden.nativeHidden and hidden.alive)
assert(#Packets.build({particles={{nativeHidden=true,event={mode=7}}}}).screenPackets==0,
  'hidden particles never create draw packets')
local expiry=Motion.init({event={flags=0},material={nativeEndAge=16}})
assert(not has(expiry.diagnostics,"unsupported-native-hide-transition"))
assert(has(Motion.init({event={mode=1,flags=0}}).diagnostics,
  "unsupported-native-constructor-scale"))
assert(not has(Motion.init({event={mode=1,flags=0x80}}).diagnostics,
  "unsupported-native-constructor-scale"))
assert(has(ribbon:snapshot().diagnostics,"approximate-ribbon-anchor"))
assert(has(ribbon:snapshot().diagnostics,"approximate-ribbon-scale"))
local particle={id=1,effectId=1,shapeId=47,event={mode=7,programId=1,
  attachment={flags=0x20},context={sourceSide="player"}},
  material={shapeId=47},position={0,0,0}}
local scene={world={actorSlots={player={0,0,0},enemy={10,0,0}}}}
local packets=Packets.build({particles={particle}},{
  contextForParticle=function(p)return Adapter.placementContext(p,scene)end})
assert(not has(packets.diagnostics,"approximate-common-model-anchor"))
assert(has(packets.diagnostics,"unresolved-screen-trig"))
assert(not has(packets.diagnostics,"unsupported-common-screen-space"))
particle.event.mode=0
particle.material={shapeId=0,nativeMaterialColors=true}
packets=Packets.build({particles={particle}},{resolvePlacement=function()
  return {resolved=true,position={0,0,0},scale=1}end})
assert(not has(packets.diagnostics,"unsupported-dynamic-anchor"))
assert(#packets.packets==0,'null shape is not drawn')
particle.material={shapeId=47};particle.event.mode=0
local snapshot={effects={{id=1,moveId=1}},particles={particle}}
local fakeRuntime={snapshot=function()return snapshot end}
local draws,warnings=0,0
local player=Player.new({runtime=fakeRuntime,resolvePlacement=function()
  return {resolved=true,position={0,0,0},scale=1}end,
  warn=function()warnings=warnings+1 end,
  loadRenderer=function()return {setHandlerRuntime=function()error("missing handler")end,
    drawScene=function()draws=draws+1;return true end}end})
assert(player:draw(scene).drawn==0 and draws==0)
assert(has(player.diagnostics,"draw-handler-runtime"))
local count=warnings;player:draw(scene);assert(warnings==count,"diagnostics must deduplicate")
snapshot={effects={{id=1,moveId=1}},nativeObjects={screenInstances={{
  active=true,effectId=1,shapeId=90,rgba={0,0,0,255}}}}}
local overlay=Player.new({runtime=fakeRuntime,loadRenderer=function()return{
  drawScene=function()error("unsupported screen draw")end}end})
assert(overlay:drawOverlay({})==0)
assert(has(overlay.diagnostics,"native-screen-renderer"))
overlay:drawOverlay({});assert(#overlay.diagnostics==1)
print("Battle FX diagnostics: branch/callback gaps, ribbon inputs, placement, screen particles, dynamic anchors and renderer failures passed")
