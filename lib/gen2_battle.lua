-- Native Gold/Gen 2 battle adapter for Stadium 2 models.
--
-- Gold does not instantiate src.battle.BattleState or src.core.Game.  Its
-- battle presenter is src.ui.gen2.BattleState and its battlers are the mon
-- records themselves (not Gen 1 battler wrappers).  Keep that distinction in
-- one module so Gen 2 battle ownership stays isolated from Gen 1.
local Importer = require("mods.STADIUM2_IMPORTER.lib.importer")
local Renderer = require("mods.STADIUM2_IMPORTER.lib.renderer")
local Camera = require("mods.STADIUM2_IMPORTER.lib.battle_camera")
local Stage = require("mods.STADIUM2_IMPORTER.lib.battle_stage")
local Shadow = require("mods.STADIUM2_IMPORTER.lib.battle_shadow")
local Sky = require("mods.STADIUM2_IMPORTER.lib.battle_sky")
local Hud = require("mods.STADIUM2_IMPORTER.lib.battle_hud")
local AA = require("mods.STADIUM2_IMPORTER.lib.battle_aa")
local Unown = require("src.core.gen2.Unown")

local Gen2 = { COUNT = 251 }
local modRef, installed, session
local configured = 251
local unpack = table.unpack or unpack

local function clamp(value, lo, hi)
  return math.max(lo, math.min(hi, tonumber(value) or lo))
end

local function warn(message)
  local log = modRef and modRef.log
  if log and log.warn then pcall(log.warn, log, "%s", tostring(message)) end
end

local function dexOf(data, mon)
  if not mon then return nil end
  if type(mon.species) == "number" then return math.floor(mon.species) end
  local def = data and data.pokemon and data.pokemon[mon.species]
  local dex = def and tonumber(def.dex or def.index)
  dex = dex and math.floor(dex) or nil
  if not dex or dex < 1 or dex > Gen2.COUNT then return nil end
  return dex
end

local function shiny(mon)
  if mon and mon.shiny ~= nil then return mon.shiny and true or false end
  local d = mon and mon.dvs
  local attacks = { [2]=true, [3]=true, [6]=true, [7]=true,
    [10]=true, [11]=true, [14]=true, [15]=true }
  return d and d.defense == 10 and d.speed == 10 and d.special == 10
    and attacks[d.attack] == true or false
end

local function unownPack(mon,dex,variant)
  if dex~=201 then return nil end
  local letter=Unown.index(mon and mon.unownLetter)
    or Unown.letterFromDVs(mon and mon.dvs)
  if not letter or letter<=1 then return nil end -- A is the ordinary #201 pack
  local name="unown_"..Unown.name(letter):lower()
  return variant=="shiny" and (name.."_shiny") or name
end

local Actor = {}
Actor.__index = Actor
local STATE_RANK={idle=0,entrance=1,attack=2,attack_default=2,faint=3}

function Actor.new(side)
  return setmetatable({ side=side, mon=nil, dex=nil, variant=nil,
    renderer=nil, context="idle", callbackFrame=0, grow=nil, flash=0,
    faintFinished=false, pendingFaint=false, failedFor=nil,failedForm=nil,
    form=nil }, Actor)
end

function Actor:release()
  if self.renderer and self.renderer.release then
    pcall(self.renderer.release, self.renderer)
  end
  self.renderer, self.mon, self.dex, self.variant, self.form = nil,nil,nil,nil,nil
  self.grow, self.flash, self.faintFinished = nil, 0, false
  self.pendingFaint = false
  self.context, self.callbackFrame = "idle", 0
end

function Actor:retire(reason)
  -- A battle actor never turns a renderer failure into permission for Gold's
  -- native pic to come back.  Keep the rig resident so the last complete
  -- owned frame remains usable and report the defect through the scene.
  if reason then warn("Gen 2 battle model retired: "..tostring(reason)) end
  return false
end

function Actor:play(context, loop)
  if not self.renderer then return false end
  local now,want=STATE_RANK[self.context] or 0,STATE_RANK[context] or 0
  if self.context == "faint" or want<now then return false end
  local actual=context
  local ok = self.renderer:setContext(actual, loop)
  if not ok and actual == "attack" then
    actual="attack_default"
    ok = self.renderer:setContext(actual, loop)
  end
  if not ok and actual ~= "idle" then
    actual="idle"
    ok = self.renderer:setContext("idle", true)
  end
  self.context = ok and actual or "idle"
  if ok then self.renderer.finished = false end
  return ok
end

function Actor:load(data, mon, forcedDex)
  local dex = forcedDex or dexOf(data, mon)
  local variant = shiny(mon) and "shiny" or "normal"
  local form=unownPack(mon,dex,variant)
  if not dex then self:release(); return false end
  if self.renderer and self.mon == mon and self.dex == dex
      and self.variant == variant and self.form==form then return true end
  if self.failedFor == mon and self.dex == dex and self.failedForm==form then
    return false
  end
  self:release()
  local options={
    textureFilter="nearest", anisotropy=4, flipY=false, anchorTravel=true,
  }
  local renderer,err
  if form then renderer,err=Importer.newSpecialRenderer(form,options)
  else renderer,err=Importer.newRenderer(dex,variant,options) end
  self.mon,self.dex,self.variant,self.form=mon,dex,variant,form
  if not renderer then
    self.failedFor = mon
    self.failedForm = form
    warn(("Gen 2 battle model %03d (%s) unavailable: %s")
      :format(dex, variant, tostring(err)))
    return false
  end
  self.failedFor,self.failedForm=nil,nil
  self.renderer = renderer
  -- The reference renderer deliberately offsets the opponent's model-local
  -- texture/FX clock so the pair do not blink and flicker in lockstep.
  self.callbackFrame = self.side=="enemy" and 4 or 0
  self:play("idle", true)
  return true
