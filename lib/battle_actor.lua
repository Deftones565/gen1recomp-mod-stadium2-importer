-- Generation-neutral Stadium model actor.
--
-- This module owns only presentation state: model selection, Stadium animation
-- playback, send-out growth, hit flash, and the terminal faint pose. Battle
-- simulation remains entirely in the host generation's battle engine.
local Importer = require("mods.STADIUM2_IMPORTER.lib.importer")
local RestPose = require("mods.STADIUM2_IMPORTER.lib.battle_rest_pose")
local Sequence = require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_sequence")
local Special = require("mods.STADIUM2_IMPORTER.lib.battle_special_moves")
local Dispatch = require("mods.STADIUM2_IMPORTER.lib.animation_dispatch")
local Pack = require("mods.STADIUM2_IMPORTER.lib.pack")

local Actor = {}
Actor.__index = Actor

-- 84114804 sets a per-move behaviour kind at actor+0x61F; 8411845C runs its
-- start routine (84123F60) at the move's hit frame and its update routine
-- (84124104) every later frame of the attack state. Kind 9 (Minimize) is
-- 84122998: uniform scale Math_StepToF(scale, 0.8, 0.01, 0.01). Kinds 6
-- (Agility) and 7 (Double Team) move the battler and draw two translucent
-- copies; kind 0xD (Meditate) wobbles its per-axis scale
-- (lib/battle_special_moves.lua). Other kinds (4/8/0xA/0xC/0xE/0x13/0x18/
-- 0x19/0x1A) are not decoded yet and do nothing here.
Actor.SPECIAL_KINDS = Special.KINDS
Actor.MINIMIZE_TARGET, Actor.MINIMIZE_STEP = 0.8, 0.01

local STATE_RANK = { idle=0, entrance=1, attack=2, attack_default=2, hit=2, faint=3 }
local SHINY_ATTACK = {
  [2]=true,[3]=true,[6]=true,[7]=true,[10]=true,[11]=true,[14]=true,[15]=true,
}

local function clamp(value, lo, hi)
  return math.max(lo, math.min(hi, tonumber(value) or lo))
end

local function defaultDex(data, mon)
  if not mon then return nil end
  if type(mon.species) == "number" then
    local dex = math.floor(mon.species)
    return dex >= 1 and dex <= 251 and dex or nil
  end
  local def = data and data.pokemon and data.pokemon[mon.species]
  local dex = def and tonumber(def.dex or def.index)
  dex = dex and math.floor(dex) or nil
  return dex and dex >= 1 and dex <= 251 and dex or nil
end

local function defaultShiny(mon)
  if mon and mon.shiny ~= nil then return mon.shiny and true or false end
  local d = mon and mon.dvs
  return d and d.defense == 10 and d.speed == 10 and d.special == 10
    and SHINY_ATTACK[d.attack] == true or false
end

function Actor.new(side, opts)
  opts = opts or {}
  return setmetatable({
    side=side, mon=nil, dex=nil, variant=nil, renderer=nil,
    context="idle", callbackFrame=0, grow=nil, flash=0,
    dynamicObjectIndex=nil,
    modelAlphaByte=255,
    faintFinished=false, pendingFaint=false,
    failedFor=nil, failedForm=nil, form=nil,
    dexOf=opts.dexOf or defaultDex,
    shiny=opts.shiny or defaultShiny,
    formFor=opts.formFor,
    warn=opts.warn,
    label=opts.label or "battle",
  }, Actor)
end

function Actor:release()
  if self.renderer and self.renderer.release then
    pcall(self.renderer.release, self.renderer)
  end
  self.renderer=nil
  self.mon,self.dex,self.variant,self.form=nil,nil,nil,nil
  self.context,self.callbackFrame="idle",0
  self.nativeCharge,self.nativeLift,self.heldAttack=nil,nil,nil
  self.grow=nil
  self.flash=0
  self.faintFinished=false
  self.pendingFaint=false
  self.rest,self.restKey,self.restHold,self.restHidden=nil,nil,nil,false
  self.sizeScale,self.special=1,nil
  self.nativeMarkerRow,self.nativeScaleSource=nil,nil
  self:clearNative()
end

