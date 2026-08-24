-- Cooperative battle-UI ownership through Gen1Recomp's public hooks.
--
-- Stadium keeps its authored detached glass UI in both generations and claims
-- only the status region it can own. Before that presentation draws, it probes
-- battle.status_hud_visible with its own link in pass-through mode. Any other
-- UI mod that returns false wins, regardless of hook priority. A short capture
-- scope renders native status data into Stadium's cards without reopening the
-- ordinary HUD pass.
local Ownership = {}

local activeResolver
local modRef
local installed = false
local claims = setmetatable({}, {__mode="k"})
local probing = setmetatable({}, {__mode="k"})
local capturing = setmetatable({}, {__mode="k"})
local unpack = table.unpack or unpack

local function pack(...) return {n=select("#",...),...} end

local function active(state)
  if type(activeResolver)~="function" then return false end
  local ok,value=pcall(activeResolver,state)
  return ok and value==true
end

local function battleFor(state)
  if not state then return nil end
  if state.phase or state.enemy or state.player then return state end
  return state.battle
end

local function activeMod(id)
  if not (modRef and type(modRef.find)=="function") then return nil end
  local ok,handle=pcall(modRef.find,id)
  return ok and handle or nil
end

local function savedOption(state,modId,key)
  local battle=battleFor(state)
  local game=(battle and battle.game) or (state and state.game)
  -- Current engine sessions expose live mod options on the loader, which is
  -- the path Crystal 251 uses. The save bucket is retained for older builds
  -- and headless presentation tests.
  local live=game and game.mods and game.mods.modOptions
  local liveBucket=live and live[modId]
  if liveBucket and liveBucket[key]~=nil then return liveBucket[key] end
  local options=game and game.save and game.save.options
  local bucket=options and options.modOptions and options.modOptions[modId]
  if bucket then return bucket[key] end
  return nil
end

-- gen3_battle_ui predates battle.status_hud_visible and
-- battle.bottom_ui_visible. Battle Art already carries this compatibility
-- adapter; mirror it narrowly so the installed replacement UI does not share
-- pixels with Stadium. A missing option value is that mod's documented
-- default: its revamped battle UI is enabled.
local function legacyGen3Enabled(state)
  if not activeMod("gen3_battle_ui") then return false end
  return savedOption(state,"gen3_battle_ui","revampedBattleUI")~=false
end

local function legacyOwns(surface,state)
  if not legacyGen3Enabled(state) then return false end
  if surface=="status" then return true end
  if surface~="bottom" then return false end
  local battle=battleFor(state)
  if not battle then return false end
  if battle.phase=="messages" or battle.phase=="moveSelect" then return true end
  return battle.phase=="menu" and not battle.safari and not battle.demo
end

function Ownership.bind(mod,resolver)
  modRef=mod
  activeResolver=resolver
  if installed then return Ownership end
  local hooks=mod and mod.hooks
  if not (hooks and type(hooks.wrap)=="function") then return Ownership end
  hooks:wrap("battle.status_hud_visible",function(next,state)
    if not active(state) then
      return next(state)
    end
    if legacyOwns("status",state) then return false end
    if probing[state] or capturing[state] then return next(state) end
    if claims[state] then return false end
    return next(state)
  end,-10000)
  hooks:wrap("battle.bottom_ui_visible",function(next,state)
    if active(state) and legacyOwns("bottom",state) then return false end
    return next(state)
  end,-10000)
  installed=true
  return Ownership
end

-- True only when the complete official hook chain leaves the status region
-- available. The probe flag makes this module's own wrapper transparent.
function Ownership.claimStatus(state)
  claims[state]=nil
  if not active(state) or type(state.statusHUDVisible)~="function" then
    return false
  end
  probing[state]=(probing[state] or 0)+1
  local ok,value=pcall(state.statusHUDVisible,state)
  probing[state]=probing[state]-1
  if probing[state]<=0 then probing[state]=nil end
  local owned=ok and value~=false
  claims[state]=owned or nil
  return owned
end

function Ownership.bottomVisible(state)
  if not active(state) or type(state.bottomUIVisible)~="function" then
    return true
  end
  local ok,value=pcall(state.bottomUIVisible,state)
  return not ok or value~=false
end

function Ownership.withNativeStatus(state,fn)
  assert(type(fn)=="function","native HUD capture callback is required")
  capturing[state]=(capturing[state] or 0)+1
  local result=pack(pcall(fn))
  capturing[state]=capturing[state]-1
  if capturing[state]<=0 then capturing[state]=nil end
  if not result[1] then error(result[2],0) end
  return unpack(result,2,result.n)
end

function Ownership.release(state)
  if state then
    claims[state],probing[state],capturing[state]=nil,nil,nil
  end
end

function Ownership.ownsStatus(state)
  return claims[state]==true
end

function Ownership.resetForTests()
  modRef=nil
  activeResolver=nil
  installed=false
  claims=setmetatable({}, {__mode="k"})
  probing=setmetatable({}, {__mode="k"})
  capturing=setmetatable({}, {__mode="k"})
end

return Ownership
