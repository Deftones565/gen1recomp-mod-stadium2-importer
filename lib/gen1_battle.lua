-- Gen 1 presentation adapter for the shared Stadium battle scene.
--
-- The host BattleState remains the sole owner of battle mechanics. This file
-- reads its public/runtime presentation state and wraps drawing only: models,
-- stage, camera, HUD composition and native animation placement. It never
-- resolves a turn, changes damage, rolls capture odds, advances the queue,
-- switches a party member, or writes battle RNG.
local Importer = require("mods.STADIUM2_IMPORTER.lib.importer")
local Actor = require("mods.STADIUM2_IMPORTER.lib.battle_actor")
local Presentation = require("mods.STADIUM2_IMPORTER.lib.battle_scene")
local Camera = require("mods.STADIUM2_IMPORTER.lib.battle_camera")
local Hud = require("mods.STADIUM2_IMPORTER.lib.battle_hud")

local Gen1={COUNT=251}
local modRef,installed,session
local configured=151
local originals={}
local unpack=table.unpack or unpack

local SOURCE_ANCHOR={player={26,96},enemy={124,56}}
local HUD_RECT={enemy={8,0,80,32},player={72,56,88,40}}
local TEXT_RECT={box={0,96,160,48},moves={0,64,88,32},mimic={0,56,128,40}}

local function clamp(v,lo,hi)
  return math.max(lo,math.min(hi,tonumber(v) or lo))
end

local function warn(message)
  local log=modRef and modRef.log
  if log and log.warn then pcall(log.warn,log,"%s",tostring(message)) end
end

local function dexOf(data,mon)
  if not mon then return nil end
  if type(mon.species)=="number" then
    local dex=math.floor(mon.species)
    return dex>=1 and dex<=Gen1.COUNT and dex or nil
  end
  local def=data and data.pokemon and data.pokemon[mon.species]
  local dex=def and tonumber(def.dex or def.index)
  dex=dex and math.floor(dex) or nil
  return dex and dex>=1 and dex<=Gen1.COUNT and dex or nil
end

local Scene=setmetatable({},{__index=Presentation})
Scene.__index=Scene

local function actorOptions()
  return {warn=warn,dexOf=dexOf,label="Gen 1 battle"}
end

function Scene.new(battle)
  local opts=actorOptions()
  local self=setmetatable({},Scene)
  Presentation.init(self,{
    actors={player=Actor.new("player",opts),enemy=Actor.new("enemy",opts)},
    warn=warn,label="Gen 1 battle",
  })
  self.battle=battle
  self.game=battle and battle.game
  self.substituteActors={player=Actor.new("player",opts),enemy=Actor.new("enemy",opts)}
  self.lastGrow={player=false,enemy=false}
  self.lastFainted={player=false,enemy=false}
  self.lastPicKind={player=nil,enemy=nil}
  self.animWasPlaying=false
  self.hudSnapped=false
  return self
end

function Scene:release()
  self.substituteActors.player:release()
  self.substituteActors.enemy:release()
  Presentation.release(self)
end

function Scene:shownBattler(side)
  return self.battle and self.battle[side] or nil
end

function Scene:shownMon(side)
  local b=self:shownBattler(side)
  return b and b.mon or nil
end

function Scene:sync()
  local data=self.battle and self.battle.data
  for _,side in ipairs({"player","enemy"}) do
    local actor=self.actors[side]
    local mon=self:shownMon(side)
    if mon then actor:load(data,mon,dexOf(data,mon))
    else actor:release() end
  end
end

local function safeCall(obj,name,...)
  local fn=obj and obj[name]
  if type(fn)~="function" then return nil end
  local ok,value=pcall(fn,obj,...)
  return ok and value or nil
end

function Scene:hostGrow(side)
  local b=self:shownBattler(side)
  return b and safeCall(self.battle,"growInScale",b) or nil
end

function Scene:hostHidden(side)
  local battle,b=self.battle,self:shownBattler(side)
  if not (battle and b) then return true end
  if side=="enemy" and battle.enemyHidden then return true end
  if safeCall(battle,"fxHidden",b) then return true end
  return false
end

function Scene:ownsSlot(side)
  local battle=self.battle
  if not battle then return false end
  if side=="enemy" and battle.showEnemyTrainer and battle.trainerPic then return false end
  if side=="player" and battle.showPlayerBack and battle.playerBackPic then return false end
  if side=="player" and (battle.safari or battle.demo) then return false end
  local b=self:shownBattler(side)
  if not b then return false end
  if b.substituteHP then return self:ensureSubstitute(side)~=nil end
  return self.actors[side] and self.actors[side].renderer~=nil
