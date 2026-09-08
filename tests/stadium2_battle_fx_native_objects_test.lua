local Objects = require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_native_objects")

local checks = 0
local function ok(value, message)
  assert(value, message)
  checks = checks + 1
end

local calls = {}
local scheduler = Objects.new({
  resolve = function(commandPointer, event)
    calls[#calls + 1] = {commandPointer, event.mode}
    return {
      object = {encodedObjectRaw = "resolved", delay = 2, flags = {1, 2}},
      delay = 2,
    }
  end,
  callbacks = {
    [2] = function(object, slot)
      ok(object.delay == 2 and slot.mode == 2, "callback receives resolved object and slot")
      return {result = 1, visuals = {{kind = "native-visual"}}, rawFields = {count = 35}}
    end,
  },
})

local index = assert(scheduler:enqueue(0x8416A3E0, {
  mode = 2, encodedDelay = 99, commandPointer = 0x8416A3E0,
}))
ok(index == 0, "first native-object uses lowest free slot")
ok(#calls == 1, "resolver is called exactly once")
local before = scheduler:snapshot()
ok(before.slots[1].countdown == 2 and before.slots[1].reload == 0,
  "resolver delay initializes countdown and reload is zero")
scheduler:tick(1)
ok(scheduler:snapshot().slots[1].countdown == 1,
  "positive countdown decrements without dispatch")
scheduler:tick(1)
ok(#scheduler:snapshot().slots == 0,
  "countdown dispatches and releases on the tick it reaches zero")
ok(#scheduler.diagnostics == 0, "supported callback does not diagnose")

local snapshot = scheduler:snapshot()
snapshot.diagnostics[1] = {code = "mutated"}
ok(#scheduler:snapshot().diagnostics == 0, "snapshot diagnostics are deep copies")

local repeatedCalls = 0
local repeated = Objects.new({
  resolve = function() return {object = {delay = 0}, delay = 0} end,
  callbacks = {[8] = function()
    repeatedCalls = repeatedCalls + 1
    return repeatedCalls == 1 and 0xFF or 1
  end},
})
assert(repeated:enqueue(0x8416C83C, {mode = 8}))
repeated:tick(1)
ok(repeatedCalls == 1 and #repeated:snapshot().slots == 1,
  "0xFF keeps the scheduler slot active")
repeated:tick(1)
ok(repeatedCalls == 2 and #repeated:snapshot().slots == 0,
  "reloaded slot dispatches again and releases on age equality")

local nonPositive = Objects.new({
  resolve = function() return {object = {delay = 0}, delay = 0} end,
  callbacks = {[5] = function() return 0 end},
})
assert(nonPositive:enqueue(0x84178894, {mode = 5}))
nonPositive:tick(1)
ok(#nonPositive:snapshot().slots == 1 and nonPositive:snapshot().slots[1].age == 0,
  "non-positive result leaves slot active and age unchanged")

for _, mode in ipairs({4, 6}) do
  local synthetic = Objects.new({
    resolve = function() return {object = {delay = 0}, delay = 0} end,
    callbacks = {[mode] = function() return 1 end},
  })
  assert(synthetic:enqueue(0x1000 + mode, {mode = mode}))
  synthetic:tick(1)
  ok(#synthetic:snapshot().slots == 0, ("synthetic mode %d scheduler path"):format(mode))
end

-- With no injected resolver, the main-segment mapping path can resolve a
-- decoded fragment-79 command conservatively.  It does not install guessed
-- update/draw callbacks; this callback is only test evidence.
local rawObject = string.char(
  0x00, 0x00, 0x00, 0x23,
  0x84, 0x16, 0xA3, 0xD8,
  0x00, 0x00, 0x00, 0x14,
  0x84, 0x16, 0xA3, 0xD8)
local builtin = Objects.new({callbacks = {
  [2] = function(object, slot)
    ok(object.pointer == 0x8416A3E0 and slot.countdown == 0x23,
      "built-in resolver exposes mapped fragment object to callbacks")
    return 0
  end,
}})
assert(builtin:enqueue(0x8416A3E0, {
  mode = 2, effectId = 98, programId = 98, address = 0x84173DA4,
  encodedObjectRaw = rawObject, encodedDelay = 0x23, delayOffset = 3,
  resolution = {status = "unresolved", resolver = 0x80003240},
}))
local builtinSnapshot = builtin:snapshot()
local builtinSlot = builtinSnapshot.slots[1]
ok(builtinSlot.object.pointer == 0x8416A3E0
    and builtinSlot.object.resolvedPointer == 0x8416A3E0
    and builtinSlot.object.encodedObjectRaw == rawObject
    and builtinSlot.resolution.resolution.status == "fragment79-main-resolver"
    and builtinSlot.resolution.resolution.mapper == 0x800024A0
    and builtinSlot.resolution.resolution.low20Offset == 0x6A3E0,
  "built-in resolver retains exact main resolver and low-20-bit evidence")
builtin:tick(1)
ok(#builtin:snapshot().diagnostics == 0,
  "mapped decoded object does not diagnose when callback is supported")

local malformed = Objects.new()
local malformedIndex, malformedError = malformed:enqueue(0x8416A3E0, {
  mode = 2, encodedDelay = 0x23, delayOffset = 3,
  encodedObjectRaw = string.rep("\0", 4),
})
ok(malformedIndex == nil and malformedError.code == "unsupported-native-resolution"
    and malformedError.message:match("at least 16 raw bytes"),
  "short decoded object evidence remains a resolution diagnostic")
local mismatch = Objects.new()
local mismatchIndex, mismatchError = mismatch:enqueue(0x8416A3E0, {
  mode = 2, encodedDelay = 0x22, delayOffset = 3,
  encodedObjectRaw = rawObject,
})
ok(mismatchIndex == nil and mismatchError.code == "unsupported-native-resolution"
    and mismatchError.message:match("disagrees with raw byte"),
  "decoded delay disagreement remains a resolution diagnostic")
local outside = Objects.new()
local outsideIndex, outsideError = outside:enqueue(0x90000000, {
  mode = 2, encodedDelay = 0x23, delayOffset = 3,
  encodedObjectRaw = rawObject,
})
ok(outsideIndex == nil and outsideError.code == "unsupported-native-resolution"
    and outsideError.message:match("outside the fragment%-79 image"),
  "out-of-range main resolver input remains a resolution diagnostic")
local wrongFragmentIndex,wrongFragmentError=outside:enqueue(0x8116A3E0,{
  mode=2,encodedObjectRaw=rawObject,encodedDelay=0x23,delayOffset=3,
})
ok(wrongFragmentIndex==nil
    and wrongFragmentError.code=="unsupported-native-resolution",
  "another registered fragment cannot alias fragment 79 by low offset")

local unresolved = Objects.new({resolve = function() return nil, "not linked" end})
local failed, failure = unresolved:enqueue(0xDEAD, {mode = 2})
ok(failed == nil and failure.code == "unsupported-native-resolution"
    and #unresolved:snapshot().slots == 0, "resolver failure allocates no slot")

local unsupported = Objects.new({
  resolve = function() return {object = {delay = 0}, delay = 0} end,
})
assert(unsupported:enqueue(0x1234, {
  mode = 6, effectId = 42, programId = 328, address = 0x841788B8,
}))
unsupported:draw()
unsupported:draw()
unsupported:tick(1)
unsupported:tick(1)
local unsupportedSnapshot = unsupported:snapshot()
local updateDiagnostic=unsupportedSnapshot.diagnostics[2]
ok(updateDiagnostic.code == "unsupported-native-update"
    and updateDiagnostic.severity == "warning"
    and updateDiagnostic.effectId == 42
    and updateDiagnostic.programId == 328
    and updateDiagnostic.address == 0x841788B8
    and updateDiagnostic.kind == "native-object"
    and type(updateDiagnostic.message) == "string"
    and updateDiagnostic.commandPointer == 0x1234
    and updateDiagnostic.mode == 6
    and #unsupportedSnapshot.diagnostics == 2
    and #unsupportedSnapshot.slots == 0,
  "missing callback diagnoses and preserves the proven one-shot scheduler result")
ok(unsupportedSnapshot.diagnostics[1].code == "unsupported-native-draw"
    and unsupportedSnapshot.diagnostics[1].effectId == 42
    and unsupportedSnapshot.diagnostics[1].programId == 328
    and unsupportedSnapshot.diagnostics[1].address == 0x841788B8,
  "missing draw callback diagnoses once without fabricating particles")

local full = Objects.new({
  resolve = function() return {object = {delay = 10}, delay = 10} end,
})
for mode = 2, 8 do
  if Objects.MODES[mode] then assert(full:enqueue(mode, {mode = mode})) end
end
for _ = 1, 60 do
  local slot = full:enqueue(0x10000, {mode = 2})
  if not slot then break end
end
local fullSnapshot = full:snapshot()
ok(#fullSnapshot.slots == 64, "scheduler capacity is 64")
local capacityIndex, capacityError = full:enqueue(0xBEEF, {mode = 2})
ok(capacityIndex == nil and capacityError.code == "native-object-capacity",
  "capacity exhaustion is diagnosed")
full:release()
ok(#full:snapshot().slots == 0, "explicit release clears all slots")

print(("%d checks passed (Stadium 2 native-object scheduler)"):format(checks))
