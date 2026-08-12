package.path = "./?.lua;./?/init.lua;" .. package.path

local checks = 0
local function ok(value, message)
  checks = checks + 1
  if not value then error("FAIL " .. message, 0) end
end

_G.love = {
  graphics = {
    getDimensions = function() return 1024, 768 end,
    getPixelDimensions = function() return 1024, 768 end,
  },
}

local created = {}
local function makeRig(species, variant)
  local rig = {
    species = species,
    variant = variant,
    animIndex = 1,
    frame = 0,
    model = { anims = { { name = "idle", frames = 30 }, { name = "attack", frames = 18 } } },
    steps = 0,
  }
  function rig:setContext() self.animIndex = 1 return true end
  function rig:setAnimation(index) self.animIndex = index self.frame = 0 return true end
  function rig:step() self.steps = self.steps + 1 self.frame = self.frame + 1 end
  function rig:release() self.released = true end
  created[#created + 1] = rig
  return rig
end

local importer = {}
function importer.configure(options) importer.count = options.count end
function importer.available() return true end
function importer.status() return { state = "ready" } end
function importer.autoImport() return true end
function importer.newRenderer(species, variant) return makeRig(species, variant) end

package.loaded["mods.STADIUM2_IMPORTER.lib.importer"] = importer
local BattleViewer = require("mods.STADIUM2_IMPORTER.tests.battle_viewer")

local stackItems = {}
local stack = {}
function stack:top() return stackItems[#stackItems] end
function stack:pop() return table.remove(stackItems) end
function stack:push(v) stackItems[#stackItems + 1] = v end
local game = { stack = stack }

ok(BattleViewer.wrapSpecies(0) == 251, "species wraps backward")
ok(BattleViewer.wrapSpecies(252) == 1, "species wraps forward")
local sw, sh = BattleViewer.surfaceSize(1024, 768)
ok(sw == 1024 and sh == 768, "battle viewer uses native 1024x768 surface")
local l = BattleViewer.layoutForSize(1024, 768)
ok(l.player.x >= 0 and l.player.y >= 0 and l.player.x + l.player.w <= 1024 and l.player.y + l.player.h <= 768, "player slot inside surface")
ok(l.foe.x >= 0 and l.foe.y >= 0 and l.foe.x + l.foe.w <= 1024 and l.foe.y + l.foe.h <= 768, "foe slot inside surface")

local viewer = BattleViewer.new(game, importer)
ok(importer.count == 251, "battle viewer requests all 251 species")
ok(viewer.playerSpecies == 25 and viewer.foeSpecies == 248, "battle starts with two distinct model fixtures")
ok(viewer.playerRig and viewer.foeRig, "battle loads both rigs")
ok(viewer.selected == "foe", "foe starts selected")

viewer:onKeyPressed("right")
ok(viewer.foeSpecies == 249, "right cycles selected foe")
viewer:onKeyPressed("tab")
ok(viewer.selected == "player", "tab changes selected side")
viewer:onKeyPressed("left")
ok(viewer.playerSpecies == 24, "left cycles selected player")
viewer:onKeyPressed("s")
ok(viewer.playerVariant == "shiny" and viewer.playerRig.variant == "shiny", "shiny toggle reloads selected side")
viewer:onKeyPressed("e")
ok(viewer.playerRig.animIndex == 2, "animation cycles on selected side")
viewer:onKeyPressed("space")
local psteps, fsteps = viewer.playerRig.steps, viewer.foeRig.steps
viewer:update(1 / 60)
ok(viewer.playerRig.steps == psteps and viewer.foeRig.steps == fsteps, "pause stops both battle animations")
viewer:onKeyPressed("space")
viewer:update(1 / 60)
ok(viewer.playerRig.steps == psteps + 1 and viewer.foeRig.steps == fsteps + 1, "update advances both battle animations")
viewer:release()
ok(viewer.playerRig == nil and viewer.foeRig == nil, "release drops both rigs")

_G.love = nil
print(("%d checks passed (Stadium 2 battle viewer)"):format(checks))
