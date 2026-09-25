local prefix='mods.STADIUM2_IMPORTER.lib.'
local Stream=require(prefix..'stadium2_battle_fx_four_stream')
local Random=require(prefix..'stadium2_battle_fx_random')
local VM=require(prefix..'stadium2_battle_fx_mips')
local Rom=require(prefix..'stadium2_battle_fx_rom')
local file=io.open(os.getenv('STADIUM2_ROM') or 'mods/STADIUM2_IMPORTER/baseroms/stadium2.z64','rb')
if not file then assert(os.getenv('STADIUM2_REQUIRE_ROM')~='1');print('SKIP Sonic Boom ROM');return end
local rom=file:read('*a');file:close()
local catalog=assert(Rom.catalog(rom))
local function equal(a,b,label)assert(a==b,('%s native %.12g lua %.12g'):format(label,a,b))end
for _,sign in ipairs({-1,1}) do for _,scale in ipairs({.5,1.75}) do
  local nativeRng,rng=Random.new(732),Random.new(732)
  local origin={-90*sign,25,5};local allocation=0x85200000
  local vm=VM.new({{base=0x84100000,bytes=catalog.lifecycleAssets.fragment79},
    {base=0x80000400,bytes=rom:sub(0x1001,0xA8000)}},{
    [0x84156BA0]=function()end,
    [0x84109544]=function(v)v.f[0]=VM.floatWord(scale)end,
    [0x841568E0]=function(v)v:putVector(v.r[4],origin)end,
    [0x8007AFA0]=function(v)v.r[2]=nativeRng:next()end,
    [0x80006DEC]=function(v)v.r[2]=allocation;allocation=allocation+v.r[4]end})
  local pool=0x85000000;vm:write(0x84187A70,pool,4);vm:call(0x8415809C)
  local s=Stream.new(nil,scale)
  for tick=1,49 do
    origin[2]=origin[2]+.125
    equal(vm:call(0x841580C8),Stream.step(s,origin,rng),'return')
    equal(nativeRng.state,rng.state,'RNG '..tick)
    for i=1,4 do
      local slot=s.slots[i];local at=pool+(i-1)*0x430
      equal(vm:read(at,2),slot and slot.active and 1 or 0,'active')
      if slot then
        equal(vm:read(at+2,2),slot.age,'age');equal(vm:float(at+12),slot.scale,'scale')
        for j,n in ipairs(slot.nodes) do
          local node=at+0x34+(j-1)*0x44
          equal(vm:read(node,1),n.alpha,'alpha');equal(vm:float(node+4),n.radius,'radius')
          equal(vm:float(node+8),n.angle,'angle')
          for k=1,3 do
            equal(vm:float(node+12+(k-1)*4),n.position[k],'position '..tick..'/'..i..'/'..j..'/'..k)
            equal(vm:float(node+24+(k-1)*4),n.velocity[k],'velocity '..tick..'/'..i..'/'..j..'/'..k)
          end
        end
      end
    end
    if tick>=2 and (tick<5 or tick%10==0) then
      allocation=0x85200000;local endDL=vm:call(0x84164280,{0x85400000},1000000)
      local geometry=Stream.geometry(s,catalog.lifecycleAssets.sonicBoom)
      local matrices={}
      for at=0x85400000,endDL%2^32-8,8 do if vm:read(at,4)==0xDA380000 then matrices[#matrices+1]=vm:read(at+4,4)end end
      local nextMatrix=1
      for i,slot in ipairs(s.slots) do if slot.active then
        local verts=vm:read(pool+(i-1)*0x430+0x18,4)
        local layer=geometry.layers[i*2]
        for j=0,29 do for k=0,2 do
          local n=vm:read(verts+j*16+k*2,2);if n>=32768 then n=n-65536 end
          equal(n,layer.pos[j*3+k+1],'draw position '..tick..'/'..i..'/'..j..'/'..k)
        end
        for k=0,3 do equal(vm:read(verts+j*16+12+k,1),layer.color[j*4+k+1],'draw color')end end
        if slot.nodes[1].position[2]>0 then
          local matrix={};local at=assert(matrices[nextMatrix]);nextMatrix=nextMatrix+1
          for j=0,15 do local high=vm:read(at+j*2,2);if high>=32768 then high=high-65536 end
            matrix[j+1]=high+vm:read(at+32+j*2,2)/65536
          end
          local asset=catalog.lifecycleAssets.sonicBoom
          for j=0,3 do for k=1,3 do
            local expected=matrix[12+k]
            for axis=0,2 do expected=expected+asset.pos[j*3+axis+1]*matrix[axis*4+k]end
            assert(math.abs(expected-geometry.layers[i*2-1].pos[j*3+k])<.02,'native Sonic Boom head matrix')
          end end
        end
      end end
    end
  end
  assert(#s.slots==3,'exactly three emissions')
  equal(vm:call(0x841580C8)%2^32,Stream.step(s,origin,rng)%2^32,'expiry')
end end
print('Sonic Boom ROM: three emissions, all 15 history nodes, RNG, motion, strip vertices/colors and expiry passed')
