package.path="./?.lua;./?/init.lua;"..package.path
-- The camera director ported to Lua against the ROM in the MIPS VM on
-- identical memory and an identical 8003570C seed (D_80124D50):
--   841119CC  shot selector (random lists 0x28..0x32)
--   84114804  the attacker's shot and actor kind (841146D4, the animation
--             bytes, is stubbed on both sides: not part of the camera)
--   84114A04  the attack state's program choice (other calls stubbed)
--   84116BC0  the defender's hit shot and kind by event code
--   84110F64  program 1's tick, run through 84111348 and the runner 84111774
--   programs 3, 5, 13 and 17 (the attack programs of Waterfall, Fly, Surf
--             and Rapid Spin) the same way; 8411EFE4 (home pose) and
--             841125F4 (the other actor's state family) are scene / battle
--             flow and stubbed on both sides
--   8411F94C  the turn-start event (0x5A): a random turn shot and program
--             10 (841111D8 / 8410ED30 with 8410EA58, 8410EB50, 84120AC4);
--             8411FEE8 (the event timer) is stubbed and counted on both sides
--   8411A544  the faint state's camera part (8411A3D4's shot, program 11:
--             84110408 / 841107D8 with 84120C20, 8410D174, 8410B60C),
--             its non-camera calls stubbed
--   84119CF0  the turn check (family 17: events 2-9, 0x2C); non-camera calls
--             stubbed
--   84119908 / 8411A19C / 841206D0  woke up (family 19, program 7:
--             8410E8E4), confused (family 20) and the kind reset
--   84115E28 / 8411B304 / 8411B3B8  Dig (family 15, program 6: 84110640 with
--             84120D34, 841111B0) and Substitute (family 11)
--   8411B070 / 84116548  Transform (family 13) and Beat Up (family 22)
--   841155E8 / 841157D8 / 84115A64 / 84115B34 / 84116138  the charge turns
--             (families 6, 7, 8; programs 2: 841110EC / 84111170 and 15:
--             84110558)
--   84116980  the confusion self-hit (family 16)
--   8411B518 / 8411B5A8 / 8411B898  Substitute faded (family 21) and
--             dragged out (family 25)
--   84113590 / 8411C8A0 / 8411C9DC  the arena intro (family 26: split
--             views 8410AF1C / 8410B08C / 8410B224 / 8410B104, path 8410BDA0,
--             8410C304, 8410C400, 8411C7B8)
--   8411C310 / 8411C418  the opening send-out (family 24: the wipe, 8410B1CC,
--             8411C1D4, programs 21 / 22)
--   84113E7C  the idle camera (family 31; programs 4, 8, 9, 12, 14)
--   8411D2E4 / 8411D388  the victory (family 30; program 24)
--   841146D4 / 84116138 / 841163A0 / 841155E8 / 84115850  the motion row,
--             the charge's follow-up and Fly's rise (real motion records)
--   8411B070 / 8411B1F4  Transform's substates (real motion records)
--   84116548 / 84116808  Beat Up's substates (real motion records)
--   841193E0 / 8411957C  weather (0x30-0x35, program 29: 8410FB0C with
--             84120960) and full paralysis (0x36); non-camera calls stubbed
--   8411ABAC  recall (family 18): shot and program 27 (84110320 /
--             84110860); non-camera calls stubbed
--   84118C08  family 9 (status and residual events): the shot by event code
--             and program 0; its non-camera calls stubbed
--   8411BB04 + 8411BCC8 (send-out: 8410C544, 8410C720, 84120310), frame by
--             frame through the hand-over to program 26 (84110264 /
--             84110910 with 8410C840); sound and state calls stubbed
local file=io.open(os.getenv("STADIUM2_ROM") or "mods/STADIUM2_IMPORTER/baseroms/stadium2.z64","rb")
if not file then assert(os.getenv("STADIUM2_REQUIRE_ROM")~="1","ROM required");print("SKIP battle camera director ROM");return end
local rom=file:read("*a");file:close()
local prefix="mods.STADIUM2_IMPORTER.lib."
local VM=require("mods.STADIUM2_IMPORTER.tests.support.stadium2_battle_fx_mips")
local FxRom=require(prefix.."stadium2_battle_fx_rom")
local Native=require(prefix.."stadium2_battle_camera_native")
local f32=require(prefix.."stadium2_battle_fx_float")
local checks=0
local function ok(v,m) checks=checks+1 if not v then error("FAIL "..m,0) end end

local fragment=assert(FxRom.catalog(rom)).lifecycleAssets.fragment79
local C0,C1,GC0,GC1=0x85000000,0x85000100,0x85000200,0x85000300
local A0,A1,REC=0x85001000,0x85002000,0x85003000
local SEED=0x80124D50
math.randomseed(9001)
local function rnd(n) return math.random(0,n-1) end
local function rf(scale) return f32((math.random()*2-1)*scale) end
local function marker(read,actor)
  return {f32(read(actor+0x24)+3),f32(read(actor+0x638)+11),f32(read(actor+0x2C)-7)}
end
local function stub(v) v.r[2]=0 end
local function yes(v) v.r[2]=1 end

