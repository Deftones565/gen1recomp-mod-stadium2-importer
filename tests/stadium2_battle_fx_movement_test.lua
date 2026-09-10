package.path = "./?.lua;./?/init.lua;" .. package.path

local Motion = require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_motion")
local single = require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_float")
local checks = 0
local function ok(v, m) checks = checks + 1; assert(v, m) end
local function near(a, b, m)
  ok(math.abs(a - b) < 1e-5, (m .. " (%.9g ~= %.9g)"):format(a, b))
end

-- Deliberately non-trigonometric values make the ROM formula and axis order
-- observable without approximating the Stadium lookup tables.
local TA, TB = {}, {}
for i = 1, 4096 do TA[i], TB[i] = 0, 0 end
TA[2], TA[3] = 2, 5       -- y=1, x=2 after >> 4
TB[2], TB[3] = 7, 3
local tables = {tableA = TA, tableB = TB}

local base = {
  position = {10, 20, 30}, rotation = {32, 16, 0}, age = 0,
  nativeAgeEndpoint = false,
  nativeMotion = {
    direction = {mode = 7, angles = {32, 16, 0},
      speed = {startAge = 1, initial = 10, target = 20, step = 5}},
    verticalSubtract = {startAge = 1, value = 2.5},
  },
}
local state = Motion.init(base)
local first = Motion.step(state, 1, {trigTables = tables})
-- mode 7: dx=TA[y>>4]*(speed*TB[x>>4]), dy=TA[x>>4]*-speed,
-- dz=TB[y>>4]*(speed*TB[x>>4]); speed 10 * .01 = .1.
near(first.position[1], 10.6, "mode 7 adds native X displacement")
near(first.position[2], 19.475, "mode 7 adds Y then applies vertical subtraction")
near(first.position[3], 32.1, "mode 7 adds native Z displacement")
near(first.nativeMotionSpeed, single(.1), "native initial speed is binary32 scaled")
local second = Motion.step(first, 1, {trigTables = tables})
near(second.position[1], 11.5, "mode 7 accumulates the next speed vector")
near(second.position[2], 18.7, "vertical subtraction repeats after its start age")
near(second.position[3], 35.25, "mode 7 accumulates Z persistently")

local replacing = Motion.init({
  position = {0, 0, 0}, age = 0, nativeAgeEndpoint = false,
  nativeMotion = {direction = {mode = 8, angles = {32, 16, 0},
    speed = {startAge = 1, initial = 10, target = 20, step = 5}}},
})
local r1 = Motion.step(replacing, 1, {trigTables = tables})
local r2 = Motion.step(r1, 1, {trigTables = tables})
near(r1.position[1], .6, "mode 8 writes its first accumulated offset")
near(r2.position[1], .9, "mode 8 replaces prior offset before position assembly")
near(r2.position[2], -.75, "mode 8 replacement uses the current speed")
near(r2.position[3], 3.15, "mode 8 replacement updates Z")

local vertical = Motion.init({position = {0, 1, 0}, age = 0,
  nativeAgeEndpoint = false, nativeMotion = {
    verticalSubtract = {startAge = 2, value = 10},
  }})
vertical = Motion.step(vertical, 1)
near(vertical.position[2], 1, "vertical subtraction waits for start age")
vertical = Motion.step(vertical, 1)
near(vertical.position[2], .9, "vertical subtraction uses value times .01")

local missing = Motion.step(Motion.init({nativeAgeEndpoint = false,
  nativeMotion = {direction = {mode = 7, angles = {0, 0, 0},
    speed = {startAge = 0, initial = 100}}}}), 1)
local found = false
for _, d in ipairs(missing.diagnostics or {}) do
  if d.code == "unsupported-native-motion-trig" then found = true end
end
ok(found, "mode 7 reports missing lookup tables explicitly")

local mode2=Motion.init({particleIndex=3,nativeMotion={direction={mode=4,
  speed={mode=2,startAge=5,initial=100,target=0,step=10,random=20}}}})
near(mode2.nativeMotionSpeed,1.6,"speed mode2 initializes particle-index distribution")
mode2=Motion.step(mode2,1)
near(mode2.position[2],1.6,"pre-start movement retains constructor speed")
local calls=0
local mode1=Motion.init({nativeMotion={direction={mode=5,
  speed={mode=1,startAge=1,initial=100,target=0,step=10,random=20}}}},
  {randomScalar=function()calls=calls+1;return 5 end})
mode1=Motion.step(mode1,1)
near(mode1.position[2],-1.05,"mode1 initializes downward speed once")
ok(calls==1,"native initialized speed does not reroll at the ramp start")
local ramped=Motion.init({nativeMotion={verticalRamp={startAge=2,step=-20,target=-50,random=0}}})
ramped=Motion.step(ramped,1)
near(ramped.position[2],0,"vertical ramp waits for start")
ramped=Motion.step(ramped,1)
near(ramped.position[2],-.2,"vertical ramp updates signed speed before displacement")
ramped=Motion.step(ramped,1)
ramped=Motion.step(ramped,1)
near(ramped.position[2],-1.1,"vertical ramp clamps its speed at the authored target")
local percent=Motion.init({nativeMotion={verticalRamp={startAge=1,step=0,target=100,random=10,base=50}}},
  {randomScalar=function(variant)ok(variant==1,"vertical percent uses centered RNG");return -5 end})
percent=Motion.step(percent,1)
near(percent.position[2],.45,"vertical percent multiplies displacement after the authored ramp")
print(("%d checks passed (Stadium 2 native movement)"):format(checks))
