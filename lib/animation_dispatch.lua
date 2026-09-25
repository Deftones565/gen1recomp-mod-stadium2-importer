local Rom = require("mods.STADIUM2_IMPORTER.lib.rom")
local Layout = require("mods.STADIUM2_IMPORTER.lib.layout")

-- Stadium 2's per-species battle-motion table.  The battle overlay copies one
-- 0x1530-byte record into each battler, indexes it in 0x14-byte strides, and
-- passes bytes 0/1 to the body/auxiliary animation selectors.  Entries 0..250
-- are the 251 Gen II moves; entries 251..270 are non-move battle contexts.
local Dispatch = {}

-- 84113014 DMA: 49B780 + 8970 + (species-1)*50, actor+67C.
function Dispatch.contextScaleBytes(rom,species)
  species=tonumber(species)
  if type(rom)~='string' or not species or species%1~=0 or species<1 or species>251 then return nil end
  local offset=0x4A40F0+(species-1)*0x50
  if #rom<offset+0x50 then return nil end
  return rom:sub(offset+1,offset+0x50)
end

-- Exact jump-table aliases of 8411E358. Offsets are zero based.
local contextOffsets={
  [252]=3,[253]=3,[254]=8,[256]=0x12,[257]=0x17,[258]=0x17,[259]=0x17,
  [260]=0x1C,[261]=0x21,[264]=0x26,[265]=0x2B,[266]=0x2B,[267]=0x30,
  [268]=0x35,[269]=0x3A,[270]=0x3A,[271]=0xD,[272]=3,[273]=3,
  [274]=0x49,[276]=0x44,[277]=0x44,[278]=0x44,[279]=0x44,[280]=0x3F,
  [290]=0x49,[291]=0x4E,[292]=0x49,[295]=0x3A,[296]=0xD,[298]=0x49,[299]=0x49}
local dispatchOffsets={[255]=0x67B,[281]=0x13D7,[282]=0x13D3,[283]=0x13D3,[294]=0x13D3}
function Dispatch.contextScale(contextId,contextBytes,dispatchBytes)
  contextId=tonumber(contextId)
  if not contextId then return nil end
  contextId=math.floor(contextId)%65536 -- scheduler +0A / particle +68
  local offset=contextOffsets[contextId]
  local bytes=contextBytes
  if offset==nil then offset=dispatchOffsets[contextId];bytes=dispatchBytes end
  if offset==nil then return 0 end
  if type(bytes)~='string' or #bytes<=offset then return nil end
  local f=require('mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_float')
  return f(bytes:byte(offset+1)*f(.01))
end

-- 8411E244(owner, contextId): marker label for a context emitter. Species
-- table (actor+67C) offsets and dispatch-record (actor+2D4) offsets from its
-- jump table at 84189450; every other ID returns zero.
local contextMarkerOffsets={
  [252]=0x04,[253]=0x04,[254]=0x09,[256]=0x13,[257]=0x18,[258]=0x18,
  [259]=0x18,[260]=0x1D,[261]=0x22,[264]=0x27,[265]=0x2C,[266]=0x2C,
  [267]=0x31,[268]=0x36,[269]=0x3B,[270]=0x3B,[271]=0x0E,[272]=0x04,
  [273]=0x04,[274]=0x4A,[276]=0x45,[277]=0x45,[278]=0x45,[279]=0x45,
  [280]=0x40,[290]=0x4A,[291]=0x4F,[292]=0x4A,[295]=0x3B,[296]=0x0E,
  [298]=0x4A,[299]=0x4A}
local contextMarkerDispatch={[255]=0x13DA,[281]=0x13C7,[282]=0x13C6,
  [283]=0x13C6,[294]=0x13C6}
function Dispatch.contextMarker(contextId,contextBytes,dispatchBytes)
  contextId=tonumber(contextId)
  if not contextId then return nil end
  contextId=math.floor(contextId)%65536
  local offset,bytes=contextMarkerOffsets[contextId],contextBytes
  if offset==nil then offset,bytes=contextMarkerDispatch[contextId],dispatchBytes end
  if offset==nil then return 0 end
  if type(bytes)~='string' or #bytes<=offset then return nil end
  return bytes:byte(offset+1)
end

-- func_84113014 DMA-loads 0x30 bytes per species from this US ROM table;
-- func_84112704 copies +14/+08 to battler+648/+650 respectively.
Dispatch.BATTLE_PROFILE_START = 0x49DA60
function Dispatch.battleProfileBytes(rom, species)
  species = tonumber(species)
  if type(rom) ~= "string" or not species or species%1~=0
      or species<1 or species>Dispatch.ARCHIVE_RECORDS then return nil end
  local offset=Dispatch.BATTLE_PROFILE_START+(species-1)*0x30
  if #rom<offset+0x30 then return nil end
  return rom:sub(offset+1,offset+0x30)
end

function Dispatch.battleProfile(bytes)
  if type(bytes)~="string" or #bytes~=0x30 then return nil end
  local function float(offset)
    local a,b,c,d=bytes:byte(offset+1,offset+4)
    local exponent=(a%128)*2+math.floor(b/128)
    local mantissa=(b%128)*65536+c*256+d
    if exponent==255 then return nil end
    return (a>=128 and -1 or 1)*math.ldexp(
      exponent==0 and mantissa/8388608 or 1+mantissa/8388608,
      exponent==0 and -126 or exponent-127)
  end
  local center,ground=float(0x14),float(8)
  if not center or not ground then return nil end
  local f32=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_float")
  return {centerY=center,groundY=ground,targetHeight=f32(center-ground),
    bodyHeight=float(4)} -- 84112704: profile+04 -> actor+64C
