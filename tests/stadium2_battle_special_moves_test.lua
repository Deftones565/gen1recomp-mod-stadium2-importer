package.path="./?.lua;./?/init.lua;"..package.path

-- Agility (kind 6) and Double Team (kind 7): 84121920 / 84121DE8 ports.
local Special=require("mods.STADIUM2_IMPORTER.lib.battle_special_moves")
local Actor=require("mods.STADIUM2_IMPORTER.lib.battle_actor")
local Scene=require("mods.STADIUM2_IMPORTER.lib.battle_scene")

local checks=0
local function ok(value,message)
  checks=checks+1
  if not value then error("FAIL "..message,0) end
end
local function near(a,b,eps) return math.abs(a-b)<=(eps or 1e-4) end
-- Table lookup as the ROM does it: index = (angle & 0xFFFF) >> 4.
local function sins(angle) return math.sin(math.floor((angle%65536)/16)*16/65536*2*math.pi) end

-- Stand-in for the ROM's 4096-entry sine table (test only).
local trig={tableA={},tableB={}}
for i=1,4096 do
  trig.tableA[i]=math.sin((i-1)*2*math.pi/4096)
  trig.tableB[i]=math.sin((i-1+1024)*2*math.pi/4096)
end

ok(Special.KINDS[97]==6 and Special.KINDS[104]==7 and Special.KINDS[107]==9,
  "84114804 kinds for Agility, Double Team and Minimize")
ok(near(Special.approach(0,50,Special.AGILITY_RATE),5),"841203B4 first step toward 50")
ok(Special.approach(0.0005,0,0.1)==0,"841203B4 snaps inside +/-0.001")
ok(Special.stepTo(0,0x80,15,15)==15 and Special.stepTo(120,0x80,15,15)==0x80,
  "800372CC steps and clamps")
ok(Special.facing("player")==0x4000 and Special.facing("enemy")==-0x4000,
  "8411E140 facing")

ok(Special.new({kind=6})==nil,"missing trig tables are reported, not guessed")
ok(Special.new({kind=7,trig=trig})==nil,"Double Team without a profile is reported")
ok(Special.new({kind=0x11,trig=trig})==nil,"undecoded kinds are rejected")

