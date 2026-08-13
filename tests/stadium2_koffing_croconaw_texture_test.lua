package.path = "./?.lua;./?/init.lua;" .. package.path

local Pack = require("mods.STADIUM2_IMPORTER.lib.pack")
local Handlers = require("mods.STADIUM2_IMPORTER.lib.model_handlers")

local TARGETS = {
  { species = 109, name = "Koffing" },
  { species = 159, name = "Croconaw" },
}

local failures = 0
local warnings = 0

local function out(fmt, ...)
  io.stdout:write(("[stadium2-texture-test] " .. fmt .. "\n"):format(...))
end

local function fail(fmt, ...)
  failures = failures + 1
  out("FAIL " .. fmt, ...)
end

local function warn(fmt, ...)
  warnings = warnings + 1
  out("WARN " .. fmt, ...)
end

local function hex(value)
  value = tonumber(value)
  return value and ("0x%X"):format(value) or "-"
end

local function readFile(path)
  local handle = io.open(path, "rb")
  if not handle then return nil end
  local bytes = handle:read("*a")
  handle:close()
  return bytes
end

local function fileExists(path)
  local handle = io.open(path, "rb")
  if not handle then return false end
  handle:close()
  return true
end

local function dirname(path)
  return path and path:match("^(.*)[/\\]normal[/\\]109%.dsm$") or nil
end

