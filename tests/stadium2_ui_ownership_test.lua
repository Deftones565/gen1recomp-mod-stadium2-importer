package.path = "./?.lua;./?/init.lua;" .. package.path

package.loaded["mods.STADIUM2_IMPORTER.lib.battle_ui_ownership"] = nil
local Ownership = require("mods.STADIUM2_IMPORTER.lib.battle_ui_ownership")

local checks=0
local function ok(value,message)
  checks=checks+1
  if not value then error("FAIL "..message,0) end
end

local stadiumHook,bottomHook
local gen3Installed,modernInstalled=false,false
local gen1ModernInstalled=false
local stadiumHud=true
local mod={find=function(id)
    if id=="gen3_battle_ui" then return gen3Installed or nil end
    if id=="modern_ui_suite" then return modernInstalled or nil end
    if id=="gen1_modern_ui" then return gen1ModernInstalled or nil end
  end,
  options={get=function(_,key)
    if key=="stadium2_battle_hud" then return stadiumHud end
  end},
  hooks={wrap=function(_,name,callback,priority)
  ok(name=="battle.status_hud_visible" or name=="battle.bottom_ui_visible",
    "ownership registers through the official battle-UI hooks")
  ok(priority<0,"Stadium status ownership yields behind ordinary UI providers")
  if name=="battle.status_hud_visible" then stadiumHook=callback
  else bottomHook=callback end
end}}
local state={active=true,externalOwns=false,bottom=true,phase="resolving",
  game={save={options={modOptions={}}}}}

-- Simulate an external wrapper both before and after Stadium in the hook
-- chain. Returning false after next is the difficult case: the complete probe
-- must still see it and yield.
function state:statusHUDVisible()
  if self.externalOwns=="before" then return false end
  local value=stadiumHook(function() return true end,self)
  if self.externalOwns=="after" then return false end
  return value~=false
end
function state:bottomUIVisible()
  return bottomHook(function() return self.bottom end,self)~=false
end

Ownership.bind(mod,function(candidate) return candidate.active end)
ok(Ownership.claimStatus(state),"Stadium claims an unowned status region")
ok(Ownership.ownsStatus(state),"successful official claim is retained for the frame")
ok(state:statusHUDVisible()==false,
  "claimed Stadium cards suppress only the native status HUD")

local captured=Ownership.withNativeStatus(state,function()
  return state:statusHUDVisible()
end)
ok(captured==true,"narrow native capture bypasses only Stadium's own claim")

state.externalOwns="before"
ok(not Ownership.claimStatus(state) and not Ownership.ownsStatus(state),
  "Stadium yields when a higher UI provider consumes the official hook")
state.externalOwns="after"
ok(not Ownership.claimStatus(state),
  "Stadium yields when another provider returns false after calling next")
state.externalOwns=false
state.bottom=false
ok(not Ownership.bottomVisible(state),
  "bottom panel styling obeys the independent official bottom-UI hook")

-- The installed Gen 3 UI predates these hooks. Match Battle Art's narrow
-- compatibility adapter until that UI migrates to the official ownership API.
state.bottom=true
state.phase="menu"
gen3Installed={}
ok(state:statusHUDVisible()==false,
  "legacy Gen 3 replacement suppresses Stadium's status capture")
ok(not Ownership.bottomVisible(state),
  "legacy Gen 3 replacement suppresses the Stadium command panel it redraws")
state.game.save.options.modOptions.gen3_battle_ui={revampedBattleUI=false}
ok(state:bottomUIVisible(),
  "disabled legacy replacement leaves the Stadium command panel available")
state.game.mods={modOptions={gen3_battle_ui={revampedBattleUI=true}}}
ok(not state:bottomUIVisible(),
  "Crystal-style live loader options take precedence over the saved fallback")
state.game.mods=nil
gen3Installed=false

-- Modern UI Suite keeps the native HUD as its source and enhances it. Stadium
-- must keep its placement and expose the native source during capture.
modernInstalled={}
state.game.mods={modOptions={modern_ui_suite={
  ["battle_hud.enabled"]=true,
}}}
state.externalOwns=false
state.bottom=true
ok(Ownership.claimStatus(state),
  "Modern UI Suite enhancements retain Stadium's detached status placement")
ok(Ownership.withNativeStatus(state,function() return state:statusHUDVisible() end),
  "Modern UI Suite can enhance the native HUD inside Stadium's capture")
ok(not state:statusHUDVisible(),
  "captured status HUD does not draw again at native screen coordinates")
ok(Ownership.bottomVisible(state),
  "Modern Battle HUD alone does not consume the independent bottom UI")
state.game.mods.modOptions.modern_ui_suite["battle_hud.enabled"]=false
ok(Ownership.claimStatus(state),
  "disabled Modern Battle HUD also retains Stadium status cards")
local modernOwns=false
setmetatable(state,{__index={_typedMoveColorsTextPatch={owns=function(candidate)
  return candidate==state and modernOwns
end}}})
modernOwns=true
ok(not Ownership.bottomVisible(state),
  "Suite command replacement suppresses Stadium glass even without a visibility hook")
ok(state:bottomUIVisible(),
  "glass handoff does not suppress Suite or native source rendering")
modernOwns=false
ok(Ownership.bottomVisible(state),
  "Suite non-owning phases and disabled controls restore Stadium glass")
modernOwns=true
modernInstalled=false
ok(Ownership.bottomVisible(state),
  "a stale Suite class patch cannot suppress glass after Suite is disabled")
setmetatable(state,nil)

stadiumHud=false
ok(not Ownership.claimStatus(state),
  "manual Stadium HUD OFF relinquishes detached status cards")
ok(state:statusHUDVisible(),
  "manual Stadium HUD OFF leaves the engine or another provider visible")
ok(not Ownership.hudEnabled() and Ownership.bottomVisible(state),
  "manual Stadium HUD OFF removes decoration but preserves native prompts")
stadiumHud=true

gen1ModernInstalled={}
state.game.mods.modOptions.gen1_modern_ui={battleUiWip=true,battle3dBypass=true}
state.wideLayout=function() return true end
ok(Ownership.claimStatus(state),"Gen1 Modern UI default 3D bypass keeps Stadium HUD")
state.game.mods.modOptions.gen1_modern_ui.battle3dBypass=false
ok(not Ownership.claimStatus(state) and not Ownership.bottomVisible(state),
  "explicit Gen1 Modern UI wide replacement consumes both Stadium surfaces")
state.wideLayout=function() return false end
ok(Ownership.claimStatus(state) and Ownership.bottomVisible(state),
  "Gen1 Modern UI leaves non-wide sources available")
state.wideLayout=nil
gen1ModernInstalled=false

local gen3Owns=false
gen3Installed={exports={uiOwnership={ownsBattleUi=function() return gen3Owns end}}}
ok(Ownership.claimStatus(state) and Ownership.bottomVisible(state),
  "live Gen3 provider deferral overrides legacy enabled defaults")
gen3Owns=true
ok(not Ownership.claimStatus(state) and not Ownership.bottomVisible(state),
  "live Gen3 ownership suppresses both surfaces in every claimed phase")
gen3Installed.exports.uiOwnership.ownsBattleUi=function() error("provider failure") end
ok(Ownership.claimStatus(state),"failed live Gen3 contract does not invent ownership")
gen3Installed=false

state.active=false
ok(not Ownership.claimStatus(state),"inactive battles never claim UI space")
ok(state:statusHUDVisible(),"inactive Stadium presentation leaves native UI untouched")

print(("%d checks passed (Stadium 2 cooperative UI ownership)"):format(checks))
