local Runtime = require("src.mods.Runtime")

local Extensions = {}

Extensions.API_VERSION = 1
Extensions.HOOKS = {
  camera = "battle.scene.camera.v1",
  background = "battle.scene.background.v1",
  environment = "battle.scene.environment.v1",
  geometry = "battle.scene.geometry.v1",
  shadow = "battle.scene.shadow.v1",
  battlers = "battle.scene.battlers.v1",
  overlay = "battle.scene.overlay.v1",
}

local unpack = table.unpack or unpack

local function pack(...)
  return { n = select("#", ...), ... }
end

local function invoke(ctx, name, fallback)
  local g = ctx and ctx.graphics
  local pushed = false
  if g and g.push and g.pop then
    pushed = pcall(g.push, "all")
  end
  local result = pack(pcall(Runtime.call, name, fallback, ctx))
  if pushed then pcall(g.pop) end
  if not result[1] then error(result[2], 0) end
  return unpack(result, 2, result.n)
end

function Extensions.camera(ctx, fallback)
  return invoke(ctx, Extensions.HOOKS.camera, fallback)
end

function Extensions.background(ctx, fallback)
  return invoke(ctx, Extensions.HOOKS.background, fallback)
end

function Extensions.environment(ctx, fallback)
  return invoke(ctx, Extensions.HOOKS.environment, fallback)
end

function Extensions.geometry(ctx)
  return invoke(ctx, Extensions.HOOKS.geometry, function()
    return true
  end)
end

function Extensions.shadow(ctx)
  return invoke(ctx, Extensions.HOOKS.shadow, function()
    return true
  end)
end

function Extensions.battlers(ctx, fallback)
  return invoke(ctx, Extensions.HOOKS.battlers, fallback)
end

function Extensions.overlay(ctx)
  return invoke(ctx, Extensions.HOOKS.overlay, function()
    return true
  end)
end

return Extensions
