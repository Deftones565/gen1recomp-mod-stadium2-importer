local prefix='mods.STADIUM2_IMPORTER.lib.'
local Rom=require(prefix..'stadium2_battle_fx_rom')
local Motion=require(prefix..'stadium2_battle_fx_motion')
local VM=require(prefix..'stadium2_battle_fx_mips')
local single=require(prefix..'stadium2_battle_fx_float')
local f=io.open(os.getenv('STADIUM2_ROM') or 'mods/STADIUM2_IMPORTER/baseroms/stadium2.z64','rb')
if not f then assert(os.getenv('STADIUM2_REQUIRE_ROM')~='1');print('SKIP scaling ROM');return end
local rom=f:read('*a');f:close()
local catalog=assert(Rom.catalog(rom))
local vm=VM.new({{base=0x84100000,bytes=catalog.lifecycleAssets.fragment79},
  {base=0x80000400,bytes=rom:sub(0x1001,0xA8000)},
  {base=0x81100074,bytes=rom:sub(0x165CC5,0x165E5C)}})
local particle,source,descriptor=0x85000000,0x85001000,0x85002000
vm:write(0x84190194,source,4)
vm:write(particle+8,source,4)
vm:write(particle+0x10,descriptor,4)
local function bits(value)
  vm:putFloat(0x85003000,value);return vm:read(0x85003000,4)
end
local count=0
for _,scaleByte in ipairs({0,37,100,175,255}) do
  local factor=single(scaleByte*single(.01))
  vm:write(source+0x661,scaleByte,1)
  for _,flags in ipairs({0,1,0x40,0x80,0x100,0x180}) do
    for _,yaw in ipairs({0,0x4000,0x9234,65519}) do
      local options={trigTables={
        tableA=function(i)return catalog.trigTables.tableA[i] end,
        tableB=function(i)return catalog.trigTables.tableB[i] end}}
      local p={event={mode=1,flags=flags},nativeGeometry=true,
        nativeSpawnScale=factor,nativeSourceYaw=yaw,position={13,-7,29},
        scale={nativeScaleUpdate={initial=731,target=950,step=17,startAge=3}},
        transform={directionalVelocity={mode=0,values={2,3,4}}},
        nativeMotion={direction={mode=4,speed={startAge=1,initial=173,target=173,step=0}}}}
      options.randomScalar=function(_,bound)return bound end
      local state=Motion.init(p,options)
      local spawnFactor=math.floor(flags/0x80)%2==1 and 1 or factor
      assert(state.scale[1]==single(single(731*single(.001))*spawnFactor))
      vm:write(source+0x20,yaw,2)
      vm:putVector(particle+0x2C,{0,0,0})
      local function addOffset(v)
        vm:putFloat(0x857FF010,spawnFactor)
        vm:call(0x84105F10,{particle+0x2C,bits(v[1]),bits(v[2]),bits(v[3])})
      end
      if flags%2==0 then addOffset(p.position) end
      addOffset({2,3,4})
      local expected=vm:vector(particle+0x2C)
      for axis=1,3 do assert(state.position[axis]==expected[axis],'spawn offset') end
      vm:write(descriptor+4,flags,4)
      vm:write(particle+0x14,math.floor(flags/0x100)%2==1 and 0x400 or 0,4)
      vm:putVector(particle+0x44,{0,0,0})
      vm:putFloat(particle+0x5C,single(173*single(.01)))
      for tick=1,4 do
        state=Motion.step(state,1,options)
        vm:putFloat(particle+0x1C,state.nativeScalar)
        vm:call(0x84101AF4,{particle,descriptor})
        assert(state.scale[1]==vm:float(particle+0x18),'live scalar flags')
        vm:call(0x841013F4,{particle,4})
        assert(state.nativeMotionOffset[2]==vm:float(particle+0x48),'live movement scale')
      end
      assert(#state.diagnostics==0)
      count=count+1
    end
  end
end
local missing=Motion.init({event={mode=1,flags=8},nativeSpawnScale=.5})
assert(missing.diagnostics[1].detail=='nativeContextScale')
local special=Motion.init({event={mode=1,flags=8},nativeContextScale=.25,scale=2})
assert(special.scale[1]==.5 and #special.diagnostics==0)
local live=.5
local options={resolveNativeSpawnScale=function()return live end}
local state=Motion.init({event={mode=1,flags=0},
  scale={nativeScaleUpdate={initial=1000,target=2000,step=100,startAge=1}}},options)
assert(state.scale[1]==.5)
live=1.75
state=Motion.step(state,1,options)
assert(state.scale[1]==single(state.nativeScalar*live))
state=Motion.step(state,1,options)
assert(state.scale[1]==single(state.nativeScalar*live),'no compounded scale')
print(('Native scaling ROM: %d scale/flag/yaw combinations, spawn offsets, animated size and movement passed'):format(count))
