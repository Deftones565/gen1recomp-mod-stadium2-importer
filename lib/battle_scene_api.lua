-- Stable public facade for extending or taking over the owned battle scene.
-- Consumers should use this module through mod.find(...).exports.scene rather
-- than requiring importer internals, which are free to change between builds.
local Extensions = require("mods.STADIUM2_IMPORTER.lib.battle_scene_extensions")

local Api = {}
Api.VERSION = Extensions.API_VERSION
Api.hooks = Extensions.HOOKS
Api.battlerModes = { host=true, provider=true, native=true }

local router

function Api.bind(value)
  router=value
  return Api
end

function Api.capabilities()
  return {
    apiVersion=Api.VERSION,
    hooks=Api.hooks,
    phases={
      camera=true, background=true, environment=true, geometry=true,
      shadow=true, battlers=true, overlay=true,
    },
    battlerModes=Api.battlerModes,
  }
end

-- Register through the consuming mod's hook facade so the engine attributes
-- failures and automatic unload cleanup to that mod, not to this importer.
-- callback follows the ordinary hook contract: callback(next, context).
function Api.register(consumerMod, phase, callback, priority)
  local hook=Api.hooks[phase]
  assert(hook, "unknown Stadium battle scene phase: "..tostring(phase))
  assert(type(callback)=="function", "scene extension callback is required")
  local hooks=consumerMod and consumerMod.hooks
  assert(hooks and type(hooks.wrap)=="function",
    "the consuming mod handle is required")
  return hooks:wrap(hook,callback,priority)
end

function Api.current()
  return router and router.currentScene and router.currentScene() or nil
end

function Api.actor(side, scene)
  scene=scene or Api.current()
  return scene and scene.actors and scene.actors[side] or nil
end

function Api.host(context)
  return context and context.scene and context.scene.host or nil
end

return Api