local function shellQuote(value)
  return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function discoverCacheRoot()
  local supplied = arg and arg[1] or nil
  if supplied and fileExists(supplied .. "/normal/109.dsm") then return supplied end
  local env = os.getenv("STADIUM2_CACHE_ROOT")
  if env and fileExists(env .. "/normal/109.dsm") then return env end
  if fileExists("stadium2_importer/normal/109.dsm") then return "stadium2_importer" end
  local home = os.getenv("HOME")
  local xdg = os.getenv("XDG_DATA_HOME")
  local bases = {}
  if xdg and xdg ~= "" then bases[#bases + 1] = xdg .. "/love" end
  if home and home ~= "" then
    bases[#bases + 1] = home .. "/.local/share/love"
    bases[#bases + 1] = home .. "/.local/share"
  end
  if io.popen then
    for _, base in ipairs(bases) do
      local command = "find " .. shellQuote(base)
        .. " -type f -path '*/stadium2_importer/normal/109.dsm' -print -quit 2>/dev/null"
      local pipe = io.popen(command, "r")
      if pipe then
        local found = pipe:read("*l")
        pipe:close()
        local root = dirname(found)
        if root and fileExists(root .. "/normal/159.dsm") then return root end
      end
    end
  end
  return nil
end

local function materialText(material)
  if type(material) ~= "table" then return "-" end
  local image = material.textureImage or {}
  local tile = material.activeTile or {}
  local s = tile.s or {}
  local t = tile.t or {}
  local scale = material.textureScale or {}
  return ("fmt=%s siz=%s width=%s ptr=%s tile=%s/%s pal=%s s=%s,m%s,sh%s t=%s,m%s,sh%s scale=%.4f,%.4f enabled=%s complete=%s"):format(
    tostring(image.format), tostring(image.size), tostring(image.width), hex(image.pointer),
    tostring(tile.format), tostring(tile.size), tostring(tile.palette),
    tostring(s.wrap), tostring(s.mask), tostring(s.shift),
    tostring(t.wrap), tostring(t.mask), tostring(t.shift),
    tonumber(scale[1]) or 0, tonumber(scale[2]) or 0,
    tostring(material.textureEnabled), tostring(material.complete))
end

local function uvRange(prim)
  local uv = prim and prim.uv
  if type(uv) ~= "table" or #uv < 2 then return "-" end
  local minU, maxU, minV, maxV = math.huge, -math.huge, math.huge, -math.huge
  for i = 1, #uv, 2 do
    local u, v = tonumber(uv[i]), tonumber(uv[i + 1])
    if u and v then
      minU, maxU = math.min(minU, u), math.max(maxU, u)
      minV, maxV = math.min(minV, v), math.max(maxV, v)
    end
  end
  if minU == math.huge then return "-" end
  return ("%.4f..%.4f,%.4f..%.4f"):format(minU, maxU, minV, maxV)
end

local function distinct(values)
  local seen, count = {}, 0
  for _, value in ipairs(values) do
    if value ~= nil and not seen[value] then
      seen[value] = true
      count = count + 1
    end
  end
  return count, seen
end

local function sortedKeys(map)
  local keys = {}
  for key in pairs(map or {}) do keys[#keys + 1] = key end
  table.sort(keys, function(a, b) return tonumber(a) < tonumber(b) end)
  return keys
end

local function inspect(target, model)
  local extension = model.handlers or {}
  local records = extension.records or {}
  local render = extension.render or {}
  local prims = model.prims or {}
  local textures = model.textures or {}
  local bySite = {}

  out("BEGIN species=%d name=%s prims=%d textures=%d handlers=%d handlerTextures=%d",
    target.species, target.name, #prims, #textures, #records, #(render.handlerTextures or {}))

  for i, texture in ipairs(textures) do
    if not texture.w or not texture.h or texture.w < 1 or texture.h < 1 then
      fail("species=%d texture=%d invalid-size=%sx%s", target.species, i, tostring(texture.w), tostring(texture.h))
    end
    out("TEXTURE species=%d index=%d size=%dx%d bytes=%d", target.species, i,
      tonumber(texture.w) or 0, tonumber(texture.h) or 0, type(texture.rgba) == "string" and #texture.rgba or 0)
  end

  for i, prim in ipairs(prims) do
    local site = tonumber(prim.callbackOffset)
    if site then
      local bucket = bySite[site]
      if not bucket then bucket = {}; bySite[site] = bucket end
      bucket[#bucket + 1] = i
    end
    if not textures[prim.tex] then
      fail("species=%d prim=%d baseTex=%s is outside 1..%d", target.species, i, tostring(prim.tex), #textures)
    end
    out("PRIM species=%d index=%d baseTex=%s callback=%s material=%s verts=%s idx=%s additive=%s generated=%s effect=%s uv=%s materialState={%s}",
      target.species, i, tostring(prim.tex), hex(prim.callbackOffset), hex(prim.materialOffset),
      tostring(prim.nverts), tostring(prim.nidx), tostring(prim.additive), tostring(prim.generated),
      tostring(prim.effect), uvRange(prim), materialText(prim.material))
  end

  local state = {}
  state = select(1, Handlers.runExtension(extension, 2, {
    species = target.species,
    sourceFrame = 0,
    textureFrame = 0,
    selector = 0,
    rangeValue = 0,
  }, state)) or state
  state = select(1, Handlers.runExtension(extension, 5, {
    species = target.species,
    sourceFrame = 0,
    textureFrame = 0,
    selector = 0,
    rangeValue = 0,
  }, state)) or state

  for i, record in ipairs(records) do
    local program = record.program or {}
    out("HANDLER species=%d index=%d site=%s descriptor=%s target=%s family=%s bone=%s assets=%d textures=%d complete=%s",
      target.species, i, hex(record.commandOffset), hex(record.descriptor), hex(record.target),
      tostring(record.family), tostring(record.bone), #(program.assets or {}), #(program.textures or {}),
      tostring(program.complete))
    for j, texture in ipairs(program.textures or {}) do
      local slot = (tonumber(texture.slot) or -1) + 1
      out("HANDLER_TEXTURE species=%d handler=%d index=%d site=%s slot=%d size=%dx%d fmt=%s siz=%s ptr=%s",
        target.species, i, j, hex(texture.commandOffset), slot, tonumber(texture.w) or 0,
        tonumber(texture.h) or 0, tostring(texture.format), tostring(texture.size), hex(texture.pointer))
      if slot < 1 or slot > #textures then
        fail("species=%d handler=%d texture-slot=%d is outside 1..%d", target.species, i, slot, #textures)
      end
      if record.descriptor == 0x81000070 then
        if texture.w ~= 32 or texture.h ~= 32 or texture.format ~= 4 or texture.size ~= 0 then
          fail("species=%d handler=%d frame=%d callback texture=%sx%s fmt=%s siz=%s expected=32x32 I4",
            target.species, i, j, tostring(texture.w), tostring(texture.h), tostring(texture.format), tostring(texture.size))
        end
        if j > 1 then
          local previous = program.textures[j - 1]
          local stride = (tonumber(texture.pointer) or 0) - (tonumber(previous.pointer) or 0)
          if stride ~= 0x200 then
            fail("species=%d handler=%d frame=%d pointer stride=0x%X expected=0x200",
              target.species, i, j, stride)
          end
        end
      end
    end
    if record.family == "dynamic-object-renderer" then
      local site = tonumber(record.commandOffset)
      local controlled = bySite[site] or {}
      local baseTextures = {}
      for _, primIndex in ipairs(controlled) do baseTextures[#baseTextures + 1] = prims[primIndex].tex end
      local count = distinct(baseTextures)
      local selected = state.textureBySite and state.textureBySite[site] or nil
      out("DYNAMIC_OBJECT species=%d site=%s controlledPrims=%d distinctBaseTextures=%d selectedTexture=%s objectTransforms=missing",
        target.species, hex(site), #controlled, count, tostring(selected))
      if selected ~= nil then
        fail("species=%d site=%s overrides base texture without object transforms: runtimeTexture=%s",
          target.species, hex(site), tostring(selected))
      elseif #controlled == 0 then
        warn("species=%d site=%s dynamic-object handler controls no packed primitive", target.species, hex(site))
      end
      local simulatedState = {}
      simulatedState = select(1, Handlers.runExtension(extension, 2, {
        species = target.species,
        sourceFrame = 0,
        callbackFrame = 0,
        textureFrame = 0,
        selector = 0,
        rangeValue = 0,
        dynamicObjectIndex = 0,
        dynamicObjectEnabled = true,
        dynamicObjectUpdateEnabled = true,
        animationState = 2,
        animationFrame = 115,
        dynamicObjectOrigin = {0,0,0},
        dynamicObjectReference = {0,0,-1},
      }, simulatedState)) or simulatedState
      simulatedState = select(1, Handlers.runExtension(extension, 2, {
        species = target.species,
        sourceFrame = 1,
        callbackFrame = 1,
        textureFrame = 1,
        selector = 0,
        rangeValue = 0,
        dynamicObjectIndex = 1,
        dynamicObjectEnabled = true,
        dynamicObjectUpdateEnabled = true,
        animationState = 2,
        animationFrame = 0,
        modelScaleY = 1,
      }, simulatedState)) or simulatedState
      local simulatedTexture = simulatedState.textureBySite and simulatedState.textureBySite[site] or nil
      local effect = simulatedState.dynamicObjectsBySite and simulatedState.dynamicObjectsBySite[site]
      local active, badAge, badFrame = 0, 0, 0
      if effect and effect.particles then
        for _, particle in ipairs(effect.particles) do
          if particle.active then
            active = active + 1
            local age = tonumber(particle.age) or -1
            local frame = math.floor(age / 2) + 1
            if age < 0 or age >= 16 then badAge = badAge + 1 end
            if frame < 1 or frame > 8 then badFrame = badFrame + 1 end
          end
        end
      end
      out("DYNAMIC_OBJECT_PARTICLES species=%d site=%s primitiveTexture=%s effect=%s active=%d textureFrames=%d",
        target.species, hex(site), tostring(simulatedTexture), tostring(effect and effect.family),
        active, effect and #(effect.textureSlots or {}) or 0)
      if target.species == 109 then
        if simulatedTexture ~= nil then
          fail("species=%d site=%s still overrides packed primitive texture: %s",
            target.species, hex(site), tostring(simulatedTexture))
        end
        if not effect or effect.family ~= "koffing-gas" then
          fail("species=%d site=%s did not create Koffing gas state", target.species, hex(site))
        elseif active ~= 1 then
          fail("species=%d site=%s active particle count=%d expected 1 from ASM-matching spawn",
            target.species, hex(site), active)
        elseif #(effect.textureSlots or {}) ~= 8 then
          fail("species=%d site=%s texture frame count=%d expected 8",
            target.species, hex(site), #(effect.textureSlots or {}))
        end
        if badAge > 0 or badFrame > 0 then
          fail("species=%d site=%s invalid particle ages=%d invalid texture frames=%d",
            target.species, hex(site), badAge, badFrame)
        end
      end
    end
  end

  for _, site in ipairs(sortedKeys(bySite)) do
    local controlled = bySite[site]
    local baseTextures = {}
    for _, primIndex in ipairs(controlled) do baseTextures[#baseTextures + 1] = prims[primIndex].tex end
    local count = distinct(baseTextures)
    local selected = state.textureBySite and state.textureBySite[site] or nil
    out("SITE species=%d site=%s prims=%d distinctBaseTextures=%d runtimeTexture=%s",
      target.species, hex(site), #controlled, count, tostring(selected))
  end

  out("END species=%d name=%s", target.species, target.name)
end

local root = discoverCacheRoot()
if not root then
  io.stderr:write("[stadium2-texture-test] could not locate stadium2_importer cache\n")
  io.stderr:write("[stadium2-texture-test] run with STADIUM2_CACHE_ROOT=/path/to/stadium2_importer or pass the cache root as argv[1]\n")
  os.exit(2)
end

out("cache=%s", root)
local marker = readFile(root .. "/pack.info") or ""
if not marker:find("format=S2IMP18", 1, true) then
  fail("cache format is stale; expected S2IMP18")
end
for _, target in ipairs(TARGETS) do
  local path = ("%s/normal/%03d.dsm"):format(root, target.species)
  local bytes = readFile(path)
  if not bytes then
    fail("species=%d pack missing: %s", target.species, path)
  else
    local model, err = Pack.parse(bytes)
    if not model then
      fail("species=%d pack parse failed: %s", target.species, tostring(err))
    else
      inspect(target, model)
    end
  end
end

out("RESULT failures=%d warnings=%d", failures, warnings)
os.exit(failures == 0 and 0 or 1)
