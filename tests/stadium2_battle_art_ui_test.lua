-- Run the real composeWorld handoff without GPU or ROM data.
local f=assert(io.open("lib/gen1_battle.lua","rb"));local s=f:read("*a");f:close()
local a=assert(s:find("function Scene:composeWorld()",1,true))
local b=assert(s:find("local function animationProjection",a,true))
local calls=0
local ui={drawHostedUI=function(ctx)
 assert(ctx.battle and ctx.canvas and ctx.box and ctx.statusAvailable==true)
 ctx.drawHUDs();calls=calls+1;return true
end}
local Scene={}
local env=setmetatable({Scene=Scene,love={graphics={}},
 modRef={find=function(id) assert(id=="BATTLE_ART_VOXEL_FORK");return {exports={battlePresentation=ui}} end},
 UIOwnership={claimStatus=function() return true end,withNativeStatus=function(_,fn)return fn()end},
 originals={drawHUDs=function(battle) assert(battle:colorMode()==false) end},
},{__index=_G})
local chunk=assert(loadstring(s:sub(a,b-1)));setfenv(chunk,env);chunk()
local target={}
local battle={}
local scene=setmetatable({readyFrame=true,hudBox={scale=2},width=320,battle=battle,
 copyForComposite=function() return target,1,1 end},{__index=Scene})
assert(scene:composeWorld()==target)
assert(calls==1 and scene.battleArtUI and scene.statusHudOwned)
assert(rawget(battle,"colorMode")==nil)
print("Stadium Battle Art UI handoff: passed")
