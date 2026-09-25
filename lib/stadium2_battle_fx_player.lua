-- Runtime/packet/renderer coordinator. Battle mechanics remain host-owned.
local Runtime=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_runtime")
local Attachment=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_attachment")
local Packets=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_draw_packets")
local NativePackets=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_native_object_packets")
local LifecyclePackets=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_lifecycle_packets")
local Ribbon=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_ribbon")
local WaveGrid=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_wave_grid")
local TerrainGrid=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_terrain_grid")
local Beam=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_beam")
local CommonAnchor=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_common_anchor")
local BattleState=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_battle_state")
local ModelAnimation=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_model_animation")
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
local function drawDiagnostic(built,packet,code,message)
  built.diagnostics[#built.diagnostics+1]={code=code,severity="warning",
    effectId=packet.effectId,programId=packet.programId,instanceId=packet.instanceId,
    familyId=packet.familyId,address=packet.address,kind="draw",message=tostring(message)}
end
local function configureRenderer(renderer,packet,built)
  if packet.modelAnimation then
    local state=packet.modelAnimation
    local model=renderer.model
    if not model or model.battleFxAnimationId~=state.id or not renderer.seekFrame then
      drawDiagnostic(built,packet,'unresolved-model-animation','native FX skeletal animation is unavailable')
      return false
    end
    local target=ModelAnimation.frame(model.anims[1],state)
    renderer.animIndex=1
    if renderer.frame~=target or renderer._battleFxPoseFrame~=target then
      local ok,result=pcall(renderer.seekFrame,renderer,target)
      if not ok or not result then
        drawDiagnostic(built,packet,'model-animation-pose',ok and 'pose rejected' or result)
        return false
      end
      renderer._battleFxPoseFrame=target
    end
  end
  if type(renderer.setHandlerRuntime)~="function" then return true end
  -- Common FX frameRule is a spawn hold, not the material clock. The
  -- fragment-26 controller reads the particle's live byte age at +0x7F.
  local frame=packet.materialFrame or packet.frame or packet.age or 0
  local ok,result,detail=pcall(renderer.setHandlerRuntime,renderer,
    -- FX renderers are cached and never advance Renderer.displayTime. Supply
    -- their material clock explicitly, or phase-5 controllers stay at zero.
    {callbackFrame=frame,materialFrame=frame},false)
  if not ok or result==false then
    drawDiagnostic(built,packet,"draw-handler-runtime",
      ok and (detail or "renderer rejected callback state") or result)
    return false
  end
  return true
