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
ok(Special.new({kind=4,trig=trig})==nil,"undecoded kinds are rejected")

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

print(("stadium2_battle_special_moves_test: %d checks passed"):format(checks))
