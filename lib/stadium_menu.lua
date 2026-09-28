-- Input for the Stadium UI menus (STADIUM UI option).
--
-- Runs from the mod's input.step hook, which the engine calls before it
-- promotes this tick's presses, so every action here reaches the battle on
-- the same tick. Actions go through the host's own menu state and the
-- public mod.input taps; no engine function is patched.
--
-- Stadium 2's own handlers (michiiik 0ed78d4, US):
-- * command bar func_84139EB0: pressed A = BATTLE, B = POKeMON, Start = RUN;
-- * move select func_8413A53C: held D-pad up/right/down/left = info card of
--   move 1..4 (func_8413A12C), held R = CHECK (func_84139F44), pressed L =
--   cancel, pressed C-up/right/down/left = move 1..4; A is not read.
--
-- Two control styles:
-- * Stadium controls (a controller is in use, or MENU CONTROLS = STADIUM):
--   exactly the handlers above, with no cursor. The host's A is withheld on
--   the move and switch screens, where Stadium does not read it, so an
--   invisible cursor can never pick anything.
-- * Cursor (keyboard or touch with MENU CONTROLS = CURSOR, the default): the
--   host's cursor and A work unchanged and the Stadium menus mark the
--   cursor; R held shows the cursor move's info card.
-- Either way B = POKeMON, Start = RUN and R = PACK on the command bar (the
-- host command menus ignore those buttons), C buttons pick, L cancels, and
-- a tap on a tab, move or card picks it. PACK is not in Stadium 2.
--
-- Generated controller prompts are a port extension. Native N64 glyphs
-- remain available on keyboard and through the icon preference.
local UI = require("mods.STADIUM2_IMPORTER.lib.stadium_ui")
local Controller = require("mods.STADIUM2_IMPORTER.lib.stadium_controller")
local ButtonGlyphs = require("mods.STADIUM2_IMPORTER.lib.stadium_button_glyphs")

local Menu = {}

-- Keyboard keys for the N64 buttons the host has no binding for, and the
-- gamepad axis flicks that stand in for the C buttons.
Menu.bindings = {
  keyboard = { CUP = "i", CLEFT = "j", CDOWN = "k", CRIGHT = "l" },
  stick = { axisX = "rightx", axisY = "righty", threshold = 0.6 },
}

local held = {}
local taps = {}
-- "pad" or "keyboard": the device that pressed last (touch leaves it as is)
local device
-- switch screen: which row of three the C buttons address (parties of 4..6)
local switchRow = 1

local function currentC()
  local now, from = {}, nil
  local keyboard = love and love.keyboard
  if keyboard and keyboard.isDown then
    for button, key in pairs(Menu.bindings.keyboard) do
      local ok, down = pcall(keyboard.isDown, key)
      if ok and down then now[button] = true; from = "keyboard" end
    end
  end
  local joystick = love and love.joystick
  if joystick and joystick.getJoysticks then
    local stick = Menu.bindings.stick
    local active = Controller.activeJoystick()
    for _, js in ipairs(active and {active} or {}) do
      if js:isGamepad() then
        local x, y = js:getGamepadAxis(stick.axisX), js:getGamepadAxis(stick.axisY)
        if y < -stick.threshold then now.CUP = true; from = "pad"
        elseif y > stick.threshold then now.CDOWN = true; from = "pad" end
        if x < -stick.threshold then now.CLEFT = true; from = "pad"
        elseif x > stick.threshold then now.CRIGHT = true; from = "pad" end
      end
    end
  end
  return now, from
end

local function padConnected()
  local joystick = love and love.joystick
  if not (joystick and joystick.getJoysticks) then return false end
  local ok, list = pcall(joystick.getJoysticks)
  if not ok then return false end
  for _, js in ipairs(list) do
    local okPad, isPad = pcall(js.isGamepad, js)
    if okPad and isPad then return true end
  end
  return false
end

-- The host tags every press with its source ("key:x", "pad:a", "joy:3",
-- "stick", "hat...", "touch:a", "mod:..."); the latest physical one decides.
local function sourceDevice(source)
  if type(source) ~= "string" then return nil end
  if source:match("^key:") then return "keyboard" end
  if source:match("^pad:") or source:match("^joy:") or source == "stick" or source:match("^hat") then
    return "pad"
  end
  return nil
end

function Menu.noteDevice(game, cFrom)
  local input = game and game.input
  local queue = input and input.pressQueue
  local sources = input and input.sources
  if type(queue) == "table" and type(sources) == "table" then
    for _, button in ipairs(queue) do
      for source in pairs(sources[button] or {}) do
        device = sourceDevice(source) or device
      end
    end
  end
  if cFrom then device = cFrom end
  if device == nil then device = padConnected() and "pad" or "keyboard" end
  return device
end

function Menu.device() return device end

function Menu.gamepad(event)
  if Controller.observe(event) then device = "pad" end
end

function Menu.stadiumControls(mode)
  return mode == "stadium" or device == "pad"
end