-- Presentation left behind by kinds 6/7: the sway offset (Stadium units,
-- relative to the home slot), the afterimage copies and the model alpha.
-- The "MOVE EFFECTS (BETA)" option (Importer.betaBattleFxEnabled);
-- tests may set Actor.forceFx.
function Actor.fxEnabled()
  if Actor.forceFx ~= nil then return Actor.forceFx end
  local ok, enabled = pcall(Importer.betaBattleFxEnabled)
  return ok and enabled == true
end

function Actor:clearNative()
  self.nativeOffset,self.afterimages,self.nativeAxisScale,self.nativeYaw,self.nativeTilt=nil,nil,nil,nil,nil
  self.modelAlphaByte=255
end

-- A state's end. With the camera director's shot resets running
-- (`reposeDriven`, Scene:stepNativeCharge), the ROM keeps a behaviour kind's
-- position, facing and scale until the next 8411EFE4 / 84120700
-- (Actor:nativeHome / nativeReset); only the copies end (841206D0 clears
-- both copy slots) and the alpha returns to 0xFF (84114BF4 at the attack's
-- end for Faint Attack / Double Team, the kinds that change it). Without
-- the director everything clears here.
function Actor:endNative()
  if not self.reposeDriven then return self:clearNative() end
  self.afterimages=nil
  self.modelAlphaByte=255
end

-- 8411EFE4: the home pose: position (a kind's displacement and Fly's
-- height), the side's facing, rotation X / Z 0. A running kind continues
-- from home, as its routines move the actor's own position.
function Actor:nativeHome()
  self.nativeLift=nil
  self.nativeOffset,self.nativeYaw,self.nativeTilt=nil,nil,nil
  local native=self.special and self.special.native
  if native and type(native.offset)=="table" then
    native.offset[1],native.offset[2],native.offset[3]=0,0,0
  end
end

-- 84120700: the home pose, scale 1 (+0x30), and 200 above the origin when
-- `lift` (the record's flying bit or Fly's attack bit). A risen Fly ends
-- at its first reset without the height.
function Actor:nativeReset(lift)
  self:nativeHome()
  self.sizeScale=1
  self.nativeAxisScale=nil
  local native=self.special and self.special.native
  if native and type(native.axisScale)=="table" then
    native.axisScale[1],native.axisScale[2],native.axisScale[3]=1,1,1
  end
  if lift then
    self.nativeLift=Special.FLY_TOP
  else
    local charge=self.nativeCharge
    if charge and charge.kind=="fly" and charge.risen then charge.landed=true end
  end
end

-- ROM trig tables (D_80087E50/D_80088E50) for the native routines; tests
-- inject Actor.trigTables.
function Actor:nativeTrig()
  if Actor.trigTables then return Actor.trigTables end
  local catalog=Importer.battleFxCatalog and Importer.battleFxCatalog()
  return catalog and catalog.trigTables
end

function Actor:startNative(kind)
  local model=self.renderer and self.renderer.model
  local profile=Dispatch.battleProfile(model and model.fxBattleProfile)
  local Layout=require("mods.STADIUM2_IMPORTER.lib.stadium_battle_layout")
  local slot=Layout.slot(self.side,self.dex)
  local actor=self
  local state,err=Special.new({kind=kind,yaw=Special.facing(self.side),
    trig=self:nativeTrig(),bodyHeight=profile and profile.bodyHeight,
    groundY=profile and profile.groundY,centerY=profile and profile.centerY,
    slotX=slot and slot[1],
    -- Surf's water height (the scene sets actor.terrainHeightAt)
    terrainHeightAt=function(x,z)
      if type(actor.terrainHeightAt)=="function" then return actor.terrainHeightAt(x,z) end
    end})
  if not state and self.warn then
    pcall(self.warn,("%s species %s: %s; move shown without it")
      :format(self.label,tostring(self.dex),tostring(err)))
  end
  return state
end

function Actor:retire(reason)
  -- A presentation failure must never hand the slot back to a native Pokemon
  -- sprite halfway through a 3D battle. Keep the renderer resident so the last
  -- complete owned frame can remain on screen; the adapter reports the defect.
  if reason and self.warn then pcall(self.warn,tostring(reason)) end
  return false
end