end

Dispatch.ARCHIVE_START = Layout.ANIMATION_DISPATCH_TABLE_START
Dispatch.ARCHIVE_RECORDS = Layout.ANIMATION_DISPATCH_TABLE_RECORDS
Dispatch.RECORD_SIZE = Layout.ANIMATION_DISPATCH_RECORD_SIZE
Dispatch.ENTRY_SIZE = 0x14
Dispatch.MOVE_COUNT = 251
Dispatch.CONTEXT_COUNT = 20
Dispatch.MOVE_NAMES_START = Layout.MOVE_NAMES_START

-- These names come from battle-overlay call sites, not clip order.  In
-- particular, entry 252 is selected immediately before Stadium calls the
-- Pokemon-cry routine during send-out, while entry 253 is selected by the
-- faint state.  Keep unproven entries numeric instead of inventing roles.
Dispatch.CONTEXTS = {
  "idle", "entrance", "faint", "hit",
  "rom_context_255", "rom_context_256", "rom_context_257",
  "rom_context_258", "rom_context_259", "rom_context_260",
  "rom_context_261", "rom_context_262", "rom_context_263",
  "rom_context_264", "rom_context_265", "rom_context_266",
  "rom_context_267", "sleep", "rom_context_269",
  "rom_context_270",
}
Dispatch.CONTEXT_ENTRY = {}
for index, name in ipairs(Dispatch.CONTEXTS) do
  Dispatch.CONTEXT_ENTRY[name] = Dispatch.MOVE_COUNT + index - 1
end

local function signed8(value)
  if value >= 0x80 then return value - 0x100 end
  return value
end

function Dispatch.decodeRecord(payload)
  if type(payload) ~= "string" or #payload ~= Dispatch.RECORD_SIZE then
    return nil, ("invalid Stadium 2 animation-dispatch record size: %s")
      :format(type(payload) == "string" and #payload or type(payload))
  end
  local rows = { n = Dispatch.MOVE_COUNT + Dispatch.CONTEXT_COUNT }
  for sourceIndex = 0, rows.n - 1 do
    local offset = sourceIndex * Dispatch.ENTRY_SIZE
    rows[sourceIndex] = {
      payload:byte(offset + 1),
      signed8(payload:byte(offset + 2)),
      -- 84114730 copies byte2 into battler+61C for 84109780's joint
      -- query. 8411E22C uses this same byte from context254 for the target.
      fxJoint=payload:byte(offset+3),
      raw=payload:sub(offset+1,offset+Dispatch.ENTRY_SIZE),
    }
  end
  return rows
end

function Dispatch.forSpecies(rom, species)
  species = math.floor(tonumber(species) or -1)
  if type(rom) ~= "string" then return nil, "Stadium 2 ROM bytes are required" end
  if species < 1 or species > Dispatch.ARCHIVE_RECORDS then
    return nil, ("animation-dispatch species record %d is out of range"):format(species)
  end
  local archive = Rom.archiveAt(rom, Dispatch.ARCHIVE_START)
  if not archive or archive.count ~= Dispatch.ARCHIVE_RECORDS then
    return nil, ("Stadium 2 animation-dispatch archive is missing at 0x%X")
      :format(Dispatch.ARCHIVE_START)
  end
  -- Unlike the model and pose archives, this archive has no record-zero
  -- placeholder: record 0 is species 1.  Lua's one-based array index is
  -- therefore the species number itself.
  local record = archive.records[species]
  local bytes, bytesErr = Rom.recordBytes(rom, record)
  if not bytes then return nil, bytesErr end
  local payload, decodeErr = Rom.decompress(bytes)
  if not payload then return nil, decodeErr end
  return Dispatch.decodeRecord(payload)
end

function Dispatch.moveRows(rows)
  local moves = {}
  for moveId = 1, Dispatch.MOVE_COUNT do
    moves[moveId] = rows and rows[moveId - 1] or nil
  end
  return moves
end

function Dispatch.contextRows(rows)
  local contexts = {}
  for index = 1, Dispatch.CONTEXT_COUNT do
    contexts[index] = rows and rows[Dispatch.MOVE_COUNT + index - 1] or nil
  end
  return contexts
end

function Dispatch.moveNames(rom)
  if type(rom) ~= "string" then return nil, "Stadium 2 ROM bytes are required" end
  local names, cursor = {}, Dispatch.MOVE_NAMES_START + 1
  for moveId = 1, Dispatch.MOVE_COUNT do
    local ending = rom:find("\0", cursor, true)
    if not ending then return nil, ("truncated move name %d"):format(moveId) end
    local name = rom:sub(cursor, ending - 1)
    if name == "" or name:find("[^ -~]") then
      return nil, ("invalid move name %d at ROM 0x%X")
        :format(moveId, cursor - 1)
    end
    names[moveId] = name
    cursor = ending + 1
  end
  return names
end

return Dispatch