end

function Scene:ensureSubstitute(side)
  local actor=self.substituteActors[side]
  if actor.renderer then return actor end
  local renderer,err=Importer.newSpecialRenderer("substitute",{
    textureFilter="nearest",anisotropy=4,flipY=false,anchorTravel=true,
  })
  if not renderer then
    warn("Gen 1 Substitute model unavailable: "..tostring(err))
    return nil
  end
  actor.renderer=renderer
  actor.mon={hp=1,species=253}
  actor.dex,actor.variant=253,"normal"
  actor.callbackFrame=side=="enemy" and 4 or 0
  actor:play("idle",true)
  return actor
end

function Scene:visualState(side)
  local battle,b=self.battle,self:shownBattler(side)
  if not self:ownsSlot(side) then return "native" end
  if not b then return "empty" end
  if b.substituteHP then return "substitute" end

  local actor=self.actors[side]
  if b.fainted then
    if actor.context=="faint" and not actor.faintFinished then return "pokemon" end
    return actor.faintFinished and "empty" or "pokemon"
  end

  -- During the trainer/player send-out text the slot is still empty. Once the
  -- host grow animation starts, the 3D model takes over at the exact same time.
  local grow=self:hostGrow(side)
  if side=="enemy" and battle.enemySendingOut and not grow then return "empty" end
  if side=="player" and battle.sendingOut and not grow then return "empty" end
  if self:hostHidden(side) then return "hidden" end
  if (battle.introSlide or 0)>0 and side=="player" then return "empty" end
  return actor.renderer and "pokemon" or "native"
end

function Scene:visualActor(side)
  local state=self:visualState(side)
  if state=="pokemon" then return self.actors[side],state end
  if state=="substitute" then return self:ensureSubstitute(side),state end
  return nil,state
end

function Scene:picScale(side)
  local grow=self:hostGrow(side)
  return grow and clamp(grow,0,1) or 1
end

function Scene:syncPresentationState()
  local battle=self.battle
  if not battle then return end

  -- A host send-out grow is presentation state, so it only starts a Stadium
  -- entrance clip; the host remains responsible for when the mon is actually
  -- considered sent out.
  for _,side in ipairs({"player","enemy"}) do
    local grow=self:hostGrow(side)
    local activeGrow=grow~=nil and grow>0 and grow<1
    if grow and not self.lastGrow[side] then
      self.actors[side]:play("entrance",false)
    end
    self.lastGrow[side]=grow and true or false

    local b=self:shownBattler(side)
    local fainted=b and b.fainted and true or false
    local faintFx=b and safeCall(battle,"fxFaintActive",b) or false
    if (faintFx or fainted) and not self.lastFainted[side]
        and self.actors[side].renderer then
      self.actors[side]:faint()
    end
    self.lastFainted[side]=fainted or faintFx or false

    local pf=b and battle.picFx and battle.picFx[b] or nil
    local kind=pf and pf.kind or nil
    if kind=="blink" and self.lastPicKind[side]~="blink" then
      self.actors[side].flash=.12
    end
    self.lastPicKind[side]=kind
  end

  -- Move rows are already selected and ordered by the host. On the rising edge
  -- of the native animation, ask only the attacking model to play its matching
  -- Stadium move clip. Special host animations (ball toss, faint, send-out)
  -- have no move definition and therefore do not trigger an attack clip.
  local playing=battle.animPlaying and true or false
  if playing and not self.animWasPlaying then
    local name=battle.animName
    local def=battle.data and battle.data.moves and battle.data.moves[name]
    if def then
      local side=battle.animAttackerIsPlayer and "player" or "enemy"
      self.actors[side]:attack(tonumber(def.index or def.number))
    end
  end
  self.animWasPlaying=playing
end

function Scene:update(dt)
  self:sync()
  self:syncPresentationState()
  Camera.update(dt)
  self.actors.player:update(dt)
  self.actors.enemy:update(dt)
  self.substituteActors.player:update(dt)
  self.substituteActors.enemy:update(dt)
  return self:render()
end

local function active(battle)
  return session and battle and session.battle==battle and session or nil
end

local function withFullPaperRemoved(fn)
  local g=love and love.graphics
  if not (g and g.rectangle and g.getColor) then return fn() end
  local rectangle=g.rectangle
  g.rectangle=function(mode,x,y,w,h,...)
    if mode=="fill" and x==0 and y==0 and w==160 and h==144 then
      local r,gg,b,a=g.getColor()
      if r>.99 and gg>.99 and b>.99 and (a or 1)>.99 then return end
    end
    return rectangle(mode,x,y,w,h,...)
  end
  local ok,result=pcall(fn)
  g.rectangle=rectangle
  if not ok then error(result,0) end
  return result
