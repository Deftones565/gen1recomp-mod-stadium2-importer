package.path='./?.lua;./?/init.lua;'..package.path
local root='mods.STADIUM2_IMPORTER.lib.'
local S=require(root..'battle_torch_shadows')
local T=require(root..'battle_torches')
local P=require(root..'torch_projection')
-- Every cube face covers its forward hemisphere; both opposite directions and
-- directions above/below the flame have valid depth, with consistent UV axes.
for _,p in ipairs(T.positions) do
 for face,basis in ipairs(P.faces) do
  local vp=S.frame(p,face)
  local function project(v)
   local c={}
   for row=1,4 do c[row]=0;for col=1,4 do c[row]=c[row]+vp[(row-1)*4+col]*v[col] end end
   return c[1]/c[4],c[2]/c[4],c[3]/c[4]
  end
  for _,distance in ipairs({2,20,80}) do
   local v={p[1],p[2]+1,p[3],1}
   for k=1,3 do v[k]=v[k]+distance*(basis.f[k]+.25*basis.r[k]-.4*basis.u[k]) end
   local x,y,z=project(v)
   assert(math.abs(x-.25)<1e-6 and math.abs(y+.4)<1e-6 and z>-1 and z<1,
    'cube face has inconsistent projection or missing directional coverage')
  end
 end
end
-- Current bounds cross face seams conservatively, while opposite faces cull.
local Mat=require(root..'renderer')
local p0=T.positions[1]
local bounds={minX=p0[1]+7,maxX=p0[1]+9,minY=p0[2],maxY=p0[2]+2,minZ=p0[3]-1,maxZ=p0[3]+1}
assert(S.visibleInFace(S.frame(p0,1),Mat.identity(),bounds))
assert(not S.visibleInFace(S.frame(p0,2),Mat.identity(),bounds))
local seam={minX=p0[1]+7,maxX=p0[1]+9,minY=p0[2],maxY=p0[2]+2,minZ=p0[3]+7,maxZ=p0[3]+9}
assert(S.visibleInFace(S.frame(p0,1),Mat.identity(),seam))
assert(S.visibleInFace(S.frame(p0,5),Mat.identity(),seam))
local p=T.positions[1]
local now,draws,allocations,pushes=0,0,0,0
local oldTime=T.time;T.time=function() return now end
local resource=function() return {setFilter=function() end,release=function() end,send=function() end} end
local width=1280
local g={getDimensions=function() return width,720 end,push=function() pushes=pushes+1 end,pop=function() pushes=pushes-1 end,
 newShader=resource,newMesh=resource,newCanvas=function() allocations=allocations+1;return resource() end,
 origin=function() end,setScissor=function() end,setCanvas=function() end,clear=function() end,setDepthMode=function() end,setMeshCullMode=function() end,
 setBlendMode=function() end,setShader=function() end,setColor=function() end,draw=function() draws=draws+1 end}
local vertices={}
for i=1,3 do vertices[i]={p[1],0,p[3],0,0,0,0,0,0,1} end
assert(S.update(g,vertices,{}, {},{},{}))
assert(draws==18 and allocations==15 and pushes==0)
now=.01;S.update(g,vertices,{}, {},{},{});assert(draws==18,'shadow refresh exceeded 20Hz')
now=.06;S.update(g,vertices,{}, {},{},{});assert(draws==18 and allocations==15,'shadow targets not reused')
width=720;now=.07;S.update(g,{}, {}, {},{},{});assert(draws==36,'resize must rebuild cleared static maps')
local actorPasses=0
local actor={renderer={drawShadowMap=function() actorPasses=actorPasses+1;return true end}}
now=.13;S.update(g,{}, {},{player=actor},{player={Mat.identity()}},{player='host'})
assert(actorPasses==12)
local prior=draws
S.resetDynamic()
now=.131;S.update(g,{}, {},{},{},{})
assert(draws==prior+12 and allocations==15,'next battle must erase old actors without reallocating the forest')
S.release()
g.newCanvas=function() error('allocation failed') end
assert(S.update(g,vertices,{}, {},{},{})==nil and S.error and pushes==0,'failure leaked graphics state')
S.release();T.time=oldTime
print('360-degree cube projection, static cache, refresh limit and failure recovery passed')
