local Objects = require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_native_objects")

local checks = 0
local function ok(value, message)
  assert(value, message)
  checks = checks + 1
end

local rgba, alive = Objects.colorAt({mode = 0, period = 2,
  colors = {{10, 20, 30, 40}, {50, 60, 70, 80}}}, 1)
ok(alive and rgba[1] == 50 and rgba[4] == 80,
  "mode-0 colour track selects one RGBA sample per age")
local expired, expiredAlive = Objects.colorAt({mode = 0, period = 2,
  colors = {{10, 20, 30, 40}, {50, 60, 70, 80}}}, 2)
ok(expired == nil and not expiredAlive,
  "colour track terminates when age reaches period")
local interpolated, interpolationAlive = Objects.colorAt({mode = 1, period = 10,
  colors = {{age = 0, rgba = {0, 20, 40, 60}},
    {age = 10, rgba = {100, 120, 140, 160}}}}, 5)
ok(interpolationAlive and interpolated[1] == 50 and interpolated[4] == 110,
  "mode-1 colour track linearly interpolates RGBA keys")
local invalid = Objects.colorAt({mode = 2, period = 2, colors = {}}, 0)
ok(invalid == nil, "unsupported colour controller mode remains unresolved")
local jump=Objects.colorAt({mode=1,period=3,colors={
  {age=0,rgba={0,0,0,0}},{age=1,rgba={0,0,0,255}},
  {age=1,rgba={255,0,0,0}},{age=2,rgba={255,0,0,255}}}},1)
ok(jump[1]==255 and jump[4]==0,"duplicate age selects the right-hand ROM key")

local scheduler = Objects.new({
  resolve = function()
    return {object = {}, delay = 0}
  end,
})
assert(scheduler:enqueue(0x84173DA4, {mode = 2, nativeColorTrack = {
  mode = 1, period = 3, colors = {{age = 0, rgba = {0, 10, 20, 30}},
    {age = 3, rgba = {90, 100, 110, 120}}},
}}))
local snapshot = scheduler:tick(1)
ok(#snapshot.slots == 0 and snapshot.nativeColor[1] == 0
    and #snapshot.colorInstances == 1,
  "mode-2 color track starts at age zero and releases scheduler slot")
scheduler:tick(1)
ok(scheduler:snapshot().nativeColor[1] == 30,
  "persistent native color advances on the 30 Hz scheduler")
scheduler:tick(1)
local finished = scheduler:snapshot()
-- One additional 30 Hz step reaches the terminal period.
scheduler:tick(1)
finished = scheduler:snapshot()
ok(not finished.colorInstances[1].active and finished.nativeColor[1] == 60,
  "terminated color instance retains its last global RGBA")

local clear=Objects.backgroundColor({1,1,1},{0,0,0,128})
ok(clear[1]==123/255 and clear[2]==123/255 and clear[3]==123/255,
  "native background blend quantizes through RGBA5551")
local untouched=Objects.backgroundColor({.1,.2,.3},{255,0,0,0})
ok(untouched[1]==.1 and untouched[2]==.2,"zero alpha preserves the host background")
scheduler:release()
ok(scheduler:snapshot().nativeColor==nil and #scheduler:snapshot().colorInstances==0,
  "release resets global native color state")
local modelTrack={mode=0,period=2,colors={{255,0,0,128},{0,0,255,0}}}
assert(scheduler:enqueue(1,{mode=5,context={sourceSide="enemy"},
  nativeModelColor={primary=modelTrack,secondary=modelTrack,hideAge=1}}))
local model=scheduler:tick().modelColors.enemy
ok(model.color[1]==255 and model.opacity==128,"mode5 writes model blend and opacity separately")
scheduler:tick()
model=scheduler:snapshot().modelColors.enemy
ok(model.color[3]==255 and model.opacity==0,"mode5 updates both channels at 30Hz")
ok(scheduler:snapshot().modelColorInstances[1].flags==0x280,"mode5 applies authored visual flags at hide age")
scheduler:tick()
ok(not scheduler:snapshot().modelColorInstances[1].active
  and scheduler:snapshot().modelColors.enemy.opacity==0,"mode5 retires the visual while model writes persist")
assert(scheduler:enqueue(2,{mode=8,nativeColorTrack=modelTrack}))
local screen=scheduler:tick().screenInstances[1]
ok(screen.shapeId==90 and screen.position[1]==160 and screen.position[2]==120,
  "mode8 uses the ROM screen quad and exact constructor origin")
ok(screen.rgba[1]==255 and scheduler:snapshot().nativeColor==nil,
  "screen color does not overwrite mode2 background state")
scheduler:tick(2)
ok(not scheduler:snapshot().screenInstances[1].active,"mode8 expires at the color period")
scheduler:release()
ok(next(scheduler:snapshot().modelColors)==nil and #scheduler:snapshot().screenInstances==0,
  "release clears screen and model state")
assert(scheduler:enqueue(3,{mode=5,
  context={sourceSide="enemy",targetSide="player",alternate=true},
  nativeModelColor={primary=modelTrack,hideAge=0}}))
scheduler:tick()
ok(scheduler:snapshot().modelColors.player~=nil
  and scheduler:snapshot().modelColors.enemy==nil,"alternate entry point writes the target model")
print(("%d checks passed (Stadium 2 native callbacks)"):format(checks))
