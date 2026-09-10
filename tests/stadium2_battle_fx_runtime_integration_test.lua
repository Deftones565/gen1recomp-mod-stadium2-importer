package.path="./?.lua;./?/init.lua;"..package.path
local Runtime=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_runtime")
local Native=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_native")
local checks=0;local function ok(v,m)checks=checks+1;if not v then error("FAIL "..m,0) end end

local common={mode=0,descriptor=0x84170000,descriptorKind="particle",start=0,interval=0,repeats=1,particleCount=1,flags=0x80,flags2=0,geometry={selectors={scale=1,position=1,velocity=1,attribute=1},scaleEntries={{scale=1,lifetime=99}},positionEntries={{1,2,3}},velocityEntries={{0,0,0}},attributeEntries={0}},transform={},material={address=0x84171000,shapeId=47,secondaryShapeId=0},attachment={flags=0x80,flags2=0}}
local object={mode=2,descriptorKind="native-object",commandPointer=0x8416A3E0,encodedObjectRaw="0123456789abcdef",delayOffset=3,encodedDelay=0x23,resolvedObject=nil,resolution={status="unresolved",resolver=0x80003240}}
local program={id=98,records={{opcode=4,address=0x84173000,emitter=common},{opcode=5,address=0x84173008,emitter=object},{opcode=0,address=0x84173010}}}
local execution=Native.execute(program,{moveId=60})
local encoded=execution.scheduled[2]
ok(encoded.commandPointer==object.commandPointer and encoded.encodedObjectRaw==object.encodedObjectRaw,"Native retains native-object command evidence")
ok(encoded.delayOffset==3 and encoded.encodedDelay==0x23 and encoded.resolution.status=="unresolved","Native retains delay and resolution evidence")
encoded.resolution.status="mutated";ok(object.resolution.status=="unresolved","Native output is detached")

