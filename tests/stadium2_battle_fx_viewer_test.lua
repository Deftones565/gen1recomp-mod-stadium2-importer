package.path="./?.lua;./?/init.lua;"..package.path
local Preview=require("mods.STADIUM2_IMPORTER.tests.stadium2_koffing_croconaw_visual.battle_fx")
local path=os.getenv("STADIUM2_ROM") or "mods/STADIUM2_IMPORTER/baseroms/stadium2.z64"
local file=io.open(path,"rb")
if not file then
  assert(os.getenv("STADIUM2_REQUIRE_ROM")~="1","required ROM unavailable")
  print("SKIP: battle FX viewer ROM integration (ROM unavailable)");return
end
local rom=file:read("*a");file:close()
local checks=0
local function check(value,message)
  checks=checks+1;assert(value,message)
end
local loads,draws,releases,models=0,0,0,0
local preview=Preview.new({rom=rom,releaseModel=function()models=models+1 end,
  importer={newRendererFromModel=function(model)
    loads=loads+1
    check(#model.prims>0,"ROM shape has decoded geometry")
    return {drawScene=function(_,pass,matrix)
      draws=draws+1
      check(#matrix==16,"player supplies a complete transform")
      return true
    end,release=function()releases=releases+1 end}
  end},
})
local context={world={groundY=0,actorSlots={enemy={x=10,y=0,z=0},player={x=-10,y=0,z=0}}}}
check(preview:start(7,"enemy",false,context)~=nil,"primary move starts")
local snapshot=preview.player:snapshot()
check(#snapshot.effects==1 and not snapshot.effects[1].alternate,
  "preview selects only the primary channel")
check(snapshot.effects[1].sourceSide=="enemy","source captured at trigger")
preview:update(1/60);check(preview.frame==0,"fractional tick retained")
preview:update(1/60);check(preview.frame==1,"30 Hz tick advances")
for _=1,11 do preview:step() end
snapshot=preview.player:snapshot()
check(snapshot.frame==12 and #snapshot.particles>0,"Fire Punch has persistent particles at frame 12")
local first=snapshot.particles[1]
local cleared
preview:drawBackground({environment={bands={{1,1,1}}},graphics={clear=function(r,g,b)
  cleared={r,g,b}
end}})
check(cleared and cleared[1]<1 and cleared[1]==cleared[2],
  "mode2 ROM color reaches the viewer background renderer")
local result=preview:draw(context)
check(result.drawn>0 and draws==result.drawn*2,"ROM shapes reach both render passes")
local count=loads
preview:draw(context)
local after=preview.player:snapshot()
check(after.frame==snapshot.frame and after.particles[1].id==first.id
  and after.particles[1].age==first.age,"drawing cannot advance or recreate particles")
check(loads==count,"repeated draws reuse shape renderers")
for _,row in ipairs(preview.diagnostics) do
  check(row.code~="unsupported-lifetime",
    "native byte-age expiry is not reported as an unresolved lifetime")
end
-- Determinism compares identical source/scene inputs. Source yaw now rotates
-- spawn offsets, so opposite battle sides intentionally have different poses.
check(preview:start(7,"enemy",false,context)~=nil,"replay starts")
check(preview.player:backgroundColor({1,1,1})[1]==1,"replay resets native background color")
check(releases==count and models==count,"replay releases renderers and models")
for _=1,12 do preview:step() end
local replay=preview.player:snapshot().particles[1]
check(replay.age==first.age and replay.position[1]==first.position[1]
  and replay.velocity[1]==first.velocity[1],"replay has deterministic presentation state")
check(preview:start(7,"player",true)~=nil,"alternate route starts independently")
local alternate=preview.player:snapshot().effects[1]
check(alternate.alternate and alternate.sourceSide=="player","alternate route and source reach runtime")
check(preview:finish() and preview.player.runtime.lifecycle.finishedEffects[preview.effectId],
  "viewer can signal native effect completion for gated fades")
preview:release();preview:update(1);preview:step()
check(not preview.active and preview.player==nil,"stop releases persistent state")
local effect,err=preview:start(999,"player",false)
check(effect==nil and err~=nil and not preview.active,"invalid move fails safely")
print(("%d checks passed (Stadium 2 battle FX viewer)"):format(checks))
