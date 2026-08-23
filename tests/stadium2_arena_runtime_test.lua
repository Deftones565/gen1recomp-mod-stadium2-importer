package.path = "./?.lua;./?/init.lua;" .. package.path

local Discovery = require("mods.STADIUM2_IMPORTER.lib.discovery")
local Arena = require("mods.STADIUM2_IMPORTER.lib.arena_runtime")

local checks = 0
local function ok(value, message)
  checks = checks + 1
  if not value then error("FAIL " .. message, 0) end
end

local path = os.getenv("STADIUM2_ROM") or arg[1]
if not path or path == "" then
  io.stderr:write("usage: STADIUM2_ROM=/path/to/stadium2.z64 luajit "
    .."mods/STADIUM2_IMPORTER/tests/stadium2_arena_runtime_test.lua\n")
  os.exit(2)
end

Discovery.bind({read=function(_, name)
  if name ~= "baseroms/stadium2.z64" then return nil end
  local file = assert(io.open(path, "rb"))
  local bytes = assert(file:read("*a"))
  file:close()
  return bytes
end})

local released = 0
local importer = {newRendererFromModel=function(model, options)
  ok(model.staticPose == true and #model.prims > 0,
    "runtime builds a static field model")
  ok(options.textureFilter == "nearest",
    "runtime preserves Stadium field texture sampling")
  return {model=model,release=function() released=released+1 end}
end}

Arena.resetForTests()
local originalRandom = math.random
math.random = function() error("battle RNG/random API was consumed", 0) end
local index = Arena.randomIndex({encounter="fixture"})
math.random = originalRandom
ok(index >= 0 and index < Arena.COUNT and index == math.floor(index),
  "presentation-only arena selection returns a valid field without math.random")

local runtime = assert(Arena.load(index, importer))
ok(runtime.index == index and runtime.renderer.model == runtime.model,
  "selected arena is retained as one encounter-owned runtime")
ok(runtime.scale == .05 and runtime.groundY == 0,
  "runtime carries Stadium ROM-to-world placement")
for _, primitive in ipairs(runtime.model.prims) do
  for _, vertexIndex in ipairs(primitive.idx or {}) do
    ok(vertexIndex >= 1, "runtime converts field vertex indices to renderer convention")
  end
end
runtime:release()
ok(released == 1 and runtime.model == nil and runtime.renderer == nil,
  "encounter release disposes its arena renderer and model")

print(("%d checks passed (Stadium 2 beta arena runtime)"):format(checks))