function Actor:play(context, loop)
  if not self.renderer then return false end
  local wanted=context or "idle"
  local nowRank=STATE_RANK[self.context] or 0
  local wantRank=STATE_RANK[wanted] or 0
  if self.context=="faint" or wantRank<nowRank then return false end
  if wanted~="attack" and self.renderer.lockTravel then
    self.renderer.lockTravel=false
    self.renderer.anchorX,self.renderer.anchorY,self.renderer.anchorZ=0,0,0
  end
  local actual=wanted
  local ok=self.renderer.setContext
    and self.renderer:setContext(actual,loop and true or false) or false
  if not ok and actual=="attack" and self.renderer.setContext then
    actual="attack_default"
    ok=self.renderer:setContext(actual,loop and true or false)
  end
  if not ok and actual~="idle" and self.renderer.setContext then
    actual="idle"
    ok=self.renderer:setContext("idle",true)
  end
  self.context=ok and actual or "idle"
  if ok then self.renderer.finished=false end
  -- Any explicit clip replaces the resting pose until it ends; an explicit
  -- idle loop already is the plain resting pose.
  self.restKey=(ok and actual=="idle" and loop) and RestPose.key({context="idle"}) or nil
  self.restHold=nil
  return ok and true or false
end

-- Host battle condition for the resting pose (flying, underground, frozen,
-- asleep). Applied while the actor is idle; see battle_rest_pose.lua.
function Actor:setRest(condition)
  self.rest=type(condition)=="table" and condition or nil
  -- Stadium's own Fly / Dig state decides the pose once it has risen or sunk
  local charge=self.nativeCharge
  if charge and (charge.risen or charge.hidden) then
    local merged={}
    for k,v in pairs(self.rest or {}) do merged[k]=v end
    if charge.risen then merged.flying=true end
    if charge.kind=="dig" then merged.underground=true end
    self.rest=merged
  end
end

-- Stadium's Fly and Dig charge turns (battle FX option), from the charge
-- row 841155B0 / 84115940 load (rows 0x100 / 0x102):
-- Fly (841155E8, Dispatch_045): the row's clip from frame 0 (84111DB4 0);
--   kind 3 from the row's hit frame (+0x619, byte 0x0B); the clip's end
--   loops context 0x106 (262); at 200 above the origin height the kind ends
--   with the battler held there (841206D0 does not re-place it).
-- Dig (84115A64, 84115B34): the playing animation until the tick after
--   frame 0x19, then the row's clip from frame 0 and, except for Diglett /
--   Dugtrio (0x32 / 0x33), kind 5 (spin, sink); the clip loops (84115988)
--   until the battler is below -3 x +0x648, when it is hidden (8411EE74).
--   Diglett / Dugtrio play the clip to its end (84115A24).
-- 84120700 then keeps the height (record +0x12 bit 1, or +0x7F4 bit 3 in
-- the Fly attack) or hides (bit 2) at every re-pose; the scene ends the
-- state when the host no longer has the charge (Scene:stepNativeCharge).
Actor.CHARGE_FLY,Actor.CHARGE_DIG=256,258
Actor.DIG_CLIP_TICK=0x1A
local function chargeHitFrame(model,entry)
  local bytes=model and model.fxDispatch
  local value=type(bytes)=="string" and bytes:byte(entry*20+0x0B+1) or nil
  if not value then return nil end
  return value>=0x80 and value-0x100 or value
end
function Actor:startNativeCharge(entry)
  local model=self.renderer and self.renderer.model
  if entry==Actor.CHARGE_FLY then
    local hit=chargeHitFrame(model,entry)
    if not hit then return false end
    self.nativeCharge={kind="fly",entry=entry}
    self.special={kind=Special.FLY,at=math.max(0,hit),clock=0,ticks=0,charge=true}
    return true
  end
  if entry==Actor.CHARGE_DIG then
    local digger=self.dex==50 or self.dex==51
    self.nativeCharge={kind="dig",entry=entry,digger=digger,wait=0,pending=true}
    -- 84115B34: kind start in substate 1 (tick 0x1A), its first update in
    -- substate 2; Special.step runs both, so from tick 0x1B
    self.special=not digger and {kind=Special.DIG,at=Actor.DIG_CLIP_TICK+1,clock=0,ticks=0,charge=true} or nil
    return true
  end
  return false
end

