-- Stadium 2 fragment-79 controller interpreter.
-- This reproduces its synchronous opcode walk and returns the scheduler
-- objects registered by emitter opcodes. It does not invent move families.
local Native = {}

local function copy(value, seen)
  if type(value) ~= "table" then return value end
  seen = seen or {}
  if seen[value] then return seen[value] end
  local out = {}
  seen[value] = out
  for key, child in pairs(value) do
    out[copy(key, seen)] = copy(child, seen)
  end
  return out
end

local function seekBranch(records,index,condition)
  local branch=0
  for cursor=index+1,#records do
    local opcode=records[cursor].opcode
    if opcode==10 then
      if branch==condition then return cursor end
      branch=branch+1
    elseif opcode==3 or opcode==0 then
      return cursor
    end
  end
  return #records+1
end

local function seekEnd(records,index)
  for cursor=index+1,#records do
    local opcode=records[cursor].opcode
    if opcode==3 or opcode==0 then return cursor end
  end
  return #records+1
end

function Native.execute(program,context)
  context=type(context)=="table" and context or {}
  local records=program and program.records or {}
  local condition=math.max(0,math.floor(tonumber(context.condition) or 0))
  local alternate=context.alternate==true
  local scheduled,calls,visited,diagnostics={},{},{},{}
  local function missing(record,code,message)
    diagnostics[#diagnostics+1]={code=code,severity="warning",kind="program",
      programId=program and program.id,address=record.address,
      opcode=record.opcode,message=message}
  end
  -- D_84190178: 84107CEC (opcode 1) and 84107D24 (opcode 3) clear it,
  -- 84108630 (opcode 17) sets it. nil means this program left it unchanged.
  local markerSelect
  local index,steps=1,0
  while index<=#records and steps<4096 do
    steps=steps+1
    local record=records[index]
    visited[#visited+1]=index
    local opcode=record.opcode
    if opcode==1 then markerSelect=0 end
    if opcode==0 then break
    elseif opcode==3 then
      condition=0
      markerSelect=0
    elseif opcode==9 then
      index=seekBranch(records,index,condition)
    elseif opcode==11 then
      index=seekEnd(records,index)
    elseif opcode==12 then
      calls[#calls+1]={handler=record.argument,argument=record.argument2,
        argument2=record.argument3,address=record.address}
      missing(record,"unsupported-native-program-call",
        "opcode 12 callback is decoded but not executed")
    elseif opcode==16 then
      if type(context.conditionForMove)=="function" then
        local ok,value=pcall(context.conditionForMove,context.moveId,context,record,condition)
        value=ok and tonumber(value) or nil
        if value and value>=0 and value<math.huge and value==math.floor(value) then
          condition=value
        else
          missing(record,"invalid-native-condition",
            "opcode 16 resolver failed or returned no nonnegative integer; using current branch")
        end
      else
        missing(record,"unsupported-native-condition",
          "opcode 16 requires native species/battle-state branch selection (841083B0); using current branch")
      end
    elseif opcode==17 then
      alternate=true
      markerSelect=1
    elseif opcode~=1 and opcode~=2 and opcode~=10
        and not record.emitter then
      missing(record,"unsupported-native-opcode",
        "native program command has no implemented handler or decoded emitter")
    end
    if record.emitter then
      local emitter = record.emitter
      local event = {
        opcode=opcode, mode=emitter.mode,
        descriptor=emitter.descriptor,
        descriptorKind=emitter.descriptorKind,
        alternate=alternate, address=record.address,
      }
      if emitter.descriptorKind == "native-object" then
        -- Native-object commands are not common particle descriptors. Keep
        -- their encoded command and resolver state intact for the scheduler.
        event.commandPointer = emitter.commandPointer
        event.encodedObjectRaw = copy(emitter.encodedObjectRaw)
        event.delayOffset = emitter.delayOffset
        event.encodedDelay = emitter.encodedDelay
        event.nativeColorTrack = copy(emitter.nativeColorTrack)
        event.nativeModelColor = copy(emitter.nativeModelColor)
        event.resolvedObject = copy(emitter.resolvedObject)
        event.resolution = copy(emitter.resolution)
      else
        event.shapeId=emitter.shapeId
        event.start=emitter.start or 0
        event.interval=emitter.interval or 0
        event.repeats=emitter.repeats or 1
        event.particleCount=emitter.particleCount
        event.flags=emitter.flags; event.flags2=emitter.flags2
        event.geometryPointer=emitter.geometryPointer
        event.transformPointer=emitter.transformPointer
        event.materialPointer=emitter.materialPointer
        event.geometry=emitter.geometry; event.transform=emitter.transform
        event.material=emitter.material
        event.attachment=emitter.attachment
      end
      scheduled[#scheduled+1] = event
    end
    index=index+1
  end
  return {programId=program and program.id,scheduled=scheduled,calls=calls,
    condition=condition,alternate=alternate,nativeMarkerSelect=markerSelect,
    visited=visited,diagnostics=diagnostics}
end

function Native.births(execution,previousFrame,frame)
  previousFrame=tonumber(previousFrame) or -1
  frame=tonumber(frame) or 0
  local out={}
  for schedulerIndex,event in ipairs(execution and execution.scheduled or {}) do
    -- Native-object commands have no common particle timing header. Their
    -- dedicated manager owns the resolved delay, but mixed execution scans
    -- must remain total and harmless here.
    local repeats=event.repeats or 1
    local interval=event.interval or 0
    local start=event.start or 0
    if repeats==0xFF then
      repeats=interval>0 and math.floor(frame/interval)+1 or 1
    end
    for repeatIndex=0,math.max(0,repeats-1) do
      local born=start+interval*repeatIndex
      if born>previousFrame and born<=frame then
        out[#out+1]={schedulerIndex=schedulerIndex,event=event,
          repeatIndex=repeatIndex,born=born,age=frame-born}
      end
    end
  end
  return out
end

-- func_84106540 selects authored table entries from the scheduler generation
-- and the particle's index within that generation. Modes 4/5 differ later in
-- how Stadium applies the selected vector, but their table index is identical
-- to modes 3/2 respectively.
function Native.selectorIndex(mode,generation,particle,particleCount)
  mode=math.floor(tonumber(mode) or 0)
  generation=math.floor(tonumber(generation) or 0)
  particle=math.floor(tonumber(particle) or 0)
  particleCount=math.max(1,math.floor(tonumber(particleCount) or 1))
  if mode==2 or mode==5 then return generation*particleCount+particle end
  if mode==3 or mode==4 then return particle end
  if mode==6 then return generation end
  return 0
end

local function selected(entries,mode,generation,particle,count)
  if type(entries)~="table" then return nil end
  return entries[Native.selectorIndex(mode,generation,particle,count)+1]
end

-- Expand scheduler births into the exact number of common particles Stadium
-- creates. This resolves only deterministic ROM table selection; random
-- rotation/motion specs remain attached for the runtime RNG to evaluate.
function Native.particles(execution,previousFrame,frame)
  local out={}
  for _,birth in ipairs(Native.births(execution,previousFrame,frame)) do
    local event=birth.event
    if event.descriptorKind=="particle" then
      local count=math.max(0,tonumber(event.particleCount) or 0)
      local geometry=event.geometry or {}
      local selectors=geometry.selectors or {}
      for particle=0,count-1 do
        local angles=selected(geometry.positionEntries,selectors.position,
          birth.repeatIndex,particle,count)
        if geometry.nativeGeometry and (selectors.position==4 or selectors.position==5) then
          local first=geometry.positionEntries and geometry.positionEntries[1]
          local index=Native.selectorIndex(selectors.position,birth.repeatIndex,particle,count)
          if first then angles={first[1]*index,first[2]*index,first[3]*index} end
        end
        local offset=selected(geometry.velocityEntries,selectors.velocity,
          birth.repeatIndex,particle,count)
        local position,velocity=angles,offset
        if geometry.nativeGeometry then position,velocity=offset,nil end
        out[#out+1]={
          schedulerIndex=birth.schedulerIndex,event=event,
          generation=birth.repeatIndex,particleIndex=particle,
          born=birth.born,age=birth.age,
          scale=selected(geometry.scaleEntries,selectors.scale,
            birth.repeatIndex,particle,count),
          nativeGeometry=geometry.nativeGeometry,
          rotation=geometry.nativeGeometry and angles or nil,
          position=position,
          velocity=velocity,
          attribute=selected(geometry.attributeEntries,selectors.attribute,
            birth.repeatIndex,particle,count),
          transform=event.transform,material=event.material,
        }
      end
    end
  end
  return out
end

return Native
