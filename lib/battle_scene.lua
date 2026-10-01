-- Shared Stadium battle presentation surface.
--
-- Generation adapters decide WHAT is visible and WHEN. This module only owns
-- HOW the stage, camera, shadows and model renderers become a window-sized
-- image. It deliberately has no knowledge of turn order, capture rolls,
-- battle queues or generation-specific phase names.
local Renderer = require("mods.STADIUM2_IMPORTER.lib.renderer")
local Camera = require("mods.STADIUM2_IMPORTER.lib.battle_camera")
local Stage = require("mods.STADIUM2_IMPORTER.lib.battle_stage")
local StadiumBattleLayout = require("mods.STADIUM2_IMPORTER.lib.stadium_battle_layout")
local Shadow = require("mods.STADIUM2_IMPORTER.lib.battle_shadow")
local Sky = require("mods.STADIUM2_IMPORTER.lib.battle_sky")
local Hud = require("mods.STADIUM2_IMPORTER.lib.battle_hud")
local AA = require("mods.STADIUM2_IMPORTER.lib.battle_aa")
local Extensions = require("mods.STADIUM2_IMPORTER.lib.battle_scene_extensions")
local ArenaLighting = require("mods.STADIUM2_IMPORTER.lib.arena_lighting")

local Watercolor = require("mods.STADIUM2_IMPORTER.lib.battle_watercolor")
local Nature = require("mods.STADIUM2_IMPORTER.lib.battle_nature")
local Cave = require("mods.STADIUM2_IMPORTER.lib.battle_cave")
local Lake = require("mods.STADIUM2_IMPORTER.lib.battle_freshwater")
local Ocean = require("mods.STADIUM2_IMPORTER.lib.battle_ocean")
local Town = require("mods.STADIUM2_IMPORTER.lib.battle_town")
local Importer = require("mods.STADIUM2_IMPORTER.lib.importer")
-- CAMERA option STADIUM (the Stadium 2 camera, arenas and custom scenes)
local function stadiumCameraMode()
  return type(Importer.cameraMode)=="function" and Importer.cameraMode()=="stadium"
end

-- In-battle evolution (user-requested extension, not Stadium 2 behaviour).
local Evolution = require("mods.STADIUM2_IMPORTER.lib.battle_evolution")

local Scene = {}
Scene.__index = Scene
Scene.MODE_CLASSIC="classic"
Scene.MODE_ARENA="arena"
Scene.ARENA_ENVIRONMENT=ArenaLighting.environment()
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
-- A battler's per-axis native scale (Meditate) on top of its uniform one.
local function axisScale(actor,image)
  local a=not image and actor.nativeAxisScale
  if not a then return nil end
  return {a[1],0,0,0,0,a[2],0,0,0,0,a[3],0,0,0,0,1}
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
  self.arena=type(opts.arena)=="table" and opts.arena or nil
  self.arenaRenderer=self.arena and self.arena.renderer or nil
  self.arenaIndex=self.arena and self.arena.index or nil
  -- Opt-in only: the ordinary Gen 1/Gen 2 presentation keeps its established
  -- normalized-height placement. Arena viewers can instead keep Stadium's
  -- model and field coordinates in the same world-unit conversion.
  self.sceneMode=(opts.sceneMode==Scene.MODE_ARENA or opts.arenaMode==true)
    and Scene.MODE_ARENA or Scene.MODE_CLASSIC
  -- Compatibility alias for API consumers that adopted arenaMode before the
  -- two scene compositions were formally separated.
  self.arenaMode=self.sceneMode==Scene.MODE_ARENA
  self.arenaScale=tonumber(opts.arenaScale)
    or tonumber(self.arena and self.arena.scale) or .05
  self.arenaGroundY=tonumber(opts.arenaGroundY)
    or tonumber(self.arena and self.arena.groundY) or 0
  self.arenaEnvironment=type(opts.arenaEnvironment)=="table"
    and opts.arenaEnvironment
    or (self.arena and self.arena.environment) or Scene.ARENA_ENVIRONMENT
  -- Generation scenes may inject the opt-in Stadium 2 FX bridge.  Keeping
  -- this as an injected seam means the default battle path does not load or
  -- allocate any FX runtime state when the beta toggle is off.
  self.battleFx=type(opts.battleFx)=="table" and opts.battleFx or nil
  return self
end

function Scene:setSceneMode(mode)
  self.sceneMode=mode==Scene.MODE_ARENA and Scene.MODE_ARENA
    or Scene.MODE_CLASSIC
  self.arenaMode=self.sceneMode==Scene.MODE_ARENA
  self.readyFrame=false
  return self.sceneMode
end

function Scene:resolveEnvironment()
  if self.sceneMode==Scene.MODE_ARENA then return self.arenaEnvironment end
  return Sky.resolve(self:environmentGame())
end

function Scene.new(opts)
  local self=setmetatable({},Scene)
  return Scene.init(self,opts)
end

