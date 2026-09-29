package.path="./?.lua;./?/init.lua;"..package.path
-- FREE CAMERA ADDITION (user-requested, non-native): camera-placed particles
-- (descriptor bit 0x1, e.g. the Vice Grip / Guillotine / Bite jaws) leave at
-- the hit, where Stadium cuts to the defender.
local checks=0
local function ok(v,m) checks=checks+1 if not v then error("FAIL "..m,0) end end
local Follow=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_camera_follow")

-- which particles
local jaw={kind="common-particle",descriptorFlags=0x91,descriptorMode=0,effectId=4,particleId=10}
ok(Follow.placed(jaw),"the jaws (descriptor 0x91, mode 0) are camera-placed")
ok(not Follow.placed({kind="common-particle",descriptorFlags=0x90,descriptorMode=0}),
  "without descriptor bit 0x1 a particle is placed natively")
ok(not Follow.placed({kind="common-particle",descriptorFlags=0x91,descriptorMode=7}),
  "screen particles (mode 7) are not touched")
ok(not Follow.placed({kind="screen-particle",descriptorFlags=0x91,descriptorMode=0}),
  "only common-particle packets")

-- hiding by effect
local f=Follow.new()
ok(not f:isHidden(jaw),"nothing hidden to begin with")
f:hideEffect(4)
ok(f:isHidden(jaw) and not f:isHidden({effectId=5}),"hiding is per effect")

-- hide at the hit, through the battle adapter
local hidden,created,nextId={},nil,0
local importer={betaBattleFxEnabled=function() return true end,
  newBattleFxPlayer=function(options)
    created=options
    return {runtime={frame=0},
      -- like Runtime:trigger, the effect id
      trigger=function(_,context) nextId=nextId+1 return nextId end,
      finish=function() end,setRouteSignal=function() end,
      hideCameraPlaced=function(_,id) hidden[#hidden+1]=id return true end}
  end}
local Adapter=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_battle_adapter")
local adapter=assert(Adapter.new(importer,{}))
ok(created and created.cameraFollowExtension==true,"battles enable the addition (the viewer does not)")
local move=adapter:trigger(12,"player",false)
ok(#hidden==0,"nothing hidden before the hit")
ok(adapter:impact(12,"player",1)=="fail" and #hidden==0,"a failed move (result 1) has no cut: nothing hidden")
local action,impactEffect=adapter:impact(12,"player",nil)
ok(action=="impact" and #hidden==1 and hidden[1]==move,
  "at the impact the move bank's camera-placed particles leave")
ok(impactEffect and hidden[1]~=impactEffect,"the impact bank itself is not hidden")
adapter:impact(12,"player",nil)
ok(#hidden==1,"each move bank is hidden once")

print(checks.." checks passed (battle FX free-camera addition)")
