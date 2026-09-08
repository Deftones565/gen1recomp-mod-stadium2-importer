local root = (... and ... ~= "" and ...) or "."
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path

local Rom = require("mods.STADIUM2_IMPORTER.lib.rom")
local FxRom = require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_rom")
local FxResources = require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_resources")
local FxNative = require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_native")
local Fragment = require("mods.STADIUM2_IMPORTER.lib.fragment")

local path = os.getenv("STADIUM2_ROM") or arg[1]
if not path then
  io.stderr:write("usage: STADIUM2_ROM=/path/to/stadium2.z64 lua "
    .. "mods/STADIUM2_IMPORTER/tests/stadium2_battle_fx_rom_audit.lua\n")
  os.exit(2)
end
local file = assert(io.open(path, "rb"))
local rom = assert(Rom.normalise(assert(file:read("*a"))))
file:close()
assert(#rom == Rom.SIZE and Rom.title(rom):upper() == Rom.US_TITLE,
  "expected the supported Pokemon Stadium 2 US ROM")

local opcodes = FxRom.opcodes(rom)
assert(#opcodes == 17, "native opcode table must expose IDs 0..17")
local lengths = {4,4,4,4,8,8,8,8,8,4,4,4,16,8,8,8,4,4}
for opcode = 0, 17 do
  local row = assert(opcodes[opcode])
  assert(row.length == lengths[opcode + 1],
    ("opcode %d record length differs from ROM"):format(opcode))
  assert(row.handler >= 0x84100000 and row.handler < 0x8416A218,
    ("opcode %d handler is outside fragment-79 code"):format(opcode))
end

local catalog = assert(FxRom.catalog(rom))
assert(catalog.programs[0] and catalog.programs[394],
  "all 395 native effect programs must be decoded")
for id = 0, 394 do
  local program = assert(catalog.programs[id])
  assert(program.records[#program.records].opcode == 0,
    ("program %d lost its ROM terminator"):format(id))
end

-- These are literal rows from the supported ROM, not inferred type mappings.
local pound = assert(catalog.moves[1])
assert(pound.primary == 0x018A and pound.alternate == 0x008A
    and pound.resourcePointer == 0x84182794
    and #pound.resources == 1 and pound.resources[1] == 1,
  "Pound routing differs from the Stadium 2 ROM")
local firePunch = assert(catalog.moves[7])
assert(firePunch.primary == 0x0103 and firePunch.alternate == 0x0104
    and firePunch.resourcePointer == 0x84182964
    and table.concat(firePunch.resources,",") == "81,110",
  "Fire Punch routing differs from the Stadium 2 ROM")
local dispatched=0
for moveId=1,FxRom.MOVE_COUNT do
  local move=catalog.moves[moveId]
  for _,resourceId in ipairs(move.resources) do
    assert(resourceId>=0 and resourceId<0x83,
      ("move %d has invalid pre-load ID %d"):format(moveId,resourceId))
  end
  for _,channel in ipairs({move.primaryDispatch,move.alternateDispatch}) do
    for _,entry in ipairs(channel) do
      assert(entry.kind == "program" or entry.kind == "lifecycle",
        ("move %d lost its native dispatch kind"):format(moveId))
      if entry.kind == "program" then
        assert(catalog.programs[entry.programId],
          ("move %d routes to a missing program"):format(moveId))
      else
        assert(catalog.lifecycle[entry.lifecycleId],
          ("move %d routes to a missing lifecycle"):format(moveId))
      end
      dispatched=dispatched+1
    end
  end
end
assert(dispatched > FxRom.MOVE_COUNT,
  "move table did not retain its ordered multi-channel dispatch")

local poundProgram = assert(catalog.programs[0x18A])
assert(#poundProgram.records == 2 and poundProgram.records[1].opcode == 1,
  "Pound's native no-particle controller differs from ROM")
local program1 = assert(catalog.programs[1])
local emitters = {}
for _,record in ipairs(program1.records) do
  if record.emitter then emitters[#emitters+1]=record.emitter end
end
assert(#emitters == 5 and emitters[1].mode == 2
    and emitters[2].mode == 0 and emitters[3].mode == 7
    and emitters[4].mode == 1 and emitters[5].mode == 1,
  "program 1 emitter modes differ from fragment-79 handlers")
assert(emitters[2].start == 0 and emitters[2].interval == 0
    and emitters[2].repeats == 1 and emitters[2].particleCount == 1,
  "native emitter timing header was not decoded verbatim")
assert(emitters[1].descriptorKind == "native-object"
    and emitters[1].particleCount == nil
    and emitters[1].commandPointer == 0x8416A438
    and #emitters[1].encodedObjectRaw >= 16
    and emitters[1].delayOffset == 3
    and emitters[1].encodedDelay == 0
    and emitters[1].resolvedObject == nil
    and emitters[2].descriptorKind == "particle"
    and emitters[2].geometryPointer == 0x8416DC84
    and emitters[2].transformPointer == 0
    and emitters[2].materialPointer == 0x8416DCA4
    and emitters[2].shapeId == 0x82,
  "mode-specific native objects were confused with particle descriptors")

-- Fragment-79 native-object scheduler coverage.  Encoded command pointers
-- remain separate from the object which external 0x80003240 would resolve.
local nativeCounts, nativePrograms, nativePointers = {}, {}, {}
for _, mode in ipairs({2, 4, 5, 6, 8}) do
  nativeCounts[mode], nativePrograms[mode], nativePointers[mode] = 0, {}, {}
end
for programId = 0, FxRom.PROGRAM_COUNT - 1 do
  for _, record in ipairs(catalog.programs[programId].records) do
    local emitter = record.emitter
    if emitter and nativeCounts[emitter.mode] ~= nil then
      nativeCounts[emitter.mode] = nativeCounts[emitter.mode] + 1
      nativePrograms[emitter.mode][programId] = true
      nativePointers[emitter.mode][emitter.commandPointer] = true
      assert(emitter.commandPointer == record.argument
          and #emitter.encodedObjectRaw >= 16
          and emitter.resolvedObject == nil
          and emitter.resolution.status == "unresolved",
        ("program %d native-object record lost unresolved command evidence"):format(programId))
      local expectedOffset = (emitter.mode == 5 or emitter.mode == 6) and 1 or 3
      assert(emitter.delayOffset == expectedOffset
          and emitter.encodedDelay == emitter.encodedObjectRaw:byte(expectedOffset + 1),
        ("program %d mode %d delay source differs from fragment 79"):format(
          programId, emitter.mode))
    end
  end
end
local function cardinality(set)
  local count = 0
  for _ in pairs(set) do count = count + 1 end
  return count
end
assert(nativeCounts[2] == 195 and cardinality(nativePrograms[2]) == 194
    and cardinality(nativePointers[2]) == 93,
  "mode-2 native-object coverage differs from ROM")
assert(nativeCounts[4] == 0 and cardinality(nativePrograms[4]) == 0
    and cardinality(nativePointers[4]) == 0,
  "mode-4 native-object coverage differs from ROM")
assert(nativeCounts[5] == 121 and cardinality(nativePrograms[5]) == 117
    and cardinality(nativePointers[5]) == 98,
  "mode-5 native-object coverage differs from ROM")
assert(nativeCounts[6] == 0 and cardinality(nativePrograms[6]) == 0
    and cardinality(nativePointers[6]) == 0,
  "mode-6 native-object coverage differs from ROM")
assert(nativeCounts[8] == 87 and cardinality(nativePrograms[8]) == 87
    and cardinality(nativePointers[8]) == 51,
  "mode-8 native-object coverage differs from ROM")

local goldens = {
  {program=98, address=0x84173DA4, mode=2, pointer=0x8416A3E0,
    delayOffset=3, delay=0x23},
  {program=328, address=0x841788B8, mode=5, pointer=0x84178894,
    delayOffset=1, delay=0x02},
  {program=299, address=0x8416C880, mode=8, pointer=0x8416C83C,
    delayOffset=3, delay=0x2B},
}
for _, golden in ipairs(goldens) do
  local found
  for _, record in ipairs(catalog.programs[golden.program].records) do
    if record.address == golden.address then found = record.emitter end
  end
  assert(found and found.mode == golden.mode
      and found.commandPointer == golden.pointer
      and found.delayOffset == golden.delayOffset
      and found.encodedDelay == golden.delay,
    ("native-object golden program %d differs from ROM"):format(golden.program))
end

-- Runtime reads the same records from the playthrough cache, which contains
-- only fragment 79 copied from the user's ROM (never a bundled ROM dump).
local overlay = rom:sub(FxRom.ROM_BASE + 1, 0x419480)
local cachedCatalog = assert(FxRom.catalog(overlay))
assert(cachedCatalog.moves[1].primary == pound.primary
    and cachedCatalog.programs[394].address == catalog.programs[394].address,
  "cached fragment-79 view differs from the source ROM")

-- The resource byte list is a module preload list, not a shape list. Verify
-- the game's export-table indirection with Fire Punch: member 81 supplies
-- shapes 47/95 while member 110 supplies shape 99.
local resourceArchive=rom:sub(FxResources.ROM_START+1,FxResources.ROM_END)
local resolved=assert(FxResources.resolve(resourceArchive,firePunch.resources))
assert(resolved.shapes[47] and resolved.shapes[47].resourceId==81
    and resolved.shapes[95] and resolved.shapes[95].resourceId==81
    and resolved.shapes[99] and resolved.shapes[99].resourceId==110,
  "Fire Punch shape symbols do not match archive-group-5 exports")
local shape47=assert(FxResources.shapeFromResolved(resolved,47))
local shape95=assert(FxResources.shapeFromResolved(resolved,95))
local shape99=assert(FxResources.shapeFromResolved(resolved,99))
assert(shape47.geometryMode==1 and #shape47.entries==1
    and #shape47.entries[1].textures==16
    and shape47.entries[1].displayListPointer==0x8FF02468,
  "Fire Punch shape 47 lost its ROM geometry/material binding")
assert(#shape95.entries[1].textures==5
    and shape95.entries[1].displayListPointer==0x8FF02468,
  "Fire Punch shape 95 lost its animated Stadium material")
assert(shape99.resourceId==110 and #shape99.entries==1,
  "Fire Punch shape 99 was not resolved from its second resource module")
local shapeModel=assert(FxResources.modelFromShape(shape47,"fire-punch-shape-47"))
assert(#shapeModel.prims>0 and #shapeModel.textures==8
    and #shapeModel.prims[1].fxFrames==16,
  "Fire Punch ROM display list/animated textures were not decoded")
assert(shapeModel.prims[1].idx[1]>=1 and shapeModel.prims[1].tex>=1
    and shapeModel.prims[1].fxFrames[1]>=1
    and type(shapeModel.rootScale)=="number" and shapeModel.rootScale==1
    and type(shapeModel.rootScaleVector)=="table",
  "battle FX live model was not converted to the renderer's one-based slots")
local triangleCount=0
for _,primitive in ipairs(shapeModel.prims) do
  triangleCount=triangleCount+primitive.nidx/3
end
assert(triangleCount>0,"Fire Punch ROM shape has no decoded triangles")

-- The viewer loads Pokemon and arenas before battle effects, so the shared
-- fragment decoder may last have used their 0x81000000 address base. Move 18
-- must select its own resource base and restore the caller's state.
local move18=assert(catalog.moves[18])
local move18Resources=assert(FxResources.resolve(resourceArchive,move18.resources))
local previousBase=Fragment.getBase()
Fragment.setBase(0x81000000)
for _,shapeId in ipairs({142,143}) do
  local shape=assert(FxResources.shapeFromResolved(move18Resources,shapeId))
  local model,modelError=FxResources.modelFromShape(shape,
    ("move-018-shape-%03d"):format(shapeId))
  assert(model,("move 18 shape %d failed after arena parsing: %s")
    :format(shapeId,tostring(modelError)))
  assert(#model.prims>0,("move 18 shape %d lost its ROM geometry"):format(shapeId))
  assert(Fragment.getBase()==0x81000000,
    "battle FX extraction leaked its resource address base")
end
Fragment.setBase(previousBase)

-- Validate the complete move/resource relationship, not a curated subset.
-- The same native program may be used with different preload lists, so each
-- move channel must resolve its shape symbols against that move's own export
-- table exactly as func_84103550 does.
local resolvedSets,shapeReferences,drawableModels={},{},{}
shapeReferences=0
for moveId=1,FxRom.MOVE_COUNT do
  local move=catalog.moves[moveId]
  local key=table.concat(move.resources,",")
  local moveResources=resolvedSets[key]
  if not moveResources then
    moveResources=assert(FxResources.resolve(resourceArchive,move.resources))
    resolvedSets[key]=moveResources
  end
  for _,channel in ipairs({move.primaryDispatch,move.alternateDispatch}) do
    for _,dispatch in ipairs(channel) do
      if dispatch.kind=="program" then
        for _,record in ipairs(catalog.programs[dispatch.programId].records) do
          local emitter=record.emitter
          if emitter and emitter.descriptorKind=="particle"
              and emitter.shapeId and emitter.shapeId~=0 then
            shapeReferences=shapeReferences+1
            local binding=assert(moveResources.shapes[emitter.shapeId],
              ("move %d program %d cannot resolve ROM shape %d")
                :format(moveId,dispatch.programId,emitter.shapeId))
            local modelKey=key..":"..emitter.shapeId..":"..binding.resourceId
            if drawableModels[modelKey]==nil then
              local shape=assert(FxResources.shapeFromResolved(
                moveResources,emitter.shapeId))
              local model,modelError=FxResources.modelFromShape(shape,
                ("move-%03d-shape-%03d"):format(moveId,emitter.shapeId))
              assert(model, ("move %d program %d shape %d failed extraction: %s")
                :format(moveId,dispatch.programId,emitter.shapeId,
                  tostring(modelError)))
              assert(type(model.rootScale)=="number",
                ("move %d shape %d retained a non-scalar root scale")
                  :format(moveId,emitter.shapeId))
              drawableModels[modelKey]=model
            end
          end
        end
      end
    end
  end
end
assert(shapeReferences==1133,
  "complete Stadium 2 move graph did not retain all shape references")

-- Dynamic loader exports are graph-layout programs. Mega Punch's member 113
-- symbol 448 exercises that route and must compile to the geometry and
-- phase-5 materials installed by descriptor 0x81000138.
local megaPunch=assert(catalog.moves[5])
local megaResources=assert(FxResources.resolve(resourceArchive,megaPunch.resources))
local compiledShape=assert(FxResources.shapeFromResolved(megaResources,448))
assert(compiledShape.compiledLayout and compiledShape.export.kind==3,
  "loader-compiled battle FX export lost its ROM kind")
local compiledModel=assert(FxResources.modelFromShape(compiledShape,"mega-punch-shape-448"))
local compiledMaterials=0
for _,primitive in ipairs(compiledModel.prims) do
  if primitive.material then compiledMaterials=compiledMaterials+1 end
end
assert(#compiledModel.prims==5 and #compiledModel.textures==5
    and compiledMaterials==5,
  "kind-3 battle FX layout was not compiled with its phase-5 materials")

local fireExecution=FxNative.execute(catalog.programs[259],{moveId=7})
assert(#fireExecution.scheduled==4
    and fireExecution.scheduled[2].shapeId==47
    and fireExecution.scheduled[2].start==0
    and fireExecution.scheduled[2].interval==2
    and fireExecution.scheduled[2].repeats==10
    and fireExecution.scheduled[3].shapeId==95
    and fireExecution.scheduled[4].shapeId==99,
  "Fire Punch scheduler differs from fragment-79 opcode execution")
local births=FxNative.births(fireExecution,-1,16)
local shape47Births,shape95Births,shape99Births=0,0,0
for _,birth in ipairs(births) do
  local id=birth.event.shapeId
  if id==47 then shape47Births=shape47Births+1
  elseif id==95 then shape95Births=shape95Births+1
  elseif id==99 then shape99Births=shape99Births+1 end
end
assert(shape47Births==9 and shape95Births==1 and shape99Births==4,
  "Fire Punch frame-16 births lost native delay/repeat timing")
local fireParticles=FxNative.particles(fireExecution,-1,16)
assert(#fireParticles==30 and fireParticles[1].particleIndex==0
    and fireParticles[2].particleIndex==1
    and fireParticles[1].scale.scale==0.3,
  "Fire Punch common emitters lost native per-generation particle expansion")
assert(FxNative.selectorIndex(2,3,1,4)==13
    and FxNative.selectorIndex(3,3,1,4)==1
    and FxNative.selectorIndex(6,3,1,4)==3,
  "fragment-79 selector modes differ from func_84106540")
local fire47=fireExecution.scheduled[2]
assert(fire47.geometry and fire47.geometry.selector==1
    and fire47.geometry.scaleTable==0x8417B624
    and fire47.geometry.selectors.scale==1
    and fire47.geometry.selectors.position==0
    and fire47.geometry.scaleEntry.scale==0.3
    and fire47.geometry.scaleEntry.lifetime==1
    and fire47.transform and fire47.transform.rotation==0x8417B650
    and fire47.transform.rotationOffset.mode==0
    and fire47.transform.rotationOffset.values[1]==-1
    and fire47.transform.directionalVelocity.mode==2
    and fire47.transform.directionalVelocity.values[1]==5
    and fire47.material and fire47.material.shapeId==47
    and fire47.material.secondaryShapeId==0
    and fire47.attachment.status=="unresolved-common-flags"
    and fire47.attachment.flags==0x50000004
    and fire47.attachment.flags2==0
    and fire47.attachment.zeroAnchorY==true
    and fire47.attachment.mode==nil
    and fire47.attachment.cameraLine==nil,
  "Fire Punch particle component pointers differ from fragment 79")

local lifecycle = catalog.lifecycle
assert(lifecycle[0] and lifecycle[29] and not lifecycle[30],
  "native lifecycle table must expose exactly 30 families")
for index = 0, 29 do
  local row = lifecycle[index]
  local empty = row.init == 0 and row.update == 0 and row.draw == 0
  local complete = row.init >= 0x84100000 and row.update >= 0x84100000
    and row.draw >= 0x84100000
  assert(empty or complete,
    ("lifecycle %d is neither an empty nor complete ROM family"):format(index))
end

-- The nearby table at ROM 0x3F35E0 is 1 fallback plus 36 groups of seven
-- actor callbacks. This assertion prevents it ever being regressed into a
-- fabricated 251-move FX map again.
local callbackTable = 0x84183D50
local words = (0x84184144 - callbackTable) / 4
assert(words == 253 and (words - 1) / 7 == 36,
  "actor callback table is not fallback + 36x7")

print(("stadium2 battle FX ROM audit: %d moves, %d native programs, "
  .. "%d opcodes, %d lifecycle families")
  :format(FxRom.MOVE_COUNT, FxRom.PROGRAM_COUNT, FxRom.OPCODE_COUNT,
    FxRom.LIFECYCLE_COUNT))
