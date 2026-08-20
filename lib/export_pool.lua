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

local function processorCount()
  local ok, count = pcall(function()
    return love and love.system and love.system.getProcessorCount
      and love.system.getProcessorCount()
  end)
  return ok and math.max(1, math.floor(tonumber(count) or 1)) or 1
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
  -- Stadium model/animation decoding is CPU-heavy. Cap at four because every
  -- worker receives the imported 64 MiB ROM and higher counts trade too much
  -- memory for diminishing throughput. Lower-core desktops retain the proven
  -- two-worker path.
  local cores = processorCount()
  local lowMemoryArch = jit and (jit.arch == "arm" or jit.arch == "arm64")
  local workerCount = not lowMemoryArch and cores >= 8 and 4
    or (not lowMemoryArch and cores >= 4 and 3 or 2)
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

  local function handle(message)
    if message.kind == "pair" then
      local ok, err = writePack(message.species, message.normal, message.shiny)
      acks[message.worker or ((message.species - 1) % workerCount + 1)]:push(ok == true)
      if not ok then return fail(err) end
      job.done = job.done + 1
      job.species = message.species
    elseif message.kind == "special" then
      local ok, err = writeSpecial(message.name, message.bytes)
      -- Specials are assigned to worker one.
      acks[1]:push(ok == true)
      if not ok then return fail(err) end
      if not tostring(message.name):find("_shiny$", 1, false) then
        job.done = job.done + 1
      end
    elseif message.kind == "complete" then
      job.completed = job.completed + 1
      job.builtCount = job.builtCount + (message.builtCount or 0)
      job.animatedBuilt = job.animatedBuilt + (message.animatedBuilt or 0)
      job.animationClips = job.animationClips + (message.animationClips or 0)
      job.unownBuilt = job.unownBuilt + (message.unownBuilt or 0)
      job.specialBuilt = job.specialBuilt or message.specialBuilt
      if job.completed == workerCount then
        job.success = job.builtCount == count and job.specialBuilt
          and job.unownBuilt == 25
        if not job.success then return fail("parallel export completed with missing models") end
        job.phase, job.buildStage = "done", nil
        return false
      end
    elseif message.kind == "error" then
      return fail(message.error)
    end
    return true
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

    -- Workers wait for an acknowledgement after handing a completed pack to
    -- the main thread. Drain everything already queued during this update so
    -- one worker is not held for an extra 60 Hz frame merely because the
    -- other worker's result was popped first. The small time/message budget
    -- keeps the import screen responsive when a burst is ready.
    local timer = love and love.timer
    local now = timer and timer.getTime or os.clock
    local started, processed = now(), 0
    repeat
      processed = processed + 1
      if handle(message) == false then return false end
      if processed >= 16 or now() - started >= 0.006 then break end
      message = output:pop()
    until not message
    return true
  end

  function job:progress()
    return math.min(1, self.done / math.max(1, self.total))
  end
  return job
end

return ExportPool
