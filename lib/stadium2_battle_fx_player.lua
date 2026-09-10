-- Runtime/packet/renderer coordinator. Battle mechanics remain host-owned.
local Runtime=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_runtime")
local Packets=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_draw_packets")
local NativePackets=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_native_object_packets")
local LifecyclePackets=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_lifecycle_packets")
local Ribbon=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_ribbon")
local WaveGrid=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_wave_grid")
local Beam=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_beam")
local Player={};Player.__index=Player
local NativeObjects=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_native_objects")
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
  local beamScene={}
  if not runtime then local ro=copy(options.runtimeOptions or{});ro.catalog=options.catalog or ro.catalog
    if options.resolveBeam then
      ro.lifecycleOptions=ro.lifecycleOptions or {}
      ro.lifecycleOptions.resolveBeam=ro.lifecycleOptions.resolveBeam or function(context)
        return options.resolveBeam(context,beamScene.value)
      end
    end
    runtime=Runtime.new(ro)
  end
  return setmetatable({runtime=runtime,loadRenderer=options.loadRenderer,releaseRenderer=options.releaseRenderer,contextForParticle=options.contextForParticle,resolvePlacement=options.resolvePlacement,
    resolveNativePlacement=options.resolveNativePlacement or options.resolveNativeObjectPlacement or options.nativePlacementResolver,
    resolveNativeGeometry=options.resolveNativeGeometry or options.resolveNativeObjectGeometry or options.nativeGeometryResolver,
    resolveNativeRenderer=options.resolveNativeRenderer or options.nativeObjectRendererResolver,
    resolveLifecycleModel=options.resolveLifecycleModel or options.lifecycleModelResolver,
    resolveLifecycleRenderer=options.resolveLifecycleRenderer or options.lifecycleRendererResolver,
    createGeometryRenderer=options.createGeometryRenderer,
    loadWaveGridTexture=options.loadWaveGridTexture,
    loadBeamTexture=options.loadBeamTexture,beamScene=beamScene,
    warn=options.warn,renderers={},diagnostics={},diagnosticKeys={},released=false},Player)
end
function Player:trigger(context)if self.released then return nil,"battle FX player released"end;return self.runtime:trigger(context)end
function Player:update(dt)if self.released then return nil end;return self.runtime:update(dt)end
function Player:finish(effectId)
  if self.released then return false end
  local manager=self.runtime.lifecycle
  if manager and manager.finishEffect then return manager:finishEffect(effectId) end
  return false
end
function Player:snapshot()return self.runtime:snapshot()end
function Player:backgroundColor(base)
  local native=self.runtime:snapshot().nativeObjects
  return NativeObjects.backgroundColor(base,native and native.nativeColor)
end
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
  built.nativeColor=snapshot.nativeObjects and copy(snapshot.nativeObjects.nativeColor)
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
  if packet.material and packet.material.nativeAlpha~=nil then
    rgba[4]=packet.material.nativeAlpha/255
  end
  local nativeColors=packet.material and packet.material.nativeMaterialColors and packet.material or nil
  if nativeColors then rgba[1],rgba[2],rgba[3]=1,1,1 end
  return{battleFxColors=nativeColors,viewProjection=camera.viewProjection or camera.vp,viewMatrix=camera.view,normalMatrix={1,0,0,0,1,0,0,0,1},lightDir=environment.light,ambient=environment.ambient,diffuse=environment.diffuse,tint=rgba,skipHandlers=pass=="additive",flipWinding=true,disableCulling=true,sunMap=shadow.map,sunVP=shadow.sunVP,sunDark=shadow.sunDark,sunBias=shadow.sunBias,sunTexel=shadow.sunTexel}
end
local function identityMatrix()
  return {1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1}
end
local function resolvedField(packet, field)
  local value = packet[field]
  if type(value) == "table" and value.resolved == true then return value end
  return nil
end
local function packetMatrix(packet)
  if type(packet.matrix) == "table" then return packet.matrix end
  local placement = resolvedField(packet, "placement")
  if placement and type(placement.matrix) == "table" then return placement.matrix end
  local resolution = packet.modelResolution
  if type(resolution) == "table" and type(resolution.matrix) == "table" then
    return resolution.matrix
  end
  -- Placement is callback-owned; only synthesize the standard transform when
  -- its proof contains explicit position/scale fields.
  if placement and (placement.position ~= nil or placement.scale ~= nil) then
    local p, s = placement.position or {0,0,0}, placement.scale or 1
    local px, py, pz = p[1] or p.x or 0, p[2] or p.y or 0, p[3] or p.z or 0
    local sx, sy, sz = type(s) == "table" and (s[1] or s.x or 1) or s,
      type(s) == "table" and (s[2] or s.y or 1) or s,
      type(s) == "table" and (s[3] or s.z or 1) or s
    return {sx,0,0,px, 0,sy,0,py, 0,0,sz,pz, 0,0,0,1}
  end
  return nil