-- The charge turn's per-tick part (see Actor:startNativeCharge). Returns
-- true when the charge has finished its animation (the attack state ends).
function Actor:stepNativeCharge(dt)
  local charge=self.nativeCharge
  if not charge or self.context~="attack" then return false end
  local renderer=self.renderer
  if charge.pending then
    charge.wait=charge.wait+(tonumber(dt) or 0)*30
    if charge.wait>=Actor.DIG_CLIP_TICK then
      charge.pending=false
      if renderer:setContext(("rom_context_%d"):format(charge.entry),not charge.digger) then
        renderer.finished=false
      end
    end
    return false
  end
  local special=self.special
  local native=special and special.native
  if charge.kind=="fly" then
    if renderer.finished then
      renderer:setContext("rom_context_262",true);renderer.finished=false
    end
    if native and Special.flyRisen(native) then
      charge.risen=true
      self.nativeLift=Special.FLY_TOP
      self.special=nil
      return true
    end
    return false
  end
  if charge.digger then return renderer.finished end
  if native and Special.digSunk(native) then
    charge.hidden=true
    self.special=nil
    return true
  end
  return false
end

-- 841139D0 as re-run by the idle state every frame: pick the pose for the
-- current condition and switch only when it changes. Held poses stay on
-- their frame. Returns the selected pose.
function Actor:applyRest()
  local pose=RestPose.select(self.rest,self.dex)
  self.restHidden=pose.hidden==true
  local key=RestPose.key(pose)
  if pose.hidden or key==self.restKey then return pose end
  local renderer=self.renderer
  local ok=renderer and renderer.setContext
    and renderer:setContext(pose.context,pose.loop==true) or false
  if ok and pose.hold and renderer.seekFrame then ok=renderer:seekFrame(pose.hold) end
  if not ok then
    -- A species without this clip keeps its idle loop; report it once.
    if pose.context~="idle" and self.warn and self.restWarned~=key then
      self.restWarned=key
      pcall(self.warn,("species %s has no %s clip for its resting pose")
        :format(tostring(self.dex),tostring(pose.context)))
    end
    if renderer and renderer.setContext then renderer:setContext("idle",true) end
    self.restKey,self.restHold=key,nil
    return pose
  end
  renderer.finished=false
  self.restKey,self.restHold=key,pose.hold
  return pose
end

function Actor:load(data, mon, forcedDex)
  local dex = forcedDex or self.dexOf(data, mon)
  if not dex then self:release(); return false end
  local variant = self.shiny(mon) and "shiny" or "normal"
  local form = self.formFor and self.formFor(mon,dex,variant) or nil

  if self.renderer and self.mon==mon and self.dex==dex
      and self.variant==variant and self.form==form then
    return true
  end
  if self.failedFor==mon and self.dex==dex and self.failedForm==form then
    return false
  end

  self:release()
  local options={textureFilter="nearest",anisotropy=4,flipY=false,anchorTravel=true}
  local renderer,err
  if form then renderer,err=Importer.newSpecialRenderer(form,options)
  else renderer,err=Importer.newRenderer(dex,variant,options) end

  self.mon,self.dex,self.variant,self.form=mon,dex,variant,form
  -- a new Pokemon (or model) starts without a Fly / Dig state
  self.nativeCharge,self.nativeLift,self.heldAttack=nil,nil,nil
  if not renderer then
    self.failedFor=mon
    self.failedForm=form
    if self.warn then
      pcall(self.warn,("%s model %03d (%s) unavailable: %s")
        :format(self.label,dex,variant,tostring(err)))
    end
    return false
  end

  self.failedFor,self.failedForm=nil,nil
  self.renderer=renderer
  if renderer.shaderTier ~= "lit" and self.warn then
    pcall(self.warn, ("%s model %03d is using compatibility rendering; Stadium materials may be incomplete: %s")
      :format(self.label, dex, tostring(renderer.shaderError or renderer.shaderTier)))
  end
  self.callbackFrame=self.side=="enemy" and 4 or 0
  self:play("idle",true)
  return true
end

