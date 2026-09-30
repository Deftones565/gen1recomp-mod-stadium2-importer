package.path="./?.lua;./?/init.lua;"..package.path
-- The STADIUM camera controller end to end on the ported camera: battle
-- start (the split-screen arena intro), an attack (84114A04: the move's
-- shot, program 0 on the attacker), the defender's hit (841170A0: program 1),
-- 30 Hz ticks, and the pose handed to the arena frame.
local file=io.open(os.getenv("STADIUM2_ROM") or "mods/STADIUM2_IMPORTER/baseroms/stadium2.z64","rb")
if not file then assert(os.getenv("STADIUM2_REQUIRE_ROM")~="1","ROM required");print("SKIP battle camera controller");return end
local rom=file:read("*a");file:close()
local prefix="mods.STADIUM2_IMPORTER.lib."
local FxRom=require(prefix.."stadium2_battle_fx_rom")
local StadiumCamera=require(prefix.."stadium2_battle_camera")
local Camera=require(prefix.."battle_camera")
local checks=0
local function ok(v,m) checks=checks+1 if not v then error("FAIL "..m,0) end end

local fragment=assert(FxRom.catalog(rom)).lifecycleAssets.fragment79
local warnings={}
local camera=assert(StadiumCamera.new({rom=rom,fragment79=fragment,seed=99,
  warn=function(m) warnings[#warnings+1]=m end}))
local scene={actors={player={dex=25,mon={hp=35}},enemy={dex=16,mon={hp=30}}},
  modelMatrix=function() error("no model in this test") end}

local function finite(v) return v==v and v>-1e7 and v<1e7 end
local function sane(pose)
  for k=1,3 do if not (finite(pose.eye[k]) and finite(pose.focus[k])) then return false end end
  return pose.fov>=20 and pose.fov<=90
end

camera:update(scene,1)
local pose=camera:pose()
ok(sane(pose),"battle start gives a finite pose (eye "..table.concat(pose.eye,",")..")")
local dx,dy,dz=pose.eye[1]-pose.focus[1],pose.eye[2]-pose.focus[2],pose.eye[3]-pose.focus[3]
ok(math.sqrt(dx*dx+dy*dy+dz*dz)>1,"the eye is away from the target")

-- Pound's attack selector is 0x28: a random shot of D_84183BDC
local mem=camera.cam.mem
ok(mem:u16(0x841849B6+1*8)==0x28,"Pound's attack selector is 0x28")
local allowed={}
for i=0,5 do allowed[mem:u16(0x84183BDC+i*2)]=true end
local seen={}
for _=1,30 do
  camera:attack(scene,"enemy",1)
  seen[mem:u16(0x85000000+0x98)]=true
  camera:update(scene,0.5)
  ok(sane(camera:pose()),"an attack gives a finite pose")
end
local count=0
for shot in pairs(seen) do ok(allowed[shot],"attack shot "..shot.." is one of D_84183BDC"); count=count+1 end
ok(count>=3,"attack shots vary ("..count.." of 6 seen)")
ok(camera.cam.missing==nil,"program 0 runs only ported handlers")
ok(mem:u32(0x85000000+0x10)==0x84110718 and mem:u32(0x85000000+4)==0x85002000,"program 0 is on the attacker")

-- the defender's hit: program 1 on the defender, event code by condition
camera:hit(scene,"player",1,{asleep=true})
ok(mem:u16(0x85003000+4)==0x0B,"an asleep defender is hit with event 0x0B")
camera:hit(scene,"player",1,{frozen=true})
ok(mem:u16(0x85003000+4)==0x0D,"a frozen defender is hit with event 0x0D")
camera:hit(scene,"player",1)
ok(mem:u16(0x85003000+4)==0x0A,"an ordinary hit is event 0x0A")
ok(mem:u32(0x85000000+0x10)==0x84110F64 and mem:u32(0x85000000+4)==0x85001000,"program 1 is on the defender")
for _=1,20 do camera:update(scene,0.1) ok(sane(camera:pose()),"the hit gives a finite pose") end
ok(camera.cam.missing==nil,"program 1 runs only ported handlers")

-- the hit's follow-up (841170A0 / 841187E4) with the scene's signals: the
-- counter starts at the impact (+0x619), the jolt comes the next tick by the
-- result (3 -> 20), and the state ends at +0x61A (the timer 0, kind 0xFF)
do
  local hs={actors=scene.actors,modelMatrix=scene.modelMatrix}
  local settled=false
  hs.stadiumHitResult=function(_,side,move) return side=="player" and move==1 and 3 or nil end
  hs.stadiumClipFrames=function(_,side,context) return context=="hit" and 0x60 or nil end
  hs.stadiumHpSettled=function() return settled end
  camera:hit(hs,"player",1)
  local a=0x85001000
  ok(camera.runs[a]~=nil,"the hit's follow-up runs on the defender")
  ok(mem:s16(a+0x7E8)==mem:s8(a+0x619)-1,"the frame counter starts just before the impact frame (+0x619)")
  ok(mem:u16(0x85003000+6)==0x258,"84116B40 sets the timer 0x258")
  local length=mem:u8(a+0x61A)
  ok(length==0x60,"the 0x0A length is the hit clip's frames (0x60)")
  camera:update(hs,1/30)
  ok(mem:f32(0x85000000+0x8C)==0,"program 1's setup runs first")
  camera:update(hs,1/30)
  ok(mem:f32(0x85000000+0x8C)>0,"then the jolt starts")
  local jolted=mem:f32(0x85000000+0x8C)
  ok(jolted>15 and jolted<=20,"a super-effective hit jolts by 20 (84117880), got "..jolted)
  settled=true
  local ended=false
  for _=1,0x80 do
    camera:update(hs,1/30)
    if mem:u8(a+0x7F6)==1 or camera.runs[a]==nil then ended=true break end
  end
  ok(ended and mem:u16(0x85003000+6)==0,"the state ends and releases the timer")
  ok(mem:u8(a+0x61A)<length,"the settled HP bar brought the end forward (841175D4)")
  ok(mem:u8(a+0x61F)==0xFF,"the end resets the defender's kind (841206D0)")
  -- an unknown clip length or result is reported, not guessed
  local unknown={actors=scene.actors,modelMatrix=scene.modelMatrix}
  camera:hit(unknown,"player",1)
  ok(camera.runs[a]==nil,"without the hit clip's length the end is not scheduled")
  local said=false
  for _,w in ipairs(warnings) do if w:find("hit clip length is unknown",1,true) then said=true end end
  ok(said,"the unknown hit clip length is reported")
  hs.stadiumHitResult=function() return nil end
  camera:hit(hs,"player",1)
  camera:update(hs,1/30)
  ok(mem:f32(0x85000000+0x8C)==0,"an unknown result skips the jolt")
end

-- a turn begins: a turn shot of D_84183C60 and program 10 on the player
local turnShots={}
for i=0,4 do turnShots[mem:u16(0x84183C60+i*2)]=true end
camera:turnStart(scene)
camera.idle=nil -- the command menu's idle cycle is tested on its own below
ok(turnShots[mem:u16(0x85000000+0x98)],"the turn shot is one of D_84183C60")
ok(mem:u32(0x85000000+0x10)==0x8410ED30 and mem:u32(0x85000000+4)==0x85001000,"program 10 is on the player")
for _=1,90 do camera:update(scene,1/30) ok(sane(camera:pose()),"the turn orbit gives a finite pose") end
ok(mem:u32(0x85000000+0x10)==0x8411123C,"the orbit arrives and program 10 ends")
ok(camera.cam.missing==nil,"program 10 runs only ported handlers")
-- then event 0x5B on the side acting first (8411F9D8, program 18), once
-- the orbit released the event timer and the host names that side
ok(camera.firstMoverPending==true,"0x5B waits while the first mover is not known yet")
scene.stadiumFirstMover=function() return "enemy" end
camera:update(scene,1/30)
ok(mem:u16(0x85003000+4)==0x5B and camera.firstMoverPending==nil,"the first mover's event is 0x5B")
ok(mem:u32(0x85000000+0x10)==0x8410F3E8 and mem:u32(0x85000000+4)==0x85002000,"program 18 is on the first mover")
ok(mem:u16(0x85000000+0x98)==0x24 or mem:u16(0x85000000+0x98)==0x26,"program 18's shot is 0x24 or 0x26")
local released=false
for _=1,200 do
  camera:update(scene,1/30) ok(sane(camera:pose()),"program 18 gives a finite pose")
  if mem:u16(0x85003000+6)==0 then released=true break end
end
ok(released and mem:u32(0x85000000+0x10)==0x8411123C,"program 18 settles, then ends the timer and its slot")
ok(camera.cam.missing==nil,"program 18 runs only ported handlers")
camera:turnStart(scene)
camera.idle=nil
camera:attack(scene,"player",1)
ok(camera.firstMoverPending==nil,"a newer event replaces the waiting 0x5B")
for _=1,90 do camera:update(scene,1/30) end
ok(mem:u16(0x85003000+4)~=0x5B,"the replaced 0x5B does not play")
scene.stadiumFirstMover=nil

-- a faint: a faint shot of D_84183C74 and program 11 on that side
local faintShots={}
for i=0,2 do faintShots[mem:u16(0x84183C74+i*2)]=true end
camera:faint(scene,"enemy")
ok(faintShots[mem:u16(0x85000000+0x98)],"the faint shot is one of D_84183C74")
ok(mem:u32(0x85000000+0x10)==0x841107D8 and mem:u32(0x85000000+4)==0x85002000,"program 11 is on the fainting side")
for _=1,30 do camera:update(scene,0.1) ok(sane(camera:pose()),"the faint gives a finite pose") end
ok(camera.cam.missing==nil,"program 11 runs only ported handlers")

-- a later send-out (family 12; the battle's first is family 24, tested
-- below): the opening shot (0 or 6), 0x61 frames, then program 26
camera.openingPhase=nil
camera:sendOut(scene,"player")
local opening=mem:u16(0x85000000+0x98)
ok(opening==0 or opening==6,"the send-out opens on shot 0 or 6")
ok(camera.sendingOut and camera.sendingOut.actor==0x85001000,"the send-out runs on the player")
for _=1,0x61 do camera:update(scene,1/30) ok(sane(camera:pose()),"the send-out gives a finite pose") end
ok(camera.sendingOut==nil,"the send-out hands over after 0x61 frames")
ok(mem:u32(0x85000000+0x10)==0x84110910 and mem:u32(0x85000000+4)==0x85001000,"program 26 follows on the player")
ok(camera.cam.missing==nil,"the send-out runs only ported handlers")
-- a later event for that actor ends a running send-out
camera:sendOut(scene,"enemy")
for _=1,5 do camera:update(scene,1/30) end
camera:turnStart(scene)
ok(camera.sendingOut==nil,"turn start ends a running send-out")

-- a miss: the defender dodges (0x11 / 0x12 frozen / 0x13 asleep) into
-- program 1, on a random shot of D_84183BDC
camera:dodge(scene,"enemy",1)
ok(mem:u16(0x85003000+4)==0x11,"a dodge is event 0x11")
ok(allowed[mem:u16(0x85000000+0x98)],"the dodge shot is one of D_84183BDC")
ok(mem:u32(0x85000000+0x10)==0x84110F64 and mem:u32(0x85000000+4)==0x85002000,"program 1 is on the dodging side")
camera:dodge(scene,"enemy",1,{frozen=true})
ok(mem:u16(0x85003000+4)==0x12 and mem:u16(0x85000000+0x98)==3,"a frozen defender's dodge is 0x12, shot 3")
camera:dodge(scene,"enemy",1,{asleep=true})
ok(mem:u16(0x85003000+4)==0x13 and mem:u16(0x85000000+0x98)==0x16,"an asleep defender's dodge is 0x13, shot 0x16")
for _=1,20 do camera:update(scene,0.1) ok(sane(camera:pose()),"the dodge gives a finite pose") end

-- Red's miss line is recognised with the engine's own text and name
local okG,Gen1=pcall(require,"mods.STADIUM2_IMPORTER.lib.gen1_battle")
local okE,EffectRegistry=pcall(require,"src.battle.EffectRegistry")
local okR,RomText=pcall(require,"src.core.RomText")
if okG and okE and okR and Gen1.Scene and Gen1.Scene.stadiumCameraMiss then
  local seen
  local fake=setmetatable({stadiumCameraDodge=function(_,side,move) seen={side,move} end},{__index=Gen1.Scene})
  local battle={data={moves={TACKLE={index=33}}},player={isPlayer=true,name="PIKACHU",lastMove="TACKLE"},
    enemy={isPlayer=false,name="PIDGEY",lastMove="TACKLE"}}
  function battle:romText(label,fallback,...) return RomText(self.data,label,fallback,...) end
  local line=battle:romText("_AttackMissedText","%s's\nattack missed!",EffectRegistry.displayName(battle.enemy))
  fake:stadiumCameraMiss(battle,{text=line})
  ok(seen and seen[1]=="player" and seen[2]==33,"the enemy's miss makes the player dodge Tackle")
  seen=nil
  fake:stadiumCameraMiss(battle,{text="PIKACHU used\nTACKLE!"})
  ok(seen==nil,"other lines are not a miss")
else
  print("SKIP Gen 1 miss line (host modules unavailable here)")
end

-- Red's turn-check lines give Stadium's family 17 events (84127194)
if okG and okE and okR and Gen1.Scene and Gen1.Scene.stadiumCameraTurnText then
  local seen={}
  local fake=setmetatable({stadiumCameraTurnCheck=function(_,side,code) seen[#seen+1]={side,code} end},{__index=Gen1.Scene})
  local battle={data={moves={}},player={isPlayer=true,name="PIKACHU"},enemy={isPlayer=false,name="PIDGEY"}}
  function battle:romText(label,fallback,...) return RomText(self.data,label,fallback,...) end
  local D=EffectRegistry.displayName
  fake:stadiumCameraTurnText(battle,{text=battle:romText("_FastAsleepText","%s\nis fast asleep!",D(battle.enemy))})
  fake:stadiumCameraTurnText(battle,{text=battle:romText("_IsFrozenText","%s\nis frozen solid!",D(battle.player))})
  fake:stadiumCameraTurnText(battle,{text=battle:romText("_FullyParalyzedText","%s's\nfully paralyzed!",D(battle.enemy))})
  fake:stadiumCameraTurnText(battle,{text=battle:romText("_MustRechargeText","%s\nmust recharge!",D(battle.player))})
  fake:stadiumCameraTurnText(battle,{text=battle:romText("_WokeUpText","%s\nwoke up!",D(battle.enemy))})
  fake:stadiumCameraTurnText(battle,{text=battle:romText("_IsConfusedText","%s\nis confused!",D(battle.player))})
  fake:stadiumCameraTurnText(battle,{text="PIKACHU used\nTACKLE!"})
  local okS,Strings=pcall(require,"src.core.Strings")
  if okS then
    fake:stadiumCameraTurnText(battle,{text=Strings("%s\ndug a hole!",D(battle.enemy))})
  end
  ok(#seen==(okS and 7 or 6),"the turn-check and charge lines are recognised, other lines are not")
  -- the self-hit goes to the side of the "is confused!" line before it
  local hit
  local fake2=setmetatable({stadiumCameraTurnCheck=function(sc,side,code)
    if code==0x26 then sc.stadiumConfusedSide=side end
    if code==1 then hit=side end end},{__index=Gen1.Scene})
  fake2.stadiumCameraSelfHit=require("mods.STADIUM2_IMPORTER.lib.battle_scene").stadiumCameraSelfHit
  fake2:stadiumCameraTurnText(battle,{text=battle:romText("_IsConfusedText","%s\nis confused!",D(battle.enemy))})
  fake2:stadiumCameraTurnText(battle,{text=battle:romText("_HurtItselfText","It hurt itself in\nits confusion!")})
  ok(hit=="enemy","the self-hit takes the confused side")
  if okS then ok(seen[7][1]=="enemy" and seen[7][2]==0x1B,"the enemy dug a hole: code 0x1B") end
  ok(seen[5][1]=="enemy" and seen[5][2]==0x1D,"woke up is event 0x1D")
  ok(seen[6][1]=="player" and seen[6][2]==0x26,"is confused is event 0x26")
  ok(seen[1][1]=="enemy" and seen[1][2]==4,"the enemy's fast asleep is event 4")
  ok(seen[2][1]=="player" and seen[2][2]==2,"the player's frozen solid is event 2")
  ok(seen[3][1]=="enemy" and seen[3][2]==0x36,"fully paralyzed is event 0x36")
  ok(seen[4][1]=="player" and seen[4][2]=="react","must recharge takes 84124594's reaction")
else
  print("SKIP Gen 1 turn-check lines (host modules unavailable here)")
end

-- the turn check on the controller: family 17, 84124594's reaction by
-- status, and full paralysis / in love through their families
camera:turnCheck(scene,"enemy","react",{asleep=true})
ok(mem:u16(0x85003000+4)==4 and mem:u16(0x85000000+0x98)==0,"an asleep mon's reaction is event 4, shot 0")
ok(mem:u32(0x85000000+0x10)==0x84110718 and mem:u32(0x85000000+4)==0x85002000,"program 0 on the checked side")
ok(mem:u8(0x85002000+0x61F)==0xFF,"84119CF0 sets the kind to 0xFF")
camera:turnCheck(scene,"player","react",{frozen=true})
ok(mem:u16(0x85003000+4)==2,"a frozen mon's reaction is event 2")
camera:turnCheck(scene,"player","react",{})
ok(mem:u16(0x85003000+4)==3,"any other reaction is event 3")
camera:turnCheck(scene,"enemy",0x2C)
ok(mem:u16(0x85003000+4)==0x2C,"defrosted is event 0x2C")
camera:turnCheck(scene,"enemy",0x36)
ok(mem:u16(0x85003000+4)==0x36,"fully paralyzed goes to family 28's 0x36")
camera:turnCheck(scene,"enemy",6)
ok(mem:u16(0x85003000+4)==6,"in love goes to family 9's 6")
-- Dig (family 15) and Substitute (family 11)
camera:attack(scene,"player",0x5B)
ok(mem:u16(0x85000000+0x98)==0x0E,"Dig takes shot 0x0E")
local dig=false
for i=0,6 do if mem:u32(0x85000000+8+i*8)==0x84110640 then dig=true end end
ok(dig,"Dig loads program 6 (84110640) on the digger")
camera:update(scene,1/30)
ok(camera:pose().fov==45,"program 6 holds FOV 45")
ok(camera.cam.missing==nil,"Dig runs only ported handlers")
local ownRecord=mem:f32(0x85002000+0x64C)
camera:attack(scene,"enemy",0xA4)
ok(mem:u16(0x85000000+0x98)==0 and mem:u32(0x85000000+0x10)==0x84110718,"Substitute: its move shot (selector 0) and program 0")
for _=1,30 do camera:update(scene,1/30) end
ok(mem:s16(0x85002000+0x658)==16,"no doll before the 31st tick")
camera:update(scene,1/30)
ok(mem:s16(0x85002000+0x658)==0xFC,"the 31st tick swaps in the doll (84112B64)")
ok(mem:f32(0x85002000+0x64C)==80,"the doll's camera record is loaded (row 0xFC)")
ok(mem:u32(0x85000000+0x10)==0x84110718 and mem:u16(0x85000000+0x98)==0,"8411B3B8: shot 0 and program 0 after the swap")
scene.substituteActive={enemy=false}
for _=1,40 do camera:update(scene,1/30) end
ok(mem:s16(0x85002000+0x658)==0xFC,"the doll stays until Stadium swaps it back")
scene.substituteActive=nil
-- Substitute faded (family 21): the swap back on the 31st tick
camera:turnCheck(scene,"enemy",0x27)
ok(mem:u16(0x85003000+4)==0x27 and mem:u16(0x85000000+0x98)==0,"SUBSTITUTE faded: event 0x27, shot 0")
for _=1,30 do camera:update(scene,1/30) end
ok(mem:s16(0x85002000+0x658)==0xFC,"the doll holds for 30 ticks")
camera:update(scene,1/30)
ok(mem:s16(0x85002000+0x658)==16 and mem:f32(0x85002000+0x64C)==ownRecord,"84112C98 restores the Pokemon's own record on the 31st tick")
ok(mem:u32(0x85000000+0x10)==0x84110718,"and program 0 again")
-- dragged out (family 25)
mem:setU8(0x85001000+0x61F,7)
mem:setU16(0x85000000+0x98,5)
camera:turnCheck(scene,"player",0x2F)
ok(mem:u16(0x85003000+4)==0x2F and mem:u16(0x85000000+0x98)==5,"dragged out: nothing until the next tick")
camera:update(scene,1/30)
ok(mem:u16(0x85000000+0x98)==0 and mem:u32(0x85000000+4)==0x85001000,"the next tick: shot 0, program 0 on the new Pokemon")
for _=1,64 do camera:update(scene,1/30) end
ok(mem:u8(0x85001000+0x61F)==7,"the kind holds until the 66th tick")
camera:update(scene,1/30)
ok(mem:u8(0x85001000+0x61F)==0xFF,"the 66th tick resets the kind")
for _=1,10 do camera:update(scene,0.1) ok(sane(camera:pose()),"Dig and Substitute give a finite pose") end

-- 8411FF1C ends the jolt on every event
mem:setF32(0x85000000+0x8C,25)
camera:turnCheck(scene,"enemy",4)
ok(mem:f32(0x85000000+0x8C)==0,"a new event ends the camera jolt (8411FF1C: 8410B578(0))")

-- the confusion self-hit (family 16)
camera:selfHit(scene,"enemy")
ok(mem:u16(0x85003000+4)==1 and mem:u8(0x85002000+0x61F)==0xFF,"the self-hit is event 1, kind 0xFF")
ok(allowed[mem:u16(0x85000000+0x98)],"the self-hit shot is one of D_84183BDC")
ok(mem:u32(0x85000000+0x10)==0x84110718 and mem:u32(0x85000000+4)==0x85002000,"program 0 on the confused side")

-- the charge turns (families 6, 7, 8)
camera:turnCheck(scene,"player",0x17)
ok(mem:u16(0x85003000+4)==0x17 and mem:u8(0x85001000+0x61F)==0xFF,"Solar Beam's charge: event 0x17, kind 0xFF")
ok(mem:u32(0x85000000+0x10)==0x84110718 and mem:u32(0x85000000+4)==0x85001000,"the charge turn takes program 0")
camera:turnCheck(scene,"enemy",0x1A)
ok(mem:u8(0x85002000+0x61F)==3 and mem:u16(0x85000000+0x98)==0,"Fly's rise: kind 3, shot 0")
local fly=false
for i=0,6 do if mem:u32(0x85000000+8+i*8)==0x84111048 then fly=true end end
ok(fly,"Fly's rise loads program 3")
camera:turnCheck(scene,"enemy",0x1B)
ok(mem:u16(0x85000000+0x98)==0 and mem:u8(0x85002000+0x61F)==5,"Dig's hole: shot 0, kind 5")
for _=1,25 do camera:update(scene,1/30) end
ok(mem:u16(0x85000000+0x98)==0,"no Dig follow-up before the 26th tick")
camera:update(scene,1/30)
ok(mem:u16(0x85000000+0x98)==0x10 and mem:u16(0x85002000+0x7F4)%32>=16,"the 26th tick takes shot 0x10 and sets +0x7F4 bit 4")
local p2=false
for i=0,6 do if mem:u32(0x85000000+8+i*8)==0x84111170 or mem:u32(0x85000000+8+i*8)==0x841110EC then p2=true end end
ok(p2,"and program 2")
for _=1,10 do camera:update(scene,1/30) ok(sane(camera:pose()),"the charge turns give a finite pose") end
ok(camera.cam.missing==nil,"the charge turns run only ported handlers")

-- Transform (family 13) and Beat Up (family 22): the move's shot, program 0
camera:attack(scene,"player",0x90)
ok(mem:u8(0x85001000+0x61F)==0xFF and mem:u32(0x85000000+0x10)==0x84110718,"Transform: kind 0xFF and program 0")
camera:attack(scene,"enemy",0xFB)
ok(mem:u32(0x85000000+0x10)==0x84110718 and mem:u32(0x85000000+4)==0x85002000,"Beat Up: program 0 on the attacker")
ok(camera.cam.missing==nil,"Transform and Beat Up run only ported handlers")

-- woke up (family 19) and confused (family 20)
mem:setU16(0x85003000+0x22,0) -- the enemy's flags: bit 2 clear
camera:turnCheck(scene,"enemy",0x1D)
ok(mem:u16(0x85003000+4)==0x1D,"woke up is event 0x1D")
ok(mem:u32(0x85002000+0x678)==0x84193E18,"the enemy's species offset row is at D_84193DF8 + 0x20")
local slotOf=0x85000000+8
local found=false
for i=0,6 do if mem:u32(0x85000000+8+i*8)==0x8410E8E4 then found=true end end
ok(found,"program 7 (8410E8E4) loads for the woken side")
camera:update(scene,1/30)
ok(camera:pose().fov==80,"program 7 sets FOV 80")
mem:setU16(0x85003000+0x22,4)
camera:turnCheck(scene,"enemy",0x1D)
ok(mem:u16(0x85000000+0x98)==0 and mem:u32(0x85000000+0x10)==0x84110718,"a woken side with flag bit 2 takes shot 0 and program 0")
mem:setU16(0x85003000+0x22,2)
mem:setU8(0x85002000+0x61F,5)
camera:turnCheck(scene,"enemy",0x26)
ok(mem:u16(0x85003000+4)==0x26 and mem:u16(0x85000000+0x98)==0x24,"confused with flag bit 1 is event 0x26, shot 0x24")
for _=1,29 do camera:update(scene,1/30) end
ok(mem:u8(0x85002000+0x61F)==5,"the confused kind holds for 29 ticks")
camera:update(scene,1/30)
ok(mem:u8(0x85002000+0x61F)==0xFF,"841206D0 resets the kind on the 30th tick")
mem:setU16(0x85003000+0x22,0)
camera:turnCheck(scene,"enemy",0x26)
ok(mem:u16(0x85000000+0x98)==0,"confused without flag bit 1 takes shot 0")
-- an undrawable pose (program 7 on a species whose offset word is out of
-- range) keeps the last drawable pose and is reported
local good=camera:pose()
mem:setF32(0x84190428+0xB4,-6.4e32)
local held=camera:pose()
ok(held.focus[1]==good.focus[1] and held.eye[1]==good.eye[1],"a pose outside the arena keeps the last drawable one")
mem:setVec(0x84190428+0xB4,good.focus)
ok(camera.timed[0x85002000]~=nil,"the kind reset is pending")
camera:turnCheck(scene,"enemy",4)
ok(camera.timed[0x85002000]==nil,"a new event on that side cancels the pending kind reset")
for _=1,20 do camera:update(scene,0.1) ok(sane(camera:pose()),"the turn check gives a finite pose") end
ok(camera.cam.missing==nil,"the turn check runs only ported handlers")

-- status and residual events by their FX entries (family 9)
camera:statusEvent(scene,"enemy",0x101) -- poison: shot 0
ok(mem:u16(0x85003000+4)==0x3C and mem:u16(0x85000000+0x98)==0,"poison is event 0x3C with shot 0")
ok(mem:u32(0x85000000+0x10)==0x84110718 and mem:u32(0x85000000+4)==0x85002000,"program 0 on the poisoned side")
local before=mem:u16(0x85000000+0x98)
camera:statusEvent(scene,"enemy",0x102) -- burn: a different shot of D_84183BDC
ok(mem:u16(0x85003000+4)==0x3E and allowed[mem:u16(0x85000000+0x98)] and mem:u16(0x85000000+0x98)~=before,
  "burn is event 0x3E with a new shot")
camera:statusEvent(scene,"player",0xFF,128) -- Clamp's trapping tick: 0x58, shot 0
ok(mem:u16(0x85003000+4)==0x58 and mem:u16(0x85000000+0x98)==0,"Clamp's tick is event 0x58 with shot 0")
local code=mem:u16(0x85003000+4)
camera:statusEvent(scene,"player",0x122) -- not family 9
ok(mem:u16(0x85003000+4)==code,"entries outside family 9 are ignored")
for _=1,10 do camera:update(scene,0.1) ok(sane(camera:pose()),"a status event gives a finite pose") end

-- a recall: a shot of D_84183C7C (0x11 when frozen) and program 27
local recallShots={}
for i=0,3 do recallShots[mem:u16(0x84183C7C+i*2)]=true end
camera:recall(scene,"player")
ok(mem:u16(0x85003000+4)==0x1E and recallShots[mem:u16(0x85000000+0x98)],"a recall is event 0x1E on a recall shot")
ok(mem:u32(0x85000000+0x10)==0x84110860 and mem:u32(0x85000000+4)==0x85001000,"program 27 is on the recalled side")
camera:recall(scene,"player",{frozen=true})
ok(mem:u16(0x85003000+4)==0x20 and mem:u16(0x85000000+0x98)==0x11,"a frozen recall is event 0x20 with shot 0x11")
for _=1,20 do camera:update(scene,0.1) ok(sane(camera:pose()),"the recall gives a finite pose") end
ok(camera.cam.missing==nil,"program 27 runs only ported handlers")

-- weather: program 29's arena shot on the player; the sandstorm's hit is
-- family 9's 0x48
camera:statusEvent(scene,"player",0x107) -- rain continues
ok(mem:u16(0x85003000+4)==0x32,"rain continuing is event 0x32")
ok(mem:u32(0x85000000+8)==0x8410FB0C and mem:u32(0x85000000+4)==0x85001000,"program 29 loads on the player")
camera:update(scene,1/30)
local wp=camera:pose()
ok(wp.eye[1]==-323 and wp.eye[2]==394 and wp.eye[3]==268,"program 29 puts the eye at (-323, 394, 268)")
camera:statusEvent(scene,"enemy",0x125)
ok(mem:u16(0x85003000+4)==0x48,"the sandstorm hit is event 0x48")
camera:statusEvent(scene,"enemy",0x10C)
ok(mem:u16(0x85003000+4)==0x36 and mem:u16(0x85000000+0x98)==0,"full paralysis is event 0x36 with shot 0")
ok(camera.cam.missing==nil,"weather runs only ported handlers")

-- the arena intro (family 26) on a fresh controller: two views, the split
-- growing from frame 0x3C, one full view at the end; a send-out cuts it
do
  local intro=assert(StadiumCamera.new({rom=rom,fragment79=fragment,seed=7}))
  local iscene={actors={player={dex=25,mon={hp=35}},enemy={dex=16,mon={hp=30}}},
    modelMatrix=function() error("no model in this test") end}
  intro:update(iscene,1/30)
  local im=intro.cam.mem
  ok(im:u16(0x85003000+4)==0x65,"battle start is event 0x65 (the arena intro)")
  local views=intro:views()
  ok(#views==2,"the intro starts with two views")
  ok(views[1].viewport[4]==0x78 and views[2].viewport[2]==0x78 and views[2].viewport[4]==0x78,
    "top and bottom halves (8410AF1C)")
  for k=1,2 do ok(sane(views[k]),"intro view "..k.." has a finite pose") end
  for _=1,0x40 do intro:update(iscene,1/30) end
  views=intro:views()
  ok(#views==2 and views[1].viewport[4]>0x78,"from frame 0x3C the top view grows")
  ok(views[1].viewport[4]+views[2].viewport[4]==0xF0,"the two views share the screen")
  for _=1,0x70 do intro:update(iscene,1/30) end
  views=intro:views()
  ok(#views==1 and views[1].viewport[3]==0x140 and views[1].viewport[4]==0xF0,"the intro ends on one full view (8410B104)")
  ok(intro.intro==nil,"the intro is over")
  ok(intro.cam.missing==nil,"the intro runs only ported handlers")
  local cut=assert(StadiumCamera.new({rom=rom,fragment79=fragment,seed=8}))
  cut:update(iscene,1/30)
  for _=1,10 do cut:update(iscene,1/30) end
  cut:sendOut(iscene,"player")
  ok(#cut:views()==2 and cut.intro~=nil,"a send-out during the intro no longer cuts it (the opening waits)")
  cut:turnStart(iscene)
  local cv=cut:views()
  ok(#cv==1 and cv[1].viewport[4]==0xF0,"a turn start during the intro closes the split (host-timing fallback)")
  -- the opening send-out (family 24): the foe's send-out keeps the intro,
  -- the player's starts the wipe once its entrance clip has ended
  local open=assert(StadiumCamera.new({rom=rom,fragment79=fragment,seed=9}))
  local oscene={actors={player={dex=25,mon={hp=35},context="entrance"},enemy={dex=16,mon={hp=30},context="idle"}},
    modelMatrix=function() error("no model in this test") end}
  open:update(oscene,1/30)
  for _=1,20 do open:update(oscene,1/30) end
  local released={}
  oscene.stadiumReleaseEntrance=function(_,side) released[#released+1]=side end
  ok(open:holdEntrance("player") and open:holdEntrance("enemy"),"entrances wait for the opening while the intro runs")
  open:sendOut(oscene,"enemy")
  ok(open.intro~=nil,"the foe's opening send-out keeps the arena intro")
  ok(open:holdEntrance("enemy"),"the foe's entrance is held (8411C418 plays it)")
  local signals={}
  oscene.battleFx={signalEffect=function(_,entry,side) signals[#signals+1]={entry,side} end}
  open:sendOut(oscene,"player")
  ok(open.intro~=nil and open.pendingOpening==true,"the opening waits for the arena intro (Stadium's engine waits for it)")
  ok(open:holdEntrance("player"),"the player's entrance is held until the opening (8411C310 plays it)")
  for _=1,200 do if open.intro==nil then break end open:update(oscene,1/30) end
  ok(released[1]=="player" and #released==1,"the opening releases the player's entrance as it starts (8411C310)")
  ok(not open:holdEntrance("player") and open:holdEntrance("enemy"),"the foe's entrance still waits")
  local om=open.cam.mem
  ok(om:u16(0x85003000+4)==0x22 and open.intro==nil and open.opening~=nil,"after the intro, the opening send-out is event 0x22 (family 24)")
  for _=1,10 do open:update(oscene,1/30) end
  ok(open.opening.substate==1,"the wipe waits for the player's entrance clip")
  oscene.actors.player.context="idle"
  open:update(oscene,1/30)
  ok(open.opening.substate==2,"then the wipe starts")
  local wiping=false
  for _=1,4 do
    open:update(oscene,1/30)
    local ov=open:views()
    if #ov==2 and ov[2].viewport[1]<320 and ov[2].viewport[3]>0 then wiping=true end
  end
  ok(wiping,"the foe's view slides in from the right")
  local threw=false
  for _,sg in ipairs(signals) do if sg[1]==0x124 and sg[2]=="enemy" then threw=true end end
  ok(threw,"the wipe signals the foe's throw (8410890C(0x124))")
  local foeAt
  for _=1,70 do
    open:update(oscene,1/30)
    if not foeAt and released[2]=="enemy" then foeAt=open.cam.mem:s16(0x85001000+0x7E8) end
  end
  ok(foeAt==0x28,"the foe's entrance is released at frame 0x28 of substate 4 (8411C418), got "..tostring(foeAt))
  ok(not open:holdEntrance("enemy"),"then the foe's entrance plays at once")
  local ov=open:views()
  ok(#ov==1 and ov[1].viewport[3]==320,"after the wipe the foe's view is the only one (8410B1CC)")
  for _=1,10 do open:update(oscene,1/30) end
  ok(open.opening==nil,"the opening ended")
  open:turnStart(oscene)
  ov=open:views()
  ok(#ov==1 and open.cam.mem:u8(0x84190428+1)%32>=16,"the turn start brings the first view back (8411F90C's 8410B104)")
  ok(open.cam.missing==nil,"the opening runs only ported handlers")

  -- a split view reaches the arena frame as its own sub-rectangle
  local f=Camera.sceneFrame(640,480,{arena=true,scale=.05,groundY=0,stadiumPose=views[1]})
  ok(f.scissor==nil or (f.scissor[3]==640 and f.scissor[4]==480),"a full view is not scissored")
  local half=Camera.sceneFrame(640,480,{arena=true,scale=.05,groundY=0,
    stadiumPose={eye={0,100,500},focus={0,0,0},up={0,1,0},fov=45,viewport={0,0x78,0x140,0x78}}})
  ok(half.scissor and half.scissor[2]==240 and half.scissor[4]==240,"the bottom half is scissored to its rectangle")
end

-- the arena intro signals the throw (0x112); a wild battle has the
-- wild-encounter camera instead (user-requested extension)
do
  local sig={}
  local a=assert(StadiumCamera.new({rom=rom,fragment79=fragment,seed=21}))
  local ascene={actors={player={dex=25,mon={hp=35}},enemy={dex=16,mon={hp=30}}},
    modelMatrix=function() error("no model in this test") end,
    battleFx={signalEffect=function(_,entry,side) sig[#sig+1]={entry,side} end}}
  a:update(ascene,1/30);a:update(ascene,1/30)
  ok(sig[1] and sig[1][1]==0x112,"the arena intro signals 8410890C(0x112)")
  local w=assert(StadiumCamera.new({rom=rom,fragment79=fragment,seed=22}))
  local wscene={actors={player={dex=25,mon={hp=35},context="idle"},enemy={dex=16,mon={hp=30},context="idle"}},
    modelMatrix=function() error("no model in this test") end,
    stadiumWildBattle=function() return true end}
  w:update(wscene,1/30)
  local wm=w.cam.mem
  ok(w.intro==nil and #w:views()==1,"a wild battle has no split-screen intro")
  ok(wm:u16(0x85000000+0x98)==0x27 and wm:u32(0x85000000+4)==0x85002000,"the wild Pokemon's own close-up (shot 0x27) first")
  for _=1,StadiumCamera.WILD_CLOSEUP do w:update(wscene,1/30) end
  local orbit=false
  for i=0,6 do if wm:u32(0x85000000+8+i*8)==0x8410FD54 or wm:u32(0x85000000+8+i*8)==0x8410FC28 then orbit=true end end
  ok(orbit,"then the arena orbit (program 4)")
  w:sendOut(wscene,"player")
  ok(w.opening~=nil,"the player's send-out runs the opening")
  ok(w.cam.missing==nil,"the wild encounter runs only ported handlers")
end

-- the over-the-shoulder idle shot hides the Pokemon at the eye (84120E14)
do
  local h=assert(StadiumCamera.new({rom=rom,fragment79=fragment,seed=23}))
  local hscene={actors={player={dex=25,mon={hp=35}},enemy={dex=16,mon={hp=30}}},
    modelMatrix=function() error("no model in this test") end,
    restCondition=function() return {} end,stadiumAwaitingCommand=function() return true end}
  h:update(hscene,1/30);h.intro,h.openingPhase=nil,nil;h.cam:endSplit()
  h:update(hscene,1/30)
  ok(h.cam.mem:u16(0x85003000+4)==0x62,"the first idle shot is 0x62 (program 14)")
  h:update(hscene,1/30)
  ok(h:hiddenSide()=="player","the Pokemon whose shoulder the camera looks over is hidden")
  for _=1,130 do h:update(hscene,1/30) end
  ok(h:hiddenSide()==nil,"and shown again for the next shot")
end

-- the command menu's idle cycle (family 31): after the turn start's timer,
-- 8413543C's steps in order, each for its timer
do
  local idle=assert(StadiumCamera.new({rom=rom,fragment79=fragment,seed=11}))
  local waiting=false
  local iscene={actors={player={dex=25,mon={hp=35}},enemy={dex=16,mon={hp=30}}},
    modelMatrix=function() error("no model in this test") end,
    restCondition=function() return {} end,
    stadiumAwaitingCommand=function() return waiting end}
  idle:update(iscene,1/30)
  idle.intro,idle.openingPhase=nil,nil
  idle.cam:endSplit()
  idle:turnStart(iscene)
  local im=idle.cam.mem
  ok(im:u16(0x85003000+6)==0x64,"the turn start's timer is 100 (8411FEE8(0x64))")
  for _=1,200 do idle:update(iscene,1/30) end
  ok(im:u16(0x85003000+4)==0x5A,"no idle camera while the battle is not waiting for a command")
  waiting=true
  local codes={}
  for _=1,900 do
    idle:update(iscene,1/30)
    local c=im:u16(0x85003000+4)
    if codes[#codes]~=c then codes[#codes+1]=c end
  end
  ok(codes[1]==0x62,"the idle cycle begins with 0x62 while waiting for a command")
  local seen={}
  for _,c in ipairs(codes) do seen[c]=true end
  for _,c in ipairs({0x5C,0x5D,0x60,0x61}) do ok(seen[c],("idle code %X plays"):format(c)) end
  for k=1,3 do ok(sane(idle:views()[1]),"the idle camera gives a finite pose") end
  waiting=false
  idle:attack(iscene,"player",33)
  ok(idle.idle==nil,"a battle event ends the idle cycle")
  ok(im:u16(0x85003000+4)==0,"and takes the camera")
end

-- the battle's end: 0x67 and program 24 on the winner, then program 7
do
  local v=assert(StadiumCamera.new({rom=rom,fragment79=fragment,seed=12}))
  local vscene={actors={player={dex=25,mon={hp=35}},enemy={dex=16,mon={hp=0}}},
    modelMatrix=function() error("no model in this test") end}
  v:update(vscene,1/30)
  v.intro,v.openingPhase=nil,nil
  v.cam:endSplit()
  v:battleEnd(vscene,"win")
  local vm=v.cam.mem
  ok(vm:u16(0x85003000+4)==0x67 and vm:u32(0x85000000+4)==0x85001000,"a win is 0x67 on the player")
  local p24=false
  for i=0,6 do if vm:u32(0x85000000+8+i*8)==0x8410F9FC or vm:u32(0x85000000+8+i*8)==0x8410FABC then p24=true end end
  ok(p24,"program 24 on the winner")
  for _=1,300 do v:update(vscene,1/30) end
  ok(v.victory==nil,"the victory camera ran to its end")
  ok(v.cam.missing==nil,"the victory runs only ported handlers")
  v:battleEnd(vscene,"run")
  ok(vm:u16(0x85003000+4)==0x67,"running away has no Stadium victory event")
end

-- the follow-ups the host has no trigger for, from host state: Fly's second
-- shot once the host's Fly departure is complete (restCondition.flying), the
-- charge's kind reset on the ROM motion row's frame
do
  local flying=false
  local f=assert(StadiumCamera.new({rom=rom,fragment79=fragment,seed=13}))
  local fscene={actors={player={dex=18,mon={hp=35},context="idle"},enemy={dex=16,mon={hp=30},context="idle"}},
    modelMatrix=function() error("no model in this test") end,
    restCondition=function(_,side) return {flying=side=="player" and flying} end}
  f:update(fscene,1/30)
  f.intro,f.openingPhase=nil,nil
  f.cam:endSplit()
  local fm=f.cam.mem
  ok(fm:u32(0x85001000+0x2D4)==0x85010000 and fm:u8(0x85010000)~=nil,"the player's motion record is loaded (+0x2D4)")
  f:turnCheck(fscene,"player",0x1A)
  for _=1,30 do f:update(fscene,1/30) end
  ok(fm:u16(0x85000000+0x98)==0,"Fly's second shot waits while the Pokemon is still rising")
  flying=true
  f:update(fscene,1/30)
  f:update(fscene,1/30)
  local p15=false
  for i=0,6 do if fm:u32(0x85000000+8+i*8)==0x84110558 then p15=true end end
  ok(fm:u16(0x85000000+0x98)==8 and (p15 or fm:u32(0x85000000+4)==0x85001000),"once it has flown up: shot 8 and program 15")
  ok(f.cam.missing==nil,"Fly's rise runs only ported handlers")
  f:turnCheck(fscene,"enemy",0x17)
  local limit=fm:u8(0x85002000+0x61A)
  ok(limit>0,"the charge row's frame limit is loaded from the ROM record")
  fm:setU8(0x85002000+0x61F,9)
  for _=1,limit+2 do f:update(fscene,1/30) end
  ok(fm:u8(0x85002000+0x61F)==0xFF,"the charge's follow-up resets the kind on the row's frame")
  ok(f.runs[0x85002000]==nil,"and ends")
end

-- Transform: shot 0 / program 0 once the host shows the copied model, the
-- transformer's own camera data kept
do
  local t=assert(StadiumCamera.new({rom=rom,fragment79=fragment,seed=14}))
  local tscene={actors={player={dex=132,mon={hp=35},context="idle"},enemy={dex=150,mon={hp=30},context="idle"}},
    modelMatrix=function() error("no model in this test") end}
  t:update(tscene,1/30)
  t.intro,t.openingPhase=nil,nil
  t.cam:endSplit()
  local tm=t.cam.mem
  local own=tm:f32(0x85001000+0x64C)
  t:attack(tscene,"player",0x90)
  for _=1,120 do t:update(tscene,1/30) end
  ok(t.runs[0x85001000]~=nil,"Transform waits for the copied model")
  tscene.actors.player.dex=150
  t:update(tscene,1/30)
  ok(tm:u32(0x85000000+0x10)==0x84110718 and tm:u16(0x85000000+0x98)==0,"once the host shows the copy: shot 0 and program 0")
  ok(tm:f32(0x85001000+0x64C)==own and tm:s16(0x85001000+0x1A)==132,"the transformer keeps its own camera data")
  for _=1,0x2A do t:update(tscene,1/30) end
  ok(t.runs[0x85001000]==nil and tm:u8(0x85001000+0x61F)==0xFF,"Transform ends with the kind reset")
  ok(t.cam.missing==nil,"Transform runs only ported handlers")
end

-- CAMERA STADIUM on a custom scene: the Stadium layout fitted onto the
-- scene's two battle spots (scale, turn, origin), and back
do
  local okS,SceneMod=pcall(require,"mods.STADIUM2_IMPORTER.lib.battle_scene")
  local okT,Stage=pcall(require,"mods.STADIUM2_IMPORTER.lib.battle_stage")
  if okS and okT then
    local fake=setmetatable({arenaMode=false},{__index=SceneMod})
    local function near(a,b) return math.abs(a[1]-b[1])<1e-6 and math.abs(a[2]-b[2])<1e-6 and math.abs(a[3]-b[3])<1e-6 end
    ok(near(fake:stadiumToWorld({-150,0,0}),Stage.positions.player),"the Stadium player slot lands on the scene's player spot")
    ok(near(fake:stadiumToWorld({150,0,0}),Stage.positions.enemy),"the Stadium foe slot lands on the scene's foe spot")
    local p={37,12,-80}
    ok(near(fake:worldToStadium(fake:stadiumToWorld(p)),p),"world and Stadium units round-trip")
    local sp=fake:stadiumSpace()
    ok(math.abs((math.pi*.5+sp.theta)-math.pi)<1e-9,"the player faces the scene's way (yaw pi)")
  else
    print("SKIP custom-scene Stadium space (scene modules unavailable here)")
  end
end

-- the game's mod sandbox refuses require("ffi") at run time: the camera
-- must not use it, and its plain-Lua double decoder must match the bits
do
  for _,name in ipairs({"lib/stadium2_battle_camera.lua","lib/stadium2_battle_camera_native.lua",
      "lib/stadium2_libultra.lua","lib/stadium2_battle_fx_stochastic_native.lua",
      "lib/stadium2_battle_fx_textured_stream_native.lua","lib/stadium2_battle_fx_tri_attack_native.lua",
      "lib/stadium2_battle_fx_terrain_grid_native.lua"}) do
    local fh=assert(io.open("mods/STADIUM2_IMPORTER/"..name,"rb"));local text=fh:read("*a");fh:close()
    ok(not text:find('require%s*%(?%s*["\']ffi["\']'),name.." does not require ffi")
  end
  local Native=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_camera_native")
  local ffi=require("ffi")
  local u=ffi.new("union { double d; uint32_t w[2]; }")
  math.randomseed(31)
  for i=1,2000 do
    local hi,lo=math.random(0,0xFFFFFFFF),math.random(0,0xFFFFFFFF)
    if i%7==0 then hi=hi%0x100000 end -- subnormals
    if ffi.abi("le") then u.w[0],u.w[1]=lo,hi else u.w[0],u.w[1]=hi,lo end
    local want=tonumber(u.d)
    local got=Native.wordsToDouble(hi,lo)
    if not (want~=want and got~=got) then ok(got==want,("double %08X %08X"):format(hi,lo)) end
  end
  -- the plain-Lua binary32 conversions against ffi's, both ways
  local Memory=require("mods.STADIUM2_IMPORTER.lib.stadium2_native_memory")
  local fu=ffi.new("union { float f; uint32_t w; }")
  for i=1,4000 do
    local w=math.random(0,0xFFFFFFFF)
    if i%5==0 then w=w%0x800000+(math.random(0,1)*0x80000000) end -- subnormals and zeros
    fu.w=w
    local want=tonumber(fu.f)
    local got=Memory.wordFloatLua(w)
    -- NaN by its bits (LuaJIT's reading of some NaN payloads is not NaN-like)
    local nan=math.floor(w/0x800000)%0x100==0xFF and w%0x800000~=0
    if not nan then
      ok(got==want,("word %08X to float"):format(w))
      ok(Memory.floatWordLua(want)==w,("float of %08X back to its word"):format(w))
    else ok(got~=got,("word %08X is NaN"):format(w)) end
  end
  for _=1,2000 do
    local v=(math.random()*2-1)*10^math.random(-44,38)
    fu.f=v
    ok(Memory.floatWordLua(v)==tonumber(fu.w),("double %.17g rounds to ffi's single"):format(v))
  end
  -- with ffi refused (as the sandbox does), the memory still reads and writes
  local saved,savedPreload=package.loaded.ffi,package.preload.ffi
  package.loaded.ffi=nil
  package.preload.ffi=function() error("ffi is not available to mods") end
  package.loaded["mods.STADIUM2_IMPORTER.lib.stadium2_native_memory"]=nil
  local okLoad,Plain=pcall(require,"mods.STADIUM2_IMPORTER.lib.stadium2_native_memory")
  package.loaded.ffi,package.preload.ffi=saved,savedPreload
  package.loaded["mods.STADIUM2_IMPORTER.lib.stadium2_native_memory"]=Memory
  ok(okLoad,"native memory loads without ffi: "..tostring(Plain))
  local pm=Plain.new({})
  pm:setF32(0x100,-1.5);pm:setVec(0x104,{3,0.1,-0})
  ok(pm:u32(0x100)==0xBFC00000 and pm:f32(0x100)==-1.5,"without ffi a float is written and read exactly")
  ok(pm:f32(0x108)==require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_float")(0.1) and pm:u32(0x10C)==0x80000000,"single rounding and negative zero without ffi")
end

-- woke up (event 0x1D): program 7, the timer 0x258, then the tail waits
-- for the wake clip and ends the timer 0x1E frames later (84119AB4)
do
  local w=assert(StadiumCamera.new({rom=rom,fragment79=fragment,seed=41}))
  local ws={actors={player={dex=25,mon={hp=35},context="idle"},enemy={dex=16,mon={hp=30},context="idle"}},
    modelMatrix=function() error("no model in this test") end}
  w:update(ws,1/30);w.intro,w.openingPhase=nil,nil;w.cam:endSplit()
  local wm=w.cam.mem
  ws.actors.enemy.context="wake"
  w:wokeUp(ws,"enemy")
  ok(wm:u16(0x85003000+6)==0x258,"woke up sets the timer 0x258 (84119908)")
  for _=1,0x30 do w:update(ws,1/30) end
  ok(wm:u8(0x85002000+0x7F6)==1 and w.runs[0x85002000]~=nil,"the tail waits for the wake clip")
  ws.actors.enemy.context="idle"
  local ended=false
  for _=1,0x30 do w:update(ws,1/30) if w.runs[0x85002000]==nil then ended=true break end end
  ok(ended and wm:u16(0x85003000+6)==0 and wm:u8(0x85002000+0x61F)==0xFF,"0x1E frames after the clip the timer ends and the kind resets")
  ok(w.cam.missing==nil,"the wake-up runs only ported handlers")
end

-- program 7 (woke up) reads the offset row DMA'd from archive + 0 (84113014):
-- the target stays at the Pokemon for species whose + 0x5730 word was wild
do
  for _,sp in ipairs({9,94,249,25}) do
    local p=assert(StadiumCamera.new({rom=rom,fragment79=fragment,seed=44}))
    local ps={actors={player={dex=25,mon={hp=35},context="idle"},enemy={dex=sp,mon={hp=30},context="idle"}},
      modelMatrix=function() error("no model in this test") end}
    p:update(ps,1/30);p.intro,p.openingPhase=nil,nil;p.cam:endSplit()
    p:wokeUp(ps,"enemy")
    p:update(ps,1/30)
    local pm=p.cam.mem
    local t=pm:vec(0x84190428+0xB4)
    local dx,dz=t[1]-pm:f32(0x85002000+0x24),t[3]-pm:f32(0x85002000+0x2C)
    ok(math.sqrt(dx*dx+dz*dz)<100,("species %d: the wake-up shot aims at the Pokemon (%.1f away)"):format(sp,math.sqrt(dx*dx+dz*dz)))
  end
end

-- Lock-On's program 25 aims at the FX player's dynamic anchor 0 (D_8418C958)
do
  local l=assert(StadiumCamera.new({rom=rom,fragment79=fragment,seed=43}))
  local ls={actors={player={dex=25,mon={hp=35},context="idle"},enemy={dex=16,mon={hp=30},context="idle"}},
    modelMatrix=function() error("no model in this test") end,
    battleFx={player={dynamicAnchor=function(_,i) return i==0 and {12,34,-56} or nil end}}}
  l:update(ls,1/30);l.intro,l.openingPhase=nil,nil;l.cam:endSplit()
  l.cam:setProgram(0x85002000,0x19)
  l:update(ls,1/30)
  local t=l.cam.mem:vec(0x84190428+0xB4)
  ok(t[1]==12 and t[2]==34 and t[3]==-56,"program 25 aims at dynamic anchor 0")
  ls.battleFx=nil
  l:update(ls,1/30)
  local t2=l.cam.mem:vec(0x84190428+0xB4)
  ok(t2[1]==12 and t2[3]==-56,"without MOVE EFFECTS the target is held")
end

-- a move without an ID is reported, not guessed
local before=mem:u16(0x85000000+0x98)
camera:attack(scene,"enemy",nil)
ok(mem:u16(0x85000000+0x98)==before,"no move ID leaves the shot alone")
local reported=false
for _,m in ipairs(warnings) do if m:find("stands in for 8411DD8C",1,true) then reported=true end end
ok(reported,"a model without markers is reported, with the anchor point standing in")

-- the arena frame uses the pose in STADIUM mode
local frame=Camera.arenaFrame(640,480,{scale=0.05,groundY=0,stadiumPose=camera:pose()})
ok(frame.stadium.native==true and math.abs(frame.eye[1]-camera:pose().eye[1]*0.05)<1e-6,
  "arenaFrame takes Stadium's eye (scaled to the scene)")
print(checks.." checks passed (STADIUM camera controller)")
