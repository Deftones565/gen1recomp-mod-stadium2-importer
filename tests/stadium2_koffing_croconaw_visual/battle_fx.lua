-- The viewer uses the same persistent player and placement adapter as battles.
local Player = require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_player")
local Adapter = require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_battle_adapter")
local Rom = require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_rom")
local Resources = require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_resources")
local Sequence = require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_sequence")
local Preview = {}
Preview.__index = Preview

function Preview.new(options)
  return setmetatable({options=options, frame=0, diagnostics={}, active=false}, Preview)
end

function Preview:release()
  if self.player then self.player:release(); self.player=nil end
  self.effectId=nil
  self.impactEffectId=nil
  self.pendingImpact=nil
  self.active=false
  self.nativeColor=nil
end

function Preview:start(moveId, side, alternate, sceneContext)
  self:release()
  self.frame, self.diagnostics, self.drawn = 0, {}, 0
  self.traceFrame=nil
  local options, catalog, err = self.options
  if options.rom then
    if not self.catalog then self.catalog, err=Rom.catalog(options.rom) end
    catalog=self.catalog
  else
    catalog, err=options.importer.battleFxCatalog()
  end
  if not catalog then return nil, err end
  local move=catalog.moves[moveId]
  if not move then return nil, "move ID out of range" end
  local resources
  if options.rom then
    resources, err=Resources.resolve(options.rom:sub(Resources.ROM_START+1,
      Resources.ROM_END), move.resources)
    if not resources then return nil, err end
  end
  self.player=Player.new({catalog=catalog, runtimeOptions=options.runtimeOptions,
    sceneContext=sceneContext or self.sceneContext,
    resolveBeam=Adapter.beamInputs,
    loadBeamTexture=function(id,symbol)
      return Resources.beamTexture(resources or options.importer.battleFxResources(id),symbol)
    end,
    loadWaveGridTexture=function(id,family)
      local resolved=resources or options.importer.battleFxResources(id)
      return Resources.waveGridTexture(resolved,family)
    end,
    createGeometryRenderer=function(model)
      return options.importer.newRendererFromModel(model,
        {textureFilter="nearest",flipY=false,shaderStyleProvider=options.shaderStyleProvider})
    end,
    contextForParticle=Adapter.placementContext,
    commonAnchorInputs=Adapter.commonAnchorInputs,
    emissionMarkers=Adapter.emissionMarkers,
    battleStateForContext=Adapter.battleState,
    contextNeedsSnapshot=false,
    resolvePlacement=Adapter.resolvePlacement,
    warn=function(diagnostic)
      self.diagnostics[#self.diagnostics+1]=diagnostic
      if options.warn then options.warn(diagnostic) end
    end,
    loadRenderer=function(id, shapeId, animationId)
      local model, modelError
      if resources then
        local shape
        shape, modelError=Resources.shapeFromResolved(resources, shapeId, animationId)
        if shape then model, modelError=Resources.modelFromShape(shape,
          ("stadium2_move_%03d_shape_%03d"):format(id, shapeId)) end
      else
        model, modelError=options.importer.battleFxShapeModel(id, shapeId, animationId)
      end
      if not model then return nil, modelError end
      local ok, renderer, rendererError=pcall(options.importer.newRendererFromModel,
        model, {textureFilter="nearest",shaderStyleProvider=options.shaderStyleProvider})
      if not ok or not renderer then
        options.releaseModel(model)
        return nil, ok and rendererError or renderer
      end
      if os.getenv("STADIUM2_VISUAL_FX_TRACE")=="1" then
        local part=renderer.parts and renderer.parts[1]
        print("[stadium2-rom-fx] mesh",shapeId,part and #part.rows,
          part and table.concat(part.rows[1],","),
          part and table.concat(part.prim.idx,","))
      end
      return renderer, model
    end,
    releaseRenderer=function(renderer, model)
      if renderer and renderer.release then pcall(renderer.release,renderer) end
      if model then options.releaseModel(model) end
    end,
  })
  -- `alternate` may be "variant" for route mode 1 (841088CC), or
  -- "sequence": move bank now, impact bank at the attacker's hit frame.
  local target=side=="player" and "enemy" or "player"
  local function route(alternateBank,variant)
    return self.player:trigger({moveId=moveId,sourceSide=side,targetSide=target,
      alternate=alternateBank,variant=variant or nil,condition=0,
      nativeBattleState=options.nativeBattleState or
        {resultFlags=0,sourceStatus=0,ownerStatusPattern=0}})
  end
  local effect, triggerError=route(alternate==true, alternate=="variant")
  if not effect then self:release(); return nil, triggerError end
  self.effectId=effect
  self.active=true
  self.impactNote=nil
  if alternate=="sequence" then
    self.triggerImpact=function() return route(true) end
    if moveId>251 then
      self.impactNote="non-move entry: no impact bank"
    else
      -- Dispatch row +0x0B (841146D4 -> actor+0x619), counted from the move
      -- start; the ROM counts from the attack state after any approach.
      local hit=Adapter.hitFrame(sceneContext or self.sceneContext,side,moveId)
      if hit==nil or hit<0 then
        self.impactNote=("no dispatch hit frame for move %d; impact skipped"):format(moveId)
      else
        self.pendingImpact={frame=self.player.runtime.frame+hit,hit=hit}
      end
    end
  end
  return effect
end

-- Fire the scheduled impact (841087B8 -> 8410874C) once its frame is due.
function Preview:_checkImpact()
  local pending=self.pendingImpact
  if not (pending and self.player) then return end
  if self.player.runtime.frame<pending.frame then return end
  self.pendingImpact=nil
  local effect,err=self.triggerImpact()
  if effect then
    self.impactEffectId=effect
    if self.player.setRouteSignal then self.player:setRouteSignal(1) end
    if self.onImpact then pcall(self.onImpact,effect) end
  else
    self.impactNote="impact bank failed: "..tostring(err)
  end
end

function Preview:finish()
  if self.player then self.player:signalContext(300) end
  if not self.active or not self.player or not self.effectId then return false end
  return self.player:finish(self.effectId)
end

function Preview:update(dt)
  if self.active then
    self.player:update(dt)
    self:_checkImpact()
    self.frame=self.player:snapshot().frame
  end
end

function Preview:step()
  if self.active then
    self.player.runtime:step(1)
    self:_checkImpact()
    self.frame=self.player:snapshot().frame
  end
end

function Preview:draw(context)
  self.sceneContext=context
  if not self.active then return end
  local result=self.player:draw(context)
  self.drawn=result.drawn
  self.nativeColor=result.nativeColor
  if os.getenv("STADIUM2_VISUAL_FX_TRACE")=="1" and self.traceFrame~=self.frame then
    self.traceFrame=self.frame
    for index,packet in ipairs(result.packets or {}) do
      if index>3 then break end
      print(("[stadium2-rom-fx] frame=%d shape=%s age=%s position=(%.5f,%.5f,%.5f) scale=(%.5f,%.5f,%.5f)")
        :format(self.frame,tostring(packet.shapeId),tostring(packet.age),
          packet.position[1],packet.position[2],packet.position[3],
          packet.scale[1],packet.scale[2],packet.scale[3]))
    end
  end
  return result
end

function Preview:drawBackground(context)
  if not self.active then return end
  local g=context.graphics
  if not g or not g.clear then return end
  local bands=context.environment and context.environment.bands
  local clear=self.player:backgroundColor(bands and bands[1] or {0,0,0})
  g.clear(clear[1],clear[2],clear[3],1,true,true)
end

return Preview