end

function Actor:attack(moveIndex)
  if not self.renderer or self.pendingFaint or self.context=="faint" then return false end
  if (STATE_RANK[self.context] or 0)>STATE_RANK.attack then return false end
  local ok = moveIndex and self.renderer:setMove(moveIndex, false) or false
  if not ok then ok = self:play("attack", false) end
  if ok then self.context = "attack" end
  return ok
end

function Actor:entrance()
  if self.context=="faint" then return false end
  self.grow = { time=0, duration=0.65 }
  self.faintFinished = false
  self.pendingFaint = false
  return self:play("entrance", false)
end

function Actor:faint()
  if not self.renderer or self.context=="faint" then return false end
  self.grow = nil
  self.pendingFaint = false
  self.faintFinished = false
  return self:play("faint", false)
end

function Actor:scale()
  if not self.grow then return 1 end
  local t = clamp(self.grow.time / self.grow.duration, 0, 1)
  -- Stadium's send-out settles at both ends instead of snapping into motion.
  t=t*t*(3-2*t)
  return t
end

function Actor:update(dt)
  if not self.renderer then return end
  if self.grow then
    self.grow.time = self.grow.time + dt
    if self.grow.time >= self.grow.duration then self.grow = nil end
  end
  self.flash = math.max(0, (self.flash or 0) - dt)
  self.callbackFrame = self.callbackFrame + dt * 30
  -- This is the path that advances texture swaps, material callbacks and
  -- model-local FX such as Charmander's flame at Stadium's authored 30 Hz.
  self.renderer:setHandlerRuntime({
    callbackFrame=math.floor(self.callbackFrame),
    frame=self.renderer.frame, textureFrame=self.renderer.frame,
    species=self.dex,
  }, true)
  self.renderer:step(dt)
  if self.renderer.finished then
    if self.context == "faint" then
      self.faintFinished = true
    elseif self.context ~= "idle" then
      self.context="idle"
      self:play("idle", true)
    end
  end
end

local Scene = {}
Scene.__index = Scene

function Scene.new(battle)
  return setmetatable({ battle=battle, screen=nil,
    actors={player=Actor.new("player"), enemy=Actor.new("enemy")},
    substituteActors={player=Actor.new("player"),enemy=Actor.new("enemy")},
    canvas=nil, presentCanvas=nil, depth=nil, width=0, height=0,
    renderWidth=0, renderHeight=0,
    stickX=0, stickY=0, hudBox=nil, uiAnchors=nil, environment=nil,
    readyFrame=false, defect=nil, substituteActive={player=false,enemy=false},
    vanish={player={active=false},enemy={active=false}},
  }, Scene)
end

function Scene:release()
  self.actors.player:release()
  self.actors.enemy:release()
  self.substituteActors.player:release()
  self.substituteActors.enemy:release()
  if self.canvas and self.canvas.release then pcall(self.canvas.release, self.canvas) end
  if self.depth and self.depth.release then pcall(self.depth.release, self.depth) end
  self.canvas, self.depth = nil, nil
  self.presentCanvas = nil
  Stage.invalidate()
  Shadow.release()
  Hud.invalidate()
  AA.release()
  Camera.reset()
end

function Scene:shownMon(side)
  if self.screen and self.screen.activeMon then
    local ok, mon = pcall(self.screen.activeMon, self.screen, side)
    if ok then return mon end
  end
  return self.battle and self.battle[side] or nil
end

function Scene:sync()
  local data = self.screen and self.screen.game and self.screen.game.data
    or self.battle and self.battle.data
  for _, side in ipairs({"player", "enemy"}) do
    local actor, mon = self.actors[side], self:shownMon(side)
    -- Do not follow an in-place Transform until its queue event is presented;
    -- Gold resolves a whole turn before showing its first message.
    if actor.mon ~= mon then actor:load(data, mon) end
  end
end

-- Whether this scene owns the Pokemon pic slot.  Ownership is deliberately
-- independent of whether anything is visible this frame: Fly, Dig, capture,
-- faint and Substitute all leave the slot owned while changing its contents.
-- Trainer art is the sole native pic allowed through because it is not a
-- Pokemon sprite.
function Scene:ownsSlot(side, screen)
  screen = screen or self.screen
  if not screen then return false end
  if side == "player" and screen.showPlayerTrainer then return false end
  if side == "enemy" and screen.showEnemyTrainer then return false end
  return true
end

-- Compatibility name retained for diagnostics/tests that used the old API.
-- It now means ownership, not visibility.
function Scene:covered(side, screen)
  return self:ownsSlot(side,screen)
end

function Scene:volatileFor(side)
  local actor,battle=self.actors[side],self.battle
  if not (actor and actor.mon and battle and battle.volatile) then return nil end
  local ok,value=pcall(battle.volatile,battle,actor.mon)
  return ok and value or nil
end

