local Rom = require("mods.STADIUM2_IMPORTER.lib.rom")
local Layout = require("mods.STADIUM2_IMPORTER.lib.layout")

-- Stadium 2's per-species battle-motion table.  The battle overlay copies one
-- 0x1530-byte record into each battler, indexes it in 0x14-byte strides, and
-- passes bytes 0/1 to the body/auxiliary animation selectors.  Entries 0..250
-- are the 251 Gen II moves; entries 251..270 are non-move battle contexts.
local Dispatch = {}

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
  "rom_context_267", "rom_context_268", "rom_context_269",
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
