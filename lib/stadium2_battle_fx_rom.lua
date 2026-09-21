-- Lossless reader for Pokemon Stadium 2 (US) battle-effect routing.
--
-- This module intentionally does not invent visual categories.  It exposes
-- the ROM-authored dispatch routes and resource preload lists, the native bytecode records and
-- the lifecycle callback tables used by fragment 79.  Rendering code must
-- consume these records; it must never replace them with type-coloured stand
-- ins.

local FxRom = {}

FxRom.ROM_BASE = 0x36F890
FxRom.VRAM_BASE = 0x84100000
FxRom.MOVE_TABLE = 0x84182A5C
FxRom.MOVE_COUNT = 251
FxRom.PROGRAM_TABLE = 0x84182154
FxRom.PROGRAM_COUNT = 395
FxRom.SEQUENCE_TABLE = 0x84182A30
FxRom.SEQUENCE_COUNT = 11
FxRom.VARIANT_TABLE = 0x84182A18
FxRom.VARIANT_COUNT = 6
FxRom.OPCODE_TABLE = 0x8416A218
FxRom.OPCODE_COUNT = 18
FxRom.LIFECYCLE_COUNT = 30
FxRom.LIFECYCLE_INIT = 0x84183700
FxRom.LIFECYCLE_UPDATE = 0x84183778
FxRom.LIFECYCLE_DRAW = 0x841837F0
-- Main-segment sine table plus its overlapping quarter-turn window. The
-- second address uses SIGNED addiu 0x8e50 after lui 0x8009 (0x841060D4).
FxRom.TRIG_ROM_START = 0x88A50
FxRom.TRIG_ROM_END = 0x8DA50
FxRom.TRIG_COUNT = 4096