end
local function packetShape(packet)
  local geometry = resolvedField(packet, "geometry")
  local model = packet.modelResolution
  return (geometry and (geometry.shapeId or geometry.shape))
    or (type(model) == "table" and (model.shapeId or model.shape))
end
local function drawProvenPacket(self, sceneContext, packet, moveId, resolver,
    kind, built)
  local renderer
  if type(resolver) == "function" then
    local ok, value = pcall(resolver, copy(packet), copy(sceneContext or {}))
    if ok then renderer = value else
      built.diagnostics[#built.diagnostics + 1] = {code="draw-renderer",severity="warning",
        effectId=packet.effectId,programId=packet.programId,kind=kind,
        message=tostring(value)}
    end
  end
  if not renderer then
    local geometry = packet.modelResolution and packet.modelResolution.geometry
    if geometry and (geometry.kind == "rom-ribbon" or geometry.kind == "rom-wave-grid"
        or geometry.kind == "rom-beam") and self.createGeometryRenderer then
      local wave=geometry.kind == "rom-wave-grid"
      local beam=geometry.kind == "rom-beam"
      local key = "lifecycle:"..tostring(packet.instanceId)
      local entry = self.renderers[key]
      if beam and entry and #entry.owned.prims~=#geometry.layers then
        if self.releaseRenderer then self.releaseRenderer(entry.renderer,entry.owned)
        elseif entry.renderer.release then entry.renderer:release() end
        self.renderers[key]=nil;entry=nil
      end
      local assets = self.runtime.catalog and self.runtime.catalog.lifecycleAssets
      local asset=assets and assets.ribbon
      if wave then
        asset=nil
        if not entry and self.loadWaveGridTexture then
          local ok,value=pcall(self.loadWaveGridTexture,moveId,geometry.family)
          if ok then asset=value end
        end
      end
      if beam then
        asset={}
        if not entry then
          for _,layer in ipairs(geometry.layers) do for _,symbol in ipairs(layer.draw.textures) do
            if not asset[symbol] then
              local ok,value
              if symbol==-1 then ok,value=true,assets and assets.beamGlow
              else ok,value=pcall(self.loadBeamTexture or function()end,moveId,symbol) end
              if ok then asset[symbol]=value end
              if not asset[symbol] then asset=nil;break end
            end
          end;if not asset then break end end
        end
      end
      if not entry and asset then
        local model = beam and Beam.model(geometry,asset)
          or wave and WaveGrid.model(asset,geometry) or Ribbon.model(asset, geometry)
        local ok, value = pcall(self.createGeometryRenderer, model)
        if ok and value then
          entry = {renderer=value, owned=model, frame=packet.frame}
          self.renderers[key] = entry
        end
      end
      if entry then
        renderer = entry.renderer
        if entry.frame ~= packet.frame then
          if beam then
            Beam.updateModel(entry.owned,geometry)
            for _,part in ipairs(renderer.parts or {}) do
              for i,row in ipairs(part.rows or {}) do
                for c=1,4 do row[8+c]=(part.prim.color[(i-1)*4+c] or 0)/255 end
              end
            end
          else
          local prim = entry.owned.prims[1]
          prim.pos, prim.idx, prim.nidx = geometry.pos, geometry.idx, #geometry.idx
          if wave then
            prim.nrm=geometry.nrm
            for i=1,prim.nverts do prim.color[i*4]=geometry.colors[1][4] end
            for _,part in ipairs(renderer.parts or {}) do
              for _,row in ipairs(part.rows or {}) do row[12]=geometry.colors[1][4]/255 end
            end
          end
          for _,part in ipairs(renderer.parts or {}) do
            part.used = {}
            for _,index in ipairs(geometry.idx) do part.used[index] = true end
          end
          end
          renderer:updatePose(true)
          entry.frame = packet.frame
        end
        if wave then
          packet.waveGrid=true
          local context=self.contextForParticle and self.contextForParticle({event={context=packet.context}},sceneContext)
          packet.matrix=WaveGrid.matrix(sceneContext and sceneContext.camera,context and context.worldUnits)
        elseif not beam then
          packet.material = {nativeMaterialColors=true,
            primaryColor=geometry.colors[1], secondaryColor=geometry.colors[2]}
        end
        if not wave and not packetMatrix(packet) and self.contextForParticle then
          local context = self.contextForParticle({event={context=packet.context}}, sceneContext)
          local units = context.worldUnits
          local origin = context.sharedOrigin
          if units and origin then
            packet.placement = {resolved=true, scale=units,
              position={origin[1]*units,origin[2]*units,origin[3]*units}}
          end
        end
      end
    end
  end
  if not renderer then
    local shape = packet.shapeId or packetShape(packet)
    if shape then renderer = self:_renderer(moveId, shape) end
  end
  if not renderer then
    built.diagnostics[#built.diagnostics + 1] = {code="draw-renderer",severity="warning",
      effectId=packet.effectId,programId=packet.programId,kind=kind,
      message=kind.." packet has no proven renderer or shape"}
    return false
  end
  local matrix = packetMatrix(packet)
  if not matrix then
    built.diagnostics[#built.diagnostics + 1] = {code="draw-placement",severity="warning",
      effectId=packet.effectId,programId=packet.programId,kind=kind,
      message=kind.." packet has no explicit proven placement or matrix"}
    return false
  end
  if type(renderer.drawScene) ~= "function" then
    built.diagnostics[#built.diagnostics + 1] = {code="draw-renderer",severity="warning",
      effectId=packet.effectId,programId=packet.programId,kind=kind,
      message=kind.." renderer has no drawScene method"}
    return false
  end
  local success = true
  if type(renderer.setHandlerRuntime) == "function" then
    pcall(renderer.setHandlerRuntime, renderer,
      {callbackFrame=packet.frame or packet.age or 0}, false)
  end
  for _, pass in ipairs({"opaque", "additive"}) do
    local options=renderOptions(sceneContext, packet, pass)
    if packet.waveGrid then
      -- All three grid materials use 0x0C184240: neither Z_CMP nor Z_UPD.
      options.screenSpace=true
      options.normalMatrix={matrix[1],matrix[2],matrix[3],matrix[5],matrix[6],matrix[7],matrix[9],matrix[10],matrix[11]}
    end
    local ok, result = pcall(renderer.drawScene, renderer, pass, matrix,
      options)
    if not ok or result == false then
      success = false
      built.diagnostics[#built.diagnostics + 1] = {code="draw-renderer",severity="warning",
        effectId=packet.effectId,programId=packet.programId,kind=kind,
        message=ok and "renderer rejected packet" or tostring(result)}
      break
    end
  end
  return success
