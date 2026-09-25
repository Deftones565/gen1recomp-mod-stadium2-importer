package.path="./?.lua;./?/init.lua;"..package.path
local Player=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_player")
local n=0;local function ok(v,m)n=n+1;if not v then error("FAIL "..m,0)end end
local snapshots={effects={{id=1,moveId=7}},particles={{id=1,effectId=1,age=2,scale={2,2,2},shapeId=47,event={programId=259},material={shapeId=47,primaryColor={255,128,0,255}},attachment={flags=0x180}}}}
local runtime={triggerCalls=0,updateCalls=0,released=false,trigger=function(self,c)self.triggerCalls=self.triggerCalls+1;return 1 end,update=function(self,dt)self.updateCalls=self.updateCalls+1;return 2 end,snapshot=function()return snapshots end,release=function(self)self.released=true end}
local calls={load=0,draw=0,release=0};local renderer={setHandlerRuntime=function(self,c)self.frame=c.callbackFrame end,drawScene=function(self,pass,matrix,options)calls.draw=calls.draw+1;ok(matrix[1]==2 and matrix[4]==10,"packet matrix reaches renderer");if pass=="opaque"then ok(math.abs(options.tint[2]-128/255)<1e-9,"RGBA byte tint normalized at renderer boundary")end;return true end,release=function()calls.release=calls.release+1 end}
local player=Player.new({runtime=runtime,loadRenderer=function(move,shape)calls.load=calls.load+1;ok(move==7 and shape==47,"loader receives move and shape");return renderer end,resolvePlacement=function()return{resolved=true,position={10,20,30},scale=1}end})
ok(player:trigger({moveId=7})==1 and runtime.triggerCalls==1,"trigger delegated")
player:update(1/30);ok(runtime.updateCalls==1,"update delegated")
local result=assert(player:draw({camera={vp={}},environment={}}));ok(result.drawn==1 and calls.draw==2,"opaque and additive render once")
local previousRuntime=renderer.setHandlerRuntime
snapshots.particles[1].frame=17 -- authored hold must not freeze texture animation
renderer.setHandlerRuntime=function(self,c)
  ok(c.materialFrame==2 and c.callbackFrame==2,"cached FX material clock advances with its packet")
  previousRuntime(self,c)
end
snapshots.particles[1].material.nativeAlpha=64
local originalDraw=renderer.drawScene
renderer.drawScene=function(self,pass,matrix,options)
  ok(options.tint[4]==64/255,"persistent native alpha reaches the renderer exactly once")
  return originalDraw(self,pass,matrix,options)