function Scene:visualState(side, screen)
  screen=screen or self.screen
  if not self:ownsSlot(side,screen) then return "trainer" end
  local actor=self.actors[side]
  if not (actor and actor.mon) then return "empty" end
  local volatile=self:volatileFor(side)
  local substituted=self.substituteActive and self.substituteActive[side]
  if substituted==nil then substituted=volatile and volatile.substitute end
  if substituted then return "substitute" end
  if (actor.mon.hp or 0)<=0 then
    if actor.context=="faint" and not actor.faintFinished then return "pokemon" end
    -- Gold resolves the whole turn before presenting its queue, so live HP
    -- may already be zero while the hit and bar drain are still being shown.
    -- Only the completed authored collapse empties the owned slot.
    if actor.faintFinished then return "empty" end
    return "pokemon"
  end
  local state = screen.animPicState and screen:animPicState(side) or nil
  -- A successful catch latches picHidden.enemy before ANIM_THROW_POKE_BALL
  -- starts.  That latch describes the state AFTER the ball animation; using it
  -- immediately makes the 3D foe disappear before the ball ever reaches it.
  -- While the throw is running, the animation's own ReturnMon state is the
  -- authority: full -> smaller -> smaller -> hidden.  Once the animation ends
  -- the latch becomes authoritative again and keeps the caught slot empty.
  local caughtInFlight = side=="enemy" and screen.anim
    and screen.ballThrow and screen.ballThrow.caught
  if screen.picHidden and screen.picHidden[side] and actor.context~="faint"
      and not caughtInFlight then
    return "empty"
  end
  local vanish=self.vanish and self.vanish[side]
  if vanish and vanish.mode=="depart" then
    if state and state.hidden then vanish.active=true end
    if not screen.anim then vanish.active,vanish.mode=true,nil end
    return (state and not state.hidden and not vanish.active) and "pokemon" or "hidden"
  elseif vanish and vanish.mode=="return" then
    if state and state.hidden then vanish.sawHidden=true end
    if not screen.anim or (vanish.sawHidden and state and not state.hidden) then
      vanish.active,vanish.mode,vanish.sawHidden=false,nil,nil
      return actor.renderer and "pokemon" or "defect"
    end
    return "hidden"
  elseif vanish and vanish.active then
    -- A cancelled/disabled charge clears the battle volatile without playing
    -- the stored move's return animation.
    if not (volatile and volatile.vanished) and not screen.anim then
      vanish.active=false
    else
      return "hidden"
    end
  end
  if state and state.hidden and not actor.grow then return "hidden" end
  -- Gold's BG animation state exists only while the current script runs.
  -- `vanished` is the persistent truth between Fly/Dig's two turns.
  if volatile and volatile.vanished then return "hidden" end
  if not actor.renderer then return "defect" end
  return "pokemon"
end

function Scene:ensureSubstitute(side)
  local actor=self.substituteActors[side]
  if actor.renderer then return actor end
  local renderer,err=Importer.newSpecialRenderer("substitute",{
    textureFilter="nearest",anisotropy=4,flipY=false,anchorTravel=true,
  })
  if not renderer then
    self.defect="Stadium 2 Substitute model unavailable: "..tostring(err)
    warn(self.defect)
    return nil
  end
  actor.renderer=renderer
  actor.mon={hp=1,species=253}
  actor.dex,actor.variant=253,"normal"
  actor.callbackFrame=side=="enemy" and 4 or 0
  actor:play("idle",true)
  return actor
end

function Scene:visualActor(side,screen)
  local state=self:visualState(side,screen)
  if state=="pokemon" then return self.actors[side],state end
  if state=="substitute" then
    local actor=self:ensureSubstitute(side)
    if not actor then error(self.defect or "Substitute renderer unavailable",0) end
    return actor,state
  end
  if state=="defect" then
    error(("Gen 2 %s Pokemon renderer unavailable"):format(side),0)
  end
  return nil,state
end

-- `covered` answers whether the native battle pic is replaced.  Drawing the
-- model is a separate question at the tail of a faint: the replacement still
-- owns the pic slot, but the held terminal pose has finished and should leave
-- the platform empty.
function Scene:modelVisible(side, screen)
  return self:visualState(side,screen)=="pokemon"
end

function Scene:handleEvent(event)
  if not event or event._stadium2Gen2Handled then return end
  event._stadium2Gen2Handled = true
  self:sync()
  local side = event.side
  if event.kind=="move" and side then
    local data=self.screen and self.screen.game and self.screen.game.data
    local def=data and data.moves and data.moves[event.move]
    if def and def.effect=="EFFECT_SUBSTITUTE" and not event.missed then
      self.substituteActive[side]=true
    end
    if def and def.effect=="EFFECT_FLY" and not event.missed then
      local flight=self.vanish[side]
      local volatile=self:volatileFor(side)
      if volatile and volatile.chargeMove==event.move then
        flight.active,flight.mode,flight.sawHidden=false,"depart",nil
      elseif flight.active or (volatile and volatile.vanished) then
        flight.active,flight.mode,flight.sawHidden=true,"return",false
      end
    end
  elseif event.kind=="message" and type(event.text)=="string"
      and event.text:find("SUBSTITUTE broke!",1,true) then
    for _,which in ipairs({"player","enemy"}) do
      local mon=self.actors[which] and self.actors[which].mon
      local name=mon and tostring(mon.nickname or mon.name or mon.species or "") or ""
      local shown=name
      if self.screen and self.screen.name then
        local ok,value=pcall(self.screen.name,self.screen,mon)
        if ok and value then shown=tostring(value) end
      end
      if shown~="" and event.text:find(shown,1,true) then
        self.substituteActive[which]=false
      end
    end
  end
  if event.kind == "move" and side then
    local actor = self.actors[side]
    local data = self.screen and self.screen.game and self.screen.game.data
    local def = data and data.moves and data.moves[event.move]
    if actor then actor:attack(def and tonumber(def.index or def.number)) end
  elseif event.kind == "damage" and side then
    local actor = self.actors[side]
    if actor then actor.flash = 0.12 end
  elseif event.kind == "faint" and side then
    local actor = self.actors[side]
    -- Gold first chases the HP bar and begins its native sink.  Starting the
    -- Stadium clip at damage time makes it finish before the faint message.
    if actor then actor.pendingFaint=true end
  elseif (event.kind == "send" or event.kind == "sendout") and side then
    self.substituteActive[side]=false
    self.vanish[side]={active=false}
    self:sync()
    local actor = self.actors[side]
    if actor then actor:entrance() end
  elseif event.kind == "sendout" then
    self.substituteActive.player=false
    self.vanish.player={active=false}
    self:sync()
    self.actors.player:entrance()
  elseif event.kind == "transform" and side and event.mon then
    local data = self.screen and self.screen.game and self.screen.game.data
    self.actors[side]:load(data, event.mon, dexOf(data, event.mon))
    self.actors[side]:play("entrance", false)
  end
