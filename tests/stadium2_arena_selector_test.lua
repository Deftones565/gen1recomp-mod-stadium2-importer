package.path="./?.lua;./?/init.lua;"..package.path

local Selector=require("mods.STADIUM2_IMPORTER.lib.arena_selector")
local checks=0
local function expect(context,index,reason)
  local got,why=Selector.resolve(context)
  checks=checks+1
  if got~=index or (reason and why~=reason) then
    error(("FAIL expected arena %s/%s, got %s/%s"):format(
      tostring(index),tostring(reason),tostring(got),tostring(why)),0)
  end
end

expect({generation=1,mapId="VIOLET_GYM"},nil,"not-gen2")
expect({generation=2,kind="trainer",mapId="VIOLET_GYM"},0,"map:VIOLET_GYM")
expect({generation=2,kind="trainer",mapId="BLACKTHORN_GYM_2F"},7,"map:BLACKTHORN_GYM_2F")
expect({generation=2,kind="trainer",mapId="LANCES_ROOM"},13,"map:LANCES_ROOM")
expect({generation=2,kind="trainer",mapId="SEAFOAM_GYM"},20,"map:SEAFOAM_GYM")
expect({generation=2,kind="trainer",mapId="BATTLE_TOWER_BATTLE_ROOM"},26,
  "map:BATTLE_TOWER_BATTLE_ROOM")
expect({generation=2,kind="trainer",trainerId="RED"},22,"mt-silver")
expect({generation=2,kind="trainer",trainerId="RIVAL2"},29,"trainer:RIVAL2")
expect({generation=2,kind="trainer",mapId="TEAM_ROCKET_BASE_B2F"},8,"team-rocket")
expect({generation=2,kind="trainer",outside=true},28,"outdoor")
expect({generation=2,kind="trainer",outside=false},27,"indoor")
expect({generation=2,kind="trainer"},nil,"unknown:classic")
expect({generation=2,kind="wild",mapId="VIOLET_GYM",outside=false},nil,
  "wild:classic")
expect({generation=2,kind="wild",battleType="fish",terrain="water",outside=true},nil,
  "wild:classic")
expect({generation=2,kind="wild",trainerId="RED",outside=true},nil,
  "wild:classic")
expect({generation=2},nil,"unsupported-kind:classic")

print(("%d checks passed (contextual arena selector)"):format(checks))
