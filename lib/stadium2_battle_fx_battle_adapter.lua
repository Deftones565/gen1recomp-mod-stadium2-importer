-- Presentation-only bridge between a host battle scene and the persistent
-- Stadium 2 move-FX player. It translates fragment-79 source units at the
-- final renderer boundary; battle mechanics and battle RNG remain untouched.
local Attachment = require(
  "mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_attachment")
local Dispatch = require("mods.STADIUM2_IMPORTER.lib.animation_dispatch")
local Endpoints = require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_endpoints")
local Sequence = require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_sequence")
local EmissionMarkers = require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_emission_markers")

local Adapter = {}
Adapter.__index = Adapter

-- D_84190194, the owner 84107170 stores at object +8: 84108728 (move bank)
-- owns particles by the attacker; 8410874C (impact bank) by the battler that
-- runs the hit-frame state, the target. An explicit nativeOwnerSide wins.
function Adapter.ownerSide(context)
  context=context or {}
  if context.nativeOwnerSide then return context.nativeOwnerSide end
  local source=context.sourceSide or 'player'
  if context.alternate then
    return context.targetSide or (source=='player' and 'enemy' or 'player')
  end
  return source
end

function Adapter.battleState(context,sceneContext)
  sceneContext=sceneContext or {}
  local scene=sceneContext.scene or {}
  local source=context.sourceSide or 'player'
  local side=context.nativeOwnerSide or (context.alternate and
    (context.targetSide or (source=='player' and 'enemy' or 'player')) or source)
  local function actor(s)
    return scene.host and scene.host.visualActor and scene.host:visualActor(s)
      or scene.actors and scene.actors[s]
  end
  local owner,attacker=actor(side),actor(source)
  local input={}
  for k,v in pairs(sceneContext.nativeBattleState or {}) do input[k]=v end
  for k,v in pairs(context.nativeBattleState or {}) do input[k]=v end
  input.ownerSpecies=input.ownerSpecies or owner and owner.renderer and owner.renderer.model
    and owner.renderer.model.species
  input.sourceStatus=input.sourceStatus or attacker and attacker.nativeStatus
  input.ownerStatusPattern=input.ownerStatusPattern or owner and owner.nativeStatusPattern
  return input
end

-- BattleAnim_GetPointAlongCameraRay (84105930): eye + t * dir, where
-- 84105B90 caches the camera eye (+0xA8) and dir = normalize(focus - eye)
-- via 84105880 (exactly coincident points yield (0,0,1)). Native units.
function Adapter.cameraRayPoint(camera,distance,units)
  distance=tonumber(distance)
  local eye,focus=camera and camera.eye,camera and camera.focus
  if distance==nil or type(eye)~="table" or type(focus)~="table" then return nil end
  local f32=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_float")
  units=tonumber(units) or .05
  local e={(eye[1] or eye.x)/units,(eye[2] or eye.y)/units,(eye[3] or eye.z)/units}
  local t={(focus[1] or focus.x)/units,(focus[2] or focus.y)/units,(focus[3] or focus.z)/units}
  local d={t[1]-e[1],t[2]-e[2],t[3]-e[3]}
  if t[1]==e[1] and d[2]==0 and d[3]==0 then d={0,0,1}
  else
    local length=math.sqrt(d[1]^2+d[2]^2+d[3]^2)
    d={d[1]/length,d[2]/length,d[3]/length}
  end
  return {f32(distance*d[1]+e[1]),f32(distance*d[2]+e[2]),f32(distance*d[3]+e[3])}
end

-- Dispatch row whose bytes 2/3 are in the owner's +61C/+61D. Only the row
-- loaders write them (841146D4: move and charge rows, 8411AF6C: move row,
-- 84116BC0: row 254 on the defender hit), so a move effect sees its own row
-- and a non-move entry (id > 251) sees the owner's last loaded row
-- (actor.nativeMarkerRow), or nothing before the first load.
function Adapter.markerRow(actor,context)
  local id=tonumber(context and context.moveId) or 0
  if id>=1 and id<=251 then return id-1 end
  return actor and tonumber(actor.nativeMarkerRow) or nil
end