end

function Scene:ensureCanvas(width, height)
  if self.canvas and self.renderWidth == width and self.renderHeight == height then return true end
  if self.canvas and self.canvas.release then pcall(self.canvas.release, self.canvas) end
  if self.depth and self.depth.release then pcall(self.depth.release, self.depth) end
  local g = love and love.graphics
  if not g then return false end
  local msaa=0
  local ok, canvas = pcall(g.newCanvas, width, height,
    {format="rgba8", readable=true, dpiscale=1})
  if not ok then
    msaa=0
    ok, canvas = pcall(g.newCanvas, width, height,
      {format="rgba8", readable=true, dpiscale=1})
  end
  if not ok then warn(canvas); return false end
  local depthOk, depth = pcall(g.newCanvas, width, height,
    {format="depth24stencil8", readable=false, dpiscale=1, msaa=msaa})
  if not depthOk then
    depthOk, depth = pcall(g.newCanvas, width, height,
      {format="depth24stencil8", readable=false, dpiscale=1})
  end
  self.canvas, self.depth = canvas, depthOk and depth or nil
  self.renderWidth, self.renderHeight = width, height
  canvas:setFilter("nearest", "nearest")
  return true
end

local function mul(a, b) return Renderer.matMul(a, b) end
local function translate(x, y, z)
  return {1,0,0,x, 0,1,0,y, 0,0,1,z, 0,0,0,1}
end
local function scale(value)
  return {value,0,0,0, 0,value,0,0, 0,0,value,0, 0,0,0,1}
end
local function rotateY(angle)
  local c, s = math.cos(angle), math.sin(angle)
  return {c,0,s,0, 0,1,0,0, -s,0,c,0, 0,0,0,1}
end

-- Gold's ReturnMon/EnterMon resize scripts use three discrete pic sizes per
-- side.  During a Pokeball throw, follow those authored states with the 3D
-- model as a smooth piece of geometry rather than leaving it full-sized until
-- the final hidden bit.  Outside a ball animation Stadium's own entrance/faint
-- animation owns model scale, so this deliberately returns 1.
local PIC_SCALE = {
  player = { [0]=1, [1]=4/6, [2]=2/6 },
  enemy  = { [3]=1, [4]=5/7, [5]=3/7 },
}

function Scene:picScale(side,screen)
  screen=screen or self.screen
  if not (screen and screen.anim and screen.ballThrow and screen.animPicState) then
    return 1
  end
  local ok,state=pcall(screen.animPicState,screen,side)
  if not ok or type(state)~="table" then return 1 end
  local size=tonumber(state.size)
  return (PIC_SCALE[side] and PIC_SCALE[side][size]) or 1
end

function Scene:modelMatrix(side,actor)
  actor=actor or self.actors[side]
  local metrics = actor.renderer:worldMetrics()
  local worldHeight = clamp(14 * math.sqrt(metrics.height / 52.25), 5, 18)
  local k = worldHeight / metrics.height * actor:scale() * self:picScale(side)
  local p = Stage.positions[side]
  local yaw = side == "player" and math.pi or 0
  local hover = math.min(math.max(metrics.floor, 0), metrics.height * 0.5)
  return mul(translate(p[1], p[2], p[3]),
    mul(rotateY(yaw), mul(scale(k), translate(0, -(metrics.floor-hover), 0)))), yaw
end

local function surfaceDimensions(g, requestedWidth, requestedHeight)
  if not g then return nil end

  -- Gen1Recomp's Gen 2 presenter lays out every widescreen screen in LOVE
  -- window units.  Framebuffer pixels are a separate metric on HiDPI/mobile
  -- displays and must only decide render-target resolution, never HUD scale,
  -- letterbox origin, or battle-animation anchors.
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
        -- Keep the physical render target matched to the requested logical
        -- presentation rect even if a resize lands between update and draw.
        pixelWidth=math.max(1,math.floor(width*pw/windowWidth+.5))
        pixelHeight=math.max(1,math.floor(height*ph/windowHeight+.5))
      else
        pixelWidth,pixelHeight=math.floor(pw),math.floor(ph)
      end
    end
  end
  return width,height,pixelWidth,pixelHeight
end

