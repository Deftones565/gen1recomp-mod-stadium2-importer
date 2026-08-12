package.path = "./?.lua;./?/init.lua;" .. package.path

local Fragment26 = require("mods.STADIUM2_IMPORTER.lib.fragment26")
local Handlers = require("mods.STADIUM2_IMPORTER.lib.model_handlers")

local checks = 0
local function ok(value, label)
  checks = checks + 1
  if not value then error(("check %d failed: %s"):format(checks, label), 0) end
end

ok(Fragment26.ROM_START == 0x15E8B0, "fragment26 ROM start")
ok(Fragment26.VRAM_BASE == 0x81000000, "fragment26 VRAM base")
ok(Fragment26.romOffset(0x81000000) == 0x15E8B0, "VRAM to ROM base")
ok(Fragment26.romOffset(0x81000030) == 0x15E8E0, "descriptor VRAM to ROM")
ok(Fragment26.vramAddress(0x15E8E0) == 0x81000030, "descriptor ROM to VRAM")
ok(Fragment26.isDescriptor(0x81000030), "used descriptor recognized")
ok(Fragment26.isDescriptor(0x81000140), "late used descriptor recognized")
ok(not Fragment26.isDescriptor(0x81000180), "code start is not descriptor")
ok(not Fragment26.isDescriptor(0x81000034), "unaligned descriptor rejected")
local usedHandlers = {
  0x81000030, 0x81000038, 0x81000040, 0x81000048, 0x81000050,
  0x81000058, 0x81000060, 0x81000068, 0x81000070, 0x81000078,
  0x81000080, 0x81000088, 0x81000140,
}
for _, address in ipairs(usedHandlers) do
  ok(Fragment26.isDescriptor(address), ("audited model handler %08X is in table"):format(address))
end

local first = Fragment26.functionInfo(0x81000180)
ok(first and first.exact and first.name == "func_81000180", "first function boundary")
ok(first and first.finish == 0x810001D4 and first.size == 0x54, "first function size")
local inside = Fragment26.functionInfo(0x81000190)
ok(inside and inside.name == "func_81000180" and inside.delta == 0x10, "function interior resolution")

local kind, info = Fragment26.classifyWord(0x810001D4)
ok(kind == "fragment26-function" and info.exact, "function word classification")
kind, info = Fragment26.classifyWord(0x81000030)
ok(kind == "descriptor", "descriptor word classification")
kind, info = Fragment26.classifyWord(0x81000154)
ok(kind == "fragment26-data" and info.offset == 0x154, "table data classification")
kind = Fragment26.classifyWord(0x80012340)
ok(kind == "runtime", "runtime word classification")
kind = Fragment26.classifyWord(7)
ok(kind == "scalar", "scalar word classification")

local function be32(value)
  return string.char(
    math.floor(value / 0x1000000) % 256,
    math.floor(value / 0x10000) % 256,
    math.floor(value / 0x100) % 256,
    value % 256)
end


local auditedStubs = {
  { 0x81000030, 0x08400E73, 0x810039CC },
  { 0x81000038, 0x084016B0, 0x81005AC0 },
  { 0x81000040, 0x08400E9D, 0x81003A74 },
  { 0x81000048, 0x0840176D, 0x81005DB4 },
  { 0x81000050, 0x08400EDE, 0x81003B78 },
  { 0x81000058, 0x08400F0C, 0x81003C30 },
  { 0x81000060, 0x08400F30, 0x81003CC0 },
  { 0x81000068, 0x084017CE, 0x81005F38 },
  { 0x81000070, 0x08401549, 0x81005524 },
  { 0x81000078, 0x08400DA0, 0x81003680 },
  { 0x81000080, 0x084017E0, 0x81005F80 },
  { 0x81000088, 0x08400F6B, 0x81003DAC },
  { 0x81000140, 0x08400CF7, 0x810033DC },
}
for _, stub in ipairs(auditedStubs) do
  local jump = Fragment26.decodeJump(stub[2], stub[1])
  ok(jump and jump.kind == "j" and jump.target == stub[3], ("jump stub %08X resolves"):format(stub[1]))
