-- Controller identity and button-label resolution for the Stadium UI.
--
-- This module deliberately observes the host's already-normalized events.  It
-- never sends input or patches the host input object. Controller artwork is a
-- requested port extension, not native Stadium 2 behavior.
local Controller = {}

local VALID_STYLES = {
  auto = true, native = true, xbox = true, playstation = true,
  ayn_thor = true, steamdeck = true,
}

local state = {
  active = nil,
  style = "auto",
  thorLayout = "thor",
  axes = setmetatable({}, { __mode = "k" }),
  buttons = setmetatable({}, { __mode = "k" }),
}

local AXIS_ON = 0.6
local AXIS_OFF = 0.3

local function read(device, method, field)
  if type(device) ~= "table" and type(device) ~= "userdata" then return nil end
  local ok, value, extra = pcall(function()
    local fn = device[method]
    if type(fn) == "function" then return fn(device) end
    return field and device[field]
  end)
  if ok then return value, extra end
end

local function number(value)
  if type(value) == "number" then return value end
  if type(value) ~= "string" then return nil end
  local hex = value:match("^0[xX]([%da-fA-F]+)$")
  if hex then return tonumber(hex, 16) end
  return tonumber(value)
end

local function lower(value)
  return type(value) == "string" and value:lower() or ""
end

local function identity(device)
  -- LÖVE 11.3+, older versions and failing driver calls fall back to names.
  -- https://www.love2d.org/wiki/Joystick:getDeviceInfo
  local vendor, product = read(device, "getDeviceInfo")
  return {
    name = read(device, "getName", "name"),
    vendor = number(vendor),
    product = number(product),
  }
end

local function isGamepad(device)
  local value = read(device, "isGamepad", "gamepad")
  return value == true
end

local function profileFor(device)
  if not device then return nil end
  local d = identity(device)
  local name = lower(d.name)

  -- SDL's primary source identifies the built-in Deck as Valve 28de:1205.
  -- The exact name is also safe when LÖVE does not expose VID/PID.
  if (d.vendor == 0x28de and d.product == 0x1205)
      or name:find("steam deck", 1, true) then
    return "steamdeck"
  end

  if name:find("ayn thor", 1, true) or name == "thor" then
    return "ayn_thor"
  end

  -- VID definitions: libsdl-org/SDL, src/joystick/usb_ids.h. In particular
  -- don't treat the generic name "Wireless Controller" as proof of Sony.
  if d.vendor == 0x054c
      or name:find("playstation", 1, true)
      or name:find("dualshock", 1, true)
      or name:find("dualsense", 1, true)
      or (name:find("sony", 1, true) and name:find("controller", 1, true))
      or name:find("ps3 controller", 1, true)
      or name:find("ps4 controller", 1, true)
      or name:find("ps5 controller", 1, true) then
    return "playstation"
  end
  if d.vendor == 0x045e or name:find("xbox", 1, true) or name:find("xinput", 1, true) then
    return "xbox"
  end

  -- A recognized but otherwise unidentified SDL gamepad has the Xbox-style
  -- logical face names.  A raw, unnamed joystick has no safe family.
  if isGamepad(device) or state.axes[device] or state.buttons[device] then return "xbox" end
  return nil
end

function Controller.profile()
  return profileFor(state.active)
end

function Controller.activeJoystick()
  return state.active
end

function Controller.setStyle(style)
  style = style == nil and "auto" or lower(style)
  if not VALID_STYLES[style] then
    return nil, "unknown controller icon style: " .. tostring(style)
  end
  state.style = style
  return style
end

function Controller.setThorLayout(layout)
  layout = lower(layout)
  if layout ~= "thor" and layout ~= "xbox" then
    return nil, "unknown Thor input mode: " .. tostring(layout)
  end
  state.thorLayout = layout
  return layout
end

function Controller.thorLayout()
  return state.thorLayout
end

local function axisState(device, axis)
  local axes = state.axes[device]
  if not axes then
    axes = {}
    state.axes[device] = axes
  end
  local prior = axes[axis]
  return axes, prior
end

function Controller.observe(event)
  if type(event) ~= "table" then return false end
  local device, phase = event.joystick, event.phase
  if type(device) ~= "table" and type(device) ~= "userdata" then return false end

  if (phase == "pressed" or phase == "released") and event.button ~= nil then
    local buttons = state.buttons[device]
    if not buttons then buttons = {}; state.buttons[device] = buttons end
    if phase == "released" then buttons[event.button] = nil; return false end
    if buttons[event.button] then return false end
    buttons[event.button] = true
    state.active = device
    return true
  end

  if phase ~= "axis" then return false end
  local axis = event.axis
  if axis == nil then return false end
  local value = tonumber(event.value)
  if not value or value ~= value then return false end
  local axes, prior = axisState(device, axis)
  local magnitude = math.abs(value)
  local direction = value < 0 and -1 or 1
  if magnitude <= AXIS_OFF then axes[axis] = nil; return false end
  if magnitude >= AXIS_ON and prior ~= direction then
    axes[axis] = direction
    state.active = device
    return true
  end
  return false
end