-- Agility on the player's side: sways along Z only, ramps to 50 and back.
local a=Special.new({kind=6,trig=trig,yaw=Special.facing("player")})
Special.step(a)
ok(#a.afterimages==2 and a.afterimages[1].alpha==0x80,"84120E7C makes two 0x80 copies")
ok(near(a.amp,5) and a.phase==0xE38,"first tick: amp 5, phase 0xE38")
ok(near(a.offset[1],0,1e-3) and near(a.offset[3],sins(0xE38)*5,1e-3),
  "sway is SINS(phase)*amp along the facing's lateral axis")
ok(near(a.afterimages[1].offset[3],a.offset[3]*(1-0.3),1e-4)
  and near(a.afterimages[2].offset[3],a.offset[3]*(1-0.45),1e-4),
  "84120F5C keeps 0.3 / 0.45 of each copy's distance")
local turned,peak
for tick=2,200 do
  Special.step(a)
  peak=math.max(peak or 0,math.abs(a.offset[3]))
  if not turned and a.stage==1 then turned=tick end
end
ok(turned==38,"amp passes 49 on tick 38 (got "..tostring(turned)..")")
ok(peak<=50,"sway never exceeds amp 50")
ok(a.offset[1]==0 and a.offset[2]==0 and a.offset[3]==0,"back at the home slot after the decay")
local e=Special.new({kind=6,trig=trig,yaw=Special.facing("enemy")})
Special.step(e)
ok(near(e.offset[3],-sins(0xE38)*5,1e-3),"enemy sways the opposite way")

-- Double Team: two copies fading in, spreading to opposite sides.
local d=Special.new({kind=7,trig=trig,yaw=Special.facing("player"),bodyHeight=80})
Special.step(d)
local s0,s1=d.afterimages[1],d.afterimages[2]
ok(s0.alpha==15 and s1.alpha==15,"copies fade in by 15")
ok(s0.speed==100 and s0.phase==100 and s1.phase==-0xE38+100,"phase speeds up by 100")
ok(near(s0.offset[3],sins(100)*80/4,1e-3),"copy 0: +SINS(phase)*R/4")
ok(near(s1.offset[3],-sins(-0xE38+100)*80/4,1e-3),"copy 1 mirrored")
for _=2,9 do Special.step(d) end
ok(s0.alpha==0x80,"copies cap at alpha 0x80")
for _=10,30 do Special.step(d) end
ok(s0.speed==0x222,"phase speed caps at 0x222")
ok(d.alpha and d.alpha>=0x80,"battler alpha never drops below 0x80")

ok(Special.doubleTeamAlpha(trig,0)==228,"phase 0: trunc(1.9*255)=484 wraps to 228 (sb)")
ok(Special.doubleTeamAlpha(trig,0x2000)==161,"phase 0x2000 wraps to 161")
ok(Special.doubleTeamAlpha(trig,0x4000)==255,"phase 0x4000: COSS(0xC000)=0 -> 255")
ok(Special.doubleTeamAlpha(trig,-0x4000)==0x80,"phase -0x4000: 25 -> clamped to 0x80")

-- Actor: the kind runs from the hit frame while the attack state lasts.
Actor.trigTables=trig
local actor=Actor.new("player")
actor.renderer={model={}}
actor.context="attack"
actor.special={kind=6,at=2,clock=0,ticks=0}
actor:stepSpecial(1/30)
ok(actor.nativeOffset==nil,"nothing before the hit frame")
actor:stepSpecial(1/30)
ok(actor.nativeOffset and actor.afterimages and #actor.afterimages==2,
  "Agility starts on the hit frame")
actor.context="idle"
actor:stepSpecial(1/30)
ok(actor.nativeOffset==nil and actor.afterimages==nil and actor.modelAlphaByte==255,
  "leaving the attack state clears the routine")

local warned
actor.warn=function(msg) warned=msg end
actor.context="attack"
actor.special={kind=7,at=1,clock=0,ticks=0}
actor:stepSpecial(1/30)
ok(warned and warned:find("battle profile",1,true) and actor.afterimages==nil,
  "Double Team without the species profile warns and draws nothing extra")
-- The defender of Stomp (23) / Body Slam (34): kind 15 from its hit state's
-- frame = its own row's byte 7, while the hit clip lasts.
do
  Actor.forceFx=true
  local row=string.rep("\0",20)
  local stompRow=row:sub(1,7)..string.char(2)..row:sub(9)
  local dispatch=string.rep(row,22)..stompRow..string.rep(row,250)
  local target=Actor.new("enemy")
  target.renderer={model={fxDispatch=dispatch},setContext=function() return true end}
  ok(target:hit(23) and target.special and target.special.kind==15 and target.special.at==2,
    "Stomp's target gets the squash from its byte 7 (2)")
  target:stepSpecial(1/30)
  ok(target.nativeAxisScale==nil,"nothing before its hit frame")
  target:stepSpecial(1/30)
  ok(target.nativeAxisScale and target.nativeAxisScale[2]~=1,"the squash starts on the hit frame")
  target.context="idle"
  target:stepSpecial(1/30)
  ok(target.nativeAxisScale==nil,"the hit clip's end clears it")
  local other=Actor.new("enemy")
  other.renderer={model={fxDispatch=dispatch},setContext=function() return true end}
  other:hit(33)
  ok(other.special==nil,"other moves' targets are not squashed")
  Actor.forceFx=nil
end
Actor.trigTables=nil

-- Scene: offsets are Stadium units scaled like the slot.
local host={arenaMode=true,arenaScale=2,arenaGroundY=0,
  picScale=function() return 1 end,picElevation=function() return 0 end,actors={}}
local mon={dex=1,renderer={worldMetrics=function() return {floor=0,height=1} end},
  scale=function() return 1 end}
local base=Scene.modelMatrix(host,"player",mon)
mon.nativeOffset={0,0,5}
local moved=Scene.modelMatrix(host,"player",mon)
local diff=0
for i=1,16 do diff=diff+math.abs(moved[i]-base[i]) end
ok(near(diff,10),"sway offset is scaled by arenaScale (moved "..diff..")")
local image=Scene.modelMatrix(host,"player",mon,{offset={0,0,0},scale=1})
diff=0
for i=1,16 do diff=diff+math.abs(image[i]-base[i]) end
ok(near(diff,0),"afterimage uses its own offset")

-- Fly and Dig's charge turns (Actor:startNativeCharge): rows 0x100 / 0x102
do
  Actor.forceFx=true
  Actor.trigTables=trig
  local Pack=require("mods.STADIUM2_IMPORTER.lib.pack")
  local function f32be(v)
    local ffi=require("ffi")
    local u=ffi.new("union { float f; uint8_t b[4]; }")
    u.f=v
    return string.char(u.b[3],u.b[2],u.b[1],u.b[0])
  end
  local function profile(body,ground,center)
    local b={}
    for i=1,0x30 do b[i]="\0" end
    local function put(o,v) local s4=f32be(v) for i=1,4 do b[o+i]=s4:sub(i,i) end end
    put(4,body);put(8,ground);put(0x14,center)
    return table.concat(b)
  end
  local row=string.rep("\0",20)
  local flyRow=row:sub(1,11)..string.char(5)..row:sub(13)
  local dispatch=string.rep(row,256)..flyRow..row..row..string.rep(row,12)
  local function rig(dex,center)
    local calls={}
    local contexts={}
    for i=1,#Pack.CONTEXTS do contexts[i]=0 end
    local r={model={fxDispatch=dispatch,fxBattleProfile=profile(40,0,center),
        anims={{frames=20}},context=contexts},
      frame=0,animIndex=1,finished=false,calls=calls,
      setContext=function(self,name,loop) calls[#calls+1]={name,loop};self.finished=false;return true end,
      seekFrame=function(self,f) calls[#calls+1]={"seek",f} end,
      step=function() end,setHandlerRuntime=function() end,setMove=function() return false end,
      worldMetrics=function() return {height=20,floor=0,radius=5} end}
    local a=Actor.new("player")
    a.renderer=r;a.dex=dex
    return a,r
  end
  -- Fly
  local fly,r=rig(18,30)
  ok(fly:charge(256,7) and r.calls[1][1]=="rom_context_256" and r.calls[2]==nil,
    "Fly plays row 0x100 from frame 0 (84111DB4 0), not row byte 6")
  for _=1,4 do fly:update(1/30) end
  ok(fly.nativeOffset==nil,"Fly has not risen before the row's hit frame")
  fly:update(1/30)
  ok(fly.nativeOffset and fly.nativeOffset[2]>0,"Fly rises from the row's hit frame (kind 3)")
  r.finished=true
  fly:update(1/30)
  ok(r.calls[#r.calls][1]=="rom_context_262" and r.calls[#r.calls][2]==true and fly.context=="attack",
    "the charge clip's end loops context 0x106 while it rises")
  for _=1,200 do if fly.context=="attack" then fly:update(1/30) end end
  ok(fly.context=="idle" and fly.nativeLift==Special.FLY_TOP and fly.nativeCharge.risen,
    "Fly is held 200 above its origin")
  local host="fly"
  local scene=setmetatable({actors={player=fly},hostCharging=function() return host end},{__index=Scene})
  scene:stepNativeCharge("player")
  ok(fly.nativeLift==Special.FLY_TOP and scene:nativeChargeVisibility("player")=="pokemon",
    "held and shown while the host has the charge")
  fly:setRest({})
  ok(fly.rest.flying==true,"the flying rest pose while held up")
  host=nil
  fly.context="attack"
  scene:stepNativeCharge("player")
  ok(fly.nativeLift==Special.FLY_TOP,"held through the Fly attack")
  fly.context="idle"
  scene:stepNativeCharge("player")
  ok(fly.nativeLift==nil and fly.nativeCharge==nil,"home once the attack has ended")
  -- Dig
  local dig,d=rig(27,20)
  ok(dig:charge(258,0) and #d.calls==0,"Dig keeps the playing animation at first")
  for _=1,0x19 do dig:update(1/30) end
  ok(#d.calls==0,"until the tick after frame 0x19")
  dig:update(1/30)
  ok(d.calls[1][1]=="rom_context_258" and d.calls[1][2]==true,"then the dig clip, looping (84115988)")
  for _=1,400 do if dig.context=="attack" then dig:update(1/30) end end
  local digScene=setmetatable({actors={player=dig},hostCharging=function() return "dig" end},{__index=Scene})
  ok(dig.nativeCharge and dig.nativeCharge.hidden and digScene:nativeChargeVisibility("player")=="hidden",
    "Dig sinks below -3 x centre and is hidden (8411EE74)")
  ok(dig:attack(91)~=nil and dig.nativeCharge==nil,"its attack turn ends the hidden state")
  -- Diglett: no kind, the clip to its end
  local diglett,g=rig(50,10)
  diglett:charge(258,0)
  for _=1,0x1A do diglett:update(1/30) end
  ok(g.calls[1][2]==false and diglett.special==nil,"Diglett plays the dig clip once, no sink")
  g.finished=true
  diglett:update(1/30)
  ok(diglett.context=="idle" and not diglett.nativeCharge.hidden,"and stays shown (its dig pose)")
  -- With the camera director's shot resets (reposeDriven)
  local shown=true
  local cam={actorShown=function() return shown end}
  local director=setmetatable({actors={},stadiumDirectorActive=true,stadiumCamera=cam,
    hostCharging=function() return nil end},{__index=Scene})
  local flier=rig(18,30)
  director.actors.player=flier
  director:stepNativeCharge("player")
  ok(flier.reposeDriven==true,"the director drives the battler's pose")
  flier:charge(256,0)
  for _=1,300 do if flier.context=="attack" then flier:update(1/30) end end
  ok(flier.nativeCharge.risen and flier.nativeOffset[2]==Special.FLY_TOP,
    "Fly's height stays after its state ends (841206D0 keeps the position)")
  director:stadiumActorReset("player",true)
  ok(flier.nativeLift==Special.FLY_TOP and flier.nativeOffset==nil,"84120700 with the flying bit: 200 up")
  director:stepNativeCharge("player")
  ok(flier.nativeCharge~=nil,"the Fly state holds while it is lifted")
  director:stadiumActorReset("player",false)
  director:stepNativeCharge("player")
  ok(flier.nativeLift==nil and flier.nativeCharge==nil,"the first reset without it brings it home")
  -- a kind's pose stays until the next home (Waterfall)
  local fall=rig(130,30)
  director.actors.player=fall
  director:stepNativeCharge("player")
  fall.context="attack"
  fall.special={kind=Special.WATERFALL,at=1,clock=0,ticks=0}
  for _=1,10 do fall:stepSpecial(1/30) end
  fall.renderer.finished=true
  fall:update(1/30)
  ok(fall.context=="idle" and fall.nativeOffset and fall.nativeOffset[2]>0,
    "after the attack the kind's position stays (no reset yet)")
  director:stadiumActorHome("player")
  ok(fall.nativeOffset==nil,"8411EFE4 brings it home")
  -- Dig's attack: hidden until Stadium shows the battler again
  local digger=rig(27,20)
  director.actors.player=digger
  director:stepNativeCharge("player")
  digger:charge(258,0)
  for _=1,400 do if digger.context=="attack" then digger:update(1/30) end end
  digger:attack(91)
  shown=false
  ok(digger.nativeCharge.attack and director:nativeChargeVisibility("player")=="hidden",
    "Dig's attack: Stadium's visibility (84120D34 hides the attacker)")
  digger.context="idle"
  director:stepNativeCharge("player")
  ok(digger.nativeCharge~=nil,"still hidden while Stadium hides it")
  shown=true
  director:stepNativeCharge("player")
  ok(digger.nativeCharge==nil,"the state ends when a shot shows it")
  Actor.forceFx=nil
end

print(("stadium2_battle_special_moves_test: %d checks passed"):format(checks))