local order={};local function push(x)order[#order+1]=x end
local motion={}
function motion.init(source) push("motion:init");return{age=source.age or 0,lifetime=5,alive=true,position=source.position,velocity={0,0,0},rotation={0,0,0},scale={1,1,1},diagnostics={}} end
function motion.step(state) push("motion");local out={};for k,v in pairs(state)do out[k]=v end;out.age=state.age+1;return out end
local material={}
function material.init(source,context) push("material:init");return{age=0,shapeId=source.shapeId,primaryShapeId=source.shapeId,diagnostics={},contextEffect=context.effectId} end
function material.step(state) push("material");local out={};for k,v in pairs(state)do out[k]=v end;out.age=state.age+1;return out end
function material.snapshot(state)local out={};for k,v in pairs(state)do out[k]=v end;return out end

local catalog={programs={[98]=program},lifecycle={[7]={init=0x84156BD4,update=0x84156C40,draw=0x84156C60}},moves={[60]={primaryDispatch={{kind="program",programId=98},{kind="lifecycle",lifecycleId=7}},alternateDispatch={}}}}
local runtime=Runtime.new({catalog=catalog,motion=motion,material=material,
  nativeObjectOptions={resolve=function(pointer,event)
    ok(pointer==0x8416A3E0 and event.effectId==1 and event.programId==98,"native resolver receives effect/program context")
    return{object={pointer=pointer},delay=0}
  end,callbacks={[2]=function(object,slot,event)push("native");ok(event.address==0x84173008,"native callback retains record address");return 0 end}},
  lifecycleOptions={callback=function(phase,address,instance,context)
    push("lifecycle:"..phase);ok(context.effectId==1 and context.familyId==7,"lifecycle receives effect/family context");return 0
  end}})
local id=assert(runtime:trigger({moveId=60,sourceSide="player",targetSide="enemy"}))
ok(id==1,"integrated effect ID")
local initial=runtime:snapshot()
ok(#initial.particles==1 and initial.particles[1].id==1,"common particle persists at frame zero")
ok(#initial.nativeObjects.slots==1 and initial.nativeObjects.slots[1].mode==2,"native object scheduled once")
ok(#initial.lifecycles.instances==1 and initial.lifecycles.instances[1].familyId==7,"lifecycle spawned once")
ok(#initial.materials==1 and initial.materials[1].particleId==1,"material state is snapshot-visible")
ok(initial.particles[1]._motionState==nil and initial.particles[1]._materialState==nil,"snapshot strips evaluator internals")

order={};runtime:step(1)
ok(table.concat(order,",")=="motion,material,native,lifecycle:update","tick order is common motion/material then native then lifecycle")
local frame1=runtime:snapshot()
ok(frame1.frame==1 and frame1.particles[1].age==1,"common state advances once")
ok(frame1.materials[1].state.age==1,"material advances once")
ok(frame1.nativeObjects.slots[1].age==0,"non-positive native result retains slot")
ok(frame1.lifecycles.instances[1].frame==1,"lifecycle advances once")

frame1.nativeObjects.slots[1].object.pointer=0
frame1.lifecycles.instances[1].context.sourceSide="mutated"
local detached=runtime:snapshot()
ok(detached.nativeObjects.slots[1].object.pointer==0x8416A3E0,"native snapshot is detached")
ok(detached.lifecycles.instances[1].context.sourceSide=="player","lifecycle snapshot is detached")
local before=#runtime:snapshot().particles;runtime:snapshot();ok(#runtime:snapshot().particles==before,"snapshot is pure")
ok(runtime:release() and #runtime:snapshot().particles==0,"release clears integrated state")

-- The default runtime owns a separate ROM random stream.  Exercise the
-- decoded mode 0/1 transform path and prove it does not consume host RNG.
local hostRngCalls=0
local randomCommon={mode=0,descriptor=0x84174000,descriptorKind="particle",
  start=0,interval=0,repeats=1,particleCount=1,flags=0x80,flags2=0,
  geometry={selectors={scale=1,position=1,velocity=1,attribute=1},
    scaleEntries={{scale=1,lifetime=99}},positionEntries={{0,0,0}},
    velocityEntries={{0,0,0}},attributeEntries={0}},
  transform={rotationOffset={mode=0,values={2,0,-1}},
    directionalVelocity={mode=1,values={3,5,7}}},
  material={address=0x84175000,shapeId=47,secondaryShapeId=0},
  attachment={flags=0x80,flags2=0}}
local randomProgram={id=99,records={{opcode=4,address=0x84176000,
  emitter=randomCommon},{opcode=0,address=0x84176018}}}
local randomRuntime=Runtime.new({catalog={programs={[99]=randomProgram},
  moves={[61]={primaryDispatch={{kind="program",programId=99}},alternateDispatch={}}}},
  rng=function() hostRngCalls=hostRngCalls+1;return 0 end,
  randomOptions={seed=1}})
assert(randomRuntime:trigger({moveId=61}))
local randomParticle=randomRuntime:snapshot().particles[1]
ok(randomParticle.rotation[1]~=0 and randomParticle.rotation[2]==0
  and randomParticle.velocity[1]~=0,
  "default ROM random helpers evaluate decoded mode 0/1 vectors")
ok(hostRngCalls==0,"battle RNG is isolated from battle FX random motion")
local overrideRuntime=Runtime.new({catalog={programs={[99]=randomProgram},
  moves={[61]={primaryDispatch={{kind="program",programId=99}},alternateDispatch={}}}},
  motionOptions={randomScalar=function(variant,bound)
    return variant==0 and 17 or 19
  end}})
assert(overrideRuntime:trigger({moveId=61}))
local overrideParticle=overrideRuntime:snapshot().particles[1]
ok(overrideParticle.rotation[1]==17 and overrideParticle.velocity[1]==19,
  "explicit motion random resolver overrides the default ROM stream")
local sentinelRandom=Runtime.new({randomOptions={seed=1}})
local sentinel=sentinelRandom.motion.init({transform={rotationOffset={mode=0,
  values={-1,0,0}}}},sentinelRandom.motionOptions)
ok(sentinel.rotation[1]~=0,"ROM -1 random bound reaches the scalar sentinel path")
print(("%d checks passed (Stadium 2 battle FX runtime integration)"):format(checks))