local function connectedList(game, supplied)
  if type(supplied) == "table" then return supplied end
  if type(game) == "table" and type(game.joysticks) == "table" then
    return game.joysticks
  end
  local js = love and love.joystick
  if js and type(js.getJoysticks) == "function" then
    local ok, list = pcall(js.getJoysticks)
    if ok and type(list) == "table" then return list end
  end
  return nil
end

local function chooseConnected(list)
  for _, device in ipairs(list) do
    if isGamepad(device) then return device end
  end
  for _, device in ipairs(list) do
    if profileFor(device) then return device end
  end
end

function Controller.update(game, joysticks)
  local list = connectedList(game, joysticks)
  if not list then
    if read(state.active, "isConnected") == false then state.active = nil end
    return state.active
  end

  local connected = {}
  for _, device in ipairs(list) do
    if read(device, "isConnected") ~= false then connected[#connected+1] = device end
  end
  list = connected

  local found
  for _, device in ipairs(list) do
    -- A GUID identifies a model, not a physical instance. Two identical pads
    -- must keep independent last-use and held-axis state.
    if state.active == device then found = device; break end
  end
  state.active = found or chooseConnected(list)

  -- Drop stale axis state, including a disconnected device's held direction.
  local live = setmetatable({}, { __mode = "k" })
  for _, device in ipairs(list) do live[device] = true end
  for device in pairs(state.axes) do
    if not live[device] then state.axes[device] = nil end
  end
  for device in pairs(state.buttons) do
    if not live[device] then state.buttons[device] = nil end
  end
  return state.active
end

local LOGICAL = {
  A = { action = "a", key = "a" }, B = { action = "b", key = "b" },
  S = { action = "start", key = "start" },
  L = { action = "l", key = "leftshoulder" },
  R = { action = "r", key = "rightshoulder" },
  CUP = { action = "r_up", key = "r_up" },
  CRIGHT = { action = "r_right", key = "r_right" },
  CDOWN = { action = "r_down", key = "r_down" },
  CLEFT = { action = "r_left", key = "r_left" },
  DPAD = { action = "dpad", key = "dpad" },
}

local PHYSICAL = {
  a = "a", b = "b", x = "x", y = "y", start = "start",
  leftshoulder = "leftshoulder", rightshoulder = "rightshoulder",
  r_up = "r_up", r_right = "r_right", r_down = "r_down", r_left = "r_left",
}

local LABELS = { back="BACK", guide="GUIDE", leftstick="L3", rightstick="R3",
  triggerleft="LT", triggerright="RT", lefttrigger="LT", righttrigger="RT",
  dpup="D-UP", dpdown="D-DOWN", dpleft="D-LEFT", dpright="D-RIGHT" }

local function label(physical)
  return LABELS[physical] or physical:upper():gsub("^JOY(%d+)$", "JOY %1")
end

local function bindingsOf(input)
  if type(input) ~= "table" then return nil end
  return input.padBindings or input
end

local function reverseBinding(bindings, wanted, default)
  if bindings[default] == wanted then return default end
  local found = {}
  for physical, action in pairs(bindings) do
    if action == wanted and type(physical) == "string" then found[#found+1] = physical end
  end
  -- Host bindings may have multiple aliases: choose deterministically.
  table.sort(found)
  return found[1]
end

local function dpadBinding(bindings)
  if type(bindings) ~= "table" then return "dpad" end
  for _, direction in ipairs({"up", "down", "left", "right"}) do
    if bindings["dp" .. direction] ~= direction then return nil end
  end
  return "dpad"
end

local function displayFamily()
  if state.style ~= "auto" then return state.style end
  return Controller.profile()
end

-- Return the icon family and the physical key that supplies the logical N64
-- control.  The nil key is intentional: callers should draw a text fallback.
function Controller.glyph(logical, input)
  logical = type(logical) == "string" and logical:upper() or logical
  local spec = LOGICAL[logical]
  local family = displayFamily()
  if not spec then return family, nil end

  local bindings = bindingsOf(input)
  local key, fallback
  if logical == "DPAD" then
    key = dpadBinding(bindings)
    if not key then fallback = "L STICK" end -- Input's fixed left-stick directions
  elseif logical == "L" or logical == "R" or logical:match("^C") then
    -- The host always dual-emits shoulders as l/r, independent of its map.
    -- stadium_menu.lua handles C directions on the right stick itself.
    key = spec.key
  elseif bindings then
    local physical = reverseBinding(bindings, spec.action, spec.key)
    key = physical and PHYSICAL[physical]
    if not key then fallback = physical and label(physical) or "UNBOUND" end
  else
    key = spec.key
  end

  -- Thor mode reports printed Android A/B/X/Y names; Xbox-style mode reports
  -- physical positions against Thor's Nintendo-style labels. This option is
  -- explicit because the firmware's style is not exposed by LÖVE/SDL identity.
  if family == "ayn_thor" and state.thorLayout == "xbox" and key then
    local swap = { a = "b", b = "a", x = "y", y = "x" }
    key = swap[key] or key
  end
  return family, key, fallback
end

function Controller.reset()
  state.active = nil
  state.style = "auto"
  state.thorLayout = "thor"
  state.axes = setmetatable({}, { __mode = "k" })
  state.buttons = setmetatable({}, { __mode = "k" })
end

return Controller
