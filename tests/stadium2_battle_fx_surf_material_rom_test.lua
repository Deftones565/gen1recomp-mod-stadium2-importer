local prefix='mods.STADIUM2_IMPORTER.lib.'
local Rom=require(prefix..'stadium2_battle_fx_rom')
local Motion=require(prefix..'stadium2_battle_fx_motion')
local Material=require(prefix..'stadium2_battle_fx_material')
local VM=require(prefix..'stadium2_battle_fx_mips')
local f=io.open(os.getenv('STADIUM2_ROM') or 'mods/STADIUM2_IMPORTER/baseroms/stadium2.z64','rb')
if not f then assert(os.getenv('STADIUM2_REQUIRE_ROM')~='1');print('SKIP Surf material ROM');return end
local rom=f:read('*a');f:close()
local catalog=assert(Rom.catalog(rom))
local count=0
for _,record in ipairs(catalog.programs[330].records) do
  local e=record.emitter
  if e then
    count=count+1
    local m=e.material
    assert(m.nativeEndAge==16)
    for _,hide in ipairs({false,true}) do
      local flags=hide and 2 or 0
      local vm=VM.new({{base=0x84100000,bytes=catalog.lifecycleAssets.fragment79},
        {base=0x81100000,bytes=rom:sub(0x165C50+1,0x165F00)}})
      local p,d,t=0x85000000,0x85001000,0x85002000
      -- Exercise the real material constructor and common update with
      -- geometry/movement disabled; their independent controllers do not
      -- change the material+4 age comparison or constant-color branch.
      vm:write(d+4,flags,4);vm:write(d+16,t,4);vm:write(d+20,m.address,4)
      vm:write(p+16,d,4);vm:write(p+0x14,1,4)
      vm:write(p+0x92,1,1);vm:write(p+0x87,255,1)
      vm:call(0x84106F34,{p,d})
      local motion=Motion.init({material=m,event={flags=flags}})
      local material=Material.init(m,{flags=flags})
      for _,diag in ipairs(material.diagnostics) do
        assert(diag.code~='unsupported-color-controller')
      end
      for tick=1,16 do
        vm:write(p+0x7F,tick,1)
        vm:call(0x84101D54,{p})
        motion=Motion.step(motion,1)
        material=Material.step(material,{age=tick})
        assert(motion.alive==(vm:read(p+0x92,1)~=0),'native material termination')
        assert((motion.nativeHidden==true)==(math.floor(vm:read(p+0x14,4)/0x80)%2==1),
          'native hide flag without particle termination')
        assert(material.nativeAlpha==vm:read(p+0x87,1),'native alpha ramp')
        for _,entry in ipairs({{'primaryColor',0x84},{'secondaryColor',0x8B}}) do
          local rgba=material[entry[1]]
          if rgba then for k=1,3 do
            assert(rgba[k]==vm:read(p+entry[2]+k-1,1),'constant RGB preload')
          end end
        end
      end
      assert(motion.alive==hide,'hide flag must not become a lifetime')
    end
  end
end
assert(count==4)
print('Surf material ROM: all four emitters, constant RGB, alpha, 16-tick expiry and hide distinction passed')
