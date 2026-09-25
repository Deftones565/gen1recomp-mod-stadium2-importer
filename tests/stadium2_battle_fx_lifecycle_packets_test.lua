package.path = "./?.lua;./?/init.lua;" .. package.path

local Packets = require(
  "mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_lifecycle_packets")

local checks = 0
local function ok(value, message)
  checks = checks + 1
  if not value then error("FAIL " .. message, 0) end
end

local snapshot = {
  frame = 12,
  instances = {
    {id = 7, familyId = 4, counter = 126, frame = 126, active = true,
      context = {effectId = 9, programId = 259, address = 0x84156E58,
        sourceSide = "player", targetSide = "enemy"}},
  },
  packets = {
    {instanceId = 7, familyId = 4, command = 0xDA380003,
      pointer = 0x841A4D08, drawHelper = 0x8415DBBC,
      requiresDrawHelper = true, counter = 126, frame = 126},
  },
}

local unresolved = Packets.build(snapshot)
ok(unresolved.frame == 12 and #unresolved.packets == 0,
  "unproven lifecycle geometry is not emitted as a render packet")
ok(#unresolved.evidence == 1 and unresolved.evidence[1].instanceId == 7
  and unresolved.evidence[1].familyId == 4,
  "command evidence preserves stable instance and family identity")
local evidence = unresolved.evidence[1]
ok(evidence.command == 0xDA380003 and evidence.pointer == 0x841A4D08
  and evidence.drawHelper == 0x8415DBBC and evidence.counter == 126
  and evidence.context.sourceSide == "player"
  and evidence.context.targetSide == "enemy",
  "evidence preserves audited command, helper, counter, and raw context")
ok(#unresolved.diagnostics == 1
  and unresolved.diagnostics[1].code == "lifecycle-model-unresolved"
  and unresolved.diagnostics[1].kind == "lifecycle-packet",
  "missing model proof is a structured lifecycle diagnostic")

-- Resolver output is accepted only when it explicitly marks its model as
-- proven.  The model payload remains opaque to this renderer-neutral layer.
local resolverCalls = 0
local resolved = Packets.build(snapshot, {
  resolveModel = function(instance, packet, context)
    resolverCalls = resolverCalls + 1
    ok(instance.id == 7 and packet.familyId == 4
      and context.effectId == 9, "resolver receives identity and copied context")
    return {proven = true, modelId = "stadium-model-4",
      geometry = {vertexCount = 24}}
  end,
})
ok(resolverCalls == 1 and #resolved.packets == 1
  and resolved.packets[1].renderable
  and resolved.packets[1].modelResolution.modelId == "stadium-model-4",
  "explicit model proof creates one renderer-neutral packet")
ok(resolved.packets[1].command == 0xDA380003
  and resolved.packets[1].pointer == 0x841A4D08
  and resolved.packets[1].instanceId == 7,
  "render packet retains exact lifecycle command evidence")

resolved.packets[1].context.sourceSide = "mutated"
resolved.packets[1].modelResolution.geometry.vertexCount = 99
ok(snapshot.instances[1].context.sourceSide == "player"
  and snapshot.packets[1].instanceId == 7
  and snapshot.packets[1].context == nil,
  "packet and resolver data are detached from source snapshot")

local rejected = Packets.build(snapshot, {
  modelResolver = function() return {proven = false, shapeId = 88} end,
})
ok(#rejected.packets == 0 and rejected.diagnostics[1].code == "lifecycle-model-unresolved",
  "unproven resolver output cannot fabricate a packet")

local failed = Packets.build(snapshot, {
  resolveModel = function() error("model lookup failed") end,
})
ok(#failed.packets == 0
  and failed.diagnostics[1].code == "lifecycle-model-resolver-error"
  and tostring(failed.diagnostics[1].message):find("model lookup failed", 1, true),
  "resolver failures remain structured diagnostics")

-- Runtime snapshots nest the lifecycle manager snapshot.  Outer frame and
-- manager diagnostics are retained without requiring the runtime module.
local nested = Packets.build({frame = 15, diagnostics = {
  {code = "upstream", severity = "warning", effectId = 9, kind = "lifecycle",
    message = "retained"},
}, lifecycles = snapshot}, {resolveModel = function()
  return {proven = true, shapeId = 4}
end})
ok(nested.frame == 15 and #nested.packets == 1
  and #nested.diagnostics == 1 and nested.diagnostics[1].code == "upstream",
  "nested runtime snapshot converts lifecycle state and retains diagnostics")

-- Malformed or mismatched evidence is never passed to a renderer.
local malformed = Packets.build({frame = 1, packets = {
  {instanceId = 2, familyId = 4, command = 0, pointer = 0},
  "not-a-packet",
}}, {resolveModel = function() return {proven = true, modelId = 1} end})
ok(#malformed.packets == 0 and #malformed.evidence == 1,
  "malformed command evidence is not emitted")
ok(#malformed.diagnostics == 2
  and malformed.diagnostics[1].code == "lifecycle-command-unproven"
  and malformed.diagnostics[2].code == "lifecycle-packet-malformed",
  "malformed lifecycle entries have explicit diagnostics")

print(("stadium2 battle FX lifecycle packets: %d checks passed"):format(checks))
