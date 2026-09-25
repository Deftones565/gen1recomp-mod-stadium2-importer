-- Move/impact sequencing (84108728/841087B8/841088CC), non-move FX entries
-- (8410890C -> 8410545C) and the failed-move cleanup (841089D8).
-- Run from the Gen1Recomp repository root.
package.path = "./?.lua;./?/init.lua;" .. package.path
local prefix = "mods.STADIUM2_IMPORTER.lib."
local Sequence = require(prefix .. "stadium2_battle_fx_sequence")
local Router = require(prefix .. "stadium2_battle_fx_router")

local checks = 0
local function ok(value, message)
  assert(value, message)
  checks = checks + 1
end

-- 841087B8 decision table.
ok(Sequence.impactAction(1, nil) == "impact", "ordinary result plays the impact bank")
ok(Sequence.impactAction(1, 0x10) == "impact", "only the low three result bits are consulted")
ok(Sequence.impactAction(1, 6) == "none", "84117CAC withholds the hit-frame call for result 6")
for _, move in ipairs({0x2D, 0x2F, 0x30, 0x5F, 0x67, 0xAD, 0xC3}) do
  ok(Sequence.impactAction(move, 1) == "impact", ("result 1 keeps the impact for move 0x%X"):format(move))
end
ok(Sequence.impactAction(0x39, 1) == "owner", "Surf result 1 reaches 8410878C only")
ok(Sequence.impactAction(33, 1) == "fail", "other result-1 moves take 841089D8")
ok(Sequence.impactAction(33, 9) == "fail", "result 9 & 7 == 1")

local row = string.rep("\0", 20)
local bytes = row .. row:sub(1, 11) .. string.char(0x0E) .. row:sub(13)
  .. row:sub(1, 11) .. string.char(0xF0) .. row:sub(13)
ok(Sequence.hitFrame(bytes, 2) == 14, "hit frame is dispatch row +0x0B")
ok(Sequence.hitFrame(bytes, 3) == -16, "hit frame is a signed byte")
ok(Sequence.hitFrame(bytes, 9) == nil and Sequence.hitFrame(nil, 1) == nil, "absent rows stay unresolved")

-- Result byte built from battle facts (84124A7C / 84128298 / 84130E04).
ok(Sequence.resultByte({missed = true, damaging = true, critical = true}) == 1,
  "a missed attack keeps result 1")
ok(Sequence.resultByte({damaging = true, typeModifier = 10}) == 0, "neutral hit is 0")
ok(Sequence.resultByte({damaging = true, typeModifier = 20}) == 3, "super effective is 3")
ok(Sequence.resultByte({damaging = true, typeModifier = 5}) == 2, "not very effective is 2")
ok(Sequence.resultByte({damaging = true, critical = true, typeModifier = 20}) == 4,
  "a critical hit overrides effectiveness")
ok(Sequence.resultByte({damaging = true, ohko = true}) == 4, "OHKO is 4")
for _, move in ipairs({0x14, 0x23, 0x84}) do
  ok(Sequence.resultByte({damaging = true, typeModifier = 20, moveId = move}) == 5,
    ("move 0x%X is 5"):format(move))
end
ok(Sequence.resultByte({damaging = true, critical = true, moveEffect = 0x75}) == 5,
  "move effect 0x75 is 5 even after a critical hit")
ok(Sequence.resultByte({damaging = true}) == nil, "a missing type modifier stays unresolved")
ok(Sequence.resultByte({damaging = false}) == nil, "status-move results are not guessed")
ok(Sequence.resultByte(nil) == nil, "absent facts stay unresolved")

-- Router variant channel.
local move = {primaryDispatch = {{kind = "program", programId = 1}},
  alternateDispatch = {{kind = "program", programId = 2}},
  variantDispatch = {{kind = "program", programId = 3}}}
ok(Router.resolve(move, false, true)[1].programId == 3, "route mode 1 selects the variant channel")
ok(Router.resolve(move, false)[1].programId == 1, "route mode 0 is unchanged")
ok(Router.resolve({primaryDispatch = {}, alternateDispatch = {}}, false, true) == nil,
  "entries without a variant primary have no mode-1 route")

