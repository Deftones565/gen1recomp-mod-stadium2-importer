-- 841343FC's handoff (84124BA0, codes 7 / 8 / 9) on Gold's engine: the
-- second side's first event of a turn carries it unless a side fainted.
-- Run from the Gen1Recomp repository root. ROM-free.
package.path = "./?.lua;./?/init.lua;" .. package.path

local checks = 0
local function ok(value, message)
  checks = checks + 1
  if not value then error("FAIL " .. message, 0) end
end

local Gen2 = require("mods.STADIUM2_IMPORTER.lib.gen2_battle")
local Battle = require("src.battle.gen2.Battle")
local Mon = require("src.battle.gen2.Mon")

local TYPES = {
  NORMAL = { id = "NORMAL", index = 0, category = "physical" },
  FLYING = { id = "FLYING", index = 2, category = "physical" },
  FIRE = { id = "FIRE", index = 20, category = "special" },
}
local MOVES = {
  TACKLE = { id = "TACKLE", name = "TACKLE", power = 35, type = "NORMAL",
    accuracy = 100, pp = 35, effect = "EFFECT_NORMAL_HIT" },
  SPLASH = { id = "SPLASH", name = "SPLASH", power = 0, type = "NORMAL",
    accuracy = 100, pp = 40, effect = "EFFECT_SPLASH" },
}
local GROWTH = { GROWTH_MEDIUM_SLOW = { numerator = 6, denominator = 5,
  squared = -15, linear = 100, constant = 140 } }
local POKEMON = {
  growthRates = GROWTH,
  CYNDAQUIL = { id = "CYNDAQUIL", index = 155, name = "CYNDAQUIL",
    baseStats = { hp = 39, attack = 52, defense = 43, speed = 65,
      specialAttack = 60, specialDefense = 50 },
    types = { "FIRE", "FIRE" }, catchRate = 45, baseExp = 65,
    growthRate = "GROWTH_MEDIUM_SLOW", genderRatio = 31,
    levelMoves = { { level = 1, move = "TACKLE" } }, evolutions = {} },
  PIDGEY = { id = "PIDGEY", index = 16, name = "PIDGEY",
    baseStats = { hp = 40, attack = 45, defense = 40, speed = 56,
      specialAttack = 35, specialDefense = 35 },
    types = { "NORMAL", "FLYING" }, catchRate = 255, baseExp = 55,
    growthRate = "GROWTH_MEDIUM_SLOW", genderRatio = 127,
    levelMoves = { { level = 1, move = "TACKLE" } }, evolutions = {} },
}
local DATA = { pokemon = POKEMON, moves = MOVES,
  type_chart = { types = TYPES, matchups = {} }, items = {} }
local perfect = { attack = 15, defense = 15, speed = 15, special = 15 }
perfect.hp = Mon.hpDV(perfect)

local function newBattle(level, wildMove)
  local player = Mon.new(DATA, "CYNDAQUIL", level or 10, { dvs = perfect })
  player.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
  local wild = Mon.new(DATA, "PIDGEY", 5, { dvs = perfect })
  wild.moves = { { id = wildMove or "TACKLE", pp = 35, maxPp = 35 } }
  local battle = Battle.new({ data = DATA, party = { player }, wild = wild,
    random = function() return 0 end })
  battle:takeEvents()
  return battle, player, wild
end

local function handoffs(events)
  local found = {}
  for index, event in ipairs(events) do
    if event.stadiumHandoff then found[#found + 1] = { index = index, event = event } end
  end
  return found
end

assert(Gen2.install())

-- an ordinary turn: both attack, nobody faints
do
  local battle = newBattle(10)
  local events = battle:takeTurn({ kind = "move", move = "TACKLE" })
  local found = handoffs(events)
  ok(#found == 1, "one handoff per turn")
  local first = battle.firstMover
  local second = first == "player" and "enemy" or "player"
  ok(found[1].event.stadiumHandoff.side == second and found[1].event.stadiumHandoff.code == 7,
    "on the second side, code 7")
  ok(found[1].index > 1, "after the first side's events")
end

-- the second side asleep: code 8
do
  -- the CYNDAQUIL is faster: the PIDGEY moves second
  local battle, player, wild = newBattle(10)
  wild.status = "sleep"; wild.statusTurns = 3
  local events = battle:takeTurn({ kind = "move", move = "TACKLE" })
  local found = handoffs(events)
  ok(battle.firstMover == "player" and #found == 1 and found[1].event.stadiumHandoff.side == "enemy"
    and found[1].event.stadiumHandoff.code == 8, "an asleep second side gets code 8")
end

-- the first action knocks the other out: no handoff
do
  local battle, player, wild = newBattle(60)
  local events = battle:takeTurn({ kind = "move", move = "TACKLE" })
  ok(#handoffs(events) == 0, "no handoff once a side has fainted")
end

Gen2.uninstall()
local events = select(1, newBattle(10)):takeTurn({ kind = "move", move = "TACKLE" })
ok(#handoffs(events) == 0, "uninstall restores the engine")

print(("stadium2_turn_handoff_test: %d checks passed"):format(checks))