end
function Player:_renderer(moveId,shapeId)
  local key=tostring(moveId)..":"..tostring(shapeId);if self.renderers[key]then return self.renderers[key].renderer end
  if type(self.loadRenderer)~="function"then return nil,"battle FX renderer loader unavailable"end
  local ok,renderer,owned=pcall(self.loadRenderer,moveId,shapeId);if not ok then return nil,tostring(renderer)end;if not renderer then return nil,tostring(owned or"battle FX shape renderer unavailable")end
  self.renderers[key]={renderer=renderer,owned=owned};return renderer
end
function Player:draw(sceneContext)
  self.beamScene.value=sceneContext
  if sceneContext then
    local native=self.runtime:snapshot().nativeObjects
    sceneContext.nativeModelColors=native and native.modelColors
    sceneContext.nativeOverlayDraw=function()return self:drawOverlay(sceneContext)end
  end
  if self.released then return nil,"battle FX player released"end
  local built=self:packets(sceneContext);local moveByEffect={};for _,e in ipairs((self.runtime:snapshot().effects or{}))do moveByEffect[e.id]=e.moveId end
  local liveLifecycle = {}
  for _,packet in ipairs(built.lifecyclePackets or {}) do
    liveLifecycle["lifecycle:"..tostring(packet.instanceId)] = true
  end
  for key,entry in pairs(self.renderers) do
    if key:sub(1,10) == "lifecycle:" and not liveLifecycle[key] then
      if self.releaseRenderer then self.releaseRenderer(entry.renderer,entry.owned)
      elseif entry.renderer.release then entry.renderer:release() end
      self.renderers[key] = nil
    end
  end
  local drawn=0
  for _,packet in ipairs(built.packets)do
    local renderer,err=self:_renderer(moveByEffect[packet.effectId],packet.shapeId)
    if not renderer or type(renderer.drawScene)~="function" then built.diagnostics[#built.diagnostics+1]={code="draw-renderer",severity="warning",effectId=packet.effectId,programId=packet.programId,address=nil,kind="draw",message=renderer and "renderer has no drawScene method" or tostring(err)}
    else
      if type(renderer.setHandlerRuntime)=="function"then pcall(renderer.setHandlerRuntime,renderer,{callbackFrame=packet.frame or packet.age or 0},false)end
      local success=true
      for _,pass in ipairs({"opaque","additive"})do if type(renderer.drawScene)=="function"then local ok,result=pcall(renderer.drawScene,renderer,pass,packet.matrix,renderOptions(sceneContext,packet,pass));if not ok or result==false then success=false;built.diagnostics[#built.diagnostics+1]={code="draw-renderer",severity="warning",effectId=packet.effectId,programId=packet.programId,address=nil,kind="draw",message=ok and"renderer rejected packet"or tostring(result)};break end end end
      if success then drawn=drawn+1 end
    end
  end
  -- Native-object and lifecycle packets are renderer-neutral, but proven
  -- packets must reach the renderer.  Unresolved packets have no geometry and
  -- remain diagnostic-only by construction in their packet builders.
  for _,packet in ipairs(built.nativeObjectPackets or {}) do
    if resolvedField(packet, "placement") and resolvedField(packet, "geometry")
        and drawProvenPacket(self, sceneContext, packet, moveByEffect[packet.effectId],
          self.resolveNativeRenderer, "native-object", built) then
      drawn = drawn + 1
    end
  end
  for _,packet in ipairs(built.lifecyclePackets or {}) do
    if packet.renderable == true and drawProvenPacket(self, sceneContext, packet,
        moveByEffect[packet.effectId], self.resolveLifecycleRenderer,
        "lifecycle", built) then
      drawn = drawn + 1
    end
  end
  for _,d in ipairs(built.diagnostics)do
    local key=diagnosticKey(d)
    if not self.diagnosticKeys[key]then self.diagnosticKeys[key]=true;self.diagnostics[#self.diagnostics+1]=copy(d);if type(self.warn)=="function"then pcall(self.warn,copy(d))end end
  end
  built.drawn=drawn;return built
end

-- 841078B8 sets flags 0x7028, placing the native visual in the 2D pass.
-- 841032F0 selects export 90 through 8418CB88; it is the ROM's screen quad.
function Player:drawOverlay(sceneContext)
  if self.released then return 0 end
  local snapshot=self.runtime:snapshot()
  local moves={}
  for _,effect in ipairs(snapshot.effects or {}) do moves[effect.id]=effect.moveId end
  local count=0
  for _,instance in ipairs(snapshot.nativeObjects.screenInstances or {}) do
    if instance.active then
      local renderer,err=self:_renderer(moves[instance.effectId],instance.shapeId)
      if renderer then
        if renderer.setHandlerRuntime then renderer:setHandlerRuntime({callbackFrame=instance.age},false) end
        local packet={material={nativeMaterialColors=true,nativeAlpha=255,
          primaryColor={255,255,255,255},secondaryColor=instance.rgba}}
        for _,pass in ipairs({"opaque","additive"}) do
          local options=renderOptions(sceneContext,packet,pass)
          options.screenSpace=true
          options.viewProjection={1/160,0,0,-1, 0,-1/120,0,1, 0,0,-.5,0, 0,0,0,1}
          options.viewMatrix=identityMatrix()
          local matrix=identityMatrix();matrix[4]=160;matrix[8]=120
          local ok,message=renderer:drawScene(pass,matrix,options)
          if ok==false then error(message or "native screen draw failed") end
        end
        count=count+1
      elseif self.warn then
        self.warn({code="native-screen-renderer",kind="native-object",severity="warning",
          effectId=instance.effectId,message=tostring(err)})
      end
    end
  end
  return count
end
function Player:release()
  if self.released then return false end
  for _,entry in pairs(self.renderers)do if type(self.releaseRenderer)=="function"then pcall(self.releaseRenderer,entry.renderer,entry.owned)elseif entry.renderer and type(entry.renderer.release)=="function"then pcall(entry.renderer.release,entry.renderer)end end
  self.renderers={};self.diagnosticKeys={};self.runtime:release();self.released=true;return true
end
return Player