end
function Player.new(options)
  options=type(options)=="table"and options or{};local runtime=options.runtime
  local beamScene={value=options.sceneContext}
  local signals={global=0}
  local player
  local dynamicAnchors={}
  if not runtime then local ro=copy(options.runtimeOptions or{});ro.catalog=options.catalog or ro.catalog
    ro.modelAnimationFinished=ro.modelAnimationFinished or function(particle,tick)
      if not ModelAnimation.finishesParticle(particle) then return false end
      -- 8410291C checks the pose from the preceding graph traversal. Keep
      -- the terminal pose visible for its tick before retiring the object.
      local animation=ModelAnimation.packet(particle,tick-1)
      if not animation then return false end
      local renderer,err=player:_renderer(particle.event.context.moveId,
        particle.shapeId,animation.id)
      local model=renderer and renderer.model
      if not model or model.battleFxAnimationId~=animation.id then
        return nil,err or 'native FX animation header unavailable for completion'
      end
      return ModelAnimation.finished(model.anims[1],animation)
    end
    ro.writeDynamicAnchor=ro.writeDynamicAnchor or function(particle,rule)
      local animation=ModelAnimation.packet(particle,player.runtime.frame)
      local renderer,err=player:_renderer(particle.event.context.moveId,particle.shapeId,
        animation and animation.id)
      if not renderer then return nil,err end
      if not renderer.attachmentPosition or not renderer.updatePose then
        return nil,'dynamic anchor requires a posed FX model marker'
      end
      local built={diagnostics={}}
      local posed={};for key,value in pairs(particle) do posed[key]=value end
      posed.modelAnimation=animation
      if not configureRenderer(renderer,posed,built) then return nil,'dynamic anchor callback pose failed' end
      renderer:updatePose(true)
      local point=renderer:attachmentPosition(1)
      if not point then return false end -- 8003C9B8 leaves the table untouched
      local position={}
      for k=1,3 do position[k]=(particle.nativeAnchor and particle.nativeAnchor[k] or 0)+particle.position[k] end
      local matrix=Packets.nativeMatrix(position,particle.scale,particle.rotation)
      local f=require('mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_float')
      local out={}
      for k=1,3 do local j=(k-1)*4
        out[k]=f(matrix[j+1]*point[1]+matrix[j+2]*point[2]+matrix[j+3]*point[3]+matrix[j+4])
      end
      dynamicAnchors[rule.index]=out
      return true
    end
    ro.materialOptions=ro.materialOptions or {}
    ro.materialOptions.resetNativeAlphaGlobalGate=ro.materialOptions.resetNativeAlphaGlobalGate
      or function()signals.global=0 end -- 841072A4, each gated constructor
    local alphaResolver=ro.materialOptions.resolveNativeAlphaGate
    ro.materialOptions.resolveNativeAlphaGate=function(kind,state,context)
      if alphaResolver then
        local value=alphaResolver(kind,state,context)
        if value~=nil then return value end
      end
      if kind=='global' then
        if context.nativeAlphaGlobalGate~=nil then return context.nativeAlphaGlobalGate end
        return signals.global
      end
      if context.nativeAlphaSignal~=nil then return context.nativeAlphaSignal end
      local manager=runtime and runtime.lifecycle
      if manager and manager.finishedEffects and manager.finishedEffects[context.effectId] then return 1 end
      return manager and manager.nativeSignal or nil
    end
    if options.commonAnchorInputs then
      ro.motionOptions=ro.motionOptions or {}
      local savedOrigin
      ro.motionOptions.resolveNativeAnchor=ro.motionOptions.resolveNativeAnchor or function(state,initial)
        local event=state.particle.event or {}
        -- 841072BC: a mode-1 emission whose descriptor has 0x800000 takes
        -- 8410668C's particle-pool origin at construction instead of 84104A00.
        if initial and event.mode==1 and math.floor((tonumber(event.flags) or 0)/0x800000)%2==1
            and runtime and runtime.nativePoolOrigin then
          return {anchor=runtime:nativePoolOrigin(state.particle),diagnostics={}}
        end
        local input=options.commonAnchorInputs(state.particle,beamScene.value)
        local rule=event.transform and event.transform.nativeAnchorTable
        if rule and rule.mode==1 then
          input=input or {}
          input.nestedAnchor=dynamicAnchors[rule.index]
          input.dynamicAnchorMissing=input.nestedAnchor==nil
        end
        local result=CommonAnchor.resolve(event,input or {},savedOrigin)
        if initial and event.mode==0 and result.saveOrigin then
          local f=require('mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_float')
          savedOrigin={}
          for axis=1,3 do savedOrigin[axis]=f(result.anchor[axis]+
            (result.clearCommonOffset and 0 or state.nativeSpawnOffset[axis])) end
        end
        return result
      end
    end
    if options.contextForParticle then
      ro.motionOptions=ro.motionOptions or {}
      ro.motionOptions.resolveNativeYaw=ro.motionOptions.resolveNativeYaw or function(particle)
        local context=options.contextForParticle(particle,beamScene.value)
        return context and context.nativeSourceYaw
      end
      ro.motionOptions.resolveNativeSpawnScale=ro.motionOptions.resolveNativeSpawnScale or function(particle)
        local context=options.contextForParticle(particle,beamScene.value)
        return context and context.nativeSpawnScale
      end
      ro.motionOptions.resolveNativeContextScale=ro.motionOptions.resolveNativeContextScale or function(particle)
        local context=options.contextForParticle(particle,beamScene.value)
        return context and context.nativeContextScale
      end
      ro.motionOptions.resolveNativeFinalY=ro.motionOptions.resolveNativeFinalY or function(state)
        local particle=copy(state.particle or {})
        particle.position=copy(state.position)
        local contract=particle.attachment or particle.event and particle.event.attachment
        local context=options.contextForParticle(particle,beamScene.value)
        local placement=contract and context and Attachment.resolve(contract,context)
        return placement and placement.resolved and placement.position[2] or nil
      end
    end
    if options.emissionMarkers and not ro.emissionMarkers then
      -- 84107998 marker selection needs the owner's live model data.
      ro.emissionMarkers=function(event,context,markerSelect)
        return options.emissionMarkers(event,context,markerSelect,beamScene.value)
      end
    end
    if options.resolveBeam then
      ro.lifecycleOptions=ro.lifecycleOptions or {}
      ro.lifecycleOptions.resolveBeam=ro.lifecycleOptions.resolveBeam or function(context)
        return options.resolveBeam(context,beamScene.value)
      end
    end
    runtime=Runtime.new(ro)
  end
  player=setmetatable({runtime=runtime,loadRenderer=options.loadRenderer,releaseRenderer=options.releaseRenderer,contextForParticle=options.contextForParticle,resolvePlacement=options.resolvePlacement,
    resolveNativePlacement=options.resolveNativePlacement or options.resolveNativeObjectPlacement or options.nativePlacementResolver,
    resolveNativeGeometry=options.resolveNativeGeometry or options.resolveNativeObjectGeometry or options.nativeGeometryResolver,
    resolveNativeRenderer=options.resolveNativeRenderer or options.nativeObjectRendererResolver,
    resolveLifecycleModel=options.resolveLifecycleModel or options.lifecycleModelResolver,
    resolveLifecycleRenderer=options.resolveLifecycleRenderer or options.lifecycleRendererResolver,
    createGeometryRenderer=options.createGeometryRenderer,
    loadWaveGridTexture=options.loadWaveGridTexture,
    loadBeamTexture=options.loadBeamTexture,beamScene=beamScene,
    battleStateForContext=options.battleStateForContext,signals=signals,dynamicAnchors=dynamicAnchors,
    contextNeedsSnapshot=options.contextNeedsSnapshot,
    warn=options.warn,renderers={},diagnostics={},diagnosticKeys={},released=false},Player)
  return player
