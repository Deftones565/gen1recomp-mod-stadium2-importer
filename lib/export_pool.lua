local ExportPool = {}

local serial = 0

local function threadApi()
  local ok, api = pcall(function() return love and love.thread end)
  return ok and api or nil
end

local function supportedPlatform()
  local ok, name = pcall(function()
    return love and love.system and love.system.getOS and love.system.getOS()
  end)
  return not (ok and (name == "Android" or name == "iOS" or name == "Web"))
end

local function workerPath(root)
  root = tostring(root or "mods/STADIUM2_IMPORTER"):gsub("/+$", "")
  return root .. "/workers/export_worker.lua"
end

local function newThread(api, path, source)
  if type(source) == "string" and love and love.filesystem
      and type(love.filesystem.newFileData) == "function" then
    local fileData = love.filesystem.newFileData(source, "stadium2_export_worker.lua")
    return api.newThread(fileData)
  end
  return api.newThread(path)
end

function ExportPool.new(data, count, writePack, writeSpecial, options)
  local api = threadApi()
  if not api or not supportedPlatform() then return nil, "threading unavailable" end
  options = type(options) == "table" and options or {}
  serial = serial + 1
  local token = ("s2_export_%d_%d"):format(os.time(), serial)
  local outputName = token .. "_out"
  local output = api.getChannel(outputName)
  if output.clear then output:clear() end

  local workers, acks, commands = {}, {}, {}
  local workerCount = 2
  for worker = 1, workerCount do
    local commandName = token .. "_cmd_" .. worker
    local ackName = token .. "_ack_" .. worker
    local ok, thread = pcall(newThread, api, workerPath(options.root), options.workerSource)
    if not ok or not thread then
      for _, channel in ipairs(commands) do channel:push({ cancel = true }) end
      return nil, tostring(thread or "worker creation failed")
    end
    local started, startErr = pcall(thread.start, thread, commandName, outputName, ackName)
    if not started then
      for _, channel in ipairs(commands) do channel:push({ cancel = true }) end
      return nil, tostring(startErr)
    end
    workers[worker] = thread
    acks[worker] = api.getChannel(ackName)
    commands[worker] = api.getChannel(commandName)
    if acks[worker].clear then acks[worker]:clear() end
  end
  for worker = 1, workerCount do
    local assigned = {}
    for species = worker, count, workerCount do assigned[#assigned + 1] = species end
    commands[worker]:push({
      rom = data, count = count, species = assigned,
      specials = worker == 1, worker = worker, packagePath = options.packagePath,
    })
  end

  local job = {
    phase = "parallel-export", buildStage = "parallel-export",
    total = count + 26, done = 0, builtCount = 0, animatedBuilt = 0,
    animationClips = 0, unownBuilt = 0, workers = workers,
    completed = 0, success = false,
  }

  local function fail(message)
    job.error = tostring(message or "parallel export failed")
    for _, channel in ipairs(acks) do channel:push(false) end
    return false
  end

  function job:step()
    if self.error or self.success then return false end
    local message = output:pop()
    if not message then
      for _, thread in ipairs(workers) do
        local err = thread.getError and thread:getError()
        if err then return fail(err) end
      end
      return true
    end
    if message.kind == "pair" then
      local ok, err = writePack(message.species, message.normal, message.shiny)
      acks[message.worker or ((message.species - 1) % workerCount + 1)]:push(ok == true)
      if not ok then return fail(err) end
      self.done = self.done + 1
      self.species = message.species
    elseif message.kind == "special" then
      local ok, err = writeSpecial(message.name, message.bytes)
      -- Specials are assigned to worker one.
      acks[1]:push(ok == true)
      if not ok then return fail(err) end
      if not tostring(message.name):find("_shiny$", 1, false) then
        self.done = self.done + 1
      end
    elseif message.kind == "complete" then
      self.completed = self.completed + 1
      self.builtCount = self.builtCount + (message.builtCount or 0)
      self.animatedBuilt = self.animatedBuilt + (message.animatedBuilt or 0)
      self.animationClips = self.animationClips + (message.animationClips or 0)
      self.unownBuilt = self.unownBuilt + (message.unownBuilt or 0)
      self.specialBuilt = self.specialBuilt or message.specialBuilt
      if self.completed == workerCount then
        self.success = self.builtCount == count and self.specialBuilt
          and self.unownBuilt == 25
        if not self.success then return fail("parallel export completed with missing models") end
        self.phase, self.buildStage = "done", nil
        return false
      end
    elseif message.kind == "error" then
      return fail(message.error)
    end
    return true
  end

  function job:progress()
    return math.min(1, self.done / math.max(1, self.total))
  end
  return job
end

return ExportPool
