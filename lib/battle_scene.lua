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
local Extensions = require("mods.STADIUM2_IMPORTER.lib.battle_scene_extensions")

local Scene = {}
Scene.__index = Scene
local unpack=table.unpack or unpack
local DEPTH_FORMATS={"depth24stencil8","depth24","depth16","depth32f"}

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
  self.providerBattlerModes=nil
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
  for _,value in ipairs({self.canvas,self.depth or false,self.compositeCanvas}) do
    if value and value.release then pcall(value.release,value) end
  end
  self.canvas,self.depth,self.presentCanvas,self.compositeCanvas=nil,nil,nil,nil
  self.providerBattlerModes=nil
  Stage.invalidate()
  Shadow.release()
  Hud.invalidate()
  AA.release()
  Camera.reset()
end

local function newDepthCanvas(g,width,height)
  for _,format in ipairs(DEPTH_FORMATS) do
    local ok,depth=pcall(g.newCanvas,width,height,
      {format=format,readable=false,dpiscale=1})
    if ok and depth then return depth end
  end
  return nil
end

local function sceneTarget(self)
  if self.depth then return {self.canvas,depthstencil=self.depth} end
  -- LÖVE allocates a driver-compatible internal depth attachment. This is
  -- preferable to silently drawing all model primitives without depth when
  -- Android rejects every explicit depth Canvas format.
  return {self.canvas,depth=true}
end

local function horizonY(frame,height)
  local m,eye,focus=frame and frame.vp,frame and frame.eye,frame and frame.focus
  if not (m and eye and focus and height and height>0) then return nil end
  local dx,dz=focus[1]-eye[1],focus[3]-eye[3]
  local len=math.sqrt(dx*dx+dz*dz)
  if len<1e-6 then return nil end
  dx,dz=dx/len,dz/len
  local y=m[5]*dx+m[7]*dz
  local w=m[13]*dx+m[15]*dz
  if w<=1e-6 then return nil end
  return (y/w*.5+.5)*height
end

local function projectedMarks(self,frame,width,height)
  local marks={}
  for _,side in ipairs({"enemy","player"}) do
    local p=Stage.positions[side]
    local x,y=Camera.project(frame,width,height,p)
    marks[side]={x=x,y=y,radius=Stage.radius(self:visualActor(side))}
  end
  return marks
end

local function extensionContext(self,g,frame,width,height,renderWidth,renderHeight,marks)
  local slots={}
  for _,side in ipairs({"enemy","player"}) do
    local p=Stage.positions[side]
    slots[side]={position={p[1],p[2],p[3]},x=p[1],y=p[2],z=p[3]}
  end
  return {
    apiVersion=Extensions.API_VERSION,
    graphics=g,
    target={
      color=self.canvas, depth=self.depth,
      width=renderWidth, height=renderHeight,
      logicalWidth=width, logicalHeight=height,
    },
    camera={
      view=frame.view, projection=frame.projection,
      viewProjection=frame.vp, vp=frame.vp,
      eye=frame.eye, focus=frame.focus,
      letterbox=frame.letterbox,
      horizonY=horizonY(frame,renderHeight),
    },
    world={
      origin={0,0,0}, groundY=0, unitsPerTile=16, actorSlots=slots,
    },
    pixelScale={
      x=renderWidth/math.max(1,width),
      y=renderHeight/math.max(1,height),
    },
    pixelGrid=math.max(1,renderHeight/math.max(1,height)),
    environment=self.environment,
    marks=marks,
    scene={
      game=self:environmentGame(), screen=self.screen, battle=self.battle,
      actors=self.actors, host=self, label=self.label,
    },
  }
end

local function restoreWorldTarget(self,g)
  g.setCanvas(sceneTarget(self))
  if g.setShader then g.setShader() end
  if g.setDepthMode then g.setDepthMode("lequal",true) end
  if g.setMeshCullMode then g.setMeshCullMode("none") end
  if g.setBlendMode then g.setBlendMode("alpha","alphamultiply") end
  g.setColor(1,1,1,1)
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
  self.canvas,self.depth=canvas,newDepthCanvas(g,width,height)
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

function Scene:battlerMode(side)
  local modes=self.providerBattlerModes
  local mode=modes and modes[side]
  if mode=="provider" or mode=="native" or mode=="host" then return mode end
  return "host"
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

local function normalizeFrame(candidate,fallback)
  if type(candidate)~="table" then return fallback end
  local vp=candidate.vp or candidate.viewProjection
  if not (candidate.view and candidate.projection and vp and candidate.eye
      and candidate.focus and candidate.letterbox) then return fallback end
  candidate.vp=vp
  candidate.viewProjection=vp
  return candidate
end

local function normalizeBattlerModes(value)
  local source=type(value)=="table" and (value.sides or value) or nil
  local out={enemy="host",player="host"}
  for _,side in ipairs({"enemy","player"}) do
    local mode=source and source[side]
    if mode=="host" or mode=="provider" or mode=="native" then out[side]=mode end
  end
  return out
end