end
function Player:trigger(context)
  if self.released then return nil,"battle FX player released" end
  context=copy(context or {})
  if not context.conditionForMove then
    local inputs=self.battleStateForContext and self.battleStateForContext(context,self.beamScene.value)
      or context.nativeBattleState
    context.conditionForMove=function(id,_,record,current)
      return BattleState.condition(context.nativeContextId or id,inputs,current)
    end
  end
  return self.runtime:trigger(context)
end
-- 8410890C latches the independent global alpha gate only for context 300.
function Player:signalContext(id)
  if self.released then return false end
  if id==300 then self.signals.global=1 end
  return true
end
-- 8410890C(id, owner) also stores the effect ID and owner; the next
-- 8410545C pass plays entry `id` of D_84182A5C through its primary route
-- (entries 252..301 are the non-move battle effects). Like move routes,
-- the runtime starts it on the current tick as local frame zero.
function Player:playEntry(id,context)
  if self.released then return nil,"battle FX player released" end
  id=tonumber(id)
  if not id or id%1~=0 or id<1 then return nil,"battle FX entry ID is invalid" end
  context=copy(context or {})
  context.moveId=id
  context.alternate=false
  context.variant=nil
  return self:trigger(context)
end
-- D_841901B8, read by 841094EC as the lifecycle presentation signal:
-- 841086F0 (route armed) clears it; 8410874C (impact) and 8410878C set it.
function Player:setRouteSignal(value)
  if self.released then return false end
  local manager=self.runtime.lifecycle
  if not (manager and manager.setNativeSignal) then return false end
  manager:setNativeSignal(value)
  return true
