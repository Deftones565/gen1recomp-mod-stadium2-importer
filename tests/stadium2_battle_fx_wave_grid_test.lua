local Grid=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_wave_grid")
local Lifecycle=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_lifecycle")
for _,family in ipairs({9,10,11}) do
  local s=Grid.new(family)
  assert(#s.vertices==256 and s.vertices[1][1]==-54 and s.vertices[1][3]==-42)
  assert(s.vertices[256][1]==47.25 and s.vertices[256][3]==36.75)
  for _=1,20 do assert(Grid.step(s,0)==0) end
  assert(s.alpha==(family~=11 and 128 or 80))
  assert(s.vertices[137][2]~=1,"authored displacement must advance")
  local snap=Grid.snapshot(s);snap.positions[1]=99
  assert(s.vertices[1][1]==-54,"snapshot must be isolated")
  assert(Grid.step(s,1)==0 and s.counter==0 and s.duration==25)
  for _=1,15 do Grid.step(s,1) end
  assert(s.counter==15 and s.alpha==(family~=11 and 128 or 80),"held signal must not restart")
  Grid.step(s,0)
  assert(s.alpha==(family~=11 and 116 or 72),"fade begins at finish tick16")
  for _=17,25 do assert(Grid.step(s,0)==0) end
  assert(s.alpha==(family~=11 and 8 or 0))
  assert(Grid.step(s,0)==-1 and not s.active)
  assert(Grid.step(s,1)==-1,"finish cannot revive an expired grid")
end
local s=Grid.new(9)
for _=1,1800 do assert(Grid.step(s,0)==0) end
assert(Grid.step(s,0)==-1,"unsignalled native duration is1800, not25")
local m=Lifecycle.new();m:spawn(9);m:spawn(11);m:step(13)
local snapshot=m:snapshot()
assert(snapshot.instances[1].nativeState.alpha==128)
assert(snapshot.instances[2].nativeState.alpha==80)
assert(#snapshot.diagnostics==0,"wave-grid callbacks are implemented")
assert(#snapshot.packets[1].geometry.idx==1350)
m:setNativeSignal(1);m:step(27)
assert(#m:snapshot().packets==0)
local f=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_float")
local Random=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_random")
local draws=0
local ripple=Grid.new(10,{next=function()draws=draws+1;return 8 end})
assert(draws==20,"ten disturbances consume exactly twenty RNG calls")
local phase=0
for _=1,11 do phase=f(phase+1.5707963705062866) end
assert(ripple.vertices[137][4]==phase,"fixed center plus ten injected center disturbances")
local initialY=ripple.vertices[137][2]
Grid.step(ripple,0)
assert(ripple.vertices[137][2]==initialY,"first update samples the old phase")
assert(ripple.vertices[137][4]==f(phase+.1))
local saved=Grid.snapshot(ripple);saved.phases[137]=99
assert(ripple.vertices[137][4]~=99)
local a,b=Grid.new(10,Random.new(123)),Grid.new(10,Random.new(123))
for i=1,256 do assert(a.vertices[i][4]==b.vertices[i][4]) end
local manager=Lifecycle.new({random={next=function()draws=draws+1;return 3 end}})
manager:spawn(10);assert(draws==40)
manager:step(2);manager:snapshot();manager:draw();assert(draws==40,"update/draw must not consume RNG")
print("wave grid: three families, deterministic disturbances, fade and expiry passed")
local file=io.open(os.getenv("STADIUM2_ROM") or "mods/STADIUM2_IMPORTER/baseroms/stadium2.z64","rb")
if not file then
  assert(os.getenv("STADIUM2_REQUIRE_ROM")~="1","required ROM unavailable")
  print("SKIP wave-grid ROM checks");return
end
local rom=file:read("*a");file:close()
local Rom=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_rom")
local Resources=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_resources")
local Runtime=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_runtime")
local c=assert(Rom.catalog(rom))
assert(Rom.read32(rom,0x84157ECC)==0x24040708)
assert(Rom.read32(rom,0x84158014)==0x24040708)
for _,id in ipairs({95,103,173,45,48,134,47,195})do
  local rt=Runtime.new({catalog=c});rt:trigger({moveId=id});rt:step(1)
  assert(rt:snapshot().lifecycles.instances[1].nativeState)
  local resolved=assert(Resources.resolve(rom,c.moves[id].resources))
  local family=rt:snapshot().lifecycles.instances[1].familyId
  local texture=assert(Resources.waveGridTexture(resolved,family))
  assert(#texture.rgba==4096 and texture.symbol==(family~=9 and 36 or 38))
  assert(texture.resourceId==((id==173 or id==195) and 96 or 25))
  local binding=resolved.shapes[texture.symbol]
  local a,b=binding.module:byte(binding.export.offset+1,binding.export.offset+2)
  local red=math.floor((a*256+b)/2048)
  assert(texture.rgba:byte(1)==red*8+math.floor(red/4),"RGBA16 replicates high bits")
  rt:release()
end
assert(not Resources.waveGridTexture({shapes={}}))
assert(Rom.read32(rom,0x841610C0)==0x8F18CAB0,"family10 loads texture export36")
assert(Rom.read32(rom,0x84187784)==0x0C184240,"family10 material disables depth compare/write")
print("wave grid ROM: eight routes, init durations and texture ownership passed")
local Player=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_player")
local Renderer=require("mods.STADIUM2_IMPORTER.lib.renderer")
local Adapter=require("mods.STADIUM2_IMPORTER.lib.stadium2_battle_fx_battle_adapter")
local scene={camera={eye={0,0,10},focus={0,0,0},fovDegrees=30},world={origin={0,0,0}}}
assert(not Grid.matrix({eye={0,0,0},focus={0,0,0}},.05))
local matrix=assert(Grid.matrix(scene.camera,.05))
assert(matrix[4]==0 and matrix[8]==0 and matrix[12]==-5.25)
for _,id in ipairs({95,45,47,195}) do
  local allocations,draws,uploads,releases=0,0,0,0
  local player=Player.new({catalog=c,contextForParticle=Adapter.placementContext,
    loadWaveGridTexture=function(move,family)
      return Resources.waveGridTexture(assert(Resources.resolve(rom,c.moves[move].resources)),family)
    end,
    createGeometryRenderer=function(model)
      allocations=allocations+1
      local renderer=assert(Renderer.new(model,{flipY=false}))
      local update=renderer.updatePose
      renderer.updatePose=function(self,force)uploads=uploads+1;return update(self,force)end
      renderer.drawScene=function(self,pass,mm,options)
        assert(options.screenSpace and mm[12]==-5.25)
        assert(options.normalMatrix[6]==.05)
        assert(#self.parts[1].rows==256 and #model.prims[1].idx==1350)
        assert(self.parts[1].rows[1][12]==model.prims[1].color[4]/255)
        draws=draws+1;return true
      end
      return renderer
    end,
    releaseRenderer=function(renderer)releases=releases+1;renderer:release()end})
  player:trigger({moveId=id});player.runtime:step(1)
  local result=player:draw(scene)
  assert(result.drawn>=1 and draws==2 and allocations==1)
  local before=uploads;player:draw(scene)
  assert(uploads==before and allocations==1,"same frame reuses mesh")
  player.runtime:step(1);player:draw(scene)
  assert(uploads>before and allocations==1,"next frame uploads normals and alpha")
  player.runtime.lifecycle:setNativeSignal(1);player.runtime:step(27);player:draw(scene)
  assert(releases==1);player:release();assert(releases==1)
end
print("wave grid renderer: three families, depth, camera, alpha, reuse and disposal passed")