end

local function withBoxPaperRemoved(fn)
  local g=love and love.graphics
  if not (g and g.rectangle and g.getColor) then return fn() end
  local rectangle=g.rectangle
  g.rectangle=function(mode,...)
    if mode=="fill" then
      local r,gg,b,a=g.getColor()
      if r>.99 and gg>.99 and b>.99 and (a or 1)>.99 then return end
    end
    return rectangle(mode,...)
  end
  local ok,result=pcall(fn)
  g.rectangle=rectangle
  if not ok then error(result,0) end
  return result
end

local function hudLive(battle,slide)
  local enemy=battle.enemy and not battle.showEnemyTrainer
    and not battle.enemySendingOut and not safeCall(battle,"growInScale",battle.enemy)
    and slide==0 and not battle.introBalls and not battle.enemy.fainted
  local player=battle.player and not (battle.safari or battle.demo)
    and not battle.showPlayerBack and slide==0
  return enemy and true or false,player and true or false
end

local function textRects(battle)
  if not battle or battle.blankForAskName then return {} end
  local out={TEXT_RECT.box}
  if battle.phase=="moveSelect" then out[#out+1]=TEXT_RECT.moves end
  if battle.phase=="mimicSelect" then out[#out+1]=TEXT_RECT.mimic end
  return out
end

function Scene:captureHud(slide)
  if not originals.drawHUDs then return nil end
  local battle=self.battle
  local had=rawget(battle,"colorMode")
  battle.colorMode=function() return false end
  local ok,layer=pcall(Hud.hudLayer,function()
    originals.drawHUDs(battle,slide)
  end)
  battle.colorMode=had
  if not ok then error(layer,0) end
  return layer
end

-- Build the full-window world image that Renderer.worldOverride consumes.
-- Status bands are detached from the 160x144 battle canvas, while the message
-- box remains in the centred native frame. Only presentation pixels move.
function Scene:composeWorld()
  if not (self.readyFrame and self.hudBox and love and love.graphics) then
    return self.presentCanvas or self.canvas
  end
  local battle=self.battle
  local slide=(battle.introSlide or 0)*4
  local hudLayer=self:captureHud(slide)
  local target,sx,sy=self:copyForComposite()
  if not target then return self.presentCanvas or self.canvas end

  local g=love.graphics
  local previous=g.getCanvas and {g.getCanvas()} or nil
  local oldBlend,oldAlpha=g.getBlendMode()
  local ok,err=pcall(function()
    g.setCanvas(target)
    g.setBlendMode("alpha","alphamultiply")
    g.push()
    g.scale(sx,sy)
    local box,s=self.hudBox,self.hudBox.scale
    local enemyLive,playerLive=hudLive(battle,slide)
    local er,pr=HUD_RECT.enemy,HUD_RECT.player

    if enemyLive then Hud.panel(self,{0,box.ly+er[2]*s,er[3]*s,er[4]*s}) end
    if playerLive then
      Hud.panel(self,{self.width-pr[3]*s,box.ly+pr[2]*s,pr[3]*s,pr[4]*s})
    end
    for _,r in ipairs(textRects(battle)) do
      Hud.panel(self,{box.lx+r[1]*s,box.ly+r[2]*s,r[3]*s,r[4]*s})
    end

    if hudLayer then
      g.setColor(1,1,1,1)
      local enemy=g.newQuad(0,0,160,48,160,144)
      local player=g.newQuad(0,48,160,48,160,144)
      -- Native HP/caught-marker tiles carry white paper. Key that paper out
      -- exactly like the shared Gen 2 HUD so only ink/gauge/icon pixels sit
      -- on the frosted Stadium panels.
      local oldShader=g.getShader and g.getShader() or nil
      local key=Hud.gaugeShader and Hud.gaugeShader() or nil
      if key then g.setShader(key) end
      -- Move the source band far enough that the actual HUD rectangle, not its
      -- built-in Game Boy inset, touches the corresponding window edge.
      g.draw(hudLayer,enemy,-er[1]*s,box.ly,0,s,s)
      g.draw(hudLayer,player,self.width-(pr[1]+pr[3])*s,box.ly+48*s,0,s,s)
      if key then g.setShader(oldShader) end
    end
    g.pop()
  end)
  if previous and #previous>0 then g.setCanvas(unpack(previous)) else g.setCanvas() end
  g.setBlendMode(oldBlend or "alpha",oldAlpha)
  g.setColor(1,1,1,1)
  if not ok then error(err,0) end
  self.hudSnapped=true
  return target
end

local function animationProjection(anchors)
  if not (anchors and anchors.player and anchors.enemy) then return nil end
  local p0,e0=SOURCE_ANCHOR.player,SOURCE_ANCHOR.enemy
  local spx,spy=(p0[1]+e0[1])*.5,(p0[2]+e0[2])*.5
  local dpx,dpy=(anchors.player[1]+anchors.enemy[1])*.5,
    (anchors.player[2]+anchors.enemy[2])*.5
  local svx,svy=e0[1]-p0[1],e0[2]-p0[2]
  local dvx,dvy=anchors.enemy[1]-anchors.player[1],anchors.enemy[2]-anchors.player[2]
  local sourceLength=math.sqrt(svx*svx+svy*svy)
  local destLength=math.sqrt(dvx*dvx+dvy*dvy)
  return {dx=dpx-spx,dy=dpy-spy,scale=clamp(destLength/sourceLength,.5,2),
    originX=spx,originY=spy}
end

local function installHooks()
  local BattleState=require("src.battle.BattleState")
  if BattleState.stadium2ImporterGen1 then return true end
  BattleState.stadium2ImporterGen1=true

  originals.isWideBattleLayout=BattleState.isWideBattleLayout
  function BattleState:isWideBattleLayout()
    if active(self) then return false end
    return originals.isWideBattleLayout(self)
  end

  originals.draw=BattleState.draw
  function BattleState:draw(...)
    local args={...}
    local scene=active(self)
    if not scene then return originals.draw(self,unpack(args)) end
    scene.battle=self
    scene.game=self.game
    scene:sync()
    if not scene.readyFrame then scene:render() end

    local world=scene:composeWorld()
    scene.composedWorld=world
    scene.composeReady=world~=nil

    -- The host battle now contributes UI only. render.compose places this
    -- 160x144 native layer at the SAME 304x144-derived scale as the shared 3D
    -- camera, so a large or HiDPI window cannot re-inflate the Gen 1 UI.
    love.graphics.clear(0,0,0,0)
    self.stadium2ImporterGen1Shot=scene
    scene.hudSnapped=false
    -- composeWorld already put the detached HUD in the world image.
    scene.hudSnapped=true

    local hadColor=rawget(self,"colorMode")
    self.colorMode=function() return false end
    local ok,result=pcall(function()
      return withFullPaperRemoved(function() return originals.draw(self,unpack(args)) end)
    end)
    self.colorMode=hadColor
    self.stadium2ImporterGen1Shot=nil
    if not ok then error(result,0) end
    return result
  end

  originals.drawPicsLayer=BattleState.drawPicsLayer
  function BattleState:drawPicsLayer(slide,sx,sy,onlySide,skipMenuClip)
    local scene=active(self)
    if not scene then
      return originals.drawPicsLayer(self,slide,sx,sy,onlySide,skipMenuClip)
    end
    local ownP,ownE=scene:ownsSlot("player"),scene:ownsSlot("enemy")
    if ownP and ownE then return end
    if ownP and not ownE then
      if onlySide=="player" then return end
      return originals.drawPicsLayer(self,slide,sx,sy,"enemy",skipMenuClip)
    end
    if ownE and not ownP then
      if onlySide=="enemy" then return end
      return originals.drawPicsLayer(self,slide,sx,sy,"player",skipMenuClip)
    end
    return originals.drawPicsLayer(self,slide,sx,sy,onlySide,skipMenuClip)
  end

  originals.drawHUDs=BattleState.drawHUDs
  function BattleState:drawHUDs(slide)
    local scene=active(self)
    if scene and scene.hudSnapped then return end
    return originals.drawHUDs(self,slide)
  end

  originals.drawTextArea=BattleState.drawTextArea
  function BattleState:drawTextArea(...)
    local args={...}
    if not active(self) then return originals.drawTextArea(self,unpack(args)) end
    return withBoxPaperRemoved(function()
      return originals.drawTextArea(self,unpack(args))
    end)
  end

  originals.drawAnimLayer=BattleState.drawAnimLayer
  function BattleState:drawAnimLayer(colorized)
    local scene=active(self)
    local projection=animationProjection(scene and scene.uiAnchors)
    if not projection then return originals.drawAnimLayer(self,colorized) end
    local g=love.graphics
    g.push()
    g.translate(projection.dx,projection.dy)
    if projection.scale~=1 then
      g.translate(projection.originX,projection.originY)
      g.scale(projection.scale,projection.scale)
      g.translate(-projection.originX,-projection.originY)
    end
    local ok,result=pcall(originals.drawAnimLayer,self,false)
    g.pop()
    if not ok then error(result,0) end
    return result
  end

  return true
end

local function installComposeHook()
  local hooks=modRef and modRef.hooks
  if not (hooks and type(hooks.wrap)=="function") then return false end
  hooks:wrap("render.compose",function(next,renderer,ctx)
    local scene=session
    if not (scene and scene.composeReady and scene.composedWorld and ctx
        and ctx.uiCanvas and ctx.ww and ctx.wh and love and love.graphics) then
      return next(renderer,ctx)
    end
    scene.composeReady=false
    local g=love.graphics
    local dpiX,dpiY=tonumber(ctx.dpiX) or 1,tonumber(ctx.dpiY) or 1
    if dpiX<=0 then dpiX=1 end
    if dpiY<=0 then dpiY=1 end
    g.setCanvas()
    g.setColor(0,0,0,1)
    g.rectangle("fill",0,0,ctx.ww,ctx.wh)
    g.setColor(1,1,1,1)
    local major=love.getVersion and select(1,love.getVersion()) or 11
    local ios=love.system and love.system.getOS and love.system.getOS()=="iOS"
    if ios and major>=12 then
      g.draw(scene.composedWorld,0,ctx.wh,0,1/dpiX,-1/dpiY)
    else
      g.draw(scene.composedWorld,0,0,0,1/dpiX,1/dpiY)
    end

    local scale=Camera.fitScale(ctx.ww,ctx.wh)
    local ox,oy=Camera.fitOrigin(ctx.ww,ctx.wh,scale)
    if renderer and renderer.blitCanvas then
      renderer:blitCanvas(ctx.uiCanvas,scale,scale,ctx.zones,scale,scale,
        ox,oy,0,0,ctx.ww,ctx.wh,dpiX,dpiY)
    else
      g.draw(ctx.uiCanvas,ox,oy,0,scale,scale)
    end
    g.setColor(1,1,1,1)
    return true
  end,110)
  return true
end

function Gen1.bind(mod)
  modRef=mod
  return Gen1
end

function Gen1.configureGame(game)
  local maxDex=151
  local pokemon=game and game.data and game.data.pokemon
  if type(pokemon)=="table" then
    for _,def in pairs(pokemon) do
      if type(def)=="table" then
        local dex=tonumber(def.dex or def.index)
        if dex and dex>maxDex and dex<=Gen1.COUNT then maxDex=math.floor(dex) end
      end
    end
  end
  configured=maxDex
  Importer.configure({count=maxDex})
  return maxDex
end

function Gen1.install()
  if installed then return true end
  local ok,err=pcall(installHooks)
  if not ok then warn(err); return false end
  local composeOk,composeErr=pcall(installComposeHook)
  if not composeOk or not composeErr then
    warn(composeOk and "render.compose hook unavailable" or composeErr)
    return false
  end
  installed=true
  return true
end

function Gen1.ensure(battle)
  if not (installed and battle and Importer.modelsEnabled()
      and Importer.battleEnabled() and Importer.available(configured)) then
    return false
  end
  if session and session.battle==battle then return true end
  Gen1.finish()
  session=Scene.new(battle)
  session:sync()
  return true
end

function Gen1.update(dt)
  if not session then return false end
  return session:update(math.min(math.max(tonumber(dt) or 0,0),.1))
end

function Gen1.finish(battle)
  if battle and session and session.battle~=battle then return false end
  if session then
    if session.battle then
      session.battle.stadium2ImporterGen1Shot=nil
    end
    session:release()
    session=nil
  end
  return true
end

function Gen1.enabled()
  return Importer.modelsEnabled() and Importer.battleEnabled()
end

function Gen1.ready()
  return Importer.available(configured)
end

function Gen1.status()
  return {
    enabled=Gen1.enabled(),ready=Gen1.ready(),count=configured,generation=1,
    active=session~=nil,
    shot=session and (session.compositeCanvas or session.presentCanvas or session.canvas) or nil,
    defect=session and session.defect or nil,
    visual=session and {
      player=session:visualState("player"),enemy=session:visualState("enemy"),
    } or nil,
  }
end

function Gen1.resetForTests()
  Gen1.finish()
  installed=false
  modRef=nil
  configured=151
end

Gen1.Actor=Actor
Gen1.Scene=Scene
Gen1._animationProjection=animationProjection
Gen1._hudLive=hudLive
Gen1._textRects=textRects

return Gen1