-- 84107998 inputs for the owner that 84107170 stores at object +8. The
-- placement path resolves markers on the source actor, so the same owner is
-- used here. Primary/secondary are dispatch bytes 2/3 (owner +61C/+61D),
-- the context label is 8411E244 for the scheduler context (+0A), and the
-- marker list is the owner model's ordered attachment labels.
function Adapter.emissionMarkers(event,context,markerSelect,sceneContext)
  sceneContext=sceneContext or {}
  context=context or {}
  local side=Adapter.ownerSide(context)
  local scene=sceneContext.scene or {}
  local host=scene.host
  local actor=host and host.visualActor and host:visualActor(side)
    or scene.actors and scene.actors[side]
  local model=actor and actor.renderer and actor.renderer.model
  if not model then return nil,"owner model is unavailable" end
  local bytes=model.fxDispatch
  local row=Adapter.markerRow(actor,context) or -1
  local inputs={}
  if type(bytes)=="string" and row>=0 and #bytes>=(row+1)*20 then
    inputs.primary=bytes:byte(row*20+3)
    inputs.secondary=bytes:byte(row*20+4)
  end
  inputs.context=Dispatch.contextMarker(context.nativeContextId or context.moveId,
    model.fxContextScales,bytes)
  if type(model.attachments)=="table" then
    inputs.attachments={}
    for _,marker in ipairs(model.attachments) do inputs.attachments[#inputs.attachments+1]=marker.label end
  end
  return EmissionMarkers.select(event,markerSelect,inputs)
end

-- Snapshot posed marker coordinates at simulation time, not during drawing.
function Adapter.commonAnchorInputs(particle,sceneContext)
  sceneContext=sceneContext or {}
  local event=particle.event or {}
  local side=Adapter.ownerSide(event.context)
  local scene=sceneContext.scene or {}
  local host=scene.host
  local actor=host and host.visualActor and host:visualActor(side)
    or scene.actors and scene.actors[side]
  local renderer=actor and actor.renderer
  local model=renderer and renderer.model
  local units=Adapter.worldUnits(sceneContext,side)
  local world=sceneContext.world or {}
  local slot=world.actorSlots and world.actorSlots[side] or world.origin or {0,0,0}
  local position={(slot.x or slot[1] or 0)/units,(slot.y or slot[2] or 0)/units,
    (slot.z or slot[3] or 0)/units}
  local input={position=position,flags=actor and actor.nativeFxFlags or 0,
    lane=side=='player' and 1 or -1,markerLabel=particle.nativeMarkerLabel,
    species=model and model.species,specialHeightPoint=actor and actor.nativeFxHeightPoint}
  local matrix=host and actor and host.modelMatrix and host:modelMatrix(side,actor)
  if matrix then
    local function transform(p)
      local out={}
      for k=1,3 do local j=(k-1)*4
        out[k]=(matrix[j+1]*p[1]+matrix[j+2]*p[2]+matrix[j+3]*p[3]+matrix[j+4])/units
      end
      return out
    end
    local profile=Dispatch.battleProfile(model and model.fxBattleProfile)
    if profile then
      input.centerY=transform({0,profile.centerY,0})[2]
      local scale=math.sqrt(matrix[1]^2+matrix[5]^2+matrix[9]^2)/units
      input.targetHeight=profile.targetHeight*scale
      input.bodyHeight=profile.bodyHeight and profile.bodyHeight*scale
    end
    if renderer.attachmentPositions then
      input.markers={}
      for label,p in pairs(renderer.attachmentPositions) do input.markers[label]=transform(p) end
    end
  end
  input.anchorY=Endpoints.anchorHeight(input)
  -- A label chosen by 84107998 at emission time is authoritative.
  input.emissionResolved=particle.nativeMarkerLabel~=nil or nil
  input.preparedAnchor=Adapter.cameraRayPoint(sceneContext.camera,
    particle.material and particle.material.nativeCameraRayDistance
      or event.material and event.material.nativeCameraRayDistance,units)
  local bytes=model and model.fxDispatch
  local row=Adapter.markerRow(actor,event.context) or -1
  if input.markerLabel==nil and bytes and row>=0 and #bytes>=(row+1)*20 then
    input.markerLabel=bytes:byte(row*20+3)
    input.secondaryMarker=bytes:byte(row*20+4)
  end
  return input
end

local function vector(value, fallback)
  fallback = fallback or {0, 0, 0}
  if type(value) ~= "table" then return {fallback[1], fallback[2], fallback[3]} end
  return {
    tonumber(value[1] or value.x) or fallback[1],
    tonumber(value[2] or value.y) or fallback[2],
    tonumber(value[3] or value.z) or fallback[3],
  }
end

local function scaled(value, factor)
  value = vector(value)
  return {value[1] * factor, value[2] * factor, value[3] * factor}
end

-- Common particles are placed relative to their owner (object +8).
-- Lifecycle geometry resolves its own owner/target inputs (beamInputs) in
-- the source frame, so it keeps the source side here.
local function sourceSide(particle)
  local event = particle and particle.event
  local context = event and event.context
  if event and event.descriptorKind == "particle" then return Adapter.ownerSide(context) end
  return context and context.sourceSide or "player"
end

-- Effect geometry and battle models are authored in the same Stadium source
-- coordinate system. In classic mode modelMatrix supplies the per-model
-- conversion; arena mode normally resolves to the field's fixed .05 scale.
function Adapter.worldUnits(sceneContext, side)
  local scene = sceneContext and sceneContext.scene
  local host = scene and scene.host
  local actor = host and host.visualActor and host:visualActor(side)
  if host and actor and host.modelMatrix then
    local ok, matrix = pcall(host.modelMatrix, host, side, actor)
    if ok and type(matrix) == "table" then
      local value = math.sqrt((matrix[1] or 0) ^ 2 + (matrix[5] or 0) ^ 2
        + (matrix[9] or 0) ^ 2)
      if value > 0 then return value end
    end
  end
  if scene and scene.arena then
    return tonumber(host and host.arenaScale) or .05
  end
  return .05
end

local function placementContextFor(particle, sceneContext, side)
  local units = Adapter.worldUnits(sceneContext, side)
  local world = sceneContext.world or {}
  local slot = world.actorSlots and world.actorSlots[side] or world.origin
  local anchor = scaled(slot or {0, world.groundY or 0, 0}, 1 / units)
  local position = vector(particle and particle.position)
  local yaw
  local scene=sceneContext.scene
  local host=scene and scene.host
  local actor=host and host.visualActor and host:visualActor(side)
  local model=actor and actor.renderer and actor.renderer.model
  local dispatch=model and model.fxDispatch
  -- +661 (spawn scale): a move effect reads its own row's byte 0x0F; a
  -- non-move entry keeps the owner's last loaded value (Adapter.markerRow).
  local moveId=tonumber(particle and particle.event and particle.event.context
    and particle.event.context.moveId)
  local moveRow,scaleByte=nil,0x0F
  if moveId and moveId>=1 and moveId<=251 then moveRow=moveId-1
  elseif actor and type(actor.nativeScaleSource)=="table" then
    moveRow,scaleByte=actor.nativeScaleSource.row,actor.nativeScaleSource.byte
  end
  local nativeSpawnScale
  local diagnostics={}
  local contract=particle and (particle.attachment or particle.event and particle.event.attachment)
  if not (particle and particle.nativeAnchor) and contract and contract.flags then
    local op=Attachment.operations(contract.flags)
    local function approximate(code,address,message)
      diagnostics[#diagnostics+1]={code=code,address=address,message=message}
    end
    if not op.zeroAnchor and not op.laneScalar then
      if op.anchorCallback or op.fixedInitialScale and not op.modelAndSavedOrigin then
        approximate("approximate-common-anchor",0x8411DCCC,
          "common-particle anchor uses the source slot; native center height and battle flags are not applied")
      elseif op.modelAndSavedOrigin then
        approximate("approximate-common-model-anchor",0x8003C9B8,
          "common-particle model anchor and saved-origin state are unavailable; using the source slot")
      else
        approximate("approximate-common-shared-origin",0x84104D28,
          "native shared-origin state is unavailable; using the source slot")
      end
    end
    if op.externalScaleOffsetY and not op.zeroAnchorY then
      approximate("approximate-common-anchor-height",0x8411EF90,
        "native attachment height/scale adjustment is not applied; using source-slot height")
    end
  end
  if type(dispatch)=="string" and moveRow and moveRow>=0
      and #dispatch>=(moveRow+1)*20 then
    local f32=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_float")
    nativeSpawnScale=f32(dispatch:byte(moveRow*20+scaleByte+1)*f32(.01))
  end
  if host and actor and host.modelMatrix then
    local ok,matrix=pcall(host.modelMatrix,host,side,actor)
    if ok and type(matrix)=="table" and matrix[3] and matrix[11]
        and (matrix[3]~=0 or matrix[11]~=0) then
      yaw=math.atan2(matrix[3],matrix[11])
    end
  end
  -- Minimal scenes expose only battler slots; their facing is source->target.
  if yaw==nil and world.actorSlots then
    local target=world.actorSlots[side=="player" and "enemy" or "player"]
    if slot and target then
      local a,b=vector(slot),vector(target)
      if a[1]~=b[1] or a[3]~=b[3] then yaw=math.atan2(b[1]-a[1],b[3]-a[3]) end
    end
  end

  return {
    nativeAnchor=particle and particle.nativeAnchor,
    diagnostics=diagnostics,
    commonOffset = position,
    transform = {0, 0, 0},
    motion = {0, 0, 0},
    -- func_84104D28's shared origin is battle-controller state. At this
    -- adapter boundary that controller is represented by the source slot.
    sharedOrigin = anchor,
    anchor = {0, 0, 0},
    scale = 1,
    worldUnits = units,
    sourceSide = side,
    nativeSourceYaw = yaw and math.floor(yaw*65536/(2*math.pi))%65536,
    nativeSpawnScale=nativeSpawnScale,
    nativeContextScale=Dispatch.contextScale(particle and particle.event
      and particle.event.context and (particle.event.context.nativeContextId
        or particle.event.context.moveId),model and model.fxContextScales,dispatch),
    resolvers = {
      anchor = function() return anchor end,
      modelAnchor = function() return anchor end,
      anchorY = function() return anchor[2] end,
      -- func_8411E1D4 returns +1 for the first battler and -1 otherwise.
      laneScalar = function() return side == "player" and 1 or -1 end,
    },
  }
end

-- Only commonOffset, nativeAnchor and (through nativeAnchor) diagnostics
-- depend on the particle itself; everything else is the same for every
-- particle of one event and side. Player:packets supplies a fresh
-- sceneContext.fxPlacementCache per build, so shared parts never outlive
-- a frame. Consumers only read the returned tables.
function Adapter.placementContext(particle, sceneContext)
  sceneContext = type(sceneContext) == "table" and sceneContext or {}
  local side = sourceSide(particle)
  local cache = sceneContext.fxPlacementCache
  local event = particle and particle.event
  if not (cache and event) then
    return placementContextFor(particle, sceneContext, side)
  end
  -- The shared part reads the particle only through: its side, the event
  -- context's move and native context IDs, the contract flags, and whether
  -- the particle has a native anchor. (Particles carry their own copies of
  -- the event, so the key is built from those values.)
  local contract = particle.attachment or event.attachment
  local context = event.context
  local key = side .. "|" .. tostring(context and context.moveId) .. "|"
    .. tostring(context and context.nativeContextId) .. "|"
    .. tostring(contract and contract.flags)
    .. (particle.nativeAnchor ~= nil and "|a" or "")
  local base = cache[key]
  if not base then
    base = placementContextFor(particle, sceneContext, side)
    base.commonOffset, base.nativeAnchor = nil, nil
    cache[key] = base
  end
  local out = {}
  for k, v in pairs(base) do out[k] = v end
  out.commonOffset = vector(particle.position)
  out.nativeAnchor = particle.nativeAnchor
  return out
end

function Adapter.resolvePlacement(contract, context)
  local resolved, err
  if context and context.nativeAnchor then
    resolved={resolved=true,position=Attachment.sum(context.nativeAnchor,
      context.commonOffset or {0,0,0},{0,0,0},{0,0,0}),scale=context.scale}
  else resolved,err=Attachment.resolve(contract, context) end
  if not resolved then return nil, err end
  if not resolved.resolved then return resolved end
  local units = tonumber(context and context.worldUnits) or .05
  resolved.position = scaled(resolved.position, units)
  if type(resolved.scale) == "table" then
    resolved.scale = scaled(resolved.scale, units)
  else
    resolved.scale = (tonumber(resolved.scale) or 1) * units
  end
  return resolved
end

-- Map posed markers and ROM endpoint rules into the host battle frame.
function Adapter.beamInputs(context,sceneContext)
  local slots=sceneContext and sceneContext.world and sceneContext.world.actorSlots
  local source=context.sourceSide or "player"
  local target=context.targetSide or (source=="player" and "enemy" or "player")
  if not slots or not slots[source] or not slots[target] then return nil end
  local units=Adapter.worldUnits(sceneContext,source)
  local origin=scaled(slots[source],1/units)
  local a,b={0,0,0},{}
  local targetPosition=scaled(slots[target],1/units)
  for i=1,3 do b[i]=targetPosition[i]-origin[i] end
  local actors=sceneContext.scene and sceneContext.scene.actors
  local host=sceneContext.scene and sceneContext.scene.host
  local usedMarkers,profiles=0,0
  local swiftTarget,modelScale,sourceSpecies,sourceCenter
  local ribbonAnchor,ribbonTargetScale
  local ribbonOwnerAnchor,ribbonUpdateAnchor,ribbonOwnerScale
  -- 8410874C selects the target as +194 for the hit/alternate context;
  -- +198 remains the attacker and +19C remains the target.
  local owner=context.nativeOwnerSide or (context.alternate and target or source)
  for _,pair in ipairs({{source,a},{target,b}}) do
    local actor=host and host.visualActor and host:visualActor(pair[1])
      or actors and actors[pair[1]]
    local renderer=actor and actor.renderer
    local model=renderer and renderer.model
    if pair[1]==source then sourceSpecies=model and model.species end
    local profile=Dispatch.battleProfile(model and model.fxBattleProfile)
    local position=scaled(slots[pair[1]],1/units)
    local height=0
    if not profile and renderer and renderer.worldMetrics then
      local ok,metrics=pcall(renderer.worldMetrics,renderer)
      if ok and metrics then height=metrics.height*.5 end
    end
    local bytes=model and model.fxDispatch
    local moveRow=(tonumber(context.moveId) or 0)-1
    if pair[1]==source and bytes and moveRow>=0 and #bytes>=(moveRow+1)*20 then
      -- 8411AF6C copies dispatch +0F to owner+661; 84109544 multiplies by .01f.
      local f32=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_float")
      modelScale=f32(bytes:byte(moveRow*20+16)*f32(.01))
    end
    local isTarget=pair[1]==target
    -- Target marker always comes from context 254, but its offset comes from
    -- the currently selected animation (84114730), including idle/hit.
    local current=renderer and renderer.fxDispatchRow
      or Dispatch.CONTEXT_ENTRY[actor and actor.context or "idle"] or 251
    local row=isTarget and 254 or (renderer and renderer.fxDispatchRow)
      or (tonumber(context.moveId) or 0)-1
    local offsetRow=isTarget and current or row
    if bytes and offsetRow>=0 and #bytes>=(offsetRow+1)*20 then
      local f32=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_float")
      local scale=f32(bytes:byte(offsetRow*20+16)*f32(.01))
      if isTarget then ribbonTargetScale=scale end
      if pair[1]==owner then ribbonOwnerScale=scale end
    end
    local point,rotation,center
    local offset={0,0,0}
    local matrix
    if host and host.modelMatrix and actor then
      local ok,value=pcall(host.modelMatrix,host,pair[1],actor)
      if ok and type(value)=="table" then matrix=value end
    end
    if matrix then
      local scale=math.sqrt(matrix[1]^2+matrix[5]^2+matrix[9]^2)
      local function transform(p)
        local result={}
        for k=1,3 do
          local at=(k-1)*4
          result[k]=(matrix[at+1]*p[1]+matrix[at+2]*p[2]
            +matrix[at+3]*p[3]+matrix[at+4])/units
        end
        return result
      end
      if profile then
        height=profile.targetHeight*scale/units
        center=transform({0,profile.centerY,0})[2]
        if bytes and row>=0 and #bytes>=(row+1)*20
            and offsetRow>=0 and #bytes>=(offsetRow+1)*20 then profiles=profiles+1 end
      end
      rotation={}
      for k=1,3 do for j=1,3 do
        rotation[(k-1)*3+j]=scale>0 and matrix[(k-1)*4+j]/scale
          or (k==j and 1 or 0)
      end end
      if bytes and row>=0 and #bytes>=(row+1)*20 and renderer.attachmentPosition then
        local localPoint=renderer:attachmentPosition(bytes:byte(row*20+3))
        if localPoint then point=transform(localPoint);usedMarkers=usedMarkers+1 end
      end
      if bytes and offsetRow>=0 and #bytes>=(offsetRow+1)*20 then
        for k=1,3 do
          local value=bytes:byte(offsetRow*20+12+k)
          offset[k]=value>=128 and value-256 or value
        end
      end
    end
    if not isTarget then
      sourceCenter=Endpoints.resolve({position=position,centerY=center or position[2]+height,
        flags=actor and actor.nativeFxFlags or 0,offset=offset,rotation=rotation},false)
      if profile and matrix then
        ribbonAnchor={}
        for k=1,3 do ribbonAnchor[k]=sourceCenter[k]-origin[k] end
      end
    end
    if pair[1]==owner and profile and matrix and bytes and offsetRow>=0
        and #bytes>=(offsetRow+1)*20 then
      local currentPoint
      if renderer.attachmentPosition then
        local p=renderer:attachmentPosition(bytes:byte(offsetRow*20+3))
        if p then
          currentPoint={}
          for k=1,3 do local j=(k-1)*4
            currentPoint[k]=(matrix[j+1]*p[1]+matrix[j+2]*p[2]+matrix[j+3]*p[3]+matrix[j+4])/units
          end
        end
      end
      local input={position=position,centerY=center,flags=actor.nativeFxFlags or 0,
        offset=offset,rotation=rotation}
      ribbonOwnerAnchor=Endpoints.resolve(input,false)
      input.marker=currentPoint
      ribbonUpdateAnchor=Endpoints.resolve(input,false)
      for k=1,3 do
        ribbonOwnerAnchor[k]=ribbonOwnerAnchor[k]-origin[k]
        ribbonUpdateAnchor[k]=ribbonUpdateAnchor[k]-origin[k]
      end
    end
    if isTarget then
      swiftTarget=Endpoints.resolve({position=position,centerY=center or position[2]+height,
        flags=actor and actor.nativeFxFlags or 0,offset=offset,rotation=rotation},false)
      swiftTarget[2]=math.max(0,swiftTarget[2])
      for k=1,3 do swiftTarget[k]=swiftTarget[k]-origin[k] end
    end
    local resolved=Endpoints.resolve({position=position,marker=point,
      centerY=center or position[2]+height,targetHeight=height,
      flags=actor and actor.nativeFxFlags or 0,offset=offset,rotation=rotation},isTarget)
    for k=1,3 do pair[2][k]=resolved[k]-origin[k] end
  end
  local direction={b[1]-a[1],b[2]-a[2],b[3]-a[3]}
  local length=math.sqrt(direction[1]^2+direction[2]^2+direction[3]^2)
  if length==0 then return nil end
  for i=1,3 do direction[i]=direction[i]/length end
  local eye=sceneContext.camera and sceneContext.camera.eye
  local camera
  if eye then
    camera=scaled(eye,1/units)
    for i=1,3 do camera[i]=camera[i]-origin[i] end
  end
  local swiftDirection={swiftTarget[1]-a[1],swiftTarget[2]-a[2],swiftTarget[3]-a[3]}
  local swiftLength=math.sqrt(swiftDirection[1]^2+swiftDirection[2]^2+swiftDirection[3]^2)
  for i=1,3 do swiftDirection[i]=swiftLength>0 and swiftDirection[i]/swiftLength or 0 end
  local terrainCamera
  local c=sceneContext.camera
  if c and c.eye and c.focus and c.projection then
    local p=c.projection
    terrainCamera={eye=scaled(c.eye,1/units),focus=scaled(c.focus,1/units),up=c.up or {0,1,0},
      fov=c.fovDegrees or 2*math.atan(1/math.abs(p[6]))*180/math.pi,
      aspect=math.abs(p[6]/p[1]),near=math.abs(p[12]/(p[11]-1))/units}
  end
  return {origin=a,direction=direction,swiftDirection=swiftDirection,terrainCamera=terrainCamera,
    ribbonAnchor=ribbonAnchor,ribbonTargetScale=ribbonTargetScale,
    ribbonOwnerAnchor=ribbonOwnerAnchor,ribbonOwnerScale=ribbonOwnerScale,ribbonUpdateAnchor=ribbonUpdateAnchor,
    swiftOrigin={a[1]+origin[1],a[2]+origin[2],a[3]+origin[3]},swiftFrameOrigin=origin,
    modelScale=modelScale,sourceSpecies=sourceSpecies,sourceCenter=sourceCenter,endpointA=a,endpointB=b,cameraEye=camera,
    approximate=profiles<2,attachmentCount=usedMarkers}
end

local function diagnosticText(value)
  if type(value) ~= "table" then return tostring(value) end
  return ("%s (move FX effect=%s program=%s address=%s)"):format(
    tostring(value.message or value.code or "diagnostic"),
    tostring(value.effectId or "?"), tostring(value.programId or "?"),
    value.address and ("0x%08X"):format(value.address) or "?")
end

function Adapter.new(importer, options)
  options = type(options) == "table" and options or {}
  if type(importer) ~= "table" or type(importer.betaBattleFxEnabled) ~= "function"
      or not importer.betaBattleFxEnabled() then
    return nil
  end
  if type(importer.newBattleFxPlayer) ~= "function" then
    return nil, "battle FX player factory is unavailable"
  end

  local self = setmetatable({warn = options.warn, warningKeys = {},
    sendOutEnabled = importer.battleFxSendOutEnabled}, Adapter)
  local player, err = importer.newBattleFxPlayer({
    resolveBeam = Adapter.beamInputs,
    contextForParticle = Adapter.placementContext,
    commonAnchorInputs = Adapter.commonAnchorInputs,
    emissionMarkers = Adapter.emissionMarkers,
    battleStateForContext = Adapter.battleState,
    contextNeedsSnapshot = false,
    resolvePlacement = Adapter.resolvePlacement,
    warn = function(value) self:_warn(value) end,
  })
  if not player then return nil, err end
  self.player = player
  if type(importer.logBattleFxSettings) == "function" then pcall(importer.logBattleFxSettings) end
  return self
end

function Adapter:_warn(value)
  local message = diagnosticText(value)
  if self.warningKeys[message] then return end
  self.warningKeys[message] = true
  if type(self.warn) == "function" then pcall(self.warn, message) end
end

local function sides(source)
  source = source == "enemy" and "enemy" or "player"
  return source, source == "player" and "enemy" or "player"
end

-- Injected players may predate the optional sequencing hooks.
function Adapter:_routeSignal(value)
  local player = self.player
  if player and type(player.setRouteSignal) == "function" then
    return player:setRouteSignal(value)
  end
  return false
end

function Adapter:trigger(moveId, source, alternate, variant)
  if not self.player then return nil, "battle FX player is unavailable" end
  local target
  source, target = sides(source)
  local effect, err = self.player:trigger({
    moveId = tonumber(moveId), sourceSide = source,
    targetSide = target,
    alternate = alternate == true, variant = variant == true or nil, condition = 0,
  })
  if not effect and err then self:_warn(err) end
  if effect then
    self:finish()
    self.activeEffect=effect
    -- 841086F0/84108728/841088CC route state consulted by 84108974.
    self.routeMove, self.routeMode = tonumber(moveId), variant == true and 1
      or (alternate == true and 2 or 0)
    -- 841086F0 clears D_841901B8; 8410874C sets it again for the impact.
    self:_routeSignal(alternate == true and 1 or 0)
  end
  return effect, err
end

-- Route mode 0 (84108728): the move bank at the start of the move.
function Adapter:playMove(moveId, source)
  return self:trigger(moveId, source, false)
end

-- Route mode 1 (841088CC): the +2 half of a two-turn move's variant route.
-- 841088CC arms D_841901A8 only for Dig.
function Adapter:playVariant(moveId, source)
  local effect, err = self:trigger(moveId, source, false, true)
  if effect and tonumber(moveId) == Sequence.DIG then self.digVariantArmed = true end
  return effect, err
end

-- Charge turn of a two-turn move: the attacker's state plays its charge row
-- and fires the variant route at that row's byte 0x0B (Sequence.chargeFrames).
function Adapter:playCharge(moveId, source, actor)
  local model = actor and actor.renderer and actor.renderer.model
  local entry, _, frame = Sequence.chargeFrames(model and model.fxDispatch, moveId)
  if not entry then return nil, "not a two-turn move" end
  if not frame then
    self:_warn({code = "unresolved-charge-frame", message =
      ("charge row %d is unavailable; move %s charge effect not played"):format(entry, tostring(moveId))})
    return nil, "charge row unavailable"
  end
  self.pendingVariants = self.pendingVariants or {}
  self.pendingVariants[#self.pendingVariants + 1] = {moveId = moveId, source = source,
    frame = (self.player and self.player.runtime and self.player.runtime.frame or 0) + frame}
  return true
end

function Adapter:_firePendingVariants()
  local pending = self.pendingVariants
  if not pending or #pending == 0 then return end
  local frame = self.player and self.player.runtime and self.player.runtime.frame or 0
  local kept = {}
  for _, item in ipairs(pending) do
    if frame >= item.frame then self:playVariant(item.moveId, item.source)
    else kept[#kept + 1] = item end
  end
  self.pendingVariants = kept
end

-- 8410890C(id, owner): latch the signal and play FX entry `id` (entries
-- 252..301 are non-move battle effects) with `owner` as the source.
function Adapter:signalEffect(id, owner)
  if not self.player or type(self.player.playEntry) ~= "function" then
    return nil, "battle FX player cannot play FX entries"
  end
  local source, target = sides(owner)
  if type(self.player.signalContext) == "function" then self.player:signalContext(tonumber(id)) end
  -- User option (POKE BALL, non-native): OFF skips the send-out effect.
  if tonumber(id) == Sequence.SEND_OUT_ENTRY and type(self.sendOutEnabled) == "function" then
    local ok, enabled = pcall(self.sendOutEnabled)
    if ok and enabled == false then return nil end
  end
  local effect, err = self.player:playEntry(id, {sourceSide = source,
    targetSide = target, condition = 0})
  if not effect and err then self:_warn(err) end
  return effect, err
end

-- 841087B8 at the attacker's hit frame. `nativeResult` is the raw battle
-- result byte (D_84193DD0+9); nil is treated as an ordinary result.
function Adapter:impact(moveId, source, nativeResult)
  if not self.player then return nil, "battle FX player is unavailable" end
  local action = Sequence.impactAction(moveId, nativeResult)
  local effect, err
  if action == "impact" then
    -- 8410874C: the impact bank starts alongside the running move bank.
    local target
    source, target = sides(source)
    effect, err = self.player:trigger({moveId = tonumber(moveId),
      sourceSide = source, targetSide = target, alternate = true, condition = 0})
    if not effect and err then self:_warn(err) end
    self.routeMove, self.routeMode = tonumber(moveId), 2
    self:_routeSignal(1)
    self:_defenderReaction(target, source, moveId)
  elseif action == "owner" then
    -- 8410878C only selects mode 2 and the owner; nothing new is dispatched.
    self.routeMode = 2
    self:_routeSignal(1)
  elseif action == "fail" then
    if type(self.player.abortAll) == "function" then self.player:abortAll() end
    -- 84108974(1): Dig still in route mode 1 signals entry 0x12D.
    if self.digVariantArmed and self.routeMode == 1 and self.routeMove == Sequence.DIG then
      self.digVariantArmed = false
      effect, err = self:signalEffect(Sequence.DIG_FAILURE_ENTRY, source)
    end
  end
  return action, effect, err
end

-- The hit-frame states 84116EB4/841170A0/84117948/84118138/841182E0 run on
-- the defender and select context 254 (0xFE, its hit clip) through
-- 84112158. Hosts install `onImpact(target, source, moveId)` to play that
-- clip. The ROM starts it when the defender's state begins, before the
-- impact; starting it with the impact is approximate and reported once.
-- 84117948 also withholds it for results 2/5/6 and move 0xD4, but which
-- moves run that state is not decoded, so no result gating is applied.
function Adapter:_defenderReaction(target, source, moveId)
  if type(self.onImpact) ~= "function" then return false end
  local ok, played, reason = pcall(self.onImpact, target, source, tonumber(moveId))
  if not ok then
    self:_warn({code = "unsupported-defender-reaction", message = tostring(played)})
    return false
  end
  if played then
    self:_warn({code = "approximate-defender-reaction-timing", message =
      "defender hit clip (context 254) starts with the impact; the ROM starts it when the defender's hit state begins"})
  elseif reason then
    self:_warn({code = "unresolved-defender-reaction", message = tostring(reason)})
  end
  return played and true or false
end

-- 84108A10(owner): release the owner's held particles.
function Adapter:releaseHeld(owner)
  if not self.player or type(self.player.releaseHeld) ~= "function" then return 0 end
  return self.player:releaseHeld(sides(owner))
end

-- Dispatch hit frame (row +0x0B) for the attacker's current species model.
function Adapter.hitFrame(sceneContext, source, moveId)
  sceneContext = sceneContext or {}
  local scene = sceneContext.scene or {}
  local actor = scene.host and scene.host.visualActor and scene.host:visualActor(source)
    or scene.actors and scene.actors[source]
  local model = actor and actor.renderer and actor.renderer.model
  return Sequence.hitFrame(model and model.fxDispatch, moveId)
end

-- Queue 841087B8 to run `ticks` 30 Hz ticks after now. Hosts that do not
-- emulate the actor state machine start this count at the move start; the
-- native count restarts when the attack state is entered (after any
-- approach phase), so this timing is an approximation and is reported.
function Adapter:scheduleImpact(moveId, source, ticks, nativeResult, native)
  if not self.player then return nil, "battle FX player is unavailable" end
  ticks = tonumber(ticks)
  if not ticks or ticks < 0 then
    self:_warn({code = "unresolved-impact-frame", message =
      ("move %s has no dispatch hit frame; impact bank not scheduled"):format(tostring(moveId))})
    return nil, "impact frame unavailable"
  end
  if not native then
    self:_warn({code = "approximate-impact-timing", message =
      "impact bank is timed from the move start by the dispatch hit frame; attack-state approach phases are not emulated"})
  end
  self.pendingImpacts = self.pendingImpacts or {}
  self.pendingImpacts[#self.pendingImpacts + 1] = {moveId = moveId, source = source,
    result = nativeResult, frame = (self.player.runtime and self.player.runtime.frame or 0) + math.floor(ticks)}
  return true
end

-- Facts for Sequence.resultByte from the host's battle.damage_dealt event
-- (Gen 1 EffectRegistry and Gen 2 Battle:dealDamage emit it per landed hit
-- while the turn resolves, before the move animation is presented). Kept per
-- attacking side in arrival order; a move start takes the oldest entry for
-- its move and drops older entries for other moves. A landed hit of an OHKO
-- move (EFFECT_OHKO / Gen 1 OHKO_EFFECT) is 8412A804's D_841951E4 = 2, and
-- EFFECT_ROLLOUT is effect 0x75 (pokecrystal move_effect_constants).
local OHKO_EFFECTS = {EFFECT_OHKO = true, OHKO_EFFECT = true}
local EFFECT_IDS = {EFFECT_ROLLOUT = 0x75}
local hitFacts = {player = {}, enemy = {}}

local function payloadMoveId(ev)
  local id = tonumber(ev.moveId)
  if id then return id end
  local move = ev.move
  if type(move) == "number" then return move end
  if type(move) == "table" then return tonumber(move.index or move.number) end
  return nil
end

function Adapter.recordHit(ev)
  if type(ev) ~= "table" then return false end
  local side
  if ev.side == "player" or ev.side == "enemy" then
    side = ev.side == "player" and "enemy" or "player" -- Gen 2 names the defender
  elseif type(ev.user) == "table" and ev.user.isPlayer ~= nil then
    side = ev.user.isPlayer and "player" or "enemy"
  end
  local moveId = payloadMoveId(ev)
  if not side or not moveId then return false end
  local list = hitFacts[side]
  local last = list[#list]
  -- Later hits of one multi-hit move add nothing: 84124A7C runs per hit
  -- but the record presented at the hit frame is the first one.
  if last and last.moveId == moveId then return true end
  local effect = type(ev.move) == "table" and ev.move.effect or nil
  list[#list + 1] = {moveId = moveId, damaging = true,
    critical = ev.crit == true, ohko = OHKO_EFFECTS[effect] == true,
    moveEffect = EFFECT_IDS[effect],
    typeModifier = tonumber(ev.effectiveness or ev.typeMult)}
  -- Entries nobody presents (FX disabled, cancelled animations) must not pile up.
  while #list > 8 do table.remove(list, 1) end
  return true
end

function Adapter.clearHits()
  hitFacts = {player = {}, enemy = {}}
end

function Adapter.takeHitResult(side, moveId)
  local list = hitFacts[side]
  moveId = tonumber(moveId)
  if not list or not moveId then return nil, "no battle facts for this move" end
  while #list > 0 do
    local facts = table.remove(list, 1)
    if facts.moveId == moveId then return Sequence.resultByte(facts) end
  end
  return nil, "no battle facts for this move"
end

-- Host entry point: move bank now, impact bank at the attacker's dispatch
-- hit frame. `actor` is the host visual actor whose model carries the
-- species animation-dispatch rows (model.fxDispatch).
-- `target` is the defending actor; its own species row times the impact
-- (Sequence.attackTiming). Without it the impact falls back to the
-- attacker's hit frame and says so.
function Adapter:playMoveAndImpact(moveId, source, actor, nativeResult, target)
  if nativeResult == nil then nativeResult = Adapter.takeHitResult(source, moveId) end
  local model = actor and actor.renderer and actor.renderer.model
  local targetModel = target and target.renderer and target.renderer.model
  local timing = Sequence.attackTiming(model and model.fxDispatch, moveId,
    {species = actor and actor.dex, defenderDispatch = targetModel and targetModel.fxDispatch})
  if not timing then
    -- No row: the previous approximation (move now, impact at the hit frame).
    local effect, err = self:playMove(moveId, source)
    self:scheduleImpact(moveId, source, Sequence.hitFrame(model and model.fxDispatch, moveId), nativeResult)
    return effect, err
  end
  for _, d in ipairs(timing.diagnostics) do self:_warn(d) end
  moveId = tonumber(moveId)
  -- 84114BF4: route and sound at the attacker's hit frame; some species play
  -- only the sound; Curse's route needs result bit 0x80.
  local routed = not timing.soundOnly and (moveId ~= Sequence.CURSE
    or math.floor((tonumber(nativeResult) or 0) / 0x80) % 2 == 1)
  local ticks = timing.route or 0
  if routed then self:scheduleRoute(moveId, source, ticks) end
  -- 841153DC (Rest): at the hit frame, entry 0x100 on the user.
  if moveId == Sequence.REST then self:scheduleSignal(Sequence.REST_ENTRY, source, ticks) end
  if timing.impact then
    self:scheduleImpact(moveId, source, timing.impact, nativeResult, true)
  else
    self:_warn({code = "approximate-impact-timing", message =
      "defender row unavailable; impact timed from the attacker's hit frame"})
    self:scheduleImpact(moveId, source, timing.route, nativeResult, true)
  end
  return true
end

-- The move route (84108728) `ticks` frames from now. A host finish that
-- arrives first is carried over: the route is released after the same time
-- the host allowed since the move started.
function Adapter:scheduleRoute(moveId, source, ticks)
  local now = self.player and self.player.runtime and self.player.runtime.frame or 0
  ticks = math.max(0, math.floor(tonumber(ticks) or 0))
  self.pendingRoute, self.pendingFinish = nil, nil -- a newer move supersedes
  if ticks == 0 then return self:playMove(moveId, source) end
  self:finish()
  self.pendingRoute = {moveId = moveId, source = source, frame = now + ticks, queued = now}
  return true
end

function Adapter:_firePendingRoute()
  local route = self.pendingRoute
  if not route then return end
  local now = self.player and self.player.runtime and self.player.runtime.frame or 0
  if now < route.frame then return end
  self.pendingRoute = nil
  self:playMove(route.moveId, route.source)
  if route.finishAfter then self.pendingFinish = {frame = now + route.finishAfter} end
end

-- Queue 8410890C(entry) for `owner`, `ticks` 30 Hz ticks from now.
function Adapter:scheduleSignal(entry, owner, ticks)
  if not self.player then return nil, "battle FX player is unavailable" end
  self.pendingSignals = self.pendingSignals or {}
  self.pendingSignals[#self.pendingSignals + 1] = {entry = entry, owner = owner,
    frame = (self.player.runtime and self.player.runtime.frame or 0) + math.max(0, math.floor(tonumber(ticks) or 0))}
  return true
end

-- Faint effects on the fainting side, timed from its context-253 row
-- (Sequence.faintFrames). The counter starts with the host's faint clip.
function Adapter:playFaint(side, actor)
  local model = actor and actor.renderer and actor.renderer.model
  local first, second = Sequence.faintFrames(model and model.fxDispatch)
  if not first then
    self:_warn({code = "unresolved-faint-frames", message = "faint row 253 is unavailable; faint effects not played"})
    return false
  end
  local marker = Dispatch.contextMarker(Sequence.FAINT_ENTRIES.first,
    model.fxContextScales, model.fxDispatch)
  if marker ~= 0xFF then self:scheduleSignal(Sequence.FAINT_ENTRIES.first, side, first) end
  self:scheduleSignal(Sequence.FAINT_ENTRIES.second, side, second)
  return true
end

function Adapter:_firePendingSignals()
  local pending = self.pendingSignals
  if not pending or #pending == 0 then return end
  local frame = self.player and self.player.runtime and self.player.runtime.frame or 0
  local kept = {}
  for _, item in ipairs(pending) do
    if frame >= item.frame then self:signalEffect(item.entry, item.owner)
    else kept[#kept + 1] = item end
  end
  self.pendingSignals = kept
end

function Adapter:_firePendingImpacts()
  local pending = self.pendingImpacts
  if not pending or #pending == 0 then return end
  local frame = self.player and self.player.runtime and self.player.runtime.frame or 0
  local kept = {}
  for _, item in ipairs(pending) do
    if frame >= item.frame then self:impact(item.moveId, item.source, item.result)
    else kept[#kept + 1] = item end
  end
  self.pendingImpacts = kept
end

function Adapter:finish()
  local route = self.pendingRoute
  if route and not route.finishAfter then
    local now = self.player and self.player.runtime and self.player.runtime.frame or 0
    route.finishAfter = math.max(0, now - route.queued)
    return true
  end
  if not self.player or not self.activeEffect then return false end
  local effect=self.activeEffect
  self.activeEffect=nil
  return self.player:finish(effect)
end

function Adapter:signalContext(id)
  return self.player and self.player:signalContext(id) or false
end

function Adapter:update(dt)
  if self.player then
    local frame = self.player:update(dt)
    self:_firePendingRoute()
    local now = self.player.runtime and self.player.runtime.frame or 0
    if self.pendingFinish and now >= self.pendingFinish.frame then
      self.pendingFinish = nil
      self:finish()
    end
    self:_firePendingImpacts()
    self:_firePendingSignals()
    self:_firePendingVariants()
    return frame
  end
end

function Adapter:draw(sceneContext)
  if not self.player then return nil end
  local ok, result = pcall(self.player.draw, self.player, sceneContext)
  if not ok then self:_warn(result); return nil end
  return result
end

function Adapter:backgroundColor(base)
  return self.player and self.player:backgroundColor(base) or base
end

function Adapter:release()
  self.pendingRoute, self.pendingFinish = nil, nil
  self.pendingImpacts = nil
  if not self.player then return false end
  local player = self.player
  self.player = nil
  return player:release()
end

return Adapter