function Scene:render(requestedWidth,requestedHeight)
  local hadFrame=self.readyFrame
  local g = love and love.graphics
  if not (g and g.newCanvas) then return false end
  local width,height,pixelWidth,pixelHeight=surfaceDimensions(
    g,requestedWidth,requestedHeight)
  if not width then return false end
  local renderWidth,renderHeight=AA.expand(pixelWidth,pixelHeight)
  if not self:ensureCanvas(renderWidth,renderHeight) then return false end
  -- Public scene geometry is always in the same LOVE-unit coordinate space as
  -- BattleState:drawWidescreen(width,height).  Only canvas allocation below
  -- uses framebuffer pixels.
  self.width,self.height=width,height
  local previous = g.getCanvas and {g.getCanvas()} or nil
  local ok, err = pcall(function()
    if self.depth then g.setCanvas({self.canvas, depthstencil=self.depth})
    else g.setCanvas(self.canvas) end
    self.environment = Sky.resolve(self.screen and self.screen.game)
    Sky.draw(g,renderWidth,renderHeight,self.environment)
    local frame = Camera.frame(width,height)
    local vp = frame.vp
    self.hudBox = frame.letterbox
    local matrices = {}
    local drawActors={}
    for _, side in ipairs({"enemy", "player"}) do
      local actor=self:visualActor(side)
      if actor and actor.renderer then
        drawActors[side]=actor
        matrices[side] = {self:modelMatrix(side,actor)}
      end
    end
    local lightVP=Shadow.begin(self.environment.light,self.environment.shadowStrength)
    if lightVP then
      for _,side in ipairs({"enemy","player"}) do
        local actor,entry=drawActors[side],matrices[side]
        if entry and actor.renderer then
          local drawn,drawErr=actor.renderer:drawShadowMap(entry[1],lightVP)
          if not drawn then warn("Gen 2 shadow draw failed: "..tostring(drawErr)) end
        end
      end
    end
    local shadow=lightVP and Shadow.finish() or nil
    if self.depth then g.setCanvas({self.canvas,depthstencil=self.depth})
    else g.setCanvas(self.canvas) end
    -- Stage anchors are measured in logical presentation units.  The
    -- projection has the same aspect in the larger physical AA target, so
    -- rendering at HiDPI resolution leaves HUD/animation framing unchanged.
    local marks,stageErr=Stage.draw(g,width,height,frame,self.actors,shadow,self.environment)
    if not marks then error("Gen 2 stage draw failed: "..tostring(stageErr)) end
    local box=frame.letterbox
    self.uiAnchors={
      player={(marks.player.x-box.lx)/box.scale,(marks.player.y-box.ly)/box.scale},
      enemy={(marks.enemy.x-box.lx)/box.scale,(marks.enemy.y-box.ly)/box.scale},
    }
    for _, pass in ipairs({"opaque", "additive"}) do
      for _, side in ipairs({"enemy", "player"}) do
        local actor, entry = drawActors[side], matrices[side]
        if entry and actor.renderer then
          local base=self.environment.modelTint or {1,1,1}
          local drawn, drawErr = actor.renderer:drawScene(pass, entry[1], {
            viewProjection=vp,
            normalMatrix=Renderer.normalMatrix(entry[2], 0, false),
            lightDir=self.environment.light, ambient=self.environment.ambient,
            -- Pose callbacks run from Actor:update (extension stage 2).  The
            -- render-stage callbacks run once with opaque geometry and their
            -- resulting texture/material state is reused by attached FX.
            diffuse=self.environment.diffuse, skipHandlers=pass=="additive",
            flipWinding=true,disableCulling=true,
            tint={base[1],base[2],base[3],1},
            flashAmount=actor.flash>0 and .5 or 0,
            sunMap=shadow and shadow.map, sunVP=shadow and shadow.sunVP,
            sunDark=shadow and shadow.sunDark, sunBias=shadow and shadow.sunBias,
            sunTexel=shadow and shadow.sunTexel,
          })
          if not drawn then
            error("Gen 2 model draw failed: "..tostring(drawErr))
          end
        end
      end
    end
    g.setColor(1,1,1,1)
  end)
  if previous and #previous > 0 then pcall(g.setCanvas, unpack(previous))
  else pcall(g.setCanvas) end
  if g.setShader then pcall(g.setShader) end
  if g.setDepthMode then pcall(g.setDepthMode, "always", false) end
  if g.setMeshCullMode then pcall(g.setMeshCullMode, "none") end
  if g.setBlendMode then pcall(g.setBlendMode, "alpha", "alphamultiply") end
  if not ok then
    self.defect=tostring(err)
    self.readyFrame=hadFrame
    warn(err)
    return false
  end
  self.presentCanvas=AA.resolve(self.canvas,pixelWidth,pixelHeight)
  Hud.build(self.presentCanvas)
  self.readyFrame=true
  self.defect=nil
  return true
end

function Scene:update(dt)
  self:sync()
  for _,side in ipairs({"player","enemy"}) do
    local actor=self.actors[side]
    if actor.pendingFaint then
      local shown=self.screen and self.screen.shownHp and self.screen.shownHp[side]
      local slide=self.screen and self.screen.faintSlide
      if (shown==nil or shown<=0) and slide and slide.side==side then actor:faint() end
    end
  end
  Camera.stickOrbit(self.stickX,dt)
  Camera.stickPitch(-self.stickY,dt)
  Camera.update(dt)
  self.actors.player:update(dt)
  self.actors.enemy:update(dt)
  self.substituteActors.player:update(dt)
  self.substituteActors.enemy:update(dt)
  return self:render()
end

local function active(screen)
  return session and screen and session.battle == screen.battle and session or nil
end

