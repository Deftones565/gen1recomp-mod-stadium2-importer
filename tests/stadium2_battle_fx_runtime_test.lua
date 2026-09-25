package.path = "./?.lua;./?/init.lua;" .. package.path

local Runtime = require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_runtime")
local Native = require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_native")
local Random = require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_random")

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

local signalEmitter=emitter(0,0,1)
signalEmitter.flags=0x10
signalEmitter.material={shapeId=47,nativeAlphaInitial=255,
  nativeAlphaRamp={target=0,step=100,startAge=2}}
local signalCatalog={programs={[1]={id=1,records={
  {opcode=4,address=0x84170000,emitter=signalEmitter},
  {opcode=0,address=0x84170008}}}},moves={[1]={
  primaryDispatch={{kind="program",programId=1}}}}}
local signalRuntime=Runtime.new({catalog=signalCatalog,
  lifetimeResolver=function() return 10 end})
assert(signalRuntime:trigger({moveId=1}))
local function alphaWarning(snapshot)
  for _,diagnostic in ipairs(snapshot.diagnostics) do
    if diagnostic.code=="unsupported-alpha-gate" then return true end
  end
  return false
end
ok(not alphaWarning(signalRuntime:snapshot()),
  "common material reads the lifecycle presentation signal at birth")
signalRuntime:step(1)
ok(signalRuntime:snapshot().particles[1].material.nativeAlpha==255,
  "inactive presentation signal holds the common alpha ramp")
signalRuntime.lifecycle:setNativeSignal(1)
signalRuntime:step(1)
ok(signalRuntime:snapshot().particles[1].material.nativeAlpha==255,
  "first active signal tick advances the authored gate counter")
signalRuntime:step(1)
ok(signalRuntime:snapshot().particles[1].material.nativeAlpha==155
    and not alphaWarning(signalRuntime:snapshot()),
  "second active signal tick starts the ROM alpha ramp")
local finishedRuntime=Runtime.new({catalog=signalCatalog,
  lifetimeResolver=function() return 10 end})
local finishedEffect=assert(finishedRuntime:trigger({moveId=1}))
ok(finishedRuntime.lifecycle:finishEffect(finishedEffect),
  "host move completion reaches the lifecycle signal owner")
finishedRuntime:step(2)
ok(finishedRuntime:snapshot().particles[1].material.nativeAlpha==155,
  "move completion also opens the common-particle alpha gate")

local sharedEmitter=emitter(0,1,2)
sharedEmitter.particleCount=3
sharedEmitter.transform={rotationOffset={mode=4,values={100,200,300}}}
local sharedCatalog={trigTables={tableA=function()return 0 end,
  tableB=function()return 1 end},programs={[1]={id=1,records={
  {opcode=4,address=0x84170000,emitter=sharedEmitter},
  {opcode=0,address=0x84170008}}}},moves={[1]={
  primaryDispatch={{kind="program",programId=1}}}}}
local sharedRuntime=Runtime.new({catalog=sharedCatalog,
  randomOptions={seed=0x1234},lifetimeResolver=function()return 10 end})
local oracle=Random.new({seed=0x1234})
local function expectedVector()
  return {oracle:scalar(0,100),oracle:scalar(0,200),oracle:scalar(0,300)}
end
local firstVector=expectedVector()
assert(sharedRuntime:trigger({moveId=1}))
local firstBurst=sharedRuntime:snapshot().particles
ok(#firstBurst==3,"mode-4 native burst spawns all sibling particles")
for index=1,3 do
  ok(firstBurst[index].rotation[1]==firstVector[1]
    and firstBurst[index].rotation[2]==firstVector[2]
    and firstBurst[index].rotation[3]==firstVector[3],
    "mode-4 siblings reuse one isolated three-sample vector")
end
local secondVector=expectedVector()
sharedRuntime:step(1)
local secondBurst=sharedRuntime:snapshot().particles
ok(#secondBurst==6 and secondBurst[4].rotation[1]==secondVector[1]
    and secondBurst[5].rotation[2]==secondVector[2]
    and secondBurst[6].rotation[3]==secondVector[3],
  "next mode-4 burst resamples at particle index zero")

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
local lifetimeWarning=false
for _,row in ipairs(unresolvedSnapshot.diagnostics) do
  if row.code=="unsupported-lifetime" then lifetimeWarning=true end
end
ok(not lifetimeWarning,"ordinary particles use their native byte-age endpoint")
unresolved:step(257)
ok(#unresolved:snapshot().particles==0,
  "ordinary unresolved particles still leave at the native age-byte endpoint")

local unsupportedCatalog = {
  programs = {},
  moves = {[1] = {primaryDispatch = {{kind = "lifecycle", lifecycleId = 16}}}},
}
local unsupported = Runtime.new({catalog = unsupportedCatalog})
assert(unsupported:trigger({moveId = 1}))
ok(unsupported:snapshot().diagnostics[1].code == "unresolved-spike-cannon-model"
  and unsupported:snapshot().diagnostics[1].effectId == 1
  and unsupported:snapshot().diagnostics[1].programId == nil,
  "lifecycle manager diagnostic retains dispatch context")

local missingAnchors = Runtime.new({catalog = {
  programs = {},
  moves = {[1] = {primaryDispatch = {{kind = "lifecycle", lifecycleId = 4}}}},
}})
assert(missingAnchors:trigger({moveId = 1}))
local missingDiagnostic = missingAnchors:snapshot().diagnostics[1]
ok(missingDiagnostic.code == "unresolved-radial-endpoints"
  and missingDiagnostic.effectId == 1 and missingDiagnostic.context.lifecycleId == 4,
  "implemented radial lifecycle reports missing anchors with dispatch context")

local invalid = Runtime.new({catalog = catalog})
local invalidStep = pcall(function() invalid:step(-1) end)
ok(not invalidStep, "negative step count is an error")
local fractionalStep = pcall(function() invalid:step(1.5) end)
ok(not fractionalStep, "fractional step count is an error")

print(("%d checks passed (Stadium 2 battle FX runtime)"):format(checks))
