package.path="./?.lua;./?/init.lua;"..package.path

local checks=0
local function ok(value,message)
  checks=checks+1
  if not value then error("FAIL "..message,0) end
end

-- A minimal host BattleState is enough to prove the adapter's boundary: only
-- presentation methods may be wrapped. Battle mechanics must remain exactly
-- the same function objects after install().
local Host={}
Host.isWideBattleLayout=function() return true end
Host.draw=function() return "draw" end
Host.drawPicsLayer=function() return "pics" end
Host.drawHUDs=function() return "hud" end
Host.drawTextArea=function() return "text" end
Host.drawAnimLayer=function() return "anim" end
Host.submit=function() return "submit" end
Host.update=function() return "update" end
Host.performMove=function() return "move" end
Host.advanceQueue=function() return "queue" end
Host.throwBall=function() return "ball" end
Host.runRoll=function() return "run" end
local mechanics={
  submit=Host.submit,update=Host.update,performMove=Host.performMove,
  advanceQueue=Host.advanceQueue,throwBall=Host.throwBall,runRoll=Host.runRoll,
}
package.preload["src.battle.BattleState"]=function() return Host end
package.loaded["src.battle.BattleState"]=nil
package.loaded["mods.STADIUM2_IMPORTER.lib.gen1_battle"]=nil

local composeWrap
local mod={hooks={wrap=function(_,name,fn) if name=="render.compose" then composeWrap=fn end end}}
local Battle=require("mods.STADIUM2_IMPORTER.lib.gen1_battle")
ok(Battle.bind(mod)==Battle,"Gen 1 adapter binds")
ok(Battle.configureGame({})==151,"ordinary Gen 1 keeps the 151-species boundary")
ok(Battle.configureGame({data={pokemon={extra={dex=251}}}})==251,
  "expanded Gen 1 data may request Stadium models through 251")
ok(Battle.install(),"Gen 1 presentation hooks install")
ok(type(composeWrap)=="function","Gen 1 installs a renderer-only composition seam")

ok(Host.draw~=nil and Host.draw~=function() end,"host draw path remains present")
ok(Host.drawPicsLayer~=nil and Host.drawHUDs~=nil and Host.drawAnimLayer~=nil,
  "presentation seams remain callable")
for name,fn in pairs(mechanics) do
  ok(Host[name]==fn,name.." battle mechanic is untouched")
end

ok(Battle.Actor~=nil and Battle.Scene~=nil,"Gen 1 uses the shared Actor/Scene presentation")
ok(type(Battle._animationProjection)=="function","Gen 1 owns native effect projection")
local status=Battle.status()
ok(status.generation==1,"Gen 1 status identifies its generation")

print(("%d checks passed (Stadium 2 Gen 1 presentation boundary)"):format(checks))