end
ok(calls.load==1 and renderer.frame==2,"renderer cached and callback frame set")
player:draw({});ok(calls.load==1,"shape renderer cache reused")
renderer.drawScene=originalDraw
ok(#player.diagnostics==0,"successful repeated draws do not add diagnostics")
ok(player:release() and runtime.released and calls.release==1,"release owns runtime and renderer")
local invalidRendererPlayer=Player.new({runtime=runtime,
  loadRenderer=function()return{}end,
  resolvePlacement=function()return{resolved=true,position={0,0,0},scale=1}end})
local rejected=invalidRendererPlayer:draw({})
ok(rejected.drawn==0 and rejected.diagnostics[1].code=="draw-renderer",
  "common packet without drawScene is rejected, not counted as rendered")

-- Native-object and lifecycle packet sets stay renderer-neutral and are
-- sourced from the same persistent runtime snapshot as common particles.
local packetSnapshot={frame=8,effects={{id=3,moveId=11}},particles={},
  nativeObjects={capacity=64,tickCount=8,slots={{index=2,generation=5,active=true,
    mode=5,countdown=0,reload=0,age=1,state=1,commandPointer=0x84178894,
    event={effectId=3,programId=328,address=0x841788B8},object={opaque=true},
    resolution={status="opaque"},visualObjects={},rawFields={},drawPackets={},diagnostics={}}}},
  lifecycles={frame=8,instances={{id=4,familyId=7,active=true,counter=2,frame=2,
    context={effectId=3,programId=259,address=0x84156BD4,sourceSide="enemy"}}},
    packets={{instanceId=4,familyId=7,command=0xDA380003,pointer=0x841A4D08,
      drawHelper=0x8415ADE0,requiresDrawHelper=true,counter=2,frame=2}},
    diagnostics={}},diagnostics={{code="runtime-warning",severity="warning",
      effectId=3,kind="runtime",message="retained runtime diagnostic"}}}
local runtime2={snapshot=function()return packetSnapshot end,release=function(self)self.released=true end}
local proofCalls={placement=0,geometry=0,model=0,nativeDraw=0,lifecycleDraw=0}
local provenRenderer={drawScene=function(_,pass,matrix)
  ok(type(matrix)=="table" and #matrix==16 and (pass=="opaque" or pass=="additive"),
    "proven native/lifecycle packet reaches renderer")
  proofCalls.nativeDraw=proofCalls.nativeDraw+1
  return true
end}
local player2=Player.new({runtime=runtime2,
  loadRenderer=function(move,shape)
    ok(move==11 and (shape==23 or shape==24),"proven packet loader receives move and shape")
    return provenRenderer
  end,
  resolveNativePlacement=function(slot,context)
    proofCalls.placement=proofCalls.placement+1
    ok(slot.index==2 and context.sceneToken=="scene","native placement receives scene context")
    return {resolved=true,position={1,2,3}}
  end,
  resolveNativeGeometry=function(slot)
    proofCalls.geometry=proofCalls.geometry+1
    return {resolved=true,resource=0x1234,shapeId=23}
  end,
  resolveLifecycleModel=function(instance,evidence,context)
    proofCalls.model=proofCalls.model+1
    ok(instance.id==4 and evidence.familyId==7 and context.sceneToken=="scene"
      and context.sourceSide=="enemy","lifecycle model resolver receives merged context")
    return {proven=true,modelId="family-7-model",shapeId=24,
      matrix={1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1}}
  end})
local sets=player2:packets({sceneToken="scene"})
ok(#sets.nativeObjects.packets==1 and sets.nativeObjects.packets[1].geometry.resource==0x1234
  and #sets.lifecycles.packets==1 and sets.lifecycles.packets[1].modelResolution.modelId=="family-7-model",
  "player returns proven native-object and lifecycle packet sets")
ok(#sets.nativeObjectPackets==1 and #sets.lifecyclePackets==1
  and #sets.lifecycleEvidence==1 and proofCalls.placement==1
  and proofCalls.geometry==1 and proofCalls.model==1,
  "player exposes packet aliases and lifecycle command evidence")
ok(#sets.diagnostics==1 and sets.diagnostics[1].code=="runtime-warning",
  "player merges runtime diagnostics into the common packet result")
local provenDraw=assert(player2:draw({sceneToken="scene",camera={vp={}},environment={}}))
ok(provenDraw.drawn==2 and proofCalls.nativeDraw==4,
  "draw renders proven native-object and lifecycle packets")

local noTransform=Player.new({runtime=runtime2,
  loadRenderer=function() return provenRenderer end,
  resolveNativePlacement=function() return {resolved=true} end,
  resolveNativeGeometry=function() return {resolved=true,shapeId=23} end,
  resolveLifecycleModel=function() return {proven=true,shapeId=24} end})
local noTransformDraw=assert(noTransform:draw({sceneToken="scene"}))
ok(noTransformDraw.drawn==0 and #noTransform.diagnostics>0,
  "proven geometry without explicit placement remains diagnostic-only")
local noMethod=Player.new({runtime=runtime2,
  loadRenderer=function() return {} end,
  resolveNativePlacement=function() return {resolved=true,position={1,2,3}} end,
  resolveNativeGeometry=function() return {resolved=true,shapeId=23} end})
local noMethodDraw=assert(noMethod:draw({sceneToken="scene"}))
ok(noMethodDraw.drawn==0 and #noMethod.diagnostics>0,
  "renderer without drawScene is rejected")
noTransform:release();noMethod:release()

local unresolvedPlayer=Player.new({runtime=runtime2})
local unresolvedDraw=assert(unresolvedPlayer:draw({}))
ok(unresolvedDraw.drawn==0 and #unresolvedDraw.nativeObjects.packets==1
  and unresolvedDraw.nativeObjects.packets[1].geometry==nil
  and #unresolvedDraw.lifecycles.packets==0,
  "unresolved native/lifecycle records are never guessed-rendered")
local firstDiagnosticCount=#unresolvedPlayer.diagnostics
assert(unresolvedPlayer:draw({}))
ok(firstDiagnosticCount>0 and #unresolvedPlayer.diagnostics==firstDiagnosticCount,
  "native/lifecycle diagnostics are deduplicated across draws")
ok(unresolvedPlayer:release() and runtime2.released==true,"packet player releases runtime")
local overlayState={effects={{id=1,moveId=5}},particles={},nativeObjects={slots={},
  modelColors={enemy={color={255,0,0,128},opacity=64}},
  screenInstances={{active=true,effectId=1,shapeId=90,age=4,rgba={1,2,3,128}}}}}
local overlayDraws=0
local overlay=Player.new({runtime={snapshot=function()return overlayState end},
  loadRenderer=function(move,shape)
    ok(move==5 and shape==90,"screen rendering requests actual ROM export90")
    return {drawScene=function(_,pass,matrix,options)
      overlayDraws=overlayDraws+1
      ok(options.screenSpace and matrix[4]==160 and matrix[8]==120,
        "screen draw uses native origin and bypasses world depth")
      ok(options.battleFxColors.secondaryColor[4]==128
        and options.viewProjection[1]==1/160,"screen color and orthographic projection reach renderer")
      return true
    end}
  end})
local scene={}
overlay:draw(scene)
ok(overlayDraws==0 and scene.nativeModelColors.enemy.opacity==64,
  "world pass publishes model writes and defers screen drawing")
ok(scene.nativeOverlayDraw()==1 and overlayDraws==2,"overlay stage submits both screen passes")
overlayState.nativeObjects.screenInstances[1].active=false
ok(scene.nativeOverlayDraw()==0 and overlayDraws==2,"expired screens no longer render")
print(("%d checks passed (Stadium 2 battle FX player)"):format(n))
