-- Run from the game root; set STADIUM2_PACK_DIR to an imported normal-pack directory.
package.path=love.filesystem.getWorkingDirectory()..'/?.lua;'..package.path
function love.load()
 local ok,err=pcall(function()
 local P=require('mods.STADIUM2_IMPORTER.lib.pack')
 local R=require('mods.STADIUM2_IMPORTER.lib.renderer')
 local L=require('mods.STADIUM2_IMPORTER.lib.visitor_locomotion')
 local B=require('mods.STADIUM2_IMPORTER.lib.visitor_behaviour')
 local C=require('mods.STADIUM2_IMPORTER.lib.visitor_catalog')
 local A=require('mods.STADIUM2_IMPORTER.lib.battle_actor')
 local N=require('mods.STADIUM2_IMPORTER.lib.visitor_navigation')
 local seed=912;local function random() seed=seed*16807%2147483647;return seed/2147483647 end
 for _,pair in ipairs({{'grass','nature','pikachu'},{'town','town','meowth'},{'town','town','eevee'},{'grass','nature','weedle'},{'grass','nature','oddish'},{'town','town','growlithe'},{'cave','cave','zubat'},{'freshwater','freshwater','yanma'}}) do
  require('mods.STADIUM2_IMPORTER.lib.battle_'..pair[2]).vertices()
  local spec=C[pair[3]]
  local f=assert(io.open(string.format('%s/%03d.dsm',assert(os.getenv('STADIUM2_PACK_DIR'),'set STADIUM2_PACK_DIR'),spec[1]),'rb'))
  local bytes=f:read('*a');f:close()
  if bytes:sub(1,4)~='DSM4' and bytes:sub(1,4)~='DSM5' then bytes=love.data.decompress('string','lz4',bytes:sub(9)) end
  local model=assert(P.parse(bytes));local r=assert(R.new(model,{flipY=false,anchorTravel=true}))
  local actor=A.new('visitor');actor.renderer=r;actor.dex=spec[1];actor:play('idle',true)
  local v={name=pair[3],actor=actor,age=0}
  assert(B.start(v,pair[1],random),'no safe spawn for '..v.name)
  assert(B.validate(v,pair[1]))
  L.attach(v)
  local travelled=0
  for i=1,1200 do
   v.age=v.age+.05;v.moved=0
   if B.validate(v,pair[1]) then B.update(v,.05,pair[1],{v}) end
   L.advance(v,v.moved,.05);actor:update(.05);B.validate(v,pair[1])
   travelled=travelled+v.moved
   assert(N.free(N.maps[pair[1]],v.x,v.y,v.z,v.radius,v.bodyHeight),'blocked visitor')
  end
  assert(travelled>2,v.name..' never progressed')
  print(v.name..': real model gait/collision passed (60 seconds), travelled '..math.floor(travelled)..' units, '..v.goalCount..' goals')
  actor:release()
 end
 end)
 if not ok then print(err) end
 love.event.quit(ok and 0 or 1)
end