-- Edges since the previous step.
function Menu.cEdges(now)
  local from
  if not now then now, from = currentC() end
  local edges = {}
  for button in pairs(now) do
    if not held[button] then edges[button] = true end
  end
  held = now
  return edges, from
end

-- input.pointer: remember presses; a press on a Stadium target acts on the
-- next step.
function Menu.pointer(event)
  if type(event) == "table" and event.phase == "pressed" and event.x and event.y then
    taps[#taps + 1] = { x = event.x, y = event.y }
  end
end

local C_SLOT = { CUP = 1, CRIGHT = 2, CDOWN = 3, CLEFT = 4 }
-- Switch screen columns (the icons the game drew): C-left, C-up, C-right.
local C_MEMBER = { CLEFT = 1, CUP = 2, CRIGHT = 3 }
-- func_8413A53C's D-pad order (up, right, down, left = move 1..4).
local DPAD_SLOT = { { "up", 1 }, { "right", 2 }, { "down", 3 }, { "left", 4 } }

-- A switch-screen pick spans two ticks: the host's A opens its SWITCH/STATS
-- submenu, then the wanted entry is chosen.
local pendingSub

local function pending(game)
  local out = {}
  local queue = game and game.input and game.input.pressQueue
  if type(queue) == "table" then
    for _, button in ipairs(queue) do out[button] = true end
  end
  return out
end

-- Withhold a queued host press this tick (it never becomes an edge).
local function withhold(game, button)
  local queue = game and game.input and game.input.pressQueue
  if type(queue) ~= "table" then return end
  for i = #queue, 1, -1 do
    if queue[i] == button then table.remove(queue, i) end
  end
end

local function isDown(game, button)
  local input = game and game.input
  if not (input and type(input.isDown) == "function") then return false end
  local ok, down = pcall(input.isDown, input, button)
  return ok and down == true
end

-- The move whose info card shows: D-pad held (Stadium controls,
-- func_8413A53C) or R held on the cursor move (cursor controls).
function Menu.infoSlot(game, mode, cursor, moveCount)
  moveCount = moveCount or 4
  if Menu.stadiumControls(mode) then
    for _, d in ipairs(DPAD_SLOT) do
      if isDown(game, d[1]) and d[2] <= moveCount then return d[2] end
    end
    return nil
  end
  if isDown(game, "r") and cursor and cursor <= moveCount then return cursor end
  return nil
end

function Menu.switchRow(memberCount)
  local rows = math.max(1, math.ceil((memberCount or 0) / 3))
  if switchRow > rows then switchRow = 1 end
  return switchRow
end

-- ctx (from the battle scene):
--   { kind = "command", select = fn(hostIndex), current = fn() -> hostIndex,
--     tabs = { {hostIndex=..}, ... } }
--   { kind = "moves", select = fn(slot), moveCount = n }
--   { kind = "switch", select = fn(i), memberCount = n, submenuOpen = fn(),
--     selectSub = fn(action) }
--   { kind = "yesno", select = fn(i) } (1 = YES, 2 = NO)
-- tap = fn(button) queues a host button press (mod.input:tap).
function Menu.step(game, ctx, mode, tap, cNow)
  Controller.update(game)
  if device == "pad" and love and love.joystick and love.joystick.getJoysticks
      and not Controller.activeJoystick() then device = "keyboard" end
  local edges, cFrom = Menu.cEdges(cNow)
  Menu.noteDevice(game, cFrom)
  local stadium = Menu.stadiumControls(mode)
  local pressedTaps = taps
  taps = {}
  if not ctx or ctx.kind ~= "switch" then pendingSub = nil; switchRow = 1 end
  if not ctx or type(tap) ~= "function" then return nil end
  local queued = pending(game)
  if ctx.kind == "command" then
    local choose
    for _, t in ipairs(pressedTaps) do
      local id = UI.hitAt(t.x, t.y)
      local i = id and tonumber(id:match("^command:(%d+)$"))
      if i then choose = i end
    end
    if not choose then
      for i, t in ipairs(ctx.tabs or {}) do
        if t.button == "A" and queued.a and stadium then
          -- the host's own A then confirms this entry
          ctx.select(t.hostIndex)
        elseif (t.button == "B" and queued.b) or (t.button == "S" and queued.start)
            or (t.button == "R" and queued.r) then
          choose = i
        end
      end
    end
    if choose and ctx.tabs and ctx.tabs[choose] then
      ctx.select(ctx.tabs[choose].hostIndex)
      tap("a")
      return "command:" .. choose
    end
    -- The host menu is a 2x2 grid; the Stadium bar is one row, so the
    -- D-pad is taken over here: left/right step along the tabs (clamped,
    -- as the host's cursor clamps), up/down do nothing.
    local left, right = queued.left, queued.right
    for _, button in ipairs({ "left", "right", "up", "down" }) do withhold(game, button) end
    if (left or right) and ctx.tabs and type(ctx.current) == "function" then
      local at = 1
      for i, t in ipairs(ctx.tabs) do
        if t.hostIndex == ctx.current() then at = i end
      end
      local to = math.max(1, math.min(#ctx.tabs, at + (right and 1 or -1)))
      if left and right then to = at end
      ctx.select(ctx.tabs[to].hostIndex)
      return "tab:" .. to
    end
  elseif ctx.kind == "switch" then
    if ctx.submenuOpen() then
      if pendingSub then
        local want = pendingSub
        pendingSub = nil
        if ctx.selectSub(want) then tap("a"); return "sub:" .. want end
      end
      return nil
    end
    pendingSub = nil
    if stadium then withhold(game, "a") end
    local count = ctx.memberCount or 0
    local rows = math.max(1, math.ceil(count / 3))
    if switchRow > rows then switchRow = 1 end
    -- C-down moves the C buttons to the next row of three (port adaptation:
    -- Stadium parties are three, Gen 1/2 parties up to six)
    if edges.CDOWN and rows > 1 then
      switchRow = switchRow % rows + 1
      return "row:" .. switchRow
    end
    local member
    for button, c in pairs(C_MEMBER) do
      if edges[button] then member = (switchRow - 1) * 3 + c end
    end
    for _, t in ipairs(pressedTaps) do
      local id = UI.hitAt(t.x, t.y)
      local i = id and tonumber(id:match("^switch:(%d+)$"))
      if i then member = i end
    end
    if member and member <= count then
      ctx.select(member)
      tap("a")
      -- R (CHECK) held while picking: the host's STATS for that member
      pendingSub = isDown(game, "r") and "stats" or "battle_switch"
      return "switch:" .. member
    end
    if not stadium then
      if queued.r then
        -- CHECK: the host's STATS for the member under the cursor
        tap("a")
        pendingSub = "stats"
        return "stats"
      end
      if queued.a then
        -- selecting a member switches, as in Stadium; the host's A opens its
        -- submenu this tick and SWITCH is chosen on the next
        pendingSub = "battle_switch"
      end
    end
  elseif ctx.kind == "yesno" then
    -- Stadium lays NO left of YES; the host toggles with up/down, so
    -- left/right (and a tap) pick directly. A and B stay the host's.
    for _, t in ipairs(pressedTaps) do
      local id = UI.hitAt(t.x, t.y)
      local i = id and tonumber(id:match("^yesno:(%d)$"))
      if i then
        ctx.select(i)
        tap("a")
        return "yesno:" .. i
      end
    end
    if queued.left then ctx.select(2); return "no" end
    if queued.right then ctx.select(1); return "yes" end
  elseif ctx.kind == "moves" then
    if stadium then withhold(game, "a") end
    local slot
    for button, i in pairs(C_SLOT) do
      if edges[button] then slot = i end
    end
    for _, t in ipairs(pressedTaps) do
      local id = UI.hitAt(t.x, t.y)
      local i = id and tonumber(id:match("^move:(%d+)$"))
      if i then slot = i end
    end
    if slot and slot <= (ctx.moveCount or 0) then
      ctx.select(slot)
      tap("a")
      return "move:" .. slot
    end
    if queued.l then
      tap("b")
      return "cancel"
    end
  end
  return nil
end

-- Draw the open menu. view = { kind, tabs, commandIndex, members,
-- switchIndex, moves, moveIndex, message, lines, yesIndex, game, mode }.
function Menu.draw(view)
  ButtonGlyphs.setContext(view.game, device)
  local stadium = Menu.stadiumControls(view.mode)
  if view.kind == "command" then
    local selected
    if not stadium then
      for i, t in ipairs(view.tabs or {}) do
        if t.hostIndex == view.commandIndex then selected = i end
      end
    end
    UI.commandBar(view.tabs or {}, selected)
  elseif view.kind == "switch" then
    local members = view.members or {}
    UI.switchCards(members, not stadium and view.switchIndex or nil, Menu.switchRow(#members))
    -- a refusal ("There's no will to fight!") from the hidden host menu
    local message = view.message
    if type(message) == "string" and message ~= "" then
      local lines = {}
      for line in message:gmatch("[^\n]+") do lines[#lines + 1] = UI.toLatin1(line) end
      UI.messageBox(lines, "player")
    end
  elseif view.kind == "yesno" then
    -- host text is UTF-8; the ROM font is Latin-1
    local lines = {}
    for i, line in ipairs(view.lines or {}) do lines[i] = UI.toLatin1(line) end
    UI.yesNo(lines, view.yesIndex)
  elseif view.kind == "moves" then
    local moves = view.moves or {}
    local info = Menu.infoSlot(view.game, view.mode, view.moveIndex, #moves)
    local slot = info and UI.MOVE_SLOTS[info]
    if slot and moves[info] then
      UI.moveInfo(moves[info], slot.button)
    else
      UI.moveDiamond(moves, not stadium and view.moveIndex or nil)
      UI.hint(3)
    end
  end
end

function Menu.reset()
  held, taps, pendingSub, switchRow, device = {}, {}, nil, 1, nil
end

return Menu