local function installScreenHooks()
  local BattleState = require("src.ui.gen2.BattleState")
  if BattleState.stadium2ImporterGen2 then return end
  BattleState.stadium2ImporterGen2 = true

  local originalPic = BattleState.drawPic
  function BattleState:drawPic(mon, back)
    local scene = active(self)
    local side = back and "player" or "enemy"
    if scene then
      scene.screen = self
      scene:sync()
      if scene:ownsSlot(side, self) then return end
    end
    return originalPic(self, mon, back)
  end

  -- Gen1Recomp 0.1.78 models Gold's anim_keepsprites bit inside AnimRunner,
  -- but BattleState:stepAnim discards the runner unconditionally when step()
  -- returns false.  On a successful ball throw that loses the one object the
  -- cart explicitly asked to keep: the closed Pokeball on the ground.  Keep
  -- the finished runner alive on the screen so the detached Stadium OBJ pass
  -- can continue drawing its final OAM until another animation replaces it or
  -- the battle leaves.  Newer engine builds that already keep self.anim do not
  -- enter this compatibility latch, so the hook stays harmless there.
  local originalStepAnim = BattleState.stepAnim
  if type(originalStepAnim) == "function" then
    function BattleState:stepAnim(input, ...)
      local runner = self.anim
      local result = originalStepAnim(self, input, ...)
      if runner and self.anim == nil and runner.keepSprites
          and self.ballThrow and self.ballThrow.caught then
        self.stadium2ImporterRetainedAnim = runner
      end
      return result
    end
  end

  local originalStartAnim = BattleState.startAnim
  if type(originalStartAnim) == "function" then
    function BattleState:startAnim(...)
      self.stadium2ImporterRetainedAnim = nil
      return originalStartAnim(self, ...)
    end
  end

  local originalWide = BattleState.drawWidescreen

  function BattleState:drawWidescreen(width, height)
    local scene = active(self)
    if not scene then return originalWide(self,width,height) end
    scene.screen = self
    scene:sync()
    -- Resize/orientation changes can occur between the fixed update and the
    -- presentation pass on Android.  Rebuild immediately when the actual
    -- widescreen rect changes so the HUD, glass panels, camera and projected
    -- animation anchors all share this frame's dimensions.
    if not scene.readyFrame or scene.width~=width or scene.height~=height then
      scene:render(width,height)
    end
    local picture=scene.presentCanvas or scene.canvas
    local g = love.graphics
    if picture and scene.readyFrame then
      g.setColor(1,1,1,1)
      g.draw(picture, 0, 0, 0,
        width / picture:getWidth(), height / picture:getHeight())
    else
      -- Even a first-frame renderer defect remains an owned battle frame.
      -- Never expose the complete native 2D scene underneath it.
      g.clear(0,0,0,1)
      scene.width,scene.height=width,height
      scene.hudBox=Camera.frame(width,height).letterbox
    end
    -- The native OBJ animation layer (Pokeballs, hit sparks, beams, etc.) must
    -- not be baked into the three HUD bands: those bands are snapped to
    -- different widescreen X positions, so an object crossing y=48/96 would
    -- jump sideways or be cut in half.  Capture the battle UI with OBJs
    -- deferred, composite the HUD, then draw the authored OBJ layer once over
    -- the finished scene in one coherent 160x144 coordinate system.
    -- Gold's successful catch ends with anim_keepsprites.  On 0.1.78 the
    -- host screen has already cleared self.anim by the next draw, so fall back
    -- to the retained finished runner above.  BattleAnimView only reads its
    -- final OAM here; it is never stepped again.
    local objectRunner=self.anim or self.stadium2ImporterRetainedAnim
    local deferObjects=objectRunner and self.animView and true or nil
    scene.deferAnimationObjects=deferObjects
    -- Keep battle ownership in the Stadium scene during the caught-mon
    -- nickname prompt. Its Yes/No window is composited separately from the
    -- snapped status HUD bands below and wears the same frosted glass as them.
    local nicknameModal=self.phase=="ask-nickname"
      and (self.messageTimer or 0)<=0
    local layerOk,layer=pcall(Hud.layer,function() self:drawScene() end)
    -- The reference wide compositor snaps status HUDs from a HUD-only texture
    -- and leaves battle text/windows in the centred Game Boy frame.  Do the same for
    -- AskNickname so opening the modal never changes the wide HUD geometry.
    -- Stadium owns the status cards as a detached widescreen HUD, so Gold's
    -- BattleAnimClearHud must not blank them during an ordinary move.  The
    -- cartridge clears the ATTACKER's native HUD because that HUD lives in the
    -- same 160x144 BG that the move animation manipulates.  Our status cards
    -- are a separate compositor layer, exactly like the reference 3D battle
    -- path: capture them independently and temporarily answer false to
    -- hudCleared while doing so.  Real visibility (send-out, faint, tutorial,
    -- trainer intro) still comes from showEnemyHud/showPlayerHud below.
    local hudLayerOk,hudLayer
    do
      local had=rawget(self,"hudCleared")
      self.hudCleared=function() return false end
      hudLayerOk,hudLayer=pcall(Hud.hudLayer,function() self:drawHud() end)
      self.hudCleared=had
    end
    local modalLayerOk,modalLayer=true,nil
    if nicknameModal then
      -- Gold draws the nickname Yes/No box on top of its native player HUD.
      -- Capture it a second time with drawHud suppressed so transparent modal
      -- paper cannot reveal that native HUD inside the modal texture itself.
      modalLayerOk,modalLayer=pcall(Hud.modalLayer,function()
        local had=rawget(self,"drawHud")
        self.drawHud=function() end
        local ok,err=pcall(self.drawScene,self)
        self.drawHud=had
        if not ok then error(err,0) end
      end)
    end
    scene.deferAnimationObjects=nil
    if not layerOk then error(layer,0) end
    if not hudLayerOk then error(hudLayer,0) end
    if not modalLayerOk then error(modalLayer,0) end
    local composed=Hud.composite(scene,self,layer,hudLayer,modalLayer)
    if deferObjects and objectRunner and self.animView then
      local box=scene.hudBox
      g.push()
      g.translate(box.lx,box.ly)
      g.scale(box.scale,box.scale)
      local drawOk,drawErr=pcall(self.animView.drawObjects,self.animView,
        objectRunner,self.battle)
      g.pop()
      if not drawOk then error(drawErr,0) end
    end
    return composed
  end

  local originalAdvance = BattleState.advanceQueue
  function BattleState:advanceQueue(...)
    local event = self.queue and self.queue[1] or nil
    local scene = active(self)
    local after = event and (event.kind == "send" or event.kind == "sendout")
    if scene and event and not after then
      scene.screen = self
      scene:handleEvent(event)
    end
    local result = originalAdvance(self, ...)
    if scene and event and after then
      scene.screen = self
      scene:handleEvent(event)
    end
    return result
  end

  -- Battle:endBattle emits battle.ended as soon as the outcome is decided,
  -- while this screen still owns the faint, victory, experience and result
  -- messages.  The session must live until the screen actually returns to
  -- the world, or the remainder is redrawn by Gold's ordinary 2D path.
  local originalFinishBattle=BattleState.finishBattle
  function BattleState:finishBattle(...)
    local scene=active(self)
    self.stadium2ImporterRetainedAnim=nil
    local result=originalFinishBattle(self,...)
    if scene then Gen2.finish(nil,true) end
    return result
  end