end
-- 84108A10(owner) held-particle release; see Runtime:releaseHeld.
function Player:releaseHeld(ownerSide)
  if self.released then return 0 end
  return self.runtime:releaseHeld(ownerSide)
end
-- 841089D8(1) failed-move cleanup; see Runtime:abortAll.
function Player:abortAll()
  if self.released then return false end
  return self.runtime:abortAll()
end
function Player:dynamicAnchor(index) return copy(self.dynamicAnchors[index]) end
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
function Player:_recordDiagnostics(items)
  for _,d in ipairs(items or {}) do
    local key=diagnosticKey(d)
    if not self.diagnosticKeys[key] then
      self.diagnosticKeys[key]=true
      self.diagnostics[#self.diagnostics+1]=copy(d)
      if type(self.warn)=="function" then pcall(self.warn,copy(d)) end
    end
  end
end
-- `snapshot` lets one draw reuse a single runtime snapshot; each snapshot
-- deep-copies lifecycle geometry, so taking several per frame was costly.
function Player:packets(sceneContext,snapshot)
  snapshot=snapshot or self.runtime:snapshot()
  local built=Packets.build(snapshot,{context=sceneContext,
    contextNeedsSnapshot=self.contextNeedsSnapshot,
    trigTables=self.runtime.catalog and self.runtime.catalog.trigTables,
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
  return{battleFxColors=nativeColors,viewProjection=camera.viewProjection or camera.vp,viewMatrix=camera.view,normalMatrix={1,0,0,0,1,0,0,0,1},lightDir=environment.light,ambient=environment.ambient,diffuse=environment.diffuse,tint=rgba,skipHandlers=pass=="additive",flipWinding=true,disableCulling=not (packet.geometry and packet.geometry.nativeCulling),sunMap=shadow.map,sunVP=shadow.sunVP,sunDark=shadow.sunDark,sunBias=shadow.sunBias,sunTexel=shadow.sunTexel}
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
        or geometry.kind == "rom-terrain-grid" or geometry.kind == "rom-beam") and self.createGeometryRenderer then
      local wave=geometry.kind == "rom-wave-grid"
      local terrain=geometry.kind == "rom-terrain-grid"
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
      if terrain then
        asset={}
        if not entry then
          for _,symbol in ipairs(geometry.textureSymbols or {31,32}) do
            local ok,value=pcall(self.loadBeamTexture or function()end,moveId,symbol)
            if ok then asset[symbol]=value end
            if not asset[symbol] then asset=nil;break end
          end
        end
      end
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
              if symbol==-4 then ok,value=true,assets and assets.radialSpark
              elseif symbol==-3 then ok,value=true,assets and assets.needle and assets.needle.texture
              elseif symbol==-2 then
                local ribbon=assets and assets.ribbon
                ok,value=true,ribbon and {w=8,h=16,format=3,size=1,rgba=ribbon.rgba}
              elseif symbol==-1 then ok,value=true,assets and assets.beamGlow
              else
                local fmt=layer.draw.textureFormat
                ok,value=pcall(self.loadBeamTexture or function()end,moveId,symbol,
                  fmt and fmt[1],fmt and fmt[2])
              end
              if ok then asset[symbol]=value end
              if not asset[symbol] then asset=nil;break end
            end
          end;if not asset then break end end
        end
      end
      if not entry and asset then
        local model = beam and Beam.model(geometry,asset)
          or wave and WaveGrid.model(asset,geometry)
          or terrain and TerrainGrid.model(geometry,asset) or Ribbon.model(asset, geometry)
        local ok, value, detail = pcall(self.createGeometryRenderer, model)
        if ok and value then
          entry = {renderer=value, owned=model, frame=packet.frame}
          self.renderers[key] = entry
        else
          drawDiagnostic(built,packet,"draw-geometry-renderer",
            ok and (detail or "geometry renderer returned no renderer") or value)
        end
      elseif not entry then
        drawDiagnostic(built,packet,"draw-lifecycle-texture",
          "ROM texture assets unavailable for "..tostring(geometry.kind))
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
          elseif terrain then
            TerrainGrid.updateModel(entry.owned,geometry)
            for _,part in ipairs(renderer.parts or {}) do
              for i,row in ipairs(part.rows or {}) do
                for c=1,4 do row[8+c]=(part.prim.color[(i-1)*4+c] or 0)/255 end
              end
              part.used={};for _,index in ipairs(part.prim.idx) do part.used[index]=true end
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
        elseif not beam and not terrain then
          packet.material = {nativeMaterialColors=true,
            primaryColor=geometry.colors[1], secondaryColor=geometry.colors[2]}
        end
        if not wave and not packetMatrix(packet) and self.contextForParticle then
          local context = self.contextForParticle({event={context=packet.context}}, sceneContext)
          local units = context.worldUnits
          local origin = terrain and {0,0,0} or context.sharedOrigin
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
  if not configureRenderer(renderer,packet,built) then return false end
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
function Player:_renderer(moveId,shapeId,animationId)
  local key=tostring(moveId)..":"..tostring(shapeId)..":"..tostring(animationId or 0);if self.renderers[key]then return self.renderers[key].renderer end
  if type(self.loadRenderer)~="function"then return nil,"battle FX renderer loader unavailable"end
  local ok,renderer,owned=pcall(self.loadRenderer,moveId,shapeId,animationId);if not ok then return nil,tostring(renderer)end;if not renderer then return nil,tostring(owned or"battle FX shape renderer unavailable")end
  self.renderers[key]={renderer=renderer,owned=owned};return renderer
end
function Player:draw(sceneContext)
  self.beamScene.value=sceneContext
  if self.released then return nil,"battle FX player released"end
  local snapshot=self.runtime:snapshot()
  if sceneContext then
    local native=snapshot.nativeObjects
    sceneContext.nativeModelColors=native and native.modelColors
    sceneContext.nativeOverlayDraw=function()return self:drawOverlay(sceneContext)end
  end
  local built=self:packets(sceneContext,snapshot);local moveByEffect={};for _,e in ipairs((snapshot.effects or{}))do moveByEffect[e.id]=e.moveId end
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
    local renderer,err=self:_renderer(moveByEffect[packet.effectId],packet.shapeId,
      packet.modelAnimation and packet.modelAnimation.id)
    if not renderer or type(renderer.drawScene)~="function" then built.diagnostics[#built.diagnostics+1]={code="draw-renderer",severity="warning",effectId=packet.effectId,programId=packet.programId,address=nil,kind="draw",message=renderer and "renderer has no drawScene method" or tostring(err)}
    else
      local success=configureRenderer(renderer,packet,built)
      local drawMatrix=packet.matrix
      local shapeModel=renderer.model
      if success and shapeModel and shapeModel.battleFxGeometryMode~=nil
          and not shapeModel.battleFxCompiledLayout and packet.nativeTransform then
        -- 841031F4 -> 84102B3C: direct shapes use the geometry-mode transform.
        -- Compiled layouts are drawn by the model system from 841028DC.
        local value,code,message=Packets.shapeMatrix(packet.nativeTransform,
          shapeModel.battleFxGeometryMode,{trigTables=self.runtime.catalog and self.runtime.catalog.trigTables,
          camera=sceneContext and sceneContext.camera})
        if value then drawMatrix=value
        else success=false;drawDiagnostic(built,packet,code,message) end
      end
      if success then
        for _,pass in ipairs({"opaque","additive"})do if type(renderer.drawScene)=="function"then local ok,result=pcall(renderer.drawScene,renderer,pass,drawMatrix,renderOptions(sceneContext,packet,pass));if not ok or result==false then success=false;built.diagnostics[#built.diagnostics+1]={code="draw-renderer",severity="warning",effectId=packet.effectId,programId=packet.programId,address=nil,kind="draw",message=ok and"renderer rejected packet"or tostring(result)};break end end end
      end
      if success then drawn=drawn+1 end
    end
  end
  -- Native-object and lifecycle packets are renderer-neutral, but proven
  -- packets must reach the renderer.  Unresolved packets have no geometry and
  -- remain diagnostic-only by construction in their packet builders.
  for _,packet in ipairs(built.nativeObjectPackets or {}) do
    if not packet.presentationKind and resolvedField(packet, "placement") and resolvedField(packet, "geometry")
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
  self:_recordDiagnostics(built.diagnostics)
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
  local built={diagnostics={}}
  local screens=Packets.build(snapshot,{screenOnly=true,trigTables=self.runtime.catalog and self.runtime.catalog.trigTables})
  for _,d in ipairs(screens.diagnostics) do
    if d.code=='unresolved-screen-trig' then built.diagnostics[#built.diagnostics+1]=d end
  end
  for _,instance in ipairs(snapshot.nativeObjects and snapshot.nativeObjects.screenInstances or {}) do
    if instance.active then
      local matrix=identityMatrix();matrix[4]=160;matrix[8]=120
      screens.screenPackets[#screens.screenPackets+1]={effectId=instance.effectId,
        age=instance.age,born=instance.born,shapeId=instance.shapeId,matrix=matrix,
        matrixYScale=matrix,material={nativeMaterialColors=true,nativeAlpha=255,
          primaryColor={255,255,255,255},secondaryColor=instance.rgba}}
    end
  end
  -- Keep earlier full-screen color layers behind later screen particles.
  for i,p in ipairs(screens.screenPackets) do p.screenOrder=i end
  table.sort(screens.screenPackets,function(a,b)
    local x,y=a.born or 0,b.born or 0
    if x~=y then return x<y end
    return a.screenOrder<b.screenOrder
  end)
  for _,packet in ipairs(screens.screenPackets) do
    local renderer,err=self:_renderer(moves[packet.effectId],packet.shapeId)
    if renderer and type(renderer.drawScene)=='function' then
      local success=configureRenderer(renderer,packet,built)
      for _,pass in ipairs(success and {'opaque','additive'} or {}) do
        local options=renderOptions(sceneContext,packet,pass)
        options.screenSpace=true
        options.viewProjection={1/160,0,0,-1,0,-1/120,0,1,0,0,-.5,0,0,0,0,1}
        options.viewMatrix=identityMatrix()
        local geometryMode=renderer.model and renderer.model.battleFxGeometryMode
        local matrix=geometryMode==6 and packet.matrixYScale or packet.matrix
        local ok,result,message=pcall(renderer.drawScene,renderer,pass,matrix,options)
        if not ok or result==false then
          drawDiagnostic(built,packet,'native-screen-renderer',ok and (message or 'screen draw failed') or result)
          success=false;break
        end
      end
      if success then count=count+1 end
    else drawDiagnostic(built,packet,'native-screen-renderer',err or 'screen renderer has no drawScene method') end
  end
  self:_recordDiagnostics(built.diagnostics)
  return count
end
function Player:release()
  if self.released then return false end
  for _,entry in pairs(self.renderers)do if type(self.releaseRenderer)=="function"then pcall(self.releaseRenderer,entry.renderer,entry.owned)elseif entry.renderer and type(entry.renderer.release)=="function"then pcall(entry.renderer.release,entry.renderer)end end
  self.renderers={};self.diagnosticKeys={};self.runtime:release();self.released=true;return true
end
return Player