local path = os.getenv("STADIUM2_ROM") or "mods/STADIUM2_IMPORTER/baseroms/stadium2.z64"
local file = io.open(path, "rb")
if not file then
  assert(os.getenv("STADIUM2_REQUIRE_ROM") ~= "1", "required ROM unavailable")
  print(checks .. " checks passed (battle FX sequencing; ROM SKIP)")
  return
end
local rom = file:read("*a"); file:close()
local FxRom = require(prefix .. "stadium2_battle_fx_rom")
local catalog = assert(FxRom.catalog(rom))

-- D_84182A5C entries 252..301 and the two-turn variant routes.
for id = 252, 301 do
  local entry = catalog.moves[id]
  ok(entry and #entry.primaryDispatch >= 1, ("non-move FX entry %d is decoded"):format(id))
end
ok(catalog.moves[302] == nil, "the catalog stops at entry 301")
ok(catalog.moves[261].primaryDispatch[1].kind == "lifecycle"
  and catalog.moves[261].primaryDispatch[1].lifecycleId == 29, "entry 261 uses lifecycle family 29")
local variants = {[13] = 69, [19] = 70, [76] = 82, [91] = 37, [130] = 394, [143] = 122}
local variantCount = 0
for id = 1, 301 do
  local entry = catalog.moves[id]
  if variants[id] then
    ok(entry.variantDispatch and entry.variantDispatch[1].programId == variants[id],
      ("move %d variant +2 route is program %d"):format(id, variants[id]))
  end
  if entry.variantDispatch then variantCount = variantCount + 1 end
end
ok(variantCount == 6, "only the six side-variant primaries have a mode-1 route")

-- Real runtime through the Player and adapter.
local Player = require(prefix .. "stadium2_battle_fx_player")
local Adapter = require(prefix .. "stadium2_battle_fx_battle_adapter")
local warnings = {}
local adapter = assert(Adapter.new({
  betaBattleFxEnabled = function() return true end,
  newBattleFxPlayer = function() return Player.new({catalog = catalog}) end,
}, {warn = function(message) warnings[#warnings + 1] = message end}))
local runtime = adapter.player.runtime
local function effectFor(id) return runtime.effects[id] end

local fly = assert(adapter:playVariant(19, "player"))
ok(effectFor(fly).dispatch[1].programId == 70, "Fly mode 1 plays variant program 70")
ok(effectFor(fly).variant == true and adapter.routeMode == 1, "mode-1 route state is recorded")

local entry = assert(adapter:signalEffect(254, "enemy"))
ok(effectFor(entry).moveId == 254 and effectFor(entry).sourceSide == "enemy"
  and effectFor(entry).alternate == false, "8410890C plays the entry primary route for its owner")
adapter:signalEffect(300, "player")
ok(adapter.player.signals.global == 1, "entry 300 still latches the alpha gate")

local move = assert(adapter:playMove(1, "player"))
ok(effectFor(move).dispatch[1].programId == 394, "Pound move bank is the empty program")
local action, impact = adapter:impact(1, "player")
ok(action == "impact" and effectFor(impact).alternate == true
  and effectFor(impact).dispatch[1].programId == 138, "Pound impact bank is program 138")
ok(effectFor(move) ~= nil, "the impact starts alongside the move bank")

-- D_841901B8 (841094EC): route arming clears it, the impact sets it.
adapter:playMove(45, "player") -- Growl: wave-grid family 11
ok(runtime.lifecycle.nativeSignal == 0, "841086F0 clears the presentation signal")
runtime:step(5)
local growlAction = adapter:impact(45, "player", 1)
ok(growlAction == "impact" and runtime.lifecycle.nativeSignal == 1,
  "8410874C sets the presentation signal for result-1 Growl")
runtime:step(1)
local finishing = false
for _, instance in pairs(runtime.lifecycle.instances) do
  if instance.waveGrid and instance.waveGrid.finishing then finishing = true end
end
ok(finishing, "the wave grid starts its native fade after the impact")
adapter:impact(0x39, "player", 1)
ok(runtime.lifecycle.nativeSignal == 1, "8410878C (Surf) also sets the signal")
adapter:playMove(1, "player")
ok(runtime.lifecycle.nativeSignal == 0, "a new move route clears the signal")

-- 841089D8: failure clears emissions, lifecycles and non-held particles.
adapter:playMove(47, "player") -- Sing: lifecycle family 10
runtime:step(4)
local lifecycleCount = 0
for _ in pairs(runtime.lifecycle.instances) do lifecycleCount = lifecycleCount + 1 end
ok(lifecycleCount > 0, "Sing starts a lifecycle before the failure")
local heldEntry = assert(adapter:signalEffect(256, "enemy"))
runtime:step(20)
local held = 0
for _, particle in ipairs(effectFor(heldEntry).particles) do
  if math.floor((particle.event.flags or 0) / 0x20000000) % 2 == 1 then held = held + 1 end
end
ok(held > 0, "entry 256 spawns held (descriptor bit 0x20000000) particles")
action = adapter:impact(33, "player", 1)
ok(action == "fail", "Tackle with result 1 takes the failure path")
for _, id in ipairs(runtime.effectOrder) do
  local effect = runtime.effects[id]
  for _, particle in ipairs(effect.particles) do
    ok(math.floor((particle.event.flags or 0) / 0x20000000) % 2 == 1,
      "841003AC frees every particle except held ones")
  end
  ok(effect.emissionCancelled == true, "84105E3C cancels pending emissions")
end
ok(next(runtime.lifecycle.instances) == nil, "841093E8 clears every lifecycle slot")
local before = #effectFor(heldEntry).particles
runtime:step(10)
ok(#effectFor(heldEntry).particles <= before, "cancelled effects emit no further particles")

-- 84108974: Dig after mode 1 signals entry 0x12D on the failure path.
adapter:playVariant(91, "enemy")
local failed, digEntry = adapter:impact(91, "enemy", 1)
ok(failed == "fail" and digEntry and effectFor(digEntry).moveId == 0x12D,
  "Dig mode-1 failure signals entry 301")
local _, noEntry = adapter:impact(91, "enemy", 1)
ok(noEntry == nil, "the Dig signal is cleared after use")

-- 84108A10: release held particles of one owner.
local function countFlags(effect, bit)
  local n = 0
  for _, particle in ipairs(effect.particles) do
    if math.floor((particle.event.flags or 0) / bit) % 2 == 1 then n = n + 1 end
  end
  return n
end
local killEntry = assert(adapter:signalEffect(301, "player"))
local keepEntry = assert(adapter:signalEffect(256, "player"))
local otherOwner = assert(adapter:signalEffect(256, "enemy"))
runtime:step(20)
ok(countFlags(effectFor(killEntry), 0x08000000) > 0, "entry 301 holds kill-on-release particles")
local keepCount = #effectFor(keepEntry).particles
local otherCount = #effectFor(otherOwner).particles
ok(keepCount > 0 and otherCount > 0, "held entries are live before release")
ok(adapter:releaseHeld("player") > 0, "84108A10 releases the owner's held particles")
ok(countFlags(effectFor(killEntry), 0x08000000) == 0, "flag-0x8000 particles end on release")
ok(#effectFor(keepEntry).particles == keepCount, "released particles without flag 0x8000 stay alive")
adapter:impact(33, "player", 1)
ok(#effectFor(keepEntry).particles == 0, "released particles are no longer exempt from the abort")
ok(#effectFor(otherOwner).particles > 0, "the other owner's held particles survive both")

-- Scheduled impact at the dispatch hit frame.
local attacker = {renderer = {model = {fxDispatch = bytes}}}
adapter:playMoveAndImpact(2, "player", attacker)
local startFrame = runtime.frame
local pendingBefore = #runtime.effectOrder
adapter:update(13 / 30)
ok(#runtime.effectOrder == pendingBefore, "impact waits for the hit frame")
adapter:update(1 / 30)
ok(runtime.frame - startFrame == 14 and #runtime.effectOrder == pendingBefore + 1,
  "impact bank starts at the dispatch hit frame")
local warned = false
for _, message in ipairs(warnings) do
  if message:find("approach phases are not emulated", 1, true) then warned = true end
end
ok(warned, "approximate impact timing is reported")
adapter:playMoveAndImpact(2, "player", {renderer = {model = {}}})
local missing = false
for _, message in ipairs(warnings) do
  if message:find("no dispatch hit frame", 1, true) then missing = true end
end
ok(missing, "a missing hit frame is reported instead of guessed")
adapter:release()
print(checks .. " checks passed (battle FX sequencing)")
