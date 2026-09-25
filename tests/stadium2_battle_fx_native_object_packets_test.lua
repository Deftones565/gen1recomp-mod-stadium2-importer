package.path = "./?.lua;./?/init.lua;" .. package.path

local Packets = require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_native_object_packets")

local checks = 0
local function ok(value, message)
  checks = checks + 1
  if not value then error("FAIL " .. message, 0) end
end

local snapshot = {
  capacity = 64,
  tickCount = 12,
  diagnostics = {{code = "native-object-callback", severity = "warning",
    kind = "native-object", message = "retained source diagnostic"}},
  slots = {
    {
      index = 3, generation = 4, active = true, mode = 2,
      countdown = 5, reload = 0, age = 7, state = 1,
      commandPointer = 0x8416A3E0,
      event = {effectId = 9, programId = 98, address = 0x84173DA4,
        encodedObjectRaw = "00 00 00 23", encodedDelay = 0x23,
        resolution = {status = "unresolved", resolver = 0x80003240}},
      object = {pointer = 0x8416A3E0, flags = 0x14},
      resolution = {pointer = 0x8416A3E0, raw = "resolved bytes"},
      visualObjects = {{slot = 17, callbackState = 2}},
      rawFields = {{offset = 4, value = 0x14}},
      drawPackets = {},
      diagnostics = {},
    },
    {
      index = 1, generation = 2, active = true, mode = 5,
      countdown = 0, reload = 0, age = 1, state = 1,
      commandPointer = 0x84178894,
      event = {effectId = 4, programId = 328, address = 0x841788B8},
      object = {opaque = true}, resolution = {status = "opaque"},
      visualObjects = {}, rawFields = {}, drawPackets = {}, diagnostics = {},
    },
  },
}

local built = Packets.build(snapshot, {
  context = {sourceSide = "player"},
  resolvePlacement = function(slot, context)
    if slot.index == 3 then
      ok(context.sourceSide == "player",
        "placement resolver receives detached slot and context")
    end
    return {resolved = true, position = {1, 2, 3}, source = "scene"}
  end,
  resolveGeometry = function(slot)
    if slot.mode == 2 then
      ok(slot.object.flags == 0x14,
        "geometry resolver receives raw resolved object")
      return {resolved = true, resource = 0x8416A3D8}
    end
    return {resolved = true, resource = 0x84178888}
  end,
})
ok(#built.packets == 2 and built.tickCount == 12,
  "one packet per active native-object slot")
local first, second = built.packets[1], built.packets[2]
ok(first.nativeObjectId == "native-object:1:2" and second.nativeObjectId == "native-object:3:4",
  "packets are stably ordered and identify slot generations")
ok(first.mode == 5 and first.countdown == 0 and first.age == 1
    and second.mode == 2 and second.reload == 0 and second.state == 1,
  "scheduler mode/countdown/reload/age/state are preserved")
ok(second.commandPointer == 0x8416A3E0
    and second.event.encodedDelay == 0x23
    and second.event.resolution.resolver == 0x80003240
    and second.resolution.raw == "resolved bytes"
    and second.visualObjects[1].callbackState == 2
    and second.rawFields[1].offset == 4,
  "resolver evidence and callback state are retained")
ok(first.placement.resolved and second.geometry.resource == 0x8416A3D8,
  "explicit placement and geometry proofs are attached")
ok(#built.diagnostics == 1 and built.diagnostics[1].code == "native-object-callback",
  "source diagnostics are retained without inventing unresolved warnings")

-- Every packet and nested resolver payload is detached from the scheduler
-- snapshot, so a renderer cannot mutate persistent runtime state.
second.event.resolution.resolver = 0
second.object.flags = 0
ok(snapshot.slots[1].event.resolution.resolver == 0x80003240
    and snapshot.slots[1].object.flags == 0x14,
  "packet evidence is deeply detached")

local unresolved = Packets.build(snapshot)
ok(#unresolved.packets == 2 and #unresolved.diagnostics == 5,
  "missing native placement and geometry are explicit diagnostics")
ok(unresolved.diagnostics[2].code == "native-object-placement-unresolved"
    and unresolved.diagnostics[3].code == "native-object-geometry-unresolved"
    and unresolved.diagnostics[2].schedulerIndex == 1
    and unresolved.diagnostics[3].commandPointer == 0x84178894,
  "unresolved diagnostics retain native identity and command evidence")
ok(unresolved.packets[1].placement == nil and unresolved.packets[1].geometry == nil,
  "unresolved native objects do not become fabricated geometry")

local presentation = Packets.build({slots={{index=0,generation=1,active=true,
  mode=2,presentationKind="background-color",event={effectId=3},
  visualObjects={},drawPackets={}}}})
ok(#presentation.packets==1 and #presentation.diagnostics==0
    and presentation.packets[1].presentationKind=="background-color"
    and presentation.packets[1].placement==nil and presentation.packets[1].geometry==nil,
  "built-in native color presentation does not request invented 3D geometry")

local romFile=io.open(os.getenv('STADIUM2_ROM') or
  'mods/STADIUM2_IMPORTER/baseroms/stadium2.z64','rb')
if romFile then
  local Rom=require('mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_rom')
  local catalog=assert(Rom.catalog(romFile:read('*a')));romFile:close()
  local decoded=0
  for _,program in pairs(catalog.programs)do for _,record in ipairs(program.records)do
    local emitter=record.emitter
    if emitter and emitter.descriptorKind=='native-object' then
      local mode=emitter.mode
      ok((mode==2 or mode==8) and emitter.nativeColorTrack~=nil
          or mode==5 and emitter.nativeModelColor~=nil
            and (emitter.nativeModelColor.primary or emitter.nativeModelColor.secondary),
        'retail native-object record has a decoded color presentation')
      decoded=decoded+1
    end
  end end
  ok(decoded>100,'shared native color presentation covers retail records')
end

local callbackError = Packets.build({slots = {{index = 0, generation = 1,
  active = true, mode = 8, commandPointer = 0x8416C83C, event = {}}}}, {
  resolvePlacement = function() error("placement ABI unavailable") end,
  resolveGeometry = function() return {resolved = false} end,
})
ok(#callbackError.packets == 1 and callbackError.diagnostics[1].code
  == "native-object-placement-unresolved"
  and callbackError.diagnostics[1].message:match("placement ABI unavailable"),
  "resolver failures degrade to explicit diagnostics")

local callbackPacket = Packets.build({slots = {{index = 0, generation = 1,
  active = true, mode = 8, commandPointer = 0x8416C83C, event = {},
  drawPackets = {{placement = {x = 1}, geometry = {shape = 7}}}}}})
ok(callbackPacket.packets[1].placement.source == "native-draw-callback"
  and callbackPacket.packets[1].geometry.source == "native-draw-callback"
  and #callbackPacket.diagnostics == 0,
  "explicit draw-callback payloads prove packet boundaries")

print(("%d checks passed (Stadium 2 native-object packets)"):format(checks))
