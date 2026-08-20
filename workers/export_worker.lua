require("love.thread")
require("love.data")
require("love.timer")
require("love.filesystem")

package.path = "./?.lua;./?/init.lua;" .. package.path

local commandName, outputName, ackName = ...
local command = love.thread.getChannel(commandName):demand()
if command.cancel then return end
local output = love.thread.getChannel(outputName)
local ack = love.thread.getChannel(ackName)
if type(command.packagePath) == "string" then package.path = command.packagePath end

local ok, failure = pcall(function()
  local Extract = require("mods.STADIUM2_IMPORTER.lib.extract")
  Extract.configure({ count = command.count })

  local function send(message)
    output:push(message)
    return ack:demand() == true
  end

  local job = Extract.newJob(command.rom, function(species, normal, shiny)
    return send({ kind = "pair", species = species, normal = normal, shiny = shiny })
  end, function(name, bytes)
    return send({ kind = "special", name = name, bytes = bytes })
  end, { species = command.species, specials = command.specials })

  while job:step() do end
  if not job.success then error(job.error or "worker export was incomplete", 0) end
  output:push({
    kind = "complete", worker = command.worker,
    builtCount = job.builtCount or 0,
    animatedBuilt = job.animatedBuilt or 0,
    animationClips = job.animationClips or 0,
    unownBuilt = job.unownBuilt or 0,
    specialBuilt = job.specialBuilt,
  })
end)

if not ok then
  output:push({ kind = "error", worker = command.worker, error = tostring(failure) })
end
