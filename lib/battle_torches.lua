-- Wooden torch fire uses the Charmander-family's actual shared Stadium flame
-- geometry, eight cached IA8 images, and frame-dependent material colours.
local Flame=require("mods.STADIUM2_IMPORTER.lib.render_callbacks.flame")
local Pack=require("mods.STADIUM2_IMPORTER.lib.pack")
local Importer=require("mods.STADIUM2_IMPORTER.lib.importer")
local Torches={positions={{-48,7,-35},{44,6,53}}}
local textures,mesh,shader,failed
function Torches.time() return love and love.timer and love.timer.getTime() or 0 end
function Torches.flicker(t) return .92+.05*math.sin(t*9.7)+.03*math.sin(t*17.3) end
local function ensure(g)
 if failed then return false end
 if textures then return true end
 local model,err=Importer.loadModel(4,"normal")
 if not model then failed=true;Torches.error=err;return false end
 local prim
 for _,p in ipairs(model.prims or {}) do if p.effect=="fire" and p.fxFrames and #p.fxFrames>0 then prim=p;break end end
 if not prim then failed=true;Torches.error="Charmander flame frames missing from cache";return false end
 textures={}
 for i,index in ipairs(prim.fxFrames) do
  local slot=model.textures[index]
  local owned={textures={{w=slot.w,h=slot.h,rgba=slot.rgba}}}
  textures[i]=assert(Pack.image(owned,1))
  textures[i]:setFilter("linear","linear")
 end
 local geo=Flame.geometry(0);local vertices={}
 for i=1,geo.nverts do vertices[i]={0,0,0,geo.uv[i*2-1],geo.uv[i*2],
  geo.color[i*4-3]/255,geo.color[i*4-2]/255,geo.color[i*4-1]/255,1} end
 mesh=g.newMesh({{"VertexPosition","float",3},{"VertexTexCoord","float",2},{"VertexColor","float",4}},vertices,"triangles","stream")
 mesh:setVertexMap(geo.idx)
 shader=g.newShader([[
 #ifdef VERTEX
 uniform mat4 vp;
 vec4 position(mat4 tp,vec4 p){return vp*p;}
 #endif
 #ifdef PIXEL
 uniform vec3 fireEnvironment;uniform vec3 firePrimitive;
 vec4 effect(vec4 color,Image tex,vec2 uv,vec2 px){
  vec4 t=Texel(tex,uv);if(t.a<.01)discard;
  return vec4(mix(fireEnvironment,firePrimitive,t.r)*color.rgb,t.a*color.a);
 }
 #endif
 ]])
 return true
end
function Torches.draw(g,frame)
 if not ensure(g) then return false end
 local geo=Flame.geometry(0);local time=Torches.time()
 g.setDepthMode("lequal",false);g.setMeshCullMode("none")
 g.setBlendMode("alpha","alphamultiply");g.setShader(shader)
 shader:send("vp","row",frame.vp);g.setColor(1,1,1,1)
 local right={frame.view[1],frame.view[2],frame.view[3]}
 for j,p in ipairs(Torches.positions) do
  local tick=math.floor(time*30+j*2);local mat=Flame.material(4,tick)
  shader:send("fireEnvironment",{mat.environmentColor[1],mat.environmentColor[2],mat.environmentColor[3]})
  shader:send("firePrimitive",{mat.primitiveColor[1],mat.primitiveColor[2],mat.primitiveColor[3]})
  local scale=.027*Torches.flicker(time+j)
  for i=1,geo.nverts do
   local x,y=geo.pos[i*3-2]*scale,geo.pos[i*3-1]*scale
   mesh:setVertex(i,{p[1]+right[1]*x,p[2]+y,p[3]+right[3]*x,
    geo.uv[i*2-1],geo.uv[i*2],1,1,geo.color[i*4-1]/255,1})
  end
  mesh:setTexture(textures[tick%#textures+1]);g.draw(mesh)
 end
 g.setShader()
 return true
end
function Torches.release()
 for _,t in ipairs(textures or {}) do if t then t:release() end end
 if mesh then mesh:release() end
 if shader then shader:release() end
 textures,mesh,shader,failed=nil,nil,nil,nil
 Torches.error=nil
end
return Torches
