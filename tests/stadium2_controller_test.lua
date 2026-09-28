package.path = "./?.lua;./?/init.lua;" .. package.path
local Controller = require("mods.STADIUM2_IMPORTER.lib.stadium_controller")
local checks = 0
local function ok(value, message)
  checks = checks + 1
  assert(value, "FAIL " .. message)
end
local function pad(name, vendor, product)
  return {
    getName = function() return name end,
    getDeviceInfo = function() return vendor, product, 1 end,
    isGamepad = function() return true end,
    getGUID = function() return "same-model-guid" end,
  }
end
local xbox = pad("Xbox Wireless Controller", 0x045e, 0x0b13)
local ps = pad("Wireless Controller", 0x054c, 0x0ce6)
local thor = pad("AYN Thor Controller")
local deck = pad("Valve Software Steam Controller", 0x28de, 0x1205)
local function press(device, button)
  return Controller.observe({joystick=device, phase="pressed", button=button or "a"})
end
local function release(device, button)
  return Controller.observe({joystick=device, phase="released", button=button or "a"})
end
local function axis(device, value, name)
  return Controller.observe({joystick=device, phase="axis", axis=name or "rightx", value=value})
end
local defaults = {padBindings={a="a", b="b", start="start", back="select",
  dpup="up", dpdown="down", dpleft="left", dpright="right"}}
local function glyph(logical, family, key, input, text)
  local actualFamily, actualKey, actualText = Controller.glyph(logical, input or defaults)
  ok(actualFamily==family and actualKey==key and actualText==text,
    logical .. " resolves " .. tostring(family) .. "/" .. tostring(key) .. "/" .. tostring(text))
end

Controller.reset()
ok(Controller.profile()==nil and Controller.activeJoystick()==nil, "no controller before detection")
ok(Controller.update(nil, {xbox,ps})==xbox, "first connected gamepad is initial fallback")
glyph("A", "xbox", "a")
ok(press(ps), "press is meaningful")
ok(Controller.profile()=="playstation", "Sony USB ID identifies generic device name")
glyph("B", "playstation", "b")
ok(press(thor), "Thor input selects handheld")
glyph("A", "ayn_thor", "a")
ok(Controller.thorLayout()=="thor", "default Thor mode reports printed letter")
ok(press(deck), "Deck input selects handheld")
glyph("S", "steamdeck", "start")
ok(Controller.update(nil, {xbox,ps,thor,deck})==deck, "polling does not replace last used pad")

-- Releases, button repeats, and already-held/drifting axes never steal focus.
ok(not release(ps), "release is not meaningful")
ok(not press(thor), "duplicate held-button report is not meaningful")
ok(Controller.activeJoystick()==deck, "button repeat preserves last meaningful device")
ok(not axis(xbox,0.2), "stick drift is not meaningful")
ok(axis(xbox,0.7), "first axis threshold crossing is meaningful")
release(deck); press(deck)
ok(not axis(xbox,0.9) and Controller.activeJoystick()==deck, "held stick does not steal device")
ok(not axis(xbox,0.4), "hysteresis prevents repeated threshold edges")
ok(not axis(xbox,0.7), "held direction remains latched until release zone")
ok(not axis(xbox,0), "axis release is not meaningful")
ok(axis(xbox,-0.8), "new axis excursion changes active device")
release(deck); press(deck)
ok(axis(xbox,0.8), "opposite axis direction is fresh activity")
ok(not axis(deck,0/0), "NaN input is ignored")
ok(not Controller.observe({joystick=deck,phase="released",axis="rightx",value=1}),
  "release tagged with high axis does not steal device")
ok(Controller.activeJoystick()==xbox, "last meaningful joystick wins")

local identical = pad("Xbox Wireless Controller",0x045e,0x0b13)
press(identical)
Controller.update(nil, {xbox,identical})
ok(Controller.activeJoystick()==identical, "identical model GUIDs do not collapse distinct pads")
ok(Controller.update(nil, {xbox})==xbox, "disconnect falls back to remaining device")
ok(Controller.update(nil, {})==nil and Controller.profile()==nil, "last disconnect clears identity")
ok(axis(identical,0.8), "reconnected device axis does not inherit stale hold")

