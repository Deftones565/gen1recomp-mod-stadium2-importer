-- Stadium resting pose (841139D0): selection rules and Actor playback.
-- Needs no ROM. Run from the Gen1Recomp repository root.
package.path = "./?.lua;./?/init.lua;" .. package.path
local RestPose = require("mods.STADIUM2_IMPORTER.lib.battle_rest_pose")
local Actor = require("mods.STADIUM2_IMPORTER.lib.battle_actor")

local checks = 0
local function ok(value, message)
  checks = checks + 1
  if not value then error("FAIL " .. message, 0) end
end

-- Selection order and species rules.
local function pose(condition, species) return RestPose.select(condition, species) end
ok(pose({}, 25).context == "idle" and pose({}, 25).loop, "no condition keeps the idle loop")
ok(pose({asleep = true}, 25).context == "rom_context_261" and pose({asleep = true}, 25).loop,
  "asleep loops context 261")
ok(pose({flying = true, asleep = true}, 25).context == "rom_context_262",
  "flying (262) is checked before sleep")
ok(pose({underground = true}, 50).context == "rom_context_258"
  and pose({underground = true}, 50).hold == 0x28, "Diglett holds 258 at frame 40")
ok(pose({underground = true}, 51).hold == 0x30, "Dugtrio holds 258 at frame 48")
ok(pose({underground = true, asleep = true}, 25).hidden, "other species underground are hidden")
ok(pose({frozen = true}, 25).context == "hit" and pose({frozen = true}, 25).hold == 6,
  "frozen holds the hit clip at frame 6")
for _, species in ipairs({35, 73, 41, 188}) do
  ok(pose({frozen = true}, species).hold == 0, ("species %d freezes on frame 0"):format(species))
end
ok(pose({frozen = true, asleep = true}, 25).context == "hit", "frozen is checked before sleep")

-- Actor playback with a stub renderer.
local calls = {}
local clips = {idle = true, hit = true, rom_context_261 = true, rom_context_262 = true,
  rom_context_258 = true, attack = true}
local renderer = {finished = false, frame = 0,
  setContext = function(self, name, loop)
    calls[#calls + 1] = {"set", name, loop}
    if not clips[name] then return false end
    self.finished = false
    return true
  end,
  seekFrame = function(_, frame) calls[#calls + 1] = {"seek", frame}; return true end,
  setMove = function() return false end,
  setHandlerRuntime = function() end,
  step = function(self, dt) calls[#calls + 1] = {"step", dt} end,
}
local warnings = {}
local actor = Actor.new("player", {warn = function(m) warnings[#warnings + 1] = m end})
actor.renderer, actor.dex, actor.context = renderer, 25, "idle"
actor:play("idle", true)
calls = {}
actor:setRest({})
actor:update(1 / 30)
ok(calls[1][1] == "step" and calls[1][2] == 1 / 30, "an explicit idle loop is not restarted")

calls = {}
actor:setRest({asleep = true})
actor:update(1 / 30)
ok(calls[1][1] == "set" and calls[1][2] == "rom_context_261" and calls[1][3] == true,
  "falling asleep switches to the looping sleep clip")
calls = {}
actor:update(1 / 30)
ok(#calls == 1 and calls[1][1] == "step", "the same pose is not reapplied every frame")

calls = {}
actor:setRest({frozen = true})
actor:update(1 / 30)
ok(calls[1][2] == "hit" and calls[2][1] == "seek" and calls[2][2] == 6
  and calls[3][1] == "step" and calls[3][2] == 0, "frozen holds the hit clip without advancing")

-- A clip played over the pose returns to the pose when it ends.
actor:hit()
calls = {}
renderer.finished = true
actor:update(1 / 30)
ok(actor.context == "idle" and calls[#calls][1] == "seek" and calls[#calls][2] == 6,
  "after the hit clip the frozen pose comes back")

-- A missing clip keeps idle and is reported once.
clips.rom_context_261 = nil
actor:play("idle", true)
actor:setRest({asleep = true})
calls = {}
actor:update(1 / 30)
actor:update(1 / 30)
ok(calls[1][2] == "rom_context_261" and calls[2][2] == "idle" and #warnings == 1
  and warnings[1]:find("rom_context_261", 1, true), "a missing sleep clip falls back to idle once, reported")

print(("%d checks passed (battle rest pose)"):format(checks))
