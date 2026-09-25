package.path = "./?.lua;./?/init.lua;" .. package.path

local Motion = require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_motion")

local checks = 0
local function ok(value, message)
  checks = checks + 1
  if not value then error("FAIL " .. message, 0) end
end

local function near(a, b, message)
  ok(math.abs(a - b) < 1e-9, message .. (" (%.9g ~= %.9g)"):format(a, b))
end

local function hasDiagnostic(state, code)
  for _, row in ipairs(state.diagnostics or {}) do
    if row.code == code then return true end
  end
  return false
end

ok(type(Motion.init) == "function" and type(Motion.step) == "function",
  "motion exposes pure init and one-tick evaluation")
ok(Motion.initialize == Motion.init and Motion.evaluate == Motion.step,
  "motion compatibility aliases are stable")

local particle = {
  shapeId = 47, born = 0, age = 0,
  position = {1, 2, 3}, velocity = {2, -1, 0.5},
  acceleration = {0, 0, -0.5}, rotation = {0, 0, 1},
  angularVelocity = {0.25, 0, 0},
  lifetime = 2, scale = {scale = 0.5, lifetime = 99},
}
local state = Motion.init(particle)
near(state.position[1], 1, "initial position copied")
near(state.scale[1], 0.5, "authored scalar scale expands to three axes")
ok(state.lifetime == 2 and state.authoredLifetime == 99 and state.alive,
  "explicit lifetime wins while raw authored lifetime is retained")
particle.position[1] = 99
ok(state.position[1] == 1, "initialization does not alias input vectors")

local function euler(s, dt, acceleration)
  s.position = {s.position[1] + s.velocity[1] * dt,
    s.position[2] + s.velocity[2] * dt, s.position[3] + s.velocity[3] * dt}
  s.velocity = {s.velocity[1] + acceleration[1] * dt,
    s.velocity[2] + acceleration[2] * dt, s.velocity[3] + acceleration[3] * dt}
  s.rotation = {s.rotation[1] + s.angularVelocity[1] * dt,
    s.rotation[2] + s.angularVelocity[2] * dt, s.rotation[3] + s.angularVelocity[3] * dt}
  return s
end
local frame1 = Motion.step(state, 1, {integrate = euler})
near(frame1.position[1], 3, "one tick integrates position")
near(frame1.position[2], 1, "one tick integrates all position axes")
near(frame1.velocity[3], 0, "one tick integrates acceleration")
near(frame1.rotation[1], 0.25, "one tick integrates rotation")
ok(frame1.age == 1 and frame1.alive, "first tick advances age and remains alive")
ok(state.age == 0 and state.position[1] == 1, "step does not mutate prior state")
local frame2 = Motion.step(frame1, 1, {integrate = euler})
ok(frame2.age == 2 and not frame2.alive, "particle expires at authored lifetime")
local held = Motion.step(frame2, 1, {integrate = euler})
ok(held.age == frame2.age and not held.alive, "expired particle remains quiescent")

local unresolvedLifetime = Motion.init({velocity = {1, 0, 0},nativeAgeEndpoint=false})
ok(unresolvedLifetime.lifetime == nil and unresolvedLifetime.alive,
  "ambiguous lifetime remains nil and alive")
ok(hasDiagnostic(unresolvedLifetime, "unsupported-lifetime"),
  "ambiguous lifetime emits an explicit diagnostic")
local unresolvedAfterTick = Motion.step(unresolvedLifetime, 8)
ok(unresolvedAfterTick.alive and unresolvedAfterTick.age == 8,
  "unresolved lifetime remains alive under evaluator policy")
local rawLifetime = Motion.init({scale = {scale = 0.3, lifetime = 17}})
ok(rawLifetime.authoredLifetime == 17 and rawLifetime.lifetime == nil
  and rawLifetime.alive, "raw scale lifetime is retained but never expires")
ok(not hasDiagnostic(rawLifetime,"unsupported-lifetime"),
  "ordinary native byte-age expiry is a resolved lifetime rule")

-- Fragment 79's common pool increments its byte age in 0x841054D4 before
-- dispatching 0x84101D54/0x841027B4, then 0x8410009C tests exact 0xff.
-- The authored scale-entry +6 value is retained as metadata, never promoted
-- to a Motion lifetime.
local observedControllerAge
local nativeEndpoint = Motion.init({
  nativeAgeEndpoint = true, event = {programId = 259, address = 0x8417B650},
  age = 0xfe, scale = {scale = 0.3, lifetime = 1},
}, {})
ok(nativeEndpoint.lifetime == nil and nativeEndpoint.authoredLifetime == 1
  and nativeEndpoint.nativeYTermination.status == "unresolved",
  "native scale-entry lifetime remains metadata with an explicit Y boundary")