-- LÖVE's real API is getDeviceInfo. Names are a fallback for pre-11.3 or
-- drivers that return zero IDs; broad Android/Steam names do not imply Thor/Deck.
local families = {
  {pad("DualSense Wireless Controller"),"playstation"},
  {pad("PS4 Controller",0,0),"playstation"},
  {pad("PLAYSTATION(R)3 Controller"),"playstation"},
  {pad("Sony Interactive Entertainment Wireless Controller"),"playstation"},
  {pad("Steam Deck"),"steamdeck"}, {pad("Thor"),"ayn_thor"},
  {pad("Android Controller"),"xbox"}, {pad("AYN Odin 2"),"xbox"},
  {pad("Steam Virtual Gamepad",0x28de,0x11ff),"xbox"},
  {pad("Wireless Controller"),"xbox"}, {pad("Unbranded Gamepad"),"xbox"},
}
for _, case in ipairs(families) do
  Controller.reset(); press(case[1])
  ok(Controller.profile()==case[2], "conservative name/VID detection: " .. case[1]:getName())
end
local old = {getName=function() return "DualShock 4" end,isGamepad=function() return true end}
Controller.reset(); Controller.update(nil,{old})
ok(Controller.profile()=="playstation", "older LÖVE without getDeviceInfo works")
old.getDeviceInfo=function() error("driver failure") end
ok(Controller.profile()=="playstation", "failed USB query falls back to name")
local broken = setmetatable({}, {__index=function() error("disconnected handle") end})
ok(pcall(Controller.update,nil,{broken}), "failing device property lookup is safe")
local savedLove = love
love={joystick={getJoysticks=function() return {ps,deck} end}}
Controller.reset(); Controller.update({})
ok(Controller.profile()=="playstation", "connected fallback uses LÖVE enumeration")
love.joystick.getJoysticks=function() error("unavailable") end
ok(Controller.update({})==ps, "enumeration failure preserves known active pad")
ps.isConnected=function() return false end
ok(Controller.update({})==nil, "explicit disconnected result clears active on query failure")
ps.isConnected=nil
love=savedLove

-- Overrides change icon family, never the detected physical controller or map.
Controller.reset(); press(xbox)
ok(Controller.setStyle("ayn_thor")=="ayn_thor", "explicit family override")
glyph("A","ayn_thor","a")
ok(Controller.profile()=="xbox", "override does not replace physical identity")
Controller.setThorLayout("xbox")
glyph("A","ayn_thor","b"); glyph("B","ayn_thor","a")
glyph("A","ayn_thor","y",{padBindings={x="a"}})
glyph("A","ayn_thor","x",{padBindings={y="a"}})
Controller.setThorLayout("thor")
glyph("A","ayn_thor","a")
Controller.setStyle("native")
glyph("A","native","a")
Controller.setStyle("auto")
glyph("A","xbox","a")
ok(not Controller.setStyle("made-up"), "invalid style rejected")
ok(not Controller.setThorLayout("made-up"), "invalid firmware layout rejected")
glyph("A","xbox","a")

-- Actual host mapping is physical -> logical. Aliases retained by Input are
-- resolved deterministically; default wins if it still supplies the action.
glyph("A","xbox","b",{padBindings={a="b",b="a"}})
glyph("B","xbox","a",{padBindings={a="b",b="a"}})
glyph("A","xbox","x",{padBindings={x="a",y="a"}})
glyph("A","xbox","a",{padBindings={a="a",x="a"}})
glyph("S","xbox","y",{padBindings={y="start"}})
glyph("A","xbox",nil,{padBindings={triggerleft="a"}},"LT")
glyph("B","xbox",nil,{padBindings={rightstick="b"}},"R3")
glyph("S","xbox",nil,{padBindings={joy12="start"}},"JOY 12")
glyph("A","xbox",nil,{padBindings={}},"UNBOUND")
glyph("L","xbox","leftshoulder",{padBindings={leftshoulder="a"}})
glyph("R","xbox","rightshoulder",{padBindings={rightshoulder="b"}})
glyph("DPAD","xbox","dpad")
glyph("DPAD","xbox",nil,{padBindings={dpup="a"}},"L STICK")
glyph("CUP","xbox","r_up"); glyph("CRIGHT","xbox","r_right")
glyph("CDOWN","xbox","r_down"); glyph("CLEFT","xbox","r_left")
local family, key = Controller.glyph("unsupported",defaults)
ok(family=="xbox" and key==nil, "unknown logical button has no fabricated mapping")
Controller.reset()
ok(Controller.profile()==nil and Controller.thorLayout()=="thor", "reset restores auto and default mode")
print("stadium2_controller_test: " .. checks .. " checks passed")
