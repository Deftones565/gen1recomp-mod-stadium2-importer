local prefix='mods.STADIUM2_IMPORTER.lib.'
local Spike=require(prefix..'stadium2_battle_fx_spike_cannon')
local Random=require(prefix..'stadium2_battle_fx_random')
local Rom=require(prefix..'stadium2_battle_fx_rom')
local file=io.open(os.getenv('STADIUM2_ROM') or 'mods/STADIUM2_IMPORTER/baseroms/stadium2.z64','rb')
if not file then assert(os.getenv('STADIUM2_REQUIRE_ROM')~='1');print('SKIP Spike Cannon ROM');return end
local rom=file:read('*a');file:close()
local catalog=assert(Rom.catalog(rom))
local inputs={origin={-90,20,5},direction={1,0,0},swiftFrameOrigin={0,0,0}}
local rng=Random.new(432)
local state=assert(Spike.new(inputs,rng))
local asset=assert(catalog.lifecycleAssets.needle)
local geometry=assert(Spike.geometry(state,asset))
assert(geometry.kind=='rom-beam' and #geometry.layers==8)
local spawned={}
for tick=1,55 do
  assert(Spike.step(state,inputs)==0)
  local count=0
  for _,slot in ipairs(state.slots)do if slot.active then count=count+1 end end
  if tick==4 or tick==8 or tick==12 then spawned[tick]=count end
  if tick==5 then
    local first=state.slots[1]
    assert(first.age==2 and first.nodes[1].position[1]>inputs.origin[1])
    assert(first.nodes[1].radius==4 and first.nodes[1].alpha==119)
  end
  if tick==20 then
    geometry=Spike.geometry(state,asset)
    assert(#geometry.layers==8 and #geometry.layers[1].idx==#asset.idx)
    assert(#geometry.layers[2].idx==84 and geometry.layers[2].color[1]==208)
  end
end
assert(spawned[4]==1 and spawned[8]==2 and spawned[12]==3,'ROM cadence creates three native projectiles')
assert(not state.slots[1].active and not state.slots[2].active and not state.slots[3].active)
assert(Spike.snapshot(state).kind=='rom-spike-cannon-state')
print('Family 16 ROM: cadence, four-slot pool, needle model, cyan trails and expiry passed')

local Renderer=require(prefix..'renderer')
local Dispatch=require(prefix..'animation_dispatch')
local Preview=require('mods.STADIUM2_IMPORTER.tests.stadium2_koffing_croconaw_visual.battle_fx')
local rows=assert(Dispatch.forSpecies(rom,109));local raw={}
for i=0,270 do raw[#raw+1]=rows[i].raw end
local model={species=109,fxDispatch=table.concat(raw)}
local scene={world={actorSlots={player={x=-3,y=0,z=0},enemy={x=3,y=0,z=0}}},
  camera={eye={0,1.5,10},focus={0,1,0},projection=Renderer.perspective(math.rad(45),1.5,1,320)},
  scene={actors={player={renderer={model=model}},enemy={renderer={model=model}}}}}
for _,side in ipairs({'player','enemy'})do
  local allocations,releases=0,0
  local preview=Preview.new({rom=rom,releaseModel=function()end,importer={newRendererFromModel=function(m)
    local renderer=assert(Renderer.new(m,{flipY=false}))
    if m.file=='stadium2-lifecycle-beam' then
      allocations=allocations+1
      assert(#m.prims==8 and #m.textures==4)
      local release=renderer.release
      renderer.release=function(self)releases=releases+1;return release(self)end
    end
    renderer.drawScene=function()return true end
    return renderer
  end}})
  local effect=assert(preview:start(131,side,false,scene))
  for _=1,22 do preview:step()end
  assert(preview:draw(scene).drawn>=1 and allocations==1)
  for _,d in ipairs(preview.diagnostics)do
    assert(d.code~='unsupported-lifecycle-callback' and d.code~='lifecycle-model-unresolved'
      and d.code~='unresolved-spike-cannon-model' and d.code~='draw-renderer',d.message)
  end
  assert(preview.player:finish(effect))
  for _=1,60 do preview:step()end
  preview:draw(scene);preview:release()
  assert(releases==1)
end
print('Family 16 viewer: Spike Cannon on both sides, persistent mesh and disposal passed')