local terminal = Motion.step(nativeEndpoint, 1, {
  integrate = function(state)
    observedControllerAge = state.age
    return state
  end,
})
ok(observedControllerAge == 0xff and terminal.age == 0xff
  and not terminal.alive, "post-increment age 0xff is updated then expires")
local authoredTick = Motion.step(Motion.init({
  nativeAgeEndpoint = true, event = {programId = 259}, age = 0,
  scale = {scale = 0.3, lifetime = 1},
}), 1)
ok(authoredTick.age == 1 and authoredTick.alive and authoredTick.lifetime == nil,
  "authored scale-entry +6 does not expire an ordinary age-1 particle")
local exactEquality = Motion.step(Motion.init({
  nativeAgeEndpoint = true, event = {programId = 259}, age = 0xff,
}), 1)
ok(exactEquality.age == 0 and exactEquality.alive,
  "native endpoint uses exact byte equality rather than age >= 0xff")
local specialEndpoint=Motion.step(Motion.init({
  nativeAgeEndpoint=true,age=0xfe,event={flags=0x10000000},
}),1)
ok(specialEndpoint.age==0xff and specialEndpoint.alive
    and specialEndpoint.nativeYTermination.active,
  "descriptor bit 28 suppresses ordinary expiry while final-Y termination is unresolved")
ok(hasDiagnostic(specialEndpoint,"unsupported-native-y-termination"),
  "special final-Y rule retains an explicit diagnostic")
specialEndpoint=Motion.step(specialEndpoint,1)
ok(specialEndpoint.age==0 and specialEndpoint.alive,
  "flag-0x20000 particles wrap the native age byte after 0xff")
local aboveGround=Motion.init({event={flags=0x10000000},age=0xfe},
  {resolveNativeFinalY=function() return 1 end})
local aboveTick=Motion.step(aboveGround,1)
ok(aboveTick.alive and aboveTick.nativeFinalY==1
    and aboveTick.nativeYTermination.status=="resolved",
  "special particles survive age 255 while their final Y is positive")
local groundTick=Motion.step(aboveTick,1,
  {resolveNativeFinalY=function() return 0 end})
ok(not groundTick.alive and groundTick.age==0,
  "special particles release when the post-update final Y reaches ground")
local controllerAge = Motion.step(Motion.init({
  nativeAgeEndpoint = true, event = {programId = 259}, age = 0,
}), 1, {integrate = function(state)
  observedControllerAge = state.age
  return state
end})
ok(controllerAge.age == 1 and observedControllerAge == 1,
  "controller integration observes post-increment age")

-- Fire-Punch-style transform records carry mode 0 and mode 2 random vectors.
-- Scalar mode 0/1 calls preserve the ROM's variant and component order.
local oldRandom = math.random
math.random = function() error("global RNG must not be called") end
local scalarCalls = {}
local randomState = Motion.init({
  effectId = 9, programId = 259, address = 0x8417B650,
  age = 4, generation = 3, angleContext = {x = 16, y = 32, z = 48},
  position = {0, 0, 0}, velocity = {1, 1, 1}, rotation = {1, 1, 1},
  transform = {
    rotationOffset = {mode = 0, values = {2, 0, -1}},
    directionalVelocity = {mode = 1, values = {3, 5, 7}},
  },
}, {
  rng = function() error("injected RNG must only be passed through context") end,
  randomScalar = function(variant, bound, context)
    scalarCalls[#scalarCalls + 1] = {variant = variant, bound = bound,
      context = context}
    return bound
  end,
})
math.random = oldRandom
near(randomState.rotation[1], 3, "mode 0 uses variant 0 in X order")
near(randomState.rotation[2], 1, "zero bound contributes zero")
near(randomState.rotation[3], 65537, "signed -1 bound normalizes to 65536")
near(randomState.velocity[1], 4, "mode 1 uses variant 1 in X order")
near(randomState.velocity[2], 6, "mode 1 scales Y bound")
near(randomState.velocity[3], 8, "mode 1 scales Z bound")
ok(#scalarCalls == 5 and scalarCalls[1].variant == 0
  and scalarCalls[1].bound == 2 and scalarCalls[2].bound == 65536
  and scalarCalls[3].variant == 1 and scalarCalls[5].context.component == 3,
  "scalar resolver receives variant/order/bounds/component")
