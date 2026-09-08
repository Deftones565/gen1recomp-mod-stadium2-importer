-- Runtime/packet/renderer coordinator. Battle mechanics remain host-owned.
local Runtime=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_runtime")
local Packets=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_draw_packets")
local NativePackets=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_native_object_packets")
local LifecyclePackets=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_lifecycle_packets")
local Player={};Player.__index=Player
local function copy(v,s)if type(v)~="table"then return v end;s=s or{};if s[v]then return s[v]end;local o={};s[v]=o;for k,x in pairs(v)do o[copy(k,s)]=copy(x,s)end;return o end
local function diagnosticKey(d)
  return table.concat({tostring(d.code),tostring(d.effectId),tostring(d.programId),
    tostring(d.address),tostring(d.instanceId),tostring(d.familyId),
    tostring(d.schedulerIndex),tostring(d.generation),tostring(d.commandPointer),
    tostring(d.message)},"\31")
end
local function mergeDiagnostics(target,items,seen)
  for _,item in ipairs(items or{})do
    local key=diagnosticKey(item)
    if not seen[key]then seen[key]=true;target[#target+1]=copy(item)end
  end
end
function Player.new(options)
  options=type(options)=="table"and options or{};local runtime=options.runtime
  if not runtime then local ro=copy(options.runtimeOptions or{});ro.catalog=options.catalog or ro.catalog;runtime=Runtime.new(ro)end
  return setmetatable({runtime=runtime,loadRenderer=options.loadRenderer,releaseRenderer=options.releaseRenderer,contextForParticle=options.contextForParticle,resolvePlacement=options.resolvePlacement,
    resolveNativePlacement=options.resolveNativePlacement or options.resolveNativeObjectPlacement or options.nativePlacementResolver,
    resolveNativeGeometry=options.resolveNativeGeometry or options.resolveNativeObjectGeometry or options.nativeGeometryResolver,
    resolveLifecycleModel=options.resolveLifecycleModel or options.lifecycleModelResolver,
    warn=options.warn,renderers={},diagnostics={},diagnosticKeys={},released=false},Player)
end
function Player:trigger(context)if self.released then return nil,"battle FX player released"end;return self.runtime:trigger(context)end
function Player:update(dt)if self.released then return nil end;return self.runtime:update(dt)end
function Player:snapshot()return self.runtime:snapshot()end
function Player:packets(sceneContext)
  local snapshot=self.runtime:snapshot()
  local built=Packets.build(snapshot,{context=sceneContext,
    contextForParticle=self.contextForParticle and function(p,s,c)return self.contextForParticle(p,sceneContext,s,c)end or nil,
    resolvePlacement=self.resolvePlacement})
  -- Native-object and lifecycle records remain separate from common particle
  -- packets.  Their builders preserve opaque ROM evidence and only mark data
  -- renderable when an injected resolver explicitly proves it.
  built.nativeObjects=NativePackets.build(snapshot.nativeObjects or {},{
    context=sceneContext,resolvePlacement=self.resolveNativePlacement,
    resolveGeometry=self.resolveNativeGeometry})
  built.lifecycles=LifecyclePackets.build(snapshot,{resolveModel=self.resolveLifecycleModel and function(instance,evidence,context)
    local merged=copy(sceneContext or {})
    for key,value in pairs(context or {})do merged[key]=copy(value)end
    return self.resolveLifecycleModel(instance,evidence,merged)
  end or nil})
  built.nativeObjectPackets=built.nativeObjects.packets
  built.lifecyclePackets=built.lifecycles.packets
  built.lifecycleEvidence=built.lifecycles.evidence
  local diagnosticSeen={}
  for _,item in ipairs(built.diagnostics or {})do diagnosticSeen[diagnosticKey(item)]=true end
  mergeDiagnostics(built.diagnostics,snapshot.diagnostics,diagnosticSeen)
  for _,set in ipairs({built.nativeObjects,built.lifecycles})do
    mergeDiagnostics(built.diagnostics,set.diagnostics,diagnosticSeen)
  end
  return built
end
local function renderOptions(scene,packet,pass)
  local camera=scene and scene.camera or{};local environment=scene and scene.environment or{};local shadow=scene and scene.shadow or{}
  local tint=packet.material and packet.material.primaryColor;local rgba=tint and{tint[1]/255,tint[2]/255,tint[3]/255,tint[4]/255}or{1,1,1,1}
  return{viewProjection=camera.viewProjection or camera.vp,viewMatrix=camera.view,normalMatrix={1,0,0,0,1,0,0,0,1},lightDir=environment.light,ambient=environment.ambient,diffuse=environment.diffuse,tint=rgba,skipHandlers=pass=="additive",flipWinding=true,disableCulling=true,sunMap=shadow.map,sunVP=shadow.sunVP,sunDark=shadow.sunDark,sunBias=shadow.sunBias,sunTexel=shadow.sunTexel}
end
function Player:_renderer(moveId,shapeId)
  local key=tostring(moveId)..":"..tostring(shapeId);if self.renderers[key]then return self.renderers[key].renderer end
  if type(self.loadRenderer)~="function"then return nil,"battle FX renderer loader unavailable"end
  local ok,renderer,owned=pcall(self.loadRenderer,moveId,shapeId);if not ok then return nil,tostring(renderer)end;if not renderer then return nil,tostring(owned or"battle FX shape renderer unavailable")end
  self.renderers[key]={renderer=renderer,owned=owned};return renderer
end
function Player:draw(sceneContext)
  if self.released then return nil,"battle FX player released"end
  local built=self:packets(sceneContext);local moveByEffect={};for _,e in ipairs((self.runtime:snapshot().effects or{}))do moveByEffect[e.id]=e.moveId end
  local drawn=0
  for _,packet in ipairs(built.packets)do
    local renderer,err=self:_renderer(moveByEffect[packet.effectId],packet.shapeId)
    if not renderer then built.diagnostics[#built.diagnostics+1]={code="draw-renderer",severity="warning",effectId=packet.effectId,programId=packet.programId,address=nil,kind="draw",message=tostring(err)}
    else
      if type(renderer.setHandlerRuntime)=="function"then pcall(renderer.setHandlerRuntime,renderer,{callbackFrame=packet.frame or packet.age or 0},false)end
      local success=true
      for _,pass in ipairs({"opaque","additive"})do if type(renderer.drawScene)=="function"then local ok,result=pcall(renderer.drawScene,renderer,pass,packet.matrix,renderOptions(sceneContext,packet,pass));if not ok or result==false then success=false;built.diagnostics[#built.diagnostics+1]={code="draw-renderer",severity="warning",effectId=packet.effectId,programId=packet.programId,address=nil,kind="draw",message=ok and"renderer rejected packet"or tostring(result)};break end end end
      if success then drawn=drawn+1 end
    end
  end
  for _,d in ipairs(built.diagnostics)do
    local key=diagnosticKey(d)
    if not self.diagnosticKeys[key]then self.diagnosticKeys[key]=true;self.diagnostics[#self.diagnostics+1]=copy(d);if type(self.warn)=="function"then pcall(self.warn,copy(d))end end
  end
  built.drawn=drawn;return built
end
function Player:release()
  if self.released then return false end
  for _,entry in pairs(self.renderers)do if type(self.releaseRenderer)=="function"then pcall(self.releaseRenderer,entry.renderer,entry.owned)elseif entry.renderer and type(entry.renderer.release)=="function"then pcall(entry.renderer.release,entry.renderer)end end
  self.renderers={};self.diagnosticKeys={};self.runtime:release();self.released=true;return true
end
return Player