end
ok(Fragment26.decodeJump(0, 0x81000030) == nil, "non-jump rejected")

local descriptorRom = string.rep("\0", Fragment26.ROM_START)
descriptorRom = descriptorRom .. string.rep("\0", 0x30) .. be32(0x08400E73) .. be32(0)
local descriptor = Fragment26.descriptor(descriptorRom, 0x81000030)
ok(descriptor and descriptor.target == 0x810039CC, "descriptor exposes jump target")
local targetInfo = Fragment26.descriptorTarget(descriptor)
ok(targetInfo and targetInfo.name == "func_810039CC", "descriptor target resolves to function")

local jal = 0x0C000000 + (math.floor(0x81000180 / 4) % 0x4000000)
local code = be32(jal) .. be32(0) .. be32(0x03E00009) .. be32(0)
local calls = Fragment26.scanDirectCalls(code, 0x81001000)
ok(#calls == 2, "direct and indirect calls found")
ok(not calls[1].indirect and calls[1].target == 0x81000180, "jal target decoded")
ok(calls[2].indirect, "jalr decoded")

local phases = Fragment26.phaseList(0x810033DC)
ok(phases and #phases == 1 and phases[1] == 5, "render handler phase")
phases = Fragment26.phaseList(0x81003DAC)
ok(phases and #phases == 2 and phases[1] == 0 and phases[2] == 2, "dual lifecycle phases")
phases = Fragment26.phaseList(0x81005F80)
ok(phases and #phases == 1 and phases[1] == 0, "registration handler phase")

local graphRom = string.rep("\0", Fragment26.ROM_END)
local function patchWord(data, romOffset, value)
  return data:sub(1, romOffset) .. be32(value) .. data:sub(romOffset + 5)
end
local rootInfo = Fragment26.functionInfo(0x810039CC)
local calleeInfo = Fragment26.functionInfo(0x81003990)
local graphJal = 0x0C000000 + (math.floor(calleeInfo.start / 4) % 0x4000000)
graphRom = patchWord(graphRom, rootInfo.romStart, graphJal)
graphRom = patchWord(graphRom, rootInfo.romStart + 4, 0x03E00008)
graphRom = patchWord(graphRom, calleeInfo.romStart, 0x03E00008)
local graph = Fragment26.callGraph(graphRom, { rootInfo.start })
ok(graph and graph.functions[rootInfo.start] ~= nil, "call graph includes root")
ok(graph and graph.functions[calleeInfo.start] ~= nil, "call graph follows fragment26 callee")

local expectedFamilies = {
  [0x81000030] = "display-list-wrapper",
  [0x81000038] = "dynamic-material-builder",
  [0x81000040] = "display-list-wrapper",
  [0x81000048] = "dynamic-material-builder",
  [0x81000050] = "texture-material-builder",
  [0x81000058] = "visibility-range-enable",
  [0x81000060] = "visibility-range-disable",
  [0x81000068] = "dynamic-material-builder",
  [0x81000070] = "dynamic-object-renderer",
  [0x81000078] = "attribute-transform",
  [0x81000080] = "model-context-register",
  [0x81000088] = "runtime-dispatch-bridge",
  [0x81000140] = "render-time-geometry-pipeline",
}
for descriptorAddress, family in pairs(expectedFamilies) do
  local row = Handlers.info(descriptorAddress)
  ok(row and row.family == family, ("handler family %08X"):format(descriptorAddress))
  local descriptor = nil
  for _, stub in ipairs(auditedStubs) do
    if stub[1] == descriptorAddress then descriptor = stub break end
  end
  ok(descriptor and Handlers.info(descriptor[3]) == row, ("handler target reverse map %08X"):format(descriptorAddress))
end
ok(Fragment26.runtimeName(0x8007AFA0) == "random", "runtime random name")
ok(Fragment26.runtimeName(0x8007AEF0) == "mtxxfmf", "runtime mtxxfmf name")
ok(Fragment26.runtimeName(0x8007CFF0) == "mtxcatl", "runtime mtxcatl name")
ok(Fragment26.runtimeName(0x80073EC0) == "scale", "runtime scale name")

print(("%d checks passed (Stadium 2 fragment26)"):format(checks))
