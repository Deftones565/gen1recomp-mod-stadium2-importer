package.path='./?.lua;./?/init.lua;'..package.path
local Mat=require('mods.STADIUM2_IMPORTER.lib.renderer')
local S=require('mods.STADIUM2_IMPORTER.lib.battle_torch_shadows')
local function reference(vp,model,bounds,margin)
 local padded=vp
 if margin then
  padded={}
  for i,n in ipairs(vp) do padded[i]=i<=8 and n/margin or n end
 end
 local m=Mat.matMul(padded,model)
 local outside={true,true,true,true,true,true}
 for _,x in ipairs({bounds.minX,bounds.maxX}) do
  for _,y in ipairs({bounds.minY,bounds.maxY}) do
   for _,z in ipairs({bounds.minZ,bounds.maxZ}) do
    local c={}
    for row=1,4 do local i=(row-1)*4;c[row]=m[i+1]*x+m[i+2]*y+m[i+3]*z+m[i+4] end
    for axis=1,3 do
     outside[axis*2-1]=outside[axis*2-1] and c[axis]<-c[4]
     outside[axis*2]=outside[axis*2] and c[axis]>c[4]
    end
   end
  end
 end
 for _,v in ipairs(outside) do if v then return false end end
 return true
end
local bounds={minX=-2,maxX=2,minY=-1,maxY=4,minZ=-3,maxZ=3}
local vp=Mat.matMul(Mat.perspective(math.rad(60),16/9,.1,400),Mat.lookAt(40,20,50,0,0,0))
local model=Mat.identity()
for i=1,4000 do
 local a=i*.731;local c,s=math.cos(a),math.sin(a)
 model[1],model[3],model[9],model[11]=c*2,s*2,-s*2,c*2
 model[4],model[8],model[12]=math.sin(i*7)*120,math.cos(i*3)*70,math.cos(i*11)*120
 for _,margin in ipairs({1,1.1}) do
  assert(S.visibleInFace(vp,model,bounds,margin)==reference(vp,model,bounds,margin),'visibility changed')
 end
end
-- Disable trace allocation elision to measure actual Lua table churn on the
-- interpreter as well as devices where these paths fail to stay on trace.
if jit then jit.off(reference,true);jit.off(S.visibleInFace,true) end
local function allocated(fn)
 collectgarbage('collect');collectgarbage('stop')
 local before=collectgarbage('count')
 for i=1,10000 do fn(vp,model,bounds) end
 local delta=collectgarbage('count')-before
 collectgarbage('restart')
 return delta
end
local before,after=allocated(reference),allocated(S.visibleInFace)
assert(after<16 and after<before*.01,'visibility still allocates temporary tables')
print(string.format('10,000 visibility checks: %.1f KiB before, %.1f KiB after; 8,000 reference comparisons passed',before,after))
local r=setmetatable({parts={{rows={{-2,0,3},{4,5,-1}},used={true,true},visible={true,true}}}},Mat)
local out={};assert(r:poseBounds(out)==out and out.minX==-2 and out.maxY==5)
local snapshot=r:poseBounds();r.parts={};r:poseBounds(out)
assert(out.minX==-.5 and out.radius==1 and snapshot.minX==-2,'bounds reuse mutated a public snapshot')
r.bindBounds=out;r.model={height=10,floor=1}
local metrics={};assert(r:worldMetrics(metrics)==metrics and metrics.height==10)
local normal={};assert(Mat.normalMatrix(.3,.2,false,normal)==normal)
local fresh=Mat.normalMatrix(.3,.2,false)
for i=1,9 do assert(normal[i]==fresh[i]) end
print('Reusable bounds, metrics and normal matrices preserve caller-owned snapshots')
