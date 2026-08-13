-- Shared Stadium battle presentation surface.
--
-- Generation adapters decide WHAT is visible and WHEN. This module only owns
-- HOW the stage, camera, shadows and model renderers become a window-sized
-- image. It deliberately has no knowledge of turn order, capture rolls,
-- battle queues or generation-specific phase names.
local Renderer = require("mods.STADIUM2_IMPORTER.lib.renderer")
local Camera = require("mods.STADIUM2_IMPORTER.lib.battle_camera")
local Stage = require("mods.STADIUM2_IMPORTER.lib.battle_stage")
local Shadow = require("mods.STADIUM2_IMPORTER.lib.battle_shadow")
local Sky = require("mods.STADIUM2_IMPORTER.lib.battle_sky")
local Hud = require("mods.STADIUM2_IMPORTER.lib.battle_hud")
local AA = require("mods.STADIUM2_IMPORTER.lib.battle_aa")

local Scene = {}
Scene.__index = Scene
local unpack=table.unpack or unpack

local function clamp(value,lo,hi)
  return math.max(lo,math.min(hi,tonumber(value) or lo))
end

local function mul(a,b) return Renderer.matMul(a,b) end
local function translate(x,y,z)
  return {1,0,0,x,0,1,0,y,0,0,1,z,0,0,0,1}
end
local function scale(value)
  return {value,0,0,0,0,value,0,0,0,0,value,0,0,0,0,1}
end
local function rotateY(angle)
  local c,s=math.cos(angle),math.sin(angle)
  return {c,0,s,0,0,1,0,0,-s,0,c,0,0,0,0,1}
end

local function hasDynamicObjectHandler(actor)
  local records=actor and actor.renderer and actor.renderer.model
    and actor.renderer.model.handlers and actor.renderer.model.handlers.records
  for _,record in ipairs(type(records)=="table" and records or {}) do
    if record.descriptor==0x81000070 then return true end
  end
  return false
end

function Scene.init(self,opts)
  opts=opts or {}
  self.actors=opts.actors or self.actors or {}
  self.canvas,self.presentCanvas,self.depth=nil,nil,nil
  self.compositeCanvas=nil
  self.width,self.height=0,0
  self.renderWidth,self.renderHeight=0,0
  self.stickX,self.stickY=0,0
  self.hudBox,self.uiAnchors,self.environment=nil,nil,nil
  self.readyFrame=false
  self.defect=nil
  self.warn=opts.warn or self.warn
  self.label=opts.label or self.label or "Stadium battle"
  return self
end

function Scene.new(opts)
  local self=setmetatable({},Scene)
  return Scene.init(self,opts)
end

function Scene:release()
  for _,actor in pairs(self.actors or {}) do
    if actor and actor.release then actor:release() end
  end
  for _,value in ipairs({self.canvas,self.depth,self.compositeCanvas}) do
    if value and value.release then pcall(value.release,value) end
  end
  self.canvas,self.depth,self.presentCanvas,self.compositeCanvas=nil,nil,nil,nil
  Stage.invalidate()
  Shadow.release()
  Hud.invalidate()
  AA.release()
  Camera.reset()
end

function Scene:ensureCanvas(width,height)
  if self.canvas and self.renderWidth==width and self.renderHeight==height then return true end
  if self.canvas and self.canvas.release then pcall(self.canvas.release,self.canvas) end
  if self.depth and self.depth.release then pcall(self.depth.release,self.depth) end
  local g=love and love.graphics
  if not g then return false end
  local ok,canvas=pcall(g.newCanvas,width,height,{format="rgba8",readable=true,dpiscale=1})
  if not ok then
    ok,canvas=pcall(g.newCanvas,width,height,{format="rgba8",readable=true,dpiscale=1})
  end
  if not ok then
    if self.warn then pcall(self.warn,tostring(canvas)) end
    return false
  end
  local depthOk,depth=pcall(g.newCanvas,width,height,
    {format="depth24stencil8",readable=false,dpiscale=1})
  self.canvas,self.depth=canvas,depthOk and depth or nil
  self.renderWidth,self.renderHeight=width,height
  canvas:setFilter("nearest","nearest")
  return true