local function normalizeBattlerDrawn(value)
  local source=type(value)=="table" and (value.drawn or value.sides or value) or nil
  local out={enemy=false,player=false}
  for _,side in ipairs({"enemy","player"}) do
    out[side]=source and source[side]==true or false
  end
  return out
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
    g.setCanvas(sceneTarget(self))
    self.environment=Sky.resolve(self:environmentGame())
    local defaultFrame=Camera.frame(width,height)
    local initialMarks=projectedMarks(self,defaultFrame,width,height)
    local cameraCtx=extensionContext(self,g,defaultFrame,width,height,renderWidth,renderHeight,initialMarks)
    cameraCtx.cameraPhase="select"
    local selectedFrame=Extensions.camera(cameraCtx,function() return defaultFrame end)
    local frame=normalizeFrame(selectedFrame,defaultFrame)
    local marks=projectedMarks(self,frame,width,height)
    local ext=extensionContext(self,g,frame,width,height,renderWidth,renderHeight,marks)
    ext.cameraPhase=nil
    ext.battlerPhase="prepare"
    local battlerSelection=Extensions.battlers(ext,function()
      return {sides={enemy="host",player="host"}}
    end)
    local battlerModes=normalizeBattlerModes(battlerSelection)
    self.providerBattlerModes=battlerModes
    ext.battlers={sides=battlerModes}
    ext.battlerPhase=nil

    local bands=self.environment and self.environment.bands
    local clear=bands and bands[1] or {0,0,0}
    g.setShader()
    if g.setDepthMode then g.setDepthMode("always",false) end
    g.clear(clear[1] or 0,clear[2] or 0,clear[3] or 0,1,true,true)
    Extensions.background(ext,function()
      Sky.paint(g,renderWidth,renderHeight,self.environment,frame)
      return true
    end)
    restoreWorldTarget(self,g)
    local vp=frame.vp
    self.hudBox=frame.letterbox
    local matrices,candidateActors={},{}
    local dynamicObjectIndex=0
    for _,side in ipairs({"enemy","player"}) do
      local actor=self:visualActor(side)
      if battlerModes[side]~="native" and actor and actor.renderer then
        if hasDynamicObjectHandler(actor) then
          actor.dynamicObjectIndex=dynamicObjectIndex
          dynamicObjectIndex=dynamicObjectIndex+1
        else
          actor.dynamicObjectIndex=nil
        end
        candidateActors[side]=actor
        matrices[side]={self:modelMatrix(side,actor)}
      elseif actor then
        actor.dynamicObjectIndex=nil
      end
    end

    local lightVP=Shadow.begin(self.environment.light,self.environment.shadowStrength)
    if lightVP then
      ext.shadowPhase="cast"
      ext.shadow={viewProjection=lightVP}
      Extensions.shadow(ext)
      ext.shadowPhase=nil
      for _,side in ipairs({"enemy","player"}) do
        local actor,entry=candidateActors[side],matrices[side]
        if battlerModes[side]=="host" and entry and actor.renderer then
          local drawn,drawErr=actor.renderer:drawShadowMap(entry[1],lightVP)
          if not drawn and self.warn then
            pcall(self.warn,self.label.." shadow draw failed: "..tostring(drawErr))
          end
        end
      end
    end
    local shadow=lightVP and Shadow.finish() or nil
    ext.shadow=shadow
    g.setCanvas(sceneTarget(self))

    local providerMarks,stageErr=Extensions.environment(ext,function()
      return Stage.draw(g,width,height,frame,self.actors,shadow,self.environment)
    end)
    if type(providerMarks)=="table" and providerMarks.player and providerMarks.enemy then
      marks=providerMarks
      ext.marks=marks
    end
    if not marks then error(self.label.." stage draw failed: "..tostring(stageErr),0) end
    restoreWorldTarget(self,g)
    Extensions.geometry(ext)
    restoreWorldTarget(self,g)
    local box=frame.letterbox
    self.uiAnchors={
      player={(marks.player.x-box.lx)/box.scale,(marks.player.y-box.ly)/box.scale},
      enemy={(marks.enemy.x-box.lx)/box.scale,(marks.enemy.y-box.ly)/box.scale},
    }

    restoreWorldTarget(self,g)
    ext.battlerPhase="draw"
    local providerDrawResult=Extensions.battlers(ext,function()
      return {drawn={enemy=false,player=false}}
    end)
    ext.battlerPhase=nil
    local providerDrawn=normalizeBattlerDrawn(providerDrawResult)
    local resolvedModes={enemy="host",player="host"}
    for _,side in ipairs({"enemy","player"}) do
      if battlerModes[side]=="native" then
        resolvedModes[side]="native"
      elseif battlerModes[side]=="provider" and providerDrawn[side] then
        resolvedModes[side]="provider"
      else
        resolvedModes[side]="host"
      end
    end
    self.providerBattlerModes=resolvedModes
    ext.battlers={sides=resolvedModes,requested=battlerModes,drawn=providerDrawn}
    restoreWorldTarget(self,g)

    local modelFailed={enemy=false,player=false}
    for _,pass in ipairs({"opaque","additive"}) do
      for _,side in ipairs({"enemy","player"}) do
        local actor,entry=candidateActors[side],matrices[side]
        if resolvedModes[side]=="host" and not modelFailed[side]
            and entry and actor.renderer then
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
            if self.warn then
              pcall(self.warn,self.label.." "..side.." "..pass
                .." model draw failed: "..tostring(drawErr))
            end
            if pass=="opaque" then
              modelFailed[side]=true
              resolvedModes[side]="native"
              self.providerBattlerModes[side]="native"
            end
          end
        end
      end
    end

    restoreWorldTarget(self,g)
    Extensions.overlay(ext)
    restoreWorldTarget(self,g)
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
    self.providerBattlerModes={enemy="host",player="host"}
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