ok(scalarCalls[1].context.effectId == 9
  and scalarCalls[1].context.programId == 259
  and scalarCalls[1].context.address == 0x8417B650
  and scalarCalls[1].context.age == 4
  and scalarCalls[1].context.channel == "rotation-offset"
  and scalarCalls[1].context.angle.x == 16
  and scalarCalls[1].context.rng ~= nil,
  "scalar resolver receives effect/program/address/age/channel/angles/RNG")

local vectorModeCalls = 0
local directional = Motion.init({
  velocity = {1, 1, 1}, transform = {
    directionalVelocity = {mode = 2, values = {3, 5, 7}},
  },
}, {randomVector = function(mode, values, context)
  vectorModeCalls = vectorModeCalls + 1
  ok(mode == 2 and values[1] == 3 and context.channel == "directional-velocity",
    "mode 2 remains behind the external vector resolver")
  return {3, 5, 7}
end
})
near(directional.velocity[1], 4, "mode 2 resolver adds X")
near(directional.velocity[2], 6, "mode 2 resolver adds Y")
near(directional.velocity[3], 8, "mode 2 resolver adds Z")
ok(vectorModeCalls == 1, "mode 2 calls the vector resolver once")
local noGeometry=Motion.init({event={descriptorKind="particle"},
  transform={directionalVelocity={mode=1,values={3,5,7}}}},
  {randomScalar=function(_,bound) return bound end})
ok(noGeometry.position[1]==3 and noGeometry.position[2]==5
    and noGeometry.position[3]==7 and noGeometry.velocity[1]==0,
  "native directional sample initializes position without a geometry block")
noGeometry=Motion.step(noGeometry,1)
ok(not hasDiagnostic(noGeometry,"unsupported-motion-integration"),
  "geometry-less native constructor does not invent per-tick velocity")

local missingResolver = Motion.init({
  transform = {rotationOffset = {mode = 0, values = {1, 1, 1}}},
})
ok(hasDiagnostic(missingResolver, "unsupported-random-scalar"),
  "random arithmetic without disassembly evidence is explicit")
near(missingResolver.rotation[1], 0, "unsupported random vector does not invent an offset")
local randomDiagnostic = missingResolver.diagnostics[1]
for _, field in ipairs({"code", "severity", "effectId", "programId", "address", "kind", "message"}) do
  ok(randomDiagnostic[field] ~= nil or field == "effectId" or field == "programId"
    or field == "address", "diagnostic schema includes " .. field)
end

local tracked = Motion.init({position={1,2,3},rotation={0,0,0},
  transform={
    rotationTracks={{flags=0,startAge=1,endAge=0,target=6,random=0,step=2}},
    positionTracks={{startAge=1,endAge=0,random=5,step=2}},
  },
})
local tracked1=Motion.step(tracked,1)
near(tracked1.rotation[1],2,"ROM angle track advances on its start tick")
near(tracked1.position[1],3,"ROM position track advances the base position")
local tracked2=Motion.step(tracked1,1)
near(tracked2.rotation[1],4,"ROM angle track retains its velocity")
near(tracked2.position[1],5,"ROM position track clamps at its target")
local trackedAxes=Motion.init({transform={motionAxes=0x84178F5C,
  positionTracks={{startAge=1,endAge=0,random=5,step=2}}}})
local trackedAxesTick=Motion.step(trackedAxes,1)
ok(not hasDiagnostic(trackedAxesTick,"unsupported-controller"),
  "decoded position tracks consume their native axis pointer")
local spawnCalls=0
local spawnedTrack=Motion.init({position={3,0,0},nativeSpawnScale=1,
  transform={positionTracks={{address=0x8417EA5C,flags=1,startAge=0,
    endAge=0,target=40,random=0,step=4,spawnRandom=40}}}},
  {randomScalar=function(variant,bound,context)
    spawnCalls=spawnCalls+1
    ok(variant==1 and bound==40 and context.channel=="position-track-spawn",
      "position-track spawn uses its centered ROM bound")
    return 0
  end})
ok(spawnCalls==1 and spawnedTrack.position[1]==43
    and not hasDiagnostic(spawnedTrack,"unresolved-position-track-initial"),
  "position-track spawn adds the sampled model-scaled offset")
