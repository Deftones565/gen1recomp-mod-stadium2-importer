-- 300-slot native particle pool: 84100260 allocation, the 841072BC stop on
-- a full pool, and the 8410668C pool origin. Needs no ROM.
-- Run from the Gen1Recomp repository root.
package.path = "./?.lua;./?/init.lua;" .. package.path
local Runtime = require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_runtime")

local checks = 0
local function ok(value, message)
  checks = checks + 1
  if not value then error("FAIL " .. message, 0) end
end

-- Stub native program: `plan[frame]` lists emissions {count, flags, mode}.
local plan = {}
local native = {
  execute = function() return {records = {}, diagnostics = {}} end,
  particles = function(_, previous, frame)
    local out = {}
    for f = previous + 1, frame do
      for group, emission in ipairs(plan[f] or {}) do
        for i = 1, emission.count do
          out[#out + 1] = {schedulerIndex = group, generation = f, particleIndex = i,
            born = f, position = {i, 0, 0}, velocity = {0, 0, 0},
            event = {mode = emission.mode or 0, flags = emission.flags or 0,
              programId = 1, address = 0x8417B624}}
        end
      end
    end
    return out
  end,
}
local lifetime = 1000
local motion = {
  init = function(source)
    return {age = 0, lifetime = lifetime, alive = true, position = source.position,
      velocity = {0, 0, 0}, rotation = {0, 0, 0}, scale = {1, 1, 1}}
  end,
  step = function(state, delta)
    return {age = state.age + delta, lifetime = state.lifetime,
      alive = state.age + delta < state.lifetime,
      position = {state.position[1], state.position[2] + 1, state.position[3]},
      velocity = state.velocity, rotation = state.rotation, scale = state.scale}
  end,
}
local catalog = {programs = {[1] = {id = 1, records = {}}},
  moves = {[1] = {primaryDispatch = {{kind = "program", programId = 1}},
    alternateDispatch = {{kind = "program", programId = 1}}}}}
local function newRuntime()
  return Runtime.new({catalog = catalog, native = native, motion = motion,
    router = {resolve = function(move) return move.primaryDispatch end}})
end
local function live(runtime)
  local n = 0
  for _, p in ipairs(runtime:snapshot().particles) do if p.active then n = n + 1 end end
  return n
end

-- Allocation order and cursor.
local runtime = newRuntime()
plan = {[1] = {{count = 3}}}
assert(runtime:trigger({moveId = 1}))
runtime:step(1)
local slots = {}
for _, p in ipairs(runtime.effects[1].particles) do slots[#slots + 1] = p.nativeSlot end
ok(slots[1] == 0 and slots[2] == 1 and slots[3] == 2, "slots are taken from the cursor in order")
ok(runtime.nativePool.cursor == 3, "the cursor moves past the last slot taken")

-- A full pool drops the rest of the emission and leaves the cursor.
runtime = newRuntime()
plan = {[1] = {{count = 250}}, [2] = {{count = 80}, {count = 5}}}
assert(runtime:trigger({moveId = 1}))
runtime:step(2)
ok(live(runtime) == 300, "no more than 300 particles are live")
local counts = {}
for _, p in ipairs(runtime.effects[1].particles) do
  counts[p.schedulerIndex .. ":" .. p.generation] = (counts[p.schedulerIndex .. ":" .. p.generation] or 0) + 1
end
ok(counts["1:2"] == 50 and counts["2:2"] == nil, "the emission stops at the full pool; later ones get nothing")
ok(runtime.nativePool.cursor == 0, "the cursor wrapped to slot 0 and stays while full")
local reported = false
for _, d in ipairs(runtime.diagnostics) do
  if d.code == "native-particle-pool-full" then reported = true end
end
ok(reported, "the dropped emission is reported")

-- Freed slots are reused from the cursor, wrapping.
lifetime = 2
runtime = newRuntime()
plan = {[1] = {{count = 300}}, [4] = {{count = 2}}}
assert(runtime:trigger({moveId = 1}))
runtime:step(4)
local reused = {}
for _, p in ipairs(runtime.effects[1].particles) do
  if p.generation == 4 then reused[#reused + 1] = p.nativeSlot end
end
ok(reused[1] == 0 and reused[2] == 1, "expired slots are reused from the wrapped cursor")
lifetime = 1000

-- 8410668C: first live 0x400000 particle in slot order with the same
-- secondary flag; not-yet-updated particles contribute (0,0,0).
runtime = newRuntime()
plan = {[1] = {{count = 1, flags = 0}, {count = 1, flags = 0x400000}}}
assert(runtime:trigger({moveId = 1}))
runtime:step(1)
local target = {event = {flags = 0x800000, mode = 1}}
local origin, source = runtime:nativePoolOrigin(target)
ok(source and source.nativeSlot == 1 and origin[1] == 0 and origin[2] == 0,
  "a particle not yet updated contributes zero")
runtime:step(1)
origin, source = runtime:nativePoolOrigin(target)
ok(source.nativeSlot == 1 and origin[1] == 1 and origin[2] == 1,
  "an updated particle contributes its current position")
target.nativeSecondaryEmission = true
origin, source = runtime:nativePoolOrigin(target)
ok(source == nil and origin[1] == 0 and origin[2] == 0 and origin[3] == 0,
  "the secondary flag must match; no match adds nothing")

print(("%d checks passed (battle FX native particle pool)"):format(checks))