function Scene:release()
  if self.evolution then pcall(self.evolution.release,self.evolution);self.evolution=nil end
  local battleFx=self.battleFx
  self.battleFx=nil
  if battleFx and type(battleFx.release)=="function" then
    pcall(battleFx.release,battleFx)
  end
  if self.weather then self.weather:release();self.weather=nil end
  if self.visitors then self.visitors:release();self.visitors=nil end
  if self.statusOverlay and self.statusOverlay.release then self.statusOverlay:release() end
  self.statusOverlay,self.statusOverlayReady=nil,nil
  for _,actor in pairs(self.actors or {}) do
    if actor and actor.release then actor:release() end
  end
  for _,value in ipairs({self.canvas,self.depth or false,self.compositeCanvas}) do
    if value and value.release then pcall(value.release,value) end
  end
  self.canvas,self.depth,self.presentCanvas,self.compositeCanvas=nil,nil,nil,nil
  if self.arena and self.arena.release then pcall(self.arena.release,self.arena) end
  self.arena,self.arenaRenderer=nil,nil
  self.providerBattlerModes=nil
  Watercolor.release()
  -- Scenery belongs to the session cache, even across presentation toggles.
  Nature.endBattle();Cave.endBattle();Lake.endBattle();Town.endBattle();Ocean.endBattle()
  Stage.invalidate()
  Shadow.release()
  Hud.invalidate()
  AA.release()
  Camera.reset()
end

-- Generation-specific update loops call this after their host presentation
-- state has advanced.  The shared scene deliberately does not own battle
-- timing, but provides one guarded seam for the persistent FX clock.
function Scene:updateBattleFx(dt)
  -- the in-battle evolution (extension) steps with the scene clock
  local evoOk,evoErr=pcall(Evolution.step,self,dt)
  if not evoOk and self.warn then pcall(self.warn,"evolution: "..tostring(evoErr)) end
  local battleFx=self.battleFx
  if not battleFx or type(battleFx.update)~="function" then return nil end
  -- 84113D7C: the first idle record after a turn clears the effects (the
  -- idle records run while the battle waits for a command; with the STADIUM
  -- camera, once its idle cycle has started, since it also waits for the
  -- event timer). D_841911FA is `stadiumIdleCleared`, reset at turn start.
  if not self.stadiumIdleCleared then
    local cam=self.stadiumDirectorActive and self.stadiumCamera
    local idle
    if cam then idle=cam.idle~=nil
    else idle=type(self.stadiumAwaitingCommand)=="function" and self:stadiumAwaitingCommand() end
    if idle then
      self.stadiumIdleCleared=true
      self:battleFxClear()
    end
  end
  local ok,result=pcall(battleFx.update,battleFx,dt)
  if not ok and self.warn then pcall(self.warn,tostring(result)) end
  return ok and result or nil
end

function Scene:stepArena(dt)
  local renderer=self.arenaRenderer
  if renderer and renderer.step then return renderer:step(dt) end
  return false
end

function Scene:drawArena(context,marks)
  local renderer=self.arenaRenderer
  if not renderer then return marks end
  local environment=context and context.environment or self.environment or {}
  local shadow=context and context.shadow or {}
  local scale=self.arenaScale
  local matrix={
    scale,0,0,0,
    0,scale,0,self.arenaGroundY,
    0,0,scale,0,
    0,0,0,1,
  }
  local camera=context and context.camera or {}
  local tint=environment.arenaTint or {1,1,1}
  local options={
    viewProjection=camera.viewProjection or camera.vp,
    viewMatrix=camera.view,
    normalMatrix={1,0,0,0,1,0,0,0,1},
    lightDir=environment.light,ambient=environment.ambient,
    diffuse=environment.diffuse,modernLighting=true,
    tint={tint[1] or 1,tint[2] or 1,tint[3] or 1,1},flipWinding=true,
    sunMap=shadow.map,sunVP=shadow.sunVP,
    sunDark=shadow.sunDark,sunBias=shadow.sunBias,sunTexel=shadow.sunTexel,
  }
  local drawn,drawError=renderer:drawScene("opaque",matrix,options)
  if drawn then drawn,drawError=renderer:drawScene("additive",matrix,options) end
  if not drawn then return nil,drawError end
  return marks
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
    local p=self:actorPosition(side)
    local x,y=Camera.project(frame,width,height,p)
    marks[side]={x=x,y=y,radius=Stage.radius(self:visualActor(side))}
  end
  return marks
end

local function extensionContext(self,g,frame,width,height,renderWidth,renderHeight,marks)
  local slots={}
  for _,side in ipairs({"enemy","player"}) do
    local p=self:actorPosition(side)
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
      origin={0,self.arenaMode and self.arenaGroundY or 0,0},
      groundY=self.arenaMode and self.arenaGroundY or 0,
      unitsPerTile=self.arenaMode and 16*self.arenaScale or 16,
      actorSlots=slots,
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
      actors=self.actors, host=self, label=self.label, mode=self.sceneMode,
      arena=self.sceneMode==Scene.MODE_ARENA,
    },
  }
end

local function restoreWorldTarget(self,g)
  g.setCanvas(sceneTarget(self))
  -- a split-screen view keeps drawing inside its own rectangle
  if self.viewScissor and g.setScissor then g.setScissor(unpack(self.viewScissor)) end
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

