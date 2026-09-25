local prefix='mods.STADIUM2_IMPORTER.lib.'
local Rom=require(prefix..'stadium2_battle_fx_rom')
local Motion=require(prefix..'stadium2_battle_fx_motion')
local VM=require(prefix..'stadium2_battle_fx_mips')
local single=require(prefix..'stadium2_battle_fx_float')
local f=io.open(os.getenv('STADIUM2_ROM') or 'mods/STADIUM2_IMPORTER/baseroms/stadium2.z64','rb')
if not f then assert(os.getenv('STADIUM2_REQUIRE_ROM')~='1');print('SKIP direction ROM');return end
local rom=f:read('*a');f:close()
local catalog=assert(Rom.catalog(rom))
local vm=VM.new({{base=0x84100000,bytes=catalog.lifecycleAssets.fragment79},
  {base=0x80000400,bytes=rom:sub(0x1001,0xA8000)},
  {base=0x811001A0,bytes=rom:sub(0x165DF0+1,0x165E5C)}},
  {[0x84100074]=function(v)v.r[2]=0 end}) -- model-scale flag disabled
local particle,source=0x85000000,0x85001000
vm:write(0x84190194,source,4)
for mode=0,8 do
  for _,yaw in ipairs({0,0x4000,0x8000,0xC000,0x1234,-17}) do
    local angles={0x2345,-yaw,0x3456}
    local state=Motion.init({nativeSourceYaw=yaw,rotation=angles,lifetime=100,
      nativeMotion={direction={mode=mode,speed={startAge=1,initial=173,target=173,step=0}}}})
    vm:putVector(particle+0x44,{0,0,0})
    vm:putFloat(particle+0x5C,single(173*single(.01)))
    vm:write(source+0x20,yaw,2)
    for k=1,3 do vm:write(particle+0x6A+(k-1)*2,angles[k],2) end
    for tick=1,3 do
      vm:call(0x841013F4,{particle,mode})
      state=Motion.step(state,1,{trigTables=catalog.trigTables})
      local expected=vm:vector(particle+0x44)
      for k=1,3 do assert(state.nativeMotionOffset[k]==expected[k],
        ('mode %d yaw %d tick %d axis %d'):format(mode,yaw,tick,k)) end
      assert(#state.diagnostics==0)
    end
  end
end
local Adapter=require(prefix..'stadium2_battle_fx_battle_adapter')
local scene={world={actorSlots={player={x=-3,y=0,z=0},enemy={x=3,y=0,z=0}}}}
local p={event={context={sourceSide='player'}}}
assert(Adapter.placementContext(p,scene).nativeSourceYaw==0x4000)
p.event.context.sourceSide='enemy'
assert(Adapter.placementContext(p,scene).nativeSourceYaw==0xC000)
local yaw=.37
scene.scene={host={visualActor=function()return {}end,modelMatrix=function()
  return {math.cos(yaw),0,math.sin(yaw),0,0,1,0,0,-math.sin(yaw),0,math.cos(yaw),0,0,0,0,1}
end}}
assert(Adapter.placementContext(p,scene).nativeSourceYaw==math.floor(yaw*65536/(2*math.pi)))
print('Native direction ROM: all nine modes, yaw wrap, accumulation and live actor facing passed')
