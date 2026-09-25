package.path='./?.lua;./?/init.lua;'..package.path
local F=require('mods.STADIUM2_IMPORTER.lib.battle_fireflies')
local Mat=require('mods.STADIUM2_IMPORTER.lib.renderer')
math.randomseed(98);local expected=math.random();math.randomseed(98)
local sent={};local shader={release=function() end,hasUniform=function() return true end,send=function(_,k,v) sent[k]=v end}
F.update({daytime='DAY'},5);F.bindLighting(shader);assert(sent.fireflyEnabled==0)
for i=1,4 do assert(F.lights[i][4]==0) end
F.update({daytime='NITE'},5);F.bindLighting(shader);assert(sent.fireflyEnabled==1)
for i=1,4 do
 local p=F.pose(i,5)
 for k=1,3 do assert(F.lights[i][k]==p[k]) end
 assert(F.lights[i][4]>0 and F.lights[i][4]<=.18)
end
assert(math.random()==expected,'fireflies consumed gameplay RNG')
for i=1,F.count do
 for t=0,100,5 do
  local a,b=F.pose(i,t),F.pose(i,t+.016)
  for k=1,3 do assert(math.abs(a[k]-b[k])<.04,'firefly jumped') end
 end
end
local created,draws=0,0
local mesh={setVertices=function(_,rows) assert(#rows==96) end,release=function() end}
local g={newMesh=function() created=created+1;return mesh end,newShader=function() created=created+1;return shader end,
 push=function() end,pop=function() end,setShader=function() end,setColor=function() end,setMeshCullMode=function() end,
 setDepthMode=function(mode,write) assert(mode=='lequal' and not write) end,setBlendMode=function() end,draw=function() draws=draws+1 end}
local frame={view=Mat.identity(),vp=Mat.identity()}
F.draw(g,frame);F.draw(g,frame);assert(created==2 and draws==2)
F.update({daytime='DAY'},10);F.draw(g,frame);assert(draws==2 and created==2)
F.reset();F.bindLighting(shader);assert(sent.fireflyEnabled==0)
F.release()
print('Firefly continuous motion, bounded lights, RNG isolation, day/night gating, depth and GPU reuse passed')
