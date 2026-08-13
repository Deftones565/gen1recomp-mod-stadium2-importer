-- Generation-neutral Stadium model actor.
--
-- This module owns only presentation state: model selection, Stadium animation
-- playback, send-out growth, hit flash, and the terminal faint pose. Battle
-- simulation remains entirely in the host generation's battle engine.
local Importer = require("mods.STADIUM2_IMPORTER.lib.importer")

local Actor = {}
Actor.__index = Actor

local STATE_RANK = { idle=0, entrance=1, attack=2, attack_default=2, faint=3 }
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
  return ok and true or false
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

function Actor:attack(moveIndex)
  if not self.renderer or self.pendingFaint or self.context=="faint" then return false end
  if (STATE_RANK[self.context] or 0)>STATE_RANK.attack then return false end
  local ok=moveIndex and self.renderer:setMove(moveIndex,false) or false
  if not ok then ok=self:play("attack",false) end
  if ok then self.context="attack" end
  return ok
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
  if not self.grow then return 1 end
  local t=clamp(self.grow.time/self.grow.duration,0,1)
  t=t*t*(3-2*t)
  return t
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
  },true)
  self.renderer:step(dt)
  if self.renderer.finished then
    if self.context=="faint" then
      self.faintFinished=true
    elseif self.context~="idle" then
      self.context="idle"
      self:play("idle",true)
    end
  end
end

Actor.STATE_RANK=STATE_RANK
Actor.defaultDex=defaultDex
Actor.defaultShiny=defaultShiny

return Actor
