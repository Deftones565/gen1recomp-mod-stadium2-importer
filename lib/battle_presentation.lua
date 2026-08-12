-- Public, generation-neutral Stadium battle presentation API.
--
-- This API owns rendering only. Callers supply battle meaning (which Pokemon
-- is out, when an attack/send-out/faint happens, and what UI they want). It
-- never calculates damage, capture odds, turn order, switching or battle RNG.
local Actor = require("mods.STADIUM2_IMPORTER.lib.battle_actor")
local Scene = require("mods.STADIUM2_IMPORTER.lib.battle_scene")
local Camera = require("mods.STADIUM2_IMPORTER.lib.battle_camera")

local Presentation = {}

function Presentation.newActor(side, opts)
  return Actor.new(side, opts)
end

function Presentation.newScene(opts)
  opts=opts or {}
  if not opts.actors then
    local actorOpts=opts.actorOptions or {}
    opts.actors={
      player=Actor.new("player",actorOpts),
      enemy=Actor.new("enemy",actorOpts),
    }
  end
  return Scene.new(opts)
end

-- Semantic helpers for callers that do not need a generation adapter.
function Presentation.setBattler(scene, side, data, mon, forcedDex)
  local actor=scene and scene.actors and scene.actors[side]
  return actor and actor:load(data,mon,forcedDex) or false
end

function Presentation.removeBattler(scene, side)
  local actor=scene and scene.actors and scene.actors[side]
  if not actor then return false end
  actor:release()
  return true
end

function Presentation.sendOut(scene, side)
  local actor=scene and scene.actors and scene.actors[side]
  return actor and actor:entrance() or false
end

function Presentation.useMove(scene, side, moveNumber)
  local actor=scene and scene.actors and scene.actors[side]
  return actor and actor:attack(tonumber(moveNumber)) or false
end

function Presentation.hit(scene, side, duration)
  local actor=scene and scene.actors and scene.actors[side]
  if not actor then return false end
  actor.flash=math.max(actor.flash or 0,tonumber(duration) or .12)
  return true
end

function Presentation.faint(scene, side)
  local actor=scene and scene.actors and scene.actors[side]
  return actor and actor:faint() or false
end

function Presentation.update(scene, dt)
  if not scene then return false end
  dt=math.max(0,tonumber(dt) or 0)
  Camera.update(dt)
  for _,actor in pairs(scene.actors or {}) do actor:update(dt) end
  return scene:render()
end

Presentation.Actor=Actor
Presentation.Scene=Scene
Presentation.Camera=Camera

return Presentation