end

local ANIM_SOURCE_PLAYER={26,96}
local ANIM_SOURCE_ENEMY={124,56}

local function animationProjection(anchors)
  if not (anchors and anchors.player and anchors.enemy) then return nil end
  local spx,spy=(ANIM_SOURCE_PLAYER[1]+ANIM_SOURCE_ENEMY[1])*.5,
    (ANIM_SOURCE_PLAYER[2]+ANIM_SOURCE_ENEMY[2])*.5
  local dpx,dpy=(anchors.player[1]+anchors.enemy[1])*.5,
    (anchors.player[2]+anchors.enemy[2])*.5
  local svx,svy=ANIM_SOURCE_ENEMY[1]-ANIM_SOURCE_PLAYER[1],
    ANIM_SOURCE_ENEMY[2]-ANIM_SOURCE_PLAYER[2]
  local dvx,dvy=anchors.enemy[1]-anchors.player[1],anchors.enemy[2]-anchors.player[2]
  local sourceLength=math.sqrt(svx*svx+svy*svy)
  local destLength=math.sqrt(dvx*dvx+dvy*dvy)
  return { dx=dpx-spx, dy=dpy-spy, scale=clamp(destLength/sourceLength,.82,1.22),
    originX=spx, originY=spy }
end

local function installAnimationProjection()
  local View=require("src.ui.gen2.BattleAnimView")
  if View.stadium2ImporterProjection then return end
  View.stadium2ImporterProjection=true
  local originalPresent=View.present
  function View:present(runner,drawBackground)
    local scene=session and session.screen and session.screen.animView==self
      and session or nil
    if not scene then return originalPresent(self,runner,drawBackground) end
    -- In the reference 3D battle scene the Game Boy BG register effects do
    -- not repaint, shake, or palette-fade the world and its HUD.  Stadium's
    -- skeletal clips provide battler movement; the native OBJ layer remains
    -- separate below and is still projected onto the two live anchors.
    return drawBackground()
  end
  local original=View.drawObjects
  function View:drawObjects(runner,battle)
    local scene=session and session.battle==battle and session or nil
    if scene and scene.deferAnimationObjects then return end
    local projection=animationProjection(scene and scene.uiAnchors)
    if not projection then return original(self,runner,battle) end
    local g=love.graphics
    -- Keep native battle OBJs upright.  They are authored pixel art, not a
    -- plane in the 3D world; rotating the whole layer with the battler axis
    -- turns a Pokeball arc and every hit sprite sideways as the camera orbits.
    -- Match the reference 3D battle: translate to the projected pair midpoint
    -- and uniformly scale about the authored midpoint, with no rotation.
    g.push()
    g.translate(projection.dx,projection.dy)
    if projection.scale~=1 then
      g.translate(projection.originX,projection.originY)
      g.scale(projection.scale,projection.scale)
      g.translate(-projection.originX,-projection.originY)
    end
    local ok,result=pcall(original,self,runner,battle)
    g.pop()
    if not ok then error(result,0) end
    return result
  end
end