-- CAMERA option STADIUM: Stadium 2's own camera (stadium2_battle_camera.lua)
-- in the arena, stepped with the battle; FREE keeps the field camera.
-- The camera's state machine (the director) runs with either CAMERA option:
-- it is Stadium's record timing, which the hosts' event queues follow
-- (Scene:stadiumPresentationBusy). Only its camera pose depends on STADIUM
-- (stadiumCameraActive); stadiumDirectorActive says the machine runs.
function Scene:updateStadiumCamera(dt)
  local StadiumCamera=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_camera")
  local camera,err=StadiumCamera.forScene(self,self.warn)
  if not camera then
    if stadiumCameraMode() and not self.stadiumCameraReported and self.warn then
      self.stadiumCameraReported=true
      pcall(self.warn,"STADIUM camera unavailable: "..tostring(err))
    end
    self.stadiumCameraActive=false
    self.stadiumDirectorActive=false
    self:stadiumReleaseEntrance("player"); self:stadiumReleaseEntrance("enemy")
    return
  end
  local ok,stepErr=pcall(camera.update,camera,self,dt)
  if not ok and not self.stadiumCameraStepReported and self.warn then
    self.stadiumCameraStepReported=true
    pcall(self.warn,"STADIUM camera: "..tostring(stepErr))
  end
  -- a failed step can not release a held entrance at its moment
  if not ok then self:stadiumReleaseEntrance("player"); self:stadiumReleaseEntrance("enemy") end
  -- A failed step keeps the Stadium camera's last pose on screen (reported
  -- once above): falling back to the FREE camera only on the frames that
  -- fail would alternate the two cameras frame by frame.
  self.stadiumDirectorActive=true
  self.stadiumCameraActive=stadiumCameraMode()
end

-- USER-REQUESTED EXTENSION (2026-10-01; not Stadium 2): a move that misses
-- or has no effect still shows its attempt. Stadium's engine queues no move
-- event for the attacker then (8412E420), only the defender's dodge after
-- the miss text. Here the attacker plays its attack clip, the camera's
-- attack state and the move bank with the missed result (841087B8 then
-- takes 841089D8(1) at the hit frame: the effect is cut where the hit would
-- land), and the dodge follows once the attack has ended.
function Scene:stadiumPresentAttempt(side,moveId)
  moveId=tonumber(moveId)
  local actor=self.actors and self.actors[side]
  if not (moveId and actor) then return false end
  if actor.attack then pcall(actor.attack,actor,moveId) end
  self:stadiumCameraAttack(side,moveId)
  local fx=self.battleFx
  if fx and fx.playMoveAndImpact then
    local FxSequence=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_sequence")
    pcall(fx.playMoveAndImpact,fx,moveId,side,actor,FxSequence.RESULT_MISSED,
      self.actors[side=="player" and "enemy" or "player"])
  end
  return true
end

-- How visible a battler's model is: the native opacity track (mode 5, model
-- +0x1D through 8003F4DC, e.g. the send-out fading it in) times the actor's
-- materialAlpha, exactly as the model draw applies them. A shadow map has
-- no partial darkness, so the model casts its shadow once it is at least
-- half visible (Scene.SHADOW_MIN_OPACITY).
Scene.SHADOW_MIN_OPACITY=0.5
function Scene:battlerOpacity(side,actor)
  local fx=self.battleFx
  local colors
  if fx and type(fx.modelColors)=="function" then
    local ok,value=pcall(fx.modelColors,fx)
    if ok then colors=value end
  end
  local native=type(colors)=="table" and colors[side] or nil
  local opacity=native and native.opacity and native.opacity/255 or 1
  return opacity*((actor and actor.modelAlphaByte or 255)/255)
end

-- The hosts hold their next battle event while Stadium's current record is
-- still playing (StadiumCamera:busy, 84135778). Without the director, the
-- attacker's attack clip stands in. Scene.PRESENTATION_HOLD_LIMIT (seconds)
-- releases any hold whose end never comes.
Scene.PRESENTATION_HOLD_LIMIT=8
function Scene:stadiumPresentationBusy()
  if (self.heldAdvanceTime or 0)>=Scene.PRESENTATION_HOLD_LIMIT then return false end
  local cam=self.stadiumDirectorActive and self.stadiumCamera
  if cam and cam.busy then
    local ok,busy=pcall(cam.busy,cam)
    if ok then return busy==true end
  end
  for _,side in ipairs({"player","enemy"}) do
    local actor=self.actors and self.actors[side]
    if actor and actor.context=="attack" then return true end
  end
  return false
end

-- A move starts (the attack state): Stadium's attack shot on the attacker.
function Scene:stadiumCameraAttack(side,moveId)
  self.stadiumLastMove={side=side,move=tonumber(moveId)}
  if self.stadiumDirectorActive and self.stadiumCamera then
    pcall(self.stadiumCamera.attack,self.stadiumCamera,self,side,moveId)
  end
end

-- 841089D8(1) through the battle FX adapter (Adapter:clearAll).
function Scene:battleFxClear()
  local fx=self.battleFx
  if fx and type(fx.clearAll)=="function" then
    local ok,err=pcall(fx.clearAll,fx)
    if not ok and self.warn then pcall(self.warn,"battle FX clear: "..tostring(err)) end
  end
end

-- A turn begins (both sides have chosen): Stadium's turn-start orbit.
function Scene:stadiumCameraTurn()
  self.stadiumIdleCleared=false -- 8411FF1C's 0x5A case clears D_841911FA
  self.stadiumTurnSeen=true
  self.stadiumFirstActor=false -- Gen 1 records the turn's first action here
  self.stadiumPresentedMove=nil -- Gen 1's stat lines pair with this turn's move
  if self.stadiumDirectorActive and self.stadiumCamera then
    pcall(self.stadiumCamera.turnStart,self.stadiumCamera,self)
  end