function FxRom.trigTables(data)
  if type(data)~="string" then return nil,"battle FX trig bytes unavailable" end
  if #data>=FxRom.ROM_BASE then
    data=data:sub(FxRom.TRIG_ROM_START+1,FxRom.TRIG_ROM_END)
  end
  if #data~=FxRom.TRIG_ROM_END-FxRom.TRIG_ROM_START then
    return nil,"battle FX trig block has invalid length"
  end
  local values={}
  for offset=0,#data-4,4 do
    local a,b,c,d=data:byte(offset+1,offset+4)
    local bits=((a*256+b)*256+c)*256+d
    local exponent=math.floor(bits/0x800000)%256
    local fraction=bits%0x800000
    if exponent==255 then return nil,"battle FX trig table has non-finite value" end
    local value=exponent==0 and fraction*2^-149
      or (1+fraction/0x800000)*2^(exponent-127)
    values[#values+1]=bits>=0x80000000 and -value or value
  end
  local out={tableA={},tableB={}}
  for i=1,FxRom.TRIG_COUNT do
    out.tableA[i],out.tableB[i]=values[i],values[i+1024]
  end
  return out
end

-- Native event modes written by the corresponding opcode handlers. These
-- values select the exact attachment/emission routines in func_84107B68.
FxRom.EMITTER_MODE = {
  [4]=0, [8]=1, [5]=2, [6]=4, [7]=5, [13]=6, [14]=7, [15]=8,
}

local function hasFlag(value,flag)
  value=tonumber(value) or 0
  return math.floor(value/flag)%2==1
end

local function attachmentContract(flags,flags2)
  return {
    status="unresolved-common-flags",flags=flags,flags2=flags2,
    placementPreparation=hasFlag(flags,0x1),
    primaryVisualPolicy=hasFlag(flags,0x2),zeroAnchorY=hasFlag(flags,0x4),
    externalScaleOffsetY=hasFlag(flags,0x8),anchorCallback=hasFlag(flags,0x10),
    modelAndSavedOrigin=hasFlag(flags,0x20),fixedInitialScale=hasFlag(flags,0x80),
    zeroAnchor=hasFlag(flags,0x100),laneScalar=hasFlag(flags,0x400),
    secondaryVisualPolicy=hasFlag(flags,0x4000),
  }
end

local byte = string.byte

local function u16(data, offset)
  local a, b = byte(data, offset + 1, offset + 2)
  if not b then return nil end
  return a * 0x100 + b
end

local function u32(data, offset)
  local a, b, c, d = byte(data, offset + 1, offset + 4)
  if not d then return nil end
  return ((a * 0x100 + b) * 0x100 + c) * 0x100 + d
end

function FxRom.romOffset(address)
  address = tonumber(address)
  if not address then return nil end
  return FxRom.ROM_BASE + address - FxRom.VRAM_BASE
end

local function read16(rom, address)
  local offset = #rom < FxRom.ROM_BASE
    and (address - FxRom.VRAM_BASE) or FxRom.romOffset(address)
  return u16(rom, assert(offset, "invalid VRAM address"))
end

local function read32(rom, address)
  local offset = #rom < FxRom.ROM_BASE
    and (address - FxRom.VRAM_BASE) or FxRom.romOffset(address)
  return u32(rom, assert(offset, "invalid VRAM address"))
end

local function readSigned16(rom,address)
  local value=read16(rom,address)
  if value and value>=0x8000 then return value-0x10000 end
  return value
end

local function addressInOverlay(address)
  local offset = FxRom.romOffset(address)
  return offset and offset >= FxRom.ROM_BASE and offset + 4 <= 0x419480
end

local function pointerAt(rom,address,offset)
  if not addressInOverlay(address) then return nil end
  local value=read32(rom,address+(offset or 0))
  return value and addressInOverlay(value) and value or nil
end

local function signedVector(rom,address)
  if not addressInOverlay(address) then return nil end
  return {readSigned16(rom,address),readSigned16(rom,address+2),
    readSigned16(rom,address+4)}
end

local function rgbaAt(rom,address)
  if not addressInOverlay(address) then return nil end
  local offset=#rom < FxRom.ROM_BASE and address-FxRom.VRAM_BASE
    or FxRom.romOffset(address)
  return {byte(rom,offset+1),byte(rom,offset+2),byte(rom,offset+3),
    byte(rom,offset+4)}
end

-- These readers mirror func_8410679C, func_84106AC4 and func_84106F34.
-- Pointer-bearing optional blocks are deliberately retained even where the
-- modern player does not consume a field yet: losing one here would force a
-- later renderer to guess values which Stadium authored in fragment 79.
local function randomVectorSpec(rom,address)
  if not addressInOverlay(address) then return nil end
  return {address=address,mode=readSigned16(rom,address),values={
    readSigned16(rom,address+2),readSigned16(rom,address+4),
    readSigned16(rom,address+6)}}
end

local function selectorEntryCount(mode,repeats,particles)
  repeats=math.max(1,tonumber(repeats) or 1)
  particles=math.max(1,tonumber(particles) or 1)
  if repeats==0xFF then repeats=1 end
  if mode==2 or mode==5 then return repeats*particles end
  if mode==3 or mode==4 then return particles end
  if mode==6 then return repeats end
  return 1
end

local function decodeGeometry(rom,address,repeats,particles)
  if not addressInOverlay(address) then return nil end
  local selector=read16(rom,address)
  local scaleTable=pointerAt(rom,address,4)
  local positionTable=pointerAt(rom,address,8)
  local velocityTable=pointerAt(rom,address,12)
  local attributeTable=pointerAt(rom,address,16)
  local selectors={scale=selector%0x10,position=math.floor(selector/0x10)%0x10,
    velocity=math.floor(selector/0x100)%0x10,
    attribute=math.floor(selector/0x1000)%0x10}
  local scales,positions,velocities,attributes={},{},{},{}
  if scaleTable then
    for index=0,selectorEntryCount(selectors.scale,repeats,particles)-1 do
      scales[#scales+1]={
        scale=readSigned16(rom,scaleTable+index*8)*0.001,
        nativeScaleUpdate={initial=readSigned16(rom,scaleTable+index*8),
          target=readSigned16(rom,scaleTable+index*8+2),
          step=readSigned16(rom,scaleTable+index*8+4),
          startAge=readSigned16(rom,scaleTable+index*8+6)},
        value1=readSigned16(rom,scaleTable+index*8+2),
        value2=readSigned16(rom,scaleTable+index*8+4),
        lifetime=readSigned16(rom,scaleTable+index*8+6),
      }
    end
  end
  if positionTable then
    for index=0,selectorEntryCount(selectors.position,repeats,particles)-1 do
      positions[#positions+1]=signedVector(rom,positionTable+index*6)
    end
  end
  if velocityTable then
    for index=0,selectorEntryCount(selectors.velocity,repeats,particles)-1 do
      velocities[#velocities+1]=signedVector(rom,velocityTable+index*6)
    end
  end
  if attributeTable then
    for index=0,selectorEntryCount(selectors.attribute,repeats,particles)-1 do
      attributes[#attributes+1]=readSigned16(rom,attributeTable+index*2)
    end
  end
  return {
    address=address,selector=selector,nativeGeometry=true,
    selectors=selectors,
    scaleTable=scaleTable,positionTable=positionTable,
    velocityTable=velocityTable,attributeTable=attributeTable,
    -- Entry zero is useful both as a deterministic test vector and as the
    -- value selected by selector mode 1. Other modes choose an index at spawn.
    scaleEntries=scales,positionEntries=positions,
    velocityEntries=velocities,attributeEntries=attributes,
    scaleEntry=scales[1],
    positionEntry=positionTable and signedVector(rom,positionTable) or nil,
    velocityEntry=velocityTable and signedVector(rom,velocityTable) or nil,
    attributeEntry=attributeTable and readSigned16(rom,attributeTable) or nil,
  }
end

-- func_8410119C/841013F4 and the vertical branch of func_84101D54.
local function decodeNativeMotion(rom,address)
  if not addressInOverlay(address) then return nil end
  local direction=pointerAt(rom,address,0)
  local vertical=pointerAt(rom,address,8)
  local out={address=address}
  if direction then
    local speed=pointerAt(rom,direction,4)
    out.direction={mode=readSigned16(rom,direction),
      curve=pointerAt(rom,direction,8)}
    if speed then
      out.direction.speed={mode=readSigned16(rom,speed),
        startAge=readSigned16(rom,speed+2),initial=readSigned16(rom,speed+4),
        target=readSigned16(rom,speed+6),step=readSigned16(rom,speed+8),
        random=readSigned16(rom,speed+10)}
    end
  end
  if vertical then out.verticalSubtract={startAge=readSigned16(rom,vertical),
    value=readSigned16(rom,vertical+2)} end
  out.verticalController=pointerAt(rom,address,4)
  if out.verticalController then
    local values=rgbaAt(rom,out.verticalController)
    out.verticalRamp={startAge=values[1],step=values[2]>=128 and values[2]-256 or values[2],
      random=values[3],base=values[4],target=readSigned16(rom,out.verticalController+4)}
  end
  return out
end

local function decodeTransform(rom,address)
  if not addressInOverlay(address) then return nil end
  local frame=pointerAt(rom,address,0)
  local rotation=pointerAt(rom,address,4)
  local scale=pointerAt(rom,address,8)
  local motion=pointerAt(rom,address,12)
  local rotationOffset=rotation and pointerAt(rom,rotation,4)
  local directionalVelocity=rotation and pointerAt(rom,rotation,8)
  local scaleController=scale and pointerAt(rom,scale,0)
  local motionController=motion and pointerAt(rom,motion,0)
  local motionAxes=motion and pointerAt(rom,motion,8)
  return {
    address=address,frame=frame,rotation=rotation,scale=scale,motion=motion,
    frameRule=frame and {mode=readSigned16(rom,frame),
      value=readSigned16(rom,frame+2)} or nil,
    rotationOffset=randomVectorSpec(rom,rotationOffset),
    directionalVelocity=randomVectorSpec(rom,directionalVelocity),
    scaleController=scaleController,
    motionController=motionController,
    nativeMotion=decodeNativeMotion(rom,motionController),
    motionAxes=motionAxes,
  }
end

local function decodeParticleColorTrack(rom,controller,field)
  local header=controller and pointerAt(rom,controller,0)
  local values=controller and pointerAt(rom,controller,field)
  if not header or not values then return nil end
  local bytes=rgbaAt(rom,header)
  if not bytes then return nil end
  local mode,period,count=bytes[1],bytes[3],bytes[4]
  if period==0 or (mode~=0 and mode~=1) then return nil end
  local times=mode==1 and pointerAt(rom,header,4)
  if mode==1 and (not times or count==0) then return nil end
  local track={mode=mode,period=period,colors={}}
  for index=0,(mode==0 and period or count)-1 do
    local rgba=rgbaAt(rom,values+index*4)
    if not rgba then return nil end
    if mode==0 then track.colors[#track.colors+1]=rgba
    else
      local age=readSigned16(rom,times+index*2)
      if age<0 or (index>0 and age<track.colors[index].age) then return nil end
      track.colors[#track.colors+1]={age=age,rgba=rgba}
    end
  end
  return track
end

local function decodeMaterial(rom,address)
  if not addressInOverlay(address) then return nil end
  local colorController=pointerAt(rom,address,8)
  local colors=pointerAt(rom,address,12)
  local primary=colorController and pointerAt(rom,colorController,4)
  local secondary=colorController and pointerAt(rom,colorController,8)
  local constant=colors and pointerAt(rom,colors,0)
  local fade=colors and pointerAt(rom,colors,4)
  local fadeBytes=fade and rgbaAt(rom,fade)
  return {
    address=address,shapeId=readSigned16(rom,address),
    secondaryShapeId=readSigned16(rom,address+2),
    colorController=colorController,colors=colors,
    nativeMaterialColors=true,
    nativePrimaryTrack=decodeParticleColorTrack(rom,colorController,4),
    nativeSecondaryTrack=decodeParticleColorTrack(rom,colorController,8),
    primaryColor=primary and rgbaAt(rom,primary) or nil,
    secondaryColor=secondary and rgbaAt(rom,secondary) or nil,
    constantColor=constant and rgbaAt(rom,constant) or nil,
    nativeAlphaInitial=constant and rgbaAt(rom,constant)[1] or nil,
    nativeAlphaRamp=fadeBytes and {address=fade,target=fadeBytes[1],
      step=fadeBytes[2],startAge=readSigned16(rom,fade+2)} or nil,
  }
end

-- Mode 2 is a global RGBA controller, not a sprite descriptor:
-- 841077E8 constructs it; 84100B3C samples it through 84100710.
local function decodeNativeColorTrack(rom,address)
  local controller=pointerAt(rom,address,4)
  if not controller then return nil end
  local header=pointerAt(rom,controller,0)
  local colors=pointerAt(rom,controller,4)
  if not header or not colors then return nil end
  local bytes=rgbaAt(rom,header)
  local mode,period,count=bytes[1],bytes[3],bytes[4]
  if period==0 or (mode~=0 and mode~=1) then return nil end
  local out={address=controller,mode=mode,period=period,colors={}}
  if mode==0 then
    for index=0,period-1 do
      local rgba=rgbaAt(rom,colors+index*4)
      if not rgba then return nil end
      out.colors[#out.colors+1]=rgba
    end
  else
    local times=pointerAt(rom,header,4)
    if not times or count==0 then return nil end
    for index=0,count-1 do
      local age=readSigned16(rom,times+index*2)
      local rgba=rgbaAt(rom,colors+index*4)
      if not rgba or age<0 or (index>0 and age<out.colors[index].age) then return nil end
      out.colors[#out.colors+1]={age=age,rgba=rgba}
    end
  end
  return out
end

local function particleComponents(rom,geometryPointer,transformPointer,materialPointer,
    repeats,particles)
  return decodeGeometry(rom,geometryPointer,repeats,particles),decodeTransform(rom,transformPointer),
    decodeMaterial(rom,materialPointer)
end

function FxRom.opcodes(rom)
  local out = {}
  for opcode = 0, FxRom.OPCODE_COUNT - 1 do
    local address = FxRom.OPCODE_TABLE + opcode * 8
    out[opcode] = {
      opcode = opcode,
      handler = assert(read32(rom, address), "truncated FX opcode table"),
      length = assert(read32(rom, address + 4), "truncated FX opcode table"),
    }
  end
  return out
end

function FxRom.programPointer(rom, programId)
  programId = math.floor(tonumber(programId) or -1)
  if programId < 0 or programId >= FxRom.PROGRAM_COUNT then return nil end
  return read32(rom, FxRom.PROGRAM_TABLE + programId * 4)
end

-- Decode the linear record stream exactly as the native interpreter sees it.
-- Branch/skip opcodes remain records in the output; no battle-state guess is
-- made here. Opcode zero is the native end instruction.
function FxRom.program(rom, programId)
  local pointer = FxRom.programPointer(rom, programId)
  if not pointer or not addressInOverlay(pointer) then
    return nil, "effect program pointer is outside fragment 79"
  end
  local definitions = FxRom.opcodes(rom)
  local records, cursor = {}, pointer
  for _ = 1, 4096 do
    local offset = #rom < FxRom.ROM_BASE
      and (cursor - FxRom.VRAM_BASE) or FxRom.romOffset(cursor)
    local opcode = offset and byte(rom, offset + 1) or nil
    local definition = opcode and definitions[opcode] or nil
    if not definition then
      return nil, ("unknown native FX opcode %s at 0x%08X")
        :format(tostring(opcode), cursor)
    end
    local length = definition.length
    if length ~= 4 and length ~= 8 and length ~= 16 then
      return nil, ("invalid native FX record length %d for opcode %d")
        :format(length, opcode)
    end
    local finish = offset + length
    if finish > #rom then return nil, "truncated native FX record" end
    local raw = rom:sub(offset + 1, finish)
    local record = {
      address = cursor,
      opcode = opcode,
      handler = definition.handler,
      length = length,
      raw = raw,
      argument = length >= 8 and u32(raw, 4) or nil,
      argument2 = length >= 16 and u32(raw, 8) or nil,
      argument3 = length >= 16 and u32(raw, 12) or nil,
    }
    local mode = FxRom.EMITTER_MODE[opcode]
    if mode ~= nil and record.argument and addressInOverlay(record.argument) then
      local descriptorOffset = #rom < FxRom.ROM_BASE
        and (record.argument - FxRom.VRAM_BASE)
        or FxRom.romOffset(record.argument)
      -- Opcodes 4/8/14 feed the shared particle constructor and therefore use
      -- the common 24-byte emitter descriptor.  The remaining emitter modes
      -- point at mode-specific native objects; their first byte is only the
      -- scheduler delay and must not be decoded as the common descriptor.
      local common = mode == 0 or mode == 1 or mode == 7
      if common then
        local descriptorLength = 24
        local descriptorRaw = rom:sub(descriptorOffset + 1,
          descriptorOffset + descriptorLength)
        local b0,b1,b2,b3 = byte(descriptorRaw,1,4)
        local geometryPointer=u32(descriptorRaw,12)
        local transformPointer=u32(descriptorRaw,16)
        local materialPointer=u32(descriptorRaw,20)
        record.emitter = {
          mode=mode, descriptor=record.argument, raw=descriptorRaw,
          descriptorKind="particle",
          start=b0, interval=b1, repeats=b2,
          particleCount=b3,
          flags=u32(descriptorRaw,4),
          flags2=u32(descriptorRaw,8),
          geometryPointer=geometryPointer,
          transformPointer=transformPointer,
          materialPointer=materialPointer,
          -- func_841031F4 reads the first signed halfword of this structure and
          -- uses it as the resource export symbol ID. All retail IDs are
          -- non-negative, so the unsigned representation is lossless here.
          shapeId=materialPointer and addressInOverlay(materialPointer)
            and read16(rom,materialPointer) or nil,
        }
        record.emitter.attachment=attachmentContract(record.emitter.flags,
          record.emitter.flags2)
        record.emitter.geometry,record.emitter.transform,
          record.emitter.material=particleComponents(rom,geometryPointer,
            transformPointer,materialPointer,b2,b3)
      else
        -- Opcodes 5/6/7/13/15 enqueue a command pointer which is resolved by
        -- external 0x80003240 before the scheduler sees an object. Preserve
        -- the encoded bytes as evidence, but never call them a descriptor or
        -- feed their delay to a live scheduler without an explicit resolver.
        local encodedObjectRaw = rom:sub(descriptorOffset + 1,
          descriptorOffset + 16)
        local delayOffset = (mode == 2 or mode == 4 or mode == 8) and 3 or 1
        record.emitter = {
          mode=mode,
          descriptorKind="native-object",
          commandPointer=record.argument,
          encodedObjectRaw=encodedObjectRaw,
          delayOffset=delayOffset,
          encodedDelay=byte(encodedObjectRaw,delayOffset + 1),
          nativeColorTrack=(mode==2 or mode==4 or mode==8)
            and decodeNativeColorTrack(rom,record.argument) or nil,
          nativeModelColor=mode==5 and {
            primary=decodeParticleColorTrack(rom,pointerAt(rom,record.argument,4),4),
            secondary=decodeParticleColorTrack(rom,pointerAt(rom,record.argument,4),8),
            hideAge=read16(rom,record.argument+2),
          } or nil,
          resolvedObject=nil,
          resolution={status="unresolved", resolver=0x80003240},
        }
      end
    end
    records[#records + 1] = record
    if opcode == 0 then
      return {id=programId, address=pointer, records=records}
    end
    cursor = cursor + length
  end
  return nil, "native FX program did not terminate"
end

local function u16Sequence(rom, pointer)
  if not addressInOverlay(pointer) then return nil, "sequence is outside fragment 79" end
  local values = {}
  for _ = 1, 1024 do
    local value = read16(rom, pointer)
    if value == nil then return nil, "truncated effect sequence" end
    if value == 0 then return values end
    values[#values + 1] = value
    pointer = pointer + 2
  end
  return nil, "effect sequence did not terminate"
end

-- Each move row's final pointer is consumed by func_841035DC. It is a byte
-- list of fragment resource IDs terminated by 0x83, not another FX program
-- channel. Those resources are loaded before the move controller runs.
local function resourceSequence(rom, pointer)
  if not addressInOverlay(pointer) then
    return nil, "resource list is outside fragment 79"
  end
  local values={}
  for _=1,256 do
    local offset=#rom < FxRom.ROM_BASE
      and (pointer-FxRom.VRAM_BASE) or FxRom.romOffset(pointer)
    local value=offset and byte(rom,offset+1) or nil
    if value==nil then return nil,"truncated move resource list" end
    if value==0x83 then return values end
    values[#values+1]=value
    pointer=pointer+1
  end
  return nil,"move resource list did not terminate"
end

-- func_841051D8 divides resolved route entries into two genuinely different
-- engines. Values below 0x2000 are bytecode programs. Values in the 0x2000
-- and 0x3000 banks select the same 30 lifecycle families, with the latter
-- setting Stadium's alternate-side flag. Keeping that distinction prevents
-- a lifecycle callback from ever being treated as particle bytecode.
function FxRom.dispatchEntry(value)
  value = math.floor(tonumber(value) or -1)
  if value < 0 then return nil, "invalid FX dispatch entry" end
  if value < 0x2000 then
    if value >= FxRom.PROGRAM_COUNT then
      return nil, ("native FX program %d is out of range"):format(value)
    end
    return { encoded=value, kind="program", programId=value }
  end
  local alternate = value >= 0x3000
  local family = value - (alternate and 0x3000 or 0x2000)
  if family < 0 or family >= FxRom.LIFECYCLE_COUNT then
    return nil, ("native FX lifecycle %d is out of range"):format(family)
  end
  return {
    encoded=value, kind="lifecycle", lifecycleId=family,
    alternate=alternate,
  }
end

local function decodedDispatch(values)
  local out = {}
  for index,value in ipairs(values or {}) do
    local entry,err=FxRom.dispatchEntry(value)
    if not entry then return nil,err end
    out[index]=entry
  end
  return out
end

-- Resolve the 0x8000 sequence and 0x4000 side-variant encodings used by
-- func_841052AC. The returned values are the exact program/lifecycle IDs sent
-- to func_841051D8, in submission order.
function FxRom.resolveRoute(rom, encoded, alternate)
  encoded = tonumber(encoded)
  if not encoded then return nil, "missing route" end
  if encoded >= 0x8000 then
    local index = encoded - 0x8000
    if index < 0 or index >= FxRom.SEQUENCE_COUNT then
      return nil, ("effect sequence index %d is out of range"):format(index)
    end
    local pointer = read32(rom, FxRom.SEQUENCE_TABLE + index * 4)
    return u16Sequence(rom, pointer)
  end
  if encoded >= 0x4000 then
    local index = encoded - 0x4000
    if index < 0 or index >= FxRom.VARIANT_COUNT then
      return nil, ("effect variant index %d is out of range"):format(index)
    end
    local value = read16(rom, FxRom.VARIANT_TABLE + index * 4
      + (alternate and 2 or 0))
    return FxRom.resolveRoute(rom, value, alternate)
  end
  return {encoded}
end

function FxRom.move(rom, moveId)
  moveId = math.floor(tonumber(moveId) or -1)
  if moveId < 1 or moveId > FxRom.MOVE_COUNT then return nil, "move ID out of range" end
  local address = FxRom.MOVE_TABLE + moveId * 8
  local primary = assert(read16(rom, address), "truncated move FX table")
  local alternate = assert(read16(rom, address + 2), "truncated move FX table")
  local resourcePointer = assert(read32(rom, address + 4), "truncated move FX table")
  local resources,resourceError=resourceSequence(rom,resourcePointer)
  if not resources then return nil,resourceError end
  local primaryResolved, primaryError = FxRom.resolveRoute(rom, primary, false)
  if not primaryResolved then return nil, primaryError end
  local alternateResolved, alternateError = FxRom.resolveRoute(rom, alternate, true)
  if not alternateResolved then return nil, alternateError end
  local primaryDispatch,primaryDispatchError=decodedDispatch(primaryResolved)
  if not primaryDispatch then return nil,primaryDispatchError end
  local alternateDispatch,alternateDispatchError=decodedDispatch(alternateResolved)
  if not alternateDispatch then return nil,alternateDispatchError end
  return {
    moveId = moveId,
    address = address,
    primary = primary,
    alternate = alternate,
    resourcePointer = resourcePointer,
    resources=resources,
    primaryResolved = primaryResolved,
    alternateResolved = alternateResolved,
    primaryDispatch=primaryDispatch,
    alternateDispatch=alternateDispatch,
  }
end

function FxRom.lifecycle(rom)
  local out = {}
  for index = 0, FxRom.LIFECYCLE_COUNT - 1 do
    out[index] = {
      index = index,
      init = assert(read32(rom, FxRom.LIFECYCLE_INIT + index * 4),
        "truncated lifecycle init table"),
      update = assert(read32(rom, FxRom.LIFECYCLE_UPDATE + index * 4),
        "truncated lifecycle update table"),
      draw = assert(read32(rom, FxRom.LIFECYCLE_DRAW + index * 4),
        "truncated lifecycle draw table"),
    }
  end
  return out
end

function FxRom.ribbonAsset(rom)
  local pixels = {}
  for i = 0, 127, 4 do
    local packed = rgbaAt(rom, 0x84187418 + i)
    for _, value in ipairs(packed) do
      local intensity, alpha = math.floor(value / 16) * 17, value % 16 * 17
      pixels[#pixels + 1] = string.char(intensity, intensity, intensity, alpha)
    end
  end
  return {w=8,h=16,format=3,size=1,rgba=table.concat(pixels), address=0x84187418,
    combiner={cycles=1, color0={3,5,1,5}, alpha0={1,7,3,7},
      color1={3,5,1,5}, alpha1={1,7,3,7}}}
end

-- Static needle display list 84188A70: 18 ROM vertices, 16 triangles, I4 4x4.
function FxRom.needleAsset(rom)
  local out={pos={},uv={},nrm={},idx={}}
  for j=0,17 do
    local at=0x84188948+j*16
    for k=0,2 do
      out.pos[#out.pos+1]=readSigned16(rom,at+k*2)
      local word=read32(rom,at+12)
      local n=math.floor(word/2^(24-k*8))%256
      out.nrm[#out.nrm+1]=(n>=128 and n-256 or n)/127
    end
    out.uv[#out.uv+1]=readSigned16(rom,at+8)/128
    out.uv[#out.uv+1]=readSigned16(rom,at+10)/128
  end
  for at=0x84188B00,0x84188B38,8 do
    for _,word in ipairs({read32(rom,at),read32(rom,at+4)}) do
      for shift=16,0,-8 do out.idx[#out.idx+1]=math.floor(word/2^shift)%256/2+1 end
    end
  end
  local pixels={}
  for at=0x84188A68,0x84188A6C,4 do for _,v in ipairs(rgbaAt(rom,at)) do
    for _,n in ipairs({math.floor(v/16),v%16}) do
      local i=n*17;pixels[#pixels+1]=string.char(i,i,i,i)
    end
  end end
  out.texture={w=4,h=4,format=4,size=0,rgba=table.concat(pixels)}
  return out
end

function FxRom.catalog(rom,trigBytes)
  local programs, moves = {}, {}
  for id = 0, FxRom.PROGRAM_COUNT - 1 do
    local program, err = FxRom.program(rom, id)
    if not program then return nil, ("program %d: %s"):format(id, err) end
    programs[id] = program
  end
  for id = 1, FxRom.MOVE_COUNT do
    local move, err = FxRom.move(rom, id)
    if not move then return nil, ("move %d: %s"):format(id, err) end
    moves[id] = move
  end
  return {
    opcodes = FxRom.opcodes(rom),
    programs = programs,
    moves = moves,
    lifecycle = FxRom.lifecycle(rom),
    lifecycleAssets = {needle=FxRom.needleAsset(rom),ribbon=FxRom.ribbonAsset(rom),beamGlow=(function()
      local pixels={}
      for i=0,1023,4 do for _,v in ipairs(rgbaAt(rom,0x84188738+i)) do
        local intensity=math.floor(v/16)*17
        pixels[#pixels+1]=string.char(intensity,intensity,intensity,v%16*17)
      end end
      return {w=32,h=32,format=3,size=1,rgba=table.concat(pixels)}
    end)()},
    trigTables = FxRom.trigTables(trigBytes or rom),
  }
end

FxRom.u16 = u16
FxRom.u32 = u32
FxRom.read16 = read16
FxRom.read32 = read32

return FxRom
