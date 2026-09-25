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

local Actor = {}
Actor.__index = Actor

-- 84114804 sets a per-move behaviour kind at actor+0x61F; 8411845C runs its
-- start routine (84123F60) at the move's hit frame and its update routine
-- (84124104) every later frame of the attack state. Kind 9 (Minimize) is
-- 84122998: uniform scale Math_StepToF(scale, 0.8, 0.01, 0.01). Kinds 6
-- (Agility) and 7 (Double Team) move the battler and draw two translucent
-- copies (lib/battle_special_moves.lua). Other kinds (4/8/0xA/0xC/0xD/0xE/
-- 0x13/0x18/0x19/0x1A) are not decoded yet and do nothing here.
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
function Actor:clearNative()
  self.nativeOffset,self.afterimages=nil,nil
  self.modelAlphaByte=255
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
  local state,err=Special.new({kind=kind,yaw=Special.facing(self.side),
    trig=self:nativeTrig(),bodyHeight=profile and profile.bodyHeight})
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
  if not ok and strict then
    return false,("species %s has no animation for move %s")
      :format(tostring(self.dex),tostring(moveIndex))
  end
  if not ok then ok=self:play("attack",false) end
  if ok then
    self.context="attack"
    -- 84114804 -> 841146D4 loads the move's row (+61C/+61D markers).
    self.nativeMarkerRow=tonumber(moveIndex) and tonumber(moveIndex)-1 or nil
    self.nativeScaleSource=self.nativeMarkerRow and {row=self.nativeMarkerRow,byte=0xF} or nil
    self:clearNative()
    local kind=Actor.SPECIAL_KINDS[tonumber(moveIndex)]
    local model=self.renderer.model
    local hit=kind and Sequence.hitFrame(model and model.fxDispatch,moveIndex)
    self.special=hit and {kind=kind,at=hit,clock=0,ticks=0} or nil
  end
  return ok
end

-- Context 254: the species' own hit clip, played once with no generic
-- fallback. Returns false and a reason when the clip is unavailable.
function Actor:hit(moveId)
  if not self.renderer then return false,"actor has no model" end
  if self.context=="faint" then return false,"actor is fainting" end
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
  return true
end

-- Charge turn of a two-turn move: the species' charge row (context
-- entry 255-260), started at the row's byte 6 like 84111DB4(+0x61B).
function Actor:charge(entry, startFrame)
  if not self.renderer then return false,"actor has no model" end
  if self.pendingFaint or self.context=="faint" then return false,"actor is fainting" end
  local name=("rom_context_%d"):format(tonumber(entry) or 0)
  local ok=self.renderer.setContext and self.renderer:setContext(name,false) or false
  if not ok then return false,("species %s has no %s clip"):format(tostring(self.dex),name) end
  if (tonumber(startFrame) or 0)>0 and self.renderer.seekFrame then
    self.renderer:seekFrame(startFrame)
  end
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
  if self.context~="attack" then self.special=nil;self:clearNative();return end
  special.clock=special.clock+(tonumber(dt) or 0)*30
  while special.clock>=1 do
    special.clock=special.clock-1
    special.ticks=special.ticks+1
    if special.ticks>=special.at and (special.kind==Special.AGILITY
        or special.kind==Special.DOUBLE_TEAM) then
      if special.native==nil then special.native=self:startNative(special.kind) or false end
      if special.native then
        Special.step(special.native)
        self.nativeOffset=special.native.offset
        self.afterimages=special.native.afterimages
        self.modelAlphaByte=special.native.alpha or 255
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
  self:stepSpecial(dt)
  if self.context=="idle" then self:applyRest() end
  -- A held resting pose (frozen, Diglett underground) does not advance.
  self.renderer:step(self.context=="idle" and self.restHold and 0 or dt)
  if self.renderer.finished then
    if self.context=="faint" then
      self.faintFinished=true
    elseif self.context~="idle" then
      self.context="idle"
      self.special=nil
      self:clearNative()
      self.restKey,self.restHold=nil,nil
      self:applyRest()
    end
  end
end

Actor.STATE_RANK=STATE_RANK
Actor.defaultDex=defaultDex
Actor.defaultShiny=defaultShiny

return Actor
