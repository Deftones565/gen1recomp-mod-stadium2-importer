-- The strike marks (Scratch 10, Cut 15, Wing Attack 17, Vine Whip 22, Fury
-- Swipes 154, Slash 163, False Swipe 206, Fury Cutter 210, Steel Wing 211,
-- Rapid Spin 229, Iron Tail 231, Metal Claw 232, Cross Chop 238) keep a
-- mode-7 screen particle alive until age 255; Stadium takes them off with
-- 841089D8(1) (84111C1C), which the first idle record after a turn
-- (84113D7C), every send-out (8411BB04) and status events run. Real ROM
-- catalog and models (the setup of tools/audit_battle_fx.lua).
package.path="./?.lua;./?/init.lua;"..package.path
local prefix="mods.STADIUM2_IMPORTER.lib."
local FxRom=require(prefix.."stadium2_battle_fx_rom")
local Native=require(prefix.."stadium2_battle_fx_native")
local Motion=require(prefix.."stadium2_battle_fx_motion")
local Preview=require("mods.STADIUM2_IMPORTER.tests.stadium2_koffing_croconaw_visual.battle_fx")
local Rom=require(prefix.."rom")
local Layout=require(prefix.."layout")
local Extract=require(prefix.."extract")
local Fragment=require(prefix.."fragment")
local Renderer=require(prefix.."renderer")
local Dispatch=require(prefix.."animation_dispatch")
local path=os.getenv("STADIUM2_ROM") or "mods/STADIUM2_IMPORTER/baseroms/stadium2.z64"
local file=io.open(path,"rb")
if not file then assert(os.getenv("STADIUM2_REQUIRE_ROM")~="1","ROM required");print("SKIP battle FX idle clear ROM");return end
local rom=file:read("*a");file:close()
local catalog=assert(FxRom.catalog(rom))
local names=assert(Dispatch.moveNames(rom))
local archive=assert(Rom.archiveAt(rom,Layout.MODEL_TABLE_START))
local function actor(species)
  local data=assert(Rom.decompress(assert(Rom.recordBytes(rom,archive.records[species+1]))))
  local info=assert(Extract.fragmentInfo(data))
  data=Extract.runtimeFragmentForSpecies(rom,species,data)
  Fragment.setBase(info.sourceBase)
  local model=assert(Fragment.extract(data,"audit-species-"..species))
  local rows=assert(Dispatch.forSpecies(rom,species));local raw={}
  for i=0,rows.n-1 do raw[#raw+1]=rows[i].raw end
  model.species=species;model.fxDispatch=table.concat(raw)
  model.fxBattleProfile=Dispatch.battleProfileBytes(rom,species)
  model.fxContextScales=Dispatch.contextScaleBytes(rom,species)
  -- Only the skeleton/markers are needed; model geometry is not GPU-tested.
  model.prims={};model.textures={}
  if type(model.rootScale)=="table" then
    model.rootScaleVector=model.rootScale;model.rootScale=model.rootScale[1]
  end
  return {renderer=assert(Renderer.new(model,{flipY=false})),context="idle"}
end
local actors={player=actor(159),enemy=actor(109)}
local slots={player={-7.5,0,0},enemy={7.5,0,0}}
local host={visualActor=function(_,side)return actors[side]end,
  modelMatrix=function(_,side)
    local s=side=="player" and .05 or -.05
    return {0,0,s,slots[side][1],0,.05,0,0,-s,0,0,0,0,0,0,1}
  end}
local scene={scene={host=host,actors=actors},world={actorSlots=slots,groundY=0},
  camera={eye={0,8,20},focus={0,2,0},up={0,1,0},
    projection={1,0,0,0,0,1.333,0,0,0,0,-1.002,-.2002,0,0,-1,0}}}

local function renderer(model)
  assert(model and model.prims,"missing model geometry")
  return {model=model,parts={},setHandlerRuntime=function()end,
    updatePose=function()end,release=function()end,
    drawScene=function() return true end}
end
local preview=Preview.new({rom=rom,releaseModel=function()end,
  importer={newRendererFromModel=renderer}})
preview.catalog=catalog
local checks=0
local function ok(v,m) checks=checks+1 if not v then error("FAIL "..m,0) end end
local function alive(p)
  local n=0
  for _,particle in ipairs(p:snapshot().particles or {}) do
    if particle.event and particle.event.mode==7 then n=n+1 end
  end
  return n
end
for _,move in ipairs({10,15,17,22,154,163,206,210,211,229,231,232,238}) do
  assert(preview:start(move,"player",false,scene))
  for frame=1,150 do
    if frame==120 then preview:finish() end
    preview:step()
  end
  ok(alive(preview.player)>0,("move %d: the slash (mode 7) is still alive at tick 150"):format(move))
  preview.player:abortAll()
  ok(alive(preview.player)==0,("move %d: 841089D8(1) takes the slash off"):format(move))
  ok(#(preview.player:snapshot().particles or {})==0,("move %d: nothing else survives the clear"):format(move))
end

-- the adapter's clear (Adapter:clearAll) is 841089D8(1): the pool, then Dig's
-- 84108974(1) signal while its variant route is still armed
local Adapter=require(prefix.."stadium2_battle_fx_battle_adapter")
local cleared,signalled=0,nil
local fake=setmetatable({player={abortAll=function() cleared=cleared+1 end},
  signalEffect=function(_,entry,side) signalled={entry,side} return true end},{__index=Adapter})
Adapter.clearAll(fake)
ok(cleared==1 and signalled==nil,"a clear without Dig's variant route only clears")
fake.digVariantArmed,fake.routeMode,fake.routeMove,fake.routeSource=true,1,91,"enemy"
Adapter.clearAll(fake)
ok(cleared==2 and signalled and signalled[1]==0x12D and signalled[2]=="enemy","Dig's variant route signals 0x12D for its owner")

-- the scene: once when the battle first waits for a command after a turn
-- (D_841911FA), again only after the next turn start; send-outs after the
-- first turn clear too
local Scene=require(prefix.."battle_scene")
local calls=0
local s=setmetatable({battleFx={update=function() end,clearAll=function() calls=calls+1 end}},{__index=Scene})
local waiting=false
s.stadiumAwaitingCommand=function() return waiting end
Scene.updateBattleFx(s,1/30)
ok(calls==0,"no clear while the turn plays")
waiting=true
Scene.updateBattleFx(s,1/30);Scene.updateBattleFx(s,1/30)
ok(calls==1,"one clear when the command menu comes up")
Scene.stadiumCameraSendOut(s,"player")
ok(calls==1,"the opening's send-outs do not clear")
Scene.stadiumCameraTurn(s)
Scene.updateBattleFx(s,1/30)
ok(calls==2,"the next turn's menu clears again")
Scene.stadiumCameraSendOut(s,"enemy")
ok(calls==3,"a later send-out clears (8411BB04)")
-- 84118C08: a status-family event (residual, stat change, heal, drain heal,
-- trap, sandstorm hit) clears before its own effect; 84119630's weather
-- start/end entries do not.
Scene.stadiumCameraEntry(s,0x101,"player")
ok(calls==4,"a residual (poison) event clears (84118C08)")
Scene.stadiumCameraEntry(s,0x114,"enemy")
ok(calls==5,"a drain heal clears before it plays")
Scene.stadiumCameraEntry(s,0x107,"player")
ok(calls==5,"rain's turn entry (84119630) does not clear")
print(checks.." checks passed (battle FX idle clear vs ROM)")
