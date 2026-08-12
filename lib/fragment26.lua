local Fragment26 = {}

local byte = string.byte
local sub = string.sub
local floor = math.floor

Fragment26.ROM_START = 0x15E8B0
Fragment26.ROM_END = 0x165C50
Fragment26.VRAM_BASE = 0x81000000
Fragment26.VRAM_END = Fragment26.VRAM_BASE + (Fragment26.ROM_END - Fragment26.ROM_START)
Fragment26.TABLE_START = 0x81000020
Fragment26.TABLE_END = 0x81000180
Fragment26.CODE_START = 0x81000180
Fragment26.DESCRIPTOR_SIZE = 0x08

Fragment26.RUNTIME_NAMES = {
  [0x80073EC0] = "scale",
  [0x8007AEF0] = "mtxxfmf",
  [0x8007AFA0] = "random",
  [0x8007CFF0] = "mtxcatl",
}

Fragment26.ROOT_PHASES = {
  [0x810033DC] = { 5 },
  [0x81003680] = { 2 },
  [0x810039CC] = { 2 },
  [0x81003A74] = { 2 },
  [0x81003B78] = { 2 },
  [0x81003C30] = { 2 },
  [0x81003CC0] = { 2 },
  [0x81003DAC] = { 0, 2 },
  [0x81005524] = { 2 },
  [0x81005AC0] = { 2 },
  [0x81005DB4] = { 2 },
  [0x81005F38] = { 2 },
  [0x81005F80] = { 0 },
}

Fragment26.FUNCTION_STARTS = {
  0x81000180, 0x810001D4, 0x81000248, 0x810002C4, 0x810004FC,
  0x81000550, 0x810006C4, 0x8100072C, 0x81000894, 0x810009C0,
  0x81000E54, 0x8100107C, 0x8100124C, 0x81001F14, 0x810020E0,
  0x810023AC, 0x810024E0, 0x8100338C, 0x810033DC, 0x8100343C,
  0x8100348C, 0x810034C0, 0x81003510, 0x81003524, 0x8100352C,
  0x81003680, 0x81003750, 0x8100375C, 0x81003768, 0x810037E0,
  0x810038BC, 0x81003910, 0x81003948, 0x81003990, 0x810039CC,
  0x81003A20, 0x81003A74, 0x81003AC0, 0x81003B78, 0x81003C30,
  0x81003CC0, 0x81003D50, 0x81003DAC, 0x81003E60, 0x81003ECC,
  0x81003F44, 0x81003F58, 0x810045C4, 0x81004818, 0x81005480,
  0x81005524, 0x81005628, 0x81005758, 0x810059D0, 0x81005AC0,
  0x81005B50, 0x81005DB4, 0x81005E00, 0x81005F38, 0x81005F80,
  0x81005FB0, 0x81005FBC, 0x81005FC8, 0x81005FE0, 0x81005FF8,
  0x8100600C,
}

local function u32be(data, offset)
  local a, b, c, d = byte(data, offset + 1, offset + 4)
  if not d then return nil end
  return ((a * 256 + b) * 256 + c) * 256 + d
end

local function hex32(value)
  if value == nil then return "-" end
  return ("0x%08X"):format(value % 0x100000000)
end

function Fragment26.containsVram(address)
  address = tonumber(address)
  return address ~= nil and address >= Fragment26.VRAM_BASE and address < Fragment26.VRAM_END
end

function Fragment26.romOffset(address)
  if not Fragment26.containsVram(address) then return nil end
  return Fragment26.ROM_START + address - Fragment26.VRAM_BASE
end

function Fragment26.vramAddress(romOffset)
  romOffset = tonumber(romOffset)
  if romOffset == nil or romOffset < Fragment26.ROM_START or romOffset >= Fragment26.ROM_END then return nil end
  return Fragment26.VRAM_BASE + romOffset - Fragment26.ROM_START
end

function Fragment26.isDescriptor(address)
  address = tonumber(address)
  if address == nil or address < Fragment26.TABLE_START or address >= Fragment26.TABLE_END then return false end
  return (address - Fragment26.TABLE_START) % Fragment26.DESCRIPTOR_SIZE == 0
end

function Fragment26.decodeJump(word, pc)
  word = tonumber(word)
  pc = tonumber(pc)
  if word == nil or pc == nil then return nil end
  local opcode = floor(word / 0x4000000)
  if opcode ~= 0x02 and opcode ~= 0x03 then return nil end
  local upper = (pc + 4) % 0x100000000
  upper = upper - (upper % 0x10000000)
  local target = upper + (word % 0x4000000) * 4
  return {
    kind = opcode == 0x02 and "j" or "jal",
    target = target,
    functionInfo = Fragment26.functionInfo and Fragment26.functionInfo(target) or nil,
  }
end

function Fragment26.descriptor(rom, address)
  if type(rom) ~= "string" then return nil, "ROM data is required" end
  if not Fragment26.isDescriptor(address) then return nil, "address is not a fragment26 descriptor" end
  local romOffset = Fragment26.romOffset(address)
  if not romOffset or romOffset + Fragment26.DESCRIPTOR_SIZE > #rom then return nil, "descriptor is outside ROM" end
  local word0 = u32be(rom, romOffset)
  local word1 = u32be(rom, romOffset + 4)
  local jump = Fragment26.decodeJump(word0, address)
  return {
    address = address,
    offset = address - Fragment26.VRAM_BASE,
    romOffset = romOffset,
    word0 = word0,
    word1 = word1,
    jump = jump,
    target = jump and jump.target or nil,
  }
end

