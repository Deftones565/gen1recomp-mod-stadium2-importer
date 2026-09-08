package.path = "./?.lua;./?/init.lua;" .. package.path

local Runtime = require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_runtime")
local Native = require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_native")

local checks = 0
local function ok(value, message)
  checks = checks + 1
  if not value then error("FAIL " .. message, 0) end
end

local function vector(x, y, z) return {x or 0, y or 0, z or 0} end
local function emitter(start, interval, repeats)
  return {
    mode = 0, descriptor = 0x84170000,
    descriptorKind = "particle", start = start, interval = interval,
    repeats = repeats, particleCount = 1, shapeId = 47,
    geometry = {
      selectors = {scale = 1, position = 1, velocity = 1, attribute = 1},
      scaleEntries = {{scale = 1}},
      positionEntries = {{0, 0, 0}},
      velocityEntries = {{0, 0, 0}},
      attributeEntries = {0},
    },
    transform = {}, material = {shapeId = 47},
    attachment = {mode = "battler-origin"},
  }
end

local function program(id)
  return {id = id, records = {
    {opcode = 4, address = 0x8417B624, emitter = emitter(0, 1, 3)},
    {opcode = 0, address = 0x8417B62C},
  }}
end

local catalog = {
  programs = {[259] = program(259), [260] = program(260)},
  moves = {
    [7] = {
      moveId = 7,
      primaryDispatch = {{kind = "program", programId = 259}},
      alternateDispatch = {{kind = "program", programId = 260}},
    },
  },
}

-- Routing is an injected, single-call boundary.  The selected channel is the
-- only one handed to Native.execute, and a failed route cannot consume IDs.
local routeCalls, executed = 0, {}
local routeProbe = {}
function routeProbe.resolve(move, alternate)
  routeCalls = routeCalls + 1
  if routeProbe.fail then return nil, "deliberate route failure" end
  return alternate and move.alternateDispatch or move.primaryDispatch
