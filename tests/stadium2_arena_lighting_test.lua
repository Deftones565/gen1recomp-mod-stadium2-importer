package.path = "./?.lua;./?/init.lua;" .. package.path

local ArenaLighting = require("mods.STADIUM2_IMPORTER.lib.arena_lighting")
local Renderer = require("mods.STADIUM2_IMPORTER.lib.renderer")

local failures = 0
local function ok(value, name)
  if value then print("PASS " .. name)
  else failures = failures + 1; print("FAIL " .. name) end
end

local model = {prims = {
  {vertexSemantics="color", lighting=false, nverts=12},
  {vertexSemantics="color", lighting=false, pos={0,0,0, 1,0,0, 0,1,0}},
  {vertexSemantics="normal", lighting=true, nverts=6},
}}
local audit = ArenaLighting.analyse(model)
ok(audit.mode == "hybrid-prelit" and audit.prelitPrimitives == 2
  and audit.directionalPrimitives == 1,
  "arena audit separates ROM-prelit and normal-lit submissions")
ok(audit.prelitVertices == 15 and audit.directionalVertices == 6,
  "arena audit counts vertices in both lighting paths")

local environment = audit.environment
local total = environment.ambient[1] + environment.diffuse[1]
ok(environment.modernLighting == true and math.abs(total - 1) < 0.000001,
  "shared modern arena light preserves a neutral full-intensity range")
ok(environment.light[2] < 0,
  "arena ray direction agrees with the battle shadow convention")
local park = ArenaLighting.environment(28)
ok(park.backdrop == true and park.outdoor == true and #park.bands == 5,
  "Academy park supplies an edge clear behind its ROM cyclorama")
ok(ArenaLighting.environment(27).backdrop ~= true,
  "enclosed arena does not inherit the classic battle sky")

local colorState = Renderer.primitiveRenderState({stageIndex=0}, model.prims[1], {})
local normalState = Renderer.primitiveRenderState({stageIndex=0}, model.prims[3], {})
ok(colorState.lightingEnabled == false and normalState.lightingEnabled == true,
  "baked field RGB is not lit twice while normals remain dynamically lit")

ok(Renderer.SHADER_SOURCE:find("modernLightingEnabled", 1, true)
  and Renderer.SHADER_SOURCE:find("ambient+diffuse*modernDiffuse", 1, true),
  "desktop arena shader uses the supplied modern light profile")
ok(Renderer.MOBILE_SHADER_SOURCE:find("modernLightingEnabled", 1, true)
  and Renderer.MOBILE_SHADER_SOURCE:find("ambient+diffuse*modernDiffuse", 1, true),
  "mobile arena shader uses the supplied modern light profile")

if failures > 0 then os.exit(1) end