-- `strict` (viewer testing) plays only the species' own clip for this move:
-- no generic attack fallback, and the reason is returned on failure.
function Actor:attack(moveIndex, strict)
  if not self.renderer then return false,"actor has no model" end
  if self.pendingFaint or self.context=="faint" then return false,"actor is fainting" end
  if (STATE_RANK[self.context] or 0)>STATE_RANK.attack then
    return false,("actor is busy (%s)"):format(tostring(self.context))
  end
  local ok=moveIndex and self.renderer:setMove(moveIndex,false) or false
  local moveClip=ok
  if not ok and strict then
    return false,("species %s has no animation for move %s")
      :format(tostring(self.dex),tostring(moveIndex))
  end
  local model=self.renderer.model
  local timing=Sequence.attackTiming(model and model.fxDispatch,moveIndex,{species=self.dex})
  -- 84114BF4 -> 84111D64 -> 8003F2C4 with the row's body selector (lb
  -- +0x616): a selector outside the species' animation table leaves the
  -- animation unchanged. The attack still runs (see Actor.stepHeldAttack).
  -- No ROM row uses 0xFF (-1, which would clear the animation). Without
  -- the move's Stadium row the generic attack clip stands in (not native).
  local held=not ok and timing~=nil
  if held then ok=true end
  if not ok then ok=self:play("attack",false) end
  if ok then
    self.context="attack"
    self.attackMove=tonumber(moveIndex)
    -- Dig's attack turn (family 15): with the director, Stadium's visibility
    -- decides (84120D34 hides the attacker unless Diglett / Dugtrio; a later
    -- shot shows it, Scene:stepNativeCharge); without it the host brings
    -- the battler back. Fly's height stays through its attack (84120700
    -- with +0x7F4 bit 3).
    local charge=self.nativeCharge
    if charge and charge.kind=="dig" then
      if self.reposeDriven and self.attackMove==91 then charge.attack,charge.hidden=true,nil
      else self.nativeCharge=nil end
    elseif charge and not charge.risen then
      self.nativeCharge=nil
    end
    -- 84114804 -> 841146D4 loads the move's row (+61C/+61D markers).
    self.nativeMarkerRow=tonumber(moveIndex) and tonumber(moveIndex)-1 or nil
    self.nativeScaleSource=self.nativeMarkerRow and {row=self.nativeMarkerRow,byte=0xF} or nil
    self:endNative()
    self.pendingClip=nil
    self.heldAttack=held and {ends=timing.attackEnd,clock=0} or nil
    if moveClip and timing then
      if timing.preRoll>0 then
        -- 84114A04/841120AC: a negative hit frame holds the idle pose until
        -- the counter reaches 0, then 84114BF4 starts the clip.
        self.pendingClip={move=moveIndex,start=timing.clipStart,ticks=timing.preRoll,clock=0}
        if self.renderer.setContext then self.renderer:setContext("idle",true) end
      elseif timing.clipStart>0 and self.renderer.seekFrame then
        -- 84114BF4: the clip starts at the row's byte 6 (+0x61B).
        self.renderer:seekFrame(timing.clipStart)
      end
    end
    -- Stadium's per-move routines belong to the battle FX option; with it
    -- off the host keeps its own presentation (e.g. Gold's Minimize).
    local kind=Actor.fxEnabled() and Special.kindFor(moveIndex,self.dex)
    local at=kind and timing and timing.special
    self.special=at and {kind=kind,at=at,clock=0,ticks=0} or nil
  end
  return ok
end

-- An attack whose clip 8003F2C4 left unchanged (see Actor:attack). 84114BF4
-- ends it at the row's length (+0x61A, byte 0x0A) when that is set, or,
-- when it is 0, once 8003EC34 reports the playing animation at its last
-- frame (frame >= length - 1). Returns true when the attack has ended.
function Actor:stepHeldAttack(dt)
  local held=self.heldAttack
  if not held then return false end
  if self.context~="attack" then self.heldAttack=nil;return false end
  held.clock=held.clock+(tonumber(dt) or 0)*30
  local done
  if held.ends then
    done=held.clock>=held.ends
  else
    local renderer=self.renderer
    local anim=renderer.model and renderer.model.anims and renderer.model.anims[renderer.animIndex]
    done=not anim or (renderer.frame or 0)>=(anim.frames or 1)-1
  end
  if done then self.heldAttack=nil end
  return done
end

-- Idle pre-roll of a negative hit frame (see Actor:attack).
function Actor:stepPendingClip(dt)
  local pending=self.pendingClip
  if not pending then return end
  if self.context~="attack" then self.pendingClip=nil;return end
  pending.clock=pending.clock+(tonumber(dt) or 0)*30
  if pending.clock<pending.ticks then return end
  self.pendingClip=nil
  if self.renderer:setMove(pending.move,false) and pending.start>0 and self.renderer.seekFrame then
    self.renderer:seekFrame(pending.start)
  end
  self.renderer.finished=false
end

-- The defender's hit frame for a move: its own dispatch row's byte 7
-- (84117CAC); 0 for a negative byte, nil without the row.
function Actor:defenderHitFrame(moveId)
  local model=self.renderer and self.renderer.model
  local bytes=model and model.fxDispatch
  local index=tonumber(moveId)
  if type(bytes)~="string" or not index or index<1 then return nil end
  local b=bytes:byte((index-1)*20+8)
  return b and (b>=0x80 and 0 or b) or nil
end

-- Event 0x0C, 8411862C (fork C 15201a6): the target falls asleep: no hit
-- clip at the state's start; at its hit frame (the row's byte 7) the
-- fall-asleep clip 0x105 (context 261).
function Actor:fallAsleep(moveId)
  if not self.renderer then return false,"actor has no model" end
  if self.pendingFaint or self.context=="faint" then return false,"actor is fainting" end
  self.context="hit"
  self.nativeMarkerRow=254
  self:endNative()
  self.special=nil
  self.pendingStatusClip={name="rom_context_261",at=self:defenderHitFrame(moveId) or 0,clock=0}
  return true
