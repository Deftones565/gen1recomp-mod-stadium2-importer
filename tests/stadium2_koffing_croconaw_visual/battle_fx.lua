-- The viewer uses the same persistent player and placement adapter as battles.
local Player = require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_player")
local Adapter = require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_battle_adapter")
local Rom = require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_rom")
local Resources = require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_resources")
local Preview = {}
Preview.__index = Preview

function Preview.new(options)
  return setmetatable({options=options, frame=0, diagnostics={}, active=false}, Preview)
end

function Preview:release()
  if self.player then self.player:release(); self.player=nil end
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
    resolvePlacement=Adapter.resolvePlacement,
    warn=function(diagnostic)
      self.diagnostics[#self.diagnostics+1]=diagnostic
      if options.warn then options.warn(diagnostic) end
    end,
    loadRenderer=function(id, shapeId)
      local model, modelError
      if resources then
        local shape
        shape, modelError=Resources.shapeFromResolved(resources, shapeId)
        if shape then model, modelError=Resources.modelFromShape(shape,
          ("stadium2_move_%03d_shape_%03d"):format(id, shapeId)) end
      else
        model, modelError=options.importer.battleFxShapeModel(id, shapeId)
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
  local effect, triggerError=self.player:trigger({moveId=moveId,
    sourceSide=side, targetSide=side=="player" and "enemy" or "player",
    alternate=alternate==true, condition=0})
  if not effect then self:release(); return nil, triggerError end
  self.active=true
  return effect
end

function Preview:update(dt)
  if self.active then
    self.player:update(dt)
    self.frame=self.player:snapshot().frame
  end
end

function Preview:step()
  if self.active then
    self.player.runtime:step(1)
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
