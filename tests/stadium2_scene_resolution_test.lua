package.path="./?.lua;./?/init.lua;"..package.path
-- 3D RESOLUTION: fixed choices, AUTO full resolution on desktop, and AUTO's
-- handheld pixel budget.
local os_name="Linux"
love={system={getOS=function() return os_name end},graphics={}}
local AA=require("mods.STADIUM2_IMPORTER.lib.battle_aa")
local setting="auto"
AA.bind({options={get=function(_,key)
  if key=="stadium2_scene_resolution" then return setting end
  return 0
end}})
local checks=0
local function ok(v,m) checks=checks+1 if not v then error("FAIL "..m,0) end end
ok(AA.renderScale(2400,1080)==1,"AUTO keeps desktop at full resolution")
os_name="Android"
local s=AA.renderScale(2400,1080)
ok(math.abs(2400*s*1080*s-AA.HANDHELD_PIXEL_BUDGET)<1,"AUTO caps a large phone at the pixel budget")
ok(AA.renderScale(1280,720)==1,"AUTO leaves a small handheld screen at full resolution")
local w,h=AA.expand(2400,1080)
ok(w<2400 and h<1080 and math.abs(w/h-2400/1080)<.01,"handheld render size shrinks with the aspect ratio kept")
setting="50"
ok(AA.renderScale(2400,1080)==.5,"fixed 50%")
os_name="Linux";setting="75"
ok(AA.renderScale(2400,1080)==.75,"fixed 75% applies on desktop too")
setting="100"
ok(AA.renderScale(2400,1080)==1,"100% is full resolution")
print(("%d checks passed (Stadium 2 3D resolution)"):format(checks))