local function installControls()
  local Game2 = require("src.core.Game2")
  if Game2.stadium2ImporterGen2Controls then return end
  Game2.stadium2ImporterGen2Controls = true
  local key=Game2.keypressed
  function Game2:keypressed(name,...)
    if session and (name=="0" or name=="kp0") then
      Camera.recentre()
      return
    end
    if session and (name=="q" or name=="e") then
      Camera.stepZoom(name=="q" and 1 or -1)
      return
    end
    return key(self,name,...)
  end
  local wheel = Game2.wheelmoved
  function Game2:wheelmoved(x, y)
    if session then
      Camera.stepZoom(-(tonumber(y) or 0))
      return
    end
    return wheel(self, x, y)
  end
  local mouse = Game2.mousemoved
  local function mouseStep(value)
    return clamp(tonumber(value) or 0,-40,40)
  end
  function Game2:mousemoved(x, y, dx, dy, istouch)
    if session and not istouch then
      -- Like the reference battle shot, ordinary mouse movement steers; no
      -- held button or pointer capture is required. Clamp a single event so
      -- entering the window or an OS cursor warp cannot throw the camera.
      Camera.mouseOrbit(mouseStep(dx))
      Camera.mousePitch(-mouseStep(dy))
    end
    return mouse(self, x, y, dx, dy, istouch)
  end
  local pressed=Game2.gamepadpressed
  function Game2:gamepadpressed(joystick,button)
    if session and (button=="leftstick" or button=="rightstick") then
      Camera.stepZoom(button=="leftstick" and 1 or -1)
      return
    end
    return pressed(self,joystick,button)
  end
  -- One free finger drags the battle shot; two free fingers pinch its lens.
  -- Touches beginning on the virtual controls remain entirely the pad's.
  local TouchControls=require("src.core.TouchControls")
  local free,pinch={},nil
  local function freeIds()
    local ids={}
    for id in pairs(free) do ids[#ids+1]=id end
    return ids
  end
  local function gap(a,b)
    local ax,ay=free[a].x,free[a].y
    local bx,by=free[b].x,free[b].y
    local dx,dy=ax-bx,ay-by
    return math.sqrt(dx*dx+dy*dy)
  end
  local function startPinch()
    if pinch then return end
    local ids=freeIds()
    if #ids<2 then return end
    local distance=gap(ids[1],ids[2])
    if distance>=16 then pinch={a=ids[1],b=ids[2],gap=distance} end
  end
  local touchPressed=Game2.touchpressed
  function Game2:touchpressed(id,x,y,...)
    if session and not TouchControls:hitTest(x,y) then
      free[id]={x=x,y=y}
      startPinch()
    end
    return touchPressed(self,id,x,y,...)
  end
  local touchMoved=Game2.touchmoved
  function Game2:touchmoved(id,x,y,...)
    local point=free[id]
    if session and point then
      local px,py=point.x,point.y
      point.x,point.y=x,y
      if pinch and (id==pinch.a or id==pinch.b) then
        local distance=gap(pinch.a,pinch.b)
        local factor=distance/math.max(1,pinch.gap)
        if math.abs(factor-1)>.02 then
          Camera.stepZoom(math.log(1/factor)/math.log(Camera.ZOOM_STEP))
          pinch.gap=distance
        end
        return
      end
      local width,height=1280,720
      if love and love.graphics then
        width=love.graphics.getWidth and love.graphics.getWidth() or width
        height=love.graphics.getHeight and love.graphics.getHeight() or height
      end
      Camera.dragOrbit((x-px)/math.max(320,width))
      Camera.dragPitch(-(y-py)/math.max(240,height))
      return
    end
    return touchMoved(self,id,x,y,...)
  end
  local touchReleased=Game2.touchreleased
  function Game2:touchreleased(id,x,y,...)
    if free[id] then
      free[id]=nil
      if pinch and (id==pinch.a or id==pinch.b) then pinch=nil end
    end
    return touchReleased(self,id,x,y,...)
  end
  local focus=Game2.focus
  function Game2:focus(value)
    free,pinch={},nil
    return focus(self,value)
  end
  local axis = Game2.gamepadaxis
  function Game2:gamepadaxis(joystick, name, value)
    if session and name == "rightx" then session.stickX = value or 0 end
    if session and name == "righty" then session.stickY = value or 0 end
    return axis(self, joystick, name, value)
  end
end

function Gen2.bind(mod) modRef = mod; return Gen2 end

function Gen2.configureGame(game)
  local maxDex = 151
  local palettePairs={}
  local pokemon=game and game.data and game.data.pokemon or {}
  -- Gold's imported palette table is namespaced as gen2Palettes by Game2 and
  -- the Gen 2 content router. `data.palettes` is the Gen 1 registry target;
  -- reading it here silently produced no pairs, so every "shiny" DSM was an
  -- unchanged copy of its normal pack.
  local paletteData=game and game.data
    and (game.data.gen2Palettes or game.data.palettes) or nil
  local pokemonPalettes=paletteData and paletteData.pokemon or {}
  for id, def in pairs(pokemon) do
    local dex = type(def) == "table" and tonumber(def.dex or def.index) or nil
    if dex and dex > maxDex and dex <= Gen2.COUNT then maxDex = math.floor(dex) end
    local pair=dex and pokemonPalettes[id]
    if dex and pair and pair.normal and pair.shiny then
      palettePairs[math.floor(dex)]={normal=pair.normal,shiny=pair.shiny}
    end
  end
  configured = maxDex
  -- The generation router enters this module directly on Gold.  Do not rely
  -- on the Gen 1 battle path to configure the shared importer: without
  -- this call its load boundary remains at the boot default of 151 even when
  -- the Gold cache and battle both correctly resolve National Dex species.
  Importer.configure({count=maxDex,palettePairs=palettePairs})
  return maxDex
end

function Gen2.install()
  if installed then return true end
  installScreenHooks()
  installAnimationProjection()
  installControls()
  installed = true
  return true
end

function Gen2.ensure(battle)
  if not (installed and battle and Importer.modelsEnabled()
      and Importer.battleEnabled() and Importer.available(configured)) then
    return false
  end
  if session and session.battle == battle then return true end
  Gen2.finish()
  session = Scene.new(battle)
  session:sync()
  return true
end

function Gen2.update(dt)
  if not session then return false end
  -- Options and cache readiness are sampled when the battle begins.  Once a
  -- scene owns the fight, only BattleState:finishBattle may release it.
  return session:update(math.min(math.max(tonumber(dt) or 0, 0), .1))
end

local function shouldDeferFinish(current,battle)
  return current and battle and current.battle==battle and current.screen
    and current.screen.phase~="done"
end

function Gen2.finish(battle, force)
  if not force and shouldDeferFinish(session,battle) then
    session.endRequested=true
    return false
  end
  if session then session:release(); session = nil end
  return true
end

function Gen2.status()
  return { enabled=Importer.modelsEnabled() and Importer.battleEnabled(),
    ready=Importer.available(configured), count=configured,
    generation=2, active=session ~= nil,
    shot=session and (session.presentCanvas or session.canvas) or nil,
    defect=session and session.defect or nil,
    visual=session and {
      player=session:visualState("player"),enemy=session:visualState("enemy")
    } or nil }
end

function Gen2.resetForTests()
  Gen2.finish()
  installed, modRef, configured = false, nil, 251
end

Gen2.Actor = Actor
Gen2.Scene = Scene
Gen2._shouldDeferFinish = shouldDeferFinish
Gen2._animationProjection = animationProjection

return Gen2
