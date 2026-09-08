package.path="./?.lua;./?/init.lua;"..package.path

local checks=0
local function ok(value,message)
  checks=checks+1
  if not value then error("FAIL "..message,0) end
end
local function read(path)
  local handle=assert(io.open(path,"rb"))
  local value=handle:read("*a")
  handle:close()
  return value
end

local driver=read("mods/STADIUM2_IMPORTER/tests/drivers/gen2_context_arena_visual.lua")
local runner=read("mods/STADIUM2_IMPORTER/tests/run_context_arena_visuals.sh")

for _,case in ipairs({"wild","fishing","outdoor_trainer","indoor_trainer","gym"}) do
  ok(driver:find(case.."={",1,true)~=nil,
    case.." encounter has a visual scenario")
  ok(runner:find("run_case "..case,1,true)~=nil,
    case.." scenario is included in the visual suite")
end
ok(driver:find("world:startBattle",1,true)~=nil,
  "visual suite starts a real Gen 2 battle")
ok(driver:find("battleOptions.wild=enemy",1,true)~=nil
    and driver:find("battleOptions.trainer=",1,true)~=nil,
  "visual suite exercises both wild and trainer engine paths")
ok(driver:find("status.arenaIndex==case.arena",1,true)~=nil
    and driver:find("status.arenaReason==case.reason",1,true)~=nil,
  "screenshots are gated by the live arena index and resolver reason")
ok(driver:find("wild encounter entered arena scene mode",1,true)~=nil,
  "wild visual cases assert that arena mode remains disabled")
ok(driver:find("U.shot(game,fullPath)",1,true)~=nil,
  "passing encounters capture the complete engine window")
ok(driver:find("saveSceneCanvas(status.shot,path)",1,true)~=nil,
  "passing encounters capture a clean Stadium scene canvas")
ok(driver:find("stadium2_beta_arena_test=true",1,true)~=nil,
  "driver explicitly enables contextual arenas in its isolated process")

print(("%d checks passed (context arena visual contract)"):format(checks))