end

function Scene.surfaceDimensions(g,requestedWidth,requestedHeight)
  if not g then return nil end
  local windowWidth,windowHeight
  if g.getDimensions then
    local ok,w,h=pcall(g.getDimensions)
    if ok then windowWidth,windowHeight=tonumber(w),tonumber(h) end
  end
  local width=math.max(1,math.floor(tonumber(requestedWidth) or windowWidth or 1))
  local height=math.max(1,math.floor(tonumber(requestedHeight) or windowHeight or 1))
  local pixelWidth,pixelHeight=width,height
  if g.getPixelDimensions then
    local ok,pw,ph=pcall(g.getPixelDimensions)
    pw,ph=ok and tonumber(pw) or nil,ok and tonumber(ph) or nil
    if pw and ph and pw>0 and ph>0 then
      if windowWidth and windowHeight and windowWidth>0 and windowHeight>0 then
        pixelWidth=math.max(1,math.floor(width*pw/windowWidth+.5))
        pixelHeight=math.max(1,math.floor(height*ph/windowHeight+.5))
      else
        pixelWidth,pixelHeight=math.floor(pw),math.floor(ph)
      end
    end
  end
  return width,height,pixelWidth,pixelHeight
end

function Scene:environmentGame()
  return self.screen and self.screen.game or self.game
end

function Scene:visualActor(side)
  return self.actors and self.actors[side] or nil
end

function Scene:picScale()
  return 1
end

function Scene:modelMatrix(side,actor)
  actor=actor or self.actors[side]
  local metrics=actor.renderer:worldMetrics()
  local worldHeight=clamp(14*math.sqrt(metrics.height/52.25),5,18)
  local k=worldHeight/metrics.height*actor:scale()*self:picScale(side)
  local p=Stage.positions[side]
  local yaw=side=="player" and math.pi or 0
  local hover=math.min(math.max(metrics.floor,0),metrics.height*.5)
  return mul(translate(p[1],p[2],p[3]),
    mul(rotateY(yaw),mul(scale(k),translate(0,-(metrics.floor-hover),0)))),yaw
end

