-- Cooperative battle-UI ownership through Gen1Recomp's public hooks.
--
-- Stadium keeps its authored detached glass UI in both generations and claims
-- only the status region it can own. Before that presentation draws, it probes
-- battle.status_hud_visible with its own link in pass-through mode. Any other
-- UI mod that returns false wins, regardless of hook priority. A short capture
-- scope renders native status data into Stadium's cards without reopening the
-- ordinary HUD pass.
local Ownership = {}
local Runtime = require("src.mods.Runtime")

function Ownership.drawStatusOverlay(state)
  return Runtime.call("battle.ui.status_overlay.v1",function() end,state)
end

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

local function stadiumHudEnabled()
  local options=modRef and modRef.options
  if not (options and type(options.get)=="function") then return true end
  local ok,value=pcall(options.get,options,"stadium2_battle_hud")
  return not ok or value~=false
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

Ownership.hudEnabled=stadiumHudEnabled

-- Suite's Gen 2 Battle Info HUD adds only the level beside a status tag.
-- Its general battle.overlay pass cannot enter our HUD-only capture. Render
-- these two semantic labels here rather than replaying battle.overlay (which
-- also contains animated effects and replacement move controls).
function Ownership.drawLegacyGen2Status(state)
  local handle=activeMod("modern_ui_suite")
  if not handle or type(state.activeMon)~="function"
      or type(state.statusTag)~="function" then return end
  local api=handle.exports
  local enabled=savedOption(state,"modern_ui_suite","battle_hud.enabled")~=false
  if api and type(api.isEnabled)=="function" then
    local ok,value=pcall(api.isEnabled,"battle_info_hud")
    if ok then enabled=value==true end
  end
  if not enabled then return end
  local Chrome=require("src.ui.gen2.Chrome")
  local Font=require("src.render.Font")
  local previous=Font.useBattleExtra(true)
  local ok,err=pcall(function()
    for _,side in ipairs({"enemy","player"}) do
      local mon=state:activeMon(side)
      local visible=side=="enemy" and state.showEnemyHud or side=="player" and state.showPlayerHud
      if mon and visible and state:statusTag(mon,side)
          and (type(state.hudCleared)~="function" or not state:hudCleared(side)) then
        local level=side=="player" and state.shownLevel or nil
        local text="<LV>"..tostring(level or mon.level or 1)
        local y=side=="enemy" and 8 or 64
        local palette,glyph,finish=Chrome.paletteGlyphs({
          {255,255,255},{170,170,170},{85,85,85},{0,0,0}},false,true)
        -- Keep the addition inside the detached card; the Suite's enemy
        -- x=80 extends beyond the native HUD crop and loses its digits.
        local labelX=side=="enemy" and 16 or 80
        if palette then
          local x=labelX
          for _,code in ipairs(Font.encode(text)) do
            glyph(code,x,y);x=x+Font.advanceOf(code)
          end
          finish()
        else
          love.graphics.setColor(0,0,0,1)
          Font.draw(text,labelX,y)
        end
      end
    end
  end)
  Font.useBattleExtra(previous)
  if not ok then error(err,0) end
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

-- Suite 0.1.23's Gen 1 move/command renderer wraps drawTextArea directly;
-- unlike its Gen 2 renderer it does not claim bottom_ui_visible. Reuse the
-- exact live predicate from that wrapper (inherited from BattleState), which
-- includes phase, options, layout and whether the detached surface fits.
-- Merely having the Suite installed is not a claim on every textbox.
local function modernSuiteOwnsBottom(state)
  if not activeMod("modern_ui_suite") then return false end
  local battle=battleFor(state)
  local patch=battle and battle._typedMoveColorsTextPatch
  if type(patch)~="table" or type(patch.owns)~="function" then return false end
  local ok,value=pcall(patch.owns,battle)
  return ok and value==true
end

local function legacyOwns(surface,state)
  -- Gen1 Modern UI's optional presenter is restricted to explicitly wide
  -- sources and normally bypasses native 3D battles. Match those live guards
  -- only when the user explicitly allows it to replace our presentation.
  if activeMod("gen1_modern_ui")
      and savedOption(state,"gen1_modern_ui","battleUiWip")==true
      and savedOption(state,"gen1_modern_ui","battle3dBypass")==false
      and savedOption(state,"gen1_modern_ui","hideOriginalUi")~=false then
    local battle=battleFor(state)
    if battle then
      local wide
      for _,key in ipairs({"wideLayout","isWideBattleLayout"}) do
        local value=battle[key]
        if type(value)=="function" then
          local ok,result=pcall(value,battle)
          value=ok and result or nil
        end
        if type(value)=="boolean" then wide=value;break end
      end
      if wide==nil then
        local mode=tostring(battle.battleLayout or battle.layoutMode or battle.layout or ""):lower()
        wide=mode=="wide" or mode=="widescreen"
      end
      if wide then return surface=="status" or surface=="bottom" end
    end
  end
  local gen3=activeMod("gen3_battle_ui")
  local contract=type(gen3)=="table" and gen3.exports and gen3.exports.uiOwnership
  if contract and type(contract.ownsBattleUi)=="function" then
    local ok,value=pcall(contract.ownsBattleUi,state)
    if ok then return value==true end
    -- A broken provider must not turn an option default into an ownership
    -- claim. Its official visibility hooks can still make the decision.
    return false
  end
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
  -- Native HUD enhancements belong inside our capture. Only a provider that
  -- actually claims the status surface through the hook should displace it.
  if not stadiumHudEnabled() then
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
  if not active(state) then return true end
  -- Native prompts stay usable even when Stadium's decoration is disabled.
  if modernSuiteOwnsBottom(state) then return false end
  if type(state.bottomUIVisible)~="function" then
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

function Ownership.beginNativeStatus(state)
  capturing[state]=(capturing[state] or 0)+1
  local closed=false
  return function()
    if closed then return end
    closed=true
    capturing[state]=(capturing[state] or 1)-1
    if capturing[state]<=0 then capturing[state]=nil end
  end
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
