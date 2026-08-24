package.path = "./?.lua;./?/init.lua;" .. package.path

package.loaded["mods.STADIUM2_IMPORTER.lib.battle_ui_ownership"] = nil
local Ownership = require("mods.STADIUM2_IMPORTER.lib.battle_ui_ownership")

local checks=0
local function ok(value,message)
  checks=checks+1
  if not value then error("FAIL "..message,0) end
end

local stadiumHook,bottomHook
local gen3Installed=false
local mod={find=function(id) return id=="gen3_battle_ui" and gen3Installed or nil end,
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

state.active=false
ok(not Ownership.claimStatus(state),"inactive battles never claim UI space")
ok(state:statusHUDVisible(),"inactive Stadium presentation leaves native UI untouched")

print(("%d checks passed (Stadium 2 cooperative UI ownership)"):format(checks))