local function scenario()
  local w={}
  local function set(a,n,v) w[#w+1]={a,n,v} end
  local function setF(a,v) w[#w+1]={a,"f",v} end
  set(0x841911E0,4,C0);set(0x841911E4,4,C1);set(C0,4,GC0);set(C1,4,GC1)
  set(0x84191208,4,A0);set(0x8419120C,4,A1);set(0x84193DD0,4,REC)
  set(SEED,4,rnd(0x10000)*0x10000+rnd(0x10000))
  -- species include D_841839EC's (7, 8, 9: move 0x6E's exemptions),
  -- D_84183988's (23, 94, 236: no faint reframe) and 0xA1 (the faint bonus)
  -- and 0x32 / 0x33 (Diglett, Dugtrio: 84120D34 keeps them shown)
  local species={1,25,150,7,8,9,23,94,236,0xA1,0x32,0x33}
  for _,a in ipairs({A0,A1}) do
    set(a+0x1A,2,species[rnd(#species)+1])
    set(a+0x20,2,rnd(65536))
    setF(a+0x24,rf(400));setF(a+0x2C,rf(400))
    setF(a+0x34,f32(0.5+math.random()))
    set(a+0x618,1,rnd(8)==0 and ({0x13,0x39,0x7F,0xE5,0x6E,0x17,0x22,0xCD,0x12,0x2E})[rnd(10)+1] or 1+rnd(251))
    set(a+0x61F,1,rnd(40))
    for off=0x634,0x654,4 do setF(a+off,rf(off==0x64C and 600 or 150)) end
    setF(a+0x640,f32(math.random()*60))
    set(a+0x7EA,2,rnd(3))
    set(a+0x7EC,2,rnd(6)==0 and 1 or 0)
    set(a+0x7F4,2,rnd(4)==0 and rnd(64) or 0)
    set(a+0x2D4,4,0x85004000) -- dispatch rows (animation bytes; not compared)
    setF(a+0x28,rf(60))
    -- +0x678: the species' offset row (archive 0x49B780 + 0), as
    -- 84113014 loads it into D_84193DF8 + side * 0x20
    local row=(a==A0 and 0x84193DF8 or 0x84193E18)
    set(a+0x678,4,row)
    w[#w+1]={row,"species-offset",a}
    set(a+0xC,4,0x85006000) -- 84119908's indirect call (+0xC -> +0x2C)
    set(a+0x44,4,0x85006300) -- 84115A64 reads the model's frame count (+0xA)
  end
  set(0x8500602C,4,0x85006100)
  local codes={0,1,0x0A,0x0B,0x0C,0x0D,0x0E,0x0F,0x10,0x11,0x12,0x13,0x14,0x15,0x16,0x3B,0x4B,0x50}
  set(REC+4,2,codes[rnd(#codes)+1])
  for s=0,1 do
    set(REC+s*16+0xE,2,rnd(4)==0 and 0 or 1+rnd(300))
    set(REC+s*16+0x10,2,rnd(6)==0 and 0x20 or rnd(8))
    set(REC+s*16+0x12,2,rnd(3)==0 and 2 or rnd(16))
  end
  for _,c in ipairs({C0,C1}) do set(c+0x98,2,rnd(39)); setF(c+0x88,f32(30+math.random()*30)) end
  for _,g in ipairs({GC0,GC1}) do
    setF(g+0x2C,f32(20+math.random()*60))
    for off=0xA8,0xBC,4 do setF(g+off,rf(500)) end
  end
  return w
end

local function setup(hooks)
  local w=scenario()
  local all={[0x8411DD8C]=function(v) v:putVector(v.r[5],marker(function(a) return v:float(a) end,v.r[4]%4294967296)) end,
    [0x8411EF2C]=stub,[0x84120700]=stub,[0x841114A8]=stub,[0x841146D4]=stub,
    [0x8411EFE4]=stub,[0x841125F4]=stub,
    [0x84108E00]=stub, -- 8411EE74's status particles (not the camera's)
    [0x8411FEE8]=function(v) v.timer=(v.timer or 0)+1 end}
  for k,fn in pairs(hooks or {}) do all[k]=fn or nil end -- false removes a default stub
  local vm=VM.new({{base=0x80000400,bytes=rom:sub(0x1001,0xA8000)},{base=0x84100000,bytes=fragment}},all)
  local cam,seed
  local timers=0
  cam=assert(Native.load(rom,fragment,{
    markerPosition=function(actor) return marker(function(a) return cam.mem:f32(a) end,actor) end,
    -- the ROM reads D_8418C958 (particle attachment points) from memory
    attachmentPoint=function(i) return cam.mem:vec(0x8418C958+i*0xC) end,
    onEventTimer=function() timers=timers+1 end,
    random=function() seed=Native.nextRandom(seed) return seed end}))
  local speciesOf={}
  for _,e in ipairs(w) do if e[2]==2 and (e[1]==A0+0x1A or e[1]==A1+0x1A) then speciesOf[e[1]-0x1A]=e[3] end end
  for _,e in ipairs(w) do
    if e[2]=="species-offset" then
      local base=0x49B780+(speciesOf[e[3]]-1)*0x20
      for i=0,0x1F do local b=rom:byte(base+i+1);vm:write(e[1]+i,b,1);cam.mem:write(e[1]+i,b,1) end
    elseif e[2]=="f" then vm:putFloat(e[1],e[3]);cam.mem:setF32(e[1],e[3])
    else vm:write(e[1],e[3],e[2]);cam.mem:write(e[1],e[3],e[2]) end
  end
  seed=cam.mem:u32(SEED)
  vm:write(0x80000300,1,4) -- osTvType: NTSC (80001FF0 returns 60)
  cam.timers=function() return timers end
  return vm,cam,function() return seed end
end

local regions={{C0,0xA4},{C1,0xA4},{GC0,0xD0},{GC1,0xD0},{0x841911E8,4},{A0+0x61F,1},{A1+0x61F,1},
  {A0+1,1},{A1+1,1},{A0+0x7EA,2},{A1+0x7EA,2},{A0+0x30,12},{A1+0x30,12}}
local function compare(vm,cam,seed,label)
  for _,r in ipairs(regions) do
    for a=r[1],r[1]+r[2]-1 do
      if vm:byte(a)~=cam.mem:u8(a) then
        error(("FAIL %s byte %08X ROM %02X Lua %02X"):format(label,a,vm:byte(a),cam.mem:u8(a)),0)
      end
    end
  end
  if vm:read(SEED,4)~=seed() then error(("FAIL %s seed ROM %08X Lua %08X"):format(label,vm:read(SEED,4),seed()),0) end
end

-- 841119CC over every selector list and plain shots
local selectors={}
for round=1,400 do
  local vm,cam,seed=setup()
  local selector=round<=220 and 0x28+(round%11) or rnd(0x40)
  selectors[selector]=true
  vm:call(0x841119CC,{C0,selector});cam:chooseShot(C0,selector)
  compare(vm,cam,seed,("841119CC selector %X"):format(selector))
end
for s=0x28,0x32 do ok(selectors[s],("selector list %X exercised"):format(s)) end
ok(true,"841119CC matches the ROM (shot and seed) in 400 cases")

-- 84114804 and 84116BC0 on either actor
local kinds,codes={},{}
for round=1,600 do
  local vm,cam,seed=setup()
  local actor=rnd(2)==0 and A0 or A1
  if round%2==0 then
    vm:call(0x84114804,{actor});cam:attackShot(actor)
    compare(vm,cam,seed,("84114804 round %d move %X"):format(round,cam.mem:u8(actor+0x618)))
  else
    vm:call(0x84116BC0,{actor});cam:hitShot(actor)
    codes[cam.mem:u16(REC+4)]=true
    compare(vm,cam,seed,("84116BC0 round %d move %X code %X"):format(round,cam.mem:u8(actor+0x618),cam.mem:u16(REC+4)))
  end
  kinds[cam.mem:u8(actor+0x61F)]=true
end
local seenKinds=0 for _ in pairs(kinds) do seenKinds=seenKinds+1 end
ok(seenKinds>=10,"actor kinds vary ("..seenKinds..")")
for _,c in ipairs({0x0A,0x10,0x11,0x12,0x13,0x15,0x3B,0x4B}) do ok(codes[c],("event code %X exercised"):format(c)) end
ok(true,"84114804 and 84116BC0 match the ROM (shot, kind, seed) in 600 cases")

-- 84114A04's program choice (fork C) with the ROM function in the VM; its
-- non-camera calls are stubbed and 84113430 (the state gate) returns 1.
local programs={}
for round=1,300 do
  local vm,cam,seed=setup({[0x84113430]=yes,[0x84112E40]=stub,[0x84112EAC]=stub,[0x841126C8]=stub,
    [0x841120AC]=stub,[0x8411FEE8]=stub,[0x84112324]=stub})
  local actor=rnd(2)==0 and A0 or A1
  vm:call(0x84114A04,{actor});cam:attackState(actor)
  compare(vm,cam,seed,("84114A04 round %d move %X"):format(round,cam.mem:u8(actor+0x618)))
  programs[cam.mem:u32(C0+8)]=true
end
ok(programs[0x84110394] and programs[0x841105CC],"programs 0/1 and 5 (Fly) were loaded")
ok(true,"84114A04's camera part matches the ROM in 300 cases")

-- 8411F94C (the turn-start event) on the player
for round=1,200 do
  local vm,cam,seed=setup()
  vm:call(0x8411F94C,{0,0x5A});cam:turnStart(A0)
  compare(vm,cam,seed,("8411F94C round %d"):format(round))
end
ok(true,"8411F94C's camera part matches the ROM (shot, program 10, seed) in 200 cases")

-- 8411F9D8 (the first mover, event 0x5B) and program 18 (8410F1A8 /
-- 8410F3E8) through the runner until the program ends the event timer
local firstHooks={[0x8411FEE8]=function(v) v.timer=(v.timer or 0)+1; v:write(REC+6,v.r[4]%65536,2) end,
  [0x841125F4]=stub}
local firstEnded,firstHigh=0,0
for round=1,120 do
  local vm,cam,seed=setup(firstHooks)
  local actor=rnd(2)==0 and A0 or A1
  if rnd(3)==0 then for _,m in ipairs({vm,cam.mem}) do m:write(REC+(actor==A0 and 0 or 16)+0x12,2,2) end firstHigh=firstHigh+1 end
  vm:call(0x8411F9D8,{actor==A0 and 0 or 1,0x5B});cam:firstMoverState(actor)
  vm:call(0x841112C8,{});cam:clearProgram1()
  compare(vm,cam,seed,("8411F9D8 round %d"):format(round))
  if vm:read(REC+1,1)~=cam.mem:u8(REC+1) or vm:read(REC+6,2)~=cam.mem:u16(REC+6) then error(("FAIL 8411F9D8 round %d record"):format(round),0) end
  for tick=1,200 do
    vm:call(0x84111774,{GC0,GC1});cam:tick(GC0,GC1)
    compare(vm,cam,seed,("program 18 round %d tick %d"):format(round,tick))
    if vm:read(REC+6,2)~=cam.mem:u16(REC+6) then error(("FAIL program 18 round %d tick %d timer"):format(round,tick),0) end
    if cam.mem:u16(REC+6)==0 then firstEnded=firstEnded+1 break end
  end
  ok(cam.missing==nil,"program 18 runs only ported handlers")
end
ok(firstEnded>60,"program 18 reached its end in "..firstEnded.." of 120 rounds")
ok(firstHigh>10,"the side flag's bit 1 (the marker height, D_84188F8C) was exercised")

-- 8411A544 (the faint state) on either actor
local faintHooks={[0x84113430]=yes,[0x841126C8]=stub,[0x84112290]=stub,[0x84108A10]=stub,
  [0x80024480]=stub,[0x84112158]=stub,[0x84112564]=stub}
for round=1,200 do
  local vm,cam,seed=setup(faintHooks)
  local actor=rnd(2)==0 and A0 or A1
  vm:write(actor+0x7F6,rnd(4)==0 and 3 or 0,1)
  local skipped=vm:read(actor+0x7F6,1)==3
  vm:call(0x8411A544,{actor})
  if not skipped then cam:faintState(actor) end
  compare(vm,cam,seed,("8411A544 round %d"):format(round))
  if vm:read(actor+0x7F4,2)~=cam.mem:u16(actor+0x7F4) then error("FAIL 8411A544 +0x7F4",0) end
end
ok(true,"8411A544's camera part matches the ROM (shot, program 11, seed) in 200 cases")

-- 84118C08 (family 9) over every event code it handles, and others
local resHooks={[0x84113430]=yes,[0x84112EAC]=stub,[0x8411FEE8]=stub,[0x841126C8]=stub,
  [0x84111C1C]=stub,[0x80030420]=stub,[0x84113D38]=stub,[0x84112464]=stub,[0x84112324]=stub}
local resCodes={}
for round=1,300 do
  local vm,cam,seed=setup(resHooks)
  local actor=rnd(2)==0 and A0 or A1
  local code=({6,1,5,0x5A,0x60})[rnd(5)+1]
  if rnd(4)>0 then code=0x3C+rnd(0x1E) end
  if round%37==0 then code=0x4F end
  local move=rnd(8)==0 and 0xAE or 33
  local busy=rnd(6)==0 and 1 or 0
  -- sometimes the current shot is one of the list, so the reroll loops
  local listed=rnd(2)==0 and cam.mem:u16(0x84183BDC+rnd(6)*2) or nil
  for _,m in ipairs({vm,cam.mem}) do
    m:write(REC+4,code,2);m:write(REC+8,move,1)
    m:write(actor+0x7F6,busy,1)
    if listed then m:write(C0+0x98,listed,2) end
  end
  vm:call(0x84118C08,{actor});cam:residualState(actor)
  compare(vm,cam,seed,("84118C08 round %d code %X"):format(round,code))
  resCodes[code]=true
end
for _,c in ipairs({6,0x3C,0x3E,0x41,0x42,0x47,0x4A,0x4F,0x59}) do ok(resCodes[c],("family 9 code %X exercised"):format(c)) end
ok(true,"84118C08's camera part matches the ROM in 300 cases")

-- 84119CF0 (family 17) over its event codes
local checkHooks={[0x84113430]=yes,[0x841126C8]=stub,[0x84112E40]=stub,[0x8411FEE8]=stub,
  [0x841139D0]=stub,[0x84112464]=stub,[0x84113D38]=stub,[0x84112324]=stub,[0x84112158]=stub,
  [0x84112564]=stub,[0x84112580]=stub}
local checkCodes={}
for round=1,200 do
  local vm,cam,seed=setup(checkHooks)
  local actor=rnd(2)==0 and A0 or A1
  local code=({2,3,4,5,6,7,8,9,0x2C,0x1D,1,0x40})[rnd(12)+1]
  for _,m in ipairs({vm,cam.mem}) do m:write(REC+4,code,2) end
  vm:call(0x84119CF0,{actor});cam:turnCheckState(actor)
  compare(vm,cam,seed,("84119CF0 round %d code %X"):format(round,code))
  checkCodes[code]=true
end
for _,c in ipairs({2,4,7,8,9,0x2C}) do ok(checkCodes[c],("family 17 code %X exercised"):format(c)) end
ok(true,"84119CF0's camera part matches the ROM in 200 cases")

-- 84119908 (woke up), Dispatch_142 (confused) and 841206D0's kind reset
local wakeHooks={[0x84111C44]=stub,[0x841126C8]=stub,[0x841139D0]=stub,[0x84108CE8]=stub,
  [0x8003EF70]=stub,[0x84112564]=stub,[0x84112580]=stub,[0x84112158]=stub,[0x841120AC]=stub,
  [0x84111E50]=stub,[0x84112324]=stub,[0x84113430]=yes,[0x84113D38]=stub,
  [0x85006100]=function(v) v.r[2]=0x85006200 end,
  [0x84111C8C]=function(v) v.r[2]=rnd(2) end}
local wakeBranches={}
for round=1,240 do
  local vm,cam,seed=setup(wakeHooks)
  local actor=rnd(2)==0 and A0 or A1
  local kind=round%3
  local flags=cam.mem:u16(REC+(actor==A0 and 0 or 1)*16+0x12)
  if kind==0 then
    vm:call(0x84119908,{actor});cam:wakeState(actor)
    wakeBranches[bit.band(flags,4)~=0 and "program 0" or "program 7"]=true
  elseif kind==1 then
    vm:call(0x8411A19C,{actor});cam:confusedState(actor)
    wakeBranches[bit.band(flags,2)~=0 and "shot 24" or "shot 0"]=true
  else
    vm:call(0x841206D0,{actor});cam:kindReset(actor)
  end
  compare(vm,cam,seed,("wake/confused round %d kind %d"):format(round,kind))
end
for _,b in ipairs({"program 0","program 7","shot 24","shot 0"}) do ok(wakeBranches[b],"84119908 / Dispatch_142 branch "..b.." exercised") end
ok(true,"84119908, Dispatch_142 and 841206D0's camera parts match the ROM in 240 cases")

-- 84119908 then 84119AB4 (the wake-up's tail) frame by frame; 8003EC34 /
-- 84111FA4 (the wake animation has finished) answer from a ready frame
local wakeEnds={[3]=0,[5]=0}
for round=1,160 do
  local ready,frame=rnd(80),0
  local hooks={}
  for k,fn in pairs(wakeHooks) do hooks[k]=fn end
  local pick=rnd(2)
  hooks[0x84111C8C]=function(v) v.r[2]=pick end
  hooks[0x8003EC34]=function(v) v.r[2]=frame>=ready and 1 or 0 end
  hooks[0x84111FA4]=function(v) v.r[2]=frame>=ready and 1 or 0 end
  hooks[0x84111D64]=stub;hooks[0x84111DB4]=stub;hooks[0x84111E80]=stub
  hooks[0x84112564]=nil;hooks[0x84112580]=nil -- the record flags are compared
  hooks[0x8411FEE8]=function(v) v:write(REC+6,v.r[4]%65536,2) end
  local vm,cam,seed=setup(hooks)
  local actor=rnd(2)==0 and A0 or A1
  vm:call(0x84119908,{actor});cam:wakeState(actor)
  compare(vm,cam,seed,("wake setup round %d"):format(round))
  local substate=cam.mem:u8(actor+0x7F6)
  for f=1,0x100 do
    frame=f
    for _,m in ipairs({vm,cam.mem}) do m:write(actor+0x7E8,(m:read(actor+0x7E8,2)+1)%65536,2) end
    vm:call(0x84119AB4,{actor});substate=cam:wakeFrame(actor,substate,frame>=ready)
    compare(vm,cam,seed,("wake round %d frame %d substate %d"):format(round,f,substate))
    for _,off in ipairs({0x7E8,0x7E9,0x7F4,0x7F5,0x7F6}) do
      if vm:byte(actor+off)~=cam.mem:u8(actor+off) then error(("FAIL wake round %d frame %d byte +%X ROM %02X Lua %02X"):format(round,f,off,vm:byte(actor+off),cam.mem:u8(actor+off)),0) end
    end
    if vm:read(REC+6,2)~=cam.mem:u16(REC+6) or vm:read(REC+1,1)~=cam.mem:u8(REC+1) then error(("FAIL wake round %d frame %d record"):format(round,f),0) end
    if substate==3 or substate==5 then wakeEnds[substate]=wakeEnds[substate]+1 break end
  end
end
ok(wakeEnds[3]>40 and wakeEnds[5]>20,("the wake-up's tail ended in %d / %d rounds (awake / underground)"):format(wakeEnds[3],wakeEnds[5]))

-- 84115E28 (Dig), Dispatch_079 / 8411B3B8 substate 2 (Substitute)
local moveHooks={[0x84113430]=yes,[0x841126C8]=stub,[0x84111E50]=stub,[0x84111D64]=stub,
  [0x84111DB4]=stub,[0x84111E80]=stub,[0x80030420]=stub,[0x84112158]=stub,[0x84112B64]=stub,
  [0x84112564]=stub}
local moveBranches={}
for round=1,300 do
  local vm,cam,seed=setup(moveHooks)
  local actor=rnd(2)==0 and A0 or A1
  local kind=round%3
  if kind==0 then
    if rnd(4)==0 then for _,m in ipairs({vm,cam.mem}) do m:write(C0+0x98,0x21,2) end end
    vm:call(0x84115E28,{actor});cam:digState(actor)
    moveBranches[(cam.mem:u16(actor+0x7EC)%2==1 and "dig held" or "dig shot")]=true
  elseif kind==1 then
    for _,m in ipairs({vm,cam.mem}) do m:write(actor+0x618,0xA4,1) end
    vm:call(0x8411B304,{actor});cam:substituteState(actor)
    moveBranches["substitute"]=true
  else
    for _,m in ipairs({vm,cam.mem}) do m:write(actor+0x7F6,2,1) end
    vm:call(0x8411B3B8,{actor});cam:substituteDollState(actor)
    moveBranches["doll"]=true
  end
  compare(vm,cam,seed,("Dig/Substitute round %d kind %d"):format(round,kind))
end
for _,b in ipairs({"dig held","dig shot","substitute","doll"}) do ok(moveBranches[b],"Dig/Substitute branch "..b.." exercised") end
ok(true,"84115E28, Dispatch_079 and 8411B3B8's camera parts match the ROM in 300 cases")

-- 8411B070 (Transform) and Dispatch_156 (Beat Up)
local tbHooks={[0x84113430]=yes,[0x84111E50]=stub,[0x84111D64]=stub,[0x84111DB4]=stub,[0x84111E80]=stub,
  [0x841139D0]=stub,[0x800427B8]=yes,[0x841126C8]=stub,[0x84111C44]=stub,[0x84112EAC]=stub,
  [0x84112EDC]=stub,[0x84116410]=stub}
for round=1,200 do
  local vm,cam,seed=setup(tbHooks)
  local actor=rnd(2)==0 and A0 or A1
  local move=rnd(3)==0 and 1+rnd(251) or (round%2==0 and 0x90 or 0xFB)
  for _,m in ipairs({vm,cam.mem}) do m:write(actor+0x618,move,1) end
  if round%2==0 then vm:call(0x8411B070,{actor});cam:transformState(actor)
  else vm:call(0x84116548,{actor});cam:beatUpState(actor) end
  compare(vm,cam,seed,("Transform/Beat Up round %d move %X"):format(round,move))
end
ok(true,"8411B070 and Dispatch_156's camera parts match the ROM in 200 cases")

-- the charge turns: 841155E8 / 841157D8 (Fly), 84115A64 / 84115B34 (Dig's
-- first turn) and 84116138 (Razor Wind, Solar Beam, Skull Bash, Sky Attack)
local chargeHooks={[0x84113430]=yes,[0x84112EAC]=stub,[0x841126C8]=stub,[0x84111E50]=stub,
  [0x84111D64]=stub,[0x84111E80]=stub,[0x84111DB4]=stub,[0x80030420]=stub,[0x84112218]=stub,
  [0x8003EC34]=stub,[0x84112158]=stub,[0x841133EC]=stub,[0x84123F60]=stub,[0x841088CC]=stub,
  [0x84112564]=stub,[0x800231A0]=stub}
local chargeKinds={}
for round=1,400 do
  local vm,cam,seed=setup(chargeHooks)
  local actor=rnd(2)==0 and A0 or A1
  local kind=round%5
  if rnd(5)==0 then for _,m in ipairs({vm,cam.mem}) do m:write(C0+0x98,0x21,2) end end
  if kind==0 then vm:call(0x841155E8,{actor});cam:flyUpState(actor)
  elseif kind==1 then
    for _,m in ipairs({vm,cam.mem}) do m:write(actor+0x7E8,1,2) end
    vm:call(0x841157D8,{actor});cam:flyHighShot(actor)
  elseif kind==2 then vm:call(0x84115A64,{actor});cam:digHoleState(actor)
  elseif kind==3 then
    for _,m in ipairs({vm,cam.mem}) do m:write(actor+0x7F6,1,1) end
    vm:call(0x84115B34,{actor});cam:digHoleShot(actor)
  else
    local code=0x16+rnd(4)
    for _,m in ipairs({vm,cam.mem}) do m:write(REC+4,code,2) end
    vm:call(0x84116138,{actor});cam:chargeState(actor)
  end
  chargeKinds[kind]=true
  compare(vm,cam,seed,("charge round %d kind %d"):format(round,kind))
end
ok(true,"the charge turns' camera parts match the ROM in 400 cases")

-- Dispatch_114 (confusion self-hit, family 16)
local selfHooks={[0x84113430]=yes,[0x84112EAC]=stub,[0x841126C8]=stub,[0x84111E50]=stub,
  [0x84111D64]=stub,[0x84111E80]=stub,[0x84111DB4]=stub,[0x84112564]=stub}
for round=1,120 do
  local vm,cam,seed=setup(selfHooks)
  local actor=rnd(2)==0 and A0 or A1
  vm:call(0x84116980,{actor});cam:selfHitState(actor)
  compare(vm,cam,seed,("self-hit round %d"):format(round))
end
ok(true,"Dispatch_114's camera part matches the ROM in 120 cases (seed included)")

-- Dispatch_149 / 8411B5A8 substate 2 (Substitute faded), 8411B898
-- substate 1 (dragged out)
local fadeHooks={[0x841139D0]=stub,[0x84113920]=stub,[0x84113430]=yes,[0x841126C8]=stub,
  [0x84112158]=stub,[0x84112C98]=function(v) end,[0x84112564]=stub,[0x84112580]=stub,
  [0x84112464]=stub,[0x84112324]=stub}
for round=1,240 do
  local vm,cam,seed=setup(fadeHooks)
  local actor=rnd(2)==0 and A0 or A1
  local kind=round%3
  if rnd(5)==0 then for _,m in ipairs({vm,cam.mem}) do m:write(C0+0x98,0x21,2) end end
  if kind==0 then vm:call(0x8411B518,{actor});cam:substituteFadedState(actor)
  elseif kind==1 then
    for _,m in ipairs({vm,cam.mem}) do m:write(actor+0x7F6,2,1) end
    vm:call(0x8411B5A8,{actor})
    -- 84112C98 (the species reload) is hooked out; 8411B5A8 clears +0x7EA
    -- itself after the program load, so both sides end the same
    cam:substituteFadedShot(actor)
  else
    for _,m in ipairs({vm,cam.mem}) do m:write(actor+0x7F6,1,1) end
    vm:call(0x8411B898,{actor});cam:dragOutShot(actor)
  end
  compare(vm,cam,seed,("faded/dragged round %d kind %d"):format(round,kind))
end
ok(true,"Dispatch_149, 8411B5A8 and 8411B898's camera parts match the ROM in 240 cases")

-- the arena intro (family 26): 84113590 (the path from the ROM archive),
-- 8411C8A0's camera part and 8411C9DC's frames with the camera tick, split
-- views included (viewport, projection and draw flags of both GeoCameras)
local introHooks={[0x84113560]=stub,[0x8410890C]=stub,[0x80023A3C]=stub,[0x8006456C]=stub,
  [0x841125A4]=stub,
  [0x80003F74]=function(v)
    local dst,src,stop=v.r[4]%4294967296,v.r[5]%4294967296,v.r[6]%4294967296
    for i=0,stop-src-1 do v:write(dst+i,rom:byte(src+i+1),1) end
  end}
local introRegions={{0x84190520,2504},{0x841911F9,1}}
local function compareViews(vm,cam,label)
  for _,base in ipairs({Native.VIEW0,Native.VIEW1}) do
    for a=base,base+0xEF do
      if vm:byte(a)~=cam.mem:u8(a) then error(("FAIL %s view byte %08X ROM %02X Lua %02X"):format(label,a,vm:byte(a),cam.mem:u8(a)),0) end
    end
  end
end
local introPaths,introSplit,introEnded={},0,0
for round=1,12 do
  local vm,cam,seed=setup(introHooks)
  local path=(round-1)%6
  -- the intro's view functions use D_84190428 / D_841910E0 directly: point
  -- the controllers at them (as in the game) and start from the scenario's
  -- GeoCamera state
  for _,m in ipairs({vm,cam.mem}) do
    for off=0,0xEF,4 do
      m:write(Native.VIEW0+off,m==vm and vm:read(GC0+off,4) or cam.mem:u32(GC0+off),4)
      m:write(Native.VIEW1+off,m==vm and vm:read(GC1+off,4) or cam.mem:u32(GC1+off),4)
    end
    m:write(C0,Native.VIEW0,4);m:write(C1,Native.VIEW1,4)
  end
  introPaths[path]=true
  for _,m in ipairs({vm,cam.mem}) do m:write(0x841910D8,0,4) end
  vm:call(0x84113590,{path});cam:loadIntroPath(path)
  for _,r in ipairs(introRegions) do
    for a=r[1],r[1]+r[2]-1 do
      if vm:byte(a)~=cam.mem:u8(a) then error(("FAIL intro path %d byte %08X ROM %02X Lua %02X"):format(path,a,vm:byte(a),cam.mem:u8(a)),0) end
    end
  end
  vm:call(0x8411C8A0,{A0});cam:arenaIntroSetup()
  compare(vm,cam,seed,("arena intro setup path %d"):format(path))
  compareViews(vm,cam,("arena intro setup path %d"):format(path))
  local substate=1
  for _,m in ipairs({vm,cam.mem}) do m:write(A0+0x7F6,1,1) end
  for frame=0,0xA5 do
    for _,m in ipairs({vm,cam.mem}) do m:write(A0+0x7E8,frame,2) end
    vm:call(0x8411C9DC,{A0})
    substate=cam:arenaIntroFrame(substate)
    local vmState=vm:byte(A0+0x7F6)
    if vmState~=substate then error(("FAIL arena intro path %d frame %d substate ROM %d Lua %d"):format(path,frame,vmState,substate),0) end
    vm:call(0x84111774,{Native.VIEW0,Native.VIEW1});cam:tick(Native.VIEW0,Native.VIEW1)
    compare(vm,cam,seed,("arena intro path %d frame %d substate %d"):format(path,frame,substate))
    compareViews(vm,cam,("arena intro path %d frame %d substate %d"):format(path,frame,substate))
    if cam.mem:u8(Native.VIEW1+1)%32>=16 then introSplit=introSplit+1 end
  end
  if substate==3 then introEnded=introEnded+1 end
  ok(cam.missing==nil,"the arena intro runs only ported handlers")
end
for i=0,5 do ok(introPaths[i],("intro path %d exercised"):format(i)) end
ok(introSplit>0,"the second view was drawn during the intro ("..introSplit.." frames)")
ok(introEnded==12,"every arena intro ended its split (8410B104)")
ok(true,"the arena intro matches the ROM over 12 x 166 frames")

-- the opening send-out (family 24): 8411C310's camera part and 8411C418's
-- substates with the camera tick; 8003EC34 (the model animation's end)
-- answers from a per-round ready frame for each actor
local openingDone,openingWiped=0,0
for round=1,10 do
  local ready={[A0]=2+rnd(20),[A1]=rnd(60)}
  local tick=0
  local hooks={[0x84112158]=stub,[0x80024480]=stub,[0x84108E00]=stub,[0x84112564]=stub,
    [0x841120AC]=stub,[0x84111C1C]=stub,[0x8410890C]=stub,[0x8006456C]=stub,[0x80023A3C]=stub,
    [0x84108A10]=stub,[0x8003EC34]=function(v) v.r[2]=tick>=(ready[v.r[4]%4294967296] or 0) and 1 or 0 end}
  local vm,cam,seed=setup(hooks)
  for _,m in ipairs({vm,cam.mem}) do
    for off=0,0xEF,4 do
      m:write(Native.VIEW0+off,m==vm and vm:read(GC0+off,4) or cam.mem:u32(GC0+off),4)
      m:write(Native.VIEW1+off,m==vm and vm:read(GC1+off,4) or cam.mem:u32(GC1+off),4)
    end
    m:write(C0,Native.VIEW0,4);m:write(C1,Native.VIEW1,4)
    m:write(A0+0x7E8,0,2)
  end
  -- the game's slots are never empty (84111774 has no null check)
  vm:call(0x84111248,{});vm:call(0x841112C8,{});cam:clearProgram();cam:clearProgram1()
  vm:call(0x8411C310,{A0});cam:openingSetup()
  compare(vm,cam,seed,("opening setup round %d"):format(round))
  local substate=1
  for frame=1,200 do
    tick=frame
    for _,m in ipairs({vm,cam.mem}) do m:write(A0+0x7E8,(m==vm and vm:read(A0+0x7E8,2) or cam.mem:u16(A0+0x7E8))+1,2) end
    vm:call(0x8411C418,{A0})
    substate=cam:openingFrame(substate,tick>=ready[A0],tick>=ready[A1])
    if vm:byte(A0+0x7F6)~=substate then error(("FAIL opening round %d frame %d substate ROM %d Lua %d"):format(round,frame,vm:byte(A0+0x7F6),substate),0) end
    vm:call(0x84111774,{Native.VIEW0,Native.VIEW1});cam:tick(Native.VIEW0,Native.VIEW1)
    compare(vm,cam,seed,("opening round %d frame %d substate %d"):format(round,frame,substate))
    compareViews(vm,cam,("opening round %d frame %d substate %d"):format(round,frame,substate))
    if substate==3 then openingWiped=openingWiped+1 end
    if substate==6 then break end
  end
  if substate==6 then openingDone=openingDone+1 end
  ok(cam.missing==nil,"the opening runs only ported handlers")
end
ok(openingWiped==10,"every opening wiped to the foe's view")
ok(openingDone==10,"every opening reached its end")
ok(true,"the opening send-out matches the ROM in 10 rounds")

-- the idle camera (family 31): 84113E7C's cases over the idle codes; the
-- event timer (record +6) and shot row 0x27 (84113658) compared too
local idleHooks={[0x84113430]=yes,[0x8410890C]=stub,[0x8002B43C]=stub,[0x8002B2FC]=stub,
  [0x8411FEE8]=function(v) v:write(REC+6,v.r[4]%65536,2) end,
  [0x80003F74]=function(v)
    local dst,src,stop=v.r[4]%4294967296,v.r[5]%4294967296,v.r[6]%4294967296
    for i=0,stop-src-1 do v:write(dst+i,rom:byte(src+i+1),1) end
  end}
local idleCodes,idleFamily={},{}
for round=1,400 do
  local vm,cam,seed=setup(idleHooks)
  local actor=rnd(2)==0 and A0 or A1
  local code=({0x5C,0x5D,0x5E,0x5F,0x60,0x61,0x62,0x63,0x64,0x68,0x69})[rnd(11)+1]
  for _,m in ipairs({vm,cam.mem}) do
    m:write(REC+4,code,2);m:write(REC+6,0x64,2)
    m:write(0x841911FA,1,1)
  end
  vm:call(0x84113E7C,{actor})
  local family=cam:idleState(actor)
  compare(vm,cam,seed,("idle round %d code %X"):format(round,code))
  if vm:read(REC+6,2)~=cam.mem:u16(REC+6) then error(("FAIL idle round %d code %X timer ROM %d Lua %d"):format(round,code,vm:read(REC+6,2),cam.mem:u16(REC+6)),0) end
  for a=Native.SHOTS+0x444,Native.SHOTS+0x453 do
    if vm:byte(a)~=cam.mem:u8(a) then error(("FAIL idle round %d code %X shot row 0x27 byte %08X"):format(round,code,a),0) end
  end
  idleCodes[code]=true
  idleFamily[tostring(family)]=true
end
for _,c in ipairs({0x5C,0x5F,0x60,0x61,0x62,0x63,0x64,0x68}) do ok(idleCodes[c],("idle code %X exercised"):format(c)) end
ok(idleFamily["1"] and idleFamily["0"],"idle cases giving family 0 and family 1 exercised")
ok(true,"84113E7C's camera part matches the ROM in 400 cases (timer, shot row 0x27, seed)")

-- the victory (family 30): 8411D2E4's camera part, then 8411D388 with the
-- camera tick until it ends
local victoryHooks={[0x8411FEE8]=function(v) v:write(REC+6,v.r[4]%65536,2) end,
  [0x841126C8]=stub,[0x84111C44]=stub,[0x84112290]=stub,[0x84108A10]=stub,[0x8002B2FC]=stub}
local victoryEnded=0
for round=1,20 do
  local vm,cam,seed=setup(victoryHooks)
  local actor=rnd(2)==0 and A0 or A1
  for _,m in ipairs({vm,cam.mem}) do
    for off=0,0xEF,4 do
      m:write(Native.VIEW0+off,m==vm and vm:read(GC0+off,4) or cam.mem:u32(GC0+off),4)
      m:write(Native.VIEW1+off,m==vm and vm:read(GC1+off,4) or cam.mem:u32(GC1+off),4)
    end
    m:write(C0,Native.VIEW0,4);m:write(C1,Native.VIEW1,4)
  end
  vm:call(0x84111248,{});vm:call(0x841112C8,{});cam:clearProgram();cam:clearProgram1()
  vm:call(0x8411D2E4,{actor});cam:victoryState(actor)
  compare(vm,cam,seed,("victory setup round %d"):format(round))
  compareViews(vm,cam,("victory setup round %d"):format(round))
  local substate=0
  for frame=1,200 do
    for _,m in ipairs({vm,cam.mem}) do m:write(actor+0x7E8,((m==vm and vm:read(actor+0x7E8,2) or cam.mem:u16(actor+0x7E8))+1)%65536,2) end
    vm:call(0x8411D388,{actor});substate=cam:victoryFrame(actor,substate)
    if vm:byte(actor+0x7F6)~=substate then error(("FAIL victory round %d frame %d substate ROM %d Lua %d"):format(round,frame,vm:byte(actor+0x7F6),substate),0) end
    vm:call(0x84111774,{Native.VIEW0,Native.VIEW1});cam:tick(Native.VIEW0,Native.VIEW1)
    compare(vm,cam,seed,("victory round %d frame %d substate %d"):format(round,frame,substate))
    compareViews(vm,cam,("victory round %d frame %d substate %d"):format(round,frame,substate))
    if vm:read(REC+6,2)~=cam.mem:u16(REC+6) then error(("FAIL victory round %d frame %d timer"):format(round,frame),0) end
    if substate==2 then victoryEnded=victoryEnded+1 break end
  end
  ok(cam.missing==nil,"the victory runs only ported handlers")
end
ok(victoryEnded>0,"the victory reached program 7 and its end in "..victoryEnded.." of 20 rounds")

-- the animation-timed follow-ups with the actors' real motion records
-- (+0x2D4, 0x1530 bytes): 841146D4's row copy, the charge's 84116138 /
-- Dispatch_059 and Fly's 841155E8 / Dispatch_045. 8003EC34 (the model
-- animation's end) answers from a ready frame; Fly's height rises 17 a frame.
local Dispatch=require(prefix.."animation_dispatch")
local recordCache={}
local function motionRecord(species)
  if recordCache[species] then return recordCache[species] end
  local rows=assert(Dispatch.forSpecies(rom,species))
  local parts={}
  for i=0,rows.n-1 do parts[#parts+1]=rows[i].raw end
  recordCache[species]=table.concat(parts)
  return recordCache[species]
end
local function loadRecords(vm,cam)
  for _,a in ipairs({A0,A1}) do
    local base=a==A0 and 0x85010000 or 0x85012000
    local bytes=motionRecord(cam.mem:u16(a+0x1A))
    for _,m in ipairs({vm,cam.mem}) do
      m:write(a+0x2D4,base,4)
      for i=1,#bytes do m:write(base+i-1,bytes:byte(i),1) end
    end
  end
end
local followEnded={charge=0,fly=0}
for round=1,160 do
  local ready=4+rnd(80)
  local tick=0
  local isFly=round%2==0
  local hooks={[0x841146D4]=false,[0x84113430]=yes,[0x84112EAC]=stub,[0x841126C8]=stub,[0x84111E50]=stub,
    [0x84111D64]=stub,[0x84111E80]=stub,[0x84111DB4]=stub,[0x80030420]=stub,[0x84112218]=stub,
    [0x8003EC34]=function(v) v.r[2]=tick>=ready and 1 or 0 end,[0x84112158]=stub,[0x841133EC]=stub,
    [0x84123F60]=stub,[0x841088CC]=stub,[0x84112564]=stub,[0x800231A0]=stub,[0x8003F4E8]=stub,
    [0x84124104]=stub,[0x841139D0]=stub,
    [0x8411FEE8]=function(v) v:write(REC+6,v.r[4]%65536,2) end}
  local vm,cam,seed=setup(hooks)
  loadRecords(vm,cam)
  vm:call(0x84111248,{});vm:call(0x841112C8,{});cam:clearProgram();cam:clearProgram1()
  local actor=rnd(2)==0 and A0 or A1
  for _,m in ipairs({vm,cam.mem}) do m:write(actor+0x7EC,0,2) end
  if isFly then
    for _,m in ipairs({vm,cam.mem}) do m:write(REC+4,0x1A,2);m:write(actor+0x618,0x13,1) end
    vm:call(0x841155E8,{actor});cam:flyUpState(actor)
  else
    local code=0x16+rnd(4)
    for _,m in ipairs({vm,cam.mem}) do m:write(REC+4,code,2) end
    vm:call(0x84116138,{actor});cam:chargeState(actor)
  end
  compare(vm,cam,seed,("follow-up setup round %d"):format(round))
  for off=0x616,0x661 do
    if vm:byte(actor+off)~=cam.mem:u8(actor+off) then error(("FAIL follow-up round %d row copy byte +%X"):format(round,off),0) end
  end
  if vm:read(actor+0x7E8,2)~=cam.mem:u16(actor+0x7E8) then error(("FAIL follow-up round %d frame counter"):format(round),0) end
  local substate=0
  for _,m in ipairs({vm,cam.mem}) do m:write(actor+0x7F6,0,1) end
  for frame=1,160 do
    tick=frame
    for _,m in ipairs({vm,cam.mem}) do
      m:write(actor+0x7E8,((m==vm and vm:read(actor+0x7E8,2) or cam.mem:u16(actor+0x7E8))+1)%65536,2)
      if isFly then
        local y=f32((m==vm and vm:float(actor+0x28) or cam.mem:f32(actor+0x28))+17)
        if m==vm then vm:putFloat(actor+0x28,y) else cam.mem:setF32(actor+0x28,y) end
      end
    end
    if isFly then
      local high=f32(cam.mem:f32(actor+0x28)-cam.mem:f32(actor+0x650))>=200
      vm:call(0x84115850,{actor});substate=cam:flyRiseFrame(actor,substate,high)
    else
      vm:call(0x841163A0,{actor});substate=cam:chargeFollowFrame(actor,substate,tick>=ready)
    end
    if vm:byte(actor+0x7F6)~=substate then error(("FAIL follow-up round %d frame %d substate ROM %d Lua %d"):format(round,frame,vm:byte(actor+0x7F6),substate),0) end
    vm:call(0x84111774,{GC0,GC1});cam:tick(GC0,GC1)
    compare(vm,cam,seed,("follow-up round %d frame %d substate %d"):format(round,frame,substate))
    if vm:read(REC+6,2)~=cam.mem:u16(REC+6) then error(("FAIL follow-up round %d frame %d timer ROM %d Lua %d"):format(round,frame,vm:read(REC+6,2),cam.mem:u16(REC+6)),0) end
    if isFly and vm:read(actor+0x28,4)~=cam.mem:u32(actor+0x28) then error(("FAIL fly round %d frame %d height"):format(round,frame),0) end
  end
  if substate>=1 then followEnded[isFly and "fly" or "charge"]=followEnded[isFly and "fly" or "charge"]+1 end
  ok(cam.missing==nil,"the follow-ups run only ported handlers")
end
ok(followEnded.charge>20 and followEnded.fly>20,("the charge (%d) and Fly (%d) follow-ups reached their next step"):format(followEnded.charge,followEnded.fly))

-- the hit (family 4): 841170A0 (84116BC0's row copy from the real motion
-- record, the length by code, 84116B40), then 841187E4 frame by frame with
-- the camera runner: 84117744 (per-move lengths, Foresight's re-shots), the
-- jolt 84117880, Lock-On 84117A24, 84117648 / 841175D4 (the HP bar from
-- D_8419521C) and the flagged 0x0A ends (84117CEC / 84117DC4). Non-camera
-- calls are stubbed; 841133EC (busy) is clear.
local hitCodes={0x0A,0x0A,0x0A,0x0B,0x0C,0x0D,0x0E,0x0F,0x10,0x11,0x12,0x13,0x14,0x15,0x3B,0x4B,0x50}
local hitMoves={0xC7,0xC1,0xCD,0x12,0x2E,0xB4}
local hitSeen={ended=0,jolt=0,lockOn=0,foresight=0,settled=0,unknown=0}
for round=1,420 do
  local settleAt=rnd(4)==0 and 10000 or rnd(90)
  local frame=0
  local hooks={[0x84113430]=yes,[0x84112E40]=stub,[0x84112158]=stub,[0x841139D0]=stub,[0x84116EB4]=false,
    [0x841120AC]=stub,[0x841087B8]=stub,[0x800231A0]=stub,[0x84112464]=stub,[0x84112324]=stub,
    [0x841126C8]=stub,[0x80030420]=stub,[0x84113920]=stub,[0x841133EC]=stub,
    [0x84117AA0]=stub,[0x80023A3C]=stub,[0x84123F60]=stub,[0x84112580]=stub,[0x8410890C]=stub,
    [0x84108E00]=stub,[0x84124104]=stub,[0x84112218]=stub,[0x84111D64]=stub,[0x8003EC34]=stub,
    [0x8003EF70]=stub,[0x84108A10]=stub,[0x84112418]=stub,[0x84111C8C]=stub,[0x8411200C]=stub,
    [0x84111DB4]=stub,[0x84111E50]=stub,[0x84111E80]=stub,[0x84112564]=stub,
    [0x8411FEE8]=function(v) v:write(REC+6,v.r[4]%65536,2) end}
  local vm,cam,seed=setup(hooks)
  loadRecords(vm,cam)
  local actor=rnd(2)==0 and A0 or A1
  local side=actor==A0 and 0 or 1
  local code=hitCodes[rnd(#hitCodes)+1]
  local move=rnd(3)==0 and hitMoves[rnd(#hitMoves)+1] or 1+rnd(251)
  local frames=rnd(3)==0 and rnd(0x50) or 0x40+rnd(0x100)
  local result=({0,2,3,4,5,6,0x10,0x12,0x13,0x14})[rnd(10)+1]
  -- record +8 (80062D20's move: Fury Attack 0x1F / Twineedle 0x29 effects
  -- 0x1D / 0x4D, Triple Kick 0xA7, Beat Up 0xFB, Double Kick 0x18 not listed)
  local multiMove=rnd(2)==0 and ({0x1F,0x29,0xA7,0xFB,0x18,0x03})[rnd(6)+1] or nil
  local hitCount=1+rnd(3)
  local hitIndex=1+rnd(hitCount)
  if multiMove and hitIndex~=hitCount then hitSeen.multi=(hitSeen.multi or 0)+1 end
  local row620
  if round>400 then
    -- the boundaries: an end exactly 40 frames past +0x620 (84116B40) and
    -- the 0xF length that keeps +0x7F4 (84117648)
    if round<=410 then code,result,row620=0x0B,0x10,0x3C-40+(round%3)-1
    else code,frames,move=0x0C,0xE+(round%2),1+rnd(0xB0);settleAt=10000 end
  end
  for _,m in ipairs({vm,cam.mem}) do
    m:write(actor+0x7EC,0,2);m:write(REC+4,code,2);m:write(actor+0x618,move,1)
    m:write(REC+9,result,1)
    m:write(REC+8,multiMove or move,1);m:write(REC+0xA,hitCount,1);m:write(REC+0xB,hitIndex,1)
    m:write(0x85006300+0xA,frames,2)
  end
  if row620 then
    for _,m in ipairs({vm,cam.mem}) do m:write(m:read(actor+0x2D4,4)+(move-1)*0x14+8,row620,1);m:write(actor+0x7F4,3,2) end
  end
  if round>410 then for _,m in ipairs({vm,cam.mem}) do m:write(actor+0x7F4,3,2) end end
  vm:putFloat(0x8419521C+side*24,settleAt==0 and 0 or 1)
  vm:call(0x841112C8,{});cam:clearProgram1()
  vm:call(0x841170A0,{actor})
  local known=cam:hitStart(actor,frames)
  ok(known,"the length is set when the hit animation's length is known")
  compare(vm,cam,seed,("hit setup round %d code %X move %X"):format(round,code,move))
  for _,off in ipairs({0x619,0x61A,0x620,0x61C,0x61D,0x628,0x62A,0x62C,0x661,0x7E8,0x7E9,0x7F6}) do
    if vm:byte(actor+off)~=cam.mem:u8(actor+off) then error(("FAIL hit setup round %d code %X byte +%X ROM %02X Lua %02X"):format(round,code,off,vm:byte(actor+off),cam.mem:u8(actor+off)),0) end
  end
  if vm:read(REC+6,2)~=cam.mem:u16(REC+6) then error(("FAIL hit setup round %d timer"):format(round),0) end
  local jolted,ended=false,false
  for f=1,0x140 do
    frame=f
    if f==settleAt then vm:putFloat(0x8419521C+side*24,0);hitSeen.settled=hitSeen.settled+1 end
    local settled=vm:float(0x8419521C+side*24)==0
    for _,m in ipairs({vm,cam.mem}) do m:write(actor+0x7E8,(m:read(actor+0x7E8,2)+1)%65536,2) end
    vm:call(0x841187E4,{actor});cam:hitFollowFrame(actor,settled)
    if cam.mem:f32(C0+0x8C)~=0 and not jolted then jolted=true end
    vm:call(0x84111774,{GC0,GC1});cam:tick(GC0,GC1)
    compare(vm,cam,seed,("hit round %d code %X move %X frame %d"):format(round,code,move,f))
    if vm:read(actor+0x7F4,2)%4~=cam.mem:u16(actor+0x7F4)%4 then error(("FAIL hit round %d frame %d +0x7F4 bits 0-1"):format(round,f),0) end
    for _,off in ipairs({0x61A,0x619,0x7E8,0x7E9,0x7F6}) do
      if vm:byte(actor+off)~=cam.mem:u8(actor+off) then error(("FAIL hit round %d code %X move %X frame %d byte +%X ROM %02X Lua %02X"):format(round,code,move,f,off,vm:byte(actor+off),cam.mem:u8(actor+off)),0) end
    end
    if vm:read(REC+6,2)~=cam.mem:u16(REC+6) then error(("FAIL hit round %d code %X frame %d timer ROM %d Lua %d"):format(round,code,f,vm:read(REC+6,2),cam.mem:u16(REC+6)),0) end
    if cam.mem:u8(actor+0x7F6)~=0 or (cam.mem:u16(REC+6)==0 and f>1) then ended=true break end
  end
  if ended then hitSeen.ended=hitSeen.ended+1 end
  if jolted then hitSeen.jolt=hitSeen.jolt+1 end
  if move==0xC7 then hitSeen.lockOn=hitSeen.lockOn+1 end
  if move==0xC1 then hitSeen.foresight=hitSeen.foresight+1 end
end
ok(hitSeen.ended>250,"the hit state reached its end in "..hitSeen.ended.." of 420 rounds")
ok(hitSeen.jolt>60,"the hit jolt fired in "..hitSeen.jolt.." rounds")
ok(hitSeen.lockOn>5 and hitSeen.foresight>5,"Lock-On and Foresight were exercised")
ok(hitSeen.settled>100,"the HP bar settled mid-state in "..hitSeen.settled.." rounds")
ok((hitSeen.multi or 0)>40,"non-final multi-hit hits were exercised in "..tostring(hitSeen.multi).." rounds")
do
  local vm,cam=setup()
  for _,m in ipairs({vm,cam.mem}) do m:write(REC+4,0x0A,2);m:write(REC+0x12,0,2);m:write(REC+0x22,0,2) end
  ok(cam:hitStart(A0,nil)==false,"an unknown hit animation length leaves the 0x0A length unset")
end

-- Transform's substates (8411B1F4) with the real motion records; 800427B8
-- (the new model is loaded) answers from a ready frame
local transformDone=0
for round=1,60 do
  local ready=rnd(60)
  local tick=0
  local hooks={[0x84113430]=yes,[0x84111E50]=stub,[0x84111D64]=stub,[0x84111DB4]=stub,[0x84111E80]=stub,
    [0x84112564]=stub,[0x8003EC34]=stub,[0x8006456C]=stub,[0x84112FD0]=stub,[0x800231A0]=stub,
    [0x84108728]=stub,[0x841126C8]=stub,[0x84112EDC]=stub,
    [0x800427B8]=function(v) v.r[2]=tick>=ready and 1 or 0 end,
    [0x8411FEE8]=function(v) v:write(REC+6,v.r[4]%65536,2) end}
  local vm,cam,seed=setup(hooks)
  loadRecords(vm,cam)
  vm:call(0x84111248,{});vm:call(0x841112C8,{});cam:clearProgram();cam:clearProgram1()
  local actor=rnd(2)==0 and A0 or A1
  for _,m in ipairs({vm,cam.mem}) do m:write(actor+0x7EC,0,2);m:write(actor+0x618,0x90,1) end
  vm:call(0x8411B070,{actor});cam:transformState(actor)
  compare(vm,cam,seed,("transform setup round %d"):format(round))
  for off=0x616,0x661 do
    if vm:byte(actor+off)~=cam.mem:u8(actor+off) then error(("FAIL transform round %d row copy byte +%X"):format(round,off),0) end
  end
  if vm:read(REC+6,2)~=cam.mem:u16(REC+6) or vm:read(actor+0x7E8,2)~=cam.mem:u16(actor+0x7E8) then error(("FAIL transform round %d timer / frame"):format(round),0) end
  local substate=1
  for frame=1,220 do
    tick=frame
    for _,m in ipairs({vm,cam.mem}) do m:write(actor+0x7E8,((m==vm and vm:read(actor+0x7E8,2) or cam.mem:u16(actor+0x7E8))+1)%65536,2) end
    vm:call(0x8411B1F4,{actor});substate=cam:transformFrame(actor,substate,tick>=ready)
    if vm:byte(actor+0x7F6)~=substate then error(("FAIL transform round %d frame %d substate ROM %d Lua %d"):format(round,frame,vm:byte(actor+0x7F6),substate),0) end
    vm:call(0x84111774,{GC0,GC1});cam:tick(GC0,GC1)
    compare(vm,cam,seed,("transform round %d frame %d substate %d"):format(round,frame,substate))
    if vm:read(REC+6,2)~=cam.mem:u16(REC+6) then error(("FAIL transform round %d frame %d timer"):format(round,frame),0) end
    if substate==5 then transformDone=transformDone+1 break end
  end
  ok(cam.missing==nil,"Transform runs only ported handlers")
end
ok(transformDone>30,"Transform reached its end in "..transformDone.." of 60 rounds")

-- Dig's first turn after 84115A64: 84115B34's substates 0-3 with the
-- camera tick (program 2 included); the actor sinks 20 a frame, 8003EC34
-- answers from a ready frame
local digDone=0
for round=1,60 do
  local ready=rnd(60)
  local tick=0
  local hooks={[0x84123F60]=stub,[0x841088CC]=stub,[0x84112564]=stub,[0x800231A0]=stub,
    [0x84111E50]=stub,[0x84111D64]=stub,[0x84111E80]=stub,[0x84111DB4]=stub,[0x84124104]=stub,
    [0x84108E00]=stub,[0x841133EC]=stub,
    [0x8003EC34]=function(v) v.r[2]=tick>=ready and 1 or 0 end}
  local vm,cam,seed=setup(hooks)
  vm:call(0x84111248,{});vm:call(0x841112C8,{});cam:clearProgram();cam:clearProgram1()
  local actor=rnd(2)==0 and A0 or A1
  if rnd(4)==0 then for _,m in ipairs({vm,cam.mem}) do m:write(actor+0x1A,0x32+rnd(2),2) end end
  for _,m in ipairs({vm,cam.mem}) do m:write(actor+0x7E8,0,2);m:write(actor+0x7F6,0,1);m:write(actor+0x7F4,0,2) end
  local substate=0
  for frame=1,160 do
    tick=frame
    for _,m in ipairs({vm,cam.mem}) do
      m:write(actor+0x7E8,((m==vm and vm:read(actor+0x7E8,2) or cam.mem:u16(actor+0x7E8))+1)%65536,2)
      local y=f32((m==vm and vm:float(actor+0x28) or cam.mem:f32(actor+0x28))-20)
      if m==vm then vm:putFloat(actor+0x28,y) else cam.mem:setF32(actor+0x28,y) end
    end
    vm:call(0x84115B34,{actor})
    if substate==0 then
      if cam.mem:s16(actor+0x7E8)==0x19 then substate=1 end
    elseif substate==1 then
      cam:digHoleShot(actor);substate=2
    else
      local sunk=cam.mem:f32(actor+0x28)<=f32(f32(-cam.mem:f32(actor+0x648))*3)
      substate=cam:digHoleFrame(actor,substate,sunk,tick>=ready)
    end
    if vm:byte(actor+0x7F6)~=substate then error(("FAIL dig round %d frame %d substate ROM %d Lua %d"):format(round,frame,vm:byte(actor+0x7F6),substate),0) end
    vm:call(0x84111774,{GC0,GC1});cam:tick(GC0,GC1)
    compare(vm,cam,seed,("dig round %d frame %d substate %d"):format(round,frame,substate))
    for _,off in ipairs({0x20,0x7E8,0x7F4}) do
      if vm:read(actor+off,2)~=cam.mem:u16(actor+off) then error(("FAIL dig round %d frame %d +%X"):format(round,frame,off),0) end
    end
    if substate==3 and cam.mem:u8(actor+0x61F)==0xFF then digDone=digDone+1 break end
  end
  ok(cam.missing==nil,"Dig's first turn runs only ported handlers")
end
ok(digDone>30,"Dig's first turn reached its kind reset in "..digDone.." of 60 rounds")

-- the confusion self-hit's Dispatch_114 (row copy) and 84116AC4
local selfDone=0
for round=1,60 do
  local ready=rnd(80)
  local tick=0
  local hooks={[0x841146D4]=false,[0x84113430]=yes,[0x84112EAC]=stub,[0x841126C8]=stub,[0x84111E50]=stub,
    [0x84111D64]=stub,[0x84111E80]=stub,[0x84111DB4]=stub,[0x84112564]=stub,[0x84108728]=stub,
    [0x800231A0]=stub,[0x841133EC]=stub,
    [0x8003EC34]=function(v) v.r[2]=tick>=ready and 1 or 0 end,
    [0x8411FEE8]=function(v) v:write(REC+6,v.r[4]%65536,2) end}
  local vm,cam,seed=setup(hooks)
  loadRecords(vm,cam)
  vm:call(0x84111248,{});vm:call(0x841112C8,{});cam:clearProgram();cam:clearProgram1()
  local actor=rnd(2)==0 and A0 or A1
  for _,m in ipairs({vm,cam.mem}) do m:write(actor+0x7EC,0,2);m:write(actor+0x618,1,1) end
  vm:call(0x84116980,{actor});cam:selfHitState(actor)
  compare(vm,cam,seed,("self-hit follow round %d setup"):format(round))
  if vm:read(REC+6,2)~=cam.mem:u16(REC+6) or vm:read(actor+0x7E8,2)~=cam.mem:u16(actor+0x7E8) then error(("FAIL self-hit round %d timer / frame"):format(round),0) end
  local substate=0
  for frame=1,160 do
    tick=frame
    for _,m in ipairs({vm,cam.mem}) do m:write(actor+0x7E8,((m==vm and vm:read(actor+0x7E8,2) or cam.mem:u16(actor+0x7E8))+1)%65536,2) end
    vm:call(0x84116AC4,{actor});substate=cam:selfHitFrame(actor,substate,tick>=ready)
    if vm:byte(actor+0x7F6)~=substate then error(("FAIL self-hit round %d frame %d substate ROM %d Lua %d"):format(round,frame,vm:byte(actor+0x7F6),substate),0) end
    vm:call(0x84111774,{GC0,GC1});cam:tick(GC0,GC1)
    compare(vm,cam,seed,("self-hit follow round %d frame %d"):format(round,frame))
    if vm:read(REC+6,2)~=cam.mem:u16(REC+6) then error(("FAIL self-hit round %d frame %d timer"):format(round,frame),0) end
    if substate==1 then selfDone=selfDone+1 break end
  end
end
ok(selfDone>30,"the self-hit reached its end in "..selfDone.." of 60 rounds")

-- Beat Up's Dispatch_156 (with 84116410's row copy) and 84116808's substates
local beatDone=0
for round=1,60 do
  local ready=rnd(80)
  local tick=0
  local hooks={[0x841146D4]=false,[0x84113430]=yes,[0x841139D0]=stub,[0x800427B8]=yes,[0x841126C8]=stub,
    [0x84111C44]=stub,[0x84112EAC]=stub,[0x84112EDC]=stub,[0x84111E50]=stub,[0x84111D64]=stub,
    [0x84111E80]=stub,[0x84111DB4]=stub,[0x84112564]=stub,[0x80030420]=stub,[0x800231A0]=stub,
    [0x84108728]=stub,[0x84112158]=stub,[0x841121CC]=stub,
    [0x8003EC34]=function(v) v.r[2]=tick>=ready and 1 or 0 end,
    [0x8411FEE8]=function(v) v:write(REC+6,v.r[4]%65536,2) end}
  local vm,cam,seed=setup(hooks)
  loadRecords(vm,cam)
  vm:call(0x84111248,{});vm:call(0x841112C8,{});cam:clearProgram();cam:clearProgram1()
  local actor=rnd(2)==0 and A0 or A1
  for _,m in ipairs({vm,cam.mem}) do m:write(actor+0x7EC,0,2);m:write(actor+0x618,0xFB,1);m:write(REC+8,0xFB,1) end
  vm:call(0x84116548,{actor});cam:beatUpState(actor)
  compare(vm,cam,seed,("beat up setup round %d"):format(round))
  for off=0x616,0x661 do
    if vm:byte(actor+off)~=cam.mem:u8(actor+off) then error(("FAIL beat up round %d row copy byte +%X"):format(round,off),0) end
  end
  local substate=1
  for frame=1,200 do
    tick=frame
    for _,m in ipairs({vm,cam.mem}) do m:write(actor+0x7E8,((m==vm and vm:read(actor+0x7E8,2) or cam.mem:u16(actor+0x7E8))+1)%65536,2) end
    vm:call(0x84116808,{actor});substate=cam:beatUpFrame(actor,substate,tick>=ready)
    if vm:byte(actor+0x7F6)~=substate then error(("FAIL beat up round %d frame %d substate ROM %d Lua %d"):format(round,frame,vm:byte(actor+0x7F6),substate),0) end
    vm:call(0x84111774,{GC0,GC1});cam:tick(GC0,GC1)
    compare(vm,cam,seed,("beat up round %d frame %d substate %d"):format(round,frame,substate))
    if vm:read(REC+6,2)~=cam.mem:u16(REC+6) then error(("FAIL beat up round %d frame %d timer"):format(round,frame),0) end
    if substate==4 then beatDone=beatDone+1 break end
  end
  ok(cam.missing==nil,"Beat Up runs only ported handlers")
end
ok(beatDone>30,"Beat Up reached its end in "..beatDone.." of 60 rounds")

-- 841193E0 (weather, from its frame 2) and 8411957C (paralysis)
local weatherHooks={[0x8411FEE8]=stub,[0x84113560]=stub,[0x84103694]=stub,[0x84113D38]=stub,
  [0x84113430]=yes,[0x84112EAC]=stub,[0x84123F60]=stub}
for round=1,160 do
  local vm,cam,seed=setup(weatherHooks)
  local actor=rnd(2)==0 and A0 or A1
  local code=0x30+rnd(7)
  local busy=rnd(5)==0 and 1 or 0
  for _,m in ipairs({vm,cam.mem}) do m:write(REC+4,code,2);m:write(actor+0x7E8,2,2);m:write(actor+0x7F6,busy,1) end
  if code==0x36 then
    vm:call(0x8411957C,{actor});cam:paralysisState(actor)
  else
    vm:call(0x841193E0,{actor});cam:weatherState(actor)
  end
  compare(vm,cam,seed,("weather round %d code %X"):format(round,code))
end
ok(true,"841193E0 and 8411957C's camera parts match the ROM in 160 cases")

-- 8411ABAC (recall) on events 0x1E / 0x1F / 0x20
local recallHooks={[0x84113430]=yes,[0x841126C8]=stub,[0x80023A3C]=stub,[0x84108A10]=stub,
  [0x84112464]=stub,[0x84111D64]=stub,[0x84112324]=stub,[0x8410890C]=stub,[0x84112564]=stub}
for round=1,120 do
  local vm,cam,seed=setup(recallHooks)
  local actor=rnd(2)==0 and A0 or A1
  local code=0x1E+rnd(3)
  for _,m in ipairs({vm,cam.mem}) do m:write(REC+4,code,2);m:write(actor+0x2D4,0x85004000,4) end
  vm:call(0x8411ABAC,{actor});cam:recallState(actor)
  compare(vm,cam,seed,("8411ABAC round %d code %X"):format(round,code))
end
ok(true,"8411ABAC's camera part matches the ROM in 120 cases")

-- the send-out, frame by frame: 8411BB04, then 8411BCC8's substate 2 with
-- the actor's frame counter advancing as 84112648 does, and the camera
-- runner each frame; through the hand-over to program 26
local sendOutHooks={[0x84111C1C]=stub,[0x841126C8]=stub,[0x8411EE74]=stub,[0x84112FD0]=stub,
  [0x80023A3C]=stub,[0x8410890C]=stub,[0x84112158]=stub,[0x84112564]=stub}
local handedOver=0
for round=1,60 do
  local vm,cam,seed=setup(sendOutHooks)
  local actor=rnd(2)==0 and A0 or A1
  vm:write(actor+0x2D4,0x85004000,4)
  vm:call(0x84111248,{});cam:clearProgram()
  vm:call(0x841112C8,{});cam:clearProgram1()
  vm:call(0x8411BB04,{actor});cam:sendOutStart(actor)
  compare(vm,cam,seed,("8411BB04 round %d"):format(round))
  for _,m in ipairs({vm,cam.mem}) do m:write(actor+0x7F6,2,1);m:write(actor+0x7E8,1,2) end
  local done=false
  for frame=1,0x80 do
    for _,a in ipairs({A0,A1}) do
      for _,off in ipairs({0x24,0x2C}) do
        local v=f32(cam.mem:f32(a+off)+rf(10))
        vm:putFloat(a+off,v);cam.mem:setF32(a+off,v)
      end
    end
    if not done then
      vm:call(0x8411BCC8,{actor})
      done=cam:sendOutFrame(actor,frame)
      if done then handedOver=handedOver+1 end
    end
    vm:call(0x84111774,{GC0,GC1});cam:tick(GC0,GC1)
    compare(vm,cam,seed,("send-out round %d frame %d"):format(round,frame))
    local vs,ls=vm:read(actor+0x7F4,2),cam.mem:u16(actor+0x7F4)
    if vs~=ls then error(("FAIL send-out round %d frame %d +0x7F4 ROM %X Lua %X"):format(round,frame,vs,ls),0) end
    for _,m in ipairs({vm,cam.mem}) do m:write(actor+0x7E8,frame+1,2) end
  end
  ok(done,"the send-out handed over by frame 0x61 (round "..round..")")
  ok(cam.missing==nil,"the send-out runs only ported handlers")
end
ok(handedOver==60,"8411BB04 and 8411BCC8 match the ROM through the hand-over to program 26")

-- programs 1, 3, 5, 10, 11, 13 and 17 through the loader and the runner
local ticks=0
local PROGRAMS={1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,17,24,26,27,29}
local orbitEnded=0
for round=1,800 do
  local vm,cam,seed=setup()
  local owner=rnd(2)==0 and A0 or A1
  local program=PROGRAMS[round%20+1]
  vm:call(0x84111348,{owner,program});cam:setProgram(owner,program)
  vm:call(0x841112C8,{});cam:clearProgram1()
  for tick=1,program==10 and 60 or 8 do
    for _,a in ipairs({A0,A1}) do
      for _,off in ipairs({0x24,0x2C}) do
        local v=f32(cam.mem:f32(a+off)+rf(30))
        vm:putFloat(a+off,v);cam.mem:setF32(a+off,v)
      end
    end
    if rnd(5)==0 then
      local amount=f32(math.random()*25)
      vm.f[12]=VM.floatWord(amount);vm:call(0x8410B578,{});cam:setJolt(amount)
    end
    vm:call(0x84111774,{GC0,GC1});cam:tick(GC0,GC1)
    compare(vm,cam,seed,("program %d round %d tick %d code %X"):format(program,round,tick,cam.mem:u16(REC+4)))
    if (vm.timer or 0)~=cam.timers() then error(("FAIL program %d round %d: event timer ROM %d Lua %d"):format(program,round,vm.timer or 0,cam.timers()),0) end
    ticks=ticks+1
  end
  if program==10 and cam.timers()>0 then orbitEnded=orbitEnded+1 end
  ok(cam.missing==nil,("program %d runs only ported handlers"):format(program))
end
ok(orbitEnded>10,"program 10 reached its end (within 1.75) in "..orbitEnded.." of 40 rounds")
ok(ticks==8480,"programs 1-15, 17, 24, 26, 27 and 29 match the ROM over "..ticks.." runner ticks")
print(checks.." checks passed (battle camera director vs ROM)")
