package.path="./?.lua;./?/init.lua;"..package.path
local Ownership=require("mods.STADIUM2_IMPORTER.lib.battle_ui_ownership")
local enabled=true
Ownership.bind({find=function(id)
  if id=="modern_ui_suite" then return {exports={isEnabled=function(component)
    assert(component=="battle_info_hud");return enabled
  end}} end
end},function() return true end)
local fontMode=false
local labels={}
local fail=false
package.loaded["src.render.Font"]={
  useBattleExtra=function(value) local old=fontMode; fontMode=value;return old end,
  encode=function(text) return {text} end,advanceOf=function() return 24 end,
}
package.loaded["src.ui.gen2.Chrome"]={paletteGlyphs=function()
  return true,function(text,x,y)
    if fail then error("glyph error") end
    labels[#labels+1]={text=text,x=x,y=y}
  end,function() end
end}
local state={showEnemyHud=true,showPlayerHud=true,shownLevel=21,
  activeMon=function() return {level=100} end,
  statusTag=function() return "PSN" end,hudCleared=function() return false end}
Ownership.drawLegacyGen2Status(state)
assert(#labels==2 and labels[1].x==16 and labels[2].x==80)
assert(labels[1].text=="<LV>100" and labels[2].text=="<LV>21")
assert(fontMode==false)
enabled=false
Ownership.drawLegacyGen2Status(state)
assert(#labels==2,"disabled Suite still supplied status labels")
enabled=true;state.showEnemyHud=false;state.showPlayerHud=false
Ownership.drawLegacyGen2Status(state)
assert(#labels==2,"hidden battler received a status label")
state.showEnemyHud=true;fail=true
assert(not pcall(Ownership.drawLegacyGen2Status,state))
assert(fontMode==false,"glyph failure leaked font mode")
print("Gen 2 Suite labels: placement, shown level, toggles, hidden HUD and failure cleanup passed")
