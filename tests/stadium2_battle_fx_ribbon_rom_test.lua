local Rom=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_rom")
local Player=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_player")
local Adapter=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_battle_adapter")
local Renderer=require("mods.STADIUM2_IMPORTER.lib.renderer")
local file=io.open(os.getenv("STADIUM2_ROM") or "mods/STADIUM2_IMPORTER/baseroms/stadium2.z64","rb")
if not file then
  assert(os.getenv("STADIUM2_REQUIRE_ROM")~="1","required ROM unavailable")
  print("SKIP: ribbon ROM unavailable");return
end
local rom=file:read("*a");file:close()
local catalog=assert(Rom.catalog(rom))
assert(Rom.read32(rom,0x841874E8)==0xFD700000,"ribbon texture format is IA8")
local asset=catalog.lifecycleAssets.ribbon
assert(#asset.rgba==512)
for i=0,127 do
  local value=rom:byte(Rom.romOffset(0x84187418)+i+1)
  assert(asset.rgba:byte(i*4+1)==math.floor(value/16)*17)
  assert(asset.rgba:byte(i*4+4)==value%16*17)
end
local allocations,updates,draws,releases=0,0,0,0
local scene={world={actorSlots={player={2,0,3},enemy={-2,0,-3}}}}
local player=Player.new({catalog=catalog,
  contextForParticle=Adapter.placementContext,
  createGeometryRenderer=function(model)
    allocations=allocations+1
    local renderer=assert(Renderer.new(model,{flipY=false}))
    assert(renderer:currentTexture(model.prims[1])==1)
    assert(model.prims[1].additive==false)
    local update=renderer.updatePose
    renderer.updatePose=function(self,force)updates=updates+1;return update(self,force)end
    renderer.drawScene=function(self,pass,matrix,options)
      assert(matrix[1]==.05 and matrix[4]==2 and matrix[12]==3)
      assert(options.battleFxColors.primaryColor[4]==200)
      assert(#self.parts[1].rows==400 and #self.parts[1].prim.idx>0)
      draws=draws+1;return true
    end
    return renderer
  end,
  releaseRenderer=function(renderer)releases=releases+1;renderer:release()end})
assert(player:trigger({moveId=20,alternate=true,sourceSide="player",targetSide="enemy"}))
player.runtime:step(1)
local built=player:draw(scene)
assert(#built.lifecyclePackets==1 and allocations==1 and draws==2)
local before=updates
player:draw(scene)
assert(allocations==1 and updates==before,"repeated draw must reuse the mesh")
player.runtime:step(1);player:draw(scene)
assert(allocations==1 and updates>before,"next tick updates the existing mesh")
player.runtime:step(289);player:draw(scene)
assert(releases==1,"expired lifecycle releases its mesh")
player:release()
assert(releases==1,"release must not double free the mesh")
for _,id in ipairs({20,35,50,81,132}) do
  local p=Player.new({catalog=catalog})
  assert(p:trigger({moveId=id,alternate=true}));p.runtime:step(1)
  local packets=p:packets(scene)
  assert(#packets.lifecyclePackets==1,"retail move must dispatch a ribbon")
  for _,d in ipairs(packets.diagnostics) do
    assert(d.code~="unsupported-lifecycle-callback" and d.code~="lifecycle-model-unresolved")
  end
  p:release()
end
print("ROM ribbon: texture, five move routes, persistent renderer and expiry passed")
