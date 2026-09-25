return function()
 local root='mods.STADIUM2_IMPORTER.lib.'
 local S=require(root..'battle_torch_shadows');S.release()
 local T=require(root..'battle_torches');local P=require(root..'torch_projection')
 local vertices={};local p=T.positions[1]
 local indices={{1,2,3,1,3,4},{5,8,7,5,7,6},{1,5,6,1,6,2},{2,6,7,2,7,3},{3,7,8,3,8,4},{4,8,5,4,5,1}}
 for _,basis in ipairs(P.faces) do
  local x,y,z=p[1]+basis.f[1]*8,p[2]+1+basis.f[2]*8,p[3]+basis.f[3]*8
  local points={{x-1,y-1,z-1},{x+1,y-1,z-1},{x+1,y+1,z-1},{x-1,y+1,z-1},{x-1,y-1,z+1},{x+1,y-1,z+1},{x+1,y+1,z+1},{x-1,y+1,z+1}}
  for _,face in ipairs(indices) do for _,i in ipairs(face) do local v=points[i];vertices[#vertices+1]={v[1],v[2],v[3],0,0,0,0,0,0,1} end end
 end
 local format={{'VertexPosition','float',3},{'SurfaceNormal','float',3},{'SurfaceColor','float',3},{'SurfaceMaterial','float',1}}
 local maps=assert(S.update(love.graphics,vertices,format,{},{},{}),S.error)
 local img=maps[1].map:newImageData()
 -- Atlas stays local to this isolated GPU test.
 for face=1,6 do
  local r,g=img:getPixel(((face-1)%3)*256+128,math.floor((face-1)/3)*256+128)
  print('CUBE FACE',face,r+g/255)
  assert(math.abs(r+g/255-.07)<.003,'cube atlas depth incorrect')
 end
 local receiver=love.graphics.newShader(P.source..[[
 uniform vec3 ray;uniform Image depthAtlas;
 vec4 effect(vec4 c,Image t,vec2 uv,vec2 px){
  float v=torchVisibility(depthAtlas,vec3(0.),ray,-normalize(ray));return vec4(v,v,v,1.);
 }]])
 local target=love.graphics.newCanvas(1,1)
 receiver:send('depthAtlas',maps[1].map)
 for _,basis in ipairs(P.faces) do
  for _,case in ipairs({{12,.5,0},{6,.25,1},{8,3,1}}) do
   local ray={}
   for k=1,3 do ray[k]=basis.f[k]*case[1]+basis.r[k]*case[2] end
   receiver:send('ray',ray)
   love.graphics.setCanvas(target);love.graphics.setShader(receiver)
   love.graphics.setDepthMode('always',false);love.graphics.setColor(1,1,1,1)
   love.graphics.rectangle('fill',0,0,1,1);love.graphics.setCanvas();love.graphics.setShader()
   local v=target:newImageData():getPixel(0,0)
   assert(math.abs(v-case[3])<.1,'receiver shadow comparison incorrect')
  end
 end
 receiver:release();target:release()
 S.release();print('Six-direction GPU occluder depth and lit/shadowed receivers passed')
end