end

-- A status or residual Stadium event (its FX entry; trapMove for a
-- trapping tick): Stadium's family 9 camera on that side.
-- Weather start/end entries come from 84119630 (codes 0x30-0x35), which
-- does not clear; every other entry here is a family-9 event (84118C08).
local NO_CLEAR_ENTRIES={[0x106]=true,[0x107]=true,[0x113]=true,
  [0x11F]=true,[0x120]=true,[0x121]=true}

function Scene:stadiumCameraEntry(entry,side,trapMove)
  -- 84118C08: a status/residual/stat/heal event (family 9) clears the
  -- battle effects (84111C1C -> 841089D8(1)) before it plays its own, so a
  -- move's leftover marks end there. Independent of the camera mode.
  if not NO_CLEAR_ENTRIES[tonumber(entry)] then self:battleFxClear() end
  if self.stadiumDirectorActive and self.stadiumCamera then
    pcall(self.stadiumCamera.statusEvent,self.stadiumCamera,self,side,entry,trapMove)
  end
end

-- A Pokemon is recalled: Stadium's recall camera on it.
function Scene:stadiumCameraRecall(side,condition)
  if self.stadiumDirectorActive and self.stadiumCamera then
    condition=condition or (self.restCondition and self:restCondition(side)) or nil
    pcall(self.stadiumCamera.recall,self.stadiumCamera,self,side,condition)
  end
end

-- A send-out's entrance animation (`start` plays it): run now, or held while
-- the STADIUM camera's opening is not yet filming that side (it releases it
-- at Stadium's own moment).
function Scene:stadiumEntrance(side,start)
  local cam=self.stadiumDirectorActive and self.stadiumCamera
  local okH,hold=false,false
  if cam and cam.holdEntrance then okH,hold=pcall(cam.holdEntrance,cam,side) end
  if okH and hold then
    self.stadiumHeldEntrance=self.stadiumHeldEntrance or {}
    self.stadiumHeldEntrance[side]=start
    return false
  end
  start()
  return true
end

function Scene:stadiumReleaseEntrance(side)
  local held=self.stadiumHeldEntrance
  local start=held and held[side]
  if not start then return false end
  held[side]=nil
  pcall(start)
  return true
end

-- The battle is decided (battle.ended): Stadium's victory camera.
function Scene:stadiumCameraBattleEnd(result)
  if self.stadiumDirectorActive and self.stadiumCamera then
    pcall(self.stadiumCamera.battleEnd,self.stadiumCamera,self,result)
  end
end

-- The turn check's event on `side` (code, or "react"): Stadium's camera.
-- "It hurt itself in its confusion!" names no one; both engines print it
-- right after that battler's "is confused!" line, so it goes to that side.
function Scene:stadiumCameraSelfHit()
  local side=self.stadiumConfusedSide
  self.stadiumConfusedSide=nil
  if side then self:stadiumCameraTurnCheck(side,1) end
end

function Scene:stadiumCameraTurnCheck(side,code)
  if code==0x26 then self.stadiumConfusedSide=side end
  if self.stadiumDirectorActive and self.stadiumCamera then
    local condition=self.restCondition and self:restCondition(side) or nil
    pcall(self.stadiumCamera.turnCheck,self.stadiumCamera,self,side,code,condition)
  end
end

-- A move misses: Stadium's dodge camera on the defender.
function Scene:stadiumCameraDodge(side,moveId)
  if self.stadiumDirectorActive and self.stadiumCamera then
    local condition=self.restCondition and self:restCondition(side) or nil
    pcall(self.stadiumCamera.dodge,self.stadiumCamera,self,side,moveId,condition)
  end
end

-- A Pokemon is sent out: 8411BB04 first clears the effects (84111C1C),
-- then Stadium's send-out camera on it.
function Scene:stadiumCameraSendOut(side)
  -- the battle's first send-outs are the opening's (8411C418 clears at its
  -- wipe instead, see StadiumCamera:update)
  if self.stadiumTurnSeen then self:battleFxClear() end
  if self.stadiumDirectorActive and self.stadiumCamera then
    pcall(self.stadiumCamera.sendOut,self.stadiumCamera,self,side)
  end
end

-- A Pokemon faints (its faint clip starts): Stadium's faint camera on it.
function Scene:stadiumCameraFaint(side)
  if self.stadiumDirectorActive and self.stadiumCamera then
    pcall(self.stadiumCamera.faint,self.stadiumCamera,self,side)
  end
end

-- The defender is hit (at the impact): Stadium's hit shot on the defender,
-- by its presented sleep / freeze (restCondition).
function Scene:stadiumCameraHit(side,moveId)
  if self.stadiumDirectorActive and self.stadiumCamera then
    local condition=self.restCondition and self:restCondition(side) or nil
    pcall(self.stadiumCamera.hit,self.stadiumCamera,self,side,moveId,condition)
  end
end

