package.path="./?.lua;./?/init.lua;"..package.path
-- Battler behaviour kinds (84114804 / actor +0x61F) against the ROM: each
-- kind's start (84123F60's case) and update (84124104's case) run in the
-- MIPS VM on an actor with scale 1.0, compared with lib/battle_special_moves
-- tick by tick. Meditate has its own test (stadium2_meditate_rom_test.lua).
local file=io.open(os.getenv("STADIUM2_ROM") or "mods/STADIUM2_IMPORTER/baseroms/stadium2.z64","rb")
if not file then assert(os.getenv("STADIUM2_REQUIRE_ROM")~="1","ROM required");print("SKIP behaviour kinds ROM");return end
local rom=file:read("*a");file:close()
local VM=require("mods.STADIUM2_IMPORTER.tests.support.stadium2_battle_fx_mips")
local FxRom=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_rom")
local Special=require("mods.STADIUM2_IMPORTER.lib.battle_special_moves")
local checks=0
local function ok(v,m) checks=checks+1 if not v then error("FAIL "..m,0) end end

local catalog=assert(FxRom.catalog(rom))
local fragment=catalog.lifecycleAssets.fragment79
local A=0x85001000
local function vm()
  local v=VM.new({{base=0x80000400,bytes=rom:sub(0x1001,0xA8000)},{base=0x84100000,bytes=fragment}},{})
  for i=0,2 do v:putFloat(A+0x30+i*4,1.0) end
  return v
end

-- Compare the scale vector over `ticks` ticks.
local function scaleKind(name,kind,start,update,ticks)
  local v=vm()
  local state=assert(Special.new({kind=kind,trig=catalog.trigTables}))
  v:call(start,{A})
  for tick=1,ticks do
    v:call(update,{A})
    Special.step(state)
    for axis=1,3 do
      local romValue=v:float(A+0x2C+axis*4)
      if romValue~=state.axisScale[axis] then
        error(("FAIL %s tick %d axis %d scale ROM %.9g Lua %.9g"):format(name,tick,axis,romValue,state.axisScale[axis]),0)
      end
    end
  end
  ok(true,name.." matches the ROM over "..ticks.." ticks")
  return state
end

-- Withdraw (kind 12): 84123914 / 8412391C
local withdraw=scaleKind("Withdraw",Special.WITHDRAW,0x84123914,0x8412391C,40)
ok(withdraw.axisScale[2]==Special.WITHDRAW_FLOOR,"Withdraw ends drawn in (0.001)")
ok(Special.kindFor(110,7)==nil and Special.kindFor(110,25)==Special.WITHDRAW,
  "Squirtle's line keeps its shape (D_841839EC); others withdraw")

-- Belly Drum (kind 26): 84122C94 / 84122CCC
local drum=scaleKind("Belly Drum",Special.BELLY_DRUM,0x84122C94,0x84122CCC,60)
ok(drum.axisScale[1]==1 and drum.axisScale[2]==1,"Belly Drum settles back to the base scale")

-- Compare the position (+0x24..+0x2C) against the port's offset; the
-- actor faces `yaw` (+0x20) and stands at origin height 0 (+0x650).
local function positionKind(name,kind,start,update,ticks,yaw)
  local v=vm()
  v:write(A+0x20,yaw%0x10000,2)
  for i=0,2 do v:putFloat(A+0x24+i*4,0) end
  v:putFloat(A+0x650,0)
  local state=assert(Special.new({kind=kind,yaw=yaw,trig=catalog.trigTables}))
  v:call(start,{A})
  local top=0
  for tick=1,ticks do
    v:call(update,{A})
    Special.step(state)
    for axis=1,3 do
      local romValue=v:float(A+0x20+axis*4)
      if romValue~=state.offset[axis] then
        error(("FAIL %s tick %d axis %d position ROM %.9g Lua %.9g"):format(name,tick,axis,romValue,state.offset[axis]),0)
      end
    end
    top=math.max(top,state.offset[2])
  end
  ok(true,name.." matches the ROM over "..ticks.." ticks")
  return state,top
end

-- Waterfall (kind 14): 84122D74 / 84122DD8, the player's facing
local _,top=positionKind("Waterfall",Special.WATERFALL,0x84122D74,0x84122DD8,120,Special.facing("player"))
ok(top==Special.WATERFALL_TOP,"Waterfall rises to 90 above its origin and holds there")

-- Fly's rise (kind 3): 841210CC / 84121130
_,top=positionKind("Fly's rise",Special.FLY,0x841210CC,0x84121130,120,Special.facing("player"))
ok(top==Special.FLY_TOP,"Fly rises to 200 above its origin and holds there")

-- Dig (kind 5): 841217C8 / 841217E4, both battlers, a real profile (origin
-- height and centre): the facing and the absolute height
local function digKind(first,ground,center,ticks)
  local v=vm()
  local yaw=first and 0x4000 or -0x4000
  v:write(A+0x20,yaw%0x10000,2)
  v:write(0x84191208,first and A or A+0x2000,4)
  v:putFloat(A+0x24,0);v:putFloat(A+0x28,ground);v:putFloat(A+0x2C,0)
  v:putFloat(A+0x650,ground);v:putFloat(A+0x648,center)
  local state=assert(Special.new({kind=Special.DIG,yaw=yaw,trig=catalog.trigTables,groundY=ground,centerY=center}))
  v:call(0x841217C8,{A})
  local sunkAt
  for tick=1,ticks do
    v:call(0x841217E4,{A})
    Special.step(state)
    local romYaw=v:read(A+0x20,2)
    if romYaw>=0x8000 then romYaw=romYaw-0x10000 end
    local romY,luaY=v:float(A+0x28),ground+state.offset[2]
    if romYaw~=state.nativeYaw or romY~=luaY then
      error(("FAIL Dig tick %d yaw ROM %d Lua %d, Y ROM %.9g Lua %.9g"):format(tick,romYaw,state.nativeYaw,romY,luaY),0)
    end
    if not sunkAt and romY<=-center*3.0 then sunkAt=tick end
    if (romY<=-center*3.0)~=Special.digSunk(state) then error(("FAIL Dig tick %d sunk test"):format(tick),0) end
  end
  ok(sunkAt~=nil,("Dig (%s) matches the ROM and sinks below -3 x centre by tick %d"):format(first and "player" or "foe",sunkAt or -1))
end
digKind(true,0,24,200)
digKind(false,65,30.5,240)

-- Destiny Bond (kind 24): 84123E74 / 84123EB0
local bond=scaleKind("Destiny Bond",Special.DESTINY_BOND,0x84123E74,0x84123EB0,140)
ok(bond.axisScale[2]>1.5 and bond.axisScale[1]<0.5,"Destiny Bond stretches tall and thin")

-- Stomp / Body Slam's defender (kind 15): 84123828 / 84123858
local squash=scaleKind("Squash (Stomp, Body Slam)",Special.SQUASHED,0x84123828,0x84123858,40)
ok(Special.DEFENDER_KINDS[23]==15 and Special.DEFENDER_KINDS[34]==15,"Stomp and Body Slam squash their target")

-- Compare the facing (+0x20) against the port's nativeYaw; `first` makes
-- the actor the first battler (D_84191208), facing +0x4000, else -0x4000.
local function yawKind(name,kind,start,update,ticks,first)
  local v=vm()
  local yaw=first and 0x4000 or -0x4000
  v:write(A+0x20,yaw%0x10000,2)
  v:write(0x84191208,first and A or A+0x2000,4)
  local state=assert(Special.new({kind=kind,yaw=yaw,trig=catalog.trigTables}))
  v:call(start,{A})
  for tick=1,ticks do
    v:call(update,{A})
    Special.step(state)
    local romYaw=v:read(A+0x20,2)
    if romYaw>=0x8000 then romYaw=romYaw-0x10000 end
    if romYaw~=state.nativeYaw then
      error(("FAIL %s tick %d yaw ROM %d Lua %d"):format(name,tick,romYaw,state.nativeYaw),0)
    end
  end
  ok(true,name.." matches the ROM over "..ticks.." ticks")
  return state
end

-- Submission (kind 4): 84121260 / 841212A0, both sides
local spun=yawKind("Submission (player)",Special.SUBMISSION,0x84121260,0x841212A0,150,true)
ok(spun.spin.landed and spun.nativeYaw==0x4000,"Submission spins and lands facing forward")
yawKind("Submission (foe)",Special.SUBMISSION,0x84121260,0x841212A0,150,false)

-- Rapid Spin (kind 19): 8412142C / 841214C0: facing, Y scale and height
local function rapidSpin(first)
  local v=vm()
  local yaw=first and 0x4000 or -0x4000
  v:write(A+0x20,yaw%0x10000,2)
  v:write(0x84191208,first and A or A+0x2000,4)
  for i=0,2 do v:putFloat(A+0x24+i*4,0) end
  v:putFloat(A+0x650,0)
  local state=assert(Special.new({kind=Special.RAPID_SPIN,yaw=yaw,trig=catalog.trigTables}))
  v:call(0x8412142C,{A})
  local rose=0
  for tick=1,200 do
    v:call(0x841214C0,{A})
    Special.step(state)
    local romYaw=v:read(A+0x20,2); if romYaw>=0x8000 then romYaw=romYaw-0x10000 end
    local romY,romScale=v:float(A+0x28),v:float(A+0x34)
    if romYaw~=state.nativeYaw or romScale~=state.axisScale[2] or romY~=state.offset[2] then
      error(("FAIL Rapid Spin tick %d yaw %d/%d scaleY %.9g/%.9g y %.9g/%.9g"):format(tick,
        romYaw,state.nativeYaw,romScale,state.axisScale[2],romY,state.offset[2]),0)
    end
    rose=math.max(rose,state.offset[2])
  end
  ok(true,"Rapid Spin ("..(first and "player" or "foe")..") matches the ROM over 200 ticks")
  return state,rose
end
local rs,rose=rapidSpin(true)
ok(rs.spin.landed and rose>0,"Rapid Spin hops while it spins and lands facing forward")
rapidSpin(false)

-- Faint Attack (kind 25): 8412230C / 84122448. The copies' pose calls
-- (8003EB84, 8003F2C4) are stubbed; the copies' alpha / offset and the
-- battler's alpha are compared.
local function faintAttack(first)
  local noop=function() end
  local v=VM.new({{base=0x80000400,bytes=rom:sub(0x1001,0xA8000)},{base=0x84100000,bytes=fragment}},
    {[0x8003EB84]=noop,[0x8003F2C4]=noop})
  for i=0,2 do v:putFloat(A+0x30+i*4,1.0) end
  local yaw=first and 0x4000 or -0x4000
  v:write(A+0x20,yaw%0x10000,2)
  for i=0,2 do v:putFloat(A+0x24+i*4,0) end
  v:putFloat(A+0x64C,60)
  local state=assert(Special.new({kind=Special.FAINT_ATTACK,yaw=yaw,trig=catalog.trigTables,bodyHeight=60}))
  v:call(0x8412230C,{A})
  for tick=1,90 do
    v:call(0x84122448,{A})
    Special.step(state)
    for i=1,2 do
      local slot=A+(i-1)*0x170
      local image=state.afterimages[i]
      local romAlpha=v:byte(slot+0x2F5)
      local rx,ry,rz=v:float(slot+0x2FC),v:float(slot+0x300),v:float(slot+0x304)
      if romAlpha~=image.alpha or rx~=image.offset[1] or ry~=image.offset[2] or rz~=image.offset[3] then
        error(("FAIL Faint Attack tick %d copy %d alpha %d/%d pos %.9g,%.9g,%.9g / %.9g,%.9g,%.9g"):format(
          tick,i,romAlpha,image.alpha,rx,ry,rz,image.offset[1],image.offset[2],image.offset[3]),0)
      end
    end
    local romMain=v:byte(A+0x1D)
    if romMain~=state.alpha then error(("FAIL Faint Attack tick %d battler alpha %d/%d"):format(tick,romMain,state.alpha),0) end
  end
  ok(true,"Faint Attack ("..(first and "player" or "foe")..") matches the ROM over 90 ticks")
  return state
end
local fa=faintAttack(true)
ok(fa.alpha==0x80 and fa.afterimages[1].alpha==0x80,"Faint Attack fades the battler to half beside two half copies")
faintAttack(false)

-- Seismic Toss (kind 8): 84121AB8 / 84121B18 roll the camera (controller 0's
-- GeoCamera up vector); the camera port's Native:seismicStart / Update
do
  local Native=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_camera_native")
  local n=assert(Native.load(rom,fragment,{}))
  local m=n.mem
  local v=vm()
  local C,G=0x85002000,0x85003000
  local eye,focus={-300,120,400},{40,30,-20}
  local function setup(write32,writeF)
    write32(Native.CONTROLLER0,C); write32(C,G)
    for i=0,2 do writeF(G+0xA8+i*4,eye[i+1]); writeF(G+0xB4+i*4,focus[i+1]) end
    writeF(A+0x28,0)
  end
  setup(function(a,x) v:write(a,x,4) end,function(a,x) v:putFloat(a,x) end)
  setup(function(a,x) m:setU32(a,x) end,function(a,x) m:setF32(a,x) end)
  v:call(0x84121AB8,{A}); n:seismicStart(A)
  for tick=1,60 do
    v:call(0x84121B18,{A}); n:seismicUpdate(A)
    for i=0,2 do
      local romUp,luaUp=v:float(G+0xC0+i*4),m:f32(G+0xC0+i*4)
      if romUp~=luaUp then error(("FAIL Seismic Toss tick %d up[%d] ROM %.9g Lua %.9g"):format(tick,i,romUp,luaUp),0) end
    end
    if v:read(A+0x600,2)~=m:u16(A+0x600) or v:read(A+0x5FC,2)~=m:u16(A+0x5FC) then
      error(("FAIL Seismic Toss tick %d roll"):format(tick),0)
    end
  end
  ok(true,"Seismic Toss's camera roll matches the ROM over 60 ticks")
  ok(m:u16(A+0x600)==0x8000 and m:f32(G+0xC4)<0,"the camera rolls upside down")
end

-- Surf's tilt: the scene's battler matrix (arena) against 8003614C, the
-- display object's matrix (rotation +0x1E, ROM execution), same angles
do
  local Scene=require("mods.STADIUM2_IMPORTER.lib.battle_scene")
  local Layout=require("mods.STADIUM2_IMPORTER.lib.stadium_battle_layout")
  local host={arenaMode=true,arenaScale=1,arenaGroundY=0,
    picElevation=function() return 0 end,picScale=function() return 1 end}
  for _,tilt in ipairs({0x0B60,-0x1A0C}) do
    local actor={dex=25,nativeTilt=tilt,scale=function() return 1 end,
      renderer={worldMetrics=function() return {floor=0,height=1} end}}
    local matrix,yaw,pitch=Scene.modelMatrix(host,"player",actor)
    local _,slotYaw=Layout.slot("player",25)
    local binaryYaw=math.floor(slotYaw*0x8000/math.pi+.5)
    local v=VM.new({{base=0x80000400,bytes=rom:sub(0x1001,0xA8000)}})
    local M,P,R=0x85001000,0x85001100,0x85001200
    for i=0,2 do v:putFloat(P+i*4,0) end
    v:write(R,tilt%65536,2);v:write(R+2,binaryYaw%65536,2);v:write(R+4,0,2)
    v:call(0x8003614C,{M,P,R})
    -- ROM row-vector matrix row i = the scene's column i
    local worst=0
    for i=0,2 do for j=0,2 do
      worst=math.max(worst,math.abs(v:float(M+i*16+j*4)-matrix[j*4+i+1]))
    end end
    ok(worst<2e-3,("the battler's tilt %d matches 8003614C (worst %.2g)"):format(tilt,worst))
    ok(math.abs(pitch-tilt*math.pi/0x8000)<1e-9,"the tilt reaches the battler's lighting")
  end
end

-- Surf (kind 10, 84122A0C): the battler at the water height of the running
-- terrain grid under its slot X (84159FA8 is ROM-tested on its own)
do
  local asked
  local surf=assert(Special.new({kind=Special.SURF,trig=catalog.trigTables,slotX=-150,
    terrainHeightAt=function(x,z) asked={x,z} return 37.5,-12.7 end}))
  Special.step(surf)
  ok(asked[1]==-150 and asked[2]==0 and surf.offset[2]==37.5,"Surf rides the water height under its slot")
  ok(surf.surfTilt==-12*182,"the slope is kept (truncated toward zero, x 182)")
  local dry=assert(Special.new({kind=Special.SURF,trig=catalog.trigTables,slotX=150}))
  Special.step(dry)
  ok(dry.offset[2]==0,"without a running grid the battler stays put")
end

print(checks.." checks passed (behaviour kinds vs ROM)")
