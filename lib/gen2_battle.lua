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
local ArenaRuntime = require("mods.STADIUM2_IMPORTER.lib.arena_runtime")
local ArenaSelector = require("mods.STADIUM2_IMPORTER.lib.arena_selector")
local ArenaLighting = require("mods.STADIUM2_IMPORTER.lib.arena_lighting")
local UIOwnership = require("mods.STADIUM2_IMPORTER.lib.battle_ui_ownership")
local FxSequence = require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_sequence")
local RestPose = require("mods.STADIUM2_IMPORTER.lib.battle_rest_pose")
local BattleFxAdapter = require(
  "mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_battle_adapter")
local Unown = require("src.core.gen2.Unown")
local GameVersion = require("src.core.GameVersion")

local Gen2 = { COUNT = 251 }
local PatchScope=require("mods.STADIUM2_IMPORTER.lib.patch_scope")
local patches
local modRef, installed, session
local configured = 251
local lastDiagnostic
local diagnosticLines={}

local function clamp(value, lo, hi)
  return math.max(lo, math.min(hi, tonumber(value) or lo))
end

local function diagnostic(message)
  message=tostring(message)
  if message==lastDiagnostic then return end
  lastDiagnostic=message
  diagnosticLines[#diagnosticLines+1]=message
  while #diagnosticLines>24 do table.remove(diagnosticLines,1) end
  local cache=modRef and modRef.cache
  if cache and type(cache.write)=="function" then
    pcall(cache.write,cache,"gen2_battle_status.txt",
      table.concat(diagnosticLines,"\n").."\n")
  end
end

local function warn(message)
  local log = modRef and modRef.log
  if log and log.warn then pcall(log.warn, log, "%s", tostring(message)) end
  diagnostic("warning: "..tostring(message))
end

-- Gen 2 move events carry the move key (e.g. "ABSORB"); its record's
-- numeric `index` is the move number Stadium's tables use. `id` is the key
-- again, so it is only a fallback for hosts that emit numeric IDs.
local function moveNumber(data, move)
  local number = tonumber(move)
  if number then return number end
  local def = data and data.moves and data.moves[move]
  return def and (tonumber(def.index) or tonumber(def.number) or tonumber(def.id)) or nil
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

-- The ROM move-FX player is presentation-only and remains opt-in.  Keep the
-- construction boundary defensive: an unavailable cache, renderer, or
-- partially initialized importer must leave the ordinary Gen 2 scene intact.
local function newBattleFx()
  local enabledOk,enabled=pcall(Importer.betaBattleFxEnabled)
  if not enabledOk or enabled~=true then return nil end
  local ok,player,err=pcall(BattleFxAdapter.new,Importer,{warn=warn})
  if not ok then
    warn("BETA BATTLE FX could not be initialized: "..tostring(player))
    return nil
  end
  if not player and err then
    warn("BETA BATTLE FX could not be initialized: "..tostring(err))
  end
  return player
end

function Scene.new(battle,context)
  local actorOpts=gen2ActorOptions()
  local self=setmetatable({},Scene)
  local arena,arenaError
  local selection=require('mods.STADIUM2_IMPORTER.lib.battle_environment').select(
    context,Importer.environmentStyle(),Importer.betaArenaEnabled(),nil,
    Importer.environmentTest and Importer.environmentTest(),
    Importer.arenaTest and Importer.arenaTest())
  if selection.mode=='arena' then
    local arenaIndex,reason=selection.arena,selection.reason
    self.arenaSelectionReason=reason
    if arenaIndex~=nil then arena,arenaError=ArenaRuntime.load(arenaIndex,Importer) end
    if arena and arenaIndex==28 and Importer.betaArenaTimeOfDayEnabled() then
      arena.environment=ArenaLighting.environment(arenaIndex,context and context.timeOfDay)
    elseif arenaIndex~=nil and not arena then
      warn("BETA ARENA TEST could not load a field; using the classic scene: "
        ..tostring(arenaError))
    end
    if not arena and selection.fallback then selection=selection.fallback end
  end
  Presentation.init(self,{
    actors={player=Actor.new("player",actorOpts),enemy=Actor.new("enemy",actorOpts)},
    warn=warn,label="Gen 2 battle",arena=arena,arenaMode=arena~=nil,
  })
  self.environmentSelection=selection
  self.battleContext=context
  self.battle=battle
  self.screen=nil
  self.substituteActors={
    player=Actor.new("player",actorOpts),enemy=Actor.new("enemy",actorOpts),
  }
  self.substituteActive={player=false,enemy=false}
  self.eventVisuals=setmetatable({},{__mode="k"})
  self.recordedSubstitute={player=0,enemy=0}
  self.vanish={player={active=false},enemy={active=false}}
  -- Major status as presented so far. Gold resolves the whole turn before
  -- presenting it, so the live mon.status can run ahead of the screen.
  self.presentedStatus={}
  self.battleFx=newBattleFx()
  if self.battleFx then
    -- The defender plays its own hit clip (context 254) at the impact.
    self.battleFx.onImpact=function(target,_,moveId)
      local actor=self.actors and self.actors[target]
      if not actor or not actor.hit then return false,"no defender actor" end
      return actor:hit(moveId)
    end
  end
  self.battleFxUpdateError=nil
  return self
end

function Scene:release()
  if self.screen then
    self.screen.stadium2ImporterRetainedAnim=nil
    local images=self.trainerImageOriginals
    if images then
      for _,key in ipairs({'enemyTrainerImage','playerBackImage'}) do
        if self.screen[key]==images.applied[key] then self.screen[key]=images[key] end
      end
      self.screen.stadium2ImporterTrainerImagesPrepared=images.prepared
      self.trainerImageOriginals=nil
    end
  end
  UIOwnership.release(self.screen)
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
    -- A different Pokemon is a fresh Stadium model: native colour/opacity
    -- writes (a recall's fade-out) belong to the one it replaced.
    self.shownMons = self.shownMons or {}
    if mon ~= self.shownMons[side] then
      if self.shownMons[side] ~= nil and self.battleFx and self.battleFx.modelChanged then
        pcall(self.battleFx.modelChanged, self.battleFx, side)
      end
      self.shownMons[side] = mon
    end
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
  screen = screen or self.screen
  -- Trainer pictures are world actors too, but they are not Pokemon models.
  -- Resolve these flags before provider ownership so Battle Art can capture
  -- and place the selected trainer image instead of exposing the loaded mon.
  if screen then
    if side == "player" and screen.showPlayerTrainer then return false end
    if side == "enemy" and screen.showEnemyTrainer then return false end
  end
  local providerMode=self.battlerMode and self:battlerMode(side) or "host"
  if providerMode=="native" then return false end
  if providerMode=="provider" then return true end
  if not screen then return false end
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

-- Fly and Dig share EFFECT_FLY in Gen 2; the stored charge move tells them
-- apart (Battle.lua keeps it as the move name; accept the ID too).
local function chargeKind(volatile)
  local move=volatile and volatile.chargeMove
  if move=="FLY" or tonumber(move)==19 then return "flying" end
  if move=="DIG" or tonumber(move)==91 then return "underground" end
  return nil
end

-- Condition for the Stadium resting pose (battle_rest_pose.lua), from what
-- has been presented: the vanish state once its departing animation has
-- finished, and the presented major status.
function Scene:restCondition(side)
  local condition={}
  local volatile=self:volatileFor(side)
  local vanish=self.vanish and self.vanish[side] or {}
  if vanish.mode==nil and (vanish.active or (volatile and volatile.vanished)) then
    local kind=chargeKind(volatile)
    if kind then condition[kind]=true end
  end
  local status=self.presentedStatus and self.presentedStatus[side]
  condition.asleep=status=="sleep"
  condition.frozen=status=="freeze"
  return condition
end

-- Stadium keeps a flying Pokemon (context 262) and an underground Diglett
-- or Dugtrio (context 258) on screen; other species underground are hidden.
function Scene:restVisible(side)
  local actor=self.actors[side]
  local condition=self:restCondition(side)
  local pose=RestPose.select(condition,actor and actor.dex)
  return (condition.flying or condition.underground) and not pose.hidden
end

function Scene:visualState(side, screen)
  screen=screen or self.screen
  if not self:ownsSlot(side,screen) then return "trainer" end
  if not screen then return "empty" end
  -- During a trainer opening, ResetEnemyBattleVars drops the trainer flag a
  -- few frames before the enemy send event begins.  The active mon already
  -- exists in battle data during that gap, but it has not been sent out yet.
  -- Keep only trainer battles empty until startSendOut arms afterSendOut;
  -- wild encounters are visible from their first presented frame.
  if side=="enemy" and screen and screen.battle
      and screen.battle.trainer and not screen.battle.wild
      and not screen.showEnemyHud then
    local sending=screen.afterSendOut and screen.afterSendOut.side=="enemy"
    if not sending then return "empty" end
  end
  local actor=self.actors[side]
  if not (actor and actor.mon) then return "empty" end
  local volatile=self:volatileFor(side)
  local presented=self.presentedVolatile and self.presentedVolatile[side]
  if presented then volatile=presented end
  local substituted=self.substituteActive and self.substituteActive[side]
  if substituted==nil then substituted=(tonumber(volatile and volatile.substitute) or 0)>0 end
  if (actor.mon.hp or 0)<=0 then
    if actor.context=="faint" and not actor.faintFinished then return "pokemon" end
    -- Gold resolves the whole turn before presenting its queue, so live HP
    -- may already be zero while the hit and bar drain are still being shown.
    -- Only the completed authored collapse empties the owned slot.
    if actor.faintFinished then return "empty" end
    return "pokemon"
  end
  local state = screen.animPicState and screen:animPicState(side) or nil
  -- false is an explicit dropsub command, not a missing override.
  if state and state.pic~=nil then substituted=state.pic=="substitute" end
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
    elseif self:restVisible(side) then
      return actor.renderer and "pokemon" or "defect"
    else
      return "hidden"
    end
  end
  if state and state.hidden and not actor.grow then return "hidden" end
  -- Gold's BG animation state exists only while the current script runs.
  -- `vanished` is the persistent truth between Fly/Dig's two turns.
  if volatile and volatile.vanished then
    if self:restVisible(side) and actor.renderer then return "pokemon" end
    return "hidden"
  end
  if substituted then return "substitute" end
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
  actor.mon={hp=1,species=252}
  actor.dex,actor.variant=252,"normal"
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

-- Sample at emission, while the engine resolves the turn, then consume only
-- when the screen reaches that event. Never infer identity from localized text
-- or read end-of-turn Substitute HP while an earlier move is playing.
function Scene:recordEvent(event)
  if not self.eventVisuals then return end
  local snapshot={}
  for _,side in ipairs({"player","enemy"}) do
    local mon=self.battle and self.battle[side]
    local volatile=mon and self.battle:volatile(mon) or {}
    local hp=tonumber(volatile.substitute) or 0
    local previous=self.recordedSubstitute[side] or 0
    snapshot[side]={substitute=hp>0,substituteHit=previous>hp and previous>0,
      vanished=volatile.vanished,chargeMove=volatile.chargeMove}
    self.recordedSubstitute[side]=hp
  end
  self.eventVisuals[event]=snapshot
end

function Scene:handleEvent(event)
  if not event or event._stadium2Gen2Handled then return end
  event._stadium2Gen2Handled = true
  self:sync()
  local snapshot=self.eventVisuals and self.eventVisuals[event]
  if snapshot then
    self.presentedVolatile=self.presentedVolatile or {}
    for _,which in ipairs({"player","enemy"}) do
      local state=snapshot[which]
      if state.substituteHit then
        local doll=self:ensureSubstitute(which)
        if doll then doll:hit() end
      end
      self.substituteActive[which]=state.substitute or state.substituteHit
      self.presentedVolatile[which]=state
    end
  end
  local side = event.side
  if event.kind=="move" and side then
    local data=self.screen and self.screen.game and self.screen.game.data
    local def=data and data.moves and data.moves[event.move]
    -- BattleState presents each queue event once and marks a miss on the same
    -- event object before it reaches this hook.  Trigger only that presented,
    -- successful move; mechanics and the host battle RNG remain untouched.
    -- `event.move` is the BattleState move ID.  Keep it authoritative; the
    -- data record's index/number is only a fallback for legacy presenters
    -- that supplied a symbolic move key.
    local moveId=moveNumber(data,event.move)
    if self.battleFx and event.missed~=true and moveId then
      -- Presented (non-missed) moves play the move bank now and the impact
      -- bank at the attacker's dispatch hit frame (84108728/841087B8).
      local ok,err
      -- Gold's charge turn (BattleCommand_Charge sets animParam 1): Stadium's
      -- charge state plays the variant route, not the move and impact.
      if event.animParam==1 and FxSequence.CHARGE_ENTRIES[moveId]
          and self.battleFx.playCharge then
        ok,err=pcall(self.battleFx.playCharge,self.battleFx,moveId,side,
          self.actors and self.actors[side])
      elseif event.alternate~=true and self.battleFx.playMoveAndImpact then
        ok,err=pcall(self.battleFx.playMoveAndImpact,self.battleFx,moveId,side,
          self.actors and self.actors[side],nil,
          self.actors and self.actors[side=="player" and "enemy" or "player"])
      else
        ok,err=pcall(self.battleFx.trigger,self.battleFx,moveId,side,
          event.alternate==true)
      end
      if ok then self.battleFxMovePending=true;self.battleFxAnimation=nil end
      if not ok and not self.battleFxTriggerError then
        self.battleFxTriggerError=true
        warn("Gen 2 battle FX trigger failed: "..tostring(err))
      end
    end
    -- The clip starts from the animForMove hook (installScreenHooks), when
    -- Gold's move animation actually starts; a charge turn plays the
    -- species' charge row there instead of the move clip.
    self.chargeTurn=self.chargeTurn or {}
    self.chargeTurn[side]=(event.animParam==1 and moveId
      and FxSequence.CHARGE_ENTRIES[moveId] and not event.missed) and moveId or nil
    if def and def.effect=="EFFECT_FLY" and not event.missed then
      local flight=self.vanish[side]
      local volatile=self:volatileFor(side)
      if event.animParam==1 then
        flight.active,flight.mode,flight.sawHidden=false,"depart",nil
      elseif event.wasVanished or flight.active or (volatile and volatile.vanished) then
        flight.active,flight.mode,flight.sawHidden=true,"return",false
      end
    end
  end
  if event.kind == "damage" and side then
    local actor = self.actors[side]
    -- Explicit anim fields describe residual effects or silent HP costs,
    -- not a direct impact. Zero-damage bookkeeping must not flinch either.
    -- With battle FX on, the hit clip plays at the Stadium impact instead
    -- (the adapter's onImpact hook), so it is not replayed here.
    if actor and not self.battleFx and event.anim==nil and (tonumber(event.amount) or 0)>0
        and not self.substituteActive[side] then actor:hit() end
  elseif event.kind == "status" and side then
    self.presentedStatus[side] = event.status
  elseif event.kind == "faint" and side then
    local actor = self.actors[side]
    -- Gold first chases the HP bar and begins its native sink.  Starting the
    -- Stadium clip at damage time makes it finish before the faint message.
    if actor then actor.pendingFaint=true end
  elseif (event.kind == "send" or event.kind == "sendout") and side then
    if self.minimized then self.minimized[side]=nil end
    self.substituteActive[side]=false
    self.vanish[side]={active=false}
    self:sync()
    -- Status carries over with the mon being sent out.
    local sent=self.actors[side] and self.actors[side].mon
    self.presentedStatus[side]=sent and sent.status or nil
    local actor = self.actors[side]
    if actor then actor:entrance() end
  elseif event.kind == "sendout" then
    if self.minimized then self.minimized.player=nil end
    self.substituteActive.player=false
    self.vanish.player={active=false}
    self:sync()
    local sent=self.actors.player and self.actors.player.mon
    self.presentedStatus.player=sent and sent.status or nil
    self.actors.player:entrance()
  elseif event.kind == "transform" and side and event.mon then
    local data = self.screen and self.screen.game and self.screen.game.data
    local shown=self:shownMon(side) or event.mon
    local species=shown==event.mon and event.species or shown.species
    self.actors[side]:load(data, shown, dexOf(data, {species=species or shown.species}))
    self.actors[side]:play("entrance", false)
  end
  self:signalEventFx(event)
end

-- Stadium's weather entries (Sequence.WEATHER_ENTRIES). Gold emits the
-- ongoing-weather line as a plain message and the end as a weather event
-- with no weather, both built with Strings() from the engine's own tables,
-- so the same lookup identifies them exactly. Sandstorm damage is a damage
-- event tagged ANIM_IN_SANDSTORM on the side that took it.
local function weatherFrom(tableName, text)
  if type(text) ~= "string" then return nil end
  local okE, Effects = pcall(require, "src.battle.gen2.Effects")
  local okS, Strings = pcall(require, "src.core.Strings")
  local texts = okE and type(Effects) == "table" and Effects[tableName]
  if not okS or type(texts) ~= "table" then return nil end
  for weather, source in pairs(texts) do
    local ok, shown = pcall(Strings, source)
    if ok and shown == text then return weather end
  end
  return nil
end

-- Gold's DRAIN effects (pokecrystal EFFECT_LEECH_HIT / EFFECT_DREAM_EATER).
local DRAIN_EFFECTS = {EFFECT_LEECH_HIT = true, EFFECT_DREAM_EATER = true}

local function sideOk(side) return side == "player" or side == "enemy" end

-- Gold's AI switch prints "<trainer> withdrew <mon>!" (Battle:switchEnemy)
-- before the send event, while the outgoing mon is still shown. Rebuilt
-- with the engine's own Strings call so only that line matches. Gold's
-- player switch has no withdraw step, so Stadium's recall has nothing to
-- pair with there.
function Scene:isEnemyWithdraw(text)
  if type(text) ~= "string" or not text:find("withdrew", 1, true) then return false end
  local battle = self.battle or (self.screen and self.screen.battle)
  -- The shown mon, not battle.enemy: the engine has already swapped it in.
  local mon = self:shownMon("enemy")
  if not (battle and mon and battle.monName) then return false end
  local okS, Strings = pcall(require, "src.core.Strings")
  if not okS then return false end
  local trainerName = (battle.trainer and battle.trainer.name) or "TRAINER"
  local okN, name = pcall(battle.monName, battle, mon)
  local ok, shown = pcall(Strings, "%s withdrew %s!", trainerName, okN and name or "?")
  return ok and shown == text
end

-- Stadium's non-move effects for presented Gold events (Sequence tables).
-- Damage events name their cause with Gold's own anim constant; heal and
-- stage events are attributed to the move being presented. Leftovers heals
-- carry no source and are not signalled.
-- The attacker's clip when Gold's move animation starts (animForMove hook):
-- the species' charge row on a charge turn noted by handleEvent, else the
-- move clip (Actor:attack times it from the dispatch row).
function Scene:startMoveClip(side, moveId)
  local actor=self.actors and self.actors[side]
  if not actor then return false end
  local charging=self.chargeTurn and self.chargeTurn[side]
  if charging and charging==moveId and actor.charge then
    self.chargeTurn[side]=nil
    local model=actor.renderer and actor.renderer.model
    local entry,start=FxSequence.chargeFrames(model and model.fxDispatch,moveId)
    if actor:charge(entry,start) then return true end
  end
  return actor:attack(moveId)
end

function Scene:signalEventFx(event)
  local fx = self.battleFx
  if not fx or not fx.signalEffect then return end
  if event.kind == "move" and sideOk(event.side) then
    local data = self.screen and self.screen.game and self.screen.game.data
    self.presentedMove = {side = event.side, move = moveNumber(data, event.move)}
  end
  local entry, owner
  if event.kind == "damage" and sideOk(event.side) then
    local anim = event.anim
    owner = event.side
    if anim == "ANIM_PSN" then entry = FxSequence.RESIDUAL_ENTRIES.poison
    elseif anim == "ANIM_BRN" then entry = FxSequence.RESIDUAL_ENTRIES.burn
    elseif anim == "ANIM_SAP" then entry = FxSequence.RESIDUAL_ENTRIES.leechSeed
    elseif anim == "ANIM_IN_NIGHTMARE" then
      -- Gold's Curse arm borrows ANIM_IN_NIGHTMARE; the cursed flag decides.
      local volatile = self:volatileFor(event.side)
      entry = (volatile and volatile.cursed) and FxSequence.RESIDUAL_ENTRIES.curse
        or FxSequence.RESIDUAL_ENTRIES.nightmare
    elseif anim == false and event.animMove then
      -- HandleWrap's tick names the trapping move (Sequence.TRAP_ENTRIES).
      entry = FxSequence.TRAP_ENTRIES[tonumber(event.animMove)]
    end
  elseif event.kind == "heal" and sideOk(event.side) then
    owner = event.side
    local moving = self.presentedMove
    if event.anim == "RECOVER" then
      entry = FxSequence.HEAL_ENTRY -- held berry (ItemRecoveryAnim)
    elseif moving and moving.side == event.side then
      local data = self.screen and self.screen.game and self.screen.game.data
      local def = data and data.moves and data.moves[moving.move]
      if def and DRAIN_EFFECTS[def.effect] then
        entry = FxSequence.DRAIN_ENTRIES[moving.move] or FxSequence.HEAL_ENTRY
      end
    end
  elseif event.kind == "stage" and sideOk(event.side) then
    local moving = self.presentedMove or {}
    local volatile = self:volatileFor(event.side)
    owner = event.side
    entry = FxSequence.statChangeEntry({side = event.side, stages = event.stages,
      moveSide = moving.side, moveId = moving.move, rage = volatile and volatile.rage})
  elseif (event.kind == "send" or event.kind == "sendout") then
    owner = sideOk(event.side) and event.side or "player"
    entry = FxSequence.SEND_OUT_ENTRY
  end
  if entry then
    pcall(fx.signalEffect, fx, entry, owner)
    return
  end
  if event.kind == "message" and self:isEnemyWithdraw(event.text) then
    pcall(fx.signalEffect, fx, FxSequence.RECALL_ENTRY, "enemy")
    return
  end
  if event.kind == "message" then
    local weather = weatherFrom("WEATHER_TURN_TEXT", event.text)
    entry = weather and FxSequence.WEATHER_ENTRIES[weather].turn
    owner = FxSequence.WEATHER_OWNER
  elseif event.kind == "weather" and event.weather == nil then
    local weather = weatherFrom("WEATHER_END_TEXT", event.text)
    entry = weather and FxSequence.WEATHER_ENTRIES[weather].ended
    owner = FxSequence.WEATHER_OWNER
  elseif event.kind == "damage" and event.anim == "ANIM_IN_SANDSTORM"
      and (event.side == "player" or event.side == "enemy") then
    entry, owner = FxSequence.SANDSTORM_HIT_ENTRY, event.side
  end
  if entry then pcall(fx.signalEffect, fx, entry, owner) end
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
  local actor=self.actors[side]
  self.minimized=self.minimized or {}
  local state=screen and screen.animPicState and screen:animPicState(side)
  if state and state.pic=="minimize" then self.minimized[side]=actor and actor.mon
  elseif state and state.pic~=nil and state.pic~="substitute" then self.minimized[side]=nil end
  -- With battle FX on, Stadium's own Minimize routine (84122998, actor
  -- sizeScale 0.8) shrinks the model; the Game Boy 0.35 applies otherwise.
  if actor and not self.battleFx and self.minimized[side]==actor.mon and actor.mon
      and not (state and state.pic=="substitute") and not self.substituteActive[side] then return .35 end
  if not (screen and screen.anim and state) then return 1 end
  if not screen.ballThrow then return 1 end
  local size=tonumber(state.size)
  return (PIC_SCALE[side] and PIC_SCALE[side][size]) or 1
end

function Scene:syncBattleFxAnimation(started)
  if self.battleFxMovePending then
    local runner=self.screen and self.screen.anim
    local ended=(self.battleFxAnimation and runner~=self.battleFxAnimation)
      or (started and not runner)
    if runner and not self.battleFxAnimation then self.battleFxAnimation=runner end
    if runner and type(runner.done)=="function" then
      local ok,done=pcall(runner.done,runner)
      ended=ok and done or ended
    end
    if ended then
      if self.battleFx and self.battleFx.finish then self.battleFx:finish() end
      self.battleFxMovePending=false;self.battleFxAnimation=nil
    end
  end
end

function Scene:update(dt)
  self:sync()
  self:syncBattleFxAnimation()
  for _,side in ipairs({"player","enemy"}) do
    local actor=self.actors[side]
    if actor.pendingFaint then
      local shown=self.screen and self.screen.shownHp and self.screen.shownHp[side]
      local slide=self.screen and self.screen.faintSlide
      if (shown==nil or shown<=0) and slide and slide.side==side then
        if actor:faint() and self.battleFx and self.battleFx.playFaint then
          pcall(self.battleFx.playFaint,self.battleFx,side,actor)
        end
      end
    end
  end
  self:stepArena(dt)
  Camera.stickOrbit(self.stickX,dt)
  Camera.stickPitch(-self.stickY,dt)
  Camera.update(dt)
  for _,which in ipairs({"player","enemy"}) do
    local actor=self.actors[which]
    if actor.setRest then actor:setRest(self:restCondition(which)) end
  end
  self.actors.player:update(dt)
  self.actors.enemy:update(dt)
  self.substituteActors.player:update(dt)
  self.substituteActors.enemy:update(dt)
  self:updateBattleFx(dt)
  return self:render()
end

local function active(screen)
  return session and screen and session.battle == screen.battle and session or nil
end

local function installScreenHooks()
  local BattleState = require("src.ui.gen2.BattleState")
  if BattleState.stadium2ImporterGen2 then return end
  BattleState.stadium2ImporterGen2 = true

  local Battle=require("src.battle.gen2.Battle")
  local emit=Battle.emit
  if emit then
    function Battle:emit(event,...)
      if session and session.battle==self then session:recordEvent(event) end
      return emit(self,event,...)
    end
  end

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
    local scene=active(screen)
    if scene then scene.trainerImageOriginals={enemyTrainerImage=screen.enemyTrainerImage,
      playerBackImage=screen.playerBackImage,prepared=screen.stadium2ImporterTrainerImagesPrepared,applied={}} end
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
    if scene then
      scene.trainerImageOriginals.applied.enemyTrainerImage=screen.enemyTrainerImage
      scene.trainerImageOriginals.applied.playerBackImage=screen.playerBackImage
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
    -- Battle Art may use the ready Stadium canvas as its world pass while
    -- retaining complete ownership of the Gen 2 HUD/text/menu compositor. In
    -- that narrow pass, skip Stadium's detached HUD compositor and expose the
    -- engine draw captured before this wrapper was installed.
    if self.stadium2ImporterBattleArtUiPass then
      return originalWide(self,width,height)
    end
    local scene = active(self)
    if not scene then
      if session and not session.diagnosticDrawMiss then
        session.diagnosticDrawMiss=true
        diagnostic(("draw-miss sessionBattle=%s screenBattle=%s same=%s")
          :format(tostring(session.battle),tostring(self and self.battle),
            tostring(session.battle==self.battle)))
      end
      return originalWide(self,width,height)
    end
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
    -- When Stadium installed after Battle Art, this wrapper is the outermost
    -- draw function. Hand the completed world canvas inward before Stadium's
    -- detached HUD compositor runs; Battle Art will discover the active scene,
    -- draw that canvas, and own the entire native UI pass. The reciprocal
    -- bypass above covers the opposite load order without recursion.
    if BattleState.battleArtGen2WidescreenAdapter then
      if not scene.diagnosticBattleArtUiOwner then
        scene.diagnosticBattleArtUiOwner=true
        diagnostic("ui-owner battle-art outer=stadium")
      end
      return originalWide(self,width,height)
    end
    local picture=scene.presentCanvas or scene.canvas
    local g = love.graphics
    if picture and scene.readyFrame and not scene.defect then
      if not scene.diagnosticDrawOwned then
        scene.diagnosticDrawOwned=true
        diagnostic(("draw-owned picture=true ready=%s defect=nil size=%sx%s")
          :format(tostring(scene.readyFrame),tostring(width),tostring(height)))
      end
      g.setColor(1,1,1,1)
      g.draw(picture, 0, 0, 0,
        width / picture:getWidth(), height / picture:getHeight())
      -- Exit fade (finishBattle -> completeBattle): Gold lightens BGP to
      -- white in steps; the native UI layers follow BGP, the Stadium picture
      -- follows the same steps through a white overlay.
      local bgp=type(self.exitFadeBgp)=="function" and self:exitFadeBgp() or nil
      if bgp then
        local lighten=(3-math.floor(bgp/64)%4)/3
        if lighten>0 then
          g.setColor(1,1,1,lighten)
          g.rectangle("fill",0,0,width,height)
          g.setColor(1,1,1,1)
        end
      end
    else
      if not scene.diagnosticDrawFallback then
        scene.diagnosticDrawFallback=true
        diagnostic(("draw-fallback picture=%s ready=%s defect=%s")
          :format(tostring(picture~=nil),tostring(scene.readyFrame),
            tostring(scene.defect)))
      end
      UIOwnership.release(self)
      return originalWide(self,width,height)
    end
    scene.statusHudOwned=UIOwnership.claimStatus(self)
    scene.bottomUiVisible=UIOwnership.bottomVisible(self)
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
    -- With Stadium battle FX on, Stadium's effects replace the Game Boy
    -- animation objects (the host animation still runs for timing). The ball
    -- throw has no Stadium effect and stays native.
    local hideObjects=scene.battleFx~=nil and objectRunner~=nil
      and objectRunner.animId~="ANIM_THROW_POKE_BALL"
    scene.deferAnimationObjects=deferObjects
    -- Keep battle ownership in the Stadium scene during the caught-mon
    -- nickname prompt. Its Yes/No window is composited separately from the
    -- snapped status HUD bands below and wears the same frosted glass as them.
    local nicknameModal=self.phase=="ask-nickname"
      and (self.messageTimer or 0)<=0
    -- Crystal's MoveSelectionScreen has a second, raised TYPE/PP window at
    -- native rows 64..103. The ordinary wide compositor only retains the
    -- three 48px HUD bands, which cuts the upper 32px off that window. Mark
    -- the capture and composition from the engine's active cart identity;
    -- this must not depend on CRYSTAL_251 (or any other installed mod).
    scene.crystalMovePane=GameVersion.engine()=="crystal"
      and self.phase=="moves"
    local layerOk,layer=pcall(Hud.layer,function() self:drawScene() end,
      {crystalMovePane=scene.crystalMovePane,
        statusOwned=scene.statusHudOwned,bottomOwned=scene.bottomUiVisible,
        preservePaper=not UIOwnership.hudEnabled()})
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
    local hudLayerOk,hudLayer=true,nil
    if scene.statusHudOwned then
      hudLayerOk,hudLayer=pcall(UIOwnership.withNativeStatus,self,function()
      local had=rawget(self,"hudCleared")
      self.hudCleared=function() return false end
      local ok,result=pcall(Hud.hudLayer,function()
        self:drawHud()
        UIOwnership.drawLegacyGen2Status(self)
        UIOwnership.drawStatusOverlay(self)
      end)
      self.hudCleared=had
      if not ok then error(result,0) end
      return result
      end)
    end
    local modalLayerOk,modalLayer=true,nil
    if nicknameModal and scene.bottomUiVisible then
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
    local composed=Hud.composite(scene,self,layer,hudLayer,modalLayer,
      {decorate=UIOwnership.hudEnabled()})
    if deferObjects and objectRunner and self.animView and not hideObjects then
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

  -- Called by the host only when the move script actually starts (including
  -- deferred/called moves), not for announcements or misses.
  if BattleState.animForMove then
    local animForMove=BattleState.animForMove
    function BattleState:animForMove(move,side,...)
      local started=animForMove(self,move,side,...)
      local scene=active(self)
      if started and scene and scene.actors[side] then
        local data=self.game and self.game.data
        local def=data and data.moves and data.moves[move]
        if def then scene:startMoveClip(side,tonumber(def.index or def.number)) end
      end
      return started
    end
  end

  local originalAdvance = BattleState.advanceQueue
  function BattleState:advanceQueue(...)
    local event = self.queue and self.queue[1] or nil
    local scene = active(self)
    local after = event and (event.kind == "send" or event.kind == "sendout"
      or event.kind == "transform")
    if scene and event and not after then
      scene.screen = self
      scene:handleEvent(event)
    end
    local result = originalAdvance(self, ...)
    if scene and event and event.kind=="move" then scene:syncBattleFxAnimation(true) end
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
  -- finishBattle only starts the exit fade; the scene stays until
  -- completeBattle, which ends the fade and hands the screen back.
  local originalFinishBattle=BattleState.finishBattle
  function BattleState:finishBattle(...)
    self.stadium2ImporterRetainedAnim=nil
    return originalFinishBattle(self,...)
  end
  local originalCompleteBattle=BattleState.completeBattle
  if originalCompleteBattle then
    function BattleState:completeBattle(...)
      local scene=active(self)
      local function finish(...)
        if scene and session==scene then Gen2.finish(nil,true) end
        return ...
      end
      return finish(originalCompleteBattle(self,...))
    end
  else
    -- Hosts without completeBattle: release where the fade starts.
    function BattleState:finishBattle(...)
      local scene=active(self)
      self.stadium2ImporterRetainedAnim=nil
      local result=originalFinishBattle(self,...)
      if scene then Gen2.finish(nil,true) end
      return result
    end
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
  patches=PatchScope.new()
  patches:capture({require("src.ui.gen2.BattleState"),require("src.battle.gen2.Battle"),
    require("src.ui.gen2.BattleAnimView"),require("src.core.Game2")},function()
    installScreenHooks()
    installAnimationProjection()
    installControls()
  end)
  installed = true
  return true
end

function Gen2.ensure(battle,context)
  -- Gen 2 announces the same encounter twice: Battle.new emits the logical
  -- battle model, then BattleState.new emits the presentation screen.  The
  -- latter stores the former in `screen.battle`.  Treat that second event as
  -- the point where the already-built Stadium scene gains its screen instead
  -- of replacing the good scene with one built from the screen wrapper (which
  -- has no direct player/enemy fields).
  local screen
  if type(battle)=="table" and type(battle.battle)=="table" then
    screen=battle
    battle=battle.battle
  end
  local models=Importer.modelsEnabled()
  local battles=Importer.battleEnabled()
  local available=Importer.available(configured)
  diagnostic(("ensure installed=%s battle=%s models=%s battles=%s "
      .."available=%s configured=%s")
    :format(tostring(installed),tostring(battle~=nil),tostring(models),
      tostring(battles),tostring(available),tostring(configured)))
  if not (installed and battle and models and battles and available) then
    return false
  end
  if session and session.battle == battle then
    if screen then
      session.screen=screen
      session:sync()
      diagnostic(("scene-bound player=%s enemy=%s screen=true")
        :format(tostring(session.actors.player.dex),
          tostring(session.actors.enemy.dex)))
    end
    return true
  end
  Gen2.finish()
  session = Scene.new(battle,context)
  if screen then session.screen=screen end
  session:sync()
  diagnostic(("scene-created player=%s enemy=%s playerRenderer=%s "
      .."enemyRenderer=%s arena=%s")
    :format(tostring(session.actors.player.dex),
      tostring(session.actors.enemy.dex),
      tostring(session.actors.player.renderer~=nil),
      tostring(session.actors.enemy.renderer~=nil),
      tostring(session.arenaMode==true)))
  return true
end

function Gen2.update(dt)
  if not session then return false end
  -- Options and cache readiness are sampled when the battle begins.  Once a
  -- scene owns the fight, only BattleState:finishBattle may release it.
  local result=session:update(math.min(math.max(tonumber(dt) or 0, 0), .1))
  if session.defect then
    diagnostic("render-defect: "..tostring(session.defect))
  elseif session.readyFrame then
    diagnostic(("scene-ready player=%s enemy=%s arena=%s")
      :format(tostring(session.actors.player.renderer~=nil),
        tostring(session.actors.enemy.renderer~=nil),
        tostring(session.arenaMode==true)))
  end
  return result
end

local function shouldDeferFinish(current,battle)
  return current and battle and current.battle==battle and current.screen
    and current.screen.phase~="done"
end

function Gen2.finish(battle, force)
  if type(battle)=="table" and type(battle.battle)=="table" then
    battle=battle.battle
  end
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
    betaArena=session and session.arenaMode or false,
    arenaIndex=session and session.arenaIndex or nil,
    arenaReason=session and session.arenaSelectionReason or nil,
    ui=session and {statusHudOwned=session.statusHudOwned==true,
      bottomUiVisible=session.bottomUiVisible~=false} or nil,
    shot=session and (session.presentCanvas or session.canvas) or nil,
    defect=session and session.defect or nil,
    visual=session and {
      player=session:visualState("player"),enemy=session:visualState("enemy")
    } or nil }
end

function Gen2.currentScene()
  return session
end

function Gen2.uninstall()
  if patches then patches:restore();patches=nil end
  installed=false
  Gen2.finish(nil,true)
end

function Gen2.resetForTests()
  Gen2.uninstall()
  ArenaRuntime.resetForTests()
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