-- The result byte (Stadium record +9) of the move `side` was hit by: the
-- battle FX adapter's record for the move it is presenting (from the host's
-- battle.damage_dealt facts), or nil when it is unknown.
function Scene:stadiumHitResult(side,moveId)
  local fx=self.battleFx
  local source=side=="player" and "enemy" or side=="enemy" and "player" or nil
  if not source then return nil end
  if fx then
    if type(fx._moveState)~="function" then return nil end
    local ok,state=pcall(fx._moveState,fx,moveId,source)
    return ok and type(state)=="table" and tonumber(state.resultFlags) or nil
  end
  -- MOVE EFFECTS off: the hit facts main.lua records from battle.damage_dealt
  -- are nobody else's, so the camera takes them (Sequence.resultByte)
  local okA,Adapter=pcall(require,"mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_battle_adapter")
  if not okA or type(Adapter.takeHitResult)~="function" then return nil end
  local okT,result=pcall(Adapter.takeHitResult,source,moveId)
  return okT and tonumber(result) or nil
end

-- The host's own impact while MOVE EFFECTS is off (with it on, the FX
-- adapter's onImpact reports the Stadium impact instead): the hit camera on
-- `side` for the move last presented by the other side.
function Scene:stadiumHostImpact(side)
  if self.battleFx then return end
  local last=self.stadiumLastMove
  if not (last and last.move and last.side~=side) then return end
  self:stadiumCameraHit(side,last.move)
end

-- The length in frames of an actor's model animation for a context (e.g.
-- "hit", context 254), as the model's animation header gives it; nil when
-- the actor has no such clip.
function Scene:stadiumClipFrames(side,context)
  local actor=self.actors and self.actors[side]
  local model=actor and actor.renderer and actor.renderer.model
  if not model then return nil end
  local okP,Pack=pcall(require,"mods.STADIUM2_IMPORTER.lib.pack")
  local index=okP and Pack.contextIndex(model,context)
  local anim=index and model.anims and model.anims[index]
  return anim and tonumber(anim.frames) or nil
end

-- Where Stadium units sit in this scene: {scale, theta, origin}. The arena
-- uses its own scale at its ground. A custom scene (CAMERA STADIUM there)
-- takes the Stadium layout (player at X -150, foe at X +150, both at the
-- ground) and fits it onto the scene's two battle spots: the scale makes 150
-- the half distance between them, the turn about Y aligns the Stadium X axis
-- with the player-to-foe line, and the origin is the midpoint.
Scene.STADIUM_HALF_DISTANCE=150
function Scene:stadiumSpace()
  if self.arenaMode then
    return {scale=self.arenaScale,theta=0,origin={0,self.arenaGroundY,0}}
  end
  local a,b=Stage.positions.player,Stage.positions.enemy
  local dx,dz=b[1]-a[1],b[3]-a[3]
  local half=math.sqrt(dx*dx+dz*dz)/2
  -- R(theta) maps +X to the player-to-foe direction (x'=x cos+z sin,
  -- z'=-x sin+z cos)
  local theta=math.atan2 and math.atan2(-dz,dx) or math.atan(-dz,dx)
  return {scale=half/Scene.STADIUM_HALF_DISTANCE,theta=theta,
    origin={(a[1]+b[1])/2,(a[2]+b[2])/2,(a[3]+b[3])/2}}
end

-- CAMERA STADIUM in a custom (non-arena) scene: the Pokemon take Stadium's
-- layout and proportions in the scene's Stadium space (user request: the
-- Stadium camera on the custom scenes, rescaled as needed).
function Scene:stadiumCustomScene()
  return not self.arenaMode and stadiumCameraMode()
end

