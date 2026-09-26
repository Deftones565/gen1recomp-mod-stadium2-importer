package.path="./?.lua;./?/init.lua;"..package.path
-- Scene-kit environments: each builds, is selected when forced, and gives
-- both battle slots (0, +/-24) a surface near the battlers' feet.
local E=require("mods.STADIUM2_IMPORTER.lib.battle_environment")
local checks=0
local function ok(v,m) checks=checks+1 if not v then error("FAIL "..m,0) end end
local IDS={'mountain','ice_cave','cave_water','indoor_water','interior','industrial','ruins','ship','gym','league'}
for _,id in ipairs(IDS) do
  local sel=E.select({kind='wild'},'classic',false,nil,id)
  ok(sel.mode=='environment' and sel.id==id,id.." is selectable")
  local rows=sel.scene.vertices()
  ok(#rows%3==0 and #rows/3>1000,id.." builds scenery")
  for _,z in ipairs({24,-24}) do
    -- Highest upward-facing surface under the slot (below head height).
    local top=-math.huge
    for i=1,#rows,3 do
      local a,b,c=rows[i],rows[i+1],rows[i+2]
      if a[5]>.7 then
        local det=(b[3]-c[3])*(a[1]-c[1])+(c[1]-b[1])*(a[3]-c[3])
        if math.abs(det)>1e-9 then
          local u=((b[3]-c[3])*(1.3-c[1])+(c[1]-b[1])*(z-c[3]))/det
          local v=((c[3]-a[3])*(1.3-c[1])+(a[1]-c[1])*(z-c[3]))/det
          if u>=0 and v>=0 and u+v<=1 then
            local y=u*a[2]+v*b[2]+(1-u-v)*c[2]
            if y<3 then top=math.max(top,y) end
          end
        end
      end
    end
    ok(top>-1.5 and top<1.5,id.." has footing at z="..z.." (top "..tostring(top)..")")
  end
end
print(("%d checks passed (scene-kit environments)"):format(checks))