local spawnTick=Motion.step(spawnedTrack,1)
near(spawnTick.position[1],39,"position-track update approaches zero from spawn offset")
local rotationCalls={}
local sampled=Motion.init({transform={rotationTracks={
  {flags=0x100,startAge=1,endAge=0,target=100,random=3,step=10},
  {flags=0x200,startAge=1,endAge=0,target=100,random=3,step=10},
  {flags=0,startAge=1,endAge=0,target=100,random=3,step=10},
}}},{randomScalar=function(variant,bound,context)
  rotationCalls[#rotationCalls+1]={variant,bound,context.component}
  return variant==0 and 3 or -2
end})
sampled=Motion.step(sampled,1)
ok(#rotationCalls==3 and rotationCalls[1][1]==0
    and rotationCalls[2][1]==1 and rotationCalls[3][1]==1,
  "three native angle random-start flag modes use their authored helpers")
near(sampled.angularVelocity[1],13,"mode 0x100 adds variant-zero sample")
near(sampled.angularVelocity[2],-12,"mode 0x200 subtracts base after negative sample")
near(sampled.angularVelocity[3],8,"default mode adds variant-one sample")

local unknown = Motion.init({
  transform = {
    frameRule = {mode = 2, value = 0},
    motionController = 0x84123456,
  },
})
ok(hasDiagnostic(unknown, "invalid-frame-rule"),
  "zero frame modulo divisor is explicit")
local unknownTick = Motion.step(unknown, 1)
ok(hasDiagnostic(unknownTick, "unsupported-controller"),
  "opaque motion pointer is explicit on evaluation")

local resolved = Motion.init({
  velocity = {1, 0, 0},
  transform = {motionController = 0x1234, motionAxes = {mask = {true, false, true}}},
}, {resolveController = function(pointer, kind)
  ok(pointer == 0x1234 and kind == "motion", "controller resolver receives pointer and kind")
  return {acceleration = {1, 2, 3}}
end})
local resolvedTick = Motion.step(resolved, 1, {
  resolveController = function(pointer, kind)
    if kind == "motion" then return {acceleration = {1, 2, 3}} end
    return nil
  end,
  integrate = euler,
})
near(resolvedTick.position[1], 1, "resolved motion integrates prior velocity")
near(resolvedTick.velocity[1], 2, "resolved acceleration updates velocity")
near(resolvedTick.velocity[2], 0, "motion axes mask suppresses disabled axis")
near(resolvedTick.velocity[3], 3, "motion axes mask applies enabled axis")

local frameRuleState = Motion.init({generation = 3,
  transform = {frameRule = {mode = 1, value = 4}}})
ok(frameRuleState.frame == 13, "frame mode 1 uses generation, not particle age")
local frameRuleTick = Motion.step(frameRuleState, 1)
ok(frameRuleTick.age == 0 and frameRuleTick.frame == 13
    and frameRuleTick.nativeHoldCountdown==12,
  "native frame rule holds age while its countdown advances")
local moduloFrame = Motion.init({generation = 5,
  transform = {frameRule = {mode = 2, value = 2}}})
ok(moduloFrame.frame == 2, "frame mode 2 uses generation modulo value")
local delayOne=Motion.step(moduloFrame,1)
local delayTwo=Motion.step(delayOne,1)
local delayThree=Motion.step(delayTwo,1)
ok(delayOne.age==0 and delayOne.nativeHoldCountdown==1
    and delayTwo.age==0 and delayTwo.nativeHoldCountdown==0
    and delayThree.age==1,
  "countdown releases the hold before the following age increment")
local frameScalarCalls = 0
local externalFrame = Motion.init({generation = 9,
  transform = {frameRule = {mode = 3, value = 7}}}, {
  rng = function() return 0.5 end,
  randomScalar = function(variant, bound, context)
    frameScalarCalls = frameScalarCalls + 1
    ok(variant == 0 and bound == 7 and context.channel == "frame",
      "frame mode 3 calls scalar variant 0 with context")
    return 23
  end,
})
ok(externalFrame.frame == 23 and frameScalarCalls == 1,
  "frame mode 3 returns the external scalar result")
local externalFrameTick = Motion.step(externalFrame, 1)
ok(externalFrameTick.frame == 23 and frameScalarCalls == 1,
  "frame mode 3 resolver is not reapplied during ordinary ticks")
local authoredFrame = Motion.init({generation = 99,
  transform = {frameRule = {mode = 42, value = 9}}})
ok(authoredFrame.frame == 9, "other frame modes return authored value")
local nativeScale=Motion.init({scale={scale=0.3,nativeScaleUpdate={
  initial=300,target=500,step=100,startAge=1}},transform={
  scaleController=0x841762C4,nativeScaleCurve={address=0x841762C4,
    times={0,2,4},values={200,400,600},loop=false,
    percentRandom=0,percentBase=0}}})
nativeScale=Motion.step(nativeScale,1)
ok(math.abs(nativeScale.nativeScalar-0.3)<1e-6,
  "native scale curve overrides the geometry size ramp at age one")
ok(not hasDiagnostic(nativeScale,"unsupported-motion-integration"),
  "decoded scale curve resolves its update controller")
local sampledScale=Motion.init({transform={nativeScaleCurve={
  times={0,2},values={200,200},loop=true,period=2,
  percentRandom=100,percentBase=1000}}},
  {randomScalar=function(variant,bound,context)
    ok(variant==1 and bound==100 and context.channel==
      "native-scale-curve-percent","scale curve uses variant-one percentage")
    return 100
  end})
sampledScale=Motion.step(sampledScale,1)
ok(math.abs(sampledScale.nativeScalar-0.22)<1e-6,
  "scale curve applies its sampled percentage")
local loopingScale=Motion.init({transform={nativeScaleCurve={
  times={0,2},values={100,200},loop=true,period=2,
  percentRandom=0,percentBase=0}}})
for _=1,3 do loopingScale=Motion.step(loopingScale,1) end
ok(math.abs(loopingScale.nativeScalar-0.15)<1e-6,
  "scale curve interpolates at wrapped age")
local zeroStart=Motion.step(Motion.init({rotation={0,0,5},
  transform={rotationTracks={[3]={address=0x8417D638,flags=1,
    startAge=0,endAge=0,target=0,random=0,step=8192}}}}),1)
ok(zeroStart.rotation[3]==5 and not hasDiagnostic(zeroStart,
  "unsupported-rotation-track-start"),
  "age-zero angle row retains the initialized increment after byte-age advances")

-- 8410119C samples the authored speed curve once per age tick, then applies
-- the constructor's percentage before native direction mode 7 moves it.
local curveOptions={trigTables={tableA=function() return 0 end,
  tableB=function() return 1 end}}
local curve=Motion.init({nativeMotion={direction={mode=7,curve={
  times={0,7,15},values={1000,200,0},loop=false,
  percentRandom=0,percentBase=0,
}}}})
for _=1,7 do curve=Motion.step(curve,1,curveOptions) end
near(curve.nativeMotionSpeed,2,"curve speed reaches the authored keyframe")
ok(curve.nativeMotionOffset[3]>2 and not hasDiagnostic(curve,
  "unsupported-native-motion-curve"),
  "curve drives persistent mode-7 movement without a fallback warning")
for _=8,20 do curve=Motion.step(curve,1,curveOptions) end
near(curve.nativeMotionSpeed,0,"non-looping curve holds its final speed")
local sampled=Motion.init({nativeMotion={direction={mode=7,curve={
  times={0,2},values={1000,1000},loop=true,period=2,
  percentRandom=30,percentBase=100,
}}}}, {randomScalar=function(variant,bound,context)
  ok(variant==0 and bound==30 and context.channel==
    "native-motion-curve-percent","curve uses native variant-0 percentage")
  return 10
end})
sampled=Motion.step(sampled,1,curveOptions)
near(sampled.nativeMotionSpeed,11,"sampled curve percentage scales speed")
local loopingSpeed=Motion.init({nativeMotion={direction={mode=7,curve={
  times={0,2},values={100,200},loop=true,period=2,
  percentRandom=0,percentBase=0}}}})
for _=1,3 do loopingSpeed=Motion.step(loopingSpeed,1,curveOptions) end
near(loopingSpeed.nativeMotionSpeed,2.5,
  "speed curve selects wrapped segment but interpolates at native byte age")

local snapshot = Motion.snapshot(frame1)
ok(snapshot._rng == nil and snapshot.particle == nil,
  "snapshot strips evaluator internals")
near(snapshot.position[1], 3, "snapshot preserves evaluated state")

print(("%d checks passed (Stadium 2 battle FX motion)"):format(checks))