end

function Actor:stepPendingStatusClip(dt)
  local pending=self.pendingStatusClip
  if not pending then return end
  if self.context~="hit" then self.pendingStatusClip=nil;return end
  pending.clock=pending.clock+(tonumber(dt) or 0)*30
  if pending.clock<pending.at then return end
  self.pendingStatusClip=nil
  if self.renderer:setContext(pending.name,false) then self.renderer.finished=false
  elseif self.warn then
    pcall(self.warn,("species %s has no %s clip"):format(tostring(self.dex),pending.name))
  end
end

-- Context 254: the species' own hit clip, played once with no generic
-- fallback. Returns false and a reason when the clip is unavailable.
function Actor:hit(moveId)
  if not self.renderer then return false,"actor has no model" end
  if self.pendingFaint or self.context=="faint" then return false,"actor is fainting" end
  self.flash=.12
  if (STATE_RANK[self.context] or 0)>STATE_RANK.hit then
    return false,("actor is busy (%s)"):format(tostring(self.context))
  end
  local ok=self.renderer.setContext and self.renderer:setContext("hit",false) or false
  if not ok then
    return false,("species %s has no hit clip"):format(tostring(self.dex))
  end
  self.context="hit"
  -- 84116BC0: markers from row 254, +661 from the received move's byte 0x13.
  self.nativeMarkerRow=254
  self.nativeScaleSource=tonumber(moveId) and {row=tonumber(moveId)-1,byte=0x13} or nil
  self.renderer.finished=false
  -- 84116BC0's defender kind (Stomp / Body Slam: 15), started by the hit
  -- state at its own row's byte 7 (8411845C) and stepped while it lasts
  self:endNative()
  local kind=Actor.fxEnabled() and Special.DEFENDER_KINDS[tonumber(moveId)]
  local model=self.renderer.model
  local bytes=model and model.fxDispatch
  local at
  if kind and type(bytes)=="string" then
    local b=bytes:byte((tonumber(moveId)-1)*20+8)
    at=b and (b>=0x80 and 0 or b) or nil
  end
  self.special=at and {kind=kind,at=at,clock=0,ticks=0,context="hit"} or nil
  return true
end

-- Charge turn of a two-turn move: the species' charge row (context
-- entry 255-260), started at the row's byte 6 like 84111DB4(+0x61B).
function Actor:charge(entry, startFrame)
  if not self.renderer then return false,"actor has no model" end
  if self.pendingFaint or self.context=="faint" then return false,"actor is fainting" end
  local name=("rom_context_%d"):format(tonumber(entry) or 0)
  local native=Actor.fxEnabled() and (entry==Actor.CHARGE_FLY or entry==Actor.CHARGE_DIG)
  self:endNative()
  self.nativeCharge=nil
  if not self.reposeDriven then self.nativeLift=nil end
  if native and entry==Actor.CHARGE_DIG then
    -- 84115B34 starts the clip on the tick after frame 0x19
    if not (self.renderer.setContext and Pack.contextIndex(self.renderer.model,name)) then
      return false,("species %s has no %s clip"):format(tostring(self.dex),name)
    end
  else
    local ok=self.renderer.setContext and self.renderer:setContext(name,false) or false
    if not ok then return false,("species %s has no %s clip"):format(tostring(self.dex),name) end
    -- Fly starts at frame 0 (84111DB4(actor, 0)); other rows at byte 6
    if not native and (tonumber(startFrame) or 0)>0 and self.renderer.seekFrame then
      self.renderer:seekFrame(startFrame)
    end
  end
  self.special=nil
  if native then self:startNativeCharge(entry) end
  self.context="attack"
  self.nativeMarkerRow=tonumber(entry) -- 841146D4 with the charge row
  self.nativeScaleSource=self.nativeMarkerRow and {row=self.nativeMarkerRow,byte=0xF} or nil
  self.renderer.finished=false
  self.restKey,self.restHold=nil,nil
  return true
