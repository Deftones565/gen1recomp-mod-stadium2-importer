package.path = "./?.lua;./?/init.lua;" .. package.path

local Rom = require("mods.STADIUM2_IMPORTER.lib.rom")
local FxRom = require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_rom")
local Lifecycle = require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_lifecycle")

local path = os.getenv("STADIUM2_ROM") or arg[1]
if not path then
  io.stderr:write("usage: STADIUM2_ROM=/path/to/stadium2.z64 lua "
    .. "mods/STADIUM2_IMPORTER/tests/stadium2_battle_fx_lifecycle_rom_test.lua\n")
  os.exit(2)
end
local file = assert(io.open(path, "rb"))
local rom = assert(Rom.normalise(assert(file:read("*a"))))
file:close()
assert(#rom == Rom.SIZE and Rom.title(rom):upper() == Rom.US_TITLE,
  "expected the supported Pokemon Stadium 2 US ROM")

local catalog = assert(FxRom.catalog(rom))
local rows = catalog.lifecycle
local metadata = Lifecycle.metadata()
local emptyCount, nonEmptyCount = 0, 0
for id = 0, 29 do
  local row = assert(rows[id])
  local meta = assert(metadata[id])
  assert(meta.init == row.init and meta.update == row.update
    and meta.draw == row.draw, ("lifecycle %d table mismatch"):format(id))
  local isEmpty = row.init == 0 and row.update == 0 and row.draw == 0
  assert(meta.empty == isEmpty, ("lifecycle %d empty flag mismatch"):format(id))
  if isEmpty then emptyCount = emptyCount + 1 else nonEmptyCount = nonEmptyCount + 1 end
end
assert(emptyCount == 6 and nonEmptyCount == 24,
  "ROM has six empty and 24 non-empty lifecycle rows")

local routeCount, moveSet, alternateBank = 0, {}, 0
for moveId = 1, FxRom.MOVE_COUNT do
  local move = assert(catalog.moves[moveId])
  for _, channel in ipairs({move.primaryDispatch, move.alternateDispatch}) do
    for _, entry in ipairs(channel) do
      if entry.kind == "lifecycle" then
        routeCount = routeCount + 1
        moveSet[moveId] = true
        if entry.alternate then alternateBank = alternateBank + 1 end
      end
    end
  end
end
local distinct = 0
for _ in pairs(moveSet) do distinct = distinct + 1 end
assert(routeCount == 34 and distinct == 29 and alternateBank == 18,
  "ROM lifecycle route counts differ")

local function has(moveId, family, channel)
  local list = assert(catalog.moves[moveId])[channel == "A"
    and "alternateDispatch" or "primaryDispatch"]
  for _, entry in ipairs(list) do
    if entry.kind == "lifecycle" and entry.lifecycleId == family then return true end
  end
  return false
end
assert(has(20, 4, "P") and has(20, 23, "A")
  and has(50, 21, "P") and has(50, 27, "A")
  and has(81, 6, "P") and has(81, 26, "A"),
  "paired lifecycle routes for moves 20, 50, and 81 differ")

assert(metadata[2].counterAddress == 0x841A4D4C
  and metadata[4].counterAddress == 0x841A4D4A
  and metadata[12].counterAddress == 0x841A4D00
  and metadata[17].terminationThreshold == 50
  and metadata[20].terminationThreshold == 181,
  "known counter and direct termination metadata differ")
assert(metadata[12].drawGate.first == 2,
  "family 12 draw gate is not retained")

print("stadium2 battle FX lifecycle ROM: 30 rows, 34 routes, 29 moves, "
  .. "18 alternate-bank entries")
