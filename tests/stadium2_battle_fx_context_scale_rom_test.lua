local prefix='mods.STADIUM2_IMPORTER.lib.'
local Dispatch=require(prefix..'animation_dispatch')
local Rom=require(prefix..'stadium2_battle_fx_rom')
local VM=require(prefix..'stadium2_battle_fx_mips')
local Motion=require(prefix..'stadium2_battle_fx_motion')
local Adapter=require(prefix..'stadium2_battle_fx_battle_adapter')
local single=require(prefix..'stadium2_battle_fx_float')
local f=io.open(os.getenv('STADIUM2_ROM') or 'mods/STADIUM2_IMPORTER/baseroms/stadium2.z64','rb')
if not f then assert(os.getenv('STADIUM2_REQUIRE_ROM')~='1');print('SKIP context scale ROM');return end
local rom=f:read('*a');f:close()
local catalog=assert(Rom.catalog(rom))
local vm=VM.new({{base=0x84100000,bytes=catalog.lifecycleAssets.fragment79}})
local actor,tableAddress,dispatchAddress=0x85000000,0x85001000,0x85002000
vm:write(actor+0x67C,tableAddress,4);vm:write(actor+0x2D4,dispatchAddress,4)
local cases=0
for _,species in ipairs({1,25,109,159,251}) do
  local bytes=assert(Dispatch.contextScaleBytes(rom,species))
  local rows=assert(Dispatch.forSpecies(rom,species));local raw={}
  for i=0,rows.n-1 do raw[#raw+1]=rows[i].raw end
  local dispatch=table.concat(raw)
  for i=1,#bytes do vm:write(tableAddress+i-1,bytes:byte(i),1) end
  for i=1,#dispatch do vm:write(dispatchAddress+i-1,dispatch:byte(i),1) end
  for id=0,300 do
    local expected=single(vm:call(0x8411E358,{actor,id})*single(.01))
    assert(Dispatch.contextScale(id,bytes,dispatch)==expected,('species %d context %d'):format(species,id))
    cases=cases+1
  end
  assert(Dispatch.contextScale(65535,bytes,dispatch)==0)
end
assert(Dispatch.contextScale(252,nil,nil)==nil,'missing table is not unit scale')
assert(Dispatch.contextScale(255,nil,nil)==nil,'missing dispatch is unresolved')
assert(Dispatch.contextScale(251,nil,nil)==0,'out-of-range lookup returns native zero')
local bytes=string.char(0,0,0,37)..string.rep('\0',76)
local scene={scene={host={visualActor=function()return {renderer={model={fxContextScales=bytes}}}end}}}
local p={event={mode=1,flags=8,context={moveId=7,nativeContextId=252}},
  scale={nativeScaleUpdate={initial=1000,target=2000,step=100,startAge=1}},
  nativeMotion={direction={mode=4,speed={startAge=1,initial=100,target=100,step=0}}}}
local options={resolveNativeContextScale=function(row)return Adapter.placementContext(row,scene).nativeContextScale end}
local state=Motion.init(p,options)
local scale=single(37*single(.01))
assert(state.scale[1]==scale and #state.diagnostics==0)
state=Motion.step(state,1,options)
assert(state.scale[1]==single(state.nativeScalar*scale) and state.nativeMotionOffset[2]==scale)
p.event.context.nativeContextId=nil
assert(Motion.init(p,options).scale[1]==0,'move ID is not replaced by program ID')
p.event.flags=0x88
assert(Motion.init(p,options).scale[1]==1,'fixed constructor scale wins over special lookup')
print(('Context scale ROM: %d species/context cases, missing data, viewer lookup and size/motion integration passed'):format(cases))