function Scene:render(requestedWidth,requestedHeight)
  local hadFrame=self.readyFrame
  local g=love and love.graphics
  if not (g and g.newCanvas) then return false end
  local width,height,pixelWidth,pixelHeight=Scene.surfaceDimensions(g,requestedWidth,requestedHeight)
  if not width then return false end
  local renderWidth,renderHeight=AA.expand(pixelWidth,pixelHeight)
  if not self:ensureCanvas(renderWidth,renderHeight) then return false end
  self.width,self.height=width,height

  local previous=g.getCanvas and {g.getCanvas()} or nil
  local ok,err=pcall(function()
    if self.depth then g.setCanvas({self.canvas,depthstencil=self.depth})
    else g.setCanvas(self.canvas) end
    self.environment=Sky.resolve(self:environmentGame())
    local frame=Camera.frame(width,height)
    Sky.draw(g,renderWidth,renderHeight,self.environment,frame)
    local vp=frame.vp
    self.hudBox=frame.letterbox
    local matrices,drawActors={},{}
    local dynamicObjectIndex=0
    for _,side in ipairs({"enemy","player"}) do
      local actor=self:visualActor(side)
      if actor and actor.renderer then
        if hasDynamicObjectHandler(actor) then
          actor.dynamicObjectIndex=dynamicObjectIndex
          dynamicObjectIndex=dynamicObjectIndex+1
        else
          actor.dynamicObjectIndex=nil
        end
        drawActors[side]=actor
        matrices[side]={self:modelMatrix(side,actor)}
      end
    end

    local lightVP=Shadow.begin(self.environment.light,self.environment.shadowStrength)
    if lightVP then
      for _,side in ipairs({"enemy","player"}) do
        local actor,entry=drawActors[side],matrices[side]
        if entry and actor.renderer then
          local drawn,drawErr=actor.renderer:drawShadowMap(entry[1],lightVP)
          if not drawn and self.warn then
            pcall(self.warn,self.label.." shadow draw failed: "..tostring(drawErr))
          end
        end
      end
    end
    local shadow=lightVP and Shadow.finish() or nil
    if self.depth then g.setCanvas({self.canvas,depthstencil=self.depth})
    else g.setCanvas(self.canvas) end

    local marks,stageErr=Stage.draw(g,width,height,frame,self.actors,shadow,self.environment)
    if not marks then error(self.label.." stage draw failed: "..tostring(stageErr),0) end
    local box=frame.letterbox
    self.uiAnchors={
      player={(marks.player.x-box.lx)/box.scale,(marks.player.y-box.ly)/box.scale},
      enemy={(marks.enemy.x-box.lx)/box.scale,(marks.enemy.y-box.ly)/box.scale},
    }

    for _,pass in ipairs({"opaque","additive"}) do
      for _,side in ipairs({"enemy","player"}) do
        local actor,entry=drawActors[side],matrices[side]
        if entry and actor.renderer then
          local base=self.environment.modelTint or {1,1,1}
          local drawn,drawErr=actor.renderer:drawScene(pass,entry[1],{
            viewProjection=vp,viewMatrix=frame.view,
            normalMatrix=Renderer.normalMatrix(entry[2],0,false),
            lightDir=self.environment.light,ambient=self.environment.ambient,
            diffuse=self.environment.diffuse,skipHandlers=pass=="additive",
            flipWinding=true,disableCulling=true,
            tint={base[1],base[2],base[3],1},
            flashAmount=actor.flash>0 and .5 or 0,
            sunMap=shadow and shadow.map,sunVP=shadow and shadow.sunVP,
            sunDark=shadow and shadow.sunDark,sunBias=shadow and shadow.sunBias,
            sunTexel=shadow and shadow.sunTexel,
          })
          if not drawn then
            error(self.label.." model draw failed: "..tostring(drawErr),0)
          end
        end
      end
    end
    g.setColor(1,1,1,1)
  end)

  if previous and #previous>0 then pcall(g.setCanvas,unpack(previous))
  else pcall(g.setCanvas) end
  if g.setShader then pcall(g.setShader) end
  if g.setDepthMode then pcall(g.setDepthMode,"always",false) end
  if g.setMeshCullMode then pcall(g.setMeshCullMode,"none") end
  if g.setBlendMode then pcall(g.setBlendMode,"alpha","alphamultiply") end

  if not ok then
    self.defect=tostring(err)
    self.readyFrame=hadFrame
    if self.warn then pcall(self.warn,tostring(err)) end
    return false
  end

  self.presentCanvas=AA.resolve(self.canvas,pixelWidth,pixelHeight)
  Hud.build(self.presentCanvas)
  self.readyFrame=true
  self.defect=nil
  return true
end

-- Copy the clean scene to a writable physical-pixel canvas. The returned
-- x/y scales convert logical window units into that canvas's coordinates.
function Scene:copyForComposite()
  local source=self.presentCanvas or self.canvas
  if not (source and source.getDimensions and love and love.graphics) then return nil end
  local g=love.graphics
  local sw,sh=source:getDimensions()
  if not self.compositeCanvas or self.compositeCanvas:getWidth()~=sw
      or self.compositeCanvas:getHeight()~=sh then
    if self.compositeCanvas and self.compositeCanvas.release then
      pcall(self.compositeCanvas.release,self.compositeCanvas)
    end
    local ok,c=pcall(g.newCanvas,sw,sh,{format="rgba8",readable=true,dpiscale=1})
    if not ok then return nil end
    self.compositeCanvas=c
    c:setFilter("nearest","nearest")
  end
  local previous=g.getCanvas and {g.getCanvas()} or nil
  g.setCanvas(self.compositeCanvas)
  g.clear(0,0,0,1)
  g.setColor(1,1,1,1)
  g.draw(source,0,0)
  if previous and #previous>0 then g.setCanvas(unpack(previous)) else g.setCanvas() end
  local sx=sw/math.max(1,self.width or 1)
  local sy=sh/math.max(1,self.height or 1)
  return self.compositeCanvas,sx,sy
end

Scene.Camera=Camera
Scene.Stage=Stage
Scene.Hud=Hud
Scene.AA=AA

return Scene