-- Stadium units -> world, and back (the STADIUM camera's model markers).
function Scene:stadiumToWorld(p)
  local sp=self:stadiumSpace()
  local x,y,z=p[1]*sp.scale,p[2]*sp.scale,p[3]*sp.scale
  local c,s=math.cos(sp.theta),math.sin(sp.theta)
  return {sp.origin[1]+x*c+z*s,sp.origin[2]+y,sp.origin[3]-x*s+z*c}
end
function Scene:worldToStadium(p)
  local sp=self:stadiumSpace()
  local x,y,z=p[1]-sp.origin[1],p[2]-sp.origin[2],p[3]-sp.origin[3]
  local c,s=math.cos(sp.theta),math.sin(sp.theta)
  return {(x*c-z*s)/sp.scale,y/sp.scale,(x*s+z*c)/sp.scale}
end

function Scene:visualActor(side)
  return self.actors and self.actors[side] or nil
end

function Scene:actorPosition(side)
  if not self.arenaMode and self:stadiumCustomScene() then
    local actor=self:visualActor(side)
    return self:stadiumToWorld(StadiumBattleLayout.slot(side,actor and actor.dex))
  end
  if self.arenaMode then
    local actor=self:visualActor(side)
    local slot=StadiumBattleLayout.slot(side,actor and actor.dex)
    return {slot[1]*self.arenaScale,self.arenaGroundY,
      slot[3]*self.arenaScale}
  end
  return Stage.positions[side]
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

-- Vertical displacement in model-height units, supplied by the host's
-- animation timeline. Apply in world space so scaling cannot cancel it.
function Scene:picElevation() return 0 end

-- `image` (optional) is one of actor.afterimages: its offset and scale
-- replace the battler's own (lib/battle_special_moves.lua).
function Scene:modelMatrix(side,actor,image)
  actor=actor or self.actors[side]
  local metrics=actor.renderer:worldMetrics()
  local elevation=self:picElevation(side)
  if self.arenaMode then
    -- Agility copies the battler's scale (84120E7C); Double Team sets 1.0
    -- (84121CAC), taken here as the battler's base scale.
    local size=image and image.scale or actor:scale()
    local k=self.arenaScale*size*self:picScale(side)
    local slot,yaw=StadiumBattleLayout.slot(side,actor.dex)
    -- Native per-move sway (Agility) or afterimage position, Stadium units.
    local o=image and image.offset or actor.nativeOffset or {0,0,0}
    -- Stadium model bounds and field vertices use the same source units.
    -- Fragment 79 authors X/Z and facing globally for every field. Ground the
    -- extracted model's real floor to reproduce its model-derived Y offset.
    local axes=axisScale(actor,image)
    local ky=axes and k*axes[6] or k
    local model=mul(rotateY(yaw),scale(k))
    if axes then model=mul(model,axes) end
    return mul(translate((slot[1]+o[1])*self.arenaScale,
        self.arenaGroundY-metrics.floor*ky+o[2]*self.arenaScale
          +elevation*metrics.height*self.arenaScale,
        (slot[3]+o[3])*self.arenaScale),
      model),yaw
  end
  if self:stadiumCustomScene() then
    -- the arena's placement and proportions, in the scene's Stadium space
    local sp=self:stadiumSpace()
    local size=image and image.scale or actor:scale()
    local k=sp.scale*size*self:picScale(side)
    local slot,yaw=StadiumBattleLayout.slot(side,actor.dex)
    local o=image and image.offset or actor.nativeOffset or {0,0,0}
    local at=self:stadiumToWorld({slot[1]+o[1],o[2],slot[3]+o[3]})
    local turn=yaw+sp.theta
    local axes=axisScale(actor,image)
    local ky=axes and k*axes[6] or k
    local model=mul(rotateY(turn),scale(k))
    if axes then model=mul(model,axes) end
    return mul(translate(at[1],at[2]-metrics.floor*ky+elevation*metrics.height*sp.scale,at[3]),
      model),turn
  end
  local worldHeight=clamp(14*math.sqrt(metrics.height/52.25),5,18)
  local k=worldHeight/metrics.height*actor:scale()*self:picScale(side)
  local p=Stage.positions[side]
  local yaw=side=="player" and math.pi or 0
  local hover=math.min(math.max(metrics.floor,0),metrics.height*.5)
  return mul(translate(p[1],p[2]+elevation*worldHeight,p[3]),
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
    self.environment=self:resolveEnvironment()
    local selection=self.environmentSelection or require('mods.STADIUM2_IMPORTER.lib.battle_environment').select(
      self.battleContext,Importer.environmentStyle(),false,nil,
      Importer.environmentTest and Importer.environmentTest(),
    Importer.arenaTest and Importer.arenaTest())
    local environmentScene=selection.scene
    local natureActive=self.sceneMode==Scene.MODE_CLASSIC and selection.mode=='environment'
    self.environmentId=selection.id
    -- EXTRA EFFECTS off (user option): no ambient visitors, weather, or
    -- Kenney-scene sun/torch shadows; Stadium arenas keep their shadows.
    local extras=not Importer.extraEffectsEnabled or Importer.extraEffectsEnabled()~=false
    require('mods.STADIUM2_IMPORTER.lib.battle_torch_shadows').setEnabled(extras)
    local visitorMode=extras and Importer.visitorMode and Importer.visitorMode() or 'off'
    local now=love.timer and love.timer.getTime and love.timer.getTime() or 0
    if natureActive and visitorMode~='off' and environmentScene.visitors~=false then
      if self.visitors and (self.visitors.environment~=selection.id or self.visitors.mode~=visitorMode) then self.visitors:release();self.visitors=nil end
      if not self.visitors then self.visitors=require('mods.STADIUM2_IMPORTER.lib.battle_visitors').new(selection.id,visitorMode) end
      self.pendingVisitorDT=self.visitorTime and now-self.visitorTime or 0
    elseif self.visitors then self.visitors:release();self.visitors=nil end
    self.visitorTime=now
    self.natureActive=natureActive
    if natureActive then self.environment=environmentScene.lighting(self.environment) end
    local weatherMode=extras and Importer.weatherStyle() or 'off'
    local outdoors=natureActive and (selection.id=='grass' or selection.id=='town' or selection.id=='freshwater' or selection.id=='ocean' or environmentScene.outdoor==true)
    if self.weather and (not outdoors or weatherMode=='off' or self.weather.mode~=weatherMode or self.weather.id~=selection.id) then
      self.weather:release();self.weather=nil
    end
    if outdoors and weatherMode~='off' then
      self.weather=self.weather or require('mods.STADIUM2_IMPORTER.lib.battle_weather').new(selection.id,weatherMode)
      self.weatherDT=self.weatherTime and math.max(0,now-self.weatherTime) or 0
      self.environment=self.weather:lighting(self.environment,self.weatherDT)
    end
    self.weatherTime=now
    -- CAMERA STADIUM draws one pass per drawn view: normally one full
    -- screen, two during Stadium's split-screen intro (each clipped to its
    -- rectangle of the game's 320 x 240 screen). Once-per-frame work
    -- (visitors, the HUD box, UI anchors) belongs to the first view.
    local stadiumViews={false}
    if self.stadiumCameraActive and self.stadiumCamera then
      local okViews,views=pcall(self.stadiumCamera.views,self.stadiumCamera)
      if okViews and type(views)=="table" and #views>0 then stadiumViews=views end
    end
    for viewIndex,viewPose in ipairs(stadiumViews) do
    local primary=viewIndex==1
    local rect=viewPose and viewPose.viewport
    self.viewScissor=nil
    if rect and not (rect[1]==0 and rect[2]==0 and rect[3]==320 and rect[4]==240) then
      local x0,y0=math.floor(rect[1]/320*renderWidth+.5),math.floor(rect[2]/240*renderHeight+.5)
      local x1,y1=math.floor((rect[1]+rect[3])/320*renderWidth+.5),math.floor((rect[2]+rect[4])/240*renderHeight+.5)
      self.viewScissor={x0,y0,math.max(0,x1-x0),math.max(0,y1-y0)}
      if g.setScissor then g.setScissor(unpack(self.viewScissor)) end
    end
    local defaultFrame
    if self.arenaMode then
      defaultFrame=Camera.sceneFrame(width,height,{
        arena=true,
        scale=self.arenaScale,groundY=self.arenaGroundY,actors=self.actors,
        stadiumPose=viewPose or nil,
      })
    elseif viewPose then
      -- CAMERA STADIUM on a custom scene: Stadium's pose in the scene's
      -- Stadium space (the scene's own framing is not applied)
      local sp=self:stadiumSpace()
      defaultFrame=Camera.sceneFrame(width,height,{
        arena=true,scale=sp.scale,groundY=sp.origin[2],stadiumTheta=sp.theta,
        stadiumOrigin=sp.origin,actors=self.actors,stadiumPose=viewPose,
      })
    else
      defaultFrame=Camera.sceneFrame(width,height)
    end
    if natureActive and not viewPose then defaultFrame=environmentScene.frame(defaultFrame) end
    local initialMarks=projectedMarks(self,defaultFrame,width,height)
    local cameraCtx=extensionContext(self,g,defaultFrame,width,height,renderWidth,renderHeight,initialMarks)
    cameraCtx.cameraPhase="select"
    local selectedFrame=Extensions.camera(cameraCtx,function() return defaultFrame end)
    local frame=normalizeFrame(selectedFrame,defaultFrame)
    frame=Evolution.sceneFrame(self,frame)
    if self.visitors and primary then
      self.visitors:update(self.pendingVisitorDT or 0,frame)
      self.visitors:prune(frame)
    end
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
    if self.battleFx and type(self.battleFx.backgroundColor)=="function" then
      clear=self.battleFx:backgroundColor(clear)
    end
    g.setShader()
    if g.setDepthMode then g.setDepthMode("always",false) end
    g.clear(clear[1] or 0,clear[2] or 0,clear[3] or 0,1,true,true)
    Extensions.background(ext,function()
      -- Classic and Stadium arena backgrounds remain separate compositions.
      -- Outdoor field geometry omits the parent battle cyclorama, so paint
      -- only an explicitly attached arena backdrop. Enclosed arenas retain
      -- their authored clear colour and never inherit the Gen 1/2 world sky.
      if natureActive then
        environmentScene.sky(g,renderWidth,renderHeight,self.environment,frame)
      elseif self.sceneMode==Scene.MODE_CLASSIC then
        Sky.paint(g,renderWidth,renderHeight,self.environment,frame)
      elseif self.environment.backdrop==true then
        Sky.paint(g,renderWidth,renderHeight,self.environment,frame)
      end
      return true
    end)
    restoreWorldTarget(self,g)
    local vp=frame.vp
    if primary then self.hudBox=frame.letterbox end
    local matrices,candidateActors={},{}
    local dynamicObjectIndex=0
    -- CAMERA STADIUM: the Pokemon Stadium hides for the current shot (the
    -- over-the-shoulder idle shot puts the eye at that Pokemon)
    local stadiumHidden=nil
    if self.stadiumCameraActive and self.stadiumCamera and self.stadiumCamera.hiddenSide then
      local okH,hidden=pcall(self.stadiumCamera.hiddenSide,self.stadiumCamera)
      if okH then stadiumHidden=hidden end
    end
    for _,side in ipairs({"enemy","player"}) do
      local actor=self:visualActor(side)
      if side==stadiumHidden then actor=nil end
      -- an evolution on screen stands in the player's slot, alone
      local evolving,evolutionActor=Evolution.actorFor(self,side)
      if evolving then actor=evolutionActor end
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

    local lightVP=(extras or not natureActive) and Shadow.begin(self.environment.light,self.environment.shadowStrength) or nil
    if lightVP then
      if natureActive then environmentScene.castShadow(g,lightVP) end
      if self.visitors then self.visitors:castShadow(lightVP) end
      ext.shadowPhase="cast"
      ext.shadow={viewProjection=lightVP}
      Extensions.shadow(ext)
      ext.shadowPhase=nil
      for _,side in ipairs({"enemy","player"}) do
        local actor,entry=candidateActors[side],matrices[side]
        -- a model the send-out (or any opacity track) still keeps invisible
        -- casts no shadow: no shadow on the floor before the ball opens
        if battlerModes[side]=="host" and entry and actor.renderer
            and self:battlerOpacity(side,actor)>=Scene.SHADOW_MIN_OPACITY then
          local drawn,drawErr=actor.renderer:drawShadowMap(entry[1],lightVP)
          if not drawn and self.warn then
            pcall(self.warn,self.label.." shadow draw failed: "..tostring(drawErr))
          end
        end
      end
    end
    local shadow=lightVP and Shadow.finish() or nil
    if natureActive then
      local a,m,b=candidateActors,matrices,battlerModes
      if self.visitors then a,m,b=self.visitors:shadowActors(a,m,b) end
      environmentScene.updateTorchShadows(g,a,m,b,self.environment)
    end
    ext.shadow=shadow
    g.setCanvas(sceneTarget(self))

    local providerMarks,stageErr=Extensions.environment(ext,function()
      if self.sceneMode==Scene.MODE_ARENA then return self:drawArena(ext,marks) end
      if natureActive then
        environmentScene.draw(g,frame,self.environment,shadow)
        return marks
      end
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
    -- Move FX are presented after the arena geometry has established the
    -- world target.  The bridge owns its renderer state, so restore the
    -- target both before and after the call even when a provider changes
    -- shader, blend, or depth state internally.
    if self.battleFx and type(self.battleFx.draw)=="function" then
      restoreWorldTarget(self,g)
      local fxOk,fxError=pcall(self.battleFx.draw,self.battleFx,ext)
      restoreWorldTarget(self,g)
      if not fxOk and self.warn then pcall(self.warn,tostring(fxError)) end
    end
    local box=frame.letterbox
    if primary then self.uiAnchors={
      player={(marks.player.x-box.lx)/box.scale,(marks.player.y-box.ly)/box.scale},
      enemy={(marks.enemy.x-box.lx)/box.scale,(marks.enemy.y-box.ly)/box.scale},
    } end

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

    Evolution.drawBackdropFor(self,g,frame,renderWidth,renderHeight)
    restoreWorldTarget(self,g)
    local modelFailed={enemy=false,player=false}
    for _,pass in ipairs({"opaque","additive"}) do
      for _,side in ipairs({"enemy","player"}) do
        local actor,entry=candidateActors[side],matrices[side]
        if resolvedModes[side]=="host" and not modelFailed[side]
            and entry and actor.renderer then
          local base=self.environment.modelTint or {1,1,1}
          local nativeColor=ext.nativeModelColors and ext.nativeModelColors[side]
          local opacity=nativeColor and nativeColor.opacity
            and nativeColor.opacity/255 or 1
          local function drawModel(matrix,alphaByte)
            return actor.renderer:drawScene(pass,matrix,{
              viewProjection=vp,viewMatrix=frame.view,
              normalMatrix=Renderer.normalMatrix(entry[2],0,false),
              bindTorchLighting=natureActive and environmentScene.bindTorchLighting or nil,
              sceneWatercolor=natureActive,
              lightDir=self.environment.light,ambient=self.environment.ambient,
              diffuse=self.environment.diffuse,skipHandlers=pass=="additive",
              modernLighting=self.sceneMode==Scene.MODE_ARENA,
              flipWinding=true,disableCulling=true,
              -- Stadium model materialAlpha (+0x1D), 255 unless a native
              -- routine (Double Team) sets it.
              tint={base[1],base[2],base[3],opacity*(alphaByte or 255)/255},
              nativeModelColor=nativeColor and nativeColor.color,
              flashAmount=math.max(actor.flash>0 and .5 or 0,actor.evolveWhite or 0),
              sunMap=shadow and shadow.map,sunVP=shadow and shadow.sunVP,
              sunDark=shadow and shadow.sunDark,sunBias=shadow and shadow.sunBias,
              sunTexel=shadow and shadow.sunTexel,
            })
          end
          local drawn,drawErr=drawModel(entry[1],actor.modelAlphaByte)
          -- Afterimage copies (Agility, Double Team): same pose, own
          -- position and alpha, drawn after the battler.
          if drawn and self.arenaMode and actor.afterimages then
            for _,image in ipairs(actor.afterimages) do
              if (image.alpha or 0)>0 then
                drawModel((self:modelMatrix(side,actor,image)),image.alpha)
              end
            end
          end
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
    Evolution.drawOverlayFor(self,g,frame,renderWidth,renderHeight)
    restoreWorldTarget(self,g)
    if natureActive then
      if self.visitors then self.visitors:draw(g,frame,self.environment,environmentScene,shadow) end
      if environmentScene.drawEffects then environmentScene.drawEffects(g,frame)
      else require("mods.STADIUM2_IMPORTER.lib.battle_torches").draw(g,frame) end
    end
    if self.weather then
      self.weather:draw(g,frame,self.weatherDT or 0)
    end
    restoreWorldTarget(self,g)
    if ext.nativeOverlayDraw then ext.nativeOverlayDraw();restoreWorldTarget(self,g) end
    Extensions.overlay(ext)
    restoreWorldTarget(self,g)
    g.setColor(1,1,1,1)
    end
    self.viewScissor=nil
    if g.setScissor then g.setScissor() end
  end)
  self.viewScissor=nil
  if g.setScissor then pcall(g.setScissor) end

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
  if self.natureActive then self.presentCanvas=Watercolor.resolve(self.presentCanvas,Importer.shaderStyle()) end
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