function Fragment26.descriptorTarget(descriptor)
  if type(descriptor) ~= "table" then return nil, "descriptor is required" end
  local jump = descriptor.jump or Fragment26.decodeJump(descriptor.word0, descriptor.address)
  if not jump or jump.kind ~= "j" then return nil, "descriptor does not begin with a MIPS j" end
  if descriptor.word1 ~= 0 then return nil, "descriptor delay slot is not nop" end
  local info = Fragment26.functionInfo(jump.target)
  if not info or not info.exact then return nil, "descriptor target is not a known fragment26 function" end
  return info, jump
end

function Fragment26.functionInfo(address)
  address = tonumber(address)
  if address == nil then return nil end
  local starts = Fragment26.FUNCTION_STARTS
  local lo, hi = 1, #starts
  local best = nil
  while lo <= hi do
    local mid = floor((lo + hi) / 2)
    if starts[mid] <= address then
      best = mid
      lo = mid + 1
    else
      hi = mid - 1
    end
  end
  if not best then return nil end
  local first = starts[best]
  local finish = starts[best + 1] or Fragment26.VRAM_END
  if address >= finish then return nil end
  return {
    name = ("func_%08X"):format(first),
    start = first,
    finish = finish,
    size = finish - first,
    delta = address - first,
    exact = address == first,
    romStart = Fragment26.romOffset(first),
    romEnd = Fragment26.romOffset(finish - 1) and (Fragment26.romOffset(finish - 1) + 1) or Fragment26.ROM_END,
  }
end

function Fragment26.functionBytes(rom, address)
  local info = Fragment26.functionInfo(address)
  if not info then return nil, "address is not inside a known fragment26 function" end
  if type(rom) ~= "string" then return nil, "ROM data is required" end
  if not info.romStart or not info.romEnd or info.romEnd > #rom then return nil, "function is outside ROM" end
  return sub(rom, info.romStart + 1, info.romEnd), info
end

function Fragment26.classifyWord(value)
  value = tonumber(value)
  if value == nil then return "invalid", nil end
  if value == 0 then return "null", nil end
  if Fragment26.isDescriptor(value) then return "descriptor", { address = value } end
  local fn = Fragment26.functionInfo(value)
  if fn then return "fragment26-function", fn end
  if Fragment26.containsVram(value) then
    return "fragment26-data", {
      address = value,
      offset = value - Fragment26.VRAM_BASE,
      romOffset = Fragment26.romOffset(value),
    }
  end
  if value >= 0x80000000 and value <= 0xBFFFFFFF then return "runtime", { address = value } end
  return "scalar", { value = value }
end

function Fragment26.scanDirectCalls(code, startAddress)
  local calls = {}
  if type(code) ~= "string" then return calls end
  startAddress = tonumber(startAddress) or 0
  local seen = {}
  for offset = 0, #code - 4, 4 do
    local word = u32be(code, offset)
    if word then
      local opcode = floor(word / 0x4000000)
      if opcode == 0x03 then
        local pc = startAddress + offset
        local target = ((pc + 4) % 0x100000000)
        target = target - (target % 0x10000000) + (word % 0x4000000) * 4
        local key = ("%08X:%X"):format(target, offset)
        if not seen[key] then
          seen[key] = true
          calls[#calls + 1] = { offset = offset, address = pc, target = target, indirect = false }
        end
      elseif opcode == 0 and word % 64 == 0x09 then
        calls[#calls + 1] = { offset = offset, address = startAddress + offset, indirect = true }
      end
    end
  end
  return calls
end

function Fragment26.describeWord(value)
  local kind, info = Fragment26.classifyWord(value)
  if kind == "fragment26-function" then
    if info.exact then return kind .. ":" .. info.name end
    return kind .. ":" .. info.name .. ("+0x%X"):format(info.delta)
  end
  if kind == "fragment26-data" then return kind .. (":+0x%X"):format(info.offset) end
  if kind == "descriptor" then return kind .. ":" .. hex32(value) end
  return kind
end


function Fragment26.runtimeName(address)
  return Fragment26.RUNTIME_NAMES[tonumber(address)]
end

function Fragment26.phaseList(address)
  local values = Fragment26.ROOT_PHASES[tonumber(address)]
  if not values then return nil end
  local out = {}
  for i = 1, #values do out[i] = values[i] end
  return out
end

function Fragment26.callGraph(rom, roots)
  if type(rom) ~= "string" then return nil, "ROM data is required" end
  if type(roots) ~= "table" then return nil, "root function list is required" end
  local queue, queued, functions, runtime = {}, {}, {}, {}
  for _, value in ipairs(roots) do
    local info = Fragment26.functionInfo(value)
    if info and info.exact and not queued[info.start] then
      queued[info.start] = true
      queue[#queue + 1] = { start = info.start, depth = 0 }
    end
  end
  local cursor = 1
  while cursor <= #queue do
    local item = queue[cursor]
    cursor = cursor + 1
    local code, info = Fragment26.functionBytes(rom, item.start)
    if not code then return nil, "could not read " .. hex32(item.start) end
    local calls = Fragment26.scanDirectCalls(code, item.start)
    local row = {
      start = item.start,
      depth = item.depth,
      info = info,
      code = code,
      calls = calls,
      callees = {},
    }
    functions[item.start] = row
    for _, call in ipairs(calls) do
      if not call.indirect then
        local target = Fragment26.functionInfo(call.target)
        if target and target.exact then
          row.callees[target.start] = true
          if not queued[target.start] then
            queued[target.start] = true
            queue[#queue + 1] = { start = target.start, depth = item.depth + 1 }
          end
        else
          runtime[call.target] = (runtime[call.target] or 0) + 1
        end
      end
    end
  end
  return { functions = functions, runtimeCalls = runtime }
end

Fragment26.u32be = u32be
Fragment26.hex32 = hex32

return Fragment26
