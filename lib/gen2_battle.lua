-- Native Gold/Gen 2 battle adapter for Stadium 2 models.
--
-- Gold does not instantiate src.battle.BattleState or src.core.Game.  Its
-- battle presenter is src.ui.gen2.BattleState and its battlers are the mon
-- records themselves (not Gen 1 battler wrappers).  Keep that distinction in
-- one module so Gen 2 battle ownership stays isolated from Gen 1.
local Importer = require("mods.STADIUM2_IMPORTER.lib.importer")
local Camera = require("mods.STADIUM2_IMPORTER.lib.battle_camera")
local Actor = require("mods.STADIUM2_IMPORTER.lib.battle_actor")
local Presentation = require("mods.STADIUM2_IMPORTER.lib.battle_scene")
local Hud = require("mods.STADIUM2_IMPORTER.lib.battle_hud")
local TrainerSprite = require("mods.STADIUM2_IMPORTER.lib.trainer_sprite")
local Unown = require("src.core.gen2.Unown")

local Gen2 = { COUNT = 251 }
local modRef, installed, session
local configured = 251

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

local Scene = setmetatable({}, {__index=Presentation})
Scene.__index = Scene

local function gen2ActorOptions()
  return {warn=warn,dexOf=dexOf,shiny=shiny,formFor=unownPack,label="Gen 2 battle"}
end

function Scene.new(battle)
  local actorOpts=gen2ActorOptions()
  local self=setmetatable({},Scene)
  Presentation.init(self,{
    actors={player=Actor.new("player",actorOpts),enemy=Actor.new("enemy",actorOpts)},
    warn=warn,label="Gen 2 battle",
  })
  self.battle=battle
  self.screen=nil
  self.substituteActors={
    player=Actor.new("player",actorOpts),enemy=Actor.new("enemy",actorOpts),
  }
  self.substituteActive={player=false,enemy=false}
  self.vanish={player={active=false},enemy={active=false}}
  return self
end

function Scene:release()
  self.substituteActors.player:release()
  self.substituteActors.enemy:release()
  Presentation.release(self)
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
  if not self.readyFrame or self.defect then return false end
  local providerMode=self.battlerMode and self:battlerMode(side) or "host"
  if providerMode=="native" then return false end
  if providerMode=="provider" then return true end
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

-- Gold's ReturnMon BG effect shrinks the native pic through its authored
-- 7x7/5x5/3x3 (enemy) or 6x6/4x4/2x2 (player) states.  The shared scene
-- owns the model transform, so the Gen 2 adapter translates those exact pic
-- states into a model scale while a ball throw is running.
local PIC_SCALE = {
  player = { [0]=1, [1]=4/6, [2]=2/6 },
  enemy = { [3]=1, [4]=5/7, [5]=3/7 },
}

function Scene:picScale(side, screen)
  screen=screen or self.screen
  if not (screen and screen.anim and screen.ballThrow and screen.animPicState) then
    return 1
  end
  local ok,state=pcall(screen.animPicState,screen,side)
  if not ok or type(state)~="table" then return 1 end
  local size=tonumber(state.size)
  return (PIC_SCALE[side] and PIC_SCALE[side][size]) or 1
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

  -- Gold's opponent trainer sheets are the odd one out in the Gen 2 import:
  -- Chris/Dude backpics go through writeCompressedPic(), which mattes
  -- edge-connected shade 0, but TrainerPicPointers are decoded with plain
  -- write2bpp(..., transparent=nil). The resulting battle/trainers/*.png files
  -- therefore contain an opaque white rectangle. Fix the loaded screen images
  -- themselves from their asset paths once, before any intro compositor sees
  -- them. That makes every native draw path (including presentSlide's baked BG
  -- bands) consume the same cutout image; no love.graphics.draw interception
  -- or GPU readback is involved.
  local function prepareTrainerImages(screen)
    if not screen or screen.stadium2ImporterTrainerImagesPrepared then return end
    screen.stadium2ImporterTrainerImagesPrepared = true
    if screen.enemyTrainerImage and screen.enemyTrainerPath then
      screen.enemyTrainerImage = TrainerSprite.fromPath(
        screen.enemyTrainerPath, screen.enemyTrainerImage, "shade0")
    end
    -- Current Chris/Dude imports are already matted, but keep this for old
    -- caches and asset overrides. fromPath is a no-op when no edge paper exists.
    if screen.playerBackImage and screen.playerBackPath
        and not screen.playerBackTrueColor then
      screen.playerBackImage = TrainerSprite.fromPath(
        screen.playerBackPath, screen.playerBackImage, "shade0")
    end
  end

  function BattleState:drawPic(mon, back)
    local scene = active(self)
    local side = back and "player" or "enemy"
    if scene then
      scene.screen = self
      scene:sync()
      prepareTrainerImages(self)
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
    prepareTrainerImages(self)
    -- Resize/orientation changes can occur between the fixed update and the
    -- presentation pass on Android.  Rebuild immediately when the actual
    -- widescreen rect changes so the HUD, glass panels, camera and projected
    -- animation anchors all share this frame's dimensions.
    if not scene.readyFrame or scene.width~=width or scene.height~=height then
      scene:render(width,height)
    end
    local picture=scene.presentCanvas or scene.canvas
    local g = love.graphics
    if picture and scene.readyFrame and not scene.defect then
      g.setColor(1,1,1,1)
      g.draw(picture, 0, 0, 0,
        width / picture:getWidth(), height / picture:getHeight())
    else
      return originalWide(self,width,height)
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

function Gen2.currentScene()
  return session
end

function Gen2.resetForTests()
  Gen2.finish()
  installed, modRef, configured = false, nil, 251
end

local Gen2Actor=setmetatable({},{__index=Actor})
function Gen2Actor.new(side)
  return Actor.new(side,gen2ActorOptions())
end

Gen2.Actor = Gen2Actor
Gen2.SharedActor = Actor
Gen2.Scene = Scene
Gen2._shouldDeferFinish = shouldDeferFinish
Gen2._animationProjection = animationProjection

return Gen2