end
local nativeProbe = {
  execute = function(nativeProgram, context)
    executed[#executed + 1] = nativeProgram.id
    return Native.execute(nativeProgram, context)
  end,
  particles = Native.particles,
}
local motionCalls = {init = 0, step = 0, rng = nil}
local motionProbe = {}
function motionProbe.init(source, options)
  motionCalls.init = motionCalls.init + 1
  motionCalls.rng = options.rng
  return {
    age = source.age or 0, lifetime = 2, alive = true,
    position = vector(4, 5, 6), velocity = vector(1, 0, 0),
    rotation = vector(), scale = vector(1, 1, 1), diagnostics = {
      {code = "probe-motion", address = 0x84106AC4, kind = "motion",
        message = "one stable probe diagnostic"},
    },
  }
end
function motionProbe.step(state, delta, options)
  motionCalls.step = motionCalls.step + 1
  return {
    age = state.age + delta, lifetime = state.lifetime,
    alive = state.age + delta < state.lifetime,
    position = vector(state.position[1] + 1, state.position[2], state.position[3]),
    velocity = state.velocity, rotation = state.rotation, scale = state.scale,
    diagnostics = state.diagnostics,
  }
end
local probeProgram = program(260)
probeProgram.records[1].emitter.repeats = 1
local probeCatalog = {
  programs = {[260] = probeProgram},
  moves = {[8] = {
    primaryDispatch = {{kind = "program", programId = 260}},
    alternateDispatch = {{kind = "program", programId = 260}},
  }},
}
local rngSentinel = function() return 0.25 end
local probeRuntime = Runtime.new({catalog = probeCatalog, router = routeProbe,
  native = nativeProbe, motion = motionProbe, rng = rngSentinel})
routeProbe.fail = true
local failedId, failedError = probeRuntime:trigger({moveId = 8})
ok(failedId == nil and failedError == "deliberate route failure",
  "routing failure returns an error")
ok(probeRuntime:snapshot().effects[1] == nil and probeRuntime.nextEffectId == 1,
  "routing failure does not mutate effects or allocate an ID")
routeProbe.fail = false
local probeEffect = assert(probeRuntime:trigger({moveId = 8, alternate = true}))
ok(probeEffect == 1 and routeCalls == 2 and executed[1] == 260,
  "router is called once and only its selected channel executes")
ok(motionCalls.init == 1 and motionCalls.rng == rngSentinel,
  "each birth initializes one motion state and receives injected RNG")
local probeFrame0 = probeRuntime:snapshot()
ok(probeFrame0.particles[1].position[1] == 4,
  "runtime particle reflects the initial evaluated motion state")
probeRuntime:step(1)
ok(motionCalls.step == 1 and probeRuntime:snapshot().particles[1].age == 1
  and probeRuntime:snapshot().particles[1].position[1] == 5,
  "each active particle is evaluated exactly once per tick")
ok(#probeRuntime:snapshot().diagnostics == 1,
  "motion diagnostics are normalized and de-duplicated")
probeRuntime:step(1)
ok(motionCalls.step == 2 and #probeRuntime:snapshot().particles == 0,
  "motion lifetime expiry removes the particle")

local runtime = Runtime.new({
  catalog = catalog,
  lifetimeResolver = function() return 2 end,
  rng = function() return 0 end,
})
local effectId = assert(runtime:trigger({
  moveId = 7, sourceSide = "player", targetSide = "enemy", condition = 0,
}))
ok(effectId == 1, "first effect receives ID one")

local frame0 = runtime:snapshot()
ok(frame0.frame == 0 and #frame0.particles == 1, "frame zero births once")
ok(frame0.particles[1].id == 1 and frame0.particles[1].age == 0,
  "frame zero particle identity and age")
ok(frame0.particles[1].position[1] == 0
  and frame0.particles[1].scale[1] == 1, "initial state is copied")

local beforeDraw = #frame0.particles
local again = runtime:snapshot()
ok(#again.particles == beforeDraw and again.particles[1].id == 1,
  "snapshotting does not create particles")
again.particles[1].position[1] = 99
ok(runtime:snapshot().particles[1].position[1] == 0,
  "snapshot nested tables are caller-owned copies")

runtime:step(1)
local frame1 = runtime:snapshot()
ok(frame1.frame == 1 and #frame1.particles == 2,
  "frame one retains old particle and adds one birth")
ok(frame1.particles[1].id == 1 and frame1.particles[1].age == 1
  and frame1.particles[2].id == 2 and frame1.particles[2].age == 0,
  "frame one ordering and persistent age")

runtime:step(1)
local frame2 = runtime:snapshot()
ok(frame2.frame == 2 and #frame2.particles == 2,
  "expired frame-zero particle is removed at its lifetime")
ok(frame2.particles[1].id == 2 and frame2.particles[1].age == 1
  and frame2.particles[2].id == 3 and frame2.particles[2].born == 2,
  "frame two birth and expiry ordering")

runtime:step(2)
local frame4 = runtime:snapshot()
ok(frame4.frame == 4 and #frame4.particles == 0,
  "all finite-lifetime particles expire")

local second = assert(runtime:trigger({moveId = 7, alternate = true}))
ok(second == 2, "effect IDs are monotonic after expiry")
ok(runtime:snapshot().particles[1].id == 4,
  "particle IDs are monotonic and never reused")

local clock = Runtime.new({catalog = catalog, lifetimeResolver = function() return 4 end})
assert(clock:trigger({moveId = 7}))
clock:update(1 / 30)
ok(clock:snapshot().frame == 1, "presentation update advances one 30 Hz tick")
clock:update(0)
ok(clock:snapshot().frame == 1, "zero update is a no-op")
local limited = Runtime.new({catalog = catalog, catchUpLimit = 1,
  lifetimeResolver = function() return 99 end})
assert(limited:trigger({moveId = 7}))
limited:update(1)
ok(limited:snapshot().frame == 1 and limited:snapshot().accumulator > 28,
  "catch-up limit preserves surplus accumulator ticks")

local unresolved = Runtime.new({catalog = catalog})
assert(unresolved:trigger({moveId = 7}))
local unresolvedSnapshot = unresolved:snapshot()
ok(unresolvedSnapshot.particles[1].lifetime == nil,
  "unresolved lifetime remains nil")
ok(unresolvedSnapshot.diagnostics[1].code == "unsupported-lifetime",
  "unresolved lifetime emits a stable diagnostic")
unresolved:step(257)
ok(#unresolved:snapshot().particles==0,
  "ordinary unresolved particles still leave at the native age-byte endpoint")

local unsupportedCatalog = {
  programs = {},
  moves = {[1] = {primaryDispatch = {{kind = "lifecycle", lifecycleId = 4}}}},
}
local unsupported = Runtime.new({catalog = unsupportedCatalog})
assert(unsupported:trigger({moveId = 1}))
ok(unsupported:snapshot().diagnostics[1].code == "unsupported-lifecycle-callback"
  and unsupported:snapshot().diagnostics[1].effectId == 1
  and unsupported:snapshot().diagnostics[1].programId == nil,
  "lifecycle manager diagnostic retains dispatch context")

local invalid = Runtime.new({catalog = catalog})
local invalidStep = pcall(function() invalid:step(-1) end)
ok(not invalidStep, "negative step count is an error")
local fractionalStep = pcall(function() invalid:step(1.5) end)
ok(not fractionalStep, "fractional step count is an error")

print(("%d checks passed (Stadium 2 battle FX runtime)"):format(checks))
