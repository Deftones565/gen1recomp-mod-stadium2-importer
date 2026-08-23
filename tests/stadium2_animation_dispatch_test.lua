package.path = "./?.lua;./?/init.lua;" .. package.path

local Dispatch = require("mods.STADIUM2_IMPORTER.lib.animation_dispatch")
local Semantics = require("mods.STADIUM2_IMPORTER.lib.animation_semantics")
local Build = require("mods.STADIUM2_IMPORTER.lib.build")
local Layout = require("mods.STADIUM2_IMPORTER.lib.layout")
local Rom = require("mods.STADIUM2_IMPORTER.lib.rom")

local function ok(value, message)
  if not value then error("FAIL " .. message, 0) end
end

local path = os.getenv("STADIUM2_ROM")
  or "mods/STADIUM2_IMPORTER/baseroms/stadium2.z64"
local file = assert(io.open(path, "rb"), "Stadium 2 ROM is required: " .. path)
local rom = file:read("*a")
file:close()

local bulbasaur = assert(Dispatch.forSpecies(rom, 1))
local names = assert(Dispatch.moveNames(rom))
ok(names[1] == "POUND" and names[165] == "STRUGGLE"
    and names[251] == "BEAT UP",
  "all move names come from the Stadium 2 ROM string table")
ok(bulbasaur.n == 271, "ROM record has 251 moves and 20 contexts")
ok(Dispatch.CONTEXT_ENTRY.idle == 251
    and Dispatch.CONTEXT_ENTRY.entrance == 252
    and Dispatch.CONTEXT_ENTRY.faint == 253
    and Dispatch.CONTEXT_ENTRY.hit == 254
    and Dispatch.CONTEXT_ENTRY.sleep == 268,
  "battle-overlay-proven semantic entries are explicit")
ok(bulbasaur[0][1] == 2 and bulbasaur[0][2] == 0,
  "first Bulbasaur move route matches ROM")
ok(bulbasaur[164][1] == 3 and bulbasaur[164][2] == 1,
  "last Gen I move route matches ROM")
ok(bulbasaur[250][1] == 2 and bulbasaur[250][2] == 0,
  "last Gen II move route matches ROM")
ok(bulbasaur[251][1] == 0 and bulbasaur[251][2] == 4,
  "first battle-context route matches ROM")

local animations = {}
for index = 0, 6 do animations[index + 1] = { index = index } end
local moves = assert(Semantics.apply(animations, {}, Build, nil, bulbasaur))
ok(#moves == 251 and moves[1][1] == bulbasaur[0][1] - 1
    and moves[251][1] == bulbasaur[250][1] - 1,
  "runtime selectors normalize while ROM entries become public move IDs")
ok(moves[1].romSelector == bulbasaur[0][1],
  "normalized routes preserve their raw ROM selector")
ok(moves[1].selectorBase == 1,
  "Bulbasaur uses the ROM-proven default-plus-external selector layout")
ok(animations[2].moveIds[1] == 1,
  "exported animation metadata identifies its ROM-routed moves")

local rhyhorn = assert(Dispatch.forSpecies(rom, 111))
local rhyhornAnimations = {}
for index = 0, 4 do rhyhornAnimations[index + 1] = { index = index } end
local _, rhyhornContexts = assert(Semantics.apply(rhyhornAnimations, {}, Build,
  nil, rhyhorn))
ok(rhyhornAnimations[3].name == "attack_default"
    and #rhyhornAnimations[3].moveIds > 0,
  "Rhyhorn move-routed selector 3 is an attack")
ok(rhyhornAnimations[4].name == "faint"
    and #rhyhornAnimations[4].moveIds == 0,
  "Rhyhorn faint selector is not polluted with move IDs")
ok(rhyhornContexts[3] == rhyhorn[253][1] - 1
    and rhyhornContexts[3] == 3,
  "Rhyhorn faint uses its normalized species-correct ROM selector")

local rattata = assert(Dispatch.forSpecies(rom, 19))
local rattataAnimations = {}
for index = 0, 5 do rattataAnimations[index + 1] = { index = index } end
local _, rattataContexts = assert(Semantics.apply(rattataAnimations, {}, Build,
  nil, rattata))
ok(Semantics.selectorBase(rattataAnimations, rattata) == 0,
  "Rattata's ROM domain directly indexes all six pose files")
ok(rattataContexts[3] == 4 and rattataContexts[4] == 5
    and rattataAnimations[5].name == "faint"
    and rattataAnimations[6].name == "hit"
    and rattataContexts[18] == 1
    and rattataAnimations[2].name == "sleep",
  "Rattata viewer animations 2, 5, and 6 are sleep, faint, and hit")

local poseArchive = assert(Rom.archiveAt(rom, Layout.POSE_TABLE_START))
local directLayout, shiftedLayout, exceptionalTop = 0, 0, 0
local directSpecies = {}
for species = 1, 251 do
  local posePayload = assert(Rom.decompress(assert(Rom.recordBytes(rom,
    poseArchive.records[species + 1]))))
  local poseFiles = assert(Rom.archiveAt(posePayload, 0)).count
  local speciesRows = assert(Dispatch.forSpecies(rom, species))
  local maximum = 0
  for rowIndex = 0, speciesRows.n - 1 do
    maximum = math.max(maximum, speciesRows[rowIndex][1])
  end
  ok(maximum <= poseFiles + 1,
    ("species %d selector %d exceeds its %d-file ROM domain")
      :format(species, maximum, poseFiles))
  if maximum < poseFiles then
    directLayout = directLayout + 1
    directSpecies[#directSpecies + 1] = species
  else
    shiftedLayout = shiftedLayout + 1
    if maximum > poseFiles then exceptionalTop = exceptionalTop + 1 end
  end
end
ok(directLayout == 20 and shiftedLayout == 231 and exceptionalTop == 2,
  "all species select their ROM-authored direct or default-plus-external layout")
ok(table.concat(directSpecies, ",")
    == "9,16,17,18,19,21,46,64,69,70,101,104,105,122,131,136,144,178,193,198",
  "the complete direct-layout species set remains ROM-derived")

print("stadium2 ROM animation dispatch tests passed")