end

function Actor:entrance()
  if self.context=="faint" then return false end
  self.grow={time=0,duration=.65}
  self.faintFinished=false
  self.pendingFaint=false
  return self:play("entrance",false)
end

function Actor:faint()
  if not self.renderer or self.context=="faint" then return false end
  self.grow=nil
  self.pendingFaint=false
  self.faintFinished=false
  return self:play("faint",false)
end

function Actor:scale()
  local size=self.sizeScale or 1
  if not self.grow then return size end
  local t=clamp(self.grow.time/self.grow.duration,0,1)
  t=t*t*(3-2*t)
  return t*size
end

-- Special routine ticks at 30 Hz while the attack state (clip) runs.
function Actor:stepSpecial(dt)
  local special=self.special
  if not special then return end
  if self.context~=(special.context or "attack") then self.special=nil;self:endNative();return end
  special.clock=special.clock+(tonumber(dt) or 0)*30
  while special.clock>=1 do
    special.clock=special.clock-1
    special.ticks=special.ticks+1
    if special.ticks>=special.at and Special.ROUTINES[special.kind] then
      if special.native==nil then special.native=self:startNative(special.kind) or false end
      if special.native then
        Special.step(special.native)
        self.nativeOffset=special.native.offset
        self.afterimages=special.native.afterimages
        self.modelAlphaByte=special.native.alpha or 255
        -- Meditate's per-axis scale (relative to the battler's own)
        self.nativeAxisScale=special.native.axisScale
        -- a kind's own facing (+0x20, binary angle): Submission's spin
        self.nativeYaw=special.native.nativeYaw
        self.nativeTilt=special.native.surfTilt
      end
    elseif special.ticks>=special.at and special.kind==9 then
      local s=self.sizeScale or 1
      local target,step=Actor.MINIMIZE_TARGET,Actor.MINIMIZE_STEP
      if s<target then s=math.min(target,s+step) else s=math.max(target,s-step) end
      self.sizeScale=s
    end
  end
end

function Actor:update(dt)
  if not self.renderer then return end
  if self.grow then
    self.grow.time=self.grow.time+dt
    if self.grow.time>=self.grow.duration then self.grow=nil end
  end
  self.flash=math.max(0,(self.flash or 0)-dt)
  self.callbackFrame=self.callbackFrame+dt*30
  self.renderer:setHandlerRuntime({
    callbackFrame=math.floor(self.callbackFrame),
    frame=self.renderer.frame,
    textureFrame=self.renderer.frame,
    species=self.dex,
    dynamicObjectIndex=self.dynamicObjectIndex,
    animationState=self.renderer.animIndex,
    animationFrame=self.renderer.frame,
    dynamicObjectEnabled=true,
    dynamicObjectUpdateEnabled=true,
    -- Stadium's Gastly gas renderer inherits the owning model object's alpha.
    modelAlphaByte=self.modelAlphaByte,
    dynamicObjectGastlyAlternate=self.variant=="shiny",
  },true)
  self:stepPendingClip(dt)
  self:stepPendingStatusClip(dt)
  self:stepSpecial(dt)
  if self.context=="idle" then self:applyRest() end
  -- A held resting pose (frozen, Diglett underground) does not advance.
  self.renderer:step(self.context=="idle" and self.restHold and 0 or dt)
  local attackEnded
  if self.heldAttack then attackEnded=self:stepHeldAttack(dt)
  elseif self.nativeCharge and self.context=="attack" then attackEnded=self:stepNativeCharge(dt)
  else attackEnded=self.renderer.finished end
  if attackEnded then
    if self.context=="faint" then
      self.faintFinished=true
    elseif self.context~="idle" then
      self.context="idle"
      self.special=nil
      self:endNative()
      self.restKey,self.restHold=nil,nil
      self:applyRest()
    end
  end
end

Actor.STATE_RANK=STATE_RANK
Actor.defaultDex=defaultDex
Actor.defaultShiny=defaultShiny

return Actor
